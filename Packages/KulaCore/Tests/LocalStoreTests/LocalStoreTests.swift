import Testing
import Foundation
import Contracts
@testable import LocalStore

func tempRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("kula-\(UUID().uuidString)", isDirectory: true)
}

@Suite struct LocalStoreTests {
    @Test func migrationIsIdempotentOnDisk() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try LocalStore(root: root)
        let again = try LocalStore(root: root)
        #expect(try again.db.scalarInt("PRAGMA user_version") == Schema.migrations.count)
        #expect(FileManager.default.fileExists(atPath: again.clipboardDirectory.path))
    }

    @Test func nestedTransactionRollsBackOnlyInner() throws {
        let s = try LocalStore(inMemoryWithRoot: tempRoot())
        try s.db.transaction {
            try s.db.run("INSERT INTO settings(key, value) VALUES('a', '1')")
            _ = try? s.db.transaction {
                try s.db.run("INSERT INTO settings(key, value) VALUES('b', '2')")
                throw SQLiteError(code: 0, message: "boom")
            }
        }
        #expect(s.setting("a") == "1")
        #expect(s.setting("b") == nil)
    }

    @Test func settingsRoundTrip() throws {
        let s = try LocalStore(inMemoryWithRoot: tempRoot())
        s.setCodableSetting("k", ["x", "y"])
        #expect(s.codableSetting("k", as: [String].self) == ["x", "y"])
        s.setSetting("k", nil)
        #expect(s.setting("k") == nil)
    }

    @Test func clipboardCleanupExpiresLegacyPinnedAndRespectsBudget() throws {
        let s = try LocalStore(inMemoryWithRoot: tempRoot())
        let c = ClipboardStore(s)
        let now = Date()
        let old = now.addingTimeInterval(-4 * 86400)
        try c.insert(ClipboardItem(kind: .text, text: "old pinned", byteSize: 10, pinned: true, contentHash: "p", createdAt: old))
        try c.insert(ClipboardItem(kind: .text, text: "old", byteSize: 10, contentHash: "o", createdAt: old))
        for i in 0..<5 {
            try c.insert(ClipboardItem(kind: .image, filePath: "/tmp/\(i).png", byteSize: 100, contentHash: "i\(i)",
                                       createdAt: now.addingTimeInterval(Double(i))))
        }
        let paths = try c.cleanup(now: now, budget: 250)
        let left = c.recent(limit: 50)
        #expect(!left.contains { $0.contentHash == "p" })
        #expect(!left.contains { $0.contentHash == "o" })
        #expect(c.totalBytes() <= 250)
        // Oldest images go first.
        #expect(Set(paths) == ["/tmp/0.png", "/tmp/1.png", "/tmp/2.png"])
        #expect(left.contains { $0.contentHash == "i4" })
    }

    @Test func clipboardRetentionBoundaryRemovesAssetsAndIndexButPreservesOriginalFiles() throws {
        let store = ClipboardStore(try LocalStore(inMemoryWithRoot: tempRoot()))
        let now = Date()
        let cutoff = now.addingTimeInterval(-3 * 86400)
        #expect(ClipboardStore.retention == 3 * 86400)
        for (hash, date) in [("expired", cutoff.addingTimeInterval(-1)), ("boundary", cutoff),
                             ("recent", cutoff.addingTimeInterval(1))] {
            try store.insert(ClipboardItem(kind: .text, text: "retention \(hash)", byteSize: 1,
                pinned: true, contentHash: hash, createdAt: date))
        }
        try store.insert(ClipboardItem(kind: .image, filePath: "/owned/original.img", thumbPath: "/owned/thumb.png",
            byteSize: 1, pinned: true, contentHash: "image", createdAt: cutoff))
        try store.insert(ClipboardItem(kind: .file, text: "retention original", filePaths: ["/original/file"],
            byteSize: 1, contentHash: "file", createdAt: cutoff))
        #expect(Set(try store.cleanup(now: now)) == ["/owned/original.img", "/owned/thumb.png"])
        #expect(store.recent(limit: 10).map(\.contentHash) == ["recent"])
        #expect(store.search("retention").map(\.contentHash) == ["recent"])
        #expect(try store.cleanup(now: now).isEmpty)
    }

    @Test(arguments: ClipboardRetention.allCases)
    func clipboardCleanupUsesSelectedRetention(retention: ClipboardRetention) throws {
        let store = ClipboardStore(try LocalStore(inMemoryWithRoot: tempRoot()), retention: retention)
        let now = Date()
        let cutoff = now.addingTimeInterval(-retention.interval)
        for (hash, date) in [("expired", cutoff), ("recent", cutoff.addingTimeInterval(1))] {
            try store.insert(ClipboardItem(kind: .text, text: hash, byteSize: 1,
                contentHash: hash, createdAt: date))
        }
        _ = try store.cleanup(now: now)
        #expect(store.recent(limit: 10).map(\.contentHash) == ["recent"])
    }

    @Test func clipboardDedupesByHashAndSearchesShortTokens() throws {
        let s = try LocalStore(inMemoryWithRoot: tempRoot())
        let c = ClipboardStore(s)
        try c.insert(ClipboardItem(kind: .text, text: "会议纪要 Asky", byteSize: 5, contentHash: "h"))
        try c.insert(ClipboardItem(kind: .text, text: "会议纪要 Asky", byteSize: 5, contentHash: "h"))
        #expect(c.recent(limit: 10).count == 1)
        #expect(c.search("会议").count == 1)      // 2 chars → LIKE fallback
        #expect(c.search("Asky").count == 1) // trigram index
        #expect(c.search("100%").isEmpty)        // LIKE metacharacters escaped
    }

    @Test func fileReferenceCleanupDoesNotReturnOriginalPaths() throws {
        let s = try LocalStore(inMemoryWithRoot: tempRoot())
        let store = ClipboardStore(s)
        let item = ClipboardItem(kind: .file, text: "Original", filePath: "/tmp/Original", byteSize: 1,
            contentHash: "file", createdAt: Date().addingTimeInterval(-32 * 86400))
        try store.insert(item)
        #expect(store.recent(limit: 1).first?.filePaths == ["/tmp/Original"])
        #expect(try store.cleanup().isEmpty)
        #expect(store.recent(limit: 1).isEmpty)
    }

    @Test func conversationPagingAndDeleteCascade() throws {
        let s = try LocalStore(inMemoryWithRoot: tempRoot())
        let cs = ConversationStore(s)
        let id = try cs.create(title: "t")
        for i in 1...130 { try cs.append(conversationID: id, role: "user", text: "message \(i)") }
        let first = cs.messages(conversationID: id, limit: 40)
        #expect(first.count == 40)
        #expect(first.first?.seq == 91 && first.last?.seq == 130)
        let older = cs.messages(conversationID: id, limit: 40, beforeSeq: first.first!.seq)
        #expect(older.last?.seq == 90)
        #expect(cs.search("message 7").count > 0)
        try cs.delete(id)
        #expect(cs.messages(conversationID: id, limit: 40).isEmpty)
        #expect(cs.search("message").isEmpty)
    }

    @Test func oldMessagesMigrateWithoutAttachments() throws {
        let db = try Database(path: ":memory:")
        try db.execute(Schema.migrations[0])
        try db.execute("PRAGMA user_version = 1")
        try db.run("INSERT INTO conversations(id,title,created_at,updated_at) VALUES('old','old',0,0)")
        try db.run("INSERT INTO messages(id,conversation_id,seq,role,text,created_at) VALUES('message','old',1,'user','old text',0)")
        try Schema.migrate(db)
        try Schema.migrate(db)
        let row = try #require(db.query("SELECT * FROM messages WHERE id = 'message'").first)
        #expect(ConversationStore.decode(row).text == "old text")
        #expect(ConversationStore.decode(row).attachments.isEmpty)
        #expect(ConversationStore.decode(row).presentation == nil)
    }

    @Test func messageAttachmentsSurviveReopeningAndPaging() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try LocalStore(root: root)
        let store = ConversationStore(local)
        let cid = try store.create(title: "附件")
        let refs = [AttachmentRef(kind: .image, path: "/local/picture.png", mimeType: "image/png", byteSize: 123, temporary: false),
                    AttachmentRef(kind: .file, path: "/local/AGENTS.md", mimeType: "text/plain", byteSize: 456, temporary: false)]
        let submitted = try store.append(conversationID: cid, role: "user", text: "查看附件", attachments: refs)
        try store.append(conversationID: cid, role: "assistant", text: "回复")
        let reopened = ConversationStore(try LocalStore(root: root))
        let restored = try #require(reopened.messages(conversationID: cid, limit: 1, beforeSeq: 2).first)
        #expect(restored.id == submitted.id)
        #expect(restored.text == submitted.text)
        #expect(restored.attachments == refs)
        #expect(reopened.messages(conversationID: cid, limit: 1).first?.attachments == [])
        #expect(reopened.search("查看").first?.attachments == refs)
        try reopened.delete(cid)
        #expect(reopened.messages(conversationID: cid, limit: 40).isEmpty)
    }

    @Test func transcriptStepsSurviveDiskReopenPagingAndUpdates() throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(try LocalStore(root: root))
        let cid = try store.create(title: "工具记录")
        let user = try store.append(conversationID: cid, role: "user", text: "检查日历")
        let started = MessagePresentation(responseID: "turn", toolName: "calendar_search")
        let call = try store.append(conversationID: cid, role: "tool", text: "调用 calendar_search…",
                                    id: "call", presentation: started)
        let ended = MessagePresentation(responseID: "turn", toolName: "calendar_search", toolStatus: .failed,
                                        toolError: "缺少权限", needsPermissionSettings: true)
        try store.updateMessage(call.id, conversationID: cid, text: "调用 calendar_search", presentation: ended)
        let completedAt = Date(timeIntervalSince1970: 1800000000)
        let reply = MessagePresentation(responseID: "turn", workSeconds: 13, completedAt: completedAt)
        try store.append(conversationID: cid, role: "error", text: "请求失败", presentation: .init(responseID: "turn"))
        try store.append(conversationID: cid, role: "assistant", text: "请授权", presentation: reply)
        let reopened = ConversationStore(try LocalStore(root: root))
        let newest = reopened.messages(conversationID: cid, limit: 2)
        #expect(newest.map(\.role) == ["error", "assistant"])
        #expect(newest.last?.presentation == reply)
        let older = reopened.messages(conversationID: cid, limit: 2, beforeSeq: newest[0].seq)
        #expect(older.map(\.id) == [user.id, call.id])
        #expect(older.last?.presentation == ended)
        #expect(older.last?.text == "调用 calendar_search")
        #expect(reopened.search("calendar").count == 1)
        #expect(reopened.search("calendar").first?.presentation == ended)
        #expect(older.first?.presentation == nil)
        #expect(reopened.messages(conversationID: cid, limit: 2, dialogueOnly: true).map(\.role) == ["user", "assistant"])
        try reopened.delete(cid)
        #expect(reopened.messages(conversationID: cid, limit: 40).isEmpty)
        #expect(reopened.search("calendar").isEmpty)
    }

    @Test func mcpInstanceLookupByHashOnly() throws {
        let s = try LocalStore(inMemoryWithRoot: tempRoot())
        let m = MCPInstanceStore(s)
        let inst = MCPInstance(name: "Claude", enabled: true, sources: [.calendar])
        try m.save(inst, credentialHash: "abc")
        #expect(m.instance(credentialHash: "abc")?.id == inst.id)
        #expect(m.instance(credentialHash: "nope") == nil)
        #expect(MCPInstance(name: "x").enabled == false && MCPInstance(name: "x").readOnly)
    }

    @Test func activityExpiryPurges() throws {
        let s = try LocalStore(inMemoryWithRoot: tempRoot())
        let a = ActivityStore(s)
        try a.append(kind: "search", sourceID: "s1", text: "x", now: Date().addingTimeInterval(-31 * 86400))
        try a.append(kind: "search", sourceID: "s2", text: "y")
        #expect(try a.purgeExpired() == 1)
        #expect(a.count() == 1)
        #expect(!SourceStore(s).isDeleted("s1"))
    }
}
