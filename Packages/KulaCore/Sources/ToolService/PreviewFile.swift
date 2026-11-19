import Foundation
import CoreGraphics
import LocalStore
import Resources
import UniformTypeIdentifiers

public enum PreviewFile: Sendable {
    case image(URL)
    case markdown(URL)
    case plainText(URL)

    public enum Content: Sendable {
        case image(CGImage)
        case markdown(String, directory: URL)
        case plainText(String)
    }

    public var url: URL {
        switch self {
        case .image(let url), .markdown(let url), .plainText(let url): url
        }
    }

    public var isRegularFile: Bool {
        (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    // Cover common formats even when no installed app has registered their type.
    private static let textExtensions: Set<String> = [
        "txt", "log", "csv", "tsv", "json", "jsonc", "jsonl", "ndjson", "xml", "yaml", "yml",
        "toml", "ini", "conf", "cfg", "properties", "env", "editorconfig", "diff", "patch",
        "c", "h", "cc", "cpp", "hpp", "m", "mm", "swift", "java", "kt", "kts", "scala",
        "cs", "go", "rs", "py", "rb", "php", "lua", "r", "sql", "sh", "bash", "zsh", "fish",
        "html", "htm", "css", "scss", "sass", "less", "js", "jsx", "mjs", "cjs", "ts", "tsx",
        "mts", "cts", "vue", "svelte", "dart", "proto", "graphql", "cmake"
    ]
    private static let textNames: Set<String> = [
        "dockerfile", "containerfile", "makefile", "gemfile", "rakefile", "readme", "license",
        ".env", ".gitignore", ".gitattributes", ".editorconfig", ".dockerignore", ".npmrc",
        ".bashrc", ".zshrc", ".zprofile"
    ]

    public init?(url: URL) {
        guard url.isFileURL else { return nil }
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)
        if ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"].contains(ext) {
            self = .markdown(url)
        } else if type?.conforms(to: .image) == true {
            self = .image(url)
        } else if Self.textExtensions.contains(ext) || Self.textNames.contains(url.lastPathComponent.lowercased())
                    || type?.conforms(to: .plainText) == true || type?.conforms(to: .sourceCode) == true {
            self = .plainText(url)
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
            case .markdown, .plainText:
                let limit = 2 * 1024 * 1024
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: limit + 1) ?? Data()
                guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
                let encoding: String.Encoding = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
                    ? .utf16 : .utf8
                guard let text = String(data: data, encoding: encoding), !text.utf8.contains(0) else {
                    throw CocoaError(.fileReadInapplicableStringEncoding)
                }
                if case .markdown = self {
                    return .markdown(text, directory: url.deletingLastPathComponent())
                }
                return .plainText(text)
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
