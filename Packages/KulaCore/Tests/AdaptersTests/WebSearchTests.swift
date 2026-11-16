import Foundation
import Testing
import Contracts
import LocalStore
import ToolService
@testable import Adapters

@Suite struct WebSearchTests {
    let url = URL(string: "https://www.bing.com/search?q=swift")!

    @Test func parsesSourcesAndRejectsUnsafeLinks() throws {
        let encoded = Data("https://swift.org/?a=1&b=2".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let html = """
        <li class="b_algo"><h2><a href="https://www.bing.com/ck/a?u=a1\(encoded)&amp;ntb=1">Swift &amp; &#x4E2D;&#25991;</a></h2><p>Learn <strong>Swift</strong>.</p></li>
        <li class="b_algo"><h2><a href="javascript:alert(1)">Unsafe</a></h2></li>
        <li class="b_algo"><h2><a href="https://swift.org/?a=1&amp;b=2">Duplicate</a></h2></li>
        <li class="b_algo"><h2><a href="https://developer.apple.com/swift/">Apple</a></h2></li>
        """
        let output = try WebSearchTool.output(html: html, query: "swift", searchURL: url, count: 5)
        #expect(output["results"]?.arrayValue?.count == 2)
        #expect(output["results"]?.arrayValue?.first?["title"]?.stringValue == "Swift & 中文")
        #expect(output["results"]?.arrayValue?.first?["url"]?.stringValue == "https://swift.org/?a=1&b=2")
        #expect(try WebSearchTool.output(html: html, query: "swift", searchURL: url, count: 1)["results"]?.arrayValue?.count == 1)
        #expect(WebSearchTool.sourceURL("file:///etc/passwd") == nil)
        #expect(WebSearchTool.sourceURL("https://user:pass@example.com") == nil)
    }

    @Test func challengesAndChangedMarkupAreFailures() throws {
        for html in ["<html>unexpected layout</html>", "<div id='b_captcha'>verify</div>"] {
            #expect(throws: ToolError.self) { try WebSearchTool.output(html: html, query: "swift", searchURL: url, count: 5) }
        }
        #expect(try WebSearchTool.output(html: "<li class='b_no'>No results</li>", query: "swift", searchURL: url, count: 5)["results"]?.arrayValue?.isEmpty == true)
    }

    @Test func validatesBeforeNetwork() async {
        for args: JSONValue in [["query": " "], ["query": .string(String(repeating: "a", count: 501))],
                                ["query": "swift", "count": 1.5], ["query": "swift", "count": 11]] {
            do { _ = try await WebSearchTool().execute(args); Issue.record("Invalid arguments accepted") }
            catch let error as ToolError { #expect(error.code == .invalidArguments) }
            catch { Issue.record("Unexpected error: \(error)") }
        }
    }

    @Test func sourcePolicyAndMCPExposure() async throws {
        let store = try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory)
        let disabled = ToolService(store: store, policy: { PolicySnapshot(enabledSources: []) }, presenter: { _ in .rejected })
        await disabled.register(WebSearchTool())
        #expect(await disabled.definitions(for: .agent(sessionID: "s")).isEmpty)
        #expect(await disabled.submit(ActionRequest(tool: "web_search", arguments: ["query": "swift"], origin: .agent(sessionID: "s"), intent: .explicitRequest)).error?.code == .sourceDisabled)
        let enabled = ToolService(store: store, policy: { PolicySnapshot(enabledSources: [.web]) }, presenter: { _ in .rejected })
        await enabled.register(WebSearchTool())
        #expect(await enabled.definitions(for: .agent(sessionID: "s")).contains { $0.name == "web_search" })
        #expect(await enabled.definitions(for: .mcp(instanceID: "s")).isEmpty)
    }

    @Test func liveSearchThroughToolService() async throws {
        guard ProcessInfo.processInfo.environment["ASKY_LIVE_WEB_SEARCH"] == "1" else { return }
        let store = try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory)
        let service = ToolService(store: store, policy: { PolicySnapshot(enabledSources: [.web]) }, presenter: { _ in .rejected })
        await service.register(WebSearchTool())
        let result = await service.submit(ActionRequest(tool: "web_search", arguments: ["query": "Swift Apple documentation", "count": 5], origin: .agent(sessionID: "live"), intent: .explicitRequest))
        #expect(result.status == .completed, "\(String(describing: result.error))")
        #expect(result.output?["results"]?.arrayValue?.isEmpty == false)
        print("Live Swift search: results=\(result.output?["results"]?.arrayValue?.count ?? 0), quality=\(result.output?["quality"]?.stringValue ?? "error")")
    }
}

