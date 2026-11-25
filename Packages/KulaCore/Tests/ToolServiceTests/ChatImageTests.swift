import AppKit
import Foundation
import Testing
@testable import ToolService

struct ChatImageTests {
    @Test func publicationChecksDecodeAllImagesRejectTinyIconsAndPopulateTheDisplayCache() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageFixtureProtocol.self]
        let service = ChatImageService(session: URLSession(configuration: configuration))
        let root = "https://images.example/" + UUID().uuidString + "/"
        let good = URL(string: root + "good.png")!
        let tiny = URL(string: root + "tiny.png")!
        let strip = URL(string: root + "strip.png")!
        let broken = URL(string: root + "404.png")!
        let html = URL(string: root + "html.png")!
        #expect(try await service.availableImages([good, tiny, strip, broken, html]) == [good])
        #expect(!(try await service.imageData(from: good)).isEmpty)
        #expect(ImageFixtureProtocol.counts.count(for: good) == 1, "UI reuses the decoded thumbnail")
        #expect(ImageFixtureProtocol.counts.count(for: tiny) == 1)
        #expect(ImageFixtureProtocol.counts.count(for: strip) == 1)
        #expect(ImageFixtureProtocol.counts.count(for: broken) == 1)
        #expect(ImageFixtureProtocol.counts.count(for: html) == 1)
    }

    @Test func probeIllustrationsReturnsRealDimensionsAndSeparatesRejectionsFromTimeouts() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageFixtureProtocol.self]
        let service = ChatImageService(session: URLSession(configuration: configuration))
        let root = "https://images.example/" + UUID().uuidString + "/"
        let good = URL(string: root + "good.png")!
        let tiny = URL(string: root + "tiny.png")!
        let slow = URL(string: root + "slow.png")!
        let probed = await service.probeIllustrations([good, tiny, slow], budget: .milliseconds(300), maxConcurrent: 3)
        #expect(probed[good] == .some(ChatImageService.ImageDimensions(width: 320, height: 240)))
        #expect(probed.keys.contains(tiny) && probed[tiny]! == nil)
        #expect(!probed.keys.contains(slow))
    }

    @Test func illustrationDimensionThresholdsRejectIconsAndStripsWhileKeepingPhotos() {
        #expect(!ChatImageService.isAcceptableIllustration(width: 32, height: 32))
        #expect(!ChatImageService.isAcceptableIllustration(width: 64, height: 64))
        #expect(!ChatImageService.isAcceptableIllustration(width: 128, height: 128))
        #expect(!ChatImageService.isAcceptableIllustration(width: 150, height: 150))
        #expect(!ChatImageService.isAcceptableIllustration(width: 800, height: 40))
        #expect(!ChatImageService.isAcceptableIllustration(width: 1000, height: 150))
        #expect(ChatImageService.isAcceptableIllustration(width: 180, height: 180))
        #expect(ChatImageService.isAcceptableIllustration(width: 250, height: 140))
        #expect(ChatImageService.isAcceptableIllustration(width: 330, height: 219))
        #expect(ChatImageService.isAcceptableIllustration(width: 1280, height: 853))
    }

    @Test func publicationDeadlineKeepsGoodImagesAndCancelsSlowReads() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageFixtureProtocol.self]
        let service = ChatImageService(session: URLSession(configuration: configuration))
        let good = URL(string: "https://images.example/good.png")!
        let slow = URL(string: "https://images.example/slow.png")!
        let start = ContinuousClock.now
        #expect(try await service.availableImages([good, slow]) == [good])
        #expect(start.duration(to: .now) < .seconds(7))
    }

    @Test func onlyRemoteImageURLsAreAccepted() {
        #expect(ChatImageService.supports(URL(string: "https://example.com/image.png")!))
        #expect(ChatImageService.supports(URL(string: "http://localhost/image.png")!))
        for value in ["file:///etc/passwd", "data:image/png;base64,AAAA", "https://user:password@example.com/a"] {
            #expect(!ChatImageService.supports(URL(string: value)!))
        }
    }

    @Test func rejectsInvalidImageData() {
        #expect(throws: (any Error).self) { try ChatImageService.thumbnail(Data("not an image".utf8)) }
    }

    @Test func downsamplesLargeImagesPreservingAspectRatio() throws {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3200, pixelsHigh: 1600,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        let input = try #require(bitmap.representation(using: .png, properties: [:]))
        let output = try ChatImageService.thumbnail(input)
        let image = try #require(NSBitmapImageRep(data: output))
        #expect(image.pixelsWide == 1600)
        #expect(image.pixelsHigh == 800)
    }

    @Test func downloadsPreserveOriginalPixelsAndNeverOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3200, pixelsHigh: 1600,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let source = URL(string: "https://example.com/photo.jpg?token=test")!
        let first = try ChatImageService.saveImage(data, source: source, directory: directory)
        let second = try ChatImageService.saveImage(data, source: source, directory: directory)
        #expect(first.lastPathComponent == "photo.png")
        #expect(second.lastPathComponent == "photo (1).png")
        #expect(try Data(contentsOf: first) == data)
        #expect(try Data(contentsOf: second) == data)
        #expect(try #require(NSBitmapImageRep(data: Data(contentsOf: first))).pixelsWide == 3200)
    }
}

private final class ImageFixtureCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URL: Int] = [:]
    func record(_ url: URL) { lock.withLock { values[url, default: 0] += 1 } }
    func count(for url: URL) -> Int { lock.withLock { values[url, default: 0] } }
}

private final class ImageFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let counts = ImageFixtureCounts()
    private static let goodPNG = makePNG(width: 320, height: 240)
    private static let tinyPNG = makePNG(width: 32, height: 32)
    private static let stripPNG = makePNG(width: 800, height: 40)

    private static func makePNG(width: Int, height: Int) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        return bitmap.representation(using: .png, properties: [:])!
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.counts.record(url)
        if url.lastPathComponent == "slow.png" { return } // URLSession cancellation must release the read.
        let status = url.lastPathComponent == "404.png" ? 404 : 200
        let data: Data
        switch url.lastPathComponent {
        case "html.png": data = Data("<html>not an image</html>".utf8)
        case "tiny.png": data = Self.tinyPNG
        case "strip.png": data = Self.stripPNG
        default: data = Self.goodPNG
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
