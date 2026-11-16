import Foundation
import Contracts
import ToolService

public struct WebSearchTool: ToolAdapter {
    private let call: FreeWebMCP.Call
    private let coordinator: FreeWebCoordinator
    public init() { call = FreeWebMCP.call; coordinator = .shared }
    init(call: @escaping FreeWebMCP.Call, coordinator: FreeWebCoordinator = FreeWebCoordinator()) {
        self.call = call; self.coordinator = coordinator
    }
    public var executionTimeout: Duration? { .seconds(140) }
    public var definition: ToolDefinition {
        ToolDefinition(name: "web_search", summary: CoreLocalization.text("搜索公开网页，直接调用免 Key 的 Parallel / Exa / Keenable 工具。返回来源链接、较长正文摘录、status、missingTerms 和 attempts；关键词覆盖不是事实核实。工具已自动换源，失败或限流时不要反复提交同组查询。需要页面正文时调用 web_read_page，不使用浏览器"),
            inputSchema: Args.schema(["query": Args.stringProp, "count": ["type": "integer", "minimum": 1, "maximum": 10]], required: ["query"]),
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
        let key = String(decoding: JSONValue.array(["search", .string(query), .number(Double(count))]).canonicalData(), as: UTF8.self)
        return AdapterOutput(output: try await coordinator.run(key: key) {
            try await search(query: query, count: count)
        })
    }

    private func search(query: String, count: Int) async throws -> JSONValue {
        let quality = WebSearchQuality(query: query)
        var results: [JSONValue] = [], attempts: [JSONValue] = []
        var seen = Set<String>()
        for provider in await coordinator.providers() {
            try Task.checkCancellation()
            if let skipped = await coordinator.skip(provider) { attempts.append(skipped); continue }
            do {
                let args: JSONValue = provider == .parallel
                    ? ["objective": .string(query), "search_queries": [.string(query)], "session_id": .string(FreeWebMCP.sessionID)]
                    : ["query": .string(query), "objective": .string(query), "numResults": .number(Double(max(count, 5)))]
                let response = try await call(provider, provider == .parallel ? "web_search" : provider == .exa ? "web_search_exa" : "search", args)
                let candidates = try FreeWebMCP.searchResults(response, provider: provider)
                var accepted: [JSONValue] = [], rejected: [JSONValue] = []
                for candidate in candidates {
                    let reason = quality.rejectionReason(candidate)
                    // Exact keyword coverage is a diagnostic, not a semantic search veto.
                    if reason == "outside_site_scope" || reason == "navigation_page" {
                        rejected.append(["url": candidate["url"] ?? .null, "reason": .string(reason!)])
                    } else { accepted.append(candidate) }
                }
                let missing = quality.terms.filter { !quality.matchedTerms(in: accepted).contains($0) }
                attempts.append(["provider": .string(provider.rawValue), "query": .string(query),
                    "status": .string(accepted.isEmpty ? "no_relevant_results" : missing.isEmpty ? "matched" : "partial"),
                    "resultCount": .number(Double(candidates.count)), "acceptedCount": .number(Double(accepted.count)),
                    "missingTerms": .array(missing.map(JSONValue.string)), "rejected": .array(rejected)])
                for candidate in accepted {
                    if let url = candidate["url"]?.stringValue, seen.insert(url).inserted { results.append(candidate) }
                }
                if !accepted.isEmpty && missing.isEmpty && accepted.contains(where: quality.relevant) { break }
            } catch {
                attempts.append(try FreeWebMCP.failure(error, provider: provider))
                await coordinator.record(error, provider: provider)
            }
        }
        // Prefer a complete identity in one source; retain partial sources for the agent to assess.
        results = results.enumerated().sorted { a, b in
            let x = quality.matchedTerms(in: [a.element]).count + (quality.relevant(a.element) ? 1000 : 0)
            let y = quality.matchedTerms(in: [b.element]).count + (quality.relevant(b.element) ? 1000 : 0)
            return x == y ? a.offset < b.offset : x > y
        }.map(\.element)
        let selected = Array(results.prefix(count))
        let missing = quality.terms.filter { !quality.matchedTerms(in: selected).contains($0) }
        let failures = attempts.filter { ["unavailable", "rate_limited"].contains($0["status"]?.stringValue ?? "") }
        let covered = missing.isEmpty && selected.contains(where: quality.relevant)
        let status: String
        if selected.isEmpty {
            status = failures.isEmpty ? "no_relevant_results" : failures.contains { $0["status"]?.stringValue == "rate_limited" } ? "rate_limited" : "unavailable"
        } else { status = covered ? "matched" : "partial" }
        return ["query": .string(query), "provider": .string("Parallel / Exa / Keenable"),
            "cached": false, "coalesced": false,
            "reason": .string(selected.isEmpty ? (failures.isEmpty ? "no_accepted_results" : "sources_unavailable") : covered ? "query_terms_covered" : "incomplete_coverage"),
            "status": .string(status), "quality": .string(selected.isEmpty ? "unknown" : covered ? "matched" : "partial"),
            "contentType": "search_excerpts", "contentAvailability": "unknown", "billing": "anonymous_no_credentials",
            "retrievedAt": .string(ISO8601DateFormatter().string(from: Date())),
            "subjectTerms": .array(quality.subjects.map(JSONValue.string)), "missingTerms": .array(missing.map(JSONValue.string)),
            "attempts": .array(attempts), "results": .array(selected),
            "nextAction": .string(selected.isEmpty ? "report_search_unavailable_or_no_results" : covered ? "assess_sources" : "read_specific_page_or_report_gap")]
    }
}
