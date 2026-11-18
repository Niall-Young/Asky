import Foundation
import Contracts
import Darwin

/// Owns only plugin workers and short-lived CLI clients, never the external Orca Agent.
final class PluginProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [Process] = []
    private var children: [PluginProcessControl] = []
    private var cancelled = false
    private var timedOut = false
    func launch(_ process: Process) throws {
        lock.lock(); defer { lock.unlock() }
        if timedOut { throw ToolError(.timeout, CoreLocalization.text("进程执行超时")) }
        if cancelled { throw CancellationError() }
        try process.run()
        processes.append(process)
    }
    func check() throws {
        lock.lock(); defer { lock.unlock() }
        if timedOut { throw ToolError(.timeout, CoreLocalization.text("进程执行超时")) }
        if cancelled { throw CancellationError() }
    }
    func withChild<T>(_ body: (PluginProcessControl) throws -> T) throws -> T {
        let child = PluginProcessControl()
        try lock.withLock {
            guard !cancelled else { throw CancellationError() }
            children.append(child)
        }
        defer { lock.withLock { children.removeAll { $0 === child } } }
        return try body(child)
    }

    func cancel(timedOut: Bool = false) {
        lock.lock(); cancelled = true; self.timedOut = self.timedOut || timedOut; let running = processes; let nested = children; lock.unlock()
        for child in nested { child.cancel(timedOut: timedOut) }
        for p in running where p.isRunning {
            p.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { if p.isRunning { kill(p.processIdentifier, SIGKILL) } }
        }
    }
}
struct PluginCommandResult: Sendable {
    var stdout: String
    var stderr: String
    var exitCode: Int32
    var json: JSONValue { ["stdout": .string(stdout), "stderr": .string(stderr), "exitCode": .number(Double(exitCode))] }
}

enum PluginProcess {
    static let maxOutput = 512 * 1024
    static func environment() -> [String: String] {
        let env = ProcessInfo.processInfo.environment
        return ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "HOME": env["HOME"] ?? NSHomeDirectory(),
                "TMPDIR": NSTemporaryDirectory(), "LANG": env["LANG"] ?? "en_US.UTF-8"]
    }
    static func executable(_ name: String) throws -> String {
        let paths = name.hasPrefix("/") ? [name] : (environment()["PATH"] ?? "").split(separator: ":").map { "\($0)/\(name)" } + [NSHomeDirectory() + "/.local/bin/" + name]
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ToolError(.unavailable, CoreLocalization.format("未找到可执行程序：%@", String(describing: name)))
        }
        return path
    }
    private static func collect(_ handle: FileHandle, control: PluginProcessControl) throws -> Data {
        var data = Data()
        while let chunk = try handle.read(upToCount: 8192), !chunk.isEmpty {
            guard data.count + chunk.count <= maxOutput else {
                control.cancel(); throw ToolError(.adapterFailure, CoreLocalization.text("进程输出超出 512 KiB 上限"))
            }
            data.append(chunk)
        }
        return data
    }
    /// Blocking work runs off the UI/actor. Both pipes drain concurrently to avoid deadlocks.
    static func commandSync(_ executable: String, _ arguments: [String], cwd: URL?, seconds: Double,
                            control: PluginProcessControl) throws -> PluginCommandResult {
        try control.check()
        let p = Process(), out = Pipe(), err = Pipe()
        p.executableURL = URL(filePath: try self.executable(executable)); p.arguments = arguments
        p.environment = environment(); p.currentDirectoryURL = cwd
        p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
        try control.launch(p)
        let timer = DispatchWorkItem { if p.isRunning { control.cancel(timedOut: true) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: timer)
        let group = DispatchGroup(), stderr = PluginDataBox()
        group.enter()
        DispatchQueue.global().async {
            stderr.result = Result { try collect(err.fileHandleForReading, control: control) }; group.leave()
        }
        let stdout = Result { try collect(out.fileHandleForReading, control: control) }
        p.waitUntilExit(); group.wait(); timer.cancel()
        let output = try stdout.get(), diagnostic = try stderr.result!.get()
        try control.check()
        return PluginCommandResult(stdout: String(decoding: output, as: UTF8.self),
                                       stderr: String(decoding: diagnostic, as: UTF8.self), exitCode: p.terminationStatus)
    }
    static func command(_ executable: String, _ arguments: [String], cwd: URL? = nil, seconds: Double = 60) async throws -> PluginCommandResult {
        let control = PluginProcessControl()
        return try await withTaskCancellationHandler {
            try await Task.detached { try commandSync(executable, arguments, cwd: cwd, seconds: seconds, control: control) }.value
        } onCancel: { control.cancel() }
    }
}
private final class PluginDataBox: @unchecked Sendable {
    // Written by one pipe-reader, read only after DispatchGroup.wait().
    var result: Result<Data, Error>?
}
