import Foundation
import Testing
import Contracts
import LocalStore
import ToolService
@testable import Adapters

@Suite struct WebSearchQualityTests {
    @Test func latinTermsRequireWordBoundaries() {
        #expect(!WebSearchQuality(query: "Go").relevant(["title": "Google", "url": "https://google.com"]))
    }

    @Test func chineseAndModelIdentifiersKeepSubjectTerms() {
        #expect(WebSearchQuality(query: "Gemini 4 Carbon 模型 Google 发布").terms.contains("carbon"))
        #expect(WebSearchQuality(query: "杭州 天气").terms.contains("杭州"))
        #expect(WebSearchQuality(query: "gemini-4-carbon").terms.contains("gemini-4-carbon"))
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
}

@Suite struct FreeWebSearchTests {
    @Test func photoModifiersDoNotTriggerRedundantProviderFallback() async throws {
        let tool = WebSearchTool(call: { provider, _, _ in
            #expect(provider == .parallel, "The subject is covered; photo wording must not force backup search")
            return Self.result("钟丽缇 Christy Chung", "演员简介和作品", url: "https://example.com/christy")
        })
        let result = try await tool.execute(["query": "钟丽缇 Christy Chung 照片 人像 photo portrait"]).output
        #expect(result["status"] == "matched")
        #expect(result["attempts"]?.arrayValue?.count == 1)
    }

    static func result(_ title: String, _ excerpt: String, url: String = "https://example.com/article") -> JSONValue {
        ["structuredContent": ["results": [["title": .string(title), "url": .string(url), "excerpts": [.string(excerpt)]]]]]
    }

    @Test func anonymousTransportAndSSE() throws {
        for provider in FreeWebProvider.allCases {
            let request = FreeWebMCP.request(provider: provider, payload: ["query": "C++ 中文"])
            #expect(request.url == provider.endpoint)
            #expect(request.url?.query == nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(String(decoding: request.httpBody!, as: UTF8.self).contains("C++ 中文"))
        }
        let sse = "event: message\r\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\"}\r\n\r\nevent: message\r\ndata: {\"id\":2,\"result\":{\"content\":[]}}\r\n\r\n"
        #expect(try FreeWebMCP.decode(Data(sse.utf8), id: 2)["result"] != nil)
        #expect(throws: FreeWebFailure.self) { try FreeWebMCP.decode(Data("{\"id\":2,\"error\":{}}".utf8), id: 2) }
        #expect(throws: FreeWebFailure.self) { try FreeWebMCP.decode(Data(sse.utf8), id: 7) }
    }

    @Test func readsBothProviderFormatsAndLongExcerpts() throws {
        let excerpt = String(repeating: "原文摘录。", count: 1400)
        let rows = try FreeWebMCP.searchResults(Self.result("中文", excerpt), provider: .parallel)
        #expect(rows.first?["snippet"]?.stringValue?.count == 6000)
        #expect(rows.first?["truncated"]?.boolValue == true)
        let exa: JSONValue = ["content": [["type": "text", "text": "Title: Slack 公司\nURL: https://slack.com/about\nHighlights:\n正文\n\n---\n\nTitle: Slack 介绍\nURL: https://en.wikipedia.org/wiki/Slack\nHighlights:\n另一篇"]]]
        #expect(try FreeWebMCP.searchResults(exa, provider: .exa).count == 2)
        #expect(throws: FreeWebFailure.self) { try FreeWebMCP.searchResults(["content": []], provider: .exa) }
    }

    @Test func failoverPreservesQueryAndReportsLimits() async throws {
        let fixture = FreeWebFixture()
        let tool = WebSearchTool(call: { p, n, a in try await fixture.call(p, n, a) })
        let value = try await tool.execute(["query": "Slack 是什么公司"]).output
        #expect(value["status"]?.stringValue == "matched")
        #expect(value["attempts"]?.arrayValue?.first?["status"]?.stringValue == "rate_limited")
        #expect(value["results"]?.arrayValue?.first?["url"]?.stringValue == "https://slack.com/about")
        #expect(await fixture.queries == ["Slack 是什么公司", "Slack 是什么公司"])
    }

