import Foundation
import Testing
import Contracts
import ToolService
@testable import AgentHost

private actor ModelScript {
    var requests: [JSONValue] = []
    var replies: [NativeCompletion]
    init(_ replies: [NativeCompletion]) { self.replies = replies }
    func respond(_ request: URLRequest, delta: @Sendable (String) -> Void) throws -> NativeCompletion {
        requests.append(try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody)))
        let reply = replies.removeFirst(); delta(reply.text); return reply
    }
}
private func call(_ name: String, _ arguments: JSONValue = [:], id: String = "call_1") -> JSONValue {
    ["id": .string(id), "type": "function", "function": ["name": .string(name), "arguments": .string(String(decoding: arguments.canonicalData(), as: UTF8.self))]]
}
private func collect(_ host: AgentHost, _ request: AgentRequest) async -> [AgentEvent] {
    var events: [AgentEvent] = []
    for await event in await host.submit(request) { events.append(event) }
    return events
}
private func host(root: URL, script: ModelScript, tools: [ToolDefinition] = [],
                  handler: @escaping AgentHost.ToolHandler = { .failure($0.requestID, .adapterFailure, "unexpected tool") },
                  imageValidator: @escaping @Sendable ([URL]) async throws -> Set<URL> = { Set($0) }) -> AgentHost {
    let storage = AgentSessionStorage(root: root)
    return AgentHost(launcher: { NativeRuntime(storage: storage, client: NativeModelClient(transport: { request, delta in try await script.respond(request, delta: delta) }), imageValidator: imageValidator) },
        configProvider: { RuntimeLaunchConfig(baseURL: "https://example.test/v1", model: "mock", apiKey: "secret-not-persisted") },
        toolsProvider: { tools }, toolHandler: handler)
}

