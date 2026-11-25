import Contracts
import Foundation
import LocalStore
import XCTest
import os
@testable import ToolService

final class ChatLinkServiceTests: XCTestCase {
    func testSourceNameTitleAndDate() {
        let html = """
        <meta content="Cognition &amp; AI" property="og:site_name">
        <meta property='og:title' content='Devin Security'>
        <meta property="article:published_time" content="2026-10-26T09:00:00Z">
        """
        let source = ChatLinkService.metadata(in: html)
        XCTAssertEqual(source.siteName, "Cognition & AI")
        XCTAssertEqual(source.title, "Devin Security")
        XCTAssertEqual(source.publishedAt, "2026-10-26T09:00:00Z")
        let fallback = ChatLinkService.metadata(in: "<title>Fallback</title>")
        XCTAssertEqual(fallback.title, "Fallback")
        XCTAssertNil(fallback.siteName)
        XCTAssertNil(fallback.publishedAt)
    }

    func testMetadataAttributeOrderAndEntities() {
        let html = """
        <meta content="A &amp; B" property="og:title">
        <meta name='description' content='Unrelated'>
        """
        XCTAssertEqual(ChatLinkService.meta("og:title", in: html).map(ChatLinkService.decode), "A & B")
        XCTAssertEqual(ChatLinkService.meta("og:title", in: "<meta property=\"og:title\" content=\"Devin's Security\">"), "Devin's Security")
        XCTAssertNil(ChatLinkService.meta("missing", in: html))
        XCTAssertEqual(ChatLinkService.capture("<title[^>]*>([\\s\\S]*?)</title>", in: "<TITLE>Fallback</TITLE>"), "Fallback")
        XCTAssertEqual(ChatLinkService.decode("A &#x2014; B &mdash; C &#39;D&#39; &nbsp;"), "A — B — C 'D'")
    }

    func testUnquotedMetaJSONLDAndBlockedPlaceholders() {
        let html = """
        <html><head>
        <meta name=apple-mobile-web-app-title content="Title">
        <meta name=application-name content="Title">
        <title>Just a moment...</title>
        <script type="application/ld+json">
        {"headline":"Real Headline From JSON-LD","datePublished":"2026-11-18T10:00:00Z","publisher":{"name":"36氪"}}
        </script>
        </head></html>
        """
        let preview = ChatLinkService.metadata(in: html)
        XCTAssertEqual(preview.title, "Real Headline From JSON-LD")
        XCTAssertEqual(preview.siteName, "36氪")
        XCTAssertEqual(preview.publishedAt, "2026-11-18T10:00:00Z")
    }

    func testSiteNameSuffixInferenceAndHyphenSafety() {
        let krURL = URL(string: "https://m.36kr.com/p/4024942758268804")!
        XCTAssertEqual(
            ChatLinkService.inferSiteName(fromTitle: "刚刚，谷歌Gemini 4 Argon上线，API价格限时五折-36氪", url: krURL),
            "36氪"
        )
        XCTAssertEqual(
            ChatLinkService.inferSiteName(fromTitle: "Introducing Claude Opus | Anthropic", url: URL(string: "https://anthropic.com/news")!),
            "Anthropic"
        )
        // Technical hyphens without CJK or host-stem match must not be misidentified as a site name.
        XCTAssertNil(ChatLinkService.inferSiteName(fromTitle: "Benchmarking GPT-4o", url: URL(string: "https://example.com/post")!))
        XCTAssertNil(ChatLinkService.inferSiteName(fromTitle: "Release Notes 2026-11-19", url: URL(string: "https://example.com/post")!))
        // Homepage slogans containing clause/list punctuation must not be mistaken for site names.
        XCTAssertNil(ChatLinkService.inferSiteName(fromTitle: "百度开发者中心 - 汇聚、开放、助力、共赢", url: URL(string: "https://developer.baidu.com")!))
        XCTAssertNil(ChatLinkService.inferSiteName(fromTitle: "知乎 - 有问题，就会有答案", url: URL(string: "https://www.zhihu.com")!))
    }

    func testIconExtractionPrioritizesRasterAndSkipsEmptyDataURIs() {
        let base = URL(string: "https://news.example.com/article/1")!
        let html = """
        <link rel="icon" href="data:;base64,=">
        <link rel="icon" type="image/svg+xml" href="/logo.svg">
        <link rel="apple-touch-icon" sizes="180x180" href="/apple.png">
        <link rel="shortcut icon" sizes="32x32" href="/static/icon-32.png">
        """
        let icons = ChatLinkService.extractIconURLs(in: html, base: base)
        XCTAssertEqual(icons, [
            URL(string: "https://news.example.com/static/icon-32.png")!,
            URL(string: "https://news.example.com/apple.png")!
        ])
    }