    @Test func chineseParaphrasesAreNotSilentlyDeleted() async throws {
        let tool = WebSearchTool(call: { p, _, _ in
            if p == .parallel { return Self.result("Slack", "Salesforce acquired this collaboration platform.") }
            throw FreeWebFailure(status: "unavailable", message: "offline")
        })
        let value = try await tool.execute(["query": "Slack 企业沟通工具怎么用"]).output
        #expect(value["status"]?.stringValue == "partial")
        #expect(value["results"]?.arrayValue?.count == 1)
        #expect(value["missingTerms"]?.arrayValue?.isEmpty == false)
    }

    @Test func emptyIsDistinctFromServiceFailureAndCancellation() async throws {
        let empty = WebSearchTool(call: { p, _, _ in p == .parallel ? ["structuredContent": ["results": []]] : p == .keenable ? ["results": []] : ["content": [["type": "text", "text": "No results found"]]] })
        #expect(try await empty.execute(["query": "Orion Nova"]).output["status"]?.stringValue == "no_relevant_results")
        let broken = WebSearchTool(call: { _, _, _ in throw FreeWebFailure(status: "unavailable", message: "HTTP 403") })
        #expect(try await broken.execute(["query": "Orion Nova"]).output["status"]?.stringValue == "unavailable")
        let cancel = WebSearchTool(call: { _, _, _ in throw CancellationError() })
        do { _ = try await cancel.execute(["query": "Orion Nova"]); Issue.record("Cancellation swallowed") }
        catch is CancellationError { }
    }

    @Test func filtersSiteAndLoginWithoutDiscardingPartialSources() async throws {
        let tool = WebSearchTool(call: { p, _, _ in
            if p == .exa { return ["content": [["type": "text", "text": "No results found"]]] }
            return ["structuredContent": ["results": [
                ["title": "Slack", "url": "https://slack.com.evil.com/about", "excerpts": ["Slack"]],
                ["title": "Slack", "url": "https://slack.com/signin", "excerpts": ["Slack"]],
                ["title": "Slack", "url": "https://slack.com/about", "excerpts": ["Slack"]]]]]
        })
        let value = try await tool.execute(["query": "Slack site:slack.com"]).output
        #expect(value["results"]?.arrayValue?.count == 1)
        #expect(value["attempts"]?.arrayValue?.first?["rejected"]?.arrayValue?.count == 2)
    }

    @Test func validatesBeforeNetworkAndPageBounds() async throws {
        let never: FreeWebMCP.Call = { _, _, _ in Issue.record("Invalid request reached network"); throw CancellationError() }
        for args: JSONValue in [["query": " "], ["query": .string(String(repeating: "a", count: 501))], ["query": "swift", "count": 1.5], ["query": "swift", "count": 11]] {
            do { _ = try await WebSearchTool(call: never).execute(args); Issue.record("Invalid arguments accepted") }
            catch let error as ToolError { #expect(error.code == .invalidArguments) }
        }
        for url in ["file:///etc/passwd", "https://user:pass@example.com", "http://127.0.0.1", "http://localhost", "http://host.local", "http://[::1]"] {
            #expect(FreeWebMCP.publicURL(url) == nil)
            do { _ = try await WebReadPageTool(call: never).execute(["url": .string(url)]); Issue.record("Unsafe URL accepted") }
            catch let error as ToolError { #expect(error.code == .invalidArguments) }
        }
        let reader = WebReadPageTool(call: { _, _, args in
            #expect(args["full_content"]?.boolValue == true)
            return ["structuredContent": ["results": [["title": "Article", "url": "https://example.com", "full_content": .string(String(repeating: "x", count: 25000))]]]]
        })
        let value = try await reader.execute(["url": "https://example.com"]).output
        #expect(value["text"]?.stringValue?.count == 24000)
        #expect(value["truncated"]?.boolValue == true)
    }

    @Test func sourcePolicyAndMCPExposure() async throws {
        let store = try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory)
        let disabled = ToolService(store: store, policy: { PolicySnapshot(enabledSources: []) }, presenter: { _ in .rejected })
        await disabled.register(WebSearchTool()); await disabled.register(WebReadPageTool())
        #expect(await disabled.definitions(for: .agent(sessionID: "s")).isEmpty)
        for name in ["web_search", "web_read_page"] {
            #expect(await disabled.submit(ActionRequest(tool: name, arguments: [:], origin: .agent(sessionID: "s"), intent: .explicitRequest)).error?.code == .sourceDisabled)
        }
        let enabled = ToolService(store: store, policy: { PolicySnapshot(enabledSources: [.web]) }, presenter: { _ in .rejected })
        await enabled.register(WebSearchTool()); await enabled.register(WebReadPageTool())
        #expect(await enabled.definitions(for: .agent(sessionID: "s")).count == 2)
        #expect(await enabled.definitions(for: .mcp(instanceID: "s")).isEmpty)
    }

    @Test func liveXPublicPostThroughToolService() async throws {
        guard ProcessInfo.processInfo.environment["ASKY_LIVE_WEB_X"] == "1" else { return }
        let store = try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory)
        let service = ToolService(store: store, policy: { PolicySnapshot(enabledSources: [.web]) }, presenter: { _ in .rejected })
        await service.register(WebSearchTool()); await service.register(WebReadPageTool())
        let search = await service.submit(ActionRequest(tool: "web_search", arguments: ["query": "Gemini 4 Carbon site:x.com"], origin: .agent(sessionID: "live-x"), intent: .explicitRequest))
        let rows = search.output?["results"]?.arrayValue ?? []
        print("LIVE X search: \(search.output?["status"]?.stringValue ?? "failed"), results=\(rows.count)")
        guard let url = rows.compactMap({ $0["url"]?.stringValue }).first(where: { $0.contains("/status/") }) else {
            print("LIVE X: no public post URL returned; reading not verified")
            return
        }
        let page = await service.submit(ActionRequest(tool: "web_read_page", arguments: ["url": .string(url)], origin: .agent(sessionID: "live-x"), intent: .explicitRequest))
        let text = page.output?["text"]?.stringValue ?? ""
        print("LIVE X read: \(url) status=\(page.output?["status"]?.stringValue ?? "failed"), chars=\(text.count), excerpt=\(text.prefix(600))")
        // Availability is observed, not assumed for every X URL or login-only post.
        #expect(page.output?["status"]?.stringValue != nil)
    }

