import XCTest
@testable import ToolService

final class ChatLinkServiceTests: XCTestCase {
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
