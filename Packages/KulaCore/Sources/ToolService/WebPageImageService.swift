import Foundation

/// On-demand public HTML metadata lookup for chat illustrations. No cookies or files.
public enum WebPageImageService {
    public struct Candidate: Sendable {
        public let url: String
        public let alt: String
        public let sourceURL: String
    }

    public static func images(from address: String) async throws -> [Candidate] {
        guard let url = publicURL(address) else { throw URLError(.unsupportedURL) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration, delegate: PublicPageRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("Asky/1.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              let finalURL = response.url, publicURL(finalURL.absoluteString) != nil,
              ["text/html", "application/xhtml+xml"].contains(response.mimeType?.lowercased() ?? "") else {
            throw URLError(.badServerResponse)
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            if data.count >= 2 * 1024 * 1024 { break }
            data.append(byte)
        }
        return candidates(in: String(decoding: data, as: UTF8.self), sourceURL: finalURL)
    }

    static func publicURL(_ value: String) -> URL? {
        guard value.count <= 4096, let url = URL(string: value),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, let host = url.host?.lowercased(), host.contains("."),
              !host.contains(":"), !host.allSatisfy({ $0.isNumber || $0 == "." }),
              !["localhost", "local", "internal", "test", "invalid"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
        return url
    }

    static func candidates(in html: String, sourceURL: URL) -> [Candidate] {
        // Match only image metadata/attributes; never execute scripts or render the page.
        let content = html.replacingOccurrences(of: #"(?is)<!--.*?-->|<(script|style)\b[^>]*>.*?</\1\s*>"#,
            with: "", options: .regularExpression)
        let tags = try! NSRegularExpression(pattern: #"(?is)<(meta|img)\b(?:[^>"']|"[^"]*"|'[^']*')*>"#)
        let attributes = try! NSRegularExpression(pattern: #"(?is)([a-z_:][a-z0-9_:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#)
        let ns = content as NSString
        var photos: [Candidate] = [], social: [Candidate] = []
        for match in tags.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range) as NSString
            var values: [String: String] = [:]
            for attr in attributes.matches(in: tag as String, range: NSRange(location: 0, length: tag.length)) {
                let key = tag.substring(with: attr.range(at: 1)).lowercased()
                if let range = (2...4).map({ attr.range(at: $0) }).first(where: { $0.location != NSNotFound }) {
                    values[key] = decodeEntities(tag.substring(with: range))
                }
            }
            let isMeta = ns.substring(with: match.range(at: 1)).lowercased() == "meta"
            let raw: String?
            if isMeta {
                guard ["og:image", "og:image:url", "twitter:image", "twitter:image:src"].contains((values["property"] ?? values["name"] ?? "").lowercased()) else { continue }
                raw = values["content"]
            } else {
                if ["width", "height"].contains(where: { key in
                    values[key].flatMap(Int.init).map { $0 < 120 } ?? false
                }) { continue }
                raw = values["data-src"] ?? values["src"]
            }
            guard let raw, let url = URL(string: raw, relativeTo: sourceURL)?.absoluteURL,
                  publicURL(url.absoluteString) != nil,
                  !["svg", "ico"].contains(url.pathExtension.lowercased()) else { continue }
            let candidate = Candidate(url: url.absoluteString, alt: String((values["alt"] ?? "").prefix(300)), sourceURL: sourceURL.absoluteString)
            if isMeta { social.append(candidate) } else { photos.append(candidate) }
            if social.count + photos.count >= 32 { break }
        }
        // In-page captions are stronger evidence of subject identity than social previews.
        var seen = Set<String>()
        return Array((photos + social).filter { seen.insert($0.url).inserted }.prefix(8))
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        let numeric = try! NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#)
        let ns = result as NSString
        for match in numeric.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed() {
            let code = ns.substring(with: match.range(at: 1))
            let value = code.hasPrefix("x") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
            if let value, let scalar = UnicodeScalar(value), let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: String(scalar))
            }
        }
        for (entity, value) in [("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }
}

private final class PublicPageRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.flatMap { WebPageImageService.publicURL($0.absoluteString) } == nil ? nil : request)
    }
}
