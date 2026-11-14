import XCTest
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
    }
}
