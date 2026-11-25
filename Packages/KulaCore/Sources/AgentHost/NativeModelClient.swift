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

public enum ModelFailureReason: Sendable, Equatable {
    case invalidURL
    case authentication
    case insufficientQuota
    case permissionDenied
    case modelNotFound
    case contextTooLong
    case contentFiltered
    case unsupportedImage
    case unsupportedTools
    case rateLimited
    case badRequest
    case timeout
    case serverUnavailable
    case outputLengthLimit
    case outputInterrupted
    case emptyResponse
    case responseTooLarge
    case invalidToolCall
    case malformedResponse
    case compactionFailed
    case toolRoundLimit
    case providerError
    case networkOffline
    case cannotFindHost
    case cannotConnect
    case tlsFailure
    case networkError
    case unknown

    public var userMessage: String {
        switch self {
        case .invalidURL:
            CoreLocalization.text("模型 API 地址格式有误，请在「设置 › 模型」中检查后重试。")
        case .authentication:
            CoreLocalization.text("API Key 无效或已失效，请在「设置 › 模型」中检查并更新。")
        case .insufficientQuota:
            CoreLocalization.text("模型服务账户余额或额度不足，请充值或检查套餐后重试。")
        case .permissionDenied:
            CoreLocalization.text("当前 API Key 没有权限访问该模型或服务，请检查账号权限或地区限制。")
        case .modelNotFound:
            CoreLocalization.text("找不到对应的模型或接口地址，请在「设置 › 模型」中核对 API 地址与模型名称。")
        case .contextTooLong:
            CoreLocalization.text("当前对话内容或附件过长，超出了模型的处理上限，请精简内容或开启新对话后重试。")
        case .contentFiltered:
            CoreLocalization.text("当前内容触发了模型服务的安全限制，无法生成回复，请调整表述后重试。")
        case .unsupportedImage:
            CoreLocalization.text("当前模型不支持处理图片附件，请切换支持视觉的模型或移除图片后重试。")
        case .unsupportedTools:
            CoreLocalization.text("当前模型不支持工具调用，请在「设置 › 模型」中更换支持工具调用的模型。")
        case .rateLimited:
            CoreLocalization.text("请求过于频繁，模型服务暂时限流，请稍后再试。")
        case .badRequest:
            CoreLocalization.text("模型服务无法处理本次请求，请检查模型设置或调整内容后重试。")
        case .timeout:
            CoreLocalization.text("连接或等待 AI 响应超时，请检查网络状况后重试。")
        case .serverUnavailable:
            CoreLocalization.text("模型服务暂时不可用或出现故障，请稍后重试。")
        case .outputLengthLimit:
            CoreLocalization.text("本次回复达到模型的生成长度上限，未能完整输出，请尝试拆分为更小的问题后重试。")
        case .outputInterrupted:
            CoreLocalization.text("AI 生成过程中意外中断，未能完成回复，请重试。")
        case .emptyResponse:
            CoreLocalization.text("AI 未能生成有效回复，请重试。")
        case .responseTooLarge:
            CoreLocalization.text("AI 返回的内容过大，超出了单次处理上限，请缩小问题范围后重试。")
        case .invalidToolCall:
            CoreLocalization.text("AI 返回的操作指令有误，无法继续执行，请重试。")
        case .malformedResponse:
            CoreLocalization.text("模型返回了无法识别的内容，请检查 API 地址是否为兼容的对话接口，或稍后重试。")
        case .compactionFailed:
            CoreLocalization.text("整理较长对话的上下文时出现异常，请重试或开启新对话。")
        case .toolRoundLimit:
            CoreLocalization.text("自动操作步骤已达上限，已暂停执行，你可以补充说明后继续。")
        case .providerError:
            CoreLocalization.text("模型服务返回异常，暂时无法生成回复，请稍后重试。")
        case .networkOffline:
            CoreLocalization.text("网络连接已断开，请检查网络或代理设置后重试。")
        case .cannotFindHost:
            CoreLocalization.text("找不到模型服务器，请检查网络连接或 API 地址是否填写正确。")
        case .cannotConnect:
            CoreLocalization.text("无法连接到模型服务，请检查网络、代理或服务是否正常运行。")
        case .tlsFailure:
            CoreLocalization.text("与模型服务的安全连接失败，请检查系统时间、代理或网络环境。")
        case .networkError:
            CoreLocalization.text("网络连接出现异常，暂时无法请求模型服务，请稍后重试。")
        case .unknown:
            CoreLocalization.text("AI 暂时遇到故障，无法生成回复，请稍后重试。")
        }
    }
}