@Suite struct WebSearchRecoveryTests {
    private func page(_ title: String, _ url: String = "https://example.com/article", _ snippet: String = "") -> String {
        "<li class='b_algo'><h2><a href='\(url)'>\(title)</a></h2><p>\(snippet)</p></li>"
    }

    @Test func retriesIgnoredSubjectAndDropsPortalPages() async throws {
        let portal = page("Orion official homepage", "https://orion.example/")
        let found = page("Orion Nova model release", "https://example.com/nova")
        let fetcher = SearchFixture([portal, found])
        let tool = WebSearchTool(fetch: { try await fetcher.fetch($0) })
        let value = try await tool.execute(["query": "Orion Nova model release", "count": 1]).output
        #expect(value["quality"]?.stringValue == "matched")
        #expect(value["results"]?.arrayValue?.first?["url"]?.stringValue == "https://example.com/nova")
        let queries = await fetcher.queries
        #expect(queries == ["Orion Nova model release", "orion nova"])
        #expect(value["attempts"]?.arrayValue?.count == 2)
    }

    @Test func exhaustedRetriesDoNotReturnUnrelatedResults() async throws {
        let fetcher = SearchFixture([page("Orion official homepage")])
        let value = try await WebSearchTool(fetch: { try await fetcher.fetch($0) })
            .execute(["query": "Orion Nova model release"]).output
        #expect(value["quality"]?.stringValue == "no_relevant_results")
        #expect(value["results"]?.arrayValue?.isEmpty == true)
        #expect(value["missingTerms"]?.arrayValue?.contains(.string("nova")) == true)
        #expect(await fetcher.queries.count <= 3)
    }

    @Test func checksRelevanceBeforeRequestedResultLimit() async throws {
        let html = page("Other topic", "https://example.com/other") + page("Orion Nova", "https://example.com/nova")
        let fetcher = SearchFixture([html])
        let value = try await WebSearchTool(fetch: { try await fetcher.fetch($0) })
            .execute(["query": "Orion Nova", "count": 1]).output
        #expect(value["results"]?.arrayValue?.first?["url"]?.stringValue == "https://example.com/nova")
        #expect(await fetcher.queries.count == 1)
    }

    @Test func siteScopeSurvivesRetriesAndRejectsLookalikes() async throws {
        let html = page("Orion Nova", "https://docs.example.evil.com/nova")
            + page("Orion Nova", "https://docs.example/nova")
        let fetcher = SearchFixture([page("Orion homepage"), html])
        let value = try await WebSearchTool(fetch: { try await fetcher.fetch($0) })
            .execute(["query": "Orion Nova site:docs.example"]).output
        #expect(value["results"]?.arrayValue?.count == 1)
        #expect(value["results"]?.arrayValue?.first?["url"]?.stringValue == "https://docs.example/nova")
        #expect(await fetcher.queries.last == "\"orion nova\" site:docs.example")
    }

    @Test func cancellationIsNeverReportedAsNoResults() async {
        let tool = WebSearchTool(fetch: { _ in throw CancellationError() })
        do { _ = try await tool.execute(["query": "Orion Nova"]); Issue.record("Cancellation swallowed") }
        catch is CancellationError { }
        catch { Issue.record("Wrong error: \(error)") }
    }

    @Test func brokenPageIsAnErrorNotAnEmptySearch() async {
        let tool = WebSearchTool(fetch: { _ in "<html>unrecognized</html>" })
        do { _ = try await tool.execute(["query": "Orion Nova"]); Issue.record("Broken page accepted") }
        catch let error as ToolError { #expect(error.code == .unavailable) }
        catch { Issue.record("Wrong error: \(error)") }
    }

    @Test func preservesQueryEncodingAndOperators() {
        let query = "C++ Swift & 中文 #api"
        let url = WebSearchTool.searchURL(query)
        #expect(url.absoluteString.contains("C%2B%2B"))
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == query)
        #expect(WebSearchQuality(query: "Orion Nova -old").retryQueries(after: []).isEmpty)
        #expect(WebSearchQuality(query: "Orion OR Nova").retryQueries(after: []).isEmpty)
        #expect(!WebSearchQuality(query: "Go").relevant(["title": "Google", "url": "https://google.com"]))
    }

    @Test func chineseAndModelIdentifiersKeepSubjectTerms() {
        #expect(WebSearchQuality(query: "Gemini 4 Carbon 模型 Google 发布").terms.contains("carbon"))
        #expect(WebSearchQuality(query: "杭州 天气").terms.contains("杭州"))
        #expect(WebSearchQuality(query: "gemini-4-carbon").terms.contains("gemini-4-carbon"))
    }

