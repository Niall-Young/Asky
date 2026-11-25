import Foundation
import Testing
@testable import ToolService

@Suite struct WebPageImageServiceTests {
    @Test func readsPhotoMetadataWithoutScriptsIconsOrCredentials() throws {
        let html = """
        <meta property="og:image" content="/preview.jpg">
        <meta property="og:image" content="/second.jpg">
        <script>const fake = '<img src="/fake.jpg">';</script>
        <!-- <img src="/comment.jpg"> -->
        <img src="/icon.svg" alt="icon">
        <img src="/pixel.png" width="1" height="1">
        <img src="https://user:pass@example.com/private.jpg">
        <img src="http://localhost/photo.jpg">
        <img data-src="//cdn.example.com/photo.jpg?a=1&amp;b=2" alt="水豚 &#x26; &#34;朋友&#34;" width="640">
        <img src=/second.jpg alt='Second > photo'>
        """
        let base = try #require(URL(string: "https://example.com/article"))
        let images = WebPageImageService.candidates(in: html, sourceURL: base)
        #expect(images.map(\.url) == ["https://cdn.example.com/photo.jpg?a=1&b=2", "https://example.com/second.jpg", "https://example.com/preview.jpg"])
        #expect(images.first?.alt == "水豚 & \"朋友\"")
        #expect(images.allSatisfy { $0.sourceURL == base.absoluteString })
    }

    @Test func limitsCandidatesAndValidatesRedirectTargets() throws {
        let html = (0..<40).map { "<img src='/\($0).jpg'>" }.joined()
        let base = try #require(URL(string: "https://example.com/article"))
        #expect(WebPageImageService.candidates(in: html, sourceURL: base).count == 8)
        for value in ["file:///photo.jpg", "http://127.0.0.1/p", "http://[::1]/p", "https://a.local/p", "https://user:pass@example.com"] {
            #expect(WebPageImageService.publicURL(value) == nil)
        }
    }

    @Test func filtersTrackerPixelsAndPreservesTitledSocialCoverWhenManyBodyImagesExist() throws {
        let bodyImages = (0..<10).map { "<img src='/sidebar-\($0).jpg'>" }.joined()
        let html = """
        <meta property="og:title" content="演员吴磊简介">
        <meta property="og:image" content="/cover-wulei.jpg">
        <img src="https://sb.scorecardresearch.com/p?c1=2&amp;c2=17813110">
        <img src="https://pixel.example.com/track.png">
        \(bodyImages)
        """
        let base = try #require(URL(string: "https://example.com/person"))
        let images = WebPageImageService.candidates(in: html, sourceURL: base)
        #expect(images.count == 8)
        #expect(!images.contains { $0.url.contains("scorecardresearch") || $0.url.contains("pixel.example.com") })
        #expect(images.last?.url == "https://example.com/cover-wulei.jpg")
        #expect(images.last?.alt == "演员吴磊简介")
    }
}
