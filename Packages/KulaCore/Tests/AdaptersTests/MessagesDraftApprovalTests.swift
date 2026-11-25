import Testing
import Foundation
import os
import Contracts
import LocalStore
import ToolService
@testable import Adapters

/// Uses the production definition and recipient validation without opening Messages or changing the clipboard.
private final class DraftProbe: ToolAdapter, Sendable {
    let tool = MessagesDraftTool(ContactsBridge())
    let calls = OSAllocatedUnfairLock(initialState: 0)
    var definition: ToolDefinition { tool.definition }
    var count: Int { calls.withLock { $0 } }

    func preview(_ arguments: JSONValue) async throws -> ConfirmationPreview {
        try await tool.preview(arguments)
    }

    func execute(_ arguments: JSONValue) async throws -> AdapterOutput {
        calls.withLock { $0 += 1 }
        return AdapterOutput(output: ["sent": false])
    }
}

@Suite struct MessagesDraftApprovalTests {
    private let arguments: JSONValue = ["handle": "+1 202-555-0100", "body": "你好"]

    private func service(presenter: @escaping ConfirmationPresenter,
                         mode: ApprovalMode = .autoReview) throws -> ToolService {
        let store = try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory)
        let instance = MCPInstance(id: "draft-test", name: "Test", enabled: true,
                                   readOnly: false, sources: [.messages])
        return ToolService(store: store, policy: {
            PolicySnapshot(enabledSources: [.messages], mcpInstances: [instance.id: instance], approvalMode: mode)
        }, presenter: presenter)
    }

    @Test(arguments: [CallerOrigin.agent(sessionID: "draft-test"), .launcher])
    func explicitDraftDoesNotAskAgain(origin: CallerOrigin) async throws {
        let svc = try service(presenter: { _ in
            Issue.record("An explicit draft request must not show a confirmation")
            return .rejected
        })
        let probe = DraftProbe()
        await svc.register(probe)
        let result = await svc.submit(ActionRequest(tool: probe.definition.name, arguments: arguments,
                                                    origin: origin, intent: .explicitRequest))
        #expect(result.status == .completed)
        #expect(result.output?["sent"] == false)
        #expect(probe.count == 1)
    }

    @Test(arguments: [ApprovalMode.autoReview, .fullAccess])
    func externalDraftStillRequiresConfirmation(mode: ApprovalMode) async throws {
        let confirmations = OSAllocatedUnfairLock(initialState: 0)
        let svc = try service(presenter: { request in
            confirmations.withLock { $0 += 1 }
            #expect(request.tool == "messages_prepare_draft")
            #expect(request.changes == ["草稿：你好"])
            return .rejected
        }, mode: mode)
        let probe = DraftProbe()
        await svc.register(probe)
        let result = await svc.submit(ActionRequest(tool: probe.definition.name, arguments: arguments,
                                                    origin: .mcp(instanceID: "draft-test"), intent: .explicitRequest))
        #expect(result.status == .rejected)
        #expect(confirmations.withLock { $0 } == 1)
        #expect(probe.count == 0)
    }

    @Test func suggestedDraftDoesNotExecute() async throws {
        let svc = try service(presenter: { _ in
            Issue.record("An unsolicited draft should remain a suggestion")
            return .rejected
        })
        let probe = DraftProbe()
        await svc.register(probe)
        let result = await svc.submit(ActionRequest(tool: probe.definition.name, arguments: arguments,
                                                    origin: .agent(sessionID: "draft-test"), intent: .aiSuggested))
        #expect(result.status == .suggestion)
        #expect(probe.count == 0)
    }

    @Test(arguments: [["body": "你好"] as JSONValue, ["handle": "invalid", "body": "你好"],
                      ["handle": "+1 202-555-0100", "body": " "]])
    func invalidDraftDoesNotExecute(arguments: JSONValue) async throws {
        let svc = try service(presenter: { _ in
            Issue.record("Invalid drafts should fail validation before confirmation")
            return .rejected
        })
        let probe = DraftProbe()
        await svc.register(probe)
        let result = await svc.submit(ActionRequest(tool: probe.definition.name, arguments: arguments,
                                                    origin: .agent(sessionID: "draft-test"), intent: .explicitRequest))
        #expect(result.error?.code == .invalidArguments)
        #expect(probe.count == 0)
    }

    @Test func agentDraftPreparesCardWithoutOpeningMessages() async throws {
        let handoffCalls = OSAllocatedUnfairLock(initialState: 0)
        let tool = MessagesDraftTool(ContactsBridge(), handoff: { _, _ in
            handoffCalls.withLock { $0 += 1 }
            return true
        })
        let svc = try service(presenter: { _ in
            Issue.record("An explicit agent draft request must not ask for confirmation")
            return .rejected
        })
        await svc.register(tool)

        let result = await svc.submit(ActionRequest(tool: tool.definition.name, arguments: arguments,
                                                    origin: .agent(sessionID: "draft-agent"), intent: .explicitRequest))
        #expect(result.status == .completed)
        #expect(handoffCalls.withLock { $0 } == 0)
        #expect(result.output?["opened"] == false)
        #expect(result.output?["copiedToClipboard"] == false)
        #expect(result.output?["sent"] == false)
        #expect(result.output?["handle"] == "+1 202-555-0100")
        #expect(result.output?["body"] == "你好")

        let card = ToolResultCard.from(tool: tool.definition.name, arguments: arguments, result: result)
        #expect(card?.kind == .messagesDraft)
        #expect(card?.action?.kind == .openMessagesDraft)
        #expect(card?.action?.target == "+1 202-555-0100")
        #expect(card?.action?.detail == "你好")
    }

    @Test func approvedMCPDraftHandsOffToMessages() async throws {
        let recorded = OSAllocatedUnfairLock(initialState: [(URL, String)]())
        let tool = MessagesDraftTool(ContactsBridge(), handoff: { url, body in
            recorded.withLock { $0.append((url, body)) }
            return true
        })
        let svc = try service(presenter: { _ in .approved })
        await svc.register(tool)

        let result = await svc.submit(ActionRequest(tool: tool.definition.name, arguments: arguments,
                                                    origin: .mcp(instanceID: "draft-test"), intent: .explicitRequest))
        #expect(result.status == .completed)
        #expect(result.output?["opened"] == true)
        #expect(result.output?["copiedToClipboard"] == true)
        #expect(result.output?["sent"] == false)
        let calls = recorded.withLock { $0 }
        #expect(calls.count == 1)
        #expect(calls.first?.0 == MessagesDraftTool.draftURL(handle: "+1 202-555-0100", body: "你好"))
        #expect(calls.first?.1 == "你好")
    }

    @Test func launcherDraftHandsOffImmediately() async throws {
        let handoffCalls = OSAllocatedUnfairLock(initialState: 0)
        let tool = MessagesDraftTool(ContactsBridge(), handoff: { _, _ in
            handoffCalls.withLock { $0 += 1 }
            return true
        })
        let svc = try service(presenter: { _ in
            Issue.record("An explicit launcher draft request must not ask for confirmation")
            return .rejected
        })
        await svc.register(tool)

        let result = await svc.submit(ActionRequest(tool: tool.definition.name, arguments: arguments,
                                                    origin: .launcher, intent: .explicitRequest))
        #expect(result.status == .completed)
        #expect(result.output?["opened"] == true)
        #expect(handoffCalls.withLock { $0 } == 1)
    }
}
