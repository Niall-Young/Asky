import Foundation
import Contracts

enum PluginWorker {
    static func run(executable: String, arguments: [String], directory: URL, payload: JSONValue,
                    saveState: @escaping @Sendable (JSONValue) -> Void) async throws -> JSONValue {
        let control = PluginProcessControl()
        return try await withTaskCancellationHandler {
            try await Task.detached {
                let p = Process(), input = Pipe(), output = Pipe()
                p.executableURL = URL(filePath: executable); p.arguments = arguments
                p.currentDirectoryURL = directory; p.environment = PluginProcess.environment()
                p.standardInput = input; p.standardOutput = output
                let log = directory.appending(path: "execution.log")
                if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
                // Bound the retained diagnostic log between calls.
                if (try? log.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 > 1024 * 1024 { try Data().write(to: log) }
                let diagnostics = try FileHandle(forWritingTo: log); try diagnostics.seekToEnd()
                p.standardError = diagnostics
                defer { control.cancel(); try? diagnostics.close(); try? input.fileHandleForWriting.close(); try? output.fileHandleForReading.close() }
                try control.launch(p)
                func send(_ value: JSONValue) throws { var data = try JSONEncoder().encode(value); data.append(10); try input.fileHandleForWriting.write(contentsOf: data) }
                try send(payload)
                var buffer = Data()
                while true {
                    let data = output.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    buffer.append(data)
                    while let newline = buffer.firstIndex(of: 10) {
                        let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                        guard line.count <= PluginProcess.maxOutput else { throw ToolError(.adapterFailure, CoreLocalization.text("插件响应过大")) }
                        let frame = try JSONDecoder().decode(JSONValue.self, from: line)
                        if frame["type"]?.stringValue == "result" {
                            if let error = frame["error"]?.stringValue { throw ToolError(frame["errorCode"]?.stringValue == "invalidArguments" ? .invalidArguments : .adapterFailure, error) }
                            return frame["value"] ?? .null
                        }
                        guard frame["type"]?.stringValue == "rpc", let id = frame["id"] else { throw ToolError(.protocolError, CoreLocalization.text("插件运行协议无效")) }
                        let value: JSONValue
                        do {
                            switch frame["method"]?.stringValue {
                            case "state":
                                guard let state = frame["value"] else { throw ToolError(.invalidArguments, CoreLocalization.text("缺少状态")) }
                                saveState(state); value = true
                            case "exec":
                                guard let executable = frame["executable"]?.stringValue,
                                      let args = frame["arguments"]?.arrayValue,
                                      args.allSatisfy({ $0.stringValue != nil }) else { throw ToolError(.invalidArguments, CoreLocalization.text("CLI 参数无效")) }
                                let cwd = frame["cwd"]?.stringValue.map { URL(filePath: $0) } ?? directory
                                let timeout = min(120, max(1, frame["timeoutSeconds"]?.numberValue ?? 20))
                                value = try control.withChild { child in
                                    try PluginProcess.commandSync(executable, args.compactMap(\.stringValue), cwd: cwd, seconds: timeout, control: child).json
                                }
                            default: throw ToolError(.protocolError, CoreLocalization.text("未知插件宿主调用"))
                            }
                            try send(["id": id, "value": value])
                        } catch {
                            try control.check()
                            try send(["id": id, "error": .string(error.localizedDescription)])
                        }
                    }
                    guard buffer.count <= PluginProcess.maxOutput else { throw ToolError(.adapterFailure, CoreLocalization.text("插件响应过大")) }
                }
                try control.check()
                throw ToolError(.adapterFailure, CoreLocalization.text("插件执行进程异常退出；查看 execution.log"))
            }.value
        } onCancel: { control.cancel() }
    }
}
