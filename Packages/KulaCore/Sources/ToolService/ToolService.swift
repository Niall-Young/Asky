import Foundation
import Contracts
import LocalStore

/// What an adapter returns after a successful write or read.
public struct AdapterOutput: Sendable, Hashable {
    public var output: JSONValue
    public var targets: [TargetRef]
    public init(output: JSONValue, targets: [TargetRef] = []) {
        self.output = output
        self.targets = targets
    }
}

/// Human-readable confirmation content, produced by the adapter after resolving the real target.
public struct ConfirmationPreview: Sendable, Hashable {
    public var target: String
    public var changes: [String]
    public var note: String?
    public var title: String?
    public var details: String?
    public init(target: String, changes: [String], note: String? = nil, title: String? = nil, details: String? = nil) {
        self.target = target
        self.changes = changes
        self.note = note
        self.title = title
        self.details = details
    }
}

/// One system capability. Adapters never decide policy; ToolService does.
public protocol ToolAdapter: Sendable {
    var definition: ToolDefinition { get }
    func prepare(requestID: String) async throws
    func finish(requestID: String) async
    var executionTimeout: Duration? { get }
    var deduplicatesArguments: Bool { get }
    func execute(_ arguments: JSONValue, requestID: String) async throws -> AdapterOutput
    func readback(_ arguments: JSONValue, output: AdapterOutput?, requestID: String) async -> JSONValue?
    /// Validates arguments and resolves the target. Throw `ToolError(.ambiguousTarget, …)` when the user must choose.
    func preview(_ arguments: JSONValue) async throws -> ConfirmationPreview
    func execute(_ arguments: JSONValue) async throws -> AdapterOutput
    /// Re-reads the target after a write (or after a timeout) to confirm the real state. nil = could not verify.
    func readback(_ arguments: JSONValue, output: AdapterOutput?) async -> JSONValue?
}

extension ToolAdapter {
    public func prepare(requestID: String) async throws {}
    public func finish(requestID: String) async {}
    public var executionTimeout: Duration? { nil }
    public var deduplicatesArguments: Bool { true }
    public func execute(_ arguments: JSONValue, requestID: String) async throws -> AdapterOutput { try await execute(arguments) }
    public func readback(_ arguments: JSONValue, output: AdapterOutput?, requestID: String) async -> JSONValue? { await readback(arguments, output: output) }
    public func preview(_ arguments: JSONValue) async throws -> ConfirmationPreview {
        ConfirmationPreview(target: definition.summary, changes: [])
    }
    public func readback(_ arguments: JSONValue, output: AdapterOutput?) async -> JSONValue? { output?.output }
}

/// Global approval mode for Asky's own AI conversations. Launcher and external MCP callers are never affected.
public enum ApprovalMode: String, Sendable, Codable, CaseIterable {
    /// Only operations the confirmation rules flag as risky ask the user.
    case autoReview
    /// Agent writes run without suggestions or confirmations.
    case fullAccess
}

/// Snapshot of user-controlled policy, read at every call so revocations apply immediately.
public struct PolicySnapshot: Sendable {
    public var enabledSources: Set<DataSourceID>
    public var mcpInstances: [String: MCPInstance]
    public var approvalMode: ApprovalMode
    public init(enabledSources: Set<DataSourceID>, mcpInstances: [String: MCPInstance] = [:],
                approvalMode: ApprovalMode = .autoReview) {
        self.enabledSources = enabledSources
        self.mcpInstances = mcpInstances
        self.approvalMode = approvalMode
    }
}

public typealias ConfirmationPresenter = @Sendable (ConfirmationRequest) async -> ConfirmationDecision

