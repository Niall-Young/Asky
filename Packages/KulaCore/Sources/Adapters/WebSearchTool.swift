import Foundation
import Contracts
import ToolService

/// Public search only. An ephemeral session never sends model keys or browser cookies.
public struct WebSearchTool: ToolAdapter {
    typealias Fetch = @Sendable (URL) async throws -> String
    private let fetch: Fetch
    public init() { fetch = Self.fetchHTML }
    init(fetch: @escaping Fetch) { self.fetch = fetch }
    public var executionTimeout: Duration? { .seconds(35) }
    public var definition: ToolDefinition {
        ToolDefinition(name: "web_search", summary: CoreLocalization.text("联网核实公开信息（Bing，无需 API Key）。回答可能变化的信息、产品推荐与比较、软件/API 用法、拿不准的事实或用户要求查证时，必须先调用，不必等待用户说“联网”。返回标题、来源链接和摘要；摘要不等于网页全文") + CoreLocalization.text("。工具会检查关键词覆盖并最多补搜两次；读取 output.status、missingTerms、attempts 和 nextAction；外层 completed 只代表执行结束。补搜已耗尽时换来源或读取具体页面，不重复同组查询；partial 或 no_relevant_results 不能作为否定事实的证据"),
            inputSchema: Args.schema(["query": Args.stringProp,
                "count": ["type": "integer", "minimum": 1, "maximum": 10]], required: ["query"]),
            source: .web, effect: .read, confirmation: .never, externallyExposable: false)
    }

    public func execute(_ arguments: JSONValue) async throws -> AdapterOutput {
        let query = try Args.requiredString(arguments, "query")
        guard query.count <= 500 else { throw ToolError(.invalidArguments, CoreLocalization.text("搜索词不能超过 500 字")) }
        let count: Int
        if let value = arguments["count"] {
            guard let n = value.numberValue, n.isFinite, n.rounded() == n, (1...10).contains(n) else {
                throw ToolError(.invalidArguments, CoreLocalization.text("count 必须是 1 到 10 的整数"))
            }
            count = Int(n)
        } else { count = 5 }
        let quality = WebSearchQuality(query: query)
        var pending = [query]
        var results: [JSONValue] = []
        var attempts: [JSONValue] = []
        var seen = Set<String>()
        var lastFailure: Error?
        while !pending.isEmpty && attempts.count < 3 {
            try Task.checkCancellation()
            let searchQuery = pending.removeFirst()
            let url = Self.searchURL(searchQuery)
            do {
                let html = try await fetch(url)
                try Task.checkCancellation()
                // Inspect every available result before enforcing the caller's count.
                let page = try Self.output(html: html, query: searchQuery, searchURL: url, count: 10)
                let candidates = page["results"]?.arrayValue ?? []
                let accepted = candidates.filter { quality.relevant($0) }
                let matched = quality.matchedTerms(in: accepted)
                let rejected: [JSONValue] = candidates.compactMap { candidate in
                    guard let reason = quality.rejectionReason(candidate) else { return nil }
                    let covered = quality.matchedTerms(in: [candidate])
                    return ["url": candidate["url"] ?? .null, "title": candidate["title"] ?? .null,
                            "reason": .string(reason),
                            "missingTerms": .array(quality.terms.filter { !covered.contains($0) }.map { .string($0) })]
                }
                let missing = quality.terms.filter { !matched.contains($0) }
                attempts.append(["query": .string(searchQuery), "searchURL": .string(url.absoluteString),
                                 "resultCount": .number(Double(candidates.count)),
                                 "missingTerms": .array(missing.map { .string($0) }),
                                 "acceptedCount": .number(Double(accepted.count)), "rejected": .array(rejected),
                                 "status": .string(candidates.isEmpty ? "no_results" : accepted.isEmpty ? "no_relevant_results" : missing.isEmpty ? "matched" : "partial")])
                if attempts.count == 1 {
                    pending += quality.retryQueries(after: candidates)
                }
                for candidate in accepted {
                    guard let link = candidate["url"]?.stringValue, seen.insert(link).inserted else { continue }
                    results.append(candidate)
                }
                // Retry if the provider ignored query terms, even when some generic results look relevant.
                if !results.isEmpty && missing.isEmpty { break }
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                lastFailure = error
                attempts.append(["query": .string(searchQuery), "searchURL": .string(url.absoluteString),
                                 "status": "failed", "error": .string(error.localizedDescription)])
            }
        }
        // Rank by original query coverage, preserving provider order for ties.
        results = results.enumerated().sorted { lhs, rhs in
            let left = quality.matchedTerms(in: [lhs.element]).count
            let right = quality.matchedTerms(in: [rhs.element]).count
            return left == right ? lhs.offset < rhs.offset : left > right
        }.map(\.element)
        let selected = Array(results.prefix(count))
        let matched = quality.matchedTerms(in: selected)
        let missing = quality.terms.filter { !matched.contains($0) }
        if selected.isEmpty && attempts.allSatisfy({ $0["status"]?.stringValue == "failed" }), let lastFailure {
            throw lastFailure
        }
        let status = selected.isEmpty ? "no_relevant_results" : (missing.isEmpty ? "matched" : "partial")
        let hadFailure = attempts.contains { $0["status"]?.stringValue == "failed" }
        let rawCount = attempts.reduce(0) { $0 + Int($1["resultCount"]?.numberValue ?? 0) }
        let reason = selected.isEmpty ? (rawCount == 0 ? "provider_returned_no_results" : "candidates_rejected")
            : (missing.isEmpty && !hadFailure ? "query_terms_covered" : "incomplete_coverage")
        return AdapterOutput(output: ["provider": "Bing", "query": .string(query),
            "searchURL": .string(Self.searchURL(query).absoluteString),
            "retrievedAt": .string(ISO8601DateFormatter().string(from: Date())),
            "contentType": "search_snippets", "quality": .string(status),
            "status": .string(hadFailure && !selected.isEmpty ? "partial" : status), "reason": .string(reason),
            "contentAvailability": "unknown", "subjectTerms": .array(quality.subjects.map { .string($0) }),
            "nextAction": .string(status == "matched" && !hadFailure ? "assess_sources" : "change_source_or_read_page"),
            "missingTerms": .array(missing.map { .string($0) }), "attempts": .array(attempts),
            "results": .array(selected),
            "notice": .string(CoreLocalization.text("关键词匹配不等于事实核实；partial 表示仍缺查询内容，no_relevant_results 表示未找到足够相关的结果，均不能据此断言对象不存在。摘要不等于网页全文。"))])
    }

