import Foundation
import Testing
import Contracts
import LocalStore
@testable import ToolService

@Suite(.timeLimit(.minutes(1))) struct NativePluginTests {
    @Test func nativeBinaryInstallsAndRunsWithoutJavaScriptRuntime() async throws {
        let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        var repository = URL(filePath: #filePath)
        for _ in 0..<5 { repository.deleteLastPathComponent() }
        let source = repository.appending(path: "examples/plugins/native-echo")
        let binary = temporary.appending(path: "native-echo")
        let compiler = try await PluginProcess.command("/usr/bin/xcrun", ["swiftc", "-O", source.appending(path: "main.swift").path, "-o", binary.path], seconds: 40)
        #expect(compiler.exitCode == 0)
        let store = try LocalStore(root: temporary.appending(path: "data"))
        // No Node or JS runner configured.
        let service = ToolService(store: store, policy: { PolicySnapshot(enabledSources: [.plugins]) }, presenter: { _ in .rejected })
        await service.plugins.setInstallationCommand { _, args, _, _ in
            if args.first == "clone" {
                let destination = URL(filePath: args.last!)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source.appending(path: "asky-plugin.json"), to: destination.appending(path: "asky-plugin.json"))
                try FileManager.default.copyItem(at: binary, to: destination.appending(path: "native-echo"))
            }
            return PluginCommandResult(stdout: "native-commit", stderr: "", exitCode: 0)
        }
        try await service.plugins.install(repository: "https://github.com/example/native")
        await service.plugins.setEnabled("native_echo", true)
        let result = await service.submit(ActionRequest(tool: "plugin_native_echo__echo", arguments: ["text": "中文 `literal` $(literal)"], origin: .agent(sessionID: "s"), intent: .explicitRequest))
        #expect(result.status == .completed)
        #expect(result.output?["text"] == "中文 `literal` $(literal)")
        let invalid = await service.submit(ActionRequest(tool: "plugin_native_echo__echo", arguments: ["text": 1], origin: .launcher, intent: .explicitRequest))
        #expect(invalid.status == .failed)
        #expect(invalid.error?.code == .invalidArguments)
        #expect(await service.plugins.launcherCommands().count == 1)
    }
}
