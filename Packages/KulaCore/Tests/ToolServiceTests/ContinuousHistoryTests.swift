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

    @Test func anchoredDialogueStaysAppendOnlyUntilBatchRolloverAndRecoversOnDeletion() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try LocalStore(root: root), history = ConversationStore(local)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var t = 0.0
        func addTurn(_ tag: String, bytes: Int = 100) throws -> StoredMessage {
            let cid = try history.create(title: tag, now: base.addingTimeInterval(t))
            let payload = tag + ":" + String(repeating: "a", count: max(0, bytes - tag.count - 1))
            let user = try history.append(conversationID: cid, role: "user", text: payload, now: base.addingTimeInterval(t))
            t += 1
            try history.append(conversationID: cid, role: "tool", text: "ignored-tool-payload", now: base.addingTimeInterval(t))
            t += 1
            try history.append(conversationID: cid, role: "assistant", text: payload, now: base.addingTimeInterval(t))
            t += 1
            return user
        }

        // Seed 6 turns (12 dialogue messages, 1200 bytes). With maxBytes=1000, rolloverBytes=500,
        // cold start should pick the tail fitting 500 bytes (5 messages = 500 bytes) and pin its anchor.
        for i in 1...6 { _ = try addTurn("t\(i)", bytes: 100) }
        let firstWindow = history.anchoredDialogue(in: local, maxBytes: 1000, rolloverBytes: 500, maxMessages: 20, rolloverMessages: 10)
        #expect(firstWindow.count == 5)
        let firstAnchor = firstWindow.first?.id
        #expect(local.setting(ConversationStore.historyAnchorSettingKey) == firstAnchor)

        // Appending 2 more turns (400 more bytes -> 900 <= 1000) must keep the exact same prefix!
        _ = try addTurn("t7", bytes: 100)
        let secondWindow = history.anchoredDialogue(in: local, maxBytes: 1000, rolloverBytes: 500, maxMessages: 20, rolloverMessages: 10)
        #expect(Array(secondWindow.prefix(firstWindow.count)) == firstWindow)
        #expect(secondWindow.count == 7)

        _ = try addTurn("t8", bytes: 100)
        let thirdWindow = history.anchoredDialogue(in: local, maxBytes: 1000, rolloverBytes: 500, maxMessages: 20, rolloverMessages: 10)
        #expect(Array(thirdWindow.prefix(secondWindow.count)) == secondWindow)
        #expect(thirdWindow.count == 9)

        // Adding 1 more turn pushes bytes to 1100 > 1000, triggering a single batch rollover to <= 500 bytes.
        _ = try addTurn("t9", bytes: 100)
        let rolledWindow = history.anchoredDialogue(in: local, maxBytes: 1000, rolloverBytes: 500, maxMessages: 20, rolloverMessages: 10)
        #expect(rolledWindow.count == 5)
        #expect(rolledWindow.first?.id != firstAnchor)
        #expect(local.setting(ConversationStore.historyAnchorSettingKey) == rolledWindow.first?.id)

        // Clearing history resets the anchor cleanly without resurrecting anything.
        _ = try await ConversationHistoryService(store: local).clear()
        let emptyWindow = history.anchoredDialogue(in: local, maxBytes: 1000, rolloverBytes: 500, maxMessages: 20, rolloverMessages: 10)
        #expect(emptyWindow.isEmpty)
        #expect(local.setting(ConversationStore.historyAnchorSettingKey) == nil)
    }
}