public enum NativeModelError: LocalizedError, Equatable {
    case invalidURL
    case http(Int, reason: ModelFailureReason? = nil)
    case malformed(String)
    case limit
    case failure(ModelFailureReason)

    public var failureReasonCategory: ModelFailureReason {
        switch self {
        case .invalidURL: .invalidURL
        case .http(let code, let reason): reason ?? Self.classifyHTTP(statusCode: code, body: nil)
        case .malformed: .malformedResponse
        case .limit: .responseTooLarge
        case .failure(let reason): reason
        }
    }

    public var errorDescription: String? {
        failureReasonCategory.userMessage
    }

    /// Maps any runtime, HTTP, decoding, or transport error into natural language with a safe fallback.
    public static func userMessage(for error: Error, redacting secret: String? = nil) -> String {
        let message: String
        if let modelError = error as? NativeModelError {
            message = modelError.failureReasonCategory.userMessage
        } else if let hostError = error as? AgentHostError, let description = hostError.errorDescription {
            message = description
        } else if let urlError = error as? URLError {
            message = classifyURLError(urlError).userMessage
        } else if error is DecodingError {
            message = ModelFailureReason.malformedResponse.userMessage
        } else {
            message = ModelFailureReason.unknown.userMessage
        }
        guard let secret, !secret.isEmpty else { return message }
        return message.replacingOccurrences(of: secret, with: "[redacted]")
    }

