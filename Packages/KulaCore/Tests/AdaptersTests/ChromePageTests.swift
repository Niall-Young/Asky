import AppKit
import Foundation
import Testing
import Contracts
import LocalStore
import ToolService
@testable import Adapters

@Suite struct ChromePageTests {
    @Test func requiresExplicitSafeTargetAndCompilesEscapedURLs() throws {
        for (w, t, url) in [("0", "2", "https://example.com"), ("1", "invalid", "https://example.com"),
                            ("1", "2", "file:///etc/passwd"), ("1", "2", "chrome://settings"),
                            ("1", "2", "https://user:pass@example.com")] {
            #expect(throws: ToolError.self) { try ChromeBridge.readPageScript(windowID: w, tabID: t, expectedURL: url) }
        }
        let script = try ChromeBridge.readPageScript(windowID: "1", tabID: "2", expectedURL: "https://example.com/?q=quoted%22text")
        #expect(NSAppleScript(source: script) != nil)
        #expect(script.contains("incognito"))
        #expect(script.contains("if URL of tb is not"))
        #expect(ChromeReadPageTool().definition.inputSchema["properties"]?["javascript"] == nil)
    }

    @Test func pageReadingRespectsChromeSourceAndIsNotExposedToMCP() async throws {
        let store = try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory)
        let enabled = ToolService(store: store, policy: { PolicySnapshot(enabledSources: [.chrome]) }, presenter: { _ in .rejected })
        await enabled.register(ChromeReadPageTool())
        #expect(await enabled.definitions(for: .agent(sessionID: "page")).contains { $0.name == "chrome_read_page" })
        #expect(await enabled.definitions(for: .mcp(instanceID: "page")).isEmpty)
        let disabled = ToolService(store: store, policy: { PolicySnapshot(enabledSources: []) }, presenter: { _ in .rejected })
        await disabled.register(ChromeReadPageTool())
        let result = await disabled.submit(ActionRequest(tool: "chrome_read_page", arguments: ["windowID": "1", "tabID": "2", "url": "https://example.com"], origin: .agent(sessionID: "page"), intent: .explicitRequest))
        #expect(result.error?.code == .sourceDisabled)
    }

    @Test func pagePermissionGuidanceIsPreserved() {
        #expect(AppleScript.mapError(code: -27001, message: "Enable Chrome page reading").code == .permissionDenied)
        #expect(AppleScript.mapError(code: -27001, message: "Enable Chrome page reading").message == "Enable Chrome page reading")
    }

}
