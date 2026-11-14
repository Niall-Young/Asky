import Foundation

/// Fetch preview content only when the reader asks to inspect a source.
public actor ChatLinkService {
    public struct Preview: Sendable {
        public var title: String?
        public var image: Data?
    }
    public static let shared = ChatLinkService()
    private var cache: [URL: Preview] = [:]
    private var order: [URL] = []

    public func preview(for url: URL) async throws -> Preview {
        guard ChatImageService.supports(url) else { throw URLError(.unsupportedURL) }
        if let cached = cache[url] { return cached }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              let base = response.url, ChatImageService.supports(base),
              response.mimeType == "text/html" else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            if data.count >= 512 * 1024 { break }
            data.append(byte)
        }
        let html = String(decoding: data, as: UTF8.self)
        let title = Self.meta("og:title", in: html) ?? Self.capture("<title[^>]*>([\\s\\S]*?)</title>", in: html)
        var preview = Preview(title: title.map(Self.decode), image: nil)
        if let source = Self.meta("og:image", in: html), let imageURL = URL(string: Self.decode(source), relativeTo: base)?.absoluteURL,
           ChatImageService.supports(imageURL) {
            preview.image = try? await ChatImageService.shared.imageData(from: imageURL)
        }
        try Task.checkCancellation()
        // Bound retained thumbnails as well as metadata.
        if cache[url] == nil { order.append(url) }
        cache[url] = preview
        while order.count > 8 { cache.removeValue(forKey: order.removeFirst()) }
        return preview
    }

    static func capture(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    static func meta(_ name: String, in html: String) -> String? {
        let expression = try? NSRegularExpression(pattern: "<meta\\b[^>]*>", options: .caseInsensitive)
        for match in expression?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? [] {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])
            if capture("(?:property|name)\\s*=\\s*([\"'])(.*?)\\1", in: tag, group: 2)?.lowercased() == name {
                return capture("content\\s*=\\s*([\"'])(.*?)\\1", in: tag, group: 2)
            }
        }
        return nil
    }

    static func decode(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
