import XCTest
@testable import ToolService

final class ChatLinkServiceTests: XCTestCase {
    func testDeclaredFaviconsResolveRelativeURLs() {
        let html = """
        <link rel="stylesheet" href="/style.css">
        <link href="/touch.png" rel="apple-touch-icon">
        <link href="../icon.png?v=1&amp;x=2" rel="shortcut icon">
        <link rel="icon" href="javascript:alert(1)">
        """
        let urls = ChatLinkService.iconURLs(in: html, base: URL(string: "https://example.com/docs/page")!)
        XCTAssertEqual(urls.map(\.absoluteString), ["https://example.com/icon.png?v=1&x=2", "https://example.com/touch.png"])
    }

    func testMetadataAttributeOrderAndEntities() {
        let html = """
        <meta content="A &amp; B" property="og:title">
        <meta property='og:image' content='/cover.png'>
        <meta name='description' content='Unrelated'>
        """
        XCTAssertEqual(ChatLinkService.meta("og:title", in: html).map(ChatLinkService.decode), "A & B")
        XCTAssertEqual(ChatLinkService.meta("og:image", in: html), "/cover.png")
        XCTAssertEqual(ChatLinkService.meta("og:title", in: "<meta property=\"og:title\" content=\"Devin's Security\">"), "Devin's Security")
        XCTAssertNil(ChatLinkService.meta("missing", in: html))
        XCTAssertEqual(ChatLinkService.capture("<title[^>]*>([\\s\\S]*?)</title>", in: "<TITLE>Fallback</TITLE>"), "Fallback")
    }
}