    static func searchURL(_ query: String) -> URL {
        var components = URLComponents(string: "https://www.bing.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        // Search endpoints decode form-style '+' as a space; preserve literal C++ and +term.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    private static func fetchHTML(_ url: URL) async throws -> String {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ToolError(.unavailable, CoreLocalization.text("联网搜索服务暂不可用，请稍后重试"))
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 1_048_576 else { throw ToolError(.unavailable, CoreLocalization.text("搜索响应超过大小限制")) }
            data.append(byte)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw ToolError(.unavailable, CoreLocalization.text("搜索响应编码无法解析"))
        }
        return html
    }

    static func output(html: String, query: String, searchURL: URL, count: Int) throws -> JSONValue {
        if html.contains("b_captcha") || html.contains("/challenge") {
            throw ToolError(.unavailable, CoreLocalization.text("搜索服务要求验证，请在浏览器中搜索或稍后重试"))
        }
        var results: [JSONValue] = []
        var seen = Set<String>()
        for block in captures(#"<li\b[^>]*class=["'][^"']*\bb_algo\b[^"']*["'][^>]*>(.*?)</li>"#, html) {
            guard let heading = captures(#"<h2\b[^>]*>(.*?)</h2>"#, block[0]).first,
                  let anchor = captures(#"<a\b[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>"#, heading[0]).first,
                  let link = sourceURL(text(anchor[0])), seen.insert(link).inserted else { continue }
            let title = String(text(anchor[1]).prefix(300))
            guard !title.isEmpty else { continue }
            let snippet = captures(#"<p\b[^>]*>(.*?)</p>"#, block[0]).map { text($0[0]) }.filter { !$0.isEmpty }.joined(separator: " ")
            results.append(["title": .string(title), "url": .string(link), "snippet": .string(String(snippet.prefix(1500)))])
            if results.count == count { break }
        }
        // A changed page or a challenge must never be reported as a successful empty search.
        if results.isEmpty && captures(#"<[^>]*class=["'][^"']*\bb_no\b[^"']*["']"#, html).isEmpty {
            throw ToolError(.unavailable, CoreLocalization.text("未能解析搜索结果，搜索服务可能限流或页面结构已变化，请稍后重试"))
        }
        return ["provider": "Bing", "query": .string(query), "searchURL": .string(searchURL.absoluteString),
                "retrievedAt": .string(ISO8601DateFormatter().string(from: Date())),
                "contentType": "search_snippets", "results": .array(results)]
    }

    static func sourceURL(_ value: String) -> String? {
        guard var url = URL(string: value) else { return nil }
        if url.host == "www.bing.com", url.path == "/ck/a" {
            guard let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "u" })?.value,
                  encoded.hasPrefix("a1") else { return nil }
            var base64 = String(encoded.dropFirst(2)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
            guard let data = Data(base64Encoded: base64), let decoded = String(data: data, encoding: .utf8),
                  let target = URL(string: decoded) else { return nil }
            url = target
        }
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url.absoluteString
    }

    private static func captures(_ pattern: String, _ input: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = input as NSString
        return regex.matches(in: input, range: NSRange(location: 0, length: ns.length)).map { match in
            (1..<match.numberOfRanges).map { ns.substring(with: match.range(at: $0)) }
        }
    }

    private static func text(_ html: String) -> String {
        var value = html.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        for (entity, replacement) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        let pattern = #"&#(x[0-9a-fA-F]+|[0-9]+);"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = value as NSString
            for match in regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).reversed() {
                let digits = ns.substring(with: match.range(at: 1))
                let number = digits.hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                if let number, let scalar = UnicodeScalar(number), let range = Range(match.range, in: value) {
                    value.replaceSubrange(range, with: String(scalar))
                }
            }
        }
        return value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
