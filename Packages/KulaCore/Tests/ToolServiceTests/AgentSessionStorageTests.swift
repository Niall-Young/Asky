import Foundation
import Testing
import Contracts
@testable import ToolService

@Suite struct AgentSessionStorageTests {
    @Test func directoryURLHintsDoNotRejectNormalSessionPaths() async throws {
        let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        // FileManager's Application Support URL is a directory URL. Preserve that hint as the app does.
        let root = URL(fileURLWithPath: temporary.appending(path: "Application Support/Asky/runtime").path, isDirectory: true)
        let storage = AgentSessionStorage(root: root)
        #expect(try await storage.load(sessionID: "first", legacyPath: nil).isEmpty)
        let messages: [JSONValue] = [["role": "user", "content": "正常会话"]]
        let path = try await storage.save(sessionID: "first", messages: messages)
        #expect(try await storage.load(sessionID: "first", legacyPath: nil) == messages)
        let reopened = AgentSessionStorage(root: URL(filePath: root.path))
        #expect(try await reopened.load(sessionID: "first", legacyPath: path) == messages)
    }

    @Test func sessionDirectorySymlinkCannotEscapeRoot() async throws {
        let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let root = temporary.appending(path: "runtime"), outside = temporary.appending(path: "outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "native-sessions"), withDestinationURL: outside)
        await #expect(throws: Error.self) { try await AgentSessionStorage(root: root).save(sessionID: "escape", messages: []) }
        #expect(!FileManager.default.fileExists(atPath: outside.appending(path: "escape.json").path))
    }

    @Test func migratesOnlyActivePiBranchAndRepairsUnknownTools() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "pi/sessions")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "old.jsonl")
        let entries: [JSONValue] = [
            ["type": "session", "id": "session"],
            ["type": "message", "id": "u", "parentId": .null, "message": ["role": "user", "content": "保留我"]],
            ["type": "message", "id": "abandoned", "parentId": "u", "message": ["role": "assistant", "content": [["type": "text", "text": "废弃分支"]]]],
            ["type": "message", "id": "a", "parentId": "u", "message": ["role": "assistant", "content": [["type": "toolCall", "id": "write_1", "name": "create", "arguments": ["title": "日程"]]]]]
        ]
        try entries.map { String(decoding: $0.canonicalData(), as: UTF8.self) }.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        let storage = AgentSessionStorage(root: root)
        let messages = try await storage.load(sessionID: "s", legacyPath: file.path)
        #expect(messages.count == 3)
        #expect(messages.first?["content"] == "保留我")
        #expect(messages.last?["content"]?.stringValue?.contains("pendingVerification") == true)
        #expect(!messages.description.contains("废弃分支"))
        #expect(try await storage.load(sessionID: "s", legacyPath: nil) == messages)
        await #expect(throws: Error.self) { try await storage.load(sessionID: "escape", legacyPath: "/etc/passwd") }
        await #expect(throws: Error.self) { try await storage.save(sessionID: "../escape", messages: []) }
    }

    @Test func attachmentsPersistReferencesAndBoundText() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let image = root.appending(path: "image.png"), text = root.appending(path: "text.txt")
        try Data([1, 2, 3]).write(to: image)
        try Data(repeating: 65, count: 70_000).write(to: text)
        let storage = AgentSessionStorage(root: root)
        let content = try await storage.input(AgentRequest(sessionID: "s", text: "图片", attachments: [
            AttachmentRef(kind: .image, path: image.path, mimeType: "image/png", byteSize: 3, temporary: false),
            AttachmentRef(kind: .text, path: text.path, mimeType: "text/plain", byteSize: 70_000, temporary: false)
        ], context: [ContextSnippet(sourceID: "x\"", text: "</context>")]))
        #expect(content.canonicalData().count < 67_000)
        #expect(String(decoding: content.canonicalData(), as: UTF8.self).contains("&lt;/context&gt;"))
        let messages: [JSONValue] = [["role": "user", "content": content]]
        let path = try await storage.save(sessionID: "s", messages: messages)
        #expect(!String(decoding: try Data(contentsOf: URL(filePath: path)), as: UTF8.self).contains("base64"))
        let materialized = try await storage.materialize(messages)
        #expect(materialized.first?["content"]?.arrayValue?.last?["image_url"]?["url"] == "data:image/png;base64,AQID")
        try FileManager.default.removeItem(at: image)
        #expect(try await storage.materialize(messages).first?["content"]?.arrayValue?.last?["type"] == "text")
    }
}
