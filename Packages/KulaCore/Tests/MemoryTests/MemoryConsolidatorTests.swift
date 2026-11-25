import Testing
import Foundation
import LocalStore
@testable import Memory

@Suite struct MemoryConsolidatorTests {
    private func setup() throws -> (LocalStore, MemoryFolder) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let s = try LocalStore(inMemoryWithRoot: root)
        let m = MemoryFolder(s)
        try m.add("用户住在杭州", section: "关于我")
        try m.add("用户的居住地是杭州", section: "关于我")
        try m.add("用户在做 Orion 项目", file: "projects.md", description: "长期项目")
        try m.add("用户在做 Orion 项目，用 Swift 写", file: "old.md", description: "旧笔记")
        return (s, m)
    }

    @Test func rewritesFolderOnlyWhenDirtyAndDue() async throws {
        let (s, m) = try setup()
        let reply = #"""
            整理好了：{"files":[
              {"name":"MEMORY.md","content":"# Asky 记忆\n\n## 关于我\n- 用户住在杭州\n\n## 偏好\n\n## 主题文件\n- [projects.md](projects.md) — 长期项目"},
              {"name":"projects.md","content":"# projects\n\n- 用户在做 Orion 项目，用 Swift 写"}]}
            """#
        var c = MemoryConsolidator(store: s, memory: m) { _, user in
            #expect(user.contains("=== old.md ==="))
            return reply
        }
        // Nothing has changed since the last pass.
        #expect(await c.run() == false)

        MemoryConsolidator.markDirty(s)
        #expect(await c.run())
        #expect(m.read().components(separatedBy: "杭州").count == 2)
        #expect(m.topicFiles() == ["projects.md"] && m.read("projects.md").contains("Swift"))
        let backup = m.root.appendingPathComponent(".previous/old.md")
        #expect(FileManager.default.fileExists(atPath: backup.path))

        // Too soon after the last pass.
        MemoryConsolidator.markDirty(s)
        #expect(c.isDue() == false)
        c.minInterval = 0
        #expect(c.isDue())
    }

    @Test func concurrentEditSurvivesConsolidation() async throws {
        let (s, m) = try setup()
        MemoryConsolidator.markDirty(s)
        let consolidate = MemoryConsolidator(store: s, memory: m) { _, _ in
            try m.add("新偏好", section: "偏好")
            return #"{"files":[{"name":"MEMORY.md","content":"old summary"}]}"#
        }
        #expect(await !consolidate.run())
        #expect(m.read().contains("新偏好"))
        #expect(s.setting(MemoryConsolidator.dirtyKey) == "1")
    }

    @Test func invalidRepliesLeaveFilesUntouched() async throws {
        let (s, m) = try setup()
        let before = m.read()
        MemoryConsolidator.markDirty(s)
        let replies = [
            "不是 JSON",
            ##"{"files":[{"name":"projects.md","content":"# p"}]}"##,                                   // no index
            ##"{"files":[{"name":"MEMORY.md","content":"# 记忆"},{"name":"projects.md","content":"# p"}]}"##, // unlisted topic
            ##"{"files":[{"name":"MEMORY.md","content":"# 记忆"},{"name":"../x.md","content":"x"}]}"##,       // bad name
        ]
        for r in replies {
            var c = MemoryConsolidator(store: s, memory: m) { _, _ in r }
            c.minInterval = 0
            #expect(await c.run() == false)
        }
        #expect(m.read() == before && m.topicFiles().count == 2 && s.setting(MemoryConsolidator.dirtyKey) == "1")
    }

    @Test func promptPrunesVolatileSystemState() {
        #expect(MemoryConsolidator.systemPrompt.contains("当前日历名称列表"))
        #expect(MemoryConsolidator.systemPrompt.contains("系统默认日历"))
    }
}
