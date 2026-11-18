import Foundation
import OSLog
import Contracts
import ToolService

struct PromptCacheUsage: Equatable, Sendable {
    let hit: Int
    let miss: Int

    init?(_ usage: JSONValue?) {
        guard let hit = usage?["prompt_cache_hit_tokens"]?.numberValue.flatMap(Int.init(exactly:)), hit >= 0,
              let miss = usage?["prompt_cache_miss_tokens"]?.numberValue.flatMap(Int.init(exactly:)), miss >= 0 else { return nil }
        self.hit = hit
        self.miss = miss
    }
}

enum ModelRequestPhase: String {
    case initial, continuation, compaction
}

public struct NativeCompletion: Sendable {
    public var text: String
    public var calls: [JSONValue]
    var cacheUsage: PromptCacheUsage?
    public var reasoningContent: String?
    public init(text: String = "", calls: [JSONValue] = [], reasoningContent: String? = nil) {
        self.text = text; self.calls = calls; self.reasoningContent = reasoningContent
    }
    var message: JSONValue {
        var value: [String: JSONValue] = ["role": "assistant", "content": .string(text)]
        if !calls.isEmpty { value["tool_calls"] = .array(calls) }
        if let reasoningContent { value["reasoning_content"] = .string(reasoningContent) }
        return .object(value)
    }
}

public enum NativeModelError: LocalizedError {
    case invalidURL, http(Int), malformed(String), limit
    public var errorDescription: String? {
        switch self {
        case .invalidURL: CoreLocalization.text("模型 API 地址无效")
        case .http(let code): CoreLocalization.format("模型请求失败（HTTP %d）", code)
        case .malformed(let reason): CoreLocalization.format("模型响应无效：%@", reason)
        case .limit: CoreLocalization.text("模型响应超过大小上限")
        }
    }
}

/// Incremental Chat Completions decoder. Fragmented tool arguments are validated only at completion.
struct NativeCompletionDecoder {
    var text = ""
    var calls: [Int: [String: String]] = [:]
    var lastCallIndex = 0
    var finish: String?
    var bytes = 0
    var reasoning = ""
    var cacheUsage: PromptCacheUsage?
    mutating func consume(_ value: JSONValue) throws -> String? {
        if value["error"] != nil { throw NativeModelError.malformed(CoreLocalization.text("提供方返回错误")) }
        if let usage = PromptCacheUsage(value["usage"]) { cacheUsage = usage }
        guard let choice = value["choices"]?.arrayValue?.first else { return nil } // usage / heartbeat
        if let reason = choice["finish_reason"]?.stringValue { finish = reason }
        let delta = choice["delta"] ?? choice["message"] ?? [:]
        let content = delta["content"]?.stringValue
        if let content { text += content; bytes += content.utf8.count }
        if let fragment = delta["reasoning_content"]?.stringValue {
            reasoning += fragment; bytes += fragment.utf8.count
        }
        for call in delta["tool_calls"]?.arrayValue ?? [] {
            let nextIndex = call["id"] == nil ? lastCallIndex : (calls.keys.max().map { $0 + 1 } ?? 0)
            let rawIndex = call["index"]?.numberValue ?? Double(nextIndex)
            guard rawIndex.isFinite, rawIndex.rounded() == rawIndex, rawIndex >= 0, rawIndex < 128 else { throw NativeModelError.limit }
            let index = Int(rawIndex)
            lastCallIndex = index
            var current = calls[index] ?? ["id": "", "name": "", "arguments": ""]
            for (key, fragment) in [("id", call["id"]), ("name", call["function"]?["name"]), ("arguments", call["function"]?["arguments"])] {
                if let fragment = fragment?.stringValue { current[key, default: ""] += fragment; bytes += fragment.utf8.count }
            }
            calls[index] = current
        }
        guard bytes <= 1024 * 1024 else { throw NativeModelError.limit }
        return content
    }

    func result() throws -> NativeCompletion {
        guard finish == "stop" || finish == "tool_calls" else { throw NativeModelError.malformed(CoreLocalization.text("输出中断或达到生成上限")) }
        var ids = Set<String>()
        let tools: [JSONValue] = try calls.keys.sorted().map { index in
            let call = calls[index]!
            let arguments = call["arguments"] ?? ""
            let raw = arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : arguments
            guard let id = call["id"], !id.isEmpty, ids.insert(id).inserted,
                  let name = call["name"], !name.isEmpty,
                  let data = raw.data(using: .utf8),
                  let args = try? JSONDecoder().decode(JSONValue.self, from: data), args.objectValue != nil else {
                throw NativeModelError.malformed(CoreLocalization.text("工具参数或调用标识无效"))
            }
            return ["id": .string(id), "type": "function", "function": ["name": .string(name), "arguments": .string(raw)]]
        }
        var reply = NativeCompletion(text: text, calls: tools, reasoningContent: reasoning.isEmpty ? nil : reasoning)
        reply.cacheUsage = cacheUsage
        return reply
    }
}

