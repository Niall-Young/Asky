import Foundation
import NaturalLanguage
import Contracts

/// A lexical guard against search pages that silently ignore most of the query.
/// This is not semantic verification: callers still have to read and assess sources.
struct WebSearchQuality {
    let query: String
    let terms: [String]
    let domains: [String]

    init(query: String) {
        self.query = query
        domains = Self.matches(#"(?i)(?:^|\s)site:([a-z0-9.-]+)"#, query).map { $0.lowercased() }
        var withoutSites = query.replacingOccurrences(of: #"(?i)(?:^|\s)site:[a-z0-9.-]+"#, with: " ", options: .regularExpression)
        withoutSites = withoutSites
            .replacingOccurrences(of: #"(?i)\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,}\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(?:january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2}\b"#, with: " ", options: .regularExpression)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = withoutSites
        var words: [String] = []
        tokenizer.enumerateTokens(in: withoutSites.startIndex..<withoutSites.endIndex) { range, _ in
            words += Self.matches(#"([\p{L}\p{N}]+)"#, String(withoutSites[range]).lowercased())
            return true
        }
        var seen = Set<String>()
        terms = words.filter { !Self.queryWords.contains($0) && seen.insert($0).inserted }
    }

    func matchedTerms(in results: [JSONValue]) -> [String] {
        terms.filter { term in results.contains { Self.contains(term, in: Self.searchable($0)) } }
    }

    func relevant(_ result: JSONValue) -> Bool {
        if !domains.isEmpty {
            guard let value = result["url"]?.stringValue, let host = URL(string: value)?.host?.lowercased(),
                  domains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return false }
        }
        guard !terms.isEmpty else { return true }
        let text = Self.searchable(result)
        let matched = terms.filter { Self.contains($0, in: text) }.count
        // A result matching only the first word of a multiword query must not pass.
        return matched >= min(2, terms.count) && Double(matched) / Double(terms.count) >= 0.6
    }

    func subjectTerms(_ values: [String]) -> [String] {
        values.filter { $0.count > 1 && $0.first?.isLetter == true && !Self.dateWords.contains($0) }
    }

    func retryQueries(after results: [JSONValue]) -> [String] {
        // Do not silently drop Boolean/negative operators while simplifying a query.
        guard !query.contains(" -"), !query.hasPrefix("-"),
              !query.contains(" OR "), !query.contains(" NOT "),
              !query.contains(" AND ") else { return [] }
        let matched = Set(matchedTerms(in: results))
        let words = subjectTerms(terms)
        let missing = words.filter { !matched.contains($0) }
        guard let last = missing.last else { return [] }
        // Use the ignored words, with one context word, rather than the engine's dominant first word.
        let anchor = missing.count > 1 ? missing.first : words.first(where: { $0 != last })
        let focused = [anchor, last].compactMap { $0 }.joined(separator: " ")
        let compact = words.joined(separator: " ")
        let scope = domains.map { "site:" + $0 }.joined(separator: " ")
        var seen: Set<String> = [query.lowercased()]
        return [focused, compact, "\"" + focused + "\""].map { scope.isEmpty ? $0 : $0 + " " + scope }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    private static func searchable(_ value: JSONValue) -> String {
        ["title", "snippet", "url"].compactMap { value[$0]?.stringValue }.joined(separator: " ").lowercased()
    }

    private static func contains(_ term: String, in text: String) -> Bool {
        // Latin terms need word boundaries (e.g. Go must not match Google); CJK words can be adjacent.
        let latin = term.unicodeScalars.allSatisfy { $0.isASCII }
        let escaped = NSRegularExpression.escapedPattern(for: term)
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
        "introducing", "new", "latest", "model", "models", "release", "released", "benchmark", "benchmarks", "comparison", "compare",
        "official", "documentation", "context", "window", "id",
        "的", "了", "是", "吗", "什么", "怎么", "如何", "为什么", "请", "帮", "我", "查", "搜索", "查询", "介绍", "最新", "发布", "开放", "模型", "旗舰", "对比", "比较", "官方", "文档"
    ]
    private static let dateWords: Set<String> = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
}
