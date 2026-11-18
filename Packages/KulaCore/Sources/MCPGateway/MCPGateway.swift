import Foundation
import Darwin
import CryptoKit
import Security
import os
import Contracts
import LocalStore
import ToolService
import MCPLink

/// External MCP instances: registration, credential check, and a hard deny-list that holds even if
/// a tool were mis-declared as externally exposable.
public struct MCPGateway: Sendable {
    /// Never reachable from external MCP, regardless of settings (PRD: no memory, clipboard, keys, shell).
    public static let blockedSources: Set<DataSourceID> = [.memory, .clipboard, .terminal]

    private let instances: MCPInstanceStore
    private let tools: ToolService

    public init(store: LocalStore, tools: ToolService) {
        instances = MCPInstanceStore(store)
        self.tools = tools
    }

    /// Creates a disabled, read-only instance. The credential is returned once and only its hash is stored.
    public func register(name: String) throws -> (MCPInstance, credential: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ToolError(.adapterFailure, CoreLocalization.text("无法生成凭据"))
        }
        let credential = "kmcp_" + Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let inst = MCPInstance(name: name)
        try instances.save(inst, credentialHash: Self.hash(credential))
        return (inst, credential)
    }

    public static func hash(_ credential: String) -> String {
        SHA256.hash(data: Data(credential.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Looks the instance up on every call so edits and revocation apply immediately.
    public func authenticate(_ credential: String) -> MCPInstance? {
        instances.instance(credentialHash: Self.hash(credential))
    }

    public func listTools(credential: String) async -> [ToolDefinition]? {
        guard let inst = authenticate(credential), inst.enabled else { return nil }
        return await tools.definitions(for: .mcp(instanceID: inst.id))
            .filter { !Self.blockedSources.contains($0.source) }
    }

    /// Writes from MCP always go through native confirmation (ToolService policy); client-declared
    /// confirmation fields are stripped by `ActionRequest`.
    public func call(credential: String, tool: String, arguments: JSONValue) async -> ExecutionResult {
        let requestID = UUID().uuidString
        guard let inst = authenticate(credential), inst.enabled else {
            return .failure(requestID, .permissionDenied, CoreLocalization.text("MCP 实例未启用或已撤销"), status: .rejected)
        }
        let defs = await tools.definitions(for: .mcp(instanceID: inst.id))
        if let def = defs.first(where: { $0.name == tool }), Self.blockedSources.contains(def.source) {
            return .failure(requestID, .notExposed, CoreLocalization.text("该工具不向外部 MCP 开放"), status: .rejected)
        }
        let req = ActionRequest(requestID: requestID, tool: tool, arguments: arguments,
                                origin: .mcp(instanceID: inst.id), intent: .explicitRequest)
        return await tools.submit(req)
    }
}

/// Listens on a same-user Unix socket for bridge connections. Bounded connections and frames.
public final class MCPLinkServer: Sendable {
    public static let maxConnections = 8

    private let path: String
    private let gateway: MCPGateway
    private let state = OSAllocatedUnfairLock<(listenFD: Int32, source: DispatchSourceRead?, connections: Int)>(initialState: (-1, nil, 0))
    private let queue = DispatchQueue(label: "asky.mcp.link")
    private let activity = OSAllocatedUnfairLock<(inFlight: Int, last: Date)>(initialState: (0, .distantPast))

    public init(socketPath: String = MCPLink.defaultSocketPath(), gateway: MCPGateway) {
        path = socketPath
        self.gateway = gateway
    }

    public func start() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        if path == MCPLink.defaultSocketPath() {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir)
        }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EMFILE) }
        let rc = withUnixAddress(path) { bind(fd, $0, $1) }
        guard rc == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
            let e = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: e) ?? .EADDRINUSE)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptPending(fd) }
        src.setCancelHandler { close(fd) }
        state.withLock { $0 = (fd, src, 0) }
        src.activate()
    }

    /// Stops listening and removes the socket, so bridges report the app as unavailable.
    public func stop() {
        let src = state.withLock { s -> DispatchSourceRead? in defer { s.source = nil; s.listenFD = -1 }; return s.source }
        src?.cancel()
        unlink(path)
    }

    private func acceptPending(_ listenFD: Int32) {
        while true {
            let c = accept(listenFD, nil, nil)
            guard c >= 0 else { return }
            _ = fcntl(c, F_SETNOSIGPIPE, 1)
            _ = fcntl(c, F_SETFL, fcntl(c, F_GETFL) & ~O_NONBLOCK)
            let admitted = state.withLock { s -> Bool in
                guard s.connections < Self.maxConnections else { return false }
                s.connections += 1
                return true
            }
            guard admitted, Self.peerIsCurrentUser(c) else {
                if admitted { state.withLock { $0.connections -= 1 } }
                close(c)
                continue
            }
            serve(c)
        }
    }

    /// True while a bridge request is being handled or one finished within `window`.
    /// Open but idle connections do not count: bridges reconnect after the app restarts.
    public func isBusy(within window: TimeInterval) -> Bool {
        activity.withLock { $0.inFlight > 0 || Date().timeIntervalSince($0.last) < window }
    }

    static func peerIsCurrentUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0, gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }

    private func serve(_ fd: Int32) {
        let conn = Connection(fd: fd, gateway: gateway, onActivity: { [weak self] began in
            self?.activity.withLock {
                $0.inFlight += began ? 1 : -1
                $0.last = Date()
            }
        }) { [weak self] in
            self?.state.withLock { $0.connections -= 1 }
        }
        conn.start()
    }
}

