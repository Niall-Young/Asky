import Testing
import Foundation
import os
import Contracts
import LocalStore
import ToolService
import Adapters

/// Exercises the real registered policies without reading or writing the user's system applications.
private final class NativeApprovalProbe: ToolAdapter, Sendable {
    let definition: ToolDefinition
    let executions = OSAllocatedUnfairLock(initialState: 0)
    init(_ definition: ToolDefinition) { self.definition = definition }
    var count: Int { executions.withLock { $0 } }
    func execute(_ arguments: JSONValue) async throws -> AdapterOutput {
        executions.withLock { $0 += 1 }
        return AdapterOutput(output: ["ok": true])
    }
}

@Suite(.serialized) struct NativeApprovalAuditTests {
    private static let definitions = NativeTools(notesFolders: { [] }).adapters(memory: nil).map(\.definition)
    private static let routineWrites = [
        "notes_create", "notes_append", "calendar_create_event", "calendar_update_event",
        "reminders_create", "messages_prepare_draft", "chrome_activate_tab"
    ]
    private static let confirmedWrites = ["calendar_delete_event", "shortcuts_run"]

    private func definition(_ name: String) throws -> ToolDefinition {
        try #require(Self.definitions.first { $0.name == name })
    }

    private func submit(_ definition: ToolDefinition, mode: ApprovalMode = .autoReview,
                        origin: CallerOrigin = .agent(sessionID: "approval-audit"),
                        intent: UserIntent = .explicitRequest,
                        enabled: Bool = true) async throws -> (ExecutionResult, Int, Int) {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let store = try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory)
        let instance = MCPInstance(id: "audit", name: "Audit", enabled: true, readOnly: false,
                                   sources: [definition.source])
        let service = ToolService(store: store, policy: {
            PolicySnapshot(enabledSources: enabled ? [definition.source] : [],
                           mcpInstances: [instance.id: instance], approvalMode: mode)
        }, presenter: { _ in calls.withLock { $0 += 1 }; return .rejected })
        let probe = NativeApprovalProbe(definition)
        await service.register(probe)
        let result = await service.submit(ActionRequest(tool: definition.name, arguments: [:],
                                                        origin: origin, intent: intent))
        return (result, calls.withLock { $0 }, probe.count)
    }

    @Test(arguments: routineWrites)
    func explicitRoutineWritesDoNotRepeatApproval(name: String) async throws {
        let (result, confirmations, executions) = try await submit(definition(name))
        #expect(result.status == .completed)
        #expect(confirmations == 0)
        #expect(executions == 1)
    }

    @Test(arguments: confirmedWrites)
    func autoReviewStillConfirmsDeletionAndShortcuts(name: String) async throws {
        let (result, confirmations, executions) = try await submit(definition(name))
        #expect(result.error?.code == .userRejected)
        #expect(confirmations == 1)
        #expect(executions == 0)
    }

    @Test(arguments: routineWrites + confirmedWrites)
    func fullAccessSkipsAgentApproval(name: String) async throws {
        let (result, confirmations, executions) = try await submit(definition(name), mode: .fullAccess)
        #expect(result.status == .completed)
        #expect(confirmations == 0)
        #expect(executions == 1)
    }

    @Test(arguments: routineWrites + ["calendar_delete_event"])
    func externalWritesStillConfirmInFullAccess(name: String) async throws {
        let (result, confirmations, executions) = try await submit(
            definition(name), mode: .fullAccess, origin: .mcp(instanceID: "audit"))
        #expect(result.error?.code == .userRejected)
        #expect(confirmations == 1)
        #expect(executions == 0)
    }

    @Test(arguments: ["notes_append", "calendar_update_event"])
    func suggestedChangesRemainSuggestions(name: String) async throws {
        let (result, confirmations, executions) = try await submit(definition(name), intent: .aiSuggested)
        #expect(result.status == .suggestion)
        #expect(confirmations == 0)
        #expect(executions == 0)
    }

    @Test(arguments: ["notes_append", "calendar_update_event"])
    func disabledSourceStillBlocksExplicitChanges(name: String) async throws {
        let (result, confirmations, executions) = try await submit(definition(name), enabled: false)
        #expect(result.error?.code == .sourceDisabled)
        #expect(confirmations == 0)
        #expect(executions == 0)
    }
}
