import Contracts
import Foundation
import ImageIO
import UniformTypeIdentifiers
import os

/// Bounded source metadata and origin favicon reads for native chat.
public actor ChatLinkService {
    public struct Preview: Sendable, Equatable {
        public var title: String?
        public var siteName: String?
        public var publishedAt: String?
        public var favicon: Data?
        public init(title: String? = nil, siteName: String? = nil, publishedAt: String? = nil, favicon: Data? = nil) {
            self.title = title
            self.siteName = siteName
            self.publishedAt = publishedAt
            self.favicon = favicon
        }
    }

    private struct SnapshotState {
        var previews: [URL: Preview] = [:]
        var previewOrder: [URL] = []
        var completed: Set<URL> = []
        var favicons: [URL: Data] = [:]
        var faviconOrder: [URL] = []
        var missingFavicons: Set<URL> = []
    }

    public static let shared = ChatLinkService()

    private static let maxPreviewCache = 256
    private static let maxFaviconCache = 128
    private static let maxHeadBytes = 128 * 1024
    private static let maxFaviconBytes = 256 * 1024
    private static let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    private static let htmlAccept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    private static let acceptLanguage = "zh-CN,zh;q=0.9,en;q=0.8"

    private let snapshot = OSAllocatedUnfairLock(initialState: SnapshotState())
    private let session: URLSession
    private let streamDelegate: LinkStreamDelegate
    private var requests: [URL: Task<Preview, Error>] = [:]
    private var waiters: [URL: [UUID: @Sendable (Preview) -> Void]] = [:]
    private var faviconTasks: [URL: Task<Data?, Never>] = [:]

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 6
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let delegate = LinkStreamDelegate()
        self.streamDelegate = delegate
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    init(configuration: URLSessionConfiguration) {
        let delegate = LinkStreamDelegate()
        self.streamDelegate = delegate
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    // MARK: - Synchronous Cache & Seeding

    /// Instant thread-safe lookup for zero-flash UI rendering.
    public nonisolated func cachedPreview(for url: URL) -> Preview? {
        guard ChatImageService.supports(url) else { return nil }
        let origin = Self.origin(of: url)
        return snapshot.withLock { state in
            let favicon = origin.flatMap { state.favicons[$0] }
            if var preview = state.previews[url] {
                if preview.favicon == nil { preview.favicon = favicon }
                return preview
            }
            if let favicon {
                return Preview(favicon: favicon)
            }
            return nil
        }
    }

    /// True once a network lookup has already completed for this URL.
    public nonisolated func hasCompletedLookup(for url: URL) -> Bool {
        snapshot.withLock { $0.completed.contains(url) }
    }

    /// Seed known metadata (e.g. from web_search or web_read_page) without overwriting richer HTML values.
    public nonisolated func seed(url: URL, title: String?, siteName: String? = nil, publishedAt: String? = nil) {
        guard ChatImageService.supports(url) else { return }
        let cleanedTitle = title.flatMap { Self.cleanTitle($0, url: url) }
        let explicitSite = siteName.flatMap(Self.cleanSiteName)
        let inferredSite = explicitSite ?? cleanedTitle.flatMap { Self.inferSiteName(fromTitle: $0, url: url) }
        let cleanedDate = publishedAt.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        guard cleanedTitle != nil || inferredSite != nil || cleanedDate != nil else { return }
        let incoming = Preview(title: cleanedTitle, siteName: inferredSite, publishedAt: cleanedDate)
        snapshot.withLock { state in
            let existing = state.previews[url]
            let merged = Preview(
                title: existing?.title ?? incoming.title,
                siteName: existing?.siteName ?? incoming.siteName,
                publishedAt: existing?.publishedAt ?? incoming.publishedAt,
                favicon: existing?.favicon
            )
            Self.storePreview(merged, for: url, in: &state, markCompleted: false)
        }
    }

    /// Extract and seed link previews from completed web_search / web_read_page tool outputs.
    public nonisolated func seed(fromTool tool: String, output: JSONValue?) {
        guard let output else { return }
        switch tool {
        case "web_search":
            for row in output["results"]?.arrayValue ?? [] {
                guard let rawURL = row["url"]?.stringValue, let url = URL(string: rawURL) else { continue }
                seed(url: url,
                     title: row["title"]?.stringValue,
                     siteName: row["siteName"]?.stringValue,
                     publishedAt: row["publishedAt"]?.stringValue)
            }
        case "web_read_page":
            guard let rawURL = output["url"]?.stringValue, let url = URL(string: rawURL) else { return }
            seed(url: url, title: output["title"]?.stringValue)
        default:
            break
        }
    }

    // MARK: - Async Preview & Prefetch

    public func preview(for url: URL, onUpdate: (@Sendable (Preview) -> Void)? = nil) async throws -> Preview {
        guard ChatImageService.supports(url) else { throw URLError(.unsupportedURL) }
        if hasCompletedLookup(for: url), let cached = cachedPreview(for: url) {
            return cached
        }
        let token = onUpdate.map { callback -> UUID in
            let id = UUID()
            waiters[url, default: [:]][id] = callback
            return id
        }
        defer {
            if let token {
                waiters[url]?.removeValue(forKey: token)
                if waiters[url]?.isEmpty == true { waiters.removeValue(forKey: url) }
            }
        }
        if let request = requests[url] { return try await request.value }
        let request = Task { try await self.loadPreview(for: url) }
        requests[url] = request
        do {
            let preview = try await request.value
            requests[url] = nil
            return preview
        } catch {
            requests[url] = nil
            throw error
        }
    }

    private func notify(_ url: URL, preview: Preview) {
        guard let callbacks = waiters[url]?.values else { return }
        for callback in callbacks { callback(preview) }
    }

    private func notifyOrigin(_ origin: URL) {
        for (url, callbacks) in waiters where Self.origin(of: url) == origin {
            if let current = cachedPreview(for: url) {
                for callback in callbacks.values { callback(current) }
            }
        }
    }

    public func prefetch(_ urls: [URL], concurrency: Int = 4) async {
        let pending = urls.filter { ChatImageService.supports($0) && !hasCompletedLookup(for: $0) }
        guard !pending.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var iterator = pending.makeIterator()
            for _ in 0..<min(max(1, concurrency), pending.count) {
                if let url = iterator.next() {
                    group.addTask { _ = try? await self.preview(for: url) }
                }
            }
            for await _ in group {
                guard !Task.isCancelled else { group.cancelAll(); return }
                if let next = iterator.next() {
                    group.addTask { _ = try? await self.preview(for: next) }
                }
            }
        }
    }

    private func loadPreview(for url: URL) async throws -> Preview {
        let origin = Self.origin(of: url)
        let existingFavicon = origin.flatMap { currentOrigin in
            snapshot.withLock { state -> (Data?, Bool) in
                (state.favicons[currentOrigin], state.missingFavicons.contains(currentOrigin))
            }
        }

        let needSpeculativeRootIcon = origin != nil && existingFavicon?.0 == nil && existingFavicon?.1 != true

        // Fetch HTML <head> and speculative origin/favicon.ico in parallel to save a full RTT.
        async let htmlOutcome: (ParsedPage, URL)? = {
            guard let (html, base) = try? await self.fetchHeadHTML(from: url) else { return nil }
            return (Self.parseHTML(html, base: base, fallbackURL: url), base)
        }()

        async let speculativeRootIcon: Data? = {
            guard needSpeculativeRootIcon, let origin else { return nil }
            let rootIconURL = origin.appendingPathComponent("favicon.ico")
            let data = await self.fetchFaviconData(from: rootIconURL)
            if let data {
                self.snapshot.withLock { state in
                    Self.storeFavicon(data, for: origin, in: &state)
                }
                await self.notifyOrigin(origin)
            }
            return data
        }()

        let pageResult = await htmlOutcome
        let htmlPreview = pageResult?.0.preview ?? Preview()
        let discoveredIcons = pageResult?.0.iconURLs ?? []

        // Publish HTML metadata to snapshot immediately if it arrived before favicon fallback completes.
        if htmlPreview.title != nil || htmlPreview.siteName != nil || htmlPreview.publishedAt != nil {
            let partial = snapshot.withLock { state -> Preview in
                var merged = Self.mergeHTML(htmlPreview, onto: state.previews[url])
                if merged.favicon == nil, let origin { merged.favicon = state.favicons[origin] }
                Self.storePreview(merged, for: url, in: &state, markCompleted: false)
                return merged
            }
            notify(url, preview: partial)
        }

        let favicon: Data?
        if let cached = existingFavicon?.0 {
            favicon = cached
        } else if existingFavicon?.1 == true && discoveredIcons.isEmpty {
            favicon = nil
        } else if let origin {
            let rootData = await speculativeRootIcon
            favicon = await resolveFavicon(origin: origin, pageBase: pageResult?.1 ?? url,
                                           discoveredIcons: discoveredIcons, speculativeRootIcon: rootData)
        } else {
            favicon = nil
        }

        let enrichedPreview = Preview(
            title: htmlPreview.title,
            siteName: htmlPreview.siteName,
            publishedAt: htmlPreview.publishedAt,
            favicon: favicon
        )

        let hadAnySourceData = pageResult != nil || favicon != nil
        let finalPreview = snapshot.withLock { state -> Preview in
            let existing = state.previews[url]
            var merged = Self.mergeHTML(enrichedPreview, onto: existing)
            if merged.favicon == nil, let origin { merged.favicon = state.favicons[origin] }
            let hasContent = merged.title != nil || merged.siteName != nil || merged.publishedAt != nil || merged.favicon != nil
            if hasContent {
                // Only mark completed when we fetched the page or obtained meaningful metadata;
                // transient failures remain retryable on later hovers.
                Self.storePreview(merged, for: url, in: &state, markCompleted: pageResult != nil || merged.title != nil)
            } else if pageResult != nil {
                // Page responded cleanly with empty metadata; avoid spinning on every hover.
                state.completed.insert(url)
            }
            return merged
        }

        if !hadAnySourceData && finalPreview.title == nil && finalPreview.siteName == nil && finalPreview.favicon == nil {
            throw URLError(.badServerResponse)
        }
        return finalPreview
    }

    private func resolveFavicon(origin: URL, pageBase: URL, discoveredIcons: [URL], speculativeRootIcon: Data?) async -> Data? {
        if let cached = snapshot.withLock({ $0.favicons[origin] }) { return cached }
        if let task = faviconTasks[origin] { return await task.value }

        let task = Task<Data?, Never> {
            let rootIconURL = origin.appendingPathComponent("favicon.ico")
            // Prefer an explicit <link rel="icon"> if it points somewhere other than /favicon.ico.
            let nonRootDiscovered = discoveredIcons.filter { $0.absoluteString != rootIconURL.absoluteString }
            for iconURL in nonRootDiscovered.prefix(2) {
                if Task.isCancelled { return nil }
                if let data = await self.fetchFaviconData(from: iconURL) {
                    return data
                }
            }
            if let speculativeRootIcon {
                return speculativeRootIcon
            }
            for candidate in Self.parentFaviconCandidates(for: pageBase, excluding: origin) {
                if Task.isCancelled { return nil }
                if let data = await self.fetchFaviconData(from: candidate) {
                    return data
                }
            }
            return nil
        }

        faviconTasks[origin] = task
        let result = await task.value
        faviconTasks[origin] = nil

        snapshot.withLock { state in
            if let result {
                Self.storeFavicon(result, for: origin, in: &state)
            } else {
                state.missingFavicons.insert(origin)
            }
        }
        if result != nil { notifyOrigin(origin) }
        return result
    }

    // MARK: - Network Readers

    private func fetchHeadHTML(from url: URL) async throws -> (String, URL) {
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.htmlAccept, forHTTPHeaderField: "Accept")
        request.setValue(Self.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await streamDelegate.fetch(request: request, on: session, kind: .html(maxBytes: Self.maxHeadBytes))
        guard let base = response.url, ChatImageService.supports(base) else { throw URLError(.badServerResponse) }
        return (Self.decodeHTML(data, textEncodingName: response.textEncodingName), base)
    }

    private func fetchFaviconData(from url: URL) async -> Data? {
        guard ChatImageService.supports(url) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 2.5)
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/png,image/webp,image/x-icon,image/vnd.microsoft.icon,image/*;q=0.8", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await streamDelegate.fetch(request: request, on: session, kind: .image(maxBytes: Self.maxFaviconBytes)),
              !data.isEmpty else { return nil }
        return Self.faviconThumbnail(data)
    }

    // MARK: - Cache Helpers

    private static func mergeHTML(_ incoming: Preview, onto existing: Preview?) -> Preview {
        Preview(
            title: incoming.title ?? existing?.title,
            siteName: incoming.siteName ?? existing?.siteName,
            publishedAt: incoming.publishedAt ?? existing?.publishedAt,
            favicon: incoming.favicon ?? existing?.favicon
        )
    }

    private static func storePreview(_ preview: Preview, for url: URL, in state: inout SnapshotState, markCompleted: Bool) {
        if state.previews[url] == nil { state.previewOrder.append(url) }
        state.previews[url] = preview
        if markCompleted { state.completed.insert(url) }
        while state.previewOrder.count > maxPreviewCache {
            let oldest = state.previewOrder.removeFirst()
            state.previews.removeValue(forKey: oldest)
            state.completed.remove(oldest)
        }
    }

    private static func storeFavicon(_ data: Data, for origin: URL, in state: inout SnapshotState) {
        if state.favicons[origin] == nil { state.faviconOrder.append(origin) }
        state.favicons[origin] = data
        state.missingFavicons.remove(origin)
        while state.faviconOrder.count > maxFaviconCache {
            let oldest = state.faviconOrder.removeFirst()
            state.favicons.removeValue(forKey: oldest)
            state.missingFavicons.remove(oldest)
        }
    }

    static func origin(of url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        components.scheme = scheme
        components.host = host
        components.path = "/"
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    /// Standard site-level favicon fallback for mobile/subdomains (e.g. m.36kr.com -> www.36kr.com/favicon.ico).
    static func parentFaviconCandidates(for url: URL, excluding origin: URL) -> [URL] {
        guard let host = url.host?.lowercased(), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else { return [] }
        let root = registrableDomain(for: host)
        guard root.contains(".") else { return [] }
        var hosts: [String] = []
        if host != "www.\(root)" { hosts.append("www.\(root)") }
        if host != root { hosts.append(root) }
        var results: [URL] = []
        for candidateHost in hosts {
            var components = URLComponents()
            components.scheme = scheme
            components.host = candidateHost
            components.path = "/favicon.ico"
            if let candidate = components.url, candidate.host?.lowercased() != origin.host?.lowercased() {
                results.append(candidate)
            }
        }
        return results
    }

    static func registrableDomain(for host: String) -> String {
        let labels = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")).split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return host }
        let multiPartTLDs: Set<String> = [
            "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn", "ac.cn",
            "co.uk", "org.uk", "ac.uk", "gov.uk",
            "co.jp", "ne.jp", "or.jp", "ac.jp",
            "com.hk", "com.tw", "org.tw", "com.au", "com.sg", "co.kr", "com.br"
        ]
        let lastTwo = labels.suffix(2).joined(separator: ".")
        if labels.count >= 3 && multiPartTLDs.contains(lastTwo) {
            return labels.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }

    // MARK: - HTML Decoding & Parsing

    struct ParsedPage {
        var preview: Preview
        var iconURLs: [URL]
    }

    private static let commentRegex = try! NSRegularExpression(pattern: #"(?is)<!--.*?-->"#)
    private static let jsonLDRegex = try! NSRegularExpression(pattern: #"(?is)<script\b[^>]*type\s*=\s*(?:"application/ld\+json"|'application/ld\+json'|application/ld\+json)[^>]*>([\s\S]*?)</script>"#)
    private static let stripScriptStyleRegex = try! NSRegularExpression(pattern: #"(?is)<(script|style|noscript)\b[^>]*>[\s\S]*?</\1\s*>"#)
    private static let metaTagRegex = try! NSRegularExpression(pattern: #"(?is)<meta\b(?:[^>"']|"[^"]*"|'[^']*')*>"#)
    private static let linkTagRegex = try! NSRegularExpression(pattern: #"(?is)<link\b(?:[^>"']|"[^"]*"|'[^']*')*>"#)
    private static let attrRegex = try! NSRegularExpression(pattern: #"(?is)([a-z_:][a-z0-9_:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#)
    private static let titleTagRegex = try! NSRegularExpression(pattern: #"(?is)<title\b[^>]*>([\s\S]*?)</title>"#)
    private static let charsetMetaRegex = try! NSRegularExpression(pattern: #"(?i)charset\s*=\s*["']?([a-zA-Z0-9._-]+)"#)
    private static let numericEntityRegex = try! NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#)
    private static let whitespaceRegex = try! NSRegularExpression(pattern: #"\s+"#)

    private static let blockedTitles: Set<String> = [
        "just a moment...", "just a moment", "attention required!", "attention required! | cloudflare",
        "access denied", "403 forbidden", "404 not found", "502 bad gateway", "503 service unavailable",
        "verify you are human", "are you a robot?", "robot or human?", "security check",
        "title", "untitled", "document", "loading...", "loading",
        "安全验证", "请稍候", "请稍候...", "验证", "页面不存在", "访问被拒绝"
    ]

    private static let blockedSiteNames: Set<String> = [
        "title", "untitled", "document", "home", "index", "website", "web", "app", "default", "page"
    ]

    static func decodeHTML(_ data: Data, textEncodingName: String? = nil) -> String {
        let headerName = textEncodingName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let headerName, !headerName.isEmpty, headerName != "iso-8859-1", headerName != "latin1",
           let decoded = decodeData(data, ianaCharset: headerName) {
            return decoded
        }
        // Inspect the first 2 KiB as ASCII/ISO-Latin-1 for <meta charset="..."> declarations.
        let prefix = data.prefix(2048)
        let asciiHead = String(decoding: prefix, as: UTF8.self)
        if let match = charsetMetaRegex.firstMatch(in: asciiHead, range: NSRange(asciiHead.startIndex..., in: asciiHead)),
           let range = Range(match.range(at: 1), in: asciiHead) {
            let declared = String(asciiHead[range]).lowercased()
            if let decoded = decodeData(data, ianaCharset: declared) {
                return decoded
            }
        }
        if let headerName, !headerName.isEmpty, let decoded = decodeData(data, ianaCharset: headerName) {
            return decoded
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeData(_ data: Data, ianaCharset: String) -> String? {
        let normalized: String
        switch ianaCharset {
        case "gb2312", "gbk", "gb_2312-80", "x-gbk": normalized = "gb18030"
        case "utf8": normalized = "utf-8"
        default: normalized = ianaCharset
        }
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(normalized as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String(data: data, encoding: String.Encoding(rawValue: nsEncoding))
    }

    static func metadata(in html: String) -> Preview {
        parseHTML(html, base: nil, fallbackURL: nil).preview
    }

    static func parseHTML(_ html: String, base: URL?, fallbackURL: URL?) -> ParsedPage {
        let noComments = commentRegex.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "")
        let jsonLD = extractJSONLD(in: noComments)
        let cleaned = stripScriptStyleRegex.stringByReplacingMatches(in: noComments, range: NSRange(noComments.startIndex..., in: noComments), withTemplate: "")

        let metas = parseMetaTags(in: cleaned)
        let htmlTitle = firstMatch(titleTagRegex, in: cleaned, group: 1).map(decode)
        let effectiveURL = base ?? fallbackURL

        let rawTitleCandidates: [String?] = [
            metas["og:title"],
            metas["twitter:title"],
            metas["title"],
            metas["dc.title"],
            htmlTitle,
            jsonLD.title
        ]
        let title = rawTitleCandidates.lazy.compactMap { $0 }.compactMap { cleanTitle($0, url: effectiveURL) }.first

        let rawSiteCandidates: [String?] = [
            metas["og:site_name"],
            metas["application-name"],
            jsonLD.siteName
        ]
        let explicitSite = rawSiteCandidates.lazy.compactMap { $0 }.compactMap(cleanSiteName).first
        let siteName = explicitSite ?? (htmlTitle ?? title).flatMap { inferSiteName(fromTitle: $0, url: effectiveURL) }

        let rawDateCandidates: [String?] = [
            metas["article:published_time"],
            metas["og:published_time"],
            metas["publishdate"],
            metas["pubdate"],
            metas["date"],
            metas["dc.date"],
            metas["citation_publication_date"],
            jsonLD.publishedAt
        ]
        let publishedAt = rawDateCandidates.lazy.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }

        let icons = base.map { extractIconURLs(in: cleaned, base: $0) } ?? []
        return ParsedPage(preview: Preview(title: title, siteName: siteName, publishedAt: publishedAt), iconURLs: icons)
    }

    private static func parseMetaTags(in html: String) -> [String: String] {
        var result: [String: String] = [:]
        let ns = html as NSString
        for match in metaTagRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            let attrs = parseAttributes(in: tag)
            guard let key = (attrs["property"] ?? attrs["name"] ?? attrs["itemprop"])?.lowercased(),
                  let content = attrs["content"] else { continue }
            let value = decode(content)
            if !value.isEmpty, result[key] == nil {
                result[key] = value
            }
        }
        return result
    }

    private static func parseAttributes(in tag: String) -> [String: String] {
        var attrs: [String: String] = [:]
        let ns = tag as NSString
        for match in attrRegex.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: match.range(at: 1)).lowercased()
            if let range = (2...4).map({ match.range(at: $0) }).first(where: { $0.location != NSNotFound }) {
                attrs[key] = ns.substring(with: range)
            }
        }
        return attrs
    }

    static func extractIconURLs(in html: String, base: URL) -> [URL] {
        var scored: [(url: URL, score: Int)] = []
        var seen = Set<URL>()
        let ns = html as NSString
        for match in linkTagRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            let attrs = parseAttributes(in: tag)
            guard let relRaw = attrs["rel"]?.lowercased(),
                  let hrefRaw = attrs["href"] else { continue }
            let relTokens = Set(relRaw.split(whereSeparator: \.isWhitespace).map(String.init))
            let isIcon = relTokens.contains("icon")
            let isTouchIcon = relTokens.contains("apple-touch-icon") || relTokens.contains("apple-touch-icon-precomposed")
            guard isIcon || isTouchIcon else { continue }

            let href = decode(hrefRaw)
            if href.isEmpty || href.lowercased().hasPrefix("data:") { continue }
            guard let resolved = URL(string: href, relativeTo: base)?.absoluteURL,
                  ChatImageService.supports(resolved),
                  !seen.contains(resolved) else { continue }

            let ext = resolved.pathExtension.lowercased()
            let typeAttr = attrs["type"]?.lowercased() ?? ""
            // Skip SVG icons since CGImageSource only rasterizes bitmap icon formats.
            if ext == "svg" || typeAttr.contains("svg") { continue }

            var score = isIcon ? 100 : 60
            if ext == "png" || typeAttr.contains("png") { score += 20 }
            else if ext == "ico" || typeAttr.contains("icon") { score += 10 }
            if let sizes = attrs["sizes"]?.lowercased(),
               let px = sizes.split(separator: "x").first.flatMap({ Int($0) }) {
                if (24...64).contains(px) { score += 25 }
                else if (16...128).contains(px) { score += 12 }
            }
            seen.insert(resolved)
            scored.append((resolved, score))
        }
        return scored.sorted { $0.score > $1.score }.map(\.url)
    }

    private struct JSONLDMetadata {
        var title: String?
        var siteName: String?
        var publishedAt: String?
    }

    private static func extractJSONLD(in html: String) -> JSONLDMetadata {
        var meta = JSONLDMetadata()
        let ns = html as NSString
        for match in jsonLDRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)).prefix(3) {
            let raw = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = raw.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            collectJSONLD(object, into: &meta)
            if meta.title != nil && meta.siteName != nil && meta.publishedAt != nil { break }
        }
        return meta
    }

    private static func collectJSONLD(_ node: Any, into meta: inout JSONLDMetadata) {
        if let array = node as? [Any] {
            for item in array { collectJSONLD(item, into: &meta) }
            return
        }
        guard let dict = node as? [String: Any] else { return }
        if meta.title == nil, let headline = (dict["headline"] as? String) ?? (dict["name"] as? String) {
            meta.title = decode(headline)
        }
        if meta.publishedAt == nil, let date = dict["datePublished"] as? String {
            meta.publishedAt = decode(date)
        }
        if meta.siteName == nil {
            if let publisher = dict["publisher"] as? [String: Any], let name = publisher["name"] as? String {
                meta.siteName = decode(name)
            }
        }
        if let graph = dict["@graph"] {
            collectJSONLD(graph, into: &meta)
        }
    }

    static func cleanTitle(_ raw: String, url: URL? = nil) -> String? {
        let text = collapseWhitespace(decode(raw))
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return nil }
        if let url, lower == url.absoluteString.lowercased() { return nil }
        if blockedTitles.contains(lower) { return nil }
        return text
    }

    static func cleanSiteName(_ raw: String) -> String? {
        let text = collapseWhitespace(decode(raw))
        guard !text.isEmpty else { return nil }
        if blockedSiteNames.contains(text.lowercased()) { return nil }
        return text
    }

    /// Conservatively infer a site name from common title suffixes (e.g. "Article - 36氪", "Devin | Cognition").
    static func inferSiteName(fromTitle title: String, url: URL?) -> String? {
        let clean = collapseWhitespace(title)
        let explicitSeparators = [" - ", " | ", " — ", " – ", " · ", " ｜ ", "｜", "_", "—"]
        for sep in explicitSeparators {
            if let range = clean.range(of: sep, options: .backwards) {
                let left = clean[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                let right = clean[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if let valid = validateInferredSiteName(right, titlePrefix: left) {
                    return valid
                }
            }
        }
        // Tight hyphen (no surrounding spaces), e.g. "文章标题-36氪" or "Post-TechCrunch":
        // only accept when the suffix contains CJK characters or matches the host stem.
        if let hyphen = clean.range(of: "-", options: .backwards) {
            let left = clean[..<hyphen.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let right = clean[hyphen.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let valid = validateInferredSiteName(right, titlePrefix: left) {
                let hasCJK = valid.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
                let hostStem = url?.host.map { registrableDomain(for: $0).split(separator: ".").first.map(String.init) ?? "" }?.lowercased() ?? ""
                let normalizedRight = valid.lowercased().replacingOccurrences(of: " ", with: "")
                if hasCJK || (!hostStem.isEmpty && hostStem.count >= 3 && (normalizedRight.contains(hostStem) || hostStem.contains(normalizedRight))) {
                    return valid
                }
            }
        }
        return nil
    }

    private static let siteNameDisallowedPunctuation = CharacterSet(charactersIn: "、，,。！？!?;；")

    private static func validateInferredSiteName(_ candidate: String, titlePrefix: String) -> String? {
        guard titlePrefix.count >= 6, candidate.count >= 2, candidate.count <= 24 else { return nil }
        if candidate.rangeOfCharacter(from: siteNameDisallowedPunctuation) != nil { return nil }
        if candidate.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" || $0 == "/" }) { return nil }
        if candidate.contains("http://") || candidate.contains("https://") { return nil }
        return cleanSiteName(candidate)
    }

    private static func collapseWhitespace(_ text: String) -> String {
        whitespaceRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(_ expression: NSRegularExpression, in text: String, group: Int = 1) -> String? {
        guard let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    static func capture(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    static func meta(_ name: String, in html: String) -> String? {
        let lower = name.lowercased()
        let ns = html as NSString
        for match in metaTagRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            let attrs = parseAttributes(in: tag)
            if (attrs["property"] ?? attrs["name"])?.lowercased() == lower {
                return attrs["content"]
            }
        }
        return nil
    }

    static func decode(_ text: String) -> String {
        var result = text
        let ns = result as NSString
        let matches = numericEntityRegex.matches(in: result, range: NSRange(location: 0, length: ns.length))
        if !matches.isEmpty {
            for match in matches.reversed() {
                let code = ns.substring(with: match.range(at: 1))
                let value = code.lowercased().hasPrefix("x")
                    ? UInt32(code.dropFirst(), radix: 16)
                    : UInt32(code)
                if let value, let scalar = UnicodeScalar(value), let range = Range(match.range, in: result) {
                    result.replaceSubrange(range, with: String(scalar))
                }
            }
        }
        let entities: [(String, String)] = [
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&nbsp;", " "),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&hellip;", "…"),
            ("&middot;", "·"),
            ("&lsquo;", "‘"),
            ("&rsquo;", "’"),
            ("&ldquo;", "“"),
            ("&rdquo;", "”"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&amp;", "&")
        ]
        for (entity, value) in entities where result.contains(entity) {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Favicon Normalization

    static func faviconThumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 32,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

// MARK: - Chunked Head-Only / Bounded-Image URLSession Delegate

private final class LinkStreamDelegate: NSObject, URLSessionDataDelegate, Sendable {
    enum Kind: Sendable {
        case html(maxBytes: Int)
        case image(maxBytes: Int)
    }

    private struct TaskState {
        let kind: Kind
        var data = Data()
        var response: HTTPURLResponse?
        var finished = false
        var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    }

    private let redirects = PublicPageRedirects()
    private let state = OSAllocatedUnfairLock(initialState: [Int: TaskState]())
    private static let headCloseBytes = Array("</head>".utf8)

    func fetch(request: URLRequest, on session: URLSession, kind: Kind) async throws -> (Data, HTTPURLResponse) {
        let task = session.dataTask(with: request)
        let id = task.taskIdentifier
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let shouldResumeCancelled = state.withLock { tasks -> Bool in
                    if Task.isCancelled { return true }
                    tasks[id] = TaskState(kind: kind, continuation: continuation)
                    return false
                }
                if shouldResumeCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                task.resume()
            }
        } onCancel: {
            let continuation = state.withLock { tasks -> CheckedContinuation<(Data, HTTPURLResponse), Error>? in
                guard var entry = tasks.removeValue(forKey: id), !entry.finished else { return nil }
                entry.finished = true
                return entry.continuation
            }
            task.cancel()
            continuation?.resume(throwing: CancellationError())
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        redirects.urlSession(session, task: task, willPerformHTTPRedirection: response,
                             newRequest: request, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        let id = dataTask.taskIdentifier
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let finalURL = http.url, ChatImageService.supports(finalURL) else {
            fail(taskID: id, error: URLError(.badServerResponse))
            completionHandler(.cancel)
            return
        }
        let allowed = state.withLock { tasks -> Bool in
            guard var entry = tasks[id], !entry.finished else { return false }
            let mime = http.mimeType?.lowercased() ?? ""
            switch entry.kind {
            case .html:
                guard mime == "text/html" || mime == "application/xhtml+xml" else { return false }
            case .image(let maxBytes):
                if http.expectedContentLength > Int64(maxBytes) { return false }
                if mime.hasPrefix("text/") || mime == "application/json" || mime == "application/javascript" || mime == "application/xhtml+xml" {
                    return false
                }
            }
            entry.response = http
            tasks[id] = entry
            return true
        }
        if allowed {
            completionHandler(.allow)
        } else {
            fail(taskID: id, error: URLError(.badServerResponse))
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let id = dataTask.taskIdentifier
        enum Action {
            case keepGoing
            case complete(CheckedContinuation<(Data, HTTPURLResponse), Error>, Data, HTTPURLResponse)
            case fail(CheckedContinuation<(Data, HTTPURLResponse), Error>, Error)
        }

        let action = state.withLock { tasks -> Action in
            guard var entry = tasks[id], !entry.finished else { return .keepGoing }
            let oldCount = entry.data.count
            entry.data.append(data)
            switch entry.kind {
            case .html(let maxBytes):
                let reachedCap = entry.data.count >= maxBytes
                let foundHeadClose = Self.containsHeadClose(in: entry.data, from: max(0, oldCount - 8))
                if reachedCap || foundHeadClose {
                    if reachedCap && entry.data.count > maxBytes {
                        entry.data = entry.data.prefix(maxBytes)
                    }
                    entry.finished = true
                    let continuation = entry.continuation
                    entry.continuation = nil
                    tasks[id] = entry
                    if let continuation, let response = entry.response {
                        return .complete(continuation, entry.data, response)
                    }
                } else {
                    tasks[id] = entry
                }
                return .keepGoing

            case .image(let maxBytes):
                if entry.data.count > maxBytes {
                    entry.finished = true
                    let continuation = entry.continuation
                    entry.continuation = nil
                    tasks[id] = entry
                    if let continuation {
                        return .fail(continuation, URLError(.dataLengthExceedsMaximum))
                    }
                } else {
                    tasks[id] = entry
                }
                return .keepGoing
            }
        }

        switch action {
        case .keepGoing:
            break
        case .complete(let continuation, let payload, let response):
            dataTask.cancel()
            continuation.resume(returning: (payload, response))
        case .fail(let continuation, let error):
            dataTask.cancel()
            continuation.resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        let entry = state.withLock { tasks -> TaskState? in
            guard var existing = tasks.removeValue(forKey: id), !existing.finished else { return nil }
            existing.finished = true
            return existing
        }
        guard let continuation = entry?.continuation else { return }
        if let error {
            continuation.resume(throwing: error)
        } else if let response = entry?.response {
            continuation.resume(returning: (entry?.data ?? Data(), response))
        } else {
            continuation.resume(throwing: URLError(.badServerResponse))
        }
    }

    private func fail(taskID: Int, error: Error) {
        let continuation = state.withLock { tasks -> CheckedContinuation<(Data, HTTPURLResponse), Error>? in
            guard var entry = tasks.removeValue(forKey: taskID), !entry.finished else { return nil }
            entry.finished = true
            return entry.continuation
        }
        continuation?.resume(throwing: error)
    }

    /// Case-insensitive ASCII search for `</head>` starting near the newly arrived chunk.
    private static func containsHeadClose(in data: Data, from start: Int) -> Bool {
        let needle = headCloseBytes
        let count = data.count
        guard count >= needle.count, start < count else { return false }
        let limit = count - needle.count
        guard start <= limit else { return false }
        return data.withUnsafeBytes { raw in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            for i in start...limit {
                if ptr[i] == 0x3C && ptr[i + 1] == 0x2F { // "</"
                    var matched = true
                    for j in 2..<needle.count {
                        var b = ptr[i + j]
                        if b >= 0x41 && b <= 0x5A { b += 32 } // ASCII tolower
                        if b != needle[j] { matched = false; break }
                    }
                    if matched { return true }
                }
            }
            return false
        }
    }
}
