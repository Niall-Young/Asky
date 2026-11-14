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
private func host(root: URL, script: ModelScript, tools: [ToolDefinition] = [], handler: @escaping AgentHost.ToolHandler = { .failure($0.requestID, .adapterFailure, "unexpected tool") }) -> AgentHost {
    let storage = AgentSessionStorage(root: root)
    return AgentHost(launcher: { NativeRuntime(storage: storage, client: NativeModelClient(transport: { request, delta in try await script.respond(request, delta: delta) })) },
        configProvider: { RuntimeLaunchConfig(baseURL: "https://example.test/v1", model: "mock", apiKey: "secret-not-persisted") },
        toolsProvider: { tools }, toolHandler: handler)
}

@Suite(.timeLimit(.minutes(1))) struct NativeRuntimeTests {
    @Test func onlyFinalAssistantReplyIsPublishedAfterToolRounds() async throws {
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
        #expect(!events.contains { if case .textDelta = $0 { return true }; return false })
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

    @Test func fragmentedToolArgumentsAndInterruptedStreams() throws {
        var decoder = NativeCompletionDecoder()
        _ = try decoder.consume(["choices": [["delta": ["tool_calls": [["index": 0, "id": "c", "function": ["name": "lookup", "arguments": "{\"text\":"]]]]]]])
        _ = try decoder.consume(["choices": [["delta": ["tool_calls": [["index": 0, "function": ["arguments": "\"中文\"}"]]]], "finish_reason": "tool_calls"]]])
        #expect(try decoder.result().calls.first?["function"]?["arguments"] == "{\"text\":\"中文\"}")
        var truncated = NativeCompletionDecoder()
        _ = try truncated.consume(["choices": [["delta": ["content": "partial"]]]])
        #expect(throws: Error.self) { try truncated.result() }
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
        #expect(!events.contains { if case .textDelta = $0 { return true }; return false })
        #expect(events.contains(.taskState(taskID: "t", .completed)))
        await agent.shutdown()
    }
}
