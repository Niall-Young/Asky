import Foundation

public final class ModelHTTPConnection: Sendable {
    public let session: URLSession

    public static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let connection = ModelHTTPConnection()
        defer { connection.session.finishTasksAndInvalidate() }
        return try await connection.session.data(for: request)
    }

    public static func endpoint(_ address: String) throws -> URL {
        guard var url = URLComponents(string: address), let host = url.host,
              url.scheme == "https" || (url.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(host)),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw URLError(.badURL) }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path == "chat/completions" || path.hasSuffix("/chat/completions") {
            url.path = "/" + path
        } else {
            url.path = path.isEmpty ? "/chat/completions" : "/" + path + "/chat/completions"
        }
        guard let endpoint = url.url else { throw URLError(.badURL) }
        return endpoint
    }

    public static func usesMaxCompletionTokens(endpoint: URL, model: String) -> Bool {
        guard endpoint.host?.lowercased() == "api.openai.com" else { return false }
        let name = model.lowercased()
        return name.hasPrefix("gpt-5") || name.hasPrefix("gpt-6")
            || (name.hasPrefix("o") && name.dropFirst().first?.isNumber == true)
    }

    /// OpenAI GPT-5.4+ and GPT-6 Luna require reasoning_effort="none" for Chat Completions tool calling.
    public static func usesOpenAIReasoningEffortNone(endpoint: URL, model: String) -> Bool {
        guard endpoint.host?.lowercased() == "api.openai.com" else { return false }
        let name = model.lowercased()
        return name == "gpt-6-luna" || name.hasPrefix("gpt-6-luna-")
            || name.hasPrefix("gpt-5.6") || name.hasPrefix("gpt-5.4")
    }

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration, delegate: NoModelRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
}

private final class NoModelRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
