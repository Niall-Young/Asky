import Testing
import Foundation
import os
import Contracts
@testable import AgentHost

/// Scripted stand-in for the Pi host process.
final class FakeRuntime: RuntimeProcess, @unchecked Sendable {
    typealias Script = @Sendable (_ msg: JSONValue, _ reply: @Sendable (JSONValue) -> Void, _ crash: @Sendable () -> Void) -> Void

    let pid: Int32
    let output: AsyncStream<Data>
    private let cont: AsyncStream<Data>.Continuation
    private let script: Script
    private let st = OSAllocatedUnfairLock<(exit: Int32?, waiters: [CheckedContinuation<Int32, Never>], seen: [String])>(initialState: (nil, [], []))
    let protocolVersion: Int
    let exitOnShutdown: Bool

    init(pid: Int32, protocolVersion: Int = WireProtocol.version, exitOnShutdown: Bool = true, script: @escaping Script) {
        self.pid = pid
        self.protocolVersion = protocolVersion
        self.exitOnShutdown = exitOnShutdown
        self.script = script
        (output, cont) = AsyncStream<Data>.makeStream()
    }

    var seenTypes: [String] { st.withLock { $0.seen } }
    var exited: Bool { st.withLock { $0.exit != nil } }

    func send(_ v: JSONValue) {
        var d = try! JSONEncoder().encode(v)
        d.append(0x0A)
        cont.yield(d)
    }

    func write(_ data: Data) throws {
        if exited { throw POSIXError(.EPIPE) }
        for line in data.split(separator: 0x0A) {
            let v = try JSONDecoder().decode(JSONValue.self, from: Data(line))
            let type = v["type"]?.stringValue ?? ""
            st.withLock { $0.seen.append(type) }
            switch type {
            case "hello": send(["type": "ready", "protocol": .number(Double(protocolVersion)), "runtime": "fake"])
            case "shutdown": if exitOnShutdown { exit(0) }
            default: script(v, { [weak self] in self?.send($0) }, { [weak self] in self?.exit(137) })
            }
        }
    }

    func closeInput() {}
    func terminate(force: Bool) { if force { exit(9) } }

    func exit(_ code: Int32) {
        let waiters: [CheckedContinuation<Int32, Never>] = st.withLock { s in
            guard s.exit == nil else { return [] }
            s.exit = code
            let w = s.waiters
            s.waiters = []
            return w
        }
        cont.finish()
        waiters.forEach { $0.resume(returning: code) }
    }

    func waitForExit() async -> Int32 {
        await withCheckedContinuation { c in
            let code: Int32? = st.withLock {
                if let e = $0.exit { return e }
                $0.waiters.append(c)
                return nil
            }
            if let code { c.resume(returning: code) }
        }
    }
}

/// Answers each prompt with text and completion.
let echoScript: FakeRuntime.Script = { msg, reply, _ in
    guard msg["type"]?.stringValue == "prompt", let id = msg["request"]?["taskID"]?.stringValue else { return }
    reply(["type": "textDelta", "taskID": .string(id), "text": "hi"])
    reply(["type": "taskState", "taskID": .string(id), "state": "completed"])
}

final class Launches: @unchecked Sendable {
    let list = OSAllocatedUnfairLock<[FakeRuntime]>(initialState: [])
    var count: Int { list.withLock { $0.count } }
    var last: FakeRuntime? { list.withLock { $0.last } }
}

func makeHost(idle: Duration = .seconds(60), protocolVersion: Int = WireProtocol.version,
              configured: Bool = true, credentialError: AgentHostError? = nil, exitOnShutdown: Bool = true,
              script: @escaping FakeRuntime.Script = echoScript,
              tool: @escaping AgentHost.ToolHandler = { .init(requestID: $0.requestID, status: .completed) })
    -> (AgentHost, Launches) {
    var cfg = AgentHostConfig()
    cfg.idleTimeout = idle
    cfg.handshakeTimeout = .seconds(2)
    cfg.shutdownGrace = .milliseconds(200)
    cfg.maxToolRounds = 2
    let launches = Launches()
    let host = AgentHost(config: cfg, launcher: {
        let p = FakeRuntime(pid: Int32(1000 + launches.count), protocolVersion: protocolVersion,
                            exitOnShutdown: exitOnShutdown, script: script)
        launches.list.withLock { $0.append(p) }
        return p
    }, configProvider: {
        if let credentialError { throw credentialError }
        return configured ? RuntimeLaunchConfig(baseURL: "http://x", model: "m", apiKey: "k") : nil
    },
       toolsProvider: { [] }, toolHandler: tool)
    return (host, launches)
}

func collect(_ s: AsyncStream<AgentEvent>) async -> [AgentEvent] {
    var out: [AgentEvent] = []
    for await e in s { out.append(e) }
    return out
}

func finalState(_ events: [AgentEvent]) -> AgentTaskState? {
    for e in events.reversed() { if case .taskState(_, let s) = e { return s } }
    return nil
}