    func testGB18030Decoding() {
        let raw = "<html><head><meta charset=\"gbk\"><title>中文财经标题 - 新浪财经</title></head></html>"
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringConvertIANACharSetNameToEncoding("gb18030" as CFString)))
        let data = raw.data(using: encoding)!
        let decoded = ChatLinkService.decodeHTML(data, textEncodingName: nil)
        let preview = ChatLinkService.metadata(in: decoded)
        XCTAssertEqual(preview.title, "中文财经标题 - 新浪财经")
        XCTAssertEqual(preview.siteName, "新浪财经")
    }

    func testHeadEarlyStopAndFaviconCaching() async throws {
        LinkFixtureProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LinkFixtureProtocol.self]
        let service = ChatLinkService(configuration: config)

        let url1 = URL(string: "https://fast.example.test/post-1")!
        let url2 = URL(string: "https://fast.example.test/post-2")!
        let preview1 = try await service.preview(for: url1)
        XCTAssertEqual(preview1.title, "Fast Article One")
        XCTAssertEqual(preview1.siteName, "FastSite")
        XCTAssertNotNil(preview1.favicon)
        XCTAssertEqual(service.cachedPreview(for: url1), preview1)

        // Second article on the same origin reuses cached origin favicon without re-fetching /favicon.ico.
        let preview2 = try await service.preview(for: url2)
        XCTAssertEqual(preview2.title, "Fast Article Two")
        XCTAssertEqual(preview2.favicon, preview1.favicon)
        XCTAssertEqual(LinkFixtureProtocol.count(for: URL(string: "https://fast.example.test/favicon.ico")!), 1)
    }

    func testSeededMetadataSurvivesEmptyWAFPageAndResolvesParentFavicon() async throws {
        LinkFixtureProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LinkFixtureProtocol.self]
        let service = ChatLinkService(configuration: config)

        let url = URL(string: "https://m.kr-fixture.test/p/4024942758268804")!
        service.seed(fromTool: "web_search", output: [
            "results": [
                [
                    "url": .string(url.absoluteString),
                    "title": .string("刚刚，谷歌Gemini 4 Argon上线-36氪"),
                    "publishedAt": .string("2026-11-19")
                ]
            ]
        ])

        // Synchronous snapshot is available immediately before any network call.
        let immediate = service.cachedPreview(for: url)
        XCTAssertEqual(immediate?.title, "刚刚，谷歌Gemini 4 Argon上线-36氪")
        XCTAssertEqual(immediate?.siteName, "36氪")
        XCTAssertEqual(immediate?.publishedAt, "2026-11-19")

        // Network call hits empty HTML + HTML-masked m.kr-fixture.test/favicon.ico,
        // preserves seeded title/date, and falls back to www.kr-fixture.test/favicon.ico.
        let enriched = try await service.preview(for: url)
        XCTAssertEqual(enriched.title, "刚刚，谷歌Gemini 4 Argon上线-36氪")
        XCTAssertEqual(enriched.siteName, "36氪")
        XCTAssertEqual(enriched.publishedAt, "2026-11-19")
        XCTAssertNotNil(enriched.favicon)
        XCTAssertEqual(LinkFixtureProtocol.count(for: URL(string: "https://www.kr-fixture.test/favicon.ico")!), 1)
    }

    func testSeedChatLinkPreviewsFromStoredExecutions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try LocalStore(inMemoryWithRoot: root)
        let executions = ExecutionStore(store)
        let now = Date()
        let url = URL(string: "https://m.36kr.com/p/999999")!
        try executions.upsert(ExecutionRecord(
            requestID: "req-1",
            tool: "web_search",
            argumentsDigest: "d1",
            origin: "agent:conv-1",
            taskID: "t1",
            status: .completed,
            result: ExecutionResult(requestID: "req-1", status: .completed, output: [
                "results": [[
                    "url": .string(url.absoluteString),
                    "title": .string("历史对话里的新闻标题 - 36氪"),
                    "publishedAt": .string("2026-11-18")
                ]]
            ]),
            createdAt: now,
            updatedAt: now
        ))
        let service = ChatLinkService(configuration: .ephemeral)
        ToolService.seedChatLinkPreviews(conversationIDs: ["conv-1"], in: store, into: service)
        let cached = service.cachedPreview(for: url)
        XCTAssertEqual(cached?.title, "历史对话里的新闻标题 - 36氪")
        XCTAssertEqual(cached?.siteName, "36氪")
        XCTAssertEqual(cached?.publishedAt, "2026-11-18")
    }
}

private final class LinkFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let counts = OSAllocatedUnfairLock(initialState: [URL: Int]())
    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jhV8AAAAASUVORK5CYII=")!

    static func reset() { counts.withLock { $0.removeAll() } }
    static func count(for url: URL) -> Int { counts.withLock { $0[url, default: 0] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.counts.withLock { $0[url, default: 0] += 1 }
        let host = url.host?.lowercased() ?? ""
        let path = url.path

        if host == "fast.example.test" {
            if path == "/favicon.ico" {
                respond(url: url, status: 200, mime: "image/png", body: Self.png)
                return
            }
            let title = path == "/post-1" ? "Fast Article One" : "Fast Article Two"
            let head = Data("<html><head><meta property=\"og:site_name\" content=\"FastSite\"><title>\(title)</title></head>".utf8)
            let hugeBody = Data(repeating: 0x41, count: 200_000)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html; charset=utf-8"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: head)
            client?.urlProtocol(self, didLoad: hugeBody)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if host == "m.kr-fixture.test" {
            // Simulates a WAF/JS stub returning HTML with empty <head> for both article and /favicon.ico.
            let stub = Data("<!DOCTYPE html><html><head><link rel=\"icon\" href=\"data:;base64,=\"></head><body></body></html>".utf8)
            respond(url: url, status: 200, mime: "text/html", body: stub)
            return
        }

        if host == "www.kr-fixture.test" && path == "/favicon.ico" {
            respond(url: url, status: 200, mime: "image/png", body: Self.png)
            return
        }

        respond(url: url, status: 404, mime: "text/plain", body: Data())
    }

    override func stopLoading() {}

    private func respond(url: URL, status: Int, mime: String, body: Data) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }
}