    @Test func liveChineseSearchAndPageReadingThroughToolService() async throws {
        guard ProcessInfo.processInfo.environment["ASKY_LIVE_WEB_SEARCH"] == "1" else { return }
        let store = try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory)
        let service = ToolService(store: store, policy: { PolicySnapshot(enabledSources: [.web]) }, presenter: { _ in .rejected })
        await service.register(WebSearchTool()); await service.register(WebReadPageTool())
        for query in ["Slack 是什么公司", "Kimi K3.1 Pro 评测 SWE-bench", "Gemini 4 Carbon 评测 开发者实测", "打工人三件套"] {
            let response = await service.submit(ActionRequest(tool: "web_search", arguments: ["query": .string(query)], origin: .agent(sessionID: "live"), intent: .explicitRequest))
            #expect(response.status == .completed)
            let output = response.output
            let rows = output?["results"]?.arrayValue ?? []
            #expect(!rows.isEmpty, "\(query): \(String(describing: output))")
            print("LIVE attempts: \(String(decoding: (output?["attempts"] ?? .null).canonicalData(), as: UTF8.self))")
            print("LIVE \(query): status=\(output?["status"]?.stringValue ?? "error") attempts=\(output?["attempts"]?.arrayValue?.count ?? 0)")
            for row in rows.prefix(3) { print("  \(row["title"]?.stringValue ?? ""): \(row["url"]?.stringValue ?? "") [\(row["snippet"]?.stringValue?.count ?? 0) chars]") }
        }
        let response = await service.submit(ActionRequest(tool: "web_read_page", arguments: ["url": "https://slack.com/intl/zh-cn/about"], origin: .agent(sessionID: "live"), intent: .explicitRequest))
        #expect(response.output?["status"]?.stringValue == "read", "\(String(describing: response.output))")
        #expect(response.output?["text"]?.stringValue?.contains("Salesforce") == true)
        print("LIVE read: provider=\(response.output?["provider"]?.stringValue ?? "") chars=\(response.output?["text"]?.stringValue?.count ?? 0) truncated=\(response.output?["truncated"]?.boolValue ?? true)")
    }
}

private actor FreeWebFixture {
    var queries: [String] = []
    func call(_ provider: FreeWebProvider, _ name: String, _ args: JSONValue) throws -> JSONValue {
        queries.append(args["objective"]?.stringValue ?? "")
        if provider == .parallel { throw FreeWebFailure(status: "rate_limited", message: "HTTP 429") }
        return ["content": [["type": "text", "text": "Title: Slack 公司介绍\nURL: https://slack.com/about\nHighlights:\nSlack 是企业协作平台。"]]]
    }
}
