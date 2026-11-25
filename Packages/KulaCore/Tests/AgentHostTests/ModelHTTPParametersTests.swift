import Foundation
import Testing
import Contracts
import ToolService
@testable import AgentHost

@Suite
struct ModelHTTPParametersTests {
    @Test func openAIChatCompletionsParametersMatchModelCapabilities() async throws {
        let openAI = try ModelHTTPConnection.endpoint("https://api.openai.com/v1")
        #expect(ModelHTTPConnection.usesMaxCompletionTokens(endpoint: openAI, model: "gpt-6-luna"))
        #expect(ModelHTTPConnection.usesMaxCompletionTokens(endpoint: openAI, model: "gpt-5.6-sol"))
        #expect(ModelHTTPConnection.usesMaxCompletionTokens(endpoint: openAI, model: "gpt-5.4"))
        #expect(!ModelHTTPConnection.usesMaxCompletionTokens(endpoint: openAI, model: "gpt-4.1"))
        #expect(ModelHTTPConnection.usesOpenAIReasoningEffortNone(endpoint: openAI, model: "gpt-6-luna"))
        #expect(ModelHTTPConnection.usesOpenAIReasoningEffortNone(endpoint: openAI, model: "gpt-5.6-terra"))
        #expect(ModelHTTPConnection.usesOpenAIReasoningEffortNone(endpoint: openAI, model: "gpt-5.4"))
        #expect(!ModelHTTPConnection.usesOpenAIReasoningEffortNone(endpoint: openAI, model: "gpt-6.2-sol"))
        #expect(!ModelHTTPConnection.usesOpenAIReasoningEffortNone(endpoint: openAI, model: "gpt-4.1"))

        let proxy = try ModelHTTPConnection.endpoint("https://proxy.example/v1")
        #expect(!ModelHTTPConnection.usesMaxCompletionTokens(endpoint: proxy, model: "gpt-6-luna"))
        #expect(!ModelHTTPConnection.usesOpenAIReasoningEffortNone(endpoint: proxy, model: "gpt-6-luna"))

        actor BodyCapture {
            var bodies: [JSONValue] = []
            func record(_ request: URLRequest) throws {
                if let data = request.httpBody {
                    bodies.append(try JSONDecoder().decode(JSONValue.self, from: data))
                }
            }
        }
        let capture = BodyCapture()
        let client = NativeModelClient { request, _ in
            try await capture.record(request)
            return NativeCompletion(text: "ok")
        }

        let openAIConfig = RuntimeLaunchConfig(baseURL: "https://api.openai.com/v1", model: "gpt-6-luna", apiKey: "k")
        _ = try await client.complete(config: openAIConfig, messages: [["role": "user", "content": "hi"]],
                                      tools: [], phase: .initial) { _ in }
        let legacyConfig = RuntimeLaunchConfig(baseURL: "https://api.openai.com/v1", model: "gpt-4.1", apiKey: "k")
        _ = try await client.complete(config: legacyConfig, messages: [["role": "user", "content": "hi"]],
                                      tools: [], phase: .initial) { _ in }
        let deepSeekConfig = RuntimeLaunchConfig(baseURL: "https://api.deepseek.com", model: "deepseek-flash", apiKey: "k")
        _ = try await client.complete(config: deepSeekConfig, messages: [["role": "user", "content": "hi"]],
                                      tools: [], phase: .initial) { _ in }

        let bodies = await capture.bodies
        #expect(bodies.count == 3)
        #expect(bodies[0]["max_tokens"] == nil)
        #expect(bodies[0]["max_completion_tokens"] == 8192)
        #expect(bodies[0]["reasoning_effort"] == "none")

        #expect(bodies[1]["max_tokens"] == 8192)
        #expect(bodies[1]["max_completion_tokens"] == nil)
        #expect(bodies[1]["reasoning_effort"] == nil)

        #expect(bodies[2]["max_tokens"] == 8192)
        #expect(bodies[2]["thinking"] == ["type": "disabled"])
        #expect(bodies[2]["reasoning_effort"] == nil)
    }
}
