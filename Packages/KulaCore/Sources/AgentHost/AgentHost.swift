import Foundation
import Contracts

/// Observable helper-process lifecycle.
public enum RuntimeState: Sendable, Equatable {
    case notRunning
    case starting
    case ready
    case busy
    case stopping
}

/// Credentials and model selection, resolved by the app right before launch (from Keychain).
public struct RuntimeLaunchConfig: Sendable {
    public var baseURL: String
    public var model: String
    public var apiKey: String
    public init(baseURL: String, model: String, apiKey: String) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
    }
}

public struct AgentHostConfig: Sendable {
    public var idleTimeout: Duration = .seconds(60)
    public var handshakeTimeout: Duration = .seconds(15)
    public var shutdownGrace: Duration = .seconds(2)
    public var maxToolRounds = 50
    public init() {}
}

public enum AgentHostError: LocalizedError, Equatable {
    case notConfigured
    case credentialMissing
    case sessionBusy
    case handshakeFailed(String)
    case protocolMismatch(Int)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: CoreLocalization.text("尚未配置模型，请在设置 › 模型中填写 API 地址、模型名与 Key。")
        case .credentialMissing: CoreLocalization.text("模型 API Key 不存在或为空，请在设置 › 模型中重新保存 Key。")
        case .sessionBusy: CoreLocalization.text("该会话已有任务在运行。")
        case .handshakeFailed(let reason): String(format: CoreLocalization.text("AI 运行时连接失败：%@"), reason)
        case .protocolMismatch(let version): String(format: CoreLocalization.text("AI 运行时协议版本不匹配：%d"), version)
        case .launchFailed(let reason): String(format: CoreLocalization.text("AI 运行时启动失败：%@"), reason)
        }
    }
}