    static func classifyURLError(_ error: URLError) -> ModelFailureReason {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return .networkOffline
        case .timedOut:
            return .timeout
        case .cannotFindHost, .dnsLookupFailed:
            return .cannotFindHost
        case .cannotConnectToHost:
            return .cannotConnect
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot,
             .clientCertificateRejected, .clientCertificateRequired:
            return .tlsFailure
        case .badURL, .unsupportedURL:
            return .invalidURL
        default:
            return .networkError
        }
    }

    static func classifyHTTP(statusCode: Int, body: Data?) -> ModelFailureReason {
        let signals = providerErrorSignals(from: body)
        if let specific = classifyProviderSignals(signals, statusCode: statusCode) {
            return specific
        }
        switch statusCode {
        case 400: return .badRequest
        case 401: return .authentication
        case 402: return .insufficientQuota
        case 403: return .permissionDenied
        case 404: return .modelNotFound
        case 408: return .timeout
        case 413: return .contextTooLong
        case 429: return .rateLimited
        case 500...599: return .serverUnavailable
        default: return .providerError
        }
    }

    static func classifyProviderError(_ value: JSONValue?) -> ModelFailureReason {
        var parts: [String] = []
        if let str = value?.stringValue {
            parts.append(str)
        } else if let obj = value?.objectValue {
            for key in ["code", "type", "message", "status"] {
                if let text = obj[key]?.stringValue { parts.append(text) }
            }
        }
        let signals = parts.joined(separator: " ").lowercased()
        return classifyProviderSignals(signals, statusCode: nil) ?? .providerError
    }

    private static func providerErrorSignals(from body: Data?) -> String {
        guard let body, !body.isEmpty else { return "" }
        if let json = try? JSONDecoder().decode(JSONValue.self, from: body) {
            var parts: [String] = []
            if let err = json["error"] {
                if let str = err.stringValue { parts.append(str) }
                if let obj = err.objectValue {
                    for key in ["code", "type", "message", "param"] {
                        if let text = obj[key]?.stringValue { parts.append(text) }
                    }
                }
            }
            for key in ["code", "type", "message", "detail"] {
                if let text = json[key]?.stringValue { parts.append(text) }
            }
            if !parts.isEmpty { return parts.joined(separator: " ").lowercased() }
        }
        return String(decoding: body.prefix(1024), as: UTF8.self).lowercased()
    }

    private static func classifyProviderSignals(_ signals: String, statusCode: Int?) -> ModelFailureReason? {
        guard !signals.isEmpty else { return nil }
        if signals.contains("insufficient_quota")
            || signals.contains("insufficient_balance")
            || signals.contains("insufficient balance")
            || signals.contains("insufficient funds")
            || signals.contains("out of credits")
            || signals.contains("credit balance")
            || signals.contains("exceeded your current quota")
            || signals.contains("billing") {
            return .insufficientQuota
        }
        if signals.contains("invalid_api_key")
            || signals.contains("incorrect api key")
            || signals.contains("authentication")
            || signals.contains("unauthorized") {
            return .authentication
        }
        if signals.contains("context_length_exceeded")
            || signals.contains("maximum context length")
            || signals.contains("context window")
            || signals.contains("too many tokens")
            || signals.contains("prompt is too long")
            || signals.contains("token limit")
            || signals.contains("input is too long") {
            return .contextTooLong
        }
        if signals.contains("model_not_found")
            || signals.contains("model does not exist")
            || signals.contains("unknown model")
            || signals.contains("invalid model") {
            return .modelNotFound
        }
        if signals.contains("content_filter")
            || signals.contains("content management policy")
            || signals.contains("safety")
            || signals.contains("moderation")
            || signals.contains("data_inspection_failed")
            || signals.contains("inappropriate content") {
            return .contentFiltered
        }
        if (signals.contains("image") || signals.contains("vision") || signals.contains("multimodal"))
            && (signals.contains("not support") || signals.contains("unsupported") || signals.contains("does not support")) {
            return .unsupportedImage
        }
        if (signals.contains("tool") || signals.contains("function"))
            && (signals.contains("not support") || signals.contains("unsupported") || signals.contains("does not support")) {
            return .unsupportedTools
        }
        if signals.contains("rate_limit")
            || signals.contains("rate limit")
            || signals.contains("too many requests") {
            return .rateLimited
        }
        if statusCode == nil && (signals.contains("overloaded") || signals.contains("temporarily unavailable") || signals.contains("service unavailable")) {
            return .serverUnavailable
        }
        return nil
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
        if let err = value["error"] { throw NativeModelError.failure(NativeModelError.classifyProviderError(err)) }
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
        switch finish {
        case "stop", "tool_calls":
            break
        case "length":
            throw NativeModelError.failure(.outputLengthLimit)
        case "content_filter":
            throw NativeModelError.failure(.contentFiltered)
        default:
            throw NativeModelError.failure(.outputInterrupted)
        }
        var ids = Set<String>()
        let tools: [JSONValue] = try calls.keys.sorted().map { index in
            let call = calls[index]!
            let arguments = call["arguments"] ?? ""
            let raw = arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : arguments
            guard let id = call["id"], !id.isEmpty, ids.insert(id).inserted,
                  let name = call["name"], !name.isEmpty,
                  let data = raw.data(using: .utf8),
                  let args = try? JSONDecoder().decode(JSONValue.self, from: data), args.objectValue != nil else {
                throw NativeModelError.failure(.invalidToolCall)
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
        var body: [String: JSONValue] = ["model": .string(config.model), "messages": .array(messages), "stream": true]
        let tokenKey = ModelHTTPConnection.usesMaxCompletionTokens(endpoint: endpoint, model: config.model)
            ? "max_completion_tokens" : "max_tokens"
        body[tokenKey] = 8192
        // Matches the former runtime's thinkingLevel=off. Custom endpoints are not given vendor flags.
        if endpoint.host?.lowercased() == "api.deepseek.com" {
            body["thinking"] = ["type": "disabled"]
            body["stream_options"] = ["include_usage": true]
        } else if ModelHTTPConnection.usesOpenAIReasoningEffortNone(endpoint: endpoint, model: config.model) {
            body["reasoning_effort"] = "none"
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
                guard let http = response as? HTTPURLResponse else { throw NativeModelError.failure(.malformedResponse) }
                guard (200..<300).contains(http.statusCode) else {
                    if attempt == 0 && (http.statusCode == 429 || (500...599).contains(http.statusCode)) {
                        stream.task.cancel()
                        try await Task.sleep(for: .seconds(1)); continue
                    }
                    var errorBody = Data()
                    for try await byte in stream {
                        errorBody.append(byte)
                        if errorBody.count >= 8192 {
                            stream.task.cancel()
                            break
                        }
                    }
                    let reason = NativeModelError.classifyHTTP(statusCode: http.statusCode, body: errorBody)
                    throw NativeModelError.http(http.statusCode, reason: reason)
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
        throw NativeModelError.failure(.outputInterrupted)
    }
}
