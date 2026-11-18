import Foundation
import Testing
import Contracts
import LocalStore
import ToolService
@testable import AgentHost

/// Opt-in, billed by the configured DeepSeek account. All conversations and tool results are synthetic.
@Suite struct CacheLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ASKY_CACHE_TEST_CONFIG"] != nil))
    func syntheticFollowups() async throws {
        let configPath = try #require(ProcessInfo.processInfo.environment["ASKY_CACHE_TEST_CONFIG"])
        let saved = try JSONDecoder().decode(ModelConfiguration.self, from: Data(contentsOf: URL(filePath: configPath)))
        try #require(saved.baseURL.scheme == "https" && saved.baseURL.host == "api.deepseek.com")
        let key = try #require(try Keychain().read(account: saved.credentialRef, allowInteraction: false))
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let connection = ModelHTTPConnection()
        let client = NativeModelClient(transport: { request, delta in
            let reply = try await NativeModelClient.send(request, session: connection.session, delta: delta)
            let usage = try #require(reply.cacheUsage)
            print("DeepSeek input tokens: hit=\(usage.hit) miss=\(usage.miss)")
            return reply
        })
        let host = AgentHost(launcher: { NativeRuntime(storage: AgentSessionStorage(root: root), client: client) },
            configProvider: { RuntimeLaunchConfig(baseURL: saved.baseURL.absoluteString, model: saved.modelName, apiKey: key) },
            toolsProvider: { [ToolDefinition(name: "lookup_sample", summary: "读取本次测试样品编号", source: .web, effect: .read, confirmation: .never, externallyExposable: false)] },
            toolHandler: { ExecutionResult(requestID: $0.requestID, status: .completed, output: ["sample": "QZ934"]) })
        var history = (1...80).map { "第\($0)号样品是白色方块，长度为\($0)毫米。" }.joined(separator: "\n")
        let questions = ["只回复数字：2+2 等于多少？", "只回复数字：3+3 等于多少？", "只回复数字：4+4 等于多少？",
                         "调用 lookup_sample 查询测试样品编号，然后只回复编号。"]
        for (i, question) in questions.enumerated() {
            var reply = "", calls = 0
            for await event in await host.submit(AgentRequest(sessionID: "test-\(i)", text: question, context: [ContextSnippet(sourceID: "history", text: history)])) {
                switch event {
                case .message(_, let text): reply = text
                case .toolCall: calls += 1
                case .error(_, let message): Issue.record("Model error: \(message)")
                default: break
                }
            }
            #expect(!reply.isEmpty)
            if i == questions.count - 1 {
                #expect(calls == 1)
                #expect(reply.contains("QZ934"))
            } else { #expect(calls == 0) }
            print("CACHE_TEST turn=\(i + 1) tools=\(calls)")
            history += "\nuser: " + question + "\nassistant: " + reply
            if i + 1 < questions.count { try await Task.sleep(for: .seconds(3)) }
        }
        await host.shutdown()
    }
}
