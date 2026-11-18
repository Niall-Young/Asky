import Foundation
import CoreGraphics
import LocalStore
import Resources
import UniformTypeIdentifiers

public enum PreviewFile: Sendable {
    case image(URL)
    case markdown(URL)

    public enum Content: Sendable {
        case image(CGImage)
        case markdown(String, directory: URL)
    }

    public var url: URL {
        switch self {
        case .image(let url), .markdown(let url): url
        }
    }

    public init?(url: URL) {
        guard url.isFileURL else { return nil }
        let ext = url.pathExtension.lowercased()
        if ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"].contains(ext) {
            self = .markdown(url)
        } else if UTType(filenameExtension: ext)?.conforms(to: .image) == true {
            self = .image(url)
        } else {
            return nil
        }
    }

    public init?(clipboardItem: ClipboardItem) {
        switch clipboardItem.kind {
        case .image:
            guard let path = clipboardItem.filePath else { return nil }
            self = .image(URL(filePath: path))
        case .file:
            guard clipboardItem.filePaths.count == 1, let path = clipboardItem.filePaths.first else { return nil }
            self.init(url: URL(filePath: path))
        case .text:
            return nil
        }
    }

    public func load() async throws -> Content {
        try await Self.read {
            let url = self.url.resolvingSymlinksInPath()
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw CocoaError(.fileReadUnknown)
            }
            switch self {
            case .image:
                guard let image = ThumbnailService.decode(url: url, maxPixelSize: 4096) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return .image(image)
            case .markdown:
                let limit = 2 * 1024 * 1024
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: limit + 1) ?? Data()
                guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
                let encoding: String.Encoding = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
                    ? .utf16 : .utf8
                guard let markdown = String(data: data, encoding: encoding) else {
                    throw CocoaError(.fileReadInapplicableStringEncoding)
                }
                return .markdown(markdown, directory: url.deletingLastPathComponent())
            }
        }
    }

    public static func loadMarkdownImage(at url: URL, in directory: URL, maxPixelSize: Int) async -> CGImage? {
        try? await read {
            guard url.isFileURL else { return nil }
            let root = directory.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            let image = url.absoluteURL.resolvingSymlinksInPath().standardizedFileURL
            guard image.pathComponents.starts(with: root),
                  case .image? = PreviewFile(url: image),
                  try image.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { return nil }
            return ThumbnailService.decode(url: image, maxPixelSize: maxPixelSize)
        }
    }

    private static func read<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try operation()
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