/// Manages an on-demand runtime: start only on explicit AI submission, coalesced starts,
/// keep-alive while work or confirmations are pending, 60 s idle exit, and process-group teardown.
public actor AgentHost {
    public typealias Launcher = @Sendable () throws -> any RuntimeProcess
    public typealias ToolHandler = @Sendable (ActionRequest) async -> ExecutionResult

    private let launcher: Launcher
    private let toolHandler: ToolHandler
    private let configProvider: @Sendable () async throws -> RuntimeLaunchConfig?
    private let toolsProvider: @Sendable () async -> [ToolDefinition]
    private let guidanceProvider: @Sendable () async -> [String]
    private let promptConfigProvider: @Sendable () async -> AgentPromptConfiguration
    private var toolTasks: [String: Task<Void, Never>] = [:]
    private let config: AgentHostConfig

    private var process: (any RuntimeProcess)?
    private var startTask: Task<any RuntimeProcess, Error>?
    private var readTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var readyWaiter: CheckedContinuation<Void, Error>?

    private struct TaskContext {
        var sessionID: String
        var continuation: AsyncStream<AgentEvent>.Continuation
        var toolRounds = 0
        var pendingTools = 0
        var state: AgentTaskState = .starting
        var hadWrite = false
    }
    private var tasks: [String: TaskContext] = [:]
    private var sessionFiles: [String: String] = [:]

    public private(set) var state: RuntimeState = .notRunning
    public private(set) var launchCount = 0

    public init(config: AgentHostConfig = .init(), launcher: @escaping Launcher,
                configProvider: @escaping @Sendable () async throws -> RuntimeLaunchConfig?,
                toolsProvider: @escaping @Sendable () async -> [ToolDefinition],
                guidanceProvider: @escaping @Sendable () async -> [String] = { [] },
                promptConfigProvider: @escaping @Sendable () async -> AgentPromptConfiguration = { .default },
                toolHandler: @escaping ToolHandler) {
        self.config = config
        self.launcher = launcher
        self.configProvider = configProvider
        self.toolsProvider = toolsProvider
        self.toolHandler = toolHandler
        self.guidanceProvider = guidanceProvider
        self.promptConfigProvider = promptConfigProvider
    }

    public var runningPID: Int32? { process.flatMap { $0.pid > 0 ? $0.pid : nil } }

    /// Restores the runtime session file reference persisted in the conversation projection.
    public func setSessionFile(_ path: String?, for sessionID: String) {
        sessionFiles[sessionID] = path
    }

    public func sessionFile(for sessionID: String) -> String? { sessionFiles[sessionID] }

    public func forgetSessions(_ ids: Set<String>) {
        for id in ids where !tasks.values.contains(where: { $0.sessionID == id }) {
            sessionFiles.removeValue(forKey: id)
        }
    }

    // MARK: submit / cancel

    public func submit(_ request: AgentRequest) -> AsyncStream<AgentEvent> {
        let (stream, cont) = AsyncStream<AgentEvent>.makeStream(bufferingPolicy: .bufferingNewest(512))
        if tasks.values.contains(where: { $0.sessionID == request.sessionID }) {
            cont.yield(.error(taskID: request.taskID, CoreLocalization.text("该会话已有任务在运行")))
            cont.finish()
            return stream
        }
        idleTask?.cancel()
        idleTask = nil
        tasks[request.taskID] = TaskContext(sessionID: request.sessionID, continuation: cont)
        cont.yield(.taskState(taskID: request.taskID, .starting))
        Task { await self.dispatch(request) }
        return stream
    }

    public func cancel(taskID: String) async {
        guard tasks[taskID] != nil else { return }
        try? process?.write(HostMessage.cancel(taskID: taskID).encoded())
        for (key, value) in toolTasks where key.hasPrefix(taskID + ":") { value.cancel() }
        let uncertain = tasks[taskID]?.hadWrite == true || (tasks[taskID]?.pendingTools ?? 0) > 0
        finish(taskID, uncertain ? .pendingVerification : .cancelled)
    }

    /// App quit: cancel everything and make sure no helper process survives.
    public func shutdown() async {
        for id in Array(tasks.keys) { await cancel(taskID: id) }
        await stopProcess()
    }

    // MARK: internals

    private func dispatch(_ request: AgentRequest) async {
        do {
            let p = try await ensureRunning()
            guard tasks[request.taskID] != nil else { return }
            let resources = HostMessage.resources(tools: await toolsProvider(),
                                                  pluginGuidance: await guidanceProvider(),
                                                  promptConfig: await promptConfigProvider())
            guard tasks[request.taskID] != nil else { return }
            state = .busy
            try p.write(resources.encoded())
            try p.write(HostMessage.prompt(request, sessionFile: sessionFiles[request.sessionID]).encoded())
        } catch {
            emit(request.taskID, .error(taskID: request.taskID, String(format: CoreLocalization.text("无法启动 AI 运行时：%@"), error.localizedDescription)))
            finish(request.taskID, .failed)
        }
    }

    private func ensureRunning() async throws -> any RuntimeProcess {
        // Join an in-flight launch first: `process` is set before the handshake/configure completes.
        if let t = startTask { return try await t.value }
        if let p = process, state != .stopping, state != .starting { return p }
        let t = Task { try await self.launch() }
        startTask = t
        defer { startTask = nil }
        return try await t.value
    }

    private func launch() async throws -> any RuntimeProcess {
        guard let cfg = try await configProvider() else { throw AgentHostError.notConfigured }
        state = .starting
        let p: any RuntimeProcess
        do { p = try launcher() } catch {
            state = .notRunning
            throw AgentHostError.launchFailed(String(describing: error))
        }
        launchCount += 1
        process = p
        readTask = Task { await self.readLoop(p) }
        do {
            try p.write(HostMessage.hello(protocolVersion: WireProtocol.version).encoded())
            try await waitForReady()
            let tools = await toolsProvider()
            try p.write(HostMessage.configure(baseURL: cfg.baseURL, model: cfg.model, apiKey: cfg.apiKey,
                                              tools: tools, maxToolRounds: config.maxToolRounds,
                                              pluginGuidance: await guidanceProvider(),
                                              promptConfig: await promptConfigProvider()).encoded())
        } catch {
            await stopProcess()
            throw error
        }
        state = .ready
        return p
    }

    private func waitForReady() async throws {
        let timeout = config.handshakeTimeout
        let timer = Task {
            try? await Task.sleep(for: timeout)
            self.failReady(AgentHostError.handshakeFailed("timeout"))
        }
        defer { timer.cancel() }
        try await withCheckedThrowingContinuation { readyWaiter = $0 }
    }

    private func failReady(_ e: Error) {
        readyWaiter?.resume(throwing: e)
        readyWaiter = nil
    }

    private func readLoop(_ p: any RuntimeProcess) async {
        var framer = LineFramer()
        for await chunk in p.output {
            for frame in framer.push(chunk) {
                switch frame {
                case .success(let line):
                    if let msg = try? RuntimeMessage.decode(line) { await handle(msg, from: p) }
                case .failure(let e):
                    emitAll(.error(taskID: nil, String(format: CoreLocalization.text("运行时协议错误：%@"), String(describing: e))))
                }
            }
        }
        let code = await p.waitForExit()
        processExited(p, code: code)
    }

    private func handle(_ msg: RuntimeMessage, from p: any RuntimeProcess) async {
        switch msg {
        case .ready(let v, _):
            if v == WireProtocol.version {
                readyWaiter?.resume()
            } else {
                readyWaiter?.resume(throwing: AgentHostError.protocolMismatch(v))
            }
            readyWaiter = nil
        case .taskState(let id, let st, let sessionFile):
            if let sessionFile, let sid = tasks[id]?.sessionID { sessionFiles[sid] = sessionFile }
            if st.isTerminal {
                // A tool still in flight means the real outcome is unknown.
                let unknown = (tasks[id]?.pendingTools ?? 0) > 0
                finish(id, unknown ? .pendingVerification : st)
            } else {
                tasks[id]?.state = st
                emit(id, .taskState(taskID: id, st))
            }
        case .textDelta(let id, let t): emit(id, .textDelta(taskID: id, t))
        case .message(let id, let t): emit(id, .message(taskID: id, t))
        case .clarification(let id, let q):
            // The question ends this turn; the answer is submitted as a new task in the same session,
            // so a pending clarification never keeps the helper process alive.
            emit(id, .clarification(taskID: id, question: q))
            finish(id, .awaitingInput)
        case .error(let id, let m):
            if let id { emit(id, .error(taskID: id, m)) } else { emitAll(.error(taskID: nil, m)) }
        case .toolCall(let id, let callID, let tool, let args, let intent):
            await runTool(taskID: id, callID: callID, tool: tool, arguments: args, intent: intent, process: p)
        }
    }

    private func runTool(taskID: String, callID: String, tool: String, arguments: JSONValue,
                         intent: UserIntent, process p: any RuntimeProcess) async {
        guard var ctx = tasks[taskID] else {
            try? p.write(HostMessage.toolResult(callID: callID, .failure(callID, .cancelled, CoreLocalization.text("任务已结束"))).encoded())
            return
        }
        ctx.toolRounds += 1
        if ctx.toolRounds > config.maxToolRounds {
            tasks[taskID] = ctx
            try? p.write(HostMessage.toolResult(callID: callID, .failure(callID, .cancelled,
                CoreLocalization.text("已达到自动工具轮数上限，请用户确认后继续"), status: .cancelled)).encoded())
            emit(taskID, .error(taskID: taskID, String(format: CoreLocalization.text("已达到 %d 轮自动工具上限"), config.maxToolRounds)))
            return
        }
        ctx.pendingTools += 1
        tasks[taskID] = ctx
        let request = ActionRequest(requestID: callID, tool: tool, arguments: arguments, taskID: taskID,
                                    origin: .agent(sessionID: ctx.sessionID), intent: intent)
        emit(taskID, .toolCall(taskID: taskID, request))
        // Run off the actor so text deltas and other tasks keep flowing while confirmation is pending.
        let handler = toolHandler
        toolTasks[callID] = Task {
            let result = await handler(request)
            self.toolFinished(taskID: taskID, callID: callID, result: result, process: p)
        }
    }

    private func toolFinished(taskID: String, callID: String, result: ExecutionResult, process p: any RuntimeProcess) {
        toolTasks[callID] = nil
        tasks[taskID]?.pendingTools -= 1
        // Writes are the only results that carry a readback or an unverified outcome.
        if result.readback != nil || result.status == .pendingVerification {
            tasks[taskID]?.hadWrite = true
        }
        if let c = result.confirmation, result.status == .awaitingConfirmation {
            emit(taskID, .confirmationRequired(taskID: taskID, c))
        }
        emit(taskID, .toolResult(taskID: taskID, result))
        do {
            let frame: Data
            do {
                frame = try HostMessage.toolResult(callID: callID, result).encoded()
            } catch {
                let failure = ExecutionResult.failure(callID, .protocolError, error.localizedDescription,
                    status: result.readback == nil && !((tasks[taskID]?.hadWrite) ?? false) ? .failed : .pendingVerification)
                frame = try HostMessage.toolResult(callID: callID, failure).encoded()
            }
            try p.write(frame)
        } catch {
            p.terminate(force: true)
        }
    }

    private func emit(_ taskID: String, _ e: AgentEvent) {
        tasks[taskID]?.continuation.yield(e)
    }

    private func emitAll(_ e: AgentEvent) {
        tasks.values.forEach { $0.continuation.yield(e) }
    }

    private func finish(_ taskID: String, _ final: AgentTaskState) {
        guard let ctx = tasks.removeValue(forKey: taskID) else { return }
        ctx.continuation.yield(.taskState(taskID: taskID, final))
        ctx.continuation.finish()
        if tasks.isEmpty, process != nil, state != .stopping {
            state = .ready
            scheduleIdleExit()
        }
    }

    private func scheduleIdleExit() {
        idleTask?.cancel()
        let delay = config.idleTimeout
        idleTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self.idleExpired()
        }
    }

    private func idleExpired() async {
        guard tasks.isEmpty else { return }
        await stopProcess()
    }

    private func stopProcess() async {
        idleTask?.cancel()
        idleTask = nil
        guard let p = process else {
            state = .notRunning
            return
        }
        state = .stopping
        try? p.write(HostMessage.shutdown.encoded())
        p.closeInput()
        let grace = config.shutdownGrace
        // waitForExit uses a continuation and cannot be cancelled. Racing it in a
        // task group would wait forever for the losing child before reaching kill.
        let escalation = Task {
            do { try await Task.sleep(for: grace) } catch { return }
            p.terminate(force: false)
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            p.terminate(force: true)
        }
        _ = await p.waitForExit()
        escalation.cancel()
        // Leader exited; still sweep any descendants left in the group.
        p.terminate(force: true)
        readTask?.cancel()
        readTask = nil
        if process?.pid == p.pid { process = nil }
        state = .notRunning
    }

    private func processExited(_ p: any RuntimeProcess, code: Int32) {
        guard process?.pid == p.pid else { return }
        process = nil
        failReady(AgentHostError.handshakeFailed("exited \(code)"))
        p.terminate(force: true)
        let wasStopping = state == .stopping
        state = .notRunning
        idleTask?.cancel()
        idleTask = nil
        guard !wasStopping else { return }
        for (id, ctx) in tasks {
            ctx.continuation.yield(.runtimeExited(code: code))
            // Never replay writes: anything with a tool in flight must be verified by the user.
            ctx.continuation.yield(.taskState(taskID: id, ctx.pendingTools > 0 || ctx.hadWrite ? .pendingVerification : .failed))
            ctx.continuation.finish()
        }
        tasks.removeAll()
    }
}
