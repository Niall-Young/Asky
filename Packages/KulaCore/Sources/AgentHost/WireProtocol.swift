import Foundation
import Contracts

/// JSONL wire protocol between AgentHost and its runtime adapter. The native adapter transports these frames in memory.
/// stdout carries protocol frames only; diagnostics go to stderr.
public enum WireProtocol {
    public static let version = 2
    /// Max bytes per frame (one line). Attachments travel by file path, never inline Base64.
    public static let maxFrameBytes = 1 << 20
}

/// Host → runtime.
public enum HostMessage: Sendable, Equatable {
    case hello(protocolVersion: Int)
    /// Credential is passed in-process via stdin once; never via argv, env or disk.
    case configure(baseURL: String, model: String, apiKey: String, tools: [ToolDefinition], maxToolRounds: Int, pluginGuidance: [String] = [], promptConfig: AgentPromptConfiguration = .default)
    case resources(tools: [ToolDefinition], pluginGuidance: [String], promptConfig: AgentPromptConfiguration = .default)
    case prompt(AgentRequest, sessionFile: String?)
    case cancel(taskID: String)
    case toolResult(callID: String, ExecutionResult)
    case shutdown

    public func encoded() throws -> Data {
        var o: [String: JSONValue] = [:]
        switch self {
        case .hello(let v):
            o = ["type": "hello", "protocol": .number(Double(v))]
        case .configure(let url, let model, let key, let tools, let rounds, let guidance, let promptConfig):
            o = ["type": "configure", "baseURL": .string(url), "model": .string(model), "apiKey": .string(key),
                 "tools": try Self.json(tools), "maxToolRounds": .number(Double(rounds)), "pluginGuidance": try Self.json(guidance),
                 "promptStyle": .string(promptConfig.style.rawValue)]
            if let custom = promptConfig.normalizedCustomInstructions { o["customInstructions"] = .string(custom) }
        case .resources(let tools, let guidance, let promptConfig):
            o = ["type": "resources", "tools": try Self.json(tools), "pluginGuidance": try Self.json(guidance),
                 "promptStyle": .string(promptConfig.style.rawValue)]
            if let custom = promptConfig.normalizedCustomInstructions { o["customInstructions"] = .string(custom) }
        case .prompt(let r, let sessionFile):
            o = ["type": "prompt", "request": try Self.json(r)]
            if let sessionFile { o["sessionFile"] = .string(sessionFile) }
        case .cancel(let id):
            o = ["type": "cancel", "taskID": .string(id)]
        case .toolResult(let callID, let result):
            o = ["type": "toolResult", "callID": .string(callID), "result": try Self.json(result)]
        case .shutdown:
            o = ["type": "shutdown"]
        }
        var d = try JSONEncoder().encode(JSONValue.object(o))
        guard d.count < WireProtocol.maxFrameBytes else { throw FrameError.oversized(d.count) }
        d.append(0x0A)
        return d
    }

    static func json<T: Encodable>(_ v: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(v))
    }
}

/// Runtime → host.
public enum RuntimeMessage: Sendable, Equatable {
    case ready(protocolVersion: Int, runtimeVersion: String)
    case taskState(taskID: String, AgentTaskState, sessionFile: String?)
    case textDelta(taskID: String, String)
    case message(taskID: String, String)
    case toolCall(taskID: String, callID: String, tool: String, arguments: JSONValue, intent: UserIntent)
    case clarification(taskID: String, question: String)
    case error(taskID: String?, String)

    public static func decode(_ line: Data) throws -> RuntimeMessage {
        let v = try JSONDecoder().decode(JSONValue.self, from: line)
        func s(_ k: String) throws -> String {
            guard let x = v[k]?.stringValue else { throw FrameError.malformed(CoreLocalization.format("缺少字段：%@", k)) }
            return x
        }
        switch v["type"]?.stringValue {
        case "ready":
            guard let version = v["protocol"]?.numberValue.flatMap(Int.init(exactly:)) else {
                throw FrameError.malformed(CoreLocalization.text("协议版本不匹配"))
            }
            return .ready(protocolVersion: version, runtimeVersion: v["runtime"]?.stringValue ?? "")
        case "taskState":
            guard let st = AgentTaskState(rawValue: try s("state")) else { throw FrameError.malformed(CoreLocalization.text("任务状态无效")) }
            return .taskState(taskID: try s("taskID"), st, sessionFile: v["sessionFile"]?.stringValue)
        case "textDelta": return .textDelta(taskID: try s("taskID"), try s("text"))
        case "message": return .message(taskID: try s("taskID"), try s("text"))
        case "toolCall":
            // Default to aiSuggested: the runtime must assert an explicit user request for direct creation.
            let intent = UserIntent(rawValue: v["intent"]?.stringValue ?? "") ?? .aiSuggested
            return .toolCall(taskID: try s("taskID"), callID: try s("callID"), tool: try s("tool"),
                             arguments: v["arguments"] ?? .object([:]), intent: intent)
        case "clarification": return .clarification(taskID: try s("taskID"), question: try s("question"))
        case "error": return .error(taskID: v["taskID"]?.stringValue, v["message"]?.stringValue ?? CoreLocalization.text("未知错误"))
        default: throw FrameError.malformed(CoreLocalization.text("未知消息类型"))
        }
    }
}

public enum FrameError: LocalizedError, Equatable, CustomStringConvertible {
    case oversized(Int)
    case malformed(String)

    public var errorDescription: String? { description }
    public var description: String {
        switch self {
        case .oversized(let size): CoreLocalization.format("消息帧超过大小上限（%d 字节）", size)
        case .malformed(let reason): CoreLocalization.format("消息帧格式无效：%@", reason)
        }
    }
}

/// Splits a byte stream into newline-delimited frames, bounding memory per frame.
public struct LineFramer: Sendable {
    private var buffer = Data()
    private var discarding = false
    public let maxFrame: Int

    public init(maxFrame: Int = WireProtocol.maxFrameBytes) { self.maxFrame = maxFrame }

    /// Returns complete frames; oversized frames are reported as errors and skipped up to the next newline.
    public mutating func push(_ chunk: Data) -> [Result<Data, FrameError>] {
        var out: [Result<Data, FrameError>] = []
        var rest = chunk[...]
        while let nl = rest.firstIndex(of: 0x0A) {
            let part = rest[rest.startIndex..<nl]
            rest = rest[rest.index(after: nl)...]
            if discarding {
                discarding = false
                buffer.removeAll(keepingCapacity: false)
                continue
            }
            buffer.append(part)
            if buffer.count > maxFrame {
                out.append(.failure(.oversized(buffer.count)))
            } else if !buffer.isEmpty {
                out.append(.success(buffer))
            }
            buffer = Data()
        }
        if !discarding {
            buffer.append(rest)
            if buffer.count > maxFrame {
                out.append(.failure(.oversized(buffer.count)))
                buffer = Data()
                discarding = true
            }
        }
        return out
    }
}
