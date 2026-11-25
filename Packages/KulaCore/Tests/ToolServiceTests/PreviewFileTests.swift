import Foundation
import Testing
import ToolService

struct PreviewFileTests {
    @Test(arguments: ["notes.txt", "events.log", "table.TSV", "settings.yaml", "Cargo.toml",
                      "index.html", "main.tsx", "query.sql", "Makefile", "Dockerfile", ".gitignore"])
    func recognizesCommonTextFiles(_ name: String) {
        let file = PreviewFile(url: URL(filePath: "/tmp").appending(path: name))
        guard case .plainText? = file else {
            Issue.record("Expected plain text for \(name)")
            return
        }
    }

    @Test func checksTextBeforeDisplayingIt() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try #require(PreviewFile(url: url))
        for data in [Data([65, 0, 66]), Data([0xC0, 0xAF]), Data(repeating: 65, count: 2 * 1024 * 1024 + 1)] {
            try data.write(to: url)
            await #expect(throws: CocoaError.self) { try await file.load() }
        }
        try Data().write(to: url)
        guard case .plainText(let text, let highlights) = try await file.load() else {
            Issue.record("Expected an empty text preview")
            return
        }
        #expect(text.isEmpty && highlights.isEmpty)
    }

    @Test func highlightsSourceFilesOnly() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "main.swift"), notes = root.appending(path: "notes.txt")
        try Data("let name = \"Asky\"".utf8).write(to: source)
        try Data("let name = \"Asky\"".utf8).write(to: notes)
        guard case .plainText(_, let code)? = try await PreviewFile(url: source)?.load(),
              case .plainText(_, let prose)? = try await PreviewFile(url: notes)?.load() else {
            Issue.record("Expected text previews")
            return
        }
        #expect(code.first == SyntaxHighlight(.keyword, location: 0, length: 3))
        #expect(prose.isEmpty)
    }
}