@Suite(.timeLimit(.minutes(1))) struct AgentHostTests {
    @Test func asynchronousCredentialFailureFinishesHandoffBeforeFailureEvent() async {
        let handoffFinished = OSAllocatedUnfairLock(initialState: false)
        let launches = Launches()
        let host = AgentHost(launcher: {
            let p = FakeRuntime(pid: 1234, script: echoScript)
            launches.list.withLock { $0.append(p) }
            return p
        }, configProvider: {
            // Model authorization hands focus back on the main actor before
            // the runtime reports a failed/cancelled credential request.
            await MainActor.run { handoffFinished.withLock { $0 = true } }
            throw AgentHostError.credentialMissing
        }, toolsProvider: { [] }, toolHandler: { .init(requestID: $0.requestID, status: .completed) })
        let stream = await host.submit(AgentRequest(sessionID: "s", text: "hello"))
        var events: [AgentEvent] = []
        for await event in stream {
            if case .error = event { #expect(handoffFinished.withLock { $0 }) }
            events.append(event)
        }
        #expect(finalState(events) == .failed)
        #expect(launches.count == 0)
    }

    @Test func credentialFailureIsPreservedAndDoesNotLaunchRuntime() async {
        let (host, launches) = makeHost(credentialError: .credentialMissing)
        let events = await collect(await host.submit(AgentRequest(sessionID: "s", text: "hello")))
        #expect(events.contains {
            if case .error(_, let text) = $0 {
                return text.contains(AgentHostError.credentialMissing.localizedDescription) && !text.contains("notConfigured")
            }
            return false
        })
        #expect(finalState(events) == .failed)
        #expect(launches.count == 0)
        #expect(await host.state == .notRunning)
    }

    @Test func failedAuthorizationCanBeRetriedAfterCredentialBecomesAvailable() async {
        struct AuthorizationError: LocalizedError {
            var errorDescription: String? { "钥匙串授权已取消" }
        }
        let authorized = OSAllocatedUnfairLock(initialState: false)
        let launches = Launches()
        let host = AgentHost(launcher: {
            let p = FakeRuntime(pid: 1234, script: echoScript)
            launches.list.withLock { $0.append(p) }
            return p
        }, configProvider: {
            guard authorized.withLock({ $0 }) else { throw AuthorizationError() }
            return RuntimeLaunchConfig(baseURL: "http://x", model: "m", apiKey: "synthetic")
        }, toolsProvider: { [] }, toolHandler: { .init(requestID: $0.requestID, status: .completed) })
        let failed = await collect(await host.submit(AgentRequest(sessionID: "s", text: "hello")))
        #expect(failed.contains {
            if case .error(_, let text) = $0 { return text.contains("钥匙串授权已取消") }
            return false
        })
        #expect(finalState(failed) == .failed)
        #expect(launches.count == 0)
        authorized.withLock { $0 = true }
        let retried = await collect(await host.submit(AgentRequest(sessionID: "s", text: "hello")))
        #expect(finalState(retried) == .completed)
        #expect(launches.count == 1)
        await host.shutdown()
    }

    @Test func coalescesConcurrentStartsIntoOneProcess() async {
        let (host, launches) = makeHost()
        async let a = collect(await host.submit(AgentRequest(sessionID: "s1", text: "a")))
        async let b = collect(await host.submit(AgentRequest(sessionID: "s2", text: "b")))
        let (ea, eb) = await (a, b)
        #expect(finalState(ea) == .completed && finalState(eb) == .completed)
        #expect(launches.count == 1)
        #expect(launches.last?.seenTypes.prefix(2) == ["hello", "configure"])
        await host.shutdown()
    }

    @Test func idleExitStopsProcessAndNextSubmitRelaunches() async throws {
        let (host, launches) = makeHost(idle: .milliseconds(100))
        _ = await collect(await host.submit(AgentRequest(sessionID: "s", text: "a")))
        try await Task.sleep(for: .milliseconds(600))
        #expect(await host.state == .notRunning)
        #expect(launches.last?.exited == true)
        _ = await collect(await host.submit(AgentRequest(sessionID: "s", text: "b")))
        #expect(launches.count == 2)
        await host.shutdown()
        #expect(await host.runningPID == nil)
    }

    @Test func oneTaskPerSession() async {
        let (host, _) = makeHost(script: { _, _, _ in })  // never completes
        let first = await host.submit(AgentRequest(sessionID: "s", text: "a"))
        let second = await collect(await host.submit(AgentRequest(sessionID: "s", text: "b")))
        #expect(second.contains { if case .error = $0 { true } else { false } })
        await host.shutdown()
        #expect(finalState(await collect(first)) == .cancelled)
    }

    @Test func shutdownKillsRuntimeThatIgnoresShutdownAndTerm() async {
        let (host, launches) = makeHost(exitOnShutdown: false)
        _ = await collect(await host.submit(AgentRequest(sessionID: "s", text: "a")))
        let clock = ContinuousClock()
        let start = clock.now
        await host.shutdown()
        #expect(clock.now - start < .seconds(3))
        #expect(launches.last?.exited == true)
        #expect(await host.runningPID == nil)
        #expect(await host.state == .notRunning)
    }

    @Test func crashDuringToolMarksPendingVerification() async {
        let (host, launches) = makeHost(script: { msg, reply, _ in
            if msg["type"]?.stringValue == "prompt", let id = msg["request"]?["taskID"]?.stringValue {
                reply(["type": "toolCall", "taskID": .string(id), "callID": "c1", "tool": "calendar_create_event",
                       "arguments": ["title": "x"], "intent": "explicitRequest"])
            }
        }, tool: { r in
            try? await Task.sleep(for: .seconds(5))
            return .init(requestID: r.requestID, status: .completed)
        })
        let stream = await host.submit(AgentRequest(sessionID: "s", text: "a"))
        let collector = Task { await collect(stream) }
        try? await Task.sleep(for: .milliseconds(200))
        launches.last?.exit(137)
        let events = await collector.value
        #expect(events.contains { if case .runtimeExited = $0 { true } else { false } })
        #expect(finalState(events) == .pendingVerification)
    }

    @Test func protocolMismatchFailsTask() async {
        let (host, launches) = makeHost(protocolVersion: 99)
        let events = await collect(await host.submit(AgentRequest(sessionID: "s", text: "a")))
        #expect(finalState(events) == .failed)
        #expect(launches.last?.exited == true)
        #expect(await host.state == .notRunning)
    }

    @Test func missingConfigurationNeverLaunches() async {
        let (host, launches) = makeHost(configured: false)
        let events = await collect(await host.submit(AgentRequest(sessionID: "s", text: "a")))
        #expect(finalState(events) == .failed && launches.count == 0)
    }

    @Test func toolRoundsAreCapped() async {
        let (host, launches) = makeHost(script: { msg, reply, _ in
            switch msg["type"]?.stringValue {
            case "prompt":
                let id = msg["request"]?["taskID"]?.stringValue ?? ""
                for i in 0..<3 {
                    reply(["type": "toolCall", "taskID": .string(id), "callID": .string("c\(i)"), "tool": "t", "arguments": [:]])
                }
            default: break
            }
        })
        let stream = await host.submit(AgentRequest(sessionID: "s", text: "a"))
        var calls = 0, capped = false
        for await e in stream {
            if case .toolCall = e { calls += 1 }
            if case .error(_, let m) = e, m == CoreLocalization.format("已达到 %d 轮自动工具上限", 2) { capped = true; break }
        }
        #expect(calls == 2 && capped)
        #expect(launches.last?.seenTypes.filter { $0 == "toolResult" }.count ?? 0 >= 1)
        await host.shutdown()
    }

    @Test func clarificationEndsTurnWithAwaitingInput() async {
        let (host, _) = makeHost(script: { msg, reply, _ in
            if let id = msg["request"]?["taskID"]?.stringValue {
                reply(["type": "clarification", "taskID": .string(id), "question": "哪个日历？"])
            }
        })
        let events = await collect(await host.submit(AgentRequest(sessionID: "s", text: "a")))
        #expect(finalState(events) == .awaitingInput)
        await host.shutdown()
    }
}

