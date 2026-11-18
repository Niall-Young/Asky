import Foundation
import Darwin
import Contracts

/// Local link between the stdio MCP Bridge and the running app.
/// Transport: a same-user Unix domain socket (0600, in a 0700 directory) carrying JSON lines.
/// Every frame after `hello` is authorised against the instance credential again on the app side.
public enum MCPLink {
    public static let version = 1
    public static let maxFrameBytes = 1 << 20

    public static func defaultSocketPath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "KulaHere/mcp.sock").path
    }

    public enum ClientFrame: Sendable, Codable, Equatable {
        case hello(version: Int, credential: String)
        case listTools(id: Int)
        case call(id: Int, tool: String, arguments: JSONValue)
    }

    public enum ServerFrame: Sendable, Codable, Equatable {
        case welcome(instance: String)
        case denied(message: String)
        case tools(id: Int, tools: [ToolDefinition])
        case result(id: Int, result: ExecutionResult)
        case failure(id: Int, message: String)
    }

    public static func encode<T: Encodable>(_ v: T) throws -> Data {
        var d = try JSONEncoder().encode(v)
        d.append(0x0A)
        return d
    }
}

/// Splits a byte stream into newline-terminated frames; drops (and reports) oversized ones.
public struct LineFramer: Sendable {
    private var buffer = Data()
    private var discarding = false
    public init() {}

    public mutating func push(_ chunk: Data, onOversize: () -> Void = {}) -> [Data] {
        var out: [Data] = []
        for byte in chunk {
            if byte == 0x0A {
                if !discarding, !buffer.isEmpty { out.append(buffer) }
                buffer.removeAll(keepingCapacity: true)
                discarding = false
            } else if !discarding {
                buffer.append(byte)
                if buffer.count > MCPLink.maxFrameBytes {
                    buffer.removeAll()
                    discarding = true
                    onOversize()
                }
            }
        }
        return out
    }
}

public enum MCPLinkError: Error, Equatable, CustomStringConvertible {
    /// The app is not running (or not listening). Recoverable: start Asky and retry.
    case appUnavailable
    case denied(String)
    case closed
    case protocolError(String)

    public var description: String {
        switch self {
        case .appUnavailable: CoreLocalization.text("Asky 未运行或未开启外部 MCP。请启动 Asky 后重试。")
        case .denied(let m): CoreLocalization.format("接入被拒绝：%@", String(describing: m))
        case .closed: CoreLocalization.text("与 Asky 的连接已断开。请重试。")
        case .protocolError(let m): CoreLocalization.format("协议错误：%@", String(describing: m))
        }
    }
}

/// Blocking client used by the bridge. One request at a time.
public final class MCPLinkClient: @unchecked Sendable {
    private let fd: Int32
    private var framer = LineFramer()
    private var pending: [Data] = []
    private var nextID = 0
    private let lock = NSLock()
    /// Display name of the authorised instance, as known by the app.
    public private(set) var instance = ""

    public init(socketPath: String = MCPLink.defaultSocketPath(), credential: String) throws {
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { throw MCPLinkError.appUnavailable }
        _ = fcntl(s, F_SETNOSIGPIPE, 1)
        guard withUnixAddress(socketPath, { connect(s, $0, $1) }) == 0 else {
            close(s)
            throw MCPLinkError.appUnavailable
        }
        fd = s
        try send(.hello(version: MCPLink.version, credential: credential))
        switch try receive() {
        case .welcome(let name): instance = name
        case .denied(let m): throw MCPLinkError.denied(m)  // deinit closes fd
        default: throw MCPLinkError.protocolError(CoreLocalization.text("握手响应无效"))
        }
    }
    deinit { close(fd) }

    public func listTools() throws -> [ToolDefinition] {
        try lock.withLock {
            nextID += 1
            let id = nextID
            try send(.listTools(id: id))
            switch try receive() {
            case .tools(id, let tools): return tools
            case .failure(id, let m): throw MCPLinkError.protocolError(m)
            case .denied(let m): throw MCPLinkError.denied(m)
            default: throw MCPLinkError.protocolError(CoreLocalization.text("响应无效"))
            }
        }
    }

    public func call(tool: String, arguments: JSONValue) throws -> ExecutionResult {
        try lock.withLock {
            nextID += 1
            let id = nextID
            try send(.call(id: id, tool: tool, arguments: arguments))
            switch try receive() {
            case .result(id, let r): return r
            case .failure(id, let m): throw MCPLinkError.protocolError(m)
            case .denied(let m): throw MCPLinkError.denied(m)
            default: throw MCPLinkError.protocolError(CoreLocalization.text("响应无效"))
            }
        }
    }

    private func send(_ f: MCPLink.ClientFrame) throws {
        let data = try MCPLink.encode(f)
        guard data.count - 1 <= MCPLink.maxFrameBytes else { throw MCPLinkError.protocolError(CoreLocalization.text("模型响应超过大小上限")) }
        guard writeAll(fd, data) else { throw MCPLinkError.closed }
    }

    private func receive() throws -> MCPLink.ServerFrame {
        while pending.isEmpty {
            var buf = [UInt8](repeating: 0, count: 64 * 1024)
            let n = read(fd, &buf, buf.count)
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { throw MCPLinkError.closed }
            var oversized = false
            pending += framer.push(Data(buf[0..<n])) { oversized = true }
            if oversized { throw MCPLinkError.protocolError(CoreLocalization.text("模型响应超过大小上限")) }
        }
        let line = pending.removeFirst()
        do { return try JSONDecoder().decode(MCPLink.ServerFrame.self, from: line) } catch {
            throw MCPLinkError.protocolError(CoreLocalization.text("消息帧格式无效"))
        }
    }
}

// MARK: socket helpers

@discardableResult
public func writeAll(_ fd: Int32, _ data: Data) -> Bool {
    data.withUnsafeBytes { buf in
        var off = 0
        while off < buf.count {
            let n = Darwin.write(fd, buf.baseAddress! + off, buf.count - off)
            if n < 0 { if errno == EINTR { continue }; return false }
            off += n
        }
        return true
    }
}

public func withUnixAddress(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> Int32) -> Int32 {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    let cap = MemoryLayout.size(ofValue: addr.sun_path)
    guard bytes.count < cap else { errno = ENAMETOOLONG; return -1 }
    withUnsafeMutableBytes(of: &addr.sun_path) { p in
        p.copyBytes(from: bytes)
        p[bytes.count] = 0
    }
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    return withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
}