public struct NativeModelClient: Sendable {
    public typealias Transport = @Sendable (URLRequest, @escaping @Sendable (String) -> Void) async throws -> NativeCompletion
    private static let cacheLog = Logger(subsystem: "app.kulahere.KulaHere", category: "ModelCache")
    private let transport: Transport
    public init(transport: Transport? = nil) {
        if let transport { self.transport = transport }
        else {
            let connection = ModelHTTPConnection()
            self.transport = { request, delta in
                try await Self.send(request, session: connection.session, delta: delta)
            }
        }
    }

    func complete(config: RuntimeLaunchConfig, messages: [JSONValue], tools: [JSONValue], phase: ModelRequestPhase,
                  delta: @escaping @Sendable (String) -> Void) async throws -> NativeCompletion {
        guard let endpoint = try? ModelHTTPConnection.endpoint(config.baseURL) else { throw NativeModelError.invalidURL }
        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer " + config.apiKey, forHTTPHeaderField: "Authorization")
        var body: [String: JSONValue] = ["model": .string(config.model), "messages": .array(messages), "stream": true, "max_tokens": 8192]
        // Matches the former runtime's thinkingLevel=off. Custom endpoints are not given vendor flags.
        if endpoint.host?.lowercased() == "api.deepseek.com" {
            body["thinking"] = ["type": "disabled"]
            body["stream_options"] = ["include_usage": true]
        }
        if !tools.isEmpty { body["tools"] = .array(tools); body["tool_choice"] = "auto" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        request.httpBody = try encoder.encode(JSONValue.object(body))
        let reply = try await transport(request, delta)
        if let usage = reply.cacheUsage {
            Self.cacheLog.notice("phase=\(phase.rawValue, privacy: .public) hit=\(usage.hit) miss=\(usage.miss)")
        }
        return reply
    }

    /// No shared disk cache, cookies or credential storage. Redirects cannot forward BYOK credentials.
    static func send(_ request: URLRequest, session: URLSession, delta: @escaping @Sendable (String) -> Void) async throws -> NativeCompletion {
        var emitted = false
        for attempt in 0...1 {
            do {
                let (stream, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse else { throw NativeModelError.malformed(CoreLocalization.text("不是 HTTP 响应")) }
                guard (200..<300).contains(http.statusCode) else {
                    if attempt == 0 && (http.statusCode == 429 || (500...599).contains(http.statusCode)) {
                        try await Task.sleep(for: .seconds(1)); continue
                    }
                    throw NativeModelError.http(http.statusCode)
                }
                var decoder = NativeCompletionDecoder(), line = Data(), event: [String] = []
                let isJSON = http.value(forHTTPHeaderField: "Content-Type")?.contains("application/json") == true
                var json = Data()
                func consumeEvent() throws -> Bool {
                    guard !event.isEmpty else { return false }
                    let payload = event.joined(separator: "\n"); event.removeAll()
                    if payload == "[DONE]" { return true }
                    let value = try JSONDecoder().decode(JSONValue.self, from: Data(payload.utf8))
                    if let content = try decoder.consume(value), !content.isEmpty { emitted = true; delta(content) }
                    return false
                }
                for try await byte in stream {
                    try Task.checkCancellation()
                    if isJSON {
                        json.append(byte); guard json.count <= 1024 * 1024 else { throw NativeModelError.limit }; continue
                    }
                    if byte == 10 {
                        let value = String(decoding: line, as: UTF8.self).trimmingCharacters(in: .newlines)
                        line.removeAll(keepingCapacity: true)
                        if value.isEmpty, try consumeEvent() {
                            // SSE completion is independent of TCP/HTTP connection teardown.
                            // Some compatible endpoints leave the response open after [DONE].
                            stream.task.cancel()
                            break
                        }
                        else if value.hasPrefix("data:") {
                            event.append(String(value.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                            guard event.reduce(0, { $0 + $1.utf8.count }) <= 1024 * 1024 else { throw NativeModelError.limit }
                        }
                    } else { line.append(byte); guard line.count <= 1024 * 1024 else { throw NativeModelError.limit } }
                }
                if isJSON {
                    let value = try JSONDecoder().decode(JSONValue.self, from: json)
                    if let content = try decoder.consume(value) { emitted = true; delta(content) }
                } else { _ = try consumeEvent() }
                return try decoder.result()
            } catch let error as URLError where attempt == 0 && !emitted && [.networkConnectionLost, .timedOut, .cannotConnectToHost].contains(error.code) {
                try await Task.sleep(for: .seconds(1))
            }
        }
        throw NativeModelError.malformed(CoreLocalization.text("请求未完成"))
    }
}
