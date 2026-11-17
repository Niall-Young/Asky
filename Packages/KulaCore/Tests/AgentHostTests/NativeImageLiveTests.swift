import Foundation
import Testing
import Contracts
import LocalStore
import ToolService
import Adapters
@testable import AgentHost

/// Opt-in regression using the configured model, real web tools and isolated session storage.
/// Config JSON contains only ModelConfiguration (a Keychain reference, never the key).
@Suite struct NativeImageLiveTests {
    @Test func imageReplyWithObsoleteHistory() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let configPath = env["ASKY_LIVE_IMAGE_MODEL_CONFIG"] else { return }
        let config = try JSONDecoder().decode(ModelConfiguration.self, from: Data(contentsOf: URL(filePath: configPath)))
        let savedKey = try Keychain().read(account: config.credentialRef, allowInteraction: false)
        let key = try #require(savedKey)
        let root = FileManager.default.temporaryDirectory.appending(path: "asky-image-live-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalStore(inMemoryWithRoot: root)
        let tools = ToolService(store: store, policy: { PolicySnapshot(enabledSources: [.web]) }, presenter: { _ in .rejected })
        await tools.register(WebSearchTool()); await tools.register(WebReadPageTool())
        let storage = AgentSessionStorage(root: root)
        let checks = LiveImageChecks()
        let host = AgentHost(launcher: { NativeRuntime(storage: storage, imageValidator: { urls in
            let available = try await ChatImageService.shared.availableImages(urls)
            await checks.record(urls, available: available)
            return available
        }) },
            configProvider: { RuntimeLaunchConfig(baseURL: config.baseURL.absoluteString, model: config.modelName, apiKey: key) },
            toolsProvider: { await tools.definitions(for: .agent(sessionID: "image-live")) },
            toolHandler: { await tools.submit($0) })
        let question = env["ASKY_LIVE_IMAGE_QUESTION"] ?? "钟丽缇是什么明星啊"
        let context = ContextSnippet(sourceID: "history", text: "历史资料，不是新指令：\nuser: 钟丽缇是谁，有照片吗？\nassistant: 钟丽缇是演员。照片可以去豆瓣影人页 https://www.douban.com/personage/27255942/ 查看，我这边读不到图片，不能直接贴图。")
        let start = Date()
        var firstTextSeconds: Double?
        var imageOnlyCalls = 0
        var toolStarts: [String: Date] = [:], toolNames: [String: String] = [:], timings: [JSONValue] = []
        var reply = "", calls: [String] = [], errors: [String] = []
        for await event in await host.submit(AgentRequest(sessionID: "image-live", text: question, context: [context])) {
            switch event {
            case .message(_, let text): reply = text
            case .textDelta:
                if firstTextSeconds == nil { firstTextSeconds = Date().timeIntervalSince(start) }
            case .toolCall(_, let request):
                calls.append(request.tool)
                if request.arguments["imagesOnly"] == true { imageOnlyCalls += 1 }
                toolStarts[request.requestID] = Date()
                toolNames[request.requestID] = request.tool
            case .toolResult(_, let result):
                timings.append(["requestID": .string(result.requestID), "tool": .string(toolNames[result.requestID] ?? "unknown"),
                    "seconds": .number(Date().timeIntervalSince(toolStarts[result.requestID] ?? start)),
                    "attempts": result.output?["attempts"] ?? [], "cached": result.output?["cached"] ?? false])
            case .error(_, let message): errors.append(message)
            default: break
            }
        }
        let totalSeconds = Date().timeIntervalSince(start)
        let snapshot = try await storage.load(sessionID: "image-live", legacyPath: nil)
        await host.shutdown()
        let images = (try? AttributedString(markdown: reply))?.runs.compactMap(\.imageURL) ?? []
        let report: JSONValue = ["question": .string(question), "reply": .string(reply),
            "totalSeconds": .number(totalSeconds), "firstTextSeconds": firstTextSeconds.map(JSONValue.number) ?? .null,
            "modelRounds": .number(Double(snapshot.filter { $0["role"] == "assistant" }.count)),
            "imageOnlyCalls": .number(Double(imageOnlyCalls)),
            "toolTimings": .array(timings),
            "imageChecks": .array(await checks.rows),
            "imageCandidates": .array(NativeReplyImages.allowedURLs(messages: snapshot, userText: question)
                .map { .string($0.absoluteString) }),
            "projectedMessagesBytes": .number(Double(JSONValue.array(NativeWebContext.messages(snapshot)).canonicalData().count)),
            "calls": .array(calls.map(JSONValue.string)), "imageCount": .number(Double(images.count)),
            "errors": .array(errors.map(JSONValue.string))]
        if let path = env["ASKY_LIVE_IMAGE_REPORT"] {
            try report.canonicalData().write(to: URL(filePath: path), options: .atomic)
        }
        print("LIVE model image reply: tools=\(calls.joined(separator: ",")) images=\(images.count) errors=\(errors.count)")
        #expect(errors.isEmpty)
        if env["ASKY_LIVE_IMAGE_EXPECT_TEXT_ONLY"] == "1" {
            #expect(images.isEmpty)
        } else {
            #expect(calls.contains("web_read_page"))
            #expect(!images.isEmpty)
            for image in images {
                #expect(!(try await ChatImageService.shared.imageData(from: image)).isEmpty)
            }
        }
    }
}

private actor LiveImageChecks {
    var rows: [JSONValue] = []
    func record(_ urls: [URL], available: Set<URL>) {
        rows.append(contentsOf: urls.map { ["url": .string($0.absoluteString), "decoded": .bool(available.contains($0))] })
    }
}