@Suite struct WireProtocolTests {
    @Test func framerSplitsAndBoundsFrames() {
        var f = LineFramer(maxFrame: 8)
        let r1 = f.push(Data("abc\nde".utf8))
        #expect(r1.count == 1 && (try? r1[0].get()) == Data("abc".utf8))
        let r2 = f.push(Data("f\n0123456789".utf8))
        #expect((try? r2[0].get()) == Data("def".utf8))
        #expect(r2.count == 2 && (try? r2[1].get()) == nil)
        let r3 = f.push(Data("rest-of-big\nok\n".utf8))
        #expect(r3.count == 1 && (try? r3[0].get()) == Data("ok".utf8))
    }

    @Test func decodesAndDefaultsIntentToSuggested() throws {
        let line = Data(#"{"type":"toolCall","taskID":"t","callID":"c","tool":"x","arguments":{"confirmed":true}}"#.utf8)
        guard case .toolCall(_, _, _, _, let intent) = try RuntimeMessage.decode(line) else { Issue.record(); return }
        #expect(intent == .aiSuggested)
        #expect(throws: FrameError.self) { try RuntimeMessage.decode(Data(#"{"type":"nope"}"#.utf8)) }
    }

    @Test func credentialOnlyInConfigureFrame() throws {
        let d = try HostMessage.configure(baseURL: "u", model: "m", apiKey: "SECRET", tools: [], maxToolRounds: 8).encoded()
        #expect(d.last == 0x0A)
        let p = try HostMessage.prompt(AgentRequest(sessionID: "s", text: "t"), sessionFile: nil).encoded()
        #expect(!String(decoding: p, as: UTF8.self).contains("SECRET"))
    }
}