@Suite(.timeLimit(.minutes(1))) struct NativeRuntimeTests {
    @Test func stablePrefixAcrossSubmissionsAndToolContinuation() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = ModelScript([NativeCompletion(text: "四"), NativeCompletion(calls: [call("lookup")]),
                                  NativeCompletion(text: "六")])
        let definition = ToolDefinition(name: "lookup", summary: "read", source: .web, effect: .read,
                                        confirmation: .never, externallyExposable: false)
        let agent = host(root: root, script: script, tools: [definition]) {
            ExecutionResult(requestID: $0.requestID, status: .completed, output: ["value": 6])
        }
        let history = ContextSnippet(sourceID: "history", text: "此前的对话")
        _ = await collect(agent, AgentRequest(sessionID: "a", text: "二加二", context: [history]))
        _ = await collect(agent, AgentRequest(sessionID: "b", text: "三加三", context: [history]))
        let requests = await script.requests
        await agent.shutdown()
        try #require(requests.count == 3)
        let first = try #require(requests[0]["messages"]?.arrayValue)
        let next = try #require(requests[1]["messages"]?.arrayValue)
        let continuation = try #require(requests[2]["messages"]?.arrayValue)
        #expect(first.first == next.first)
        #expect(first.first?["content"]?.stringValue?.contains("当前本地时间：") == false)
        #expect(requests[0]["tools"] == requests[1]["tools"])
        #expect(requests[0]["stream_options"] == nil) // Custom endpoints retain their existing wire options.
        #expect(continuation.starts(with: next))
        #expect(continuation.last?["role"] == "tool")

        let storage = AgentSessionStorage(root: root)
        let submission = AgentRequest(sessionID: "fixed", text: "明天下午", context: [history])
        let firstTime = Date(timeIntervalSince1970: 1_800_000_000)
        let firstText = try #require(try await storage.input(submission, now: firstTime).stringValue)
        let laterText = try #require(try await storage.input(submission, now: firstTime.addingTimeInterval(60)).stringValue)
        #expect(firstText != laterText)
        let clock = try #require(firstText.range(of: "本轮提交时间："))
        #expect(firstText[..<clock.lowerBound].contains(history.text))
        #expect(laterText.hasPrefix(String(firstText[..<clock.upperBound])))
        #expect(firstText.hasSuffix(submission.text))
    }

    @Test(arguments: [true, false]) func cacheUsageSurvivesFinalStreamChunk(separate: Bool) throws {
        let usage: JSONValue = ["prompt_cache_hit_tokens": 0, "prompt_cache_miss_tokens": 2048]
        var decoder = NativeCompletionDecoder()
        _ = try decoder.consume(["choices": [["delta": ["content": "ok"], "finish_reason": "stop"]],
                                 "usage": separate ? .null : usage])
        if separate { _ = try decoder.consume(["choices": [], "usage": usage]) }
        let reply = try decoder.result()
        #expect(reply.cacheUsage?.hit == 0)
        #expect(reply.cacheUsage?.miss == 2048)
        #expect(reply.message == ["role": "assistant", "content": "ok"])
        #expect(PromptCacheUsage(["prompt_cache_miss_tokens": 1]) == nil)
    }

    @Test func inventedImageDraftIsCorrectedOnceBeforePublication() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bad = "![捏造](https://example.com/fake.jpg)"
        let good = "珠峰正文\n\n![照片](https://example.com/real.jpg)"
        let script = ModelScript([NativeCompletion(text: bad), NativeCompletion(calls: [call("web_read_page")]), NativeCompletion(text: good)])
        let definition = ToolDefinition(name: "web_read_page", summary: "read", source: .web, effect: .read, confirmation: .never, externallyExposable: false)
        let agent = host(root: root, script: script, tools: [definition]) { request in
            ExecutionResult(requestID: request.requestID, status: .completed, output: ["images": [["url": "https://example.com/real.jpg"]]])
        }
        let events = await collect(agent, AgentRequest(sessionID: "s", text: "介绍珠峰"))
        #expect(events.compactMap { if case .message(_, let text) = $0 { text } else { nil } } == [good])
        #expect(!events.contains { if case .textDelta(_, let text) = $0 { text.contains("fake.jpg") } else { false } })
        let saved = try await AgentSessionStorage(root: root).load(sessionID: "s", legacyPath: nil)
        #expect(!saved.contains { $0["content"] == .string(bad) })
        #expect(await script.requests.count == 3)
        await agent.shutdown()
    }

    @Test func repeatedInventedImagesAreRemovedWithoutFurtherModelRounds() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let reply = "保留**正文**。\n\n![假的](https://example.com/fake.jpg)"
        let script = ModelScript([NativeCompletion(text: reply), NativeCompletion(text: reply)])
        let definition = ToolDefinition(name: "web_read_page", summary: "read", source: .web, effect: .read, confirmation: .never, externallyExposable: false)
        let agent = host(root: root, script: script, tools: [definition], imageValidator: { urls in
            Issue.record("Invented URLs must never be downloaded"); return Set(urls)
        })
        let events = await collect(agent, AgentRequest(sessionID: "s", text: "介绍"))
        #expect(events.contains { if case .message(_, "保留**正文**。\n\n") = $0 { true } else { false } })
        #expect(await script.requests.count == 2)
        await agent.shutdown()
    }

    @Test func brokenSourcedImagesAreRemovedAndValidSiblingsSurvive() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let reply = "正文\n![好图](https://example.com/good.jpg)\n![坏图](https://example.com/broken.jpg)"
        let script = ModelScript([NativeCompletion(text: reply)])
        let agent = host(root: root, script: script, imageValidator: { urls in
            #expect(urls.count == 2)
            return Set(urls.filter { $0.lastPathComponent == "good.jpg" })
        })
        let events = await collect(agent, AgentRequest(sessionID: "s", text: "查看 https://example.com/good.jpg 和 https://example.com/broken.jpg"))
        #expect(events.contains { if case .message(_, "正文\n![好图](https://example.com/good.jpg)\n") = $0 { true } else { false } })
        await agent.shutdown()
    }

    @Test func terminalImageBatchAllowsOneURLCorrectionWithoutReopeningWebTools() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let good = "![山峰](https://example.com/original.jpg)"
        let script = ModelScript([NativeCompletion(calls: [call("web_read_page", ["imagesOnly": true])]),
            NativeCompletion(text: "![山峰](https://example.com/resized.jpg)"), NativeCompletion(text: good)])
        let definition = ToolDefinition(name: "web_read_page", summary: "read", source: .web, effect: .read, confirmation: .never, externallyExposable: false)
        let agent = host(root: root, script: script, tools: [definition]) { request in
            ExecutionResult(requestID: request.requestID, status: .completed, output: ["images": [["url": "https://example.com/original.jpg"]]])
        }
        let events = await collect(agent, AgentRequest(sessionID: "s", text: "介绍珠峰"))
        #expect(events.filter { if case .toolCall = $0 { true } else { false } }.count == 1)
        #expect(events.contains { if case .message(_, good) = $0 { true } else { false } })
        let requests = await script.requests
        #expect(requests.first?["tools"] == requests.last?["tools"], "Tools stay frozen to preserve prompt cache")
        await agent.shutdown()
    }

    @Test func cancellingImageValidationDoesNotPublishTheDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (started, signal) = AsyncStream<Void>.makeStream()
        let script = ModelScript([NativeCompletion(text: "![图](https://example.com/photo.jpg)")])
        let agent = host(root: root, script: script, imageValidator: { urls in
            signal.yield(())
            try await Task.sleep(for: .seconds(30))
            return Set(urls)
        })
        let task = Task { await collect(agent, AgentRequest(sessionID: "s", taskID: "t", text: "查看 https://example.com/photo.jpg")) }
        for await _ in started { break }
        await agent.cancel(taskID: "t")
        #expect(!(await task.value).contains { if case .message = $0 { true } else { false } })
        await agent.shutdown()
    }

    @Test func imageOnlyBatchEndsWebResearchEvenWhenOptionalImagesAreMissing() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = ModelScript([
            NativeCompletion(calls: [call("web_read_page", ["imagesOnly": true], id: "photo-a"),
                call("web_read_page", ["imagesOnly": true], id: "photo-b")]),
            NativeCompletion(calls: [call("web_search", id: "unnecessary-research")]),
            NativeCompletion(text: "文字资料支持的区别")])
        let definitions = ["web_read_page", "web_search"].map {
            ToolDefinition(name: $0, summary: $0, source: .web, effect: .read, confirmation: .never, externallyExposable: false)
        }
        let agent = host(root: root, script: script, tools: definitions) { request in
            #expect(request.tool == "web_read_page")
            return ExecutionResult(requestID: request.requestID, status: .completed,
                output: ["status": "images_not_found", "images": [], "contentType": "image_metadata"])
        }
        let events = await collect(agent, AgentRequest(sessionID: "s", text: "比较这些景点"))
        #expect(events.filter { if case .toolCall = $0 { true } else { false } }.count == 2)
        let requests = await script.requests
        #expect(requests[1]["tools"] == requests[0]["tools"], "Tools stay frozen to preserve prompt cache")
        #expect(events.contains { if case .message(_, "文字资料支持的区别") = $0 { true } else { false } })
        await agent.shutdown()
    }

    @Test func pendingWebReadDoesNotHoldBackNextIndependentRead() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = RollingWebProbe()
        let script = ModelScript([NativeCompletion(calls: (0..<4).map {
            call("web_search", ["n": .number(Double($0))], id: "read-\($0)")
        }), NativeCompletion(text: "完成")])
        let definition = ToolDefinition(name: "web_search", summary: "read", source: .web,
            effect: .read, confirmation: .never, externallyExposable: false)
        let agent = host(root: root, script: script, tools: [definition]) { await probe.run($0) }
        _ = await collect(agent, AgentRequest(sessionID: "s", text: "查询四个对象"))
        #expect(await probe.fourthStartedBeforeSlowReadFinished)
        await agent.shutdown()
    }

    @Test func exhaustedWebSourcesStopFurtherNetworkCallsForThisTurn() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = ModelScript([NativeCompletion(calls: [call("web_search")]),
            NativeCompletion(calls: [call("web_read_page", id: "ignored-capability")]), NativeCompletion(text: "已有资料")])
        let definitions = ["web_search", "web_read_page"].map {
            ToolDefinition(name: $0, summary: $0, source: .web, effect: .read, confirmation: .never, externallyExposable: false)
        }
        let agent = host(root: root, script: script, tools: definitions) { request in
            #expect(request.tool == "web_search", "A model ignoring the removed capability must not reach the network")
            return ExecutionResult(requestID: request.requestID, status: .completed, output: ["status": "rate_limited",
                "attempts": [["provider": "Parallel", "skipped": true, "stage": "cooldown"]]])
        }
        let events = await collect(agent, AgentRequest(sessionID: "s", text: "介绍"))
        #expect(events.filter { if case .toolCall = $0 { true } else { false } }.count == 1)
        let requests = await script.requests
        #expect(requests[1]["tools"] == requests[0]["tools"], "Tools stay frozen to preserve prompt cache")
        #expect(events.contains { if case .message(_, "已有资料") = $0 { true } else { false } })
        await agent.shutdown()
    }

    @Test func cancellingParallelReadsStopsBeforeFollowingWrite() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (started, signal) = AsyncStream<String>.makeStream()
        let script = ModelScript([NativeCompletion(calls: [call("web_search", id: "a"),
            call("web_read_page", id: "b"), call("write", id: "w")])])
        let definitions = ["web_search", "web_read_page", "write"].map {
            ToolDefinition(name: $0, summary: $0, source: .web, effect: $0 == "write" ? .write : .read,
                confirmation: $0 == "write" ? .always : .never, externallyExposable: false)
        }
        let agent = host(root: root, script: script, tools: definitions) { request in
            #expect(request.tool != "write")
            signal.yield(request.tool)
            do { try await Task.sleep(for: .seconds(30)) } catch { }
            return .failure(request.requestID, .cancelled, "cancelled", status: .cancelled)
        }
        let task = Task { await collect(agent, AgentRequest(sessionID: "s", taskID: "t", text: "查询")) }
        var count = 0
        for await _ in started { count += 1; if count == 2 { break } }
        await agent.cancel(taskID: "t")
        let events = await task.value
        #expect(events.filter { if case .toolCall = $0 { true } else { false } }.count == 2)
        #expect(await script.requests.count == 1)
        await agent.shutdown()
        let saved = try await AgentSessionStorage(root: root).load(sessionID: "s", legacyPath: nil)
        #expect(saved.filter { $0["role"] == "tool" }.count == 3, "Restore must close every interrupted tool pair without replay")
    }

    @Test func webProjectionLeavesWritesAndSearchSourcesIntact() throws {
        let text = String(repeating: "资料🙂", count: 10_000)
        let output: JSONValue = ["status": "completed", "output": ["results": .array((0..<5).map { i in
            ["url": .string("https://example.com/\(i)"), "snippet": .string(text)] as JSONValue
        })]]
        let raw = String(decoding: output.canonicalData(), as: UTF8.self)
        let messages: [JSONValue] = [NativeCompletion(calls: [call("web_search")]).message,
            ["role": "tool", "tool_call_id": "call_1", "content": .string(raw)],
            NativeCompletion(calls: [call("write")]).message,
            ["role": "tool", "tool_call_id": "call_1", "content": .string(raw)]]
        let projected = NativeWebContext.messages(messages)
        #expect(projected[3] == messages[3], "Reused model call IDs cannot cause write results to be shortened")
        let result = try JSONDecoder().decode(JSONValue.self, from: Data(try #require(projected[1]["content"]?.stringValue).utf8))
        let rows = try #require(result["output"]?["results"]?.arrayValue)
        #expect(rows.count == 5)
        #expect(rows.allSatisfy { $0["truncated"] == true && $0["url"] != nil })
        #expect(rows.reduce(0) { $0 + ($1["snippet"]?.stringValue?.utf8.count ?? 0) } <= NativeWebContext.perResultBudget)
    }

    @Test func webReadsOverlapButWritesAndClarificationRemainBarriers() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = WebOverlapProbe()
        let reads = (0..<4).map { call("web_search", ["n": .number(Double($0))], id: "r\($0)") }
        let script = ModelScript([NativeCompletion(calls: reads + [call("write", id: "w"),
            call("web_read_page", id: "page"), call("ask_user", ["question": "哪一天？"], id: "q"),
            call("write", id: "must-not-run")])])
        let definitions = ["web_search", "web_read_page", "write"].map {
            ToolDefinition(name: $0, summary: $0, source: .web, effect: $0 == "write" ? .write : .read,
                confirmation: $0 == "write" ? .always : .never, externallyExposable: false)
        }
        let agent = host(root: root, script: script, tools: definitions) { await probe.run($0) }
        let events = await collect(agent, AgentRequest(sessionID: "s", text: "查询后写入"))
        #expect(await probe.peak == 3)
        #expect(await probe.writes == 1)
        #expect(events.contains { if case .clarification = $0 { true } else { false } })
        let saved = try await AgentSessionStorage(root: root).load(sessionID: "s", legacyPath: nil)
        #expect(saved.filter { $0["role"] == "tool" }.compactMap { $0["tool_call_id"]?.stringValue }
            == ["r0", "r1", "r2", "r3", "w", "page", "q", "must-not-run"])
        await agent.shutdown()
    }

    @Test func requestBoundsSingleTurnWebProseWithoutChangingStoredEvidence() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let calls = (0..<10).map { call("web_read_page", id: "p\($0)") }
        let script = ModelScript([NativeCompletion(calls: calls), NativeCompletion(text: "完成")])
        let definition = ToolDefinition(name: "web_read_page", summary: "read", source: .web,
            effect: .read, confirmation: .never, externallyExposable: false)
        let original = String(repeating: "完整网页中文内容🙂", count: 8000)
        let agent = host(root: root, script: script, tools: [definition]) {
            ExecutionResult(requestID: $0.requestID, status: .completed, output: ["text": .string(original),
                "url": "https://example.com/page", "images": [["url": "https://example.com/photo.jpg"]], "truncated": false])
        }
        _ = await collect(agent, AgentRequest(sessionID: "s", text: "比较这些页面"))
        let requests = await script.requests
        #expect(requests.count == 2, "No extra summarization round should delay a single user turn")
        let sent = try #require(requests.last?["messages"]?.arrayValue)
        var prose = 0
        for message in sent where message["role"] == "tool" {
            let data = Data(try #require(message["content"]?.stringValue).utf8)
            let output = try JSONDecoder().decode(JSONValue.self, from: data)["output"]
            prose += output?["text"]?.stringValue?.utf8.count ?? 0
            #expect(output?["truncated"] == true)
            #expect(output?["images"]?.arrayValue?.first?["url"] == "https://example.com/photo.jpg")
            #expect(output?["text"]?.stringValue?.contains("�") == false)
        }
        #expect(prose <= NativeWebContext.proseBudget)
        let saved = try await AgentSessionStorage(root: root).load(sessionID: "s", legacyPath: nil)
        let content = try #require(saved.first { $0["role"] == "tool" }?["content"]?.stringValue)
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(content.utf8))["output"]?["text"] == .string(original))
        await agent.shutdown()
    }

    @Test(arguments: [true, false]) func currentImageCapabilityFollowsHistoryWithoutPersisting(hasPageReader: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let name = hasPageReader ? "web_read_page" : "lookup"
        let script = ModelScript([NativeCompletion(calls: [call(name)]), NativeCompletion(text: "回复")])
        let definition = ToolDefinition(name: name, summary: "Read", source: .web, effect: .read, confirmation: .never, externallyExposable: false)
        let agent = host(root: root, script: script, tools: [definition]) { ExecutionResult(requestID: $0.requestID, status: .completed) }
        _ = await collect(agent, AgentRequest(sessionID: "s", text: "介绍一位演员",
            context: [ContextSnippet(sourceID: "history", text: "此前助手错误地说不能展示图片。")]))
        let requests = await script.requests
        #expect(requests.count == 2)
        for request in requests {
            let messages = try #require(request["messages"]?.arrayValue)
            #expect(messages.filter { $0["role"] == "system" }.count == 1)
            #expect(messages.first?["role"] == "system")
            let systemContent = try #require(messages.first?["content"]?.stringValue)
            #expect(systemContent.contains("本轮能力核对：") == hasPageReader)
        }
        #expect(requests[0]["messages"]?.arrayValue?.first == requests[1]["messages"]?.arrayValue?.first)
        let stored = try await AgentSessionStorage(root: root).load(sessionID: "s", legacyPath: nil)
        #expect(!stored.contains { $0["role"] == "system" })
        #expect(stored.last?["content"] == "回复")
        await agent.shutdown()
    }

    @Test func webProjectionPreservesEarlierResultsAcrossAppendedWebCalls() throws {
        let longText = String(repeating: "网页正文片段。", count: 3_000)
        func makeRound(_ id: String) -> [JSONValue] {
            let output: JSONValue = ["status": "completed", "output": ["text": .string(longText), "url": .string("https://example.com/\(id)")]]
            return [
                NativeCompletion(calls: [call("web_read_page", id: id)]).message,
                ["role": "tool", "tool_call_id": .string(id), "content": .string(String(decoding: output.canonicalData(), as: UTF8.self))]
            ]
        }
        let firstFour = (0..<4).flatMap { makeRound("p\($0)") }
        let projectedFour = NativeWebContext.messages(firstFour)
        let withFifth = firstFour + makeRound("p4")
        let projectedFive = NativeWebContext.messages(withFifth)
        #expect(Array(projectedFive.prefix(projectedFour.count)) == projectedFour,
                "Appending a fifth web tool result must not mutate earlier projected messages")
    }

    @Test func streamsReplyAndPublishesOnlyTheFinalMessage() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let texts = ["先查看项目。", "已找到项目，接下来查看工作区。", "### 操作结果\n\n- 项目：**Asky**\n- 终端：`term_5`"]
        let script = ModelScript([
            NativeCompletion(text: texts[0], calls: [call("lookup")]),
            NativeCompletion(text: texts[1], calls: [call("lookup", id: "second")]),
            NativeCompletion(text: texts[2])
        ])
        let definition = ToolDefinition(name: "lookup", summary: "Read", source: .calendar, effect: .read, confirmation: .never, externallyExposable: false)
        let agent = host(root: root, script: script, tools: [definition]) { ExecutionResult(requestID: $0.requestID, status: .completed) }
        let events = await collect(agent, AgentRequest(sessionID: "s", taskID: "t", text: "查看项目"))
        let messages = events.compactMap { event -> String? in if case .message(_, let text) = event { return text }; return nil }
        #expect(messages == [texts[2]])
        #expect(events.contains { if case .textDelta = $0 { return true }; return false })
        #expect(events.filter { if case .toolCall = $0 { return true }; return false }.count == 2)
        let history = try await AgentSessionStorage(root: root).load(sessionID: "s", legacyPath: nil)
        #expect(history.contains { $0["content"]?.stringValue == texts[0] })
        await agent.shutdown()
    }

    @Test func textToolsAndResumeWithoutNode() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = ModelScript([NativeCompletion(calls: [call("lookup")]), NativeCompletion(text: "第一轮完成")])
        let definition = ToolDefinition(name: "lookup", summary: "Read", inputSchema: ["type": "object"], source: .calendar, effect: .read, confirmation: .never, externallyExposable: false)
        let first = host(root: root, script: script, tools: [definition]) { req in
            #expect(req.intent == .aiSuggested)
            return ExecutionResult(requestID: req.requestID, status: .completed, output: ["answer": 42])
        }
        let events = await collect(first, AgentRequest(sessionID: "session", taskID: "task", text: "先查一下"))
        #expect(events.contains(.message(taskID: "task", "第一轮完成")))
        #expect(await first.runningPID == nil)
        #expect(await first.launchCount == 1)
        let file = try #require(await first.sessionFile(for: "session"))
        #expect(!String(decoding: try Data(contentsOf: URL(filePath: file)), as: UTF8.self).contains("secret-not-persisted"))
        await first.shutdown()
        let nextScript = ModelScript([NativeCompletion(text: "继续")])
        let second = host(root: root, script: nextScript)
        await second.setSessionFile(file, for: "session")
        _ = await collect(second, AgentRequest(sessionID: "session", text: "继续刚才的"))
        let sent = try #require(await nextScript.requests.first?["messages"]?.arrayValue)
        #expect(sent.contains { $0["content"]?.stringValue == "第一轮完成" })
        #expect(sent.contains { $0["role"]?.stringValue == "tool" && $0["content"]?.stringValue?.contains("42") == true })
        await second.shutdown()
    }

    @Test func clarificationPersistsAndSkipsSiblingWrites() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = ModelScript([NativeCompletion(calls: [call("ask_user", ["question": "哪一天？"]), call("write", id: "sibling")])])
        let agent = host(root: root, script: script)
        let events = await collect(agent, AgentRequest(sessionID: "s", taskID: "t", text: "安排一下"))
        #expect(events.contains(.clarification(taskID: "t", question: "哪一天？")))
        #expect(events.contains(.taskState(taskID: "t", .awaitingInput)))
        let messages = try await AgentSessionStorage(root: root).load(sessionID: "s", legacyPath: nil)
        #expect(messages.last?["tool_call_id"] == "sibling")
        #expect(messages.last?["content"]?.stringValue?.contains("cancelled") == true)
        await agent.shutdown()
    }

    @Test func writeIntentAndToolLimit() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = ModelScript([NativeCompletion(calls: [call("write", ["userRequested": true])]), NativeCompletion(text: "完成")])
        let definition = ToolDefinition(name: "write", summary: "Write", inputSchema: ["type": "object"], source: .calendar, effect: .write, confirmation: .always, externallyExposable: false)
        let agent = host(root: root, script: script, tools: [definition]) { req in
            #expect(req.intent == .explicitRequest)
            #expect(req.arguments["userRequested"] == nil)
            return ExecutionResult(requestID: req.requestID, status: .rejected)
        }
        let events = await collect(agent, AgentRequest(sessionID: "s", taskID: "t", text: "写入"))
        #expect(events.contains { if case .toolResult(_, let result) = $0 { return result.status == .rejected }; return false })
        await agent.shutdown()
    }

    @Test func oversizedToolResultCompletesTheRoundAndEscapedReplyFailsExplicitly() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = ModelScript([NativeCompletion(calls: [call("lookup")]), NativeCompletion(text: "done"),
                                  NativeCompletion(text: String(repeating: "\\", count: 550_000))])
        let definition = ToolDefinition(name: "lookup", summary: "read", source: .web, effect: .read, confirmation: .never, externallyExposable: false)
        let agent = host(root: root, script: script, tools: [definition]) { request in
            ExecutionResult(requestID: request.requestID, status: .completed, output: .string(String(repeating: "x", count: 1 << 20)))
        }
        let first = await collect(agent, AgentRequest(sessionID: "s", text: "lookup"))
        #expect(first.contains { if case .message(_, "done") = $0 { true } else { false } })
        let tool = try #require(await script.requests.last?["messages"]?.arrayValue?.last { $0["role"] == "tool" })
        #expect(tool["content"]?.stringValue?.contains("protocolError") == true)
        let second = await collect(agent, AgentRequest(sessionID: "s", text: "again"))
        #expect(second.contains { if case .taskState(_, .failed) = $0 { true } else { false } })
        await agent.shutdown()
    }

    @Test func fragmentedToolArgumentsAndInterruptedStreams() throws {
        var decoder = NativeCompletionDecoder()
        _ = try decoder.consume(["choices": [["delta": ["tool_calls": [["index": 0, "id": "c", "function": ["name": "lookup", "arguments": "{\"text\":"]]]]]]])
        _ = try decoder.consume(["choices": [["delta": ["tool_calls": [["function": ["arguments": "\"中文\"}"]]]], "finish_reason": "tool_calls"]]])
        #expect(try decoder.result().calls.first?["function"]?["arguments"] == "{\"text\":\"中文\"}")
        var truncated = NativeCompletionDecoder()
        _ = try truncated.consume(["choices": [["delta": ["content": "partial"]]]])
        #expect(throws: Error.self) { try truncated.result() }
        var empty = NativeCompletionDecoder()
        _ = try empty.consume(["choices": [["message": ["tool_calls": [["id": "a", "function": ["name": "lookup", "arguments": " "]]]], "finish_reason": "tool_calls"]]])
        #expect(try empty.result().calls.first?["function"]?["arguments"] == "{}")

        var invalid = NativeCompletionDecoder()
        _ = try invalid.consume(["choices": [["delta": ["tool_calls": [["index": 0, "id": "c", "function": ["name": "write", "arguments": "{"]]]], "finish_reason": "tool_calls"]]])
        #expect(throws: Error.self) { try invalid.result() }
    }

    @Test func compactionPreservesCurrentRequestAndSavesSummary() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = AgentSessionStorage(root: root)
        try await storage.save(sessionID: "s", messages: [["role": "user", "content": .string(String(repeating: "旧", count: 65_000))], ["role": "assistant", "content": "历史结果"]])
        let script = ModelScript([NativeCompletion(text: "已完成查询，写操作待核实"), NativeCompletion(text: "继续当前任务")])
        let agent = host(root: root, script: script)
        let events = await collect(agent, AgentRequest(sessionID: "s", taskID: "t", text: "当前请求"))
        #expect(events.contains(.taskState(taskID: "t", .compacting)))
        let requests = await script.requests
        #expect(requests.count == 2)
        #expect(requests[0]["tools"] == nil)
        #expect(requests[1]["messages"]?.arrayValue?.last?["content"]?.stringValue?.contains("当前请求") == true)
        #expect(requests[1].canonicalData().count < 30_000)
        let saved = try await storage.load(sessionID: "s", legacyPath: nil)
        #expect(saved.first?["content"]?.stringValue?.contains("待核实") == true)
        await agent.shutdown()
    }

    @Test func cancellingInFlightToolLeavesUnknownOutcomeAndNoReplay() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (started, signal) = AsyncStream<Void>.makeStream()
        let script = ModelScript([NativeCompletion(calls: [call("write", ["userRequested": true])])])
        let definition = ToolDefinition(name: "write", summary: "write", source: .calendar, effect: .write, confirmation: .always, externallyExposable: false)
        let agent = host(root: root, script: script, tools: [definition]) { req in
            signal.yield(())
            do { try await Task.sleep(for: .seconds(30)) } catch { }
            return .failure(req.requestID, .cancelled, "interrupted", status: .cancelled)
        }
        let result = Task { await collect(agent, AgentRequest(sessionID: "s", taskID: "t", text: "写入")) }
        for await _ in started { break }
        await agent.cancel(taskID: "t")
        #expect(await result.value.contains(.taskState(taskID: "t", .pendingVerification)))
        await agent.shutdown()
        let saved = try await AgentSessionStorage(root: root).load(sessionID: "s", legacyPath: nil)
        #expect(saved.last?["role"] == "tool")
        #expect(await script.requests.count == 1)
    }

    @Test func realNetworkFailureIsTerminalAndDoesNotLaunchProcess() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let agent = AgentHost(launcher: { NativeRuntime(storage: AgentSessionStorage(root: root)) },
            configProvider: { RuntimeLaunchConfig(baseURL: "http://127.0.0.1:1/v1", model: "m", apiKey: "key") }, toolsProvider: { [] }, toolHandler: { .failure($0.requestID, .unavailable, "no tools") })
        let events = await collect(agent, AgentRequest(sessionID: "s", taskID: "t", text: "hi"))
        #expect(events.contains(.taskState(taskID: "t", .failed)))
        #expect(await agent.runningPID == nil)
        await agent.shutdown()
        #expect(await agent.state == .notRunning)
    }

    @Test func realHTTPStreamingAndToolLoop() async throws {
        let root = URL(fileURLWithPath: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = Process(), ready = Pipe()
        server.executableURL = URL(filePath: "/usr/bin/python3")
        server.standardOutput = ready; server.standardError = FileHandle.nullDevice
        server.arguments = ["-u", "-c", #"""
import json, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert self.path == '/chat/completions'
        assert self.headers['Authorization'] == 'Bearer fake-key'
        assert body['model'] == 'mock'
        self.send_response(200); self.send_header('Content-Type','text/event-stream'); self.end_headers()
        if body['messages'][-1]['role'] == 'tool':
            assert '42' in body['messages'][-1]['content']
            chunks=[{'delta':{'content':'原生流式完成'}},{'delta':{},'finish_reason':'stop'}]
        else:
            chunks=[{'delta':{'tool_calls':[{'index':0,'id':'call','function':{'name':'lookup','arguments':'{'}}]}},
                    {'delta':{'tool_calls':[{'index':0,'function':{'arguments':'}'}}]},'finish_reason':'tool_calls'}]
        for chunk in chunks:
            encoded=('data: '+json.dumps({'choices':[chunk]},ensure_ascii=False)+'\r\n\r\n').encode()
            for b in encoded:
                self.wfile.write(bytes([b])); self.wfile.flush()
        self.wfile.write(b'data: [DONE]\r\n\r\n')
        self.wfile.flush()
        time.sleep(5)  # Completion must not wait for a compatible server to close its response.
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
print(server.server_port,flush=True)
server.serve_forever()
"""#]
        try server.run()
        defer { server.terminate(); server.waitUntilExit() }
        var port = Data()
        while let byte = try ready.fileHandleForReading.read(upToCount: 1), !byte.isEmpty, byte != Data([10]) { port.append(byte) }
        let number = try #require(Int(String(decoding: port, as: UTF8.self)))
        let definition = ToolDefinition(name: "lookup", summary: "lookup", source: .calendar, effect: .read, confirmation: .never, externallyExposable: false)
        let agent = AgentHost(launcher: { NativeRuntime(storage: AgentSessionStorage(root: root)) },
            configProvider: { RuntimeLaunchConfig(baseURL: "http://127.0.0.1:\(number)", model: "mock", apiKey: "fake-key") }, toolsProvider: { [definition] }, toolHandler: { req in ExecutionResult(requestID: req.requestID, status: .completed, output: ["value": 42]) })
        let clock = ContinuousClock(), start = ContinuousClock.now
        let events = await collect(agent, AgentRequest(sessionID: "s", taskID: "t", text: "查一下"))
        #expect(clock.now - start < .seconds(4), "[DONE] must finish the response before the server closes the socket")
        #expect(events.contains(.message(taskID: "t", "原生流式完成")))
        #expect(events.contains { if case .textDelta = $0 { return true }; return false })
        #expect(events.contains(.taskState(taskID: "t", .completed)))
        await agent.shutdown()
    }

    @Test func customSystemPromptUpdatesLiveAndRevertsToDefault() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = ModelScript([NativeCompletion(text: "一"), NativeCompletion(text: "二"), NativeCompletion(text: "三"), NativeCompletion(text: "四")])
        let promptBox = PromptBox()
        let storage = AgentSessionStorage(root: root)
        let agent = AgentHost(
            launcher: { NativeRuntime(storage: storage, client: NativeModelClient(transport: { request, delta in try await script.respond(request, delta: delta) })) },
            configProvider: { RuntimeLaunchConfig(baseURL: "https://example.test/v1", model: "mock", apiKey: "secret") },
            toolsProvider: { [] },
            guidanceProvider: { ["插件附加说明"] },
            systemPromptProvider: { await promptBox.value },
            toolHandler: { .failure($0.requestID, .adapterFailure, "unexpected tool") }
        )

        _ = await collect(agent, AgentRequest(sessionID: "s1", text: "第一轮"))
        await promptBox.set("你是精简版个人助理。")
        _ = await collect(agent, AgentRequest(sessionID: "s2", text: "第二轮"))
        await promptBox.set("   \n  ")
        _ = await collect(agent, AgentRequest(sessionID: "s3", text: "第三轮"))
        await promptBox.set(nil)
        _ = await collect(agent, AgentRequest(sessionID: "s4", text: "第四轮"))
        await agent.shutdown()

        let requests = await script.requests
        try #require(requests.count == 4)
        let systems = requests.compactMap { $0["messages"]?.arrayValue?.first?["content"]?.stringValue }
        try #require(systems.count == 4)
        let expectedDefault = NativeAgentPrompt.system(guidance: ["插件附加说明"])
        let expectedCustom = NativeAgentPrompt.runtimeProtocolPrompt + "\n插件附加说明\n你是精简版个人助理。"
        #expect(!NativeAgentPrompt.defaultSystemPrompt.contains("asky-form"))
        #expect(!NativeAgentPrompt.defaultSystemPrompt.contains("<asky-reaction>"))
        #expect(!NativeAgentPrompt.defaultSystemPrompt.contains("web_read_page"))
        #expect(!NativeAgentPrompt.defaultSystemPrompt.contains("calendar_list_calendars"))
        #expect(!NativeAgentPrompt.defaultSystemPrompt.contains("memory_save"))
        #expect(systems[0] == expectedDefault)
        #expect(systems[0].hasSuffix(NativeAgentPrompt.defaultSystemPrompt))
        #expect(systems[1] == expectedCustom)
        #expect(systems[1].contains("asky-form"))
        #expect(systems[1].contains("<asky-reaction>"))
        #expect(systems[1].hasSuffix("你是精简版个人助理。"))
        #expect(systems[2] == expectedDefault)
        #expect(systems[3] == expectedDefault)

        let legacyCustom = "自定义人设\n```asky-form\n<asky-reaction>"
        let legacyAssembled = NativeAgentPrompt.system(basePrompt: legacyCustom, guidance: ["插件附加说明"])
        #expect(legacyAssembled == "插件附加说明\n" + legacyCustom)
    }

    @Test func webCitationGuidancePreservedAcrossFormattingAndTerminalImages() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let assembled = NativeAgentPrompt.system(basePrompt: "你是精简版个人助理。", guidance: [])
        #expect(NativeAgentPrompt.runtimeProtocolPrompt.contains("渲染为来源标签"))
        #expect(NativeAgentPrompt.runtimeProtocolPrompt.contains("不能只给配图附来源"))
        #expect(assembled.contains("渲染为来源标签"))
        #expect(assembled.contains("不能只给配图附来源"))
        let capabilities = try #require(NativeAgentPrompt.imageCapabilities(hasPageReader: true))
        #expect(capabilities.contains("渲染为来源标签"))
        #expect(capabilities.contains("不能只给配图附来源"))

        let script = ModelScript([
            NativeCompletion(calls: [call("web_read_page", ["imagesOnly": true])]),
            NativeCompletion(text: "结论。[来源](https://example.com/article)")
        ])
        let definition = ToolDefinition(name: "web_read_page", summary: "read", source: .web, effect: .read, confirmation: .never, externallyExposable: false)
        let agent = host(root: root, script: script, tools: [definition]) { request in
            ExecutionResult(requestID: request.requestID, status: .completed, output: ["images": []])
        }
        _ = await collect(agent, AgentRequest(sessionID: "s", text: "比较几个模型"))
        await agent.shutdown()

        let finalMessages = try #require(await script.requests.last?["messages"]?.arrayValue)
        let tailSystems = finalMessages.compactMap { $0["role"] == "system" ? $0["content"]?.stringValue : nil }.dropFirst()
        #expect(tailSystems.contains { $0.contains("imagesOnly") && $0.contains("不能只给配图附来源") && $0.contains("[来源](url)") })
    }

    @Test func webSearchCapabilityInjectedOutsidePersona() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!NativeAgentPrompt.defaultSystemPrompt.contains("web_search"))
        #expect(NativeAgentPrompt.webSearchCapabilities(hasWebSearch: false) == nil)
        let reminder = try #require(NativeAgentPrompt.webSearchCapabilities(hasWebSearch: true))
        let assembled = NativeAgentPrompt.system(basePrompt: "自定义人设。", guidance: [], hasWebSearch: true)
        #expect(assembled.contains(reminder))
        #expect(assembled.hasSuffix(reminder + "\n自定义人设。"))

        let script = ModelScript([NativeCompletion(text: "ok")])
        let definition = ToolDefinition(name: "web_search", summary: "search", source: .web, effect: .read, confirmation: .never, externallyExposable: false)
        let storage = AgentSessionStorage(root: root)
        let agent = AgentHost(
            launcher: { NativeRuntime(storage: storage, client: NativeModelClient(transport: { request, delta in try await script.respond(request, delta: delta) })) },
            configProvider: { RuntimeLaunchConfig(baseURL: "https://example.test/v1", model: "mock", apiKey: "secret") },
            toolsProvider: { [definition] },
            guidanceProvider: { [] },
            systemPromptProvider: { "自定义人设。" },
            toolHandler: { ExecutionResult(requestID: $0.requestID, status: .completed) }
        )
        _ = await collect(agent, AgentRequest(sessionID: "s", text: "我觉得 6.2 反馈很差"))
        await agent.shutdown()

        let system = try #require(await script.requests.first?["messages"]?.arrayValue?.first?["content"]?.stringValue)
        #expect(system.contains(reminder))
        #expect(system.hasSuffix(reminder + "\n自定义人设。"))
    }

    @Test func antiDefensiveDisclaimerGuidancePresentAcrossLayers() throws {
        #expect(NativeAgentPrompt.defaultSystemPrompt.contains("直接为自己的判断负责"))
        #expect(NativeAgentPrompt.defaultSystemPrompt.contains("我得先承认"))
        #expect(NativeAgentPrompt.defaultSystemPrompt.contains("私密群聊"))
        #expect(NativeAgentPrompt.defaultSystemPrompt.contains("不是查证结论"))
        #expect(!NativeAgentPrompt.defaultSystemPrompt.contains("信息不全或不确定时坦白说不清楚"))
        #expect(!NativeAgentPrompt.runtimeProtocolPrompt.contains("区分来源事实、推断和未核实内容"))
        #expect(NativeAgentPrompt.runtimeProtocolPrompt.contains("这是判断不是结论"))
        let reminder = try #require(NativeAgentPrompt.webSearchCapabilities(hasWebSearch: true))
        #expect(reminder.contains("私密群聊"))
        #expect(!reminder.contains("确实查不到时再坦白说明"))
    }
}

private actor PromptBox {
    var value: String?
    func set(_ next: String?) { value = next }
}

private actor WebOverlapProbe {
    var running = 0
    var peak = 0
    var writes = 0
    func run(_ request: ActionRequest) async -> ExecutionResult {
        if request.tool == "write" {
            #expect(running == 0, "Writes must wait for the preceding web batch")
            writes += 1
        } else {
            if request.tool == "web_read_page" { #expect(writes == 1) }
            running += 1
            peak = max(peak, running)
            try? await Task.sleep(for: .milliseconds(30))
            running -= 1
        }
        return ExecutionResult(requestID: request.requestID, status: .completed)
    }
}

private actor RollingWebProbe {
    var slowReadFinished = false
    var fourthStartedBeforeSlowReadFinished = false
    func run(_ request: ActionRequest) async -> ExecutionResult {
        let n = request.arguments["n"]?.numberValue ?? -1
        if n == 0 {
            try? await Task.sleep(for: .milliseconds(150))
            slowReadFinished = true
        } else if n == 3 {
            fourthStartedBeforeSlowReadFinished = !slowReadFinished
        }
        return ExecutionResult(requestID: request.requestID, status: .completed)
    }
}
