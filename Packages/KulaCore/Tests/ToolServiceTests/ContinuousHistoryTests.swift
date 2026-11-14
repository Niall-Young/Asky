import Foundation
import Testing
import Contracts
import LocalStore
@testable import ToolService

@Suite struct ContinuousHistoryTests {
    @Test func timelineAndClearPreserveMemory() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try LocalStore(root: root), history = ConversationStore(local)
        let now = Date()
        let a = try history.create(title: "a", now: now)
        let b = try history.create(title: "b", now: now)
        let first = try history.append(conversationID: a, role: "user", text: "first", now: now)
        let second = try history.append(conversationID: b, role: "user", text: "second", now: now.addingTimeInterval(1))
        #expect(history.timeline(limit: 1).first?.id == second.id)
        #expect(history.timeline(limit: 1, before: second).first?.id == first.id)
        let memory = root.appending(path: "Memory/MEMORY.md")
        try FileManager.default.createDirectory(at: memory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: memory)
        let tool = HistoryTool(store: local)
        #expect(try await tool.execute(["query": "first"]).output["messages"]?.arrayValue?.count == 1)
        let result = try await ConversationHistoryService(store: local).clear()
        #expect(result.deletedIDs == [a, b])
        #expect(history.timeline().isEmpty)
        #expect(history.search("first").isEmpty)
        #expect(try String(contentsOf: memory, encoding: .utf8) == "keep me")
    }

    @Test func legacyExpiryRemovesPrefixAndInvalidatesSnapshots() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try LocalStore(root: root), history = ConversationStore(local)
        let now = Date(), old = now.addingTimeInterval(-40 * 86400)
        let id = try history.create(title: "legacy", now: old)
        try history.append(conversationID: id, role: "user", text: "expired", now: old)
        try history.append(conversationID: id, role: "assistant", text: "expired reply", now: old.addingTimeInterval(1))
        try history.append(conversationID: id, role: "user", text: "recent", now: now)
        let storage = AgentSessionStorage(root: root.appending(path: "runtime"))
        let path = try await storage.save(sessionID: id, messages: [["role": "user", "content": "expired summary"]])
        try history.setRuntimeSession(id, ref: path)
        _ = try await ConversationHistoryService(store: local).cleanup(retention: .thirtyDays, now: now)
        #expect(history.messages(conversationID: id, limit: 20).map(\.text) == ["recent"])
        #expect(history.search("expired").isEmpty)
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(history.list(limit: 10).first?.runtimeSessionRef == nil)
    }

    @Test func deletingOneLegacyRoundKeepsOtherRounds() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try LocalStore(root: root), history = ConversationStore(local)
        let id = try history.create(title: "legacy")
        let first = try history.append(conversationID: id, role: "user", text: "remove this")
        try history.append(conversationID: id, role: "assistant", text: "old reply")
        try history.append(conversationID: id, role: "user", text: "keep this")
        let service = ConversationHistoryService(store: local)
        _ = try await service.deleteRound(first, protecting: [id])
        #expect(history.messages(conversationID: id, limit: 20).count == 3)
        _ = try await service.deleteRound(first)
        #expect(history.messages(conversationID: id, limit: 20).map(\.text) == ["keep this"])
        #expect(history.search("remove").isEmpty)
        #expect(local.setting("history.revision") != nil)
    }

    @Test func historyIsInternalAndIndependentOfMemorySwitch() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try LocalStore(root: root)
        let service = ToolService(store: local, policy: { PolicySnapshot(enabledSources: []) }, presenter: { _ in .rejected })
        await service.register(HistoryTool(store: local))
        #expect(await service.definitions(for: .agent(sessionID: "test")).count == 1)
        #expect(await service.definitions(for: .mcp(instanceID: "test")).isEmpty)
        #expect(await service.definitions(for: .launcher).isEmpty)
    }
}