/// One bridge connection: frames handled strictly in order on an async loop.
private final class Connection: @unchecked Sendable {
    let fd: Int32
    let gateway: MCPGateway
    let onActivity: @Sendable (Bool) -> Void
    let onClose: @Sendable () -> Void
    private var credential: String?

    init(fd: Int32, gateway: MCPGateway, onActivity: @escaping @Sendable (Bool) -> Void,
         onClose: @escaping @Sendable () -> Void) {
        self.fd = fd
        self.gateway = gateway
        self.onActivity = onActivity
        self.onClose = onClose
    }

    func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "asky.mcp.connection"))
        let framer = ConnectionFramer()
        source.setCancelHandler { [fd, onClose] in close(fd); onClose() }
        source.setEventHandler { [self] in
            var bytes = [UInt8](repeating: 0, count: 64 * 1024)
            let n = Darwin.read(fd, &bytes, bytes.count)
            if n < 0, errno == EINTR { return }
            guard n > 0 else { source.cancel(); return }
            var oversized = false
            let lines = framer.value.push(Data(bytes[..<n])) { oversized = true }
            guard !oversized else { source.cancel(); return }
            guard !lines.isEmpty else { return }
            // Pause reads while the batch is handled. The socket supplies backpressure.
            source.suspend()
            Task {
                defer { source.resume() }
                for line in lines {
                    onActivity(true)
                    let keep = await handle(line)
                    onActivity(false)
                    if !keep { source.cancel(); return }
                }
            }
        }
        source.activate()
    }

    // Confined to the serial read-source queue.
    private final class ConnectionFramer: @unchecked Sendable { var value = LineFramer() }

    /// Returns false to drop the connection.
    private func handle(_ line: Data) async -> Bool {
        guard let frame = try? JSONDecoder().decode(MCPLink.ClientFrame.self, from: line) else { return false }
        switch frame {
        case .hello(let version, let cred):
            guard credential == nil else { return false }
            guard version == MCPLink.version else { return reply(.denied(message: CoreLocalization.text("协议版本不匹配"))) && false }
            guard let inst = gateway.authenticate(cred), inst.enabled else {
                return reply(.denied(message: CoreLocalization.text("凭据无效或实例未启用"))) && false
            }
            credential = cred
            return reply(.welcome(instance: inst.name))
        case .listTools(let id):
            guard let cred = credential else { return false }
            guard let tools = await gateway.listTools(credential: cred) else {
                return reply(.denied(message: CoreLocalization.text("MCP 实例未启用或已撤销"))) && false
            }
            return reply(.tools(id: id, tools: tools))
        case .call(let id, let tool, let args):
            guard let cred = credential else { return false }
            return reply(.result(id: id, result: await gateway.call(credential: cred, tool: tool, arguments: args)))
        }
    }

    private func reply(_ f: MCPLink.ServerFrame) -> Bool {
        guard let d = try? MCPLink.encode(f) else { return false }
        if d.count - 1 > MCPLink.maxFrameBytes {
            let id: Int
            switch f {
            case .result(let request, _), .tools(let request, _): id = request
            default: return false
            }
            return reply(.failure(id: id, message: CoreLocalization.text("模型响应超过大小上限")))
        }
        return writeAll(fd, d)
    }
}
