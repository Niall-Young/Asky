import Foundation
import Darwin

/// On-demand public HTML metadata and Wikipedia REST lookup for chat illustrations. No cookies or files.
public enum WebPageImageService {
    public struct Candidate: Sendable, Equatable {
        public let url: String
        public let alt: String
        public let sourceURL: String
        public let width: Int?
        public let height: Int?

        public init(url: String, alt: String, sourceURL: String, width: Int? = nil, height: Int? = nil) {
            self.url = url
            self.alt = alt
            self.sourceURL = sourceURL
            self.width = width
            self.height = height
        }
    }

    public typealias DimensionProbe = @Sendable ([URL]) async -> [URL: ChatImageService.ImageDimensions?]

    public static func images(from address: String) async throws -> [Candidate] {
        try await images(from: address, probe: { urls in
            await ChatImageService.shared.probeIllustrations(urls)
        })
    }

    static func images(from address: String, probe: DimensionProbe) async throws -> [Candidate] {
        guard let url = publicURL(address) else { throw URLError(.unsupportedURL) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 3
        let session = URLSession(configuration: configuration, delegate: PublicPageRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        if let wiki = wikipediaArticle(from: url) {
            let wikiCandidates = await fetchWikipediaCandidates(wiki, sourceURL: url, session: session)
            if !wikiCandidates.isEmpty {
                let verified = await filterByProbe(wikiCandidates, limit: 8, probe: probe)
                if !verified.isEmpty { return verified }
            }
        }

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
        let raw = candidates(in: String(decoding: data, as: UTF8.self), sourceURL: finalURL, limit: 12)
        return await filterByProbe(raw, limit: 8, probe: probe)
    }

    static func filterByProbe(_ raw: [Candidate], limit: Int = 8, probe: DimensionProbe) async -> [Candidate] {
        guard !raw.isEmpty else { return [] }
        let urls = raw.compactMap { URL(string: $0.url) }
        let probed = await probe(urls)
        var verified: [Candidate] = []
        var inconclusive: [Candidate] = []
        for candidate in raw {
            guard let url = URL(string: candidate.url) else { continue }
            if let entry = probed[url] {
                guard let dims = entry else { continue } // Conclusively failed or tiny UI icon.
                verified.append(Candidate(url: candidate.url, alt: candidate.alt, sourceURL: candidate.sourceURL,
                                          width: dims.width, height: dims.height))
            } else {
                // Timed out before probe finished; keep only as trailing fallback so publication validation decides.
                inconclusive.append(candidate)
            }
        }
        return Array((verified + inconclusive).prefix(limit))
    }

    static func publicURL(_ value: String) -> URL? {
        guard value.count <= 4096, let url = URL(string: value),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")), host.contains("."),
              !host.contains(":"), !host.allSatisfy({ $0.isNumber || $0 == "." }),
              !["localhost", "local", "internal", "test", "invalid"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
        return url
    }

    private static let trackerHostSuffixes = [
        "scorecardresearch.com",
        "doubleclick.net",
        "google-analytics.com",
        "googletagmanager.com",
        "googlesyndication.com",
        "adservice.google.com",
        "quantserve.com",
        "chartbeat.net",
        "omtrdc.net"
    ]

    private static let noiseDirectorySegments = [
        "/icons/", "/icon/", "/sprites/", "/sprite/", "/emoji/", "/emojis/",
        "/badges/", "/avatars/", "/avatar/"
    ]

    private static let noiseTokenRegex = try! NSRegularExpression(
        pattern: #"(?<![a-z0-9])(favicon|sprite|sprites|spacer|blank|transparent|1x1|pixel|spinner|loading|placeholder|qrcode|arrow|arrows|chevron|caret|rating|ratings|score-\d+|dianping-score|btn|ic|icon|icons|badge|badges)(?![a-z])"#,
        options: .caseInsensitive
    )

    private static let chromeClassRegex = try! NSRegularExpression(
        pattern: #"(?<![a-z0-9])(icon|icons|arrow|arrows|chevron|caret|sprite|badge|badges|avatar|emoji|spinner|loading|placeholder|rating|star|qrcode|qr|btn-icon|nav-icon|logo-icon)(?![a-z])"#,
        options: .caseInsensitive
    )

    private static let inlinePixelDimensionRegex = try! NSRegularExpression(
        pattern: #"(?i)(?:^|;)\s*(?:max-)?(width|height)\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*px\b"#
    )

    private static let inlineHiddenStyleRegex = try! NSRegularExpression(
        pattern: #"(?i)(?:^|;)\s*(?:display\s*:\s*none|visibility\s*:\s*hidden|opacity\s*:\s*0(?:\.0+)?(?:\s|;|$))"#
    )

    public static func isLikelyTrackerOrNoise(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        if trackerHostSuffixes.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return true
        }
        if host.hasPrefix("pixel.") || host.hasPrefix("beacon.") || host.hasPrefix("metrics.") {
            return true
        }
        let path = url.path.lowercased()
        if (host == "www.facebook.com" || host == "facebook.com") && path == "/tr" {
            return true
        }
        if noiseDirectorySegments.contains(where: { path.contains($0) }) {
            return true
        }
        let filename = url.deletingPathExtension().lastPathComponent
        let filenameRange = NSRange(location: 0, length: (filename as NSString).length)
        if noiseTokenRegex.firstMatch(in: filename, range: filenameRange) != nil {
            return true
        }
        return false
    }

    // MARK: - Wikipedia REST API fast-path

    struct WikipediaArticle: Equatable {
        let lang: String
        let encodedTitle: String
    }

    private static let wikipediaIgnoredNamespaces = [
        "special:", "file:", "help:", "category:", "talk:", "portal:", "wikipedia:", "template:", "module:",
        "特殊:", "文件:", "分类:", "维基百科:", "模板:", "讨论:", "帮助:"
    ]

    static func wikipediaArticle(from url: URL) -> WikipediaArticle? {
        guard let host = url.host?.lowercased() else { return nil }
        let parts = host.split(separator: ".")
        let lang: String
        if parts.count == 3, parts[1] == "wikipedia", parts[2] == "org" {
            lang = String(parts[0])
        } else if parts.count == 4, parts[1] == "m", parts[2] == "wikipedia", parts[3] == "org" {
            lang = String(parts[0])
        } else {
            return nil
        }
        guard !lang.isEmpty, lang != "www", lang.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        let path = url.path
        guard path.hasPrefix("/wiki/") else { return nil }
        let rawTitle = String(path.dropFirst("/wiki/".count))
        guard !rawTitle.isEmpty, !rawTitle.contains("/") else { return nil }
        let lowerTitle = rawTitle.lowercased()
        if wikipediaIgnoredNamespaces.contains(where: { lowerTitle.hasPrefix($0) }) { return nil }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?&")
        guard let encoded = rawTitle.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return WikipediaArticle(lang: lang, encodedTitle: encoded)
    }

    private static func fetchWikipediaCandidates(_ article: WikipediaArticle, sourceURL: URL,
                                                 session: URLSession) async -> [Candidate] {
        let summaryURL = URL(string: "https://\(article.lang).wikipedia.org/api/rest_v1/page/summary/\(article.encodedTitle)")
        let mediaListURL = URL(string: "https://\(article.lang).wikipedia.org/api/rest_v1/page/media-list/\(article.encodedTitle)")
        async let summaryData = fetchJSON(summaryURL, session: session)
        async let mediaListData = fetchJSON(mediaListURL, session: session)
        return wikipediaCandidates(mediaListData: await mediaListData, summaryData: await summaryData, sourceURL: sourceURL)
    }

    private static func fetchJSON(_ url: URL?, session: URLSession) async -> Data? {
        guard let url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Asky/1.0", forHTTPHeaderField: "User-Agent")
        guard let (bytes, response) = try? await session.bytes(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        var data = Data()
        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                if data.count >= 512 * 1024 { break }
                data.append(byte)
            }
            return data
        } catch {
            return nil
        }
    }

    static func wikipediaCandidates(mediaListData: Data?, summaryData: Data?, sourceURL: URL) -> [Candidate] {
        var summaryTitle = ""
        var summaryLead: Candidate?
        if let summaryData,
           let json = try? JSONSerialization.jsonObject(with: summaryData) as? [String: Any] {
            let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let description = (json["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            summaryTitle = description.isEmpty ? title : "\(title)（\(description)）"
            for key in ["originalimage", "thumbnail"] {
                if let img = json[key] as? [String: Any],
                   let raw = img["source"] as? String,
                   let resolved = URL(string: raw, relativeTo: sourceURL)?.absoluteURL,
                   publicURL(resolved.absoluteString) != nil,
                   !["svg", "ico"].contains(resolved.pathExtension.lowercased()),
                   !isLikelyTrackerOrNoise(resolved) {
                    let width = img["width"] as? Int
                    let height = img["height"] as? Int
                    if let width, let height, !ChatImageService.isAcceptableIllustration(width: width, height: height) {
                        continue
                    }
                    summaryLead = Candidate(url: resolved.absoluteString, alt: String(summaryTitle.prefix(300)),
                                            sourceURL: sourceURL.absoluteString, width: width, height: height)
                    break
                }
            }
        }

        var leadPhotos: [Candidate] = []
        var bodyPhotos: [Candidate] = []
        var diagramPhotos: [Candidate] = []

        if let mediaListData,
           let json = try? JSONSerialization.jsonObject(with: mediaListData) as? [String: Any],
           let items = json["items"] as? [[String: Any]] {
            for item in items {
                guard (item["type"] as? String) == "image",
                      (item["showInGallery"] as? Bool) != false,
                      let srcset = item["srcset"] as? [[String: Any]], !srcset.isEmpty else { continue }
                let bestSrc = srcset.max { lhs, rhs in
                    let ls = Double(((lhs["scale"] as? String) ?? "1x").trimmingCharacters(in: CharacterSet(charactersIn: "xX"))) ?? 1
                    let rs = Double(((rhs["scale"] as? String) ?? "1x").trimmingCharacters(in: CharacterSet(charactersIn: "xX"))) ?? 1
                    return ls < rs
                }?["src"] as? String ?? srcset.first?["src"] as? String
                guard let bestSrc,
                      let resolved = URL(string: bestSrc, relativeTo: sourceURL)?.absoluteURL,
                      publicURL(resolved.absoluteString) != nil,
                      !["svg", "ico"].contains(resolved.pathExtension.lowercased()),
                      !isLikelyTrackerOrNoise(resolved) else { continue }

                let isLead = (item["leadImage"] as? Bool) == true
                let captionText = ((item["caption"] as? [String: Any])?["text"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let fileTitle = (item["title"] as? String) ?? ""
                let cleanedTitle = fileTitle.replacingOccurrences(of: #"^(?:File|Image|文件):"#, with: "", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: "_", with: " ")
                let alt: String
                if !captionText.isEmpty {
                    alt = String(captionText.prefix(300))
                } else if isLead && !summaryTitle.isEmpty {
                    alt = String(summaryTitle.prefix(300))
                } else {
                    alt = String(cleanedTitle.prefix(300))
                }

                let candidate = Candidate(url: resolved.absoluteString, alt: alt, sourceURL: sourceURL.absoluteString)
                let isRasterizedSVG = fileTitle.lowercased().hasSuffix(".svg") || resolved.path.lowercased().contains(".svg/")
                if isLead && !isRasterizedSVG {
                    leadPhotos.append(candidate)
                } else if isRasterizedSVG {
                    diagramPhotos.append(candidate)
                } else {
                    bodyPhotos.append(candidate)
                }
            }
        }

        // Prefer curated 1280px lead thumbnail from media-list (fast to load) or summary originalimage,
        // deduplicated by Wikimedia filename so the same photo isn't returned twice.
        var seenFiles = Set<String>()
        var combined: [Candidate] = []
        let ordered = leadPhotos + (summaryLead.map { [$0] } ?? []) + bodyPhotos + diagramPhotos
        for candidate in ordered {
            let key = wikimediaDedupKey(candidate.url)
            if seenFiles.insert(key).inserted {
                combined.append(candidate)
            }
            if combined.count == 10 { break }
        }
        return combined
    }

    private static func wikimediaDedupKey(_ rawURL: String) -> String {
        guard let url = URL(string: rawURL) else { return rawURL }
        let path = url.path.lowercased()
        // Wikimedia thumb paths look like /wikipedia/commons/thumb/a/ab/Name.jpg/1280px-Name.jpg
        if let range = path.range(of: "/thumb/") {
            let rest = path[range.upperBound...]
            let parts = rest.split(separator: "/")
            if parts.count >= 3 { return String(parts[2]) }
        }
        return url.lastPathComponent.lowercased()
    }

    // MARK: - HTML Extraction with Chrome Stripping

    static func candidates(in html: String, sourceURL: URL, limit: Int = 8) -> [Candidate] {
        // Match only image metadata/attributes; never execute scripts or render the page.
        let cleaned = html.replacingOccurrences(of: #"(?is)<!--.*?-->|<(script|style)\b[^>]*>.*?</\1\s*>"#,
            with: "", options: .regularExpression)
        let metaTags = try! NSRegularExpression(pattern: #"(?is)<meta\b(?:[^>"']|"[^"]*"|'[^']*')*>"#)
        let imgTags = try! NSRegularExpression(pattern: #"(?is)<img\b(?:[^>"']|"[^"]*"|'[^']*')*>"#)
        let attributes = try! NSRegularExpression(pattern: #"(?is)([a-z_:][a-z0-9_:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#)

        func parseAttributes(_ tag: NSString) -> [String: String] {
            var values: [String: String] = [:]
            for attr in attributes.matches(in: tag as String, range: NSRange(location: 0, length: tag.length)) {
                let key = tag.substring(with: attr.range(at: 1)).lowercased()
                if let range = (2...4).map({ attr.range(at: $0) }).first(where: { $0.location != NSNotFound }) {
                    values[key] = decodeEntities(tag.substring(with: range))
                }
            }
            return values
        }

        // 1. Extract <meta> social previews & title from full cleaned HTML (including <head>).
        let cleanedNS = cleaned as NSString
        var social: [Candidate] = []
        var pageTitle: String?
        for match in metaTags.matches(in: cleaned, range: NSRange(location: 0, length: cleanedNS.length)) {
            let values = parseAttributes(cleanedNS.substring(with: match.range) as NSString)
            let metaKey = (values["property"] ?? values["name"] ?? "").lowercased()
            if pageTitle == nil, ["og:title", "twitter:title"].contains(metaKey),
               let title = values["content"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                pageTitle = String(title.prefix(160))
                continue
            }
            guard ["og:image", "og:image:url", "twitter:image", "twitter:image:src"].contains(metaKey),
                  let raw = values["content"],
                  let url = URL(string: raw, relativeTo: sourceURL)?.absoluteURL,
                  publicURL(url.absoluteString) != nil,
                  !["svg", "ico"].contains(url.pathExtension.lowercased()),
                  !isLikelyTrackerOrNoise(url) else { continue }
            social.append(Candidate(url: url.absoluteString, alt: "", sourceURL: sourceURL.absoluteString))
            if social.count >= 8 { break }
        }
        if pageTitle == nil,
           let titleRegex = try? NSRegularExpression(pattern: #"(?is)<title\b[^>]*>(.*?)</title\s*>"#),
           let match = titleRegex.firstMatch(in: cleaned, range: NSRange(location: 0, length: cleanedNS.length)) {
            let text = decodeEntities(cleanedNS.substring(with: match.range(at: 1)))
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { pageTitle = String(text.prefix(160)) }
        }

        // 2. Strip navigation, footer, sidebar, form, and button chrome before scanning <img> tags.
        let bodyHTML = cleaned.replacingOccurrences(
            of: #"(?is)<(nav|footer|aside|button|svg|template|form)\b[^>]*>.*?</\1\s*>"#,
            with: "", options: .regularExpression
        )
        let bodyNS = bodyHTML as NSString
        var captionedPhotos: [Candidate] = []
        var uncaptionedPhotos: [Candidate] = []
        for match in imgTags.matches(in: bodyHTML, range: NSRange(location: 0, length: bodyNS.length)) {
            let values = parseAttributes(bodyNS.substring(with: match.range) as NSString)
            if isLikelyDecorativeImage(values) { continue }
            guard let raw = values["data-src"] ?? values["src"],
                  let url = URL(string: raw, relativeTo: sourceURL)?.absoluteURL,
                  publicURL(url.absoluteString) != nil,
                  !["svg", "ico"].contains(url.pathExtension.lowercased()),
                  !isLikelyTrackerOrNoise(url) else { continue }
            let rawAlt = String((values["alt"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
            let candidate = Candidate(url: url.absoluteString, alt: rawAlt, sourceURL: sourceURL.absoluteString)
            if rawAlt.isEmpty {
                uncaptionedPhotos.append(candidate)
            } else {
                captionedPhotos.append(candidate)
            }
            if captionedPhotos.count + uncaptionedPhotos.count >= 32 { break }
        }

        // 3. Rank: captioned body photos first, then titled og:image cover, then uncaptioned fallback images.
        let titledSocial = social.map { candidate -> Candidate in
            guard candidate.alt.isEmpty, let pageTitle else { return candidate }
            return Candidate(url: candidate.url, alt: pageTitle, sourceURL: candidate.sourceURL)
        }
        var seen = Set<String>()
        let uniqueCaptioned = captionedPhotos.filter { seen.insert($0.url).inserted }
        let uniqueSocial = titledSocial.filter { seen.insert($0.url).inserted }
        let uniqueUncaptioned = uncaptionedPhotos.filter { seen.insert($0.url).inserted }

        if uniqueCaptioned.count >= limit, let primarySocial = uniqueSocial.first {
            return Array(uniqueCaptioned.prefix(max(0, limit - 1))) + [primarySocial]
        }
        let hasTitledSocial = pageTitle != nil && !uniqueSocial.isEmpty
        let ordered = hasTitledSocial
            ? (uniqueCaptioned + uniqueSocial + uniqueUncaptioned)
            : (uniqueCaptioned + uniqueUncaptioned + uniqueSocial)
        return Array(ordered.prefix(limit))
    }

    private static func isLikelyDecorativeImage(_ values: [String: String]) -> Bool {
        if values["aria-hidden"]?.lowercased() == "true" { return true }
        if let role = values["role"]?.lowercased(), ["presentation", "none"].contains(role) { return true }
        for key in ["width", "height"] {
            if let raw = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                let numeric = raw.hasSuffix("px") ? String(raw.dropLast(2)) : raw
                if let px = Double(numeric), px < 120 { return true }
            }
        }
        if let style = values["style"], !style.isEmpty {
            let range = NSRange(location: 0, length: (style as NSString).length)
            if inlineHiddenStyleRegex.firstMatch(in: style, range: range) != nil { return true }
            for match in inlinePixelDimensionRegex.matches(in: style, range: range) {
                let numStr = (style as NSString).substring(with: match.range(at: 2))
                if let px = Double(numStr), px < 120 { return true }
            }
        }
        for key in ["class", "id"] {
            if let value = values[key], !value.isEmpty {
                let range = NSRange(location: 0, length: (value as NSString).length)
                if chromeClassRegex.firstMatch(in: value, range: range) != nil { return true }
            }
        }
        return false
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
