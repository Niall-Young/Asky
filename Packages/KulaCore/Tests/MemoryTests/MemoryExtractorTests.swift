import Testing
import Foundation
import Contracts
import LocalStore
@testable import Memory

private actor Calls {
    var prompts: [String] = []
    func add(_ p: String) { prompts.append(p) }
}

private func conversation(_ s: LocalStore, _ texts: [(String, String)]) throws -> String {
    let conv = ConversationStore(s)
    let cid = try conv.create(title: "t")
    for (role, text) in texts { try conv.append(conversationID: cid, role: role, text: text) }
    try SourceStore(s).upsert(SourceRecord(id: "conversation:\(cid)", kind: "conversation", title: "t",
                                           permissions: [.read, .aiUse, .extraction]))
    try ExtractionQueue(s).enqueue("conversation:\(cid)")
    return cid
}

@Suite struct MemoryExtractorTests {
    @Test func appliesFileEditsIncrementallyAfterIdle() async throws {
        let s = try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory)
        let m = tempMemoryFolder()
        let cid = try conversation(s, [("user", "以后都用中文回复我"), ("assistant", "好的")])
        let calls = Calls()
        var extractor = MemoryExtractor(store: s, memory: m) { _, user in
            await calls.add(user)
            return #"好的：{"add":[{"section":"偏好","content":"用户希望默认用中文回复"},{"content":" "}]}"#
        }
        // A conversation that is still active is not extracted yet.
        #expect(await extractor.run().isEmpty)
        #expect(await calls.prompts.isEmpty && ExtractionQueue(s).count == 1)
        extractor.minIdle = 0
        #expect(await extractor.run() == ["用户希望默认用中文回复"])
        #expect(m.read().contains("## 偏好\n- 用户希望默认用中文回复"))
        #expect(ExtractionQueue(s).count == 0 && s.setting(MemoryConsolidator.dirtyKey) == "1")

        // Re-queue without new messages: no model call.
        try ExtractionQueue(s).enqueue("conversation:\(cid)")
        #expect(await extractor.run().isEmpty)
        #expect(await calls.prompts.count == 1)

        // New messages only: the prompt carries the new turn and the current index; a repeated line is not written again.
        try ConversationStore(s).append(conversationID: cid, role: "user", text: "我在做 Orion 项目")
        try ExtractionQueue(s).enqueue("conversation:\(cid)")
        #expect(await extractor.run().isEmpty)
        let second = try #require(await calls.prompts.last)
        #expect(second.contains("Orion") && !second.contains("以后都用中文回复我") && second.contains("- 用户希望默认用中文回复"))
        #expect(m.read().components(separatedBy: "用户希望默认用中文回复").count == 2)
    }

    @Test func longConversationRequeuesRemainingMessages() async throws {
        let s = try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory)
        _ = try conversation(s, (1...41).map { ("user", "message-\($0)") })
        let calls = Calls()
        var extractor = MemoryExtractor(store: s, memory: tempMemoryFolder()) { _, user in
            await calls.add(user)
            return #"{"add":[]}"#
        }
        extractor.minIdle = 0
        _ = await extractor.run()
        #expect(ExtractionQueue(s).count == 1)
        _ = await extractor.run()
        #expect(await calls.prompts.last?.contains("message-41") == true)
        #expect(ExtractionQueue(s).count == 0)
    }

    @Test func failedCallRequeuesAndDeletedSourceIsSkipped() async throws {
        struct Boom: Error {}
        let s = try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory)
        let m = tempMemoryFolder()
        let cid = try conversation(s, [("user", "记一下我喜欢靠窗")])
        var failing = MemoryExtractor(store: s, memory: m) { _, _ in throw Boom() }
        failing.minIdle = 0
        _ = await failing.run()
        #expect(ExtractionQueue(s).count == 1)

        var extractor = MemoryExtractor(store: s, memory: m) { _, _ in
            try s.db.run("INSERT INTO deletion_markers(source_id, deleted_at) VALUES(?, 0)", ["conversation:\(cid)"])
            return #"{"add":[{"section":"偏好","content":"用户喜欢靠窗座位"}]}"#
        }
        extractor.minIdle = 0
        #expect(await extractor.run().isEmpty)
        #expect(m.context() == nil)
    }

    @Test func editsIndexAndTopicFilesByExactText() async throws {
        let s = try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory)
        let m = tempMemoryFolder()
        try m.add("用户住在上海", section: "关于我")
        try m.add("用户在做 Orion 项目", file: "projects.md", description: "长期项目")
        try m.add("用户的生日是 3 月 2 日", section: "关于我")
        _ = try conversation(s, [("user", "我上个月搬到杭州了，Orion 项目也结束了，女儿今年上小学")])
        let calls = Calls()
        var extractor = MemoryExtractor(store: s, memory: m) { _, user in
            await calls.add(user)
            return #"""
                {"replace":[{"file":"MEMORY.md","old":"用户住在上海","new":"用户住在杭州"},{"old":"不存在","new":"x"}],
                 "remove":[{"file":"projects.md","old":"用户在做 Orion 项目"}],
                 "add":[{"file":"family.md","description":"家人与亲友","content":"用户的女儿今年上小学"}]}
                """#
        }
        extractor.minIdle = 0
        #expect(await extractor.run() == ["用户住在杭州", "用户的女儿今年上小学"])
        // Topic files are shown to the model so it can edit them.
        #expect(await calls.prompts.first?.contains("记忆文件 projects.md：") == true)
        let index = m.read()
        #expect(index.contains("- 用户住在杭州") && !index.contains("上海") && index.contains("生日"))
        #expect(index.contains("- [family.md](family.md) — 家人与亲友"))
        #expect(!m.read("projects.md").contains("Orion") && m.read("family.md").contains("- 用户的女儿今年上小学"))
    }

    @Test func promptExcludesVolatileSystemState() {
        #expect(MemoryExtractor.systemPrompt.contains("当前日历名称列表"))
        #expect(MemoryExtractor.systemPrompt.contains("系统默认日历"))
    }
}
