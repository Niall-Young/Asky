import Foundation
import Darwin

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
        configuration.timeoutIntervalForResource = 3
        let session = URLSession(configuration: configuration, delegate: PublicPageRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, timeoutInterval: 3)
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
              url.user == nil, url.password == nil, let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")), host.contains("."),
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

final class PublicPageRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, WebPageImageService.publicURL(url.absoluteString) != nil,
              let host = url.host, Self.resolvesPublicly(host) else { completionHandler(nil); return }
        completionHandler(request)
    }

    private static func resolvesPublicly(_ host: String) -> Bool {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        var first: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &first) == 0, let first else { return false }
        defer { freeaddrinfo(first) }
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let entry = current {
            let address = entry.pointee
            switch address.ai_family {
            case AF_INET:
                let ipv4 = UnsafeRawPointer(address.ai_addr).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                let bytes = withUnsafeBytes(of: ipv4.s_addr) { Array($0) }
                guard Self.publicIPv4(bytes) else { return false }
            case AF_INET6:
                let ipv6 = UnsafeRawPointer(address.ai_addr).assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
                // Globally routable unicast. Reject local, mapped IPv4 and transition prefixes.
                let bytes = withUnsafeBytes(of: ipv6) { Array($0) }
                guard bytes[0] & 0xe0 == 0x20, !bytes.starts(with: [0x20, 0x02]),
                      !bytes.starts(with: [0x20, 0x01, 0, 0]) else { return false }
            default: return false
            }
            current = address.ai_next
        }
        return true
    }

    private static func publicIPv4(_ bytes: [UInt8]) -> Bool {
        let a = bytes[0], b = bytes[1]
        return a != 0 && a != 10 && a != 127 && a < 224
            && !(a == 100 && (64...127).contains(b)) && !(a == 169 && b == 254)
            && !(a == 172 && (16...31).contains(b)) && !(a == 192 && (b == 168 || b == 0))
            && !(a == 198 && (18...19).contains(b))
    }
}
