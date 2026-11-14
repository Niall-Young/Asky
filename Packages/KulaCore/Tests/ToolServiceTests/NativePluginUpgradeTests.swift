import Foundation
import Testing
import Contracts
import LocalStore
@testable import ToolService

@Suite struct NativePluginUpgradeTests {
    @Test func legacyLauncherUpgradesWithoutNodeAndPreservesConfigurationStateAndRollback() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalStore(root: root)
        var repository = URL(filePath: #filePath)
        for _ in 0..<5 { repository.deleteLastPathComponent() }
        let source = repository.appending(path: "examples/plugins/text-tools")
        let manifestData = try Data(contentsOf: source.appending(path: "asky-plugin.json"))
        var old = try JSONDecoder().decode(PluginManifest.self, from: manifestData)
        old.apiVersion = 1; old.entry = "index.mjs"; old.version = "1.0.0"
        let installed = root.appending(path: "plugins/text_tools")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        try JSONEncoder().encode(old).write(to: installed.appending(path: "asky-plugin.json"))
        try "export default {tools:{}}".write(to: installed.appending(path: "index.mjs"), atomically: true, encoding: .utf8)
        let origin = "https://github.com/example/text-tools"
        store.setCodableSetting("plugins.installed", [InstalledPlugin(manifest: old, repository: origin, commit: "legacy", enabled: true, configuration: ["saved": "keep"] )])
        let checkpoint: JSONValue = ["attempts": ["old-request": "do-not-replay"]]
        store.setCodableSetting("plugins.state.text_tools", checkpoint)
        // Deliberately provide neither Node nor a JavaScript runner.
        let service = ToolService(store: store, policy: { PolicySnapshot(enabledSources: [.plugins]) }, presenter: { _ in .rejected })
        await service.plugins.setInstallationCommand { _, args, _, _ in
            if args.first == "clone" { try FileManager.default.copyItem(at: source, to: URL(filePath: args.last!)) }
            return PluginCommandResult(stdout: "native", stderr: "", exitCode: 0)
        }
        try await service.plugins.install(repository: origin)
        let upgraded = try #require(await service.plugins.installed().first)
        #expect(upgraded.manifest.apiVersion == 2)
        #expect(upgraded.enabled)
        #expect(upgraded.configuration["saved"] == "keep")
        #expect(upgraded.previousCommit == "legacy")
        #expect(store.codableSetting("plugins.state.text_tools", as: JSONValue.self) == checkpoint)
        for (input, expected) in [("你好 world", "%E4%BD%A0%E5%A5%BD%20world"), ("/ &?", "%2F%20%26%3F"), ("%E4%", "%25E4%25"), ("\"`$(echo hi)\"", "%22%60%24(echo%20hi)%22")] {
            let result = await service.runPluginCommand(id: "text_tools/text", query: input)
            #expect(result.status == .completed)
            let rows = try PluginLauncherOutput.results(#require(result.output), commandID: "text_tools/text")
            #expect(rows.first?.title == expected)
            #expect(rows.first?.actions == [.copy(expected)])
        }
        let empty = await service.runPluginCommand(id: "text_tools/text", query: "")
        #expect(empty.output?["items"]?.arrayValue?.isEmpty == true)
        let decoded = await service.runPluginCommand(id: "text_tools/text", query: "%E4%BD%A0%E5%A5%BD")
        #expect(decoded.output?["items"]?.arrayValue?.last?["copy"] == "你好")
        try await service.plugins.rollback("text_tools")
        let restored = try #require(await service.plugins.installed().first)
        #expect(restored.manifest.apiVersion == 1)
        #expect(restored.commit == "legacy")
        #expect(restored.configuration["saved"] == "keep")
        #expect(restored.enabled)
        #expect(store.codableSetting("plugins.state.text_tools", as: JSONValue.self) == checkpoint)
        try await service.plugins.rollback("text_tools")
        #expect(await service.runPluginCommand(id: "text_tools/uuid", query: "").status == .completed)
    }
}