/// Single authority for every system read/write requested by Launcher, Agent (Pi) or external MCP.
public actor ToolService {
    public static let dedupeWindow: TimeInterval = 10 * 60
    public static let defaultTimeout: Duration = .seconds(20)

    public nonisolated let plugins: PluginManager
    private var adapters: [String: any ToolAdapter] = [:]
    private let executions: ExecutionStore
    private let policy: @Sendable () -> PolicySnapshot
    private let presenter: ConfirmationPresenter
    private let authorize: @Sendable (DataSourceID, CallerOrigin) async throws -> Void
    private let timeout: Duration
    private let writeLock = AsyncLock()
    private var inFlight: [String: Task<ExecutionResult, Never>] = [:]
    private var inFlightSessions: [String: String] = [:]
    public var activeAgentSessionIDs: Set<String> { Set(inFlightSessions.values) }

    public init(store: LocalStore, policy: @escaping @Sendable () -> PolicySnapshot,
                presenter: @escaping ConfirmationPresenter, timeout: Duration = ToolService.defaultTimeout,
                pluginRuntime: PluginRuntimeConfiguration = .init(),
                authorize: @escaping @Sendable (DataSourceID, CallerOrigin) async throws -> Void = { _, _ in }) {
        executions = ExecutionStore(store)
        plugins = PluginManager(store: store, runtime: pluginRuntime)
        self.policy = policy
        self.presenter = presenter
        self.timeout = timeout
        self.authorize = authorize
    }

    public func register(_ adapter: any ToolAdapter) {
        adapters[adapter.definition.name] = adapter
    }

    /// Tools visible to a caller under the current policy.
    public func definitions(for origin: CallerOrigin) async -> [ToolDefinition] {
        let p = policy()
        return (adapters.values.map(\.definition) + (await plugins.definitions()))
            .filter { exposureError($0, origin: origin, policy: p) == nil }
            .sorted { $0.name < $1.name }
    }

    public func submit(_ request: ActionRequest) async -> ExecutionResult {
        if let prior = executions.record(requestID: request.requestID), let result = prior.result,
           prior.status != .awaitingConfirmation {
            return result
        }
        if let running = inFlight[request.requestID] { return await running.value }
        let task = Task { await self.process(request) }
        inFlight[request.requestID] = task
        if case .agent(let id) = request.origin { inFlightSessions[request.requestID] = id }
        let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        inFlight[request.requestID] = nil
        inFlightSessions[request.requestID] = nil
        return result
    }

    // MARK: pipeline

    private func process(_ request: ActionRequest) async -> ExecutionResult {
        var candidate = adapters[request.tool]
        if candidate == nil { candidate = await plugins.adapter(named: request.tool, origin: request.origin) }
        guard let adapter = candidate else {
            return .failure(request.requestID, .unknownTool, CoreLocalization.format("未知工具：%@", String(describing: request.tool)))
        }
        do { try await adapter.prepare(requestID: request.requestID) } catch { return failure(request, error) }
        defer { Task { await adapter.finish(requestID: request.requestID) } }
        let def = adapter.definition
        let p = policy()
        if let err = exposureError(def, origin: request.origin, policy: p) {
            return .failure(request.requestID, err.code, err.message, status: .rejected)
        }
        do {
            if def.name != "history_search" && def.name != "history_read" { try await authorize(def.source, request.origin) }
        } catch { return failure(request, error) }
        if let err = exposureError(def, origin: request.origin, policy: policy()) {
            return .failure(request.requestID, err.code, err.message, status: .rejected)
        }
        if def.effect == .read {
            return await runRead(adapter, request)
        }

        let preview: ConfirmationPreview
        do {
            preview = try await adapter.preview(request.arguments)
        } catch {
            return failure(request, error)
        }
        let confirmation = ConfirmationRequest(requestID: request.requestID, tool: def.name, target: preview.target,
                                               changes: preview.changes, note: preview.note,
                                               argumentsDigest: request.argumentsDigest, origin: request.origin,
                                               title: preview.title, details: preview.details)

        // Full access only applies to Asky's own AI conversations, never Launcher or external MCP callers.
        let fullAccess: Bool
        if case .agent = request.origin { fullAccess = p.approvalMode == .fullAccess } else { fullAccess = false }

        if request.intent == .aiSuggested && !fullAccess {
            return ExecutionResult(requestID: request.requestID, status: .suggestion, confirmation: confirmation)
        }

        if adapter.deduplicatesArguments, let dup = executions.recent(digest: request.argumentsDigest, within: Self.dedupeWindow),
           dup.requestID != request.requestID, var prior = dup.result {
            prior.requestID = request.requestID
            return prior
        }

        if !fullAccess && needsConfirmation(def, request) {
            persist(request, status: .awaitingConfirmation, result: nil)
            let decision = await presenter(confirmation)
            // Re-check policy after waiting: a source or instance may have been revoked meanwhile.
            if let err = exposureError(def, origin: request.origin, policy: policy()) {
                return record(request, .failure(request.requestID, err.code, err.message, status: .rejected))
            }
            guard decision == .approved else {
                return record(request, ExecutionResult(requestID: request.requestID, status: .rejected,
                                                       error: ToolError(.userRejected, CoreLocalization.text("用户未确认，操作未执行")),
                                                       confirmation: confirmation))
            }
        }
        return await runWrite(adapter, request)
    }

    private func runRead(_ adapter: any ToolAdapter, _ request: ActionRequest) async -> ExecutionResult {
        do {
            let out = try await withTimeout(adapter.executionTimeout ?? timeout) { try await adapter.execute(request.arguments, requestID: request.requestID) }
            return ExecutionResult(requestID: request.requestID, status: .completed, targets: out.targets, output: out.output)
        } catch {
            return failure(request, error)
        }
    }

    private func runWrite(_ adapter: any ToolAdapter, _ request: ActionRequest) async -> ExecutionResult {
        await writeLock.lock()
        let result = await runWriteLocked(adapter, request)
        await writeLock.unlock()
        return result
    }

    private func runWriteLocked(_ adapter: any ToolAdapter, _ request: ActionRequest) async -> ExecutionResult {
        persist(request, status: .pendingVerification, result: nil)
        do {
            let out = try await withTimeout(adapter.executionTimeout ?? timeout) { try await adapter.execute(request.arguments, requestID: request.requestID) }
            let readback = await adapter.readback(request.arguments, output: out, requestID: request.requestID)
            let status: ExecutionStatus = readback == nil ? .pendingVerification : .completed
            return record(request, ExecutionResult(requestID: request.requestID, status: status, targets: out.targets,
                                                   output: out.output, readback: readback))
        } catch let e as ToolError where e.code == .timeout {
            // Unknown outcome: read back before reporting; never retry blindly.
            if let rb = await adapter.readback(request.arguments, output: nil, requestID: request.requestID) {
                return record(request, ExecutionResult(requestID: request.requestID, status: .completed, readback: rb))
            }
            return record(request, ExecutionResult(requestID: request.requestID, status: .pendingVerification, error: e))
        } catch is CancellationError {
            let rb = await adapter.readback(request.arguments, output: nil, requestID: request.requestID)
            return record(request, ExecutionResult(requestID: request.requestID, status: rb == nil ? .pendingVerification : .completed,
                                                   readback: rb, error: ToolError(.cancelled, CoreLocalization.text("已取消，结果需核实"))))
        } catch {
            if adapter.definition.source == .plugins, (error as? ToolError)?.code != .invalidArguments {
                let rb = await adapter.readback(request.arguments, output: nil, requestID: request.requestID)
                return record(request, ExecutionResult(requestID: request.requestID, status: rb == nil ? .pendingVerification : .completed,
                                                       readback: rb, error: ToolError(.adapterFailure, error.localizedDescription)))
            }
            return record(request, failure(request, error))
        }
    }

    // MARK: policy

    nonisolated func exposureError(_ def: ToolDefinition, origin: CallerOrigin, policy p: PolicySnapshot) -> ToolError? {
        if def.name == "history_search" || def.name == "history_read" {
            if case .agent = origin { return nil }
            return ToolError(.notExposed, CoreLocalization.text("聊天历史仅向应用内 Agent 开放"))
        }
        guard p.enabledSources.contains(def.source) else {
            return ToolError(.sourceDisabled, CoreLocalization.format("数据源未启用：%@", String(describing: def.source.rawValue)))
        }
        switch origin {
        case .launcher:
            return nil
        case .agent:
            return def.agentExposable ? nil : ToolError(.notExposed, CoreLocalization.text("该工具不向 AI 开放"))
        case .mcp(let instanceID):
            guard def.externallyExposable else { return ToolError(.notExposed, CoreLocalization.text("该工具不向外部 MCP 开放")) }
            guard let inst = p.mcpInstances[instanceID], inst.enabled else {
                return ToolError(.permissionDenied, CoreLocalization.text("MCP 实例未启用或已撤销"))
            }
            guard inst.sources.contains(def.source) else {
                return ToolError(.permissionDenied, CoreLocalization.format("该实例未获准访问 %@", String(describing: def.source.rawValue)))
            }
            if def.effect == .write && inst.readOnly { return ToolError(.permissionDenied, CoreLocalization.text("该实例为只读")) }
            return nil
        }
    }

    nonisolated func needsConfirmation(_ def: ToolDefinition, _ request: ActionRequest) -> Bool {
        switch def.confirmation {
        case .never: return false
        case .explicitDirectOtherwiseConfirm:
            if case .mcp = request.origin { return true }
            return request.intent != .explicitRequest
        case .always: return true
        case .createDirectOtherwiseConfirm:
            if case .mcp = request.origin { return true }
            return def.writeKind != .create || request.intent != .explicitRequest
        }
    }

    // MARK: persistence helpers

    private func persist(_ request: ActionRequest, status: ExecutionStatus, result: ExecutionResult?) {
        let now = Date()
        let created = executions.record(requestID: request.requestID)?.createdAt ?? now
        try? executions.upsert(ExecutionRecord(requestID: request.requestID, tool: request.tool,
                                               argumentsDigest: request.argumentsDigest, origin: Self.originTag(request.origin),
                                               taskID: request.taskID, status: status, result: result,
                                               createdAt: created, updatedAt: now))
    }

    private func record(_ request: ActionRequest, _ result: ExecutionResult) -> ExecutionResult {
        persist(request, status: result.status, result: result)
        return result
    }

    private nonisolated func failure(_ request: ActionRequest, _ error: Error) -> ExecutionResult {
        if let e = error as? ToolError {
            return ExecutionResult(requestID: request.requestID, status: .failed, error: e)
        }
        if error is CancellationError {
            return .failure(request.requestID, .cancelled, CoreLocalization.text("已取消"), status: .cancelled)
        }
        return .failure(request.requestID, .adapterFailure, String(describing: error))
    }

    static func originTag(_ o: CallerOrigin) -> String {
        switch o {
        case .launcher: "launcher"
        case .agent(let s): "agent:\(s)"
        case .mcp(let i): "mcp:\(i)"
        }
    }
}

/// FIFO async mutex used to serialize writes across suspension points.
actor AsyncLock {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func unlock() {
        if waiters.isEmpty {
            locked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

func withTimeout<T: Sendable>(_ limit: Duration, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await op() }
        group.addTask {
            try await Task.sleep(for: limit)
            throw ToolError(.timeout, CoreLocalization.text("操作超时"))
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw ToolError(.timeout, CoreLocalization.text("操作超时")) }
        return first
    }
}
