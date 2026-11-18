import Foundation

/// Bounded source metadata reads for native chat.
public actor ChatLinkService {
    public struct Preview: Sendable {
        public var title: String?
        public var siteName: String?
        public var publishedAt: String?
        public init(title: String? = nil, siteName: String? = nil, publishedAt: String? = nil) {
            self.title = title; self.siteName = siteName; self.publishedAt = publishedAt
        }
    }
    public static let shared = ChatLinkService()
    private var cache: [URL: Preview] = [:]
    private var order: [URL] = []
    private var requests: [URL: Task<Preview, Error>] = [:]

    public func preview(for url: URL) async throws -> Preview {
        guard ChatImageService.supports(url) else { throw URLError(.unsupportedURL) }
        if let cached = cache[url] { return cached }
        if let request = requests[url] { return try await request.value }
        let request = Task { try await self.loadPreview(for: url) }
        requests[url] = request
        do {
            let preview = try await request.value
            requests[url] = nil
            if cache[url] == nil { order.append(url) }
            cache[url] = preview
            while order.count > 32 { cache.removeValue(forKey: order.removeFirst()) }
            return preview
        } catch {
            requests[url] = nil
            throw error
        }
    }

    private func loadPreview(for url: URL) async throws -> Preview {
        let (html, _) = try await html(from: url)
        return Self.metadata(in: html)
    }

    static func metadata(in html: String) -> Preview {
        Preview(title: (meta("og:title", in: html) ?? capture("<title[^>]*>([\\s\\S]*?)</title>", in: html)).map(decode),
                siteName: meta("og:site_name", in: html).map(decode),
                publishedAt: (meta("article:published_time", in: html) ?? meta("date", in: html)).map(decode))
    }

    private func html(from url: URL) async throws -> (String, URL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: PublicPageRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("Asky/1.0", forHTTPHeaderField: "User-Agent")
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
        return (String(decoding: data, as: UTF8.self), base)
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
