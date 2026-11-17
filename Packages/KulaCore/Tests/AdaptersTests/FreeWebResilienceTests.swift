import Foundation
import Testing
import Contracts
import LocalStore
import ToolService
@testable import Adapters

@Suite struct FreeWebResilienceTests {
    @Test func pageFailuresDoNotDisableProviderButRateLimitsStillDo() async {
        let pool = FreeWebCoordinator()
        await pool.record(FreeWebFailure(status: "unavailable", message: "content_not_extracted", stage: "fetch", httpStatus: 422), provider: .keenable)
        await pool.record(FreeWebFailure(status: "unavailable", message: "CRAWL_LIVECRAWL_TIMEOUT", stage: "web_fetch_exa", httpStatus: 200), provider: .exa)
        #expect(await pool.skip(.keenable) == nil)
        #expect(await pool.skip(.exa) == nil)
        await pool.record(FreeWebFailure(status: "rate_limited", message: "quota", stage: "fetch", httpStatus: 429), provider: .keenable)
        #expect(await pool.skip(.keenable) != nil)
    }

    @Test func actualTransportRetainsDiagnosticsAndDoesNotWaitForSSEClose() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WebFixtureProtocol.self]
        for query in ["rpc", "http"] {
            do {
                _ = try await FreeWebMCP.performCall(.parallel, "web_search", ["objective": .string(query)], configuration: config)
                Issue.record("Provider error lost")
            } catch let error as FreeWebFailure {
                #expect(error.status == "rate_limited")
                #expect(error.stage == "web_search")
                #expect(error.retryAfter == 90)
                #expect(error.requestID == "fixture-request")
                #expect(error.httpStatus == (query == "http" ? 429 : 200))
                if query == "rpc" { #expect(error.rpcCode == -32000) }
                #expect(error.message.contains("quota"))
            }
        }
        // The fixture deliberately never closes this event stream. A wait-for-EOF client times out.
        let result = try await FreeWebMCP.performCall(.parallel, "web_search", ["objective": "stream"], configuration: config)
        #expect(result["structuredContent"]?["results"]?.arrayValue == [])
    }

    @Test func rpcErrorsRetainReasonCodeAndNullID() throws {
        for raw in [
            #"{"jsonrpc":"2.0","id":2,"error":{"code":-32000,"message":"Quota exceeded; retry later"}}"#,
            #"{"jsonrpc":"2.0","id":null,"error":{"code":-32000,"message":"Quota exceeded; retry later"}}"#
        ] {
            do { _ = try FreeWebMCP.decode(Data(raw.utf8), id: 2); Issue.record("Error discarded") }
            catch let error as FreeWebFailure {
                #expect(error.status == "rate_limited")
                #expect(error.rpcCode == -32000)
                #expect(error.message.contains("Quota exceeded"))
            }
        }
        let unrelated = #"{"id":7,"result":{"content":[]}}"#
        #expect(throws: FreeWebFailure.self) { try FreeWebMCP.decode(Data(unrelated.utf8), id: 2) }
        let batch = #"[{"method":"notifications/progress"},{"id":"2","result":{"content":[]}}]"#
        #expect(try FreeWebMCP.decode(Data(batch.utf8), id: 2)["result"] != nil)
        let sse = "event: message\ndata: {\"id\":2,\ndata: \"result\":{\"content\":[]}}\n\n"
        #expect(try FreeWebMCP.envelope(Data(sse.utf8), id: 2)?["result"] != nil)
        let mixed: JSONValue = ["content": [["type": "text", "text": "extra provider note"],
            ["type": "text", "text": "{\"results\":[]}"]]]
        #expect(try FreeWebMCP.structured(mixed)["results"]?.arrayValue == [])
    }

    @Test func retryAfterAndCooldownDoNotBlockOtherVendors() async throws {
        let clock = WebTestClock()
        let pool = FreeWebCoordinator(now: { clock.now })
        #expect(FreeWebMCP.retryDelay("120") == 120)
        #expect(FreeWebMCP.retryDelay("Thu, 01 Jan 1970 00:02:00 GMT", now: Date(timeIntervalSince1970: 0)) == 120)
        #expect(FreeWebMCP.retryDelay("invalid") == nil)
        await pool.record(FreeWebFailure(status: "rate_limited", message: "slow down", retryAfter: 120), provider: .parallel)
        #expect(await pool.skip(.parallel)?["skipped"]?.boolValue == true)
        #expect(await pool.skip(.exa) == nil)
        let first = await pool.providers(), second = await pool.providers()
        #expect(first == [.parallel, .exa, .keenable])
        #expect(second == [.parallel, .keenable, .exa])
        clock.advance(121)
        #expect(await pool.skip(.parallel) == nil)
        await pool.record(FreeWebFailure(status: "unavailable", message: "Origin blocked this page", stage: "page"), provider: .exa)
        #expect(await pool.skip(.exa) == nil)
    }

    @Test func thirdProviderRecoversAndNextQuerySkipsThrottledPrimary() async throws {
        let calls = WebTestCalls()
        let pool = FreeWebCoordinator()
        let tool = WebSearchTool(call: { provider, _, _ in
            await calls.add()
            if provider == .parallel { throw FreeWebFailure(status: "rate_limited", message: "HTTP 429", retryAfter: 60) }
            if provider == .exa { throw FreeWebFailure(status: "unavailable", message: "HTTP 503", httpStatus: 503) }
            return ["results": [["title": "Slack", "url": "https://slack.com/about", "snippet": "Slack company Salesforce"]]]
        }, coordinator: pool)
        let first = try await tool.execute(["query": "Slack 是什么公司"]).output
        #expect(first["results"]?.arrayValue?.first?["provider"]?.stringValue == "Keenable")
        #expect(await calls.count == 3)
        let second = try await tool.execute(["query": "Slack company"]).output
        #expect(second["attempts"]?.arrayValue?.first?["skipped"]?.boolValue == true)
        #expect(await calls.count == 4)
        let cached = try await tool.execute(["query": "Slack 是什么公司"]).output
        #expect(cached["cached"]?.boolValue == true)
        #expect(cached["attempts"]?.arrayValue == [])
        #expect(cached["sourceAttempts"]?.arrayValue?.count == 3)
        #expect(await calls.count == 4)
    }

    @Test func cacheExpiresEvictsAndNeverCachesFailure() async throws {
        let clock = WebTestClock(), calls = WebTestCalls()
        let pool = FreeWebCoordinator(ttl: 10, byteLimit: 1024, entryLimit: 1, now: { clock.now })
        let success: @Sendable () async throws -> JSONValue = { await calls.add(); return ["status": "read", "text": "page", "attempts": []] }
        _ = try await pool.run(key: "a", operation: success)
        #expect(try await pool.run(key: "a", operation: success)["cached"]?.boolValue == true)
        clock.advance(11)
        _ = try await pool.run(key: "a", operation: success)
        _ = try await pool.run(key: "b", operation: success)
        _ = try await pool.run(key: "a", operation: success)
        #expect(await calls.count == 4)
        for _ in 0..<2 {
            _ = try await pool.run(key: "failed") { await calls.add(); return ["status": "unavailable"] }
        }
        #expect(await calls.count == 6)
        for _ in 0..<2 {
            _ = try await pool.run(key: "large") {
                await calls.add(); return ["status": "read", "text": .string(String(repeating: "x", count: 2048))]
            }
        }
        #expect(await calls.count == 8)
    }

    @Test func concurrentDuplicatesShareRequestAndCancellationIsIndependent() async throws {
        let pool = FreeWebCoordinator(), calls = WebTestCalls()
        let operation: @Sendable () async throws -> JSONValue = {
            await calls.add()
            try await Task.sleep(for: .milliseconds(200))
            return ["status": "read", "text": "page", "attempts": [["provider": "Parallel"]]]
        }
        let first = Task { try await pool.run(key: "same", operation: operation) }
        try await Task.sleep(for: .milliseconds(30))
        let second = Task { try await pool.run(key: "same", operation: operation) }
        try await Task.sleep(for: .milliseconds(30))
        first.cancel()
        do { _ = try await first.value; Issue.record("Cancelled waiter returned a result") } catch is CancellationError { }
        let result = try await second.value
        #expect(result["coalesced"]?.boolValue == true)
        #expect(result["attempts"]?.arrayValue == [])
        #expect(await calls.count == 1)
        #expect(try await pool.run(key: "same", operation: operation)["cached"]?.boolValue == true)
    }

    @Test func cancellingLastWaiterCancelsUnderlyingWorkAndAllowsRetry() async throws {
        let pool = FreeWebCoordinator(), calls = WebTestCalls()
        let task = Task {
            try await pool.run(key: "cancel") {
                await calls.add()
                do { try await Task.sleep(for: .seconds(10)) }
                catch { await calls.cancelled(); throw error }
                return ["status": "read", "text": "stale"]
            }
        }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancellation swallowed") } catch is CancellationError { }
        let fresh = try await pool.run(key: "cancel") { ["status": "read", "text": "fresh"] }
        #expect(fresh["text"]?.stringValue == "fresh")
        try await Task.sleep(for: .milliseconds(20))
        #expect(await calls.cancellations == 1)
    }

    @Test func keenableRequestsHaveNoCredentialsAndPreserveURL() throws {
        let search = try FreeWebMCP.keenableRequest(name: "search", arguments: ["query": "中文 C++", "numResults": 5])
        let page = try FreeWebMCP.keenableRequest(name: "fetch", arguments: ["urls": ["https://example.com/a?x=1&y=中文"]])
        for request in [search, page] {
            #expect(request.value(forHTTPHeaderField: "X-Keenable-Title") == "Asky")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "X-API-Key") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        }
        #expect(search.httpMethod == "POST")
        #expect(page.httpMethod == "GET")
        #expect(URLComponents(url: page.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "https://example.com/a?x=1&y=中文")
    }

    @Test func liveKeenableRecoveryThroughToolService() async throws {
        guard ProcessInfo.processInfo.environment["ASKY_LIVE_WEB_KEENABLE"] == "1" else { return }
        let pool = FreeWebCoordinator()
        let call: FreeWebMCP.Call = { provider, name, arguments in
            guard provider == .keenable else {
                throw FreeWebFailure(status: "unavailable", message: "Fixture: primary unavailable")
            }
            return try await FreeWebMCP.call(provider, name, arguments)
        }
        let store = try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory)
        let service = ToolService(store: store, policy: { PolicySnapshot(enabledSources: [.web]) }, presenter: { _ in .rejected })
        await service.register(WebSearchTool(call: call, coordinator: pool))
        await service.register(WebReadPageTool(call: call, coordinator: pool))
        for query in ["Slack 是什么公司", "Kimi K3.1 Pro 评测 SWE-bench", "Gemini 4 Carbon 评测 开发者实测", "打工人三件套"] {
            let result = await service.submit(ActionRequest(tool: "web_search", arguments: ["query": .string(query)], origin: .agent(sessionID: "keenable-live"), intent: .explicitRequest))
            #expect(result.output?["results"]?.arrayValue?.isEmpty == false, "\(String(describing: result.output))")
            print("KEENABLE \(query): status=\(result.output?["status"]?.stringValue ?? "error") results=\(result.output?["results"]?.arrayValue?.count ?? 0)")
            for row in result.output?["results"]?.arrayValue?.prefix(2) ?? [] { print("  \(row["title"]?.stringValue ?? ""): \(row["url"]?.stringValue ?? "")") }
        }
        let args: JSONValue = ["url": "https://slack.com/intl/zh-cn/about"]
        let request = ActionRequest(tool: "web_read_page", arguments: args, origin: .agent(sessionID: "keenable-live"), intent: .explicitRequest)
        let page = await service.submit(request)
        #expect(page.output?["status"]?.stringValue == "read", "\(String(describing: page.output))")
        #expect(page.output?["text"]?.stringValue?.contains("Salesforce") == true)
        print("KEENABLE read: \(page.output?["text"]?.stringValue?.count ?? 0) chars; attempts=\(String(describing: page.output?["attempts"]))")
        // Fresh request ID to exercise the adapter cache, not ToolService request de-duplication.
        let repeated = await service.submit(ActionRequest(tool: "web_read_page", arguments: args, origin: .agent(sessionID: "keenable-live"), intent: .explicitRequest))
        #expect(repeated.output?["cached"]?.boolValue == true)
        #expect(repeated.output?["attempts"]?.arrayValue == [])
    }
}

