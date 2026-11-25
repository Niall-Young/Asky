import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Markdown image reads belong to the native ToolService module, never the agent or UI.
public actor ChatImageService {
    public struct ImageDimensions: Sendable, Equatable {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    private struct CachedImage {
        let data: Data
        let dimensions: ImageDimensions
    }

    public static let shared = ChatImageService()
    private let session: URLSession
    private var cache: [URL: CachedImage] = [:]
    private var order: [URL] = []
    private var cacheBytes = 0
    private static let downloadLimit = 10 * 1024 * 1024
    private static let cacheLimit = 32 * 1024 * 1024
    private static let minIllustrationShortSide = 120
    private static let minIllustrationLongSide = 180
    private static let minIllustrationArea = 28_000
    private static let maxIllustrationAspectRatio = 4

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: PublicPageRedirects(), delegateQueue: nil)
    }

    init(session: URLSession) { self.session = session }

    public static func supports(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
            && url.user == nil && url.password == nil
    }

    /// Reject UI icons, tiny thumbnails, tracking pixels, and ultra-thin strips/banners
    /// regardless of misleading URL parameters (e.g. `_W_2048_1536` on a 32x32 arrow icon).
    public static func isAcceptableIllustration(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0 else { return false }
        let shortSide = min(width, height)
        let longSide = max(width, height)
        guard shortSide >= minIllustrationShortSide, longSide >= minIllustrationLongSide else { return false }
        guard Int64(width) * Int64(height) >= Int64(minIllustrationArea) else { return false }
        return longSide <= shortSide * maxIllustrationAspectRatio
    }

    public func imageData(from url: URL) async throws -> Data {
        try await loadCachedImage(from: url).data
    }

    /// Decode an illustration, warm the thumbnail cache, and enforce minimum illustration pixel dimensions.
    public func illustrationDimensions(from url: URL) async throws -> ImageDimensions {
        let cached = try await loadCachedImage(from: url)
        guard Self.isAcceptableIllustration(width: cached.dimensions.width, height: cached.dimensions.height) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return cached.dimensions
    }

    private func loadCachedImage(from url: URL) async throws -> CachedImage {
        guard Self.supports(url) else { throw URLError(.unsupportedURL) }
        if let existing = cache[url] { return existing }
        let data = try await remoteData(from: url)
        let decoded = try Self.thumbnailWithDimensions(data)
        // Another suspended request may have populated this URL in the meantime.
        if let existing = cache[url] { return existing }
        while cacheBytes + decoded.data.count > Self.cacheLimit, !order.isEmpty {
            let oldest = order.removeFirst()
            cacheBytes -= cache.removeValue(forKey: oldest)?.data.count ?? 0
        }
        if decoded.data.count <= Self.cacheLimit {
            cache[url] = decoded
            order.append(url)
            cacheBytes += decoded.data.count
        }
        return decoded
    }

    /// Verify every selected illustration before publication and warm the UI's thumbnail cache.
    /// Rejects broken URLs, non-images, tiny icons, and ultra-thin strips within a five-second budget.
    public func availableImages(_ urls: [URL]) async throws -> Set<URL> {
        let probed = await probeIllustrations(urls, budget: .seconds(5), maxConcurrent: 3)
        try Task.checkCancellation()
        return Set(probed.compactMap { url, dimensions in
            dimensions != nil ? url : nil
        })
    }

    /// Probe candidate illustration URLs concurrently within a tight budget.
    /// Map values distinguish:
    /// - `.some(dimensions)`: verified acceptable illustration (cached for instant UI display)
    /// - `.some(nil)`: conclusively failed download/decode or failed illustration dimension gate
    /// - missing key: timed out before completion
    public func probeIllustrations(_ urls: [URL], budget: Duration = .milliseconds(2500),
                                   maxConcurrent: Int = 4) async -> [URL: ImageDimensions?] {
        let candidates = Array(Set(urls)).sorted { $0.absoluteString < $1.absoluteString }
        guard !candidates.isEmpty else { return [:] }
        let concurrency = max(1, min(maxConcurrent, candidates.count))
        return await withTaskGroup(of: (URL?, ImageDimensions?).self) { group in
            group.addTask {
                try? await Task.sleep(for: budget)
                return (nil, nil)
            }
            func enqueue(_ url: URL) {
                group.addTask {
                    do { return (url, try await self.illustrationDimensions(from: url)) }
                    catch { return (url, nil) }
                }
            }
            for url in candidates.prefix(concurrency) { enqueue(url) }
            var next = concurrency, completed = 0
            var results: [URL: ImageDimensions?] = [:]
            for await (url, dimensions) in group {
                guard let url else { group.cancelAll(); break }
                completed += 1
                results[url] = dimensions
                if completed == candidates.count { group.cancelAll(); break }
                if next < candidates.count { enqueue(candidates[next]); next += 1 }
            }
            return results
        }
    }

    /// The explicit download action saves the original image, not the display thumbnail.
    public func download(from url: URL) async throws -> URL {
        let data = try await remoteData(from: url)
        let directory = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        return try Self.saveImage(data, source: url, directory: directory)
    }

    private func remoteData(from url: URL) async throws -> Data {
        guard Self.supports(url) else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url)
        request.setValue("Asky/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              response.url.map(Self.supports) == true else { throw URLError(.badServerResponse) }
        guard response.expectedContentLength <= Self.downloadLimit else { throw URLError(.dataLengthExceedsMaximum) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < Self.downloadLimit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }

    static func saveImage(_ data: Data, source url: URL, directory: URL) throws -> URL {
        guard let image = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(image),
              let type = UTType(identifier as String), type.conforms(to: .image),
              let fileExtension = type.preferredFilenameExtension else { throw CocoaError(.fileReadCorruptFile) }
        var name = url.deletingPathExtension().lastPathComponent
        name = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != ":" && $0 != "/" }.prefix(120))
        if name.isEmpty || name == "." || name == ".." { name = "Asky-image" }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for suffix in 0..<10000 {
            let filename = name + (suffix == 0 ? "" : " (\(suffix))") + "." + fileExtension
            let destination = directory.appendingPathComponent(filename)
            do {
                try data.write(to: destination, options: .withoutOverwriting)
                return destination
            } catch let error as CocoaError where error.code == .fileWriteFileExists { continue }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    static func thumbnail(_ data: Data) throws -> Data {
        try thumbnailWithDimensions(data).data
    }

    private static func thumbnailWithDimensions(_ data: Data) throws -> CachedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let dimensions = sourceDimensions(from: source) ?? ImageDimensions(width: image.width, height: image.height)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileReadCorruptFile) }
        return CachedImage(data: output as Data, dimensions: dimensions)
    }

    private static func sourceDimensions(from source: CGImageSource) -> ImageDimensions? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let rawHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              rawWidth > 0, rawHeight > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if (5...8).contains(orientation) {
            return ImageDimensions(width: rawHeight, height: rawWidth)
        }
        return ImageDimensions(width: rawWidth, height: rawHeight)
    }
}
