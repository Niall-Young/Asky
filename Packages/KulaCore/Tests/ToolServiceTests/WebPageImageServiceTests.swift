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

    @Test func filtersTrackerPixelsAndPrioritizesTitledSocialCoverOverUncaptionedBodyImages() throws {
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
        #expect(images.first?.url == "https://example.com/cover-wulei.jpg")
        #expect(images.first?.alt == "演员吴磊简介")
    }

    @Test func stripsNavFooterButtonChromeAndDecorativeIconsWithoutBlockingRealSubjects() throws {
        let html = """
        <nav><img src="/nav-banner.jpg" alt="nav"></nav>
        <footer><img src="/footer-qr.png" alt="qr"></footer>
        <aside><img src="/aside-ad.jpg" alt="ad"></aside>
        <button><img src="/next-step.png"></button>
        <main>
          <img src="/ui/right-arrow.png">
          <img src="https://pages.c-ctrip.com/you/livestream/gs-dianping-score-5.png">
          <img src="/opaque-1.png" class="nav-arrow-icon">
          <img src="/opaque-2.png" style="width: 24px; height: 24px;">
          <img src="/opaque-3.png" aria-hidden="true">
          <img src="/opaque-4.png" role="presentation">
          <img src="/photos/sparrow.jpg" alt="麻雀">
          <img src="/photos/silicon-valley.jpg" alt="硅谷">
        </main>
        """
        let base = try #require(URL(string: "https://example.com/guide"))
        let images = WebPageImageService.candidates(in: html, sourceURL: base)
        #expect(images.map(\.url) == [
            "https://example.com/photos/sparrow.jpg",
            "https://example.com/photos/silicon-valley.jpg"
        ])
    }

    @Test func parsesWikipediaArticleURLsAndRESTMediaCandidates() throws {
        let zh = try #require(URL(string: "https://zh.wikipedia.org/wiki/%E5%8D%83%E5%B2%9B%E6%B9%96"))
        let mobile = try #require(URL(string: "https://en.m.wikipedia.org/wiki/Capybara"))
        let special = try #require(URL(string: "https://zh.wikipedia.org/wiki/Special:Search"))
        #expect(WebPageImageService.wikipediaArticle(from: zh) == .init(lang: "zh", encodedTitle: "%E5%8D%83%E5%B2%9B%E6%B9%96"))
        #expect(WebPageImageService.wikipediaArticle(from: mobile) == .init(lang: "en", encodedTitle: "Capybara"))
        #expect(WebPageImageService.wikipediaArticle(from: special) == nil)

        let summary = Data("""
        {
          "title": "千岛湖",
          "description": "浙江水库",
          "originalimage": {
            "source": "https://upload.wikimedia.org/wikipedia/commons/6/6f/Thousand_Island_Lake.JPG",
            "width": 3008,
            "height": 2000
          }
        }
        """.utf8)
        let mediaList = Data("""
        {
          "items": [
            {
              "title": "File:Thousand_Island_Lake.JPG",
              "leadImage": true,
              "type": "image",
              "showInGallery": true,
              "srcset": [
                {"src": "//thumb.wikimedia.org/wikipedia/commons/thumb/6/6f/Thousand_Island_Lake.JPG/500px-Thousand_Island_Lake.JPG", "scale": "1x"},
                {"src": "//thumb.wikimedia.org/wikipedia/commons/thumb/6/6f/Thousand_Island_Lake.JPG/1280px-Thousand_Island_Lake.JPG", "scale": "2x"}
              ]
            },
            {
              "title": "File:Tiny_flag_icon.png",
              "leadImage": false,
              "type": "image",
              "showInGallery": false,
              "srcset": [{"src": "//thumb.wikimedia.org/wikipedia/commons/thumb/1/11/Tiny_flag_icon.png/20px-Tiny_flag_icon.png", "scale": "1x"}]
            },
            {
              "title": "File:Qiandaohu.svg",
              "leadImage": false,
              "type": "image",
              "showInGallery": true,
              "srcset": [{"src": "//thumb.wikimedia.org/wikipedia/commons/thumb/4/43/Qiandaohu.svg/500px-Qiandaohu.svg.png", "scale": "1x"}]
            },
            {
              "title": "File:Dam.jpg",
              "leadImage": false,
              "type": "image",
              "showInGallery": true,
              "caption": {"text": "泄洪中的新安江水电站"},
              "srcset": [{"src": "//thumb.wikimedia.org/wikipedia/commons/thumb/8/87/Dam.jpg/1280px-Dam.jpg", "scale": "2x"}]
            }
          ]
        }
        """.utf8)
        let images = WebPageImageService.wikipediaCandidates(mediaListData: mediaList, summaryData: summary, sourceURL: zh)
        #expect(images.map(\.url) == [
            "https://thumb.wikimedia.org/wikipedia/commons/thumb/6/6f/Thousand_Island_Lake.JPG/1280px-Thousand_Island_Lake.JPG",
            "https://thumb.wikimedia.org/wikipedia/commons/thumb/8/87/Dam.jpg/1280px-Dam.jpg",
            "https://thumb.wikimedia.org/wikipedia/commons/thumb/4/43/Qiandaohu.svg/500px-Qiandaohu.svg.png"
        ])
        #expect(images[0].alt == "千岛湖（浙江水库）")
        #expect(images[1].alt == "泄洪中的新安江水电站")
    }

    @Test func filterByProbeDropsTinyIconsEnrichesDimensionsAndKeepsSlowFallbacksLast() async throws {
        let iconURL = try #require(URL(string: "https://dimg04.c-ctrip.com/images/25t0e12000gkhucin9310_W_2048_1536.png"))
        let photoURL = try #require(URL(string: "https://example.com/real-photo.jpg"))
        let slowURL = try #require(URL(string: "https://example.com/slow-photo.jpg"))
        let raw = [
            WebPageImageService.Candidate(url: iconURL.absoluteString, alt: "", sourceURL: "https://example.com"),
            WebPageImageService.Candidate(url: slowURL.absoluteString, alt: "慢图", sourceURL: "https://example.com"),
            WebPageImageService.Candidate(url: photoURL.absoluteString, alt: "千岛湖实景", sourceURL: "https://example.com")
        ]
        let filtered = await WebPageImageService.filterByProbe(raw, limit: 8) { _ in
            [
                iconURL: nil,
                photoURL: ChatImageService.ImageDimensions(width: 1280, height: 853)
            ]
        }
        #expect(filtered.map(\.url) == [photoURL.absoluteString, slowURL.absoluteString])
        #expect(filtered.first?.width == 1280)
        #expect(filtered.first?.height == 853)
        #expect(filtered.last?.width == nil)
    }

    @Test func liveQiandaohuWikipediaAndCtripExcludeTinyArrowIcons() async throws {
        guard ProcessInfo.processInfo.environment["ASKY_LIVE_WEB_IMAGES"] == "1" else { return }
        let wikiImages = try await WebPageImageService.images(from: "https://zh.wikipedia.org/wiki/%E5%8D%83%E5%B2%9B%E6%B9%96")
        print("LIVE wiki 千岛湖 count=\(wikiImages.count) first=\(wikiImages.first.map { "\($0.url) (\($0.width ?? 0)x\($0.height ?? 0)) alt=\($0.alt)" } ?? "none")")
        #expect(!wikiImages.isEmpty)
        #expect(wikiImages.first?.alt.isEmpty == false)
        for image in wikiImages {
            if let width = image.width, let height = image.height {
                #expect(ChatImageService.isAcceptableIllustration(width: width, height: height))
            }
        }
        let ctripImages = try await WebPageImageService.images(from: "https://you.ctrip.com/sight/chunan2249/16656.html")
        print("LIVE ctrip 千岛湖 count=\(ctripImages.count) urls=\(ctripImages.map { "\($0.url) (\($0.width ?? 0)x\($0.height ?? 0))" })")
        #expect(!ctripImages.contains { $0.url.contains("25t0e12000gkhucin9310") || $0.url.contains("gs-dianping-score") })
        for image in ctripImages {
            if let width = image.width, let height = image.height {
                #expect(ChatImageService.isAcceptableIllustration(width: width, height: height))
            }
        }
    }
}
