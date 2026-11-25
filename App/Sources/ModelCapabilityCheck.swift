import Foundation
import Contracts
import ToolService

/// HTTP failures do not establish that a model lacks a capability.
enum ModelCapabilityCheck {
    struct Report {
        var capabilities: ModelCapabilities
        var failures: [String]
    }

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static func run(baseURL: URL, model: String, apiKey: String,
                    transport: Transport = { try await ModelHTTPConnection.data(for: $0) }) async -> Report {
        let endpoint = (try? ModelHTTPConnection.endpoint(baseURL.absoluteString)) ?? baseURL
        func requestBody(_ messages: [[String: Any]], maxTokens: Int, tools: [[String: Any]]? = nil) -> [String: Any] {
            let tokenKey = ModelHTTPConnection.usesMaxCompletionTokens(endpoint: endpoint, model: model)
                ? "max_completion_tokens" : "max_tokens"
            var body: [String: Any] = ["model": model, tokenKey: maxTokens, "messages": messages]
            if ModelHTTPConnection.usesOpenAIReasoningEffortNone(endpoint: endpoint, model: model) {
                body["reasoning_effort"] = "none"
            }
            if let tools { body["tools"] = tools }
            return body
        }
        let text = await probe(baseURL, apiKey, transport, requestBody([["role": "user", "content": "ping"]], maxTokens: 4))
        let tools = await probe(baseURL, apiKey, transport, requestBody(
            [["role": "user", "content": "call noop"]], maxTokens: 16,
            tools: [["type": "function", "function": ["name": "noop", "description": "no-op",
                                                      "parameters": ["type": "object", "properties": [String: String]()]]]]
        ))
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let image = await probe(baseURL, apiKey, transport, requestBody([
            ["role": "user", "content": [
                ["type": "text", "text": "color?"],
                ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(png)"]],
            ]],
        ], maxTokens: 4))
        let failures = [(NSLocalizedString("文本", comment: ""), text),
                        (NSLocalizedString("工具调用", comment: ""), tools),
                        (NSLocalizedString("图像输入", comment: ""), image)].compactMap { label, error in
            error.map { "\(label)：\($0)" }
        }
        return Report(capabilities: ModelCapabilities(text: text == nil ? .available : .unknown,
                      image: image == nil ? .available : .unknown, tools: tools == nil ? .available : .unknown,
                      checkedAt: Date()), failures: failures)
    }

    private static func probe(_ base: URL, _ key: String, _ transport: Transport, _ body: [String: Any]) async -> String? {
        guard let endpoint = try? ModelHTTPConnection.endpoint(base.absoluteString) else { return CoreLocalization.text("模型 API 地址无效") }
        var req = URLRequest(url: endpoint, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await transport(req)
            guard let response = response as? HTTPURLResponse else {
                return NSLocalizedString("模型服务未返回有效的 HTTP 响应。", comment: "")
            }
            guard !(200..<300).contains(response.statusCode) else { return nil }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let nested = json?["error"] as? [String: Any]
            let detail = nested?["message"] as? String ?? json?["message"] as? String
            let hint: String
            switch response.statusCode {
            case 401: hint = NSLocalizedString("API Key 无效或未通过认证。", comment: "")
            case 402: hint = NSLocalizedString("模型服务账户余额不足，请检查此 API Key 对应的余额或套餐额度。", comment: "")
            case 403: hint = NSLocalizedString("此 API Key 无权访问该模型，请检查模型或套餐权限。", comment: "")
            case 429: hint = NSLocalizedString("模型服务限流或额度受限，请稍后重试。", comment: "")
            default: hint = NSLocalizedString("模型服务拒绝了检查请求。", comment: "")
            }
            // Never show request headers or unstructured response bodies; redact echoed credentials.
            let safeDetail = detail.map { String($0.replacingOccurrences(of: key, with: "[redacted]").prefix(500)) }
            return "HTTP \(response.statusCode)：\(hint)" + (safeDetail.map { " \($0)" } ?? "")
        } catch {
            return String(format: NSLocalizedString("连接失败：%@", comment: ""),
                          error.localizedDescription.replacingOccurrences(of: key, with: "[redacted]"))
        }
    }
}