private actor WebTestCalls {
    var count = 0
    var cancellations = 0
    func add() { count += 1 }
    func cancelled() { cancellations += 1 }
}

private final class WebTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value.addTimeInterval(seconds) } }
}

private final class WebFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(contentsOf: buffer.prefix(read))
            }
        }
        let payload = try? JSONDecoder().decode(JSONValue.self, from: data)
        let method = payload?["method"]?.stringValue ?? ""
        let query = payload?["params"]?["arguments"]?["objective"]?.stringValue ?? ""
        var status = 200, headers = ["Content-Type": "application/json"]
        let body: String
        var finish = true
        switch method {
        case "initialize":
            body = #"{"id":1,"result":{"protocolVersion":"2025-06-18"}}"#
        case "notifications/initialized":
            status = 202; body = ""
        default:
            headers["Retry-After"] = "90"
            headers["x-request-id"] = "fixture-request"
            if query == "rpc" {
                body = #"{"id":null,"error":{"code":-32000,"message":"quota exceeded"}}"#
            } else if query == "http" {
                status = 429; body = "quota exceeded"
            } else {
                headers["Content-Type"] = "text/event-stream"
                body = "data: {\"id\":2,\"result\":{\"structuredContent\":{\"results\":[]}}}\n\n"
                finish = false
            }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        if finish { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() { }
}
