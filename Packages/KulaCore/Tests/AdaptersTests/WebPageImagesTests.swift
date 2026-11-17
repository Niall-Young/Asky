import Foundation
import Testing
import Contracts
import LocalStore
import ToolService
@testable import Adapters

@Suite struct WebPageImagesTests {
    @Test func resolvesReferencesAndExcludesCodeLinksAndUnsupportedURLs() {
        let markdown = """
        ![水豚](../photos/capybara.jpg)
        ![重复](https://example.com/photos/capybara.jpg)
        ![山景][photo]

        [photo]: //cdn.example.com/mountain.jpg

        [普通网页](https://example.com/about)
        `![代码](https://example.com/code.jpg)`
        ![本地](http://localhost/a.png)
        ![凭据](https://user:pass@example.com/a.jpg)
        ![图标](https://example.com/icon.svg)
        ![内嵌](data:image/png;base64,AA)
        """
        let images = WebPageImages.candidates(in: markdown, sourceURL: "https://example.com/articles/animals")
        #expect(images.compactMap { $0["url"]?.stringValue } == [
            "https://example.com/photos/capybara.jpg", "https://cdn.example.com/mountain.jpg"])
        #expect(images.first?["alt"]?.stringValue == "水豚")
        #expect(images.allSatisfy { $0["sourceURL"] == "https://example.com/articles/animals" })
        let many = (0..<20).map { "![photo \($0)](https://example.com/\($0).jpg)" }.joined(separator: "\n\n")
        #expect(WebPageImages.candidates(in: many, sourceURL: "https://example.com").count == 8)
    }

    @Test func findsImagesBeyondTextLimitAndKeepsPlainReadFast() async throws {
        let tool = WebReadPageTool(call: { provider, _, _ in
            #expect(provider == .parallel)
            return ["structuredContent": ["results": [["full_content": .string(
                String(repeating: "文字", count: 12500) + "\n\n![照片](https://example.com/photo.jpg)")]]]]
        })
        let result = try await tool.execute(["url": "https://example.com/page"]).output
        #expect(result["text"]?.stringValue?.count == 24000)
        #expect(result["truncated"] == true)
        #expect(result["images"]?.arrayValue?.count == 1)
        #expect(result["attempts"]?.arrayValue?.count == 1)
    }

    @Test func imageReadUsesSeparateCacheAndFallsBackWhenTextHasNoImages() async throws {
        let tool = WebReadPageTool(call: { provider, _, _ in
            switch provider {
            case .parallel: return ["structuredContent": ["results": [["full_content": "Readable text, no images"]]]]
            case .exa: return ["content": [["type": "text", "text": "Title: Article\nURL: https://example.com/page\n![照片](https://example.com/photo.jpg)"]]]
            case .keenable: return ["url": "https://example.com/page", "content": "![照片](https://example.com/photo.jpg)", "truncated": false]
            }
        })
        let plain = try await tool.execute(["url": "https://example.com/page"]).output
        #expect(plain["images"]?.arrayValue?.isEmpty == true)
        #expect(plain["attempts"]?.arrayValue?.count == 1)
        let illustrated = try await tool.execute(["url": "https://example.com/page", "includeImages": true]).output
        #expect(illustrated["cached"] == false)
        #expect(illustrated["images"]?.arrayValue?.count == 1)
        #expect(illustrated["attempts"]?.arrayValue?.count == 2)
        let cached = try await tool.execute(["url": "https://example.com/page", "includeImages": true]).output
        #expect(cached["cached"] == true)
        #expect(cached["images"] == illustrated["images"])
    }

    @Test func optionalImageFailureRetainsSuccessfulTextAndRejectsBadArguments() async throws {
        let tool = WebReadPageTool(call: { provider, _, _ in
            if provider == .parallel { return ["structuredContent": ["results": [["full_content": "Useful text"]]]] }
            throw FreeWebFailure(status: "rate_limited", message: "HTTP 429")
        })
        let result = try await tool.execute(["url": "https://example.com/page", "includeImages": true]).output
        #expect(result["status"] == "read")
        #expect(result["text"] == "Useful text")
        #expect(result["imageStatus"] == "not_found_in_returned_content")
        #expect(result["attempts"]?.arrayValue?.count == 4)
        let never = WebReadPageTool(call: { _, _, _ in Issue.record("Bad argument reached network"); throw CancellationError() })
        do {
            _ = try await never.execute(["url": "https://example.com", "includeImages": "true"])
            Issue.record("Accepted string boolean")
        } catch let error as ToolError { #expect(error.code == .invalidArguments) }
    }

    @Test func usesPageMetadataOnlyWhenRequestedAndKeepsTextOnMetadataFailure() async throws {
        let call: FreeWebMCP.Call = { provider, _, _ in
            if provider == .parallel { return ["structuredContent": ["results": [["full_content": "Article"]]]] }
            throw FreeWebFailure(status: "unavailable", message: "offline")
        }
        let tool = WebReadPageTool(call: call, readImages: { url in
            [["url": "https://example.com/photo.jpg", "alt": "Photo", "sourceURL": .string(url)]]
        })
        let plain = try await tool.execute(["url": "https://example.com/page"]).output
        #expect(plain["images"]?.arrayValue?.isEmpty == true)
        let illustrated = try await tool.execute(["url": "https://example.com/page", "includeImages": true]).output
        #expect(illustrated["text"] == "Article")
        #expect(illustrated["images"]?.arrayValue?.count == 1)
        let broken = WebReadPageTool(call: call, readImages: { _ in throw URLError(.timedOut) })
        let retained = try await broken.execute(["url": "https://example.com/page", "includeImages": true]).output
        #expect(retained["status"] == "read")
        #expect(retained["text"] == "Article")
        #expect(retained["attempts"]?.arrayValue?.last?["status"] == "unavailable")
        let cancelled = WebReadPageTool(call: call, readImages: { _ in throw CancellationError() })
        do {
            _ = try await cancelled.execute(["url": "https://example.com/page", "includeImages": true])
            Issue.record("Cancellation swallowed")
        } catch is CancellationError { }
    }

    @Test func livePhotoReadThroughToolService() async throws {
        guard ProcessInfo.processInfo.environment["ASKY_LIVE_WEB_IMAGES"] == "1" else { return }
        let store = try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory)
        let service = ToolService(store: store, policy: { PolicySnapshot(enabledSources: [.web]) }, presenter: { _ in .rejected })
        await service.register(WebReadPageTool())
        let result = await service.submit(ActionRequest(tool: "web_read_page",
            arguments: ["url": "https://en.wikipedia.org/wiki/Capybara", "includeImages": true],
            origin: .agent(sessionID: "live-images"), intent: .explicitRequest))
        #expect(result.status == .completed)
        let images = result.output?["images"]?.arrayValue ?? []
        print("LIVE images: provider=\(result.output?["provider"]?.stringValue ?? "none") count=\(images.count)")
        #expect(!images.isEmpty)
        let photo = try #require(images.first { $0["url"]?.stringValue?.lowercased().contains("capybara") == true })
        let address = try #require(photo["url"]?.stringValue)
        let url = try #require(URL(string: address))
        let data = try await ChatImageService.shared.imageData(from: url)
        #expect(!data.isEmpty)
        print("LIVE image decoded by ChatImageService: \(data.count) bytes; \(url.absoluteString)")
    }
}
