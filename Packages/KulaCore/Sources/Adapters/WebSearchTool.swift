import Foundation
import Contracts
import ToolService

/// Public search only. An ephemeral session never sends model keys or browser cookies.
public struct WebSearchTool: ToolAdapter {
    public init() {}
    public var definition: ToolDefinition {
        ToolDefinition(name: "web_search", summary: CoreLocalization.text("联网核实公开信息（Bing，无需 API Key）。回答可能变化的信息、产品推荐与比较、软件/API 用法、拿不准的事实或用户要求查证时，必须先调用，不必等待用户说“联网”。返回标题、来源链接和摘要；摘要不等于网页全文"),
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
        var components = URLComponents(string: "https://www.bing.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        let url = components.url!
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
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
        return AdapterOutput(output: try Self.output(html: html, query: query, searchURL: url, count: count))
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
            let snippet = captures(#"<p\b[^>]*>(.*?)</p>"#, block[0]).first.map { text($0[0]) } ?? ""
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