    @Test func chineseIntentAcceptsEnglishSourcesAndKeepsIdentity() async throws {
        let fetcher = SearchFixture([page("Gemini exchange", "https://gemini.com"),
                                    page("Gemini 4 Carbon review", "https://example.com/carbon", "Model benchmark results")])
        let value = try await WebSearchTool(fetch: { try await fetcher.fetch($0) })
            .execute(["query": "Gemini 4 Carbon 评测 口碑 benchmark"]).output
        #expect(value["status"]?.stringValue == "matched")
        #expect(value["results"]?.arrayValue?.count == 1)
        #expect(await fetcher.queries == ["Gemini 4 Carbon 评测 口碑 benchmark", "gemini 4 carbon review benchmark"])
        #expect(value["attempts"]?.arrayValue?.first?["rejected"]?.arrayValue?.first?["reason"]?.stringValue == "missing_subject_terms")
    }

    @Test func topicSourceSurvivesMissingReviewWithoutClaimingReviewCoverage() async throws {
        let fetcher = SearchFixture([page("Kimi K3.1 Pro", "https://example.com/k3", "New language model")])
        let value = try await WebSearchTool(fetch: { try await fetcher.fetch($0) })
            .execute(["query": "Kimi K3.1 Pro 评测 SWE-bench"]).output
        #expect(value["status"]?.stringValue == "partial")
        #expect(value["results"]?.arrayValue?.count == 1)
        #expect(value["missingTerms"]?.arrayValue?.contains("评测") == true)
        #expect(value["missingTerms"]?.arrayValue?.contains("swe-bench") == true)
        #expect(value["nextAction"]?.stringValue == "change_source_or_read_page")
        for query in await fetcher.queries { #expect(query.lowercased().contains("kimi k3.1 pro")) }
    }

    @Test func brandAndVersionCannotBeSatisfiedByDifferentResults() async throws {
        let html = page("Gemini 4 homepage", "https://example.com/gemini")
            + page("Carbon review", "https://example.com/carbon")
        let fetcher = SearchFixture([html])
        let value = try await WebSearchTool(fetch: { try await fetcher.fetch($0) })
            .execute(["query": "Gemini 4 Carbon 评测"]).output
        #expect(value["status"]?.stringValue == "no_relevant_results")
        #expect(value["reason"]?.stringValue == "candidates_rejected")
        #expect(value["contentAvailability"]?.stringValue == "unknown")
    }

    @Test func chineseCompanyQuestionAndModelDisambiguation() {
        let slack = WebSearchQuality(query: "Slack 是什么公司")
        #expect(slack.subjects == ["slack"])
        #expect(!slack.relevant(["title": "Slack", "url": "https://slack.com/signin"]))
        #expect(WebSearchQuality(query: "Slack login").relevant(["title": "Slack login", "url": "https://slack.com/login"]))
        #expect(!WebSearchQuality(query: "Москва погода").terms.isEmpty)
        #expect(slack.relevant(["title": "Slack", "snippet": "A collaboration platform owned by Salesforce"]))
        let model = WebSearchQuality(query: "Gemini 模型")
        #expect(!model.relevant(["title": "Gemini", "snippet": "Cryptocurrency exchange"]))
        #expect(model.relevant(["title": "Gemini", "snippet": "An AI model from Google"]))
        #expect(!WebSearchQuality(query: "Kimi K3.1 Pro 评测").relevant(["title": "Kimi K2.5 Pro review"]))
        #expect(WebSearchQuality(query: "谷歌 Gemini 新模型 2026年11月").subjects == ["谷歌", "gemini"])
    }

    @Test func comparisonsAndSpecificationsKeepPartialSources() {
        let source: JSONValue = ["title": "Gemini 4 Carbon", "url": "https://blog.google/carbon"]
        #expect(WebSearchQuality(query: "Google Gemini 4 Argon Carbon 对比").relevant(source))
        let spec = WebSearchQuality(query: "gemini-4-carbon model ID context window 1M")
        #expect(spec.relevant(source))
        #expect(!spec.matchedTerms(in: [source]).contains("1m"))
    }

    @Test func emptyProviderAndFailedRecoveryHaveDistinctSignals() async throws {
        let empty = SearchFixture(["<li class='b_no'>No results</li>"])
        let value = try await WebSearchTool(fetch: { try await empty.fetch($0) }).execute(["query": "Orion Nova"]).output
        #expect(value["status"]?.stringValue == "no_relevant_results")
        #expect(value["reason"]?.stringValue == "provider_returned_no_results")
        let partial = SearchFixture([page("Orion Nova"), "<html>broken</html>"])
        let output = try await WebSearchTool(fetch: { try await partial.fetch($0) }).execute(["query": "Orion Nova 评测"]).output
        #expect(output["status"]?.stringValue == "partial")
        #expect(output["attempts"]?.arrayValue?.last?["status"]?.stringValue == "failed")
        #expect(output["results"]?.arrayValue?.isEmpty == false)
    }

    @Test func collectsAvailableSnippetParagraphs() throws {
        let html = page("Slack", "https://example.com", "First paragraph")
        let expanded = html.replacingOccurrences(of: "</p>", with: "</p><p>Second paragraph</p>")
        let value = try WebSearchTool.output(html: expanded, query: "Slack", searchURL: WebSearchTool.searchURL("Slack"), count: 5)
        #expect(value["results"]?.arrayValue?.first?["snippet"]?.stringValue == "First paragraph Second paragraph")
    }

    @Test func liveReportedChineseQueriesThroughToolService() async throws {
        guard ProcessInfo.processInfo.environment["ASKY_LIVE_WEB_SEARCH_CHINESE"] == "1" else { return }
        let store = try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory)
        let service = ToolService(store: store, policy: { PolicySnapshot(enabledSources: [.web]) }, presenter: { _ in .rejected })
        await service.register(WebSearchTool())
        for query in ["Slack 是什么公司", "Kimi K3.1 Pro 评测 SWE-bench", "Gemini 4 Carbon 评测 口碑 benchmark", "Gemini 4 Carbon 开发者 评价 实测"] {
            let result = await service.submit(ActionRequest(tool: "web_search", arguments: ["query": .string(query)], origin: .agent(sessionID: "live-chinese"), intent: .explicitRequest))
            #expect(result.status == .completed, "\(query): \(String(describing: result.error))")
            #expect(result.output?["status"]?.stringValue != nil)
            if query.hasPrefix("Slack") { #expect(result.output?["results"]?.arrayValue?.isEmpty == false) }
            // Emerging model coverage is observed, not asserted as proof the named product exists.
            let data = try JSONEncoder().encode(result.output)
            print("Chinese live: \(query) | \(String(decoding: data, as: UTF8.self))")
        }
    }

    @Test func liveOriginalQueriesThroughToolService() async throws {
        guard ProcessInfo.processInfo.environment["ASKY_LIVE_WEB_SEARCH_RECOVERY"] == "1" else { return }
        let store = try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory)
        let service = ToolService(store: store, policy: { PolicySnapshot(enabledSources: [.web]) }, presenter: { _ in .rejected })
        await service.register(WebSearchTool())
        let queries = ["Gemini Carbon model Google", "Google Gemini 4 Argon Carbon 旗舰模型 对比",
                       "\"Gemini\" \"Carbon\" 模型 发布", "Gemini new model Carbon benchmark release 2026",
                       "Gemini 4 Carbon 模型 Google 发布", "\"gemini-4-carbon\" model ID context window 1M",
                       "Introducing Gemini 4 Carbon blog.google October 28 2026", "Gemini 4 Carbon 发布 2026年11月 开放"]
        for query in queries {
            let result = await service.submit(ActionRequest(tool: "web_search", arguments: ["query": .string(query)], origin: .agent(sessionID: "live-recovery"), intent: .explicitRequest))
            let output = result.output
            let results = output?["results"]?.arrayValue ?? []
            let official = results.contains { item in
                guard let url = item["url"]?.stringValue, let host = URL(string: url)?.host else { return false }
                return (host == "blog.google" || host == "deepmind.google" || host == "ai.google.dev")
                    && (item["title"]?.stringValue?.lowercased().contains("carbon") == true || url.contains("carbon"))
            }
            #expect(result.status == .completed, "\(query): \(String(describing: result.error))")
            #expect(official, "No official Carbon result for \(query): \(String(describing: output))")
            print("Recovery: \(query) | quality=\(output?["quality"]?.stringValue ?? "error") | attempts=\(output?["attempts"]?.arrayValue?.count ?? 0) | official=\(official)")
        }
    }
}

private actor SearchFixture {
    let pages: [String]
    var queries: [String] = []
    init(_ pages: [String]) { self.pages = pages }
    func fetch(_ url: URL) throws -> String {
        queries.append(URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first!.value!)
        return pages[min(queries.count - 1, pages.count - 1)]
    }
}
