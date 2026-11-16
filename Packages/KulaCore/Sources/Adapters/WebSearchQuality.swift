import Foundation
import NaturalLanguage
import Contracts

/// Lexical coverage diagnostics and ranking for hosted search tool results.
/// This is not semantic verification: callers still have to read and assess sources.
struct WebSearchQuality {
    let query: String
    let terms: [String]
    let domains: [String]
    let subjects: [String]
    private let calendarTerms: Set<String>
    private let comparison: Bool

    init(query: String) {
        self.query = query
        comparison = query.range(of: #"(?i)\b(?:vs|versus|compare|comparison|OR)\b|对比|比较"#, options: .regularExpression) != nil
        domains = Self.matches(#"(?i)(?:^|\s)site:([a-z0-9.-]+)"#, query).map { $0.lowercased() }
        var withoutSites = query.replacingOccurrences(of: #"(?i)(?:^|\s)site:[a-z0-9.-]+"#, with: " ", options: .regularExpression)
        withoutSites = withoutSites
            .replacingOccurrences(of: #"(?i)\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,}\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(?:january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2}\b"#, with: " ", options: .regularExpression)
        calendarTerms = Set(Self.matches(#"((?:19|20)\d{2})年"#, withoutSites)
            + Self.matches(#"(\d{1,2})月"#, withoutSites) + Self.matches(#"(\d{1,2})日"#, withoutSites))
        // Tokenize each script separately: automatic language detection can split 谷歌 into 谷/歌.
        // Keep dotted/hyphenated model identifiers intact (K3.1, SWE-bench, gemini-4-carbon).
        var words: [String] = []
        for span in Self.matches(#"([a-zA-Z0-9]+(?:[.\-+][a-zA-Z0-9]+)*|[\p{Han}]+|[\p{L}\p{N}]+)"#, withoutSites) {
            if span.range(of: #"\p{Han}"#, options: .regularExpression) == nil {
                words.append(span.lowercased())
            } else {
                let tokenizer = NLTokenizer(unit: .word)
                tokenizer.setLanguage(.simplifiedChinese)
                tokenizer.string = span
                tokenizer.enumerateTokens(in: span.startIndex..<span.endIndex) { range, _ in
                    words.append(String(span[range]))
                    return true
                }
            }
        }
        var seen = Set<String>()
        terms = words.filter { !Self.queryWords.contains($0) && seen.insert($0).inserted }
        let dates = calendarTerms
        subjects = terms.filter { Self.facet($0) == nil && !Self.isDate($0) && !dates.contains($0) && !Self.isMeasurement($0) }
    }

    func matchedTerms(in results: [JSONValue]) -> [String] {
        terms.filter { term in results.contains { Self.matchesTerm(term, in: Self.searchable($0)) } }
    }

    func relevant(_ result: JSONValue) -> Bool { rejectionReason(result) == nil }

    func rejectionReason(_ result: JSONValue) -> String? {
        if !domains.isEmpty {
            guard let value = result["url"]?.stringValue, let host = URL(string: value)?.host?.lowercased(),
                  domains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return "outside_site_scope" }
        }
        if let link = result["url"]?.stringValue, let url = URL(string: link) {
            let path = "/" + url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let wantsLogin = query.range(of: #"(?i)login|sign.?in|登录|登陆"#, options: .regularExpression) != nil
            if !wantsLogin && ["/login", "/signin", "/ssb/signin", "/client"].contains(path) { return "navigation_page" }
        }
        let matched = matchedTerms(in: [result])
        // Brand AND model/version must occur in the same source. A collection of portal pages is not evidence.
        let subjectMatches = subjects.filter { matched.contains($0) }.count
        let minimum = comparison ? max(1, Int(ceil(Double(subjects.count) * 0.6))) : subjects.count
        if subjectMatches < minimum { return "missing_subject_terms" }
        // A single ambiguous brand plus an explicit model context needs that context.
        let contexts = terms.filter { Self.facet($0)?.first == "model" }
        if subjects.count == 1 && subjects[0].allSatisfy({ $0.isLetter }) && !contexts.isEmpty && !contexts.contains(where: { matched.contains($0) }) {
            return "missing_context"
        }
        if subjects.isEmpty && !terms.isEmpty && matched.isEmpty { return "no_keyword_overlap" }
        return nil
    }

    private static func facet(_ term: String) -> [String]? {
        facets.first { $0.contains(term) }
    }

    private static func matchesTerm(_ term: String, in text: String) -> Bool {
        (facet(term) ?? [term]).contains { contains($0, in: text) }
    }

    private static func isMeasurement(_ term: String) -> Bool {
        term.range(of: #"^\d+(?:\.\d+)?(?:k|m|b|gb|mb|tokens)$"#, options: .regularExpression) != nil
    }

    private static func isDate(_ term: String) -> Bool {
        dateWords.contains(term) || term.range(of: #"^(?:19|20)\d{2}$"#, options: .regularExpression) != nil
            || ["年", "月", "日"].contains(term)
    }

    // Generic intent equivalents affect coverage/ranking; they are never substituted for product identities.
    private static let facets: [[String]] = [
        ["review", "reviews", "评测", "评价", "口碑", "实测"],
        ["benchmark", "benchmarks", "跑分", "基准", "基准测试"],
        ["company", "公司", "企业", "corporation", "business"],
        ["model", "models", "模型", "llm", "ai", "人工智能"],
        ["developer", "developers", "开发者"],
        ["coding", "编程", "code"],
        ["release", "released", "发布"],
        ["swe-bench", "swe bench"]
    ]

    private static func searchable(_ value: JSONValue) -> String {
        ["title", "snippet", "url"].compactMap { value[$0]?.stringValue }.joined(separator: " ").lowercased()
    }

    private static func contains(_ term: String, in text: String) -> Bool {
        // Latin terms need word boundaries (e.g. Go must not match Google); CJK words can be adjacent.
        let latin = term.unicodeScalars.allSatisfy { $0.isASCII }
        let escaped = NSRegularExpression.escapedPattern(for: term)
            .replacingOccurrences(of: "-", with: #"[\s_-]+"#)
        let pattern = latin ? "(?<![a-z0-9])" + escaped + "(?![a-z0-9])" : escaped
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func matches(_ pattern: String, _ value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let text = value as NSString
        return regex.matches(in: value, range: NSRange(location: 0, length: text.length)).map { text.substring(with: $0.range(at: 1)) }
    }

    // Query instructions are not subject identities. No product/vendor/model names belong here.
    private static let queryWords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "of", "for", "to", "in", "on", "at", "and", "or", "with", "by", "from",
        "what", "which", "how", "when", "why", "does", "do", "can", "please", "search", "find", "about", "vs", "versus",
        "introducing", "new", "latest", "comparison", "compare",
        "official", "documentation", "blog", "context", "window", "id",
        "的", "了", "是", "吗", "什么", "怎么", "如何", "为什么", "请", "帮", "我", "查", "搜索", "查询", "介绍", "最新", "新", "一", "代", "新一代", "开放", "旗舰", "对比", "比较", "官方", "文档"
    ]
    private static let dateWords: Set<String> = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
}
