import Foundation
import Testing
import Contracts
import LocalStore
@testable import ToolService

@Suite struct ConversationHistoryTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Asky-history-cleanup-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func expiryRemovesAllConversationDataButPreservesMemory() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try LocalStore(root: root)
        let store = ConversationStore(local)
        let now = Date()
        let old = now.addingTimeInterval(-31 * 86400)
        let id = try store.create(title: "过期", now: old)
        let activeID = try store.create(title: "运行中", now: old)
        let recentID = try store.create(title: "近期", now: now)
        let attachment = root.appending(path: "Attachments/owned/file.txt")
        let native = root.appending(path: "runtime/native-sessions/\(id).json")
        let legacy = root.appending(path: "runtime/pi/sessions/old.jsonl")
        let memory = root.appending(path: "Memory/MEMORY.md")
        let topic = root.appending(path: "Memory/preferences.md")
        try write("原始附件", to: attachment)
        try write("原始上下文", to: native)
        try write("旧会话", to: legacy)
        try write("长期记忆：偏好中文", to: memory)
        try write("长期主题内容", to: topic)
        let memoryBefore = try Data(contentsOf: memory), topicBefore = try Data(contentsOf: topic)
        try store.setRuntimeSession(id, ref: legacy.path)
        let ref = AttachmentRef(kind: .text, path: attachment.path, mimeType: "text/plain", byteSize: 10, temporary: false)
        try store.append(conversationID: id, role: "user", text: "expired searchable history", attachments: [ref], now: old)
        let source = "conversation:\(id)"
        try SourceStore(local).upsert(SourceRecord(id: source, kind: "conversation", title: "旧标题", permissions: [.read, .aiUse, .extraction]))
        try ActivityStore(local).append(kind: "conversation", sourceID: source, text: "旧正文", now: old)
        try local.db.run("INSERT INTO extraction_queue(source_id,enqueued_at) VALUES(?,?)", [source, old])
        local.setSetting("memory.extracted.\(source)", "1")
        try ExecutionStore(local).upsert(ExecutionRecord(requestID: "call", tool: "calendar_search", argumentsDigest: "digest",
            origin: "agent:\(id)", taskID: "task", status: .completed, result: nil, createdAt: old, updatedAt: old))
        // Legacy structured memories and their provenance must also survive unchanged.
        try local.db.run("INSERT INTO memories(id,content,kind,status,source_ids,subjects,confirmed,pinned,permissions,created_at,updated_at) VALUES('kept','记忆','fact','active',?,'[]',0,0,0,?,?)", [JSONText.encode([source]), old, old])
        try local.db.run("INSERT INTO memory_sources(memory_id,source_id) VALUES('kept',?)", [source])
        let service = ConversationHistoryService(store: local)
        let result = try await service.cleanup(retention: .thirtyDays, protecting: [activeID], now: now)
        #expect(result.deletedIDs == [id])
        #expect(result.pendingFiles == 0)
        #expect(store.messages(conversationID: id, limit: 10).isEmpty)
        #expect(store.search("expired").isEmpty)
        #expect(!FileManager.default.fileExists(atPath: attachment.path))
        #expect(!FileManager.default.fileExists(atPath: attachment.deletingLastPathComponent().path))
        #expect(!FileManager.default.fileExists(atPath: native.path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        for table in ["executions", "activity", "extraction_queue", "sources", "attachments"] {
            #expect(try local.db.scalarInt("SELECT COUNT(*) FROM \(table)") == 0)
        }
        #expect(local.setting("memory.extracted.\(source)") == nil)
        #expect(Set(store.list(limit: 10).map(\.id)) == [activeID, recentID])
        #expect(try Data(contentsOf: memory) == memoryBefore)
        #expect(try Data(contentsOf: topic) == topicBefore)
        #expect(try local.db.query("SELECT content FROM memories WHERE id = 'kept'").first?.string("content") == "记忆")
        #expect(try local.db.scalarInt("SELECT COUNT(*) FROM memory_sources") == 1)
    }

    @Test func runningToolsProtectSessionsUntilTheirResultsAreRecorded() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try LocalStore(root: root)
        let old = Date().addingTimeInterval(-40 * 86400)
        let id = try ConversationStore(local).create(title: "工具仍在执行", now: old)
        let tools = ToolService(store: local, policy: { PolicySnapshot(enabledSources: [.calendar]) }, presenter: { _ in .approved })
        let adapter = FakeAdapter("history_read", effect: .read, delay: .milliseconds(250))
        await tools.register(adapter)
        let request = ActionRequest(tool: "history_read", arguments: [:], origin: .agent(sessionID: id), intent: .explicitRequest)
        let task = Task { await tools.submit(request) }
        for _ in 0..<100 where adapter.count == 0 { try await Task.sleep(for: .milliseconds(1)) }
        #expect(adapter.count == 1)
        let active = await tools.activeAgentSessionIDs
        #expect(active.contains(id))
        let history = ConversationHistoryService(store: local)
        let skipped = try await history.cleanup(retention: .thirtyDays, protecting: active)
        #expect(skipped.deletedIDs.isEmpty)
        _ = await task.value
        let finished = await tools.activeAgentSessionIDs
        #expect(finished.isEmpty)
        let removed = try await history.cleanup(retention: .thirtyDays, protecting: finished)
        #expect(removed.deletedIDs == [id])
        #expect(ExecutionStore(local).record(requestID: request.requestID) == nil)
    }

    @Test func manualDeletionPreservesSharedAttachmentsOriginalsAndMemory() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try LocalStore(root: root), store = ConversationStore(try LocalStore(root: root))
        let first = try store.create(title: "一"), second = try store.create(title: "二")
        let shared = root.appending(path: "Attachments/shared/file.txt")
        let original = root.appending(path: "original.txt")
        let memory = root.appending(path: "Memory/topic.md")
        let link = root.appending(path: "Attachments/linked")
        try write("shared", to: shared); try write("original", to: original); try write("memory", to: memory)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: memory.deletingLastPathComponent())
        let paths = [shared.path, original.path, memory.path, link.appending(path: "topic.md").path]
        let refs = paths.map { AttachmentRef(kind: .text, path: $0, mimeType: "text/plain", byteSize: 1, temporary: false) }
        try store.append(conversationID: first, role: "user", text: "first", attachments: refs)
        try store.append(conversationID: second, role: "user", text: "second", attachments: [refs[0]])
        let service = ConversationHistoryService(store: local)
        let one = try await service.delete(first)
        #expect(one.pendingFiles == 0)
        #expect(FileManager.default.fileExists(atPath: shared.path))
        let two = try await service.delete(second)
        #expect(two.pendingFiles == 0)
        #expect(!FileManager.default.fileExists(atPath: shared.path))
        #expect(try String(contentsOf: original, encoding: .utf8) == "original")
        #expect(try String(contentsOf: memory, encoding: .utf8) == "memory")
    }

    @Test func failedFilesRetryAfterReopeningAndForeverStillReclaimsOrphans() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try LocalStore(root: root), store = ConversationStore(local)
        let id = try store.create(title: "删除失败")
        let bad = root.appending(path: "Attachments/not-a-file")
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try store.append(conversationID: id, role: "user", text: "file",
            attachments: [AttachmentRef(kind: .file, path: bad.path, mimeType: "text/plain", byteSize: 1, temporary: false)])
        let first = try await ConversationHistoryService(store: local).delete(id)
        #expect(first.pendingFiles == 1)
        try FileManager.default.removeItem(at: bad)
        try write("retry", to: bad)
        let orphan = root.appending(path: "runtime/native-sessions/orphan.json")
        let draft = root.appending(path: "Attachments/draft.txt")
        try write("orphan", to: orphan); try write("draft", to: draft)
        let now = Date(), old = now.addingTimeInterval(-2 * 86400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: orphan.path)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: draft.path)
        let kept = try store.create(title: "永久", now: old.addingTimeInterval(-100 * 86400))
        try SourceStore(local).upsert(SourceRecord(id: "conversation:dangling", kind: "conversation", title: "旧版残留", permissions: [.read], createdAt: old))
        try ExecutionStore(local).upsert(ExecutionRecord(requestID: "dangling-call", tool: "calendar_search", argumentsDigest: "digest",
            origin: "agent:dangling", taskID: "old-task", status: .completed, result: nil, createdAt: old, updatedAt: old))
        let reopened = try LocalStore(root: root)
        let result = try await ConversationHistoryService(store: reopened).cleanup(retention: .forever, draftPaths: [draft.path], now: now)
        #expect(result.pendingFiles == 0)
        #expect(result.deletedIDs == ["dangling"])
        #expect(SourceStore(reopened).source("conversation:dangling") == nil)
        #expect(ExecutionStore(reopened).record(requestID: "dangling-call") == nil)
        #expect(!FileManager.default.fileExists(atPath: bad.path))
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(FileManager.default.fileExists(atPath: draft.path))
        #expect(ConversationStore(reopened).list(limit: 10).contains { $0.id == kept })
    }

    @Test func deleteSingleMessagePreservesSiblingRepliesAndCleansUnusedAttachments() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try LocalStore(root: root)
        let store = ConversationStore(local)
        let cid = try store.create(title: "单条删除")
        let onlyUserFile = root.appending(path: "Attachments/single/user-only.txt")
        let sharedFile = root.appending(path: "Attachments/shared/shared.txt")
        try write("only", to: onlyUserFile)
        try write("shared", to: sharedFile)
        let userOnlyRef = AttachmentRef(kind: .text, path: onlyUserFile.path, mimeType: "text/plain", byteSize: 4, temporary: false)
        let sharedRef = AttachmentRef(kind: .text, path: sharedFile.path, mimeType: "text/plain", byteSize: 6, temporary: false)

        let user = try store.append(conversationID: cid, role: "user", text: "uniquedeletablequery", attachments: [userOnlyRef, sharedRef])
        let assistant = try store.append(conversationID: cid, role: "assistant", text: "保留这条回复", attachments: [sharedRef])

        let service = ConversationHistoryService(store: local)
        let partial = try await service.deleteMessage(user)
        #expect(partial.deletedIDs.isEmpty)
        #expect(partial.pendingFiles == 0)
        #expect(store.message(user.id, conversationID: cid) == nil)
        #expect(store.message(assistant.id, conversationID: cid)?.text == "保留这条回复")
        #expect(store.search("uniquedeletablequery").isEmpty)
        #expect(!FileManager.default.fileExists(atPath: onlyUserFile.path))
        #expect(FileManager.default.fileExists(atPath: sharedFile.path))

        let finalResult = try await service.deleteMessage(assistant)
        #expect(finalResult.deletedIDs == [cid])
        #expect(finalResult.pendingFiles == 0)
        #expect(store.messages(conversationID: cid, limit: 10).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: sharedFile.path))
    }
}
