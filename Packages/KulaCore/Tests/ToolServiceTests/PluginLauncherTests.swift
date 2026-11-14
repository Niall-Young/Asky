import Foundation
import Testing
import Contracts
import LocalStore
@testable import ToolService

@Suite struct PluginLauncherTests {
    private var repository: URL {
        var url = URL(filePath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
    private func manifest() throws -> PluginManifest {
        try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: repository.appending(path: "examples/plugins/text-tools/asky-plugin.json")))
    }

    @Test func manifestCompatibilityAndSearchMustBeReadOnly() throws {
        let root = repository.appending(path: "examples/plugins/text-tools")
        var value = try manifest()
        try value.validate(at: root)
        value.commands = nil
        try value.validate(at: root)
        value = try manifest()
        value.tools[0].effect = .write
        value.tools[0].confirmation = .always
        #expect(throws: Error.self) { try value.validate(at: root) }
        value = try manifest()
        value.commands?[0].tool = "missing"
        #expect(throws: Error.self) { try value.validate(at: root) }
        value = try manifest()
        value.commands?[0].queryArgument = "unknown"
        #expect(throws: Error.self) { try value.validate(at: root) }
        value = try manifest()
        let duplicate = value.commands![0]
        value.commands?.append(duplicate)
        #expect(throws: Error.self) { try value.validate(at: root) }
    }

    @Test func nativeResultsAreBoundedAndRejectInvalidLinksAndDuplicateIDs() throws {
        let values: JSONValue = ["items": [["id": "one", "title": "One", "copy": "中文", "url": "https://example.com"]]]
        let rows = try PluginLauncherOutput.results(values, commandID: "text_tools/text")
        #expect(rows.first?.actions == [.copy("中文"), .openURL(URL(string: "https://example.com")!)])
        for url in ["file:///tmp/a", "javascript:alert(1)", "https://user:secret@example.com", "https:"] {
            let value: JSONValue = ["items": [["id": "one", "title": "One", "url": .string(url)]]]
            #expect(throws: Error.self) { try PluginLauncherOutput.results(value, commandID: "a") }
        }
        #expect(throws: Error.self) { try PluginLauncherOutput.results(["items": [["id": "x", "title": "A"], ["id": "x", "title": "B"]]], commandID: "a") }
        let many: JSONValue = ["items": .array((0..<300).map { ["id": .string(String($0)), "title": "Row"] })]
        #expect(try PluginLauncherOutput.results(many, commandID: "a").count == 200)
    }

    @Test func installedExampleExecutesWithoutAgentAndFollowsLifecycle() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalStore(root: root)
        let service = ToolService(store: store, policy: { PolicySnapshot(enabledSources: [.plugins]) },
            presenter: { _ in Issue.record("Read commands should not confirm"); return .rejected })
        let source = repository.appending(path: "examples/plugins/text-tools")
        await service.plugins.setInstallationCommand { _, args, _, _ in
            if args.first == "clone" { try FileManager.default.copyItem(at: source, to: URL(filePath: args.last!)) }
            return PluginCommandResult(stdout: "example-commit", stderr: "", exitCode: 0)
        }
        try await service.plugins.install(repository: "https://github.com/example/text-tools")
        #expect(await service.plugins.launcherCommands().isEmpty)
        await service.plugins.setEnabled("text_tools", true)
        #expect(await service.plugins.launcherCommands().count == 2)
        #expect(await service.definitions(for: .agent(sessionID: "test")).isEmpty)
        let hidden = await service.submit(ActionRequest(tool: "plugin_text_tools__transform", arguments: ["text": "test"], origin: .agent(sessionID: "test"), intent: .explicitRequest))
        #expect(hidden.status == .failed)
        let result = await service.runPluginCommand(id: "text_tools/text", query: "你好 world")
        #expect(result.status == .completed)
        let rows = try PluginLauncherOutput.results(#require(result.output), commandID: "text_tools/text")
        #expect(rows.first?.title == "%E4%BD%A0%E5%A5%BD%20world")
        let uuid = await service.runPluginCommand(id: "text_tools/uuid", query: "ignored")
        #expect(UUID(uuidString: uuid.output?["text"]?.stringValue ?? "") != nil)
        await service.plugins.setEnabled("text_tools", false)
        #expect(await service.runPluginCommand(id: "text_tools/text", query: "x").status == .failed)
        #expect(await service.plugins.launcherCommands().isEmpty)
        try await service.plugins.uninstall("text_tools")
        #expect(await service.plugins.launcherCommands().isEmpty)
    }

    @Test func launcherWriteCommandStillRequiresConfirmationAndReadback() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalStore(root: root)
        var m = try manifest()
        // Keep a separate API v1 fixture to verify legacy write compatibility.
        m.apiVersion = 1; m.entry = "index.mjs"
        m.commands = [m.commands![1]]
        m.tools = [m.tools[1]]
        m.tools[0].effect = .write
        m.tools[0].confirmation = .always
        let directory = root.appending(path: "plugins/text_tools")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "export default {tools:{uuid:{execute(){return {text:'done'}},readback(){return {text:'done'}}}}}".write(to: directory.appending(path: "index.mjs"), atomically: true, encoding: .utf8)
        let record = InstalledPlugin(manifest: m, repository: "https://github.com/example/text-tools", commit: "test", enabled: true, configuration: [:])
        store.setCodableSetting("plugins.installed", [record])
        let runtime = PluginRuntimeConfiguration(nodePath: try PluginProcess.executable("node"), runnerPath: repository.appending(path: "PluginSupport/plugin-runner.mjs").path)
        let rejected = ToolService(store: store, policy: { PolicySnapshot(enabledSources: [.plugins], approvalMode: .fullAccess) }, presenter: { _ in .rejected }, pluginRuntime: runtime)
        #expect(await rejected.runPluginCommand(id: "text_tools/uuid", query: "").status == .rejected)
        let approved = ToolService(store: store, policy: { PolicySnapshot(enabledSources: [.plugins]) }, presenter: { _ in .approved }, pluginRuntime: runtime)
        let result = await approved.runPluginCommand(id: "text_tools/uuid", query: "")
        #expect(result.status == .completed)
        #expect(result.readback?["text"] == "done")
    }
}
