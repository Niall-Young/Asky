import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Markdown image reads belong to the native ToolService module, never the agent or UI.
public actor ChatImageService {
    public static let shared = ChatImageService()
    private let session: URLSession
    private var cache: [URL: Data] = [:]
    private var order: [URL] = []
    private var cacheBytes = 0
    private static let downloadLimit = 10 * 1024 * 1024
    private static let cacheLimit = 32 * 1024 * 1024

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    public static func supports(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
            && url.user == nil && url.password == nil
    }

    public func imageData(from url: URL) async throws -> Data {
        guard Self.supports(url) else { throw URLError(.unsupportedURL) }
        if let data = cache[url] { return data }
        let data = try await remoteData(from: url)
        let thumbnail = try Self.thumbnail(data)
        // Another suspended request may have populated this URL in the meantime.
        if let existing = cache[url] { return existing }
        while cacheBytes + thumbnail.count > Self.cacheLimit, !order.isEmpty {
            let oldest = order.removeFirst()
            cacheBytes -= cache.removeValue(forKey: oldest)?.count ?? 0
        }
        if thumbnail.count <= Self.cacheLimit {
            cache[url] = thumbnail
            order.append(url)
            cacheBytes += thumbnail.count
        }
        return thumbnail
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
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileReadCorruptFile) }
        return output as Data
    }
}
