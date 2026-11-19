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
        guard case .plainText(let text) = try await file.load() else {
            Issue.record("Expected an empty text preview")
            return
        }
        #expect(text.isEmpty)
    }
}
