import Foundation

/// Bounded, site-owned source previews and favicon reads for native chat.
public actor ChatLinkService {
    public struct Preview: Sendable {
        public var title: String?
        public var image: Data?
    }
    public static let shared = ChatLinkService()
    private var cache: [URL: Preview] = [:]
    private var order: [URL] = []

    private var icons: [URL: Data] = [:]
    private var iconOrder: [URL] = []
    private var missingIcons: Set<URL> = []
    private var iconTasks: [URL: Task<Data?, Never>] = [:]

    /// Site-owned icons only; no third-party favicon proxy receives browsing URLs.
    public func favicon(for url: URL) async -> Data? {
        guard ChatImageService.supports(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        guard let origin = components.url else { return nil }
        if let icon = icons[origin] { return icon }
        if missingIcons.contains(origin) { return nil }
        if let task = iconTasks[origin] { return await task.value }
        let task = Task { await self.loadFavicon(origin) }
        iconTasks[origin] = task
        let data = await task.value
        iconTasks[origin] = nil
        if let data { icons[origin] = data } else { missingIcons.insert(origin) }
        iconOrder.append(origin)
        while iconOrder.count > 64 {
            let oldest = iconOrder.removeFirst()
            icons[oldest] = nil
            missingIcons.remove(oldest)
        }
        return data
    }

    private func loadFavicon(_ origin: URL) async -> Data? {
        var candidates: [URL] = []
        if let (html, base) = try? await html(from: origin) {
            candidates = Self.iconURLs(in: html, base: base)
        }
        candidates.append(origin.appendingPathComponent("favicon.ico"))
        for url in candidates.prefix(5) {
            if let data = try? await ChatImageService.shared.imageData(from: url),
               let thumbnail = try? ChatImageService.thumbnail(data, maxPixelSize: 32) { return thumbnail }
        }
        return nil
    }

    static func iconURLs(in html: String, base: URL) -> [URL] {
        let expression = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: .caseInsensitive)
        var icons: [URL] = []
        for match in expression?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? [] {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])
            let rel = capture("\\brel\\s*=\\s*([\"'])(.*?)\\1", in: tag, group: 2)?.lowercased().split(whereSeparator: \.isWhitespace) ?? []
            guard rel.contains("icon") || rel.contains("apple-touch-icon"),
                  let href = capture("\\bhref\\s*=\\s*([\"'])(.*?)\\1", in: tag, group: 2),
                  let url = URL(string: decode(href), relativeTo: base)?.absoluteURL,
                  ChatImageService.supports(url), !icons.contains(url) else { continue }
            if rel.contains("icon") { icons.insert(url, at: 0) } else { icons.append(url) }
        }
        return icons
    }

    public func preview(for url: URL) async throws -> Preview {
        guard ChatImageService.supports(url) else { throw URLError(.unsupportedURL) }
        if let cached = cache[url] { return cached }
        let (html, base) = try await html(from: url)
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

    private func html(from url: URL) async throws -> (String, URL) {
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
