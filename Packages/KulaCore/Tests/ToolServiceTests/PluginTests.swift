import Foundation
import Testing
import Contracts
import LocalStore
@testable import ToolService

private func fixture(_ version: String = "1", dependency: Bool = false) -> String {
    """
    {"id":"example","name":"Example","version":"\(version)","apiVersion":1,"entry":"index.mjs","instructions":"SKILL.md",
    "configuration":[{"key":"choice","label":"Choice","type":"enum","options":["one","two"],"required":true,"defaultValue":"one"}],
    "tools":[{"name":"run","description":"Run","effect":"write","confirmation":"explicitDirectOtherwiseConfirm","timeoutSeconds":20,
    "inputSchema":{"type":"object","required":["text"],"additionalProperties":false,"properties":{"text":{"type":"string","minLength":1}}}}]}
    """
}
private func prepareFixture(_ url: URL, version: String = "1", dependency: Bool = false) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try fixture(version).write(to: url.appending(path: "asky-plugin.json"), atomically: true, encoding: .utf8)
    try "Use example tools.".write(to: url.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
    try """
    export default {tools:{run:{async execute(args,ctx){
    console.log('diagnostic only');
    const r=await ctx.exec('/usr/bin/printf',['%s',args.text]);
    await ctx.saveState({[ctx.requestID]:r.stdout});return {text:r.stdout};
    },async readback(args,ctx){return ctx.state[ctx.requestID]===args.text?{text:ctx.state[ctx.requestID]}:null;}}}};
    """.write(to: url.appending(path: "index.mjs"), atomically: true, encoding: .utf8)
    if dependency { try "{\"dependencies\":{\"example\":\"1\"}}".write(to: url.appending(path: "package.json"), atomically: true, encoding: .utf8) }
}
private func installer(version: String = "1", dependency: Bool = false, failure: Bool = false) -> @Sendable (String, [String], URL?, Double) async throws -> PluginCommandResult {
    { _, args, _, _ in
        if failure { throw ToolError(.adapterFailure, "simulated download failure") }
        if args.first == "clone" { try prepareFixture(URL(filePath: args.last!), version: version, dependency: dependency) }
        return PluginCommandResult(stdout: "commit-\(version)", stderr: "", exitCode: 0)
    }
}
@Suite struct PluginTests {
    @Test func repositoryAndManifestValidation() throws {
        #expect(try PluginManager.repositoryURL("https://github.com/niall-young/asky-plugin-orca.git/") == PluginManager.officialRepositories[0])
        #expect(try PluginManager.repositoryURL("https://github.com/niall-young/asky-plugin-lark.git") == "https://github.com/Niall-Young/asky-plugin-lark")
        for url in ["file:///tmp/repo", "https://user:token@github.com/a/b", "https://github.com/a/b/tree/main", "https://github.com/a/b?token=x"] {
            #expect(throws: Error.self) { try PluginManager.repositoryURL(url) }
        }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try prepareFixture(root)
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(fixture().utf8))
        try manifest.validate(at: root)
        #expect(throws: Error.self) { try PluginManifest.resource("../escape", at: root) }
    }
    @Test func installUpdateFailureRollbackDisableAndUninstall() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalStore(root: root), manager = PluginManager(store: store)
        #expect(await manager.installed().isEmpty)
        await manager.setInstallationCommand(installer())
        try await manager.install(repository: "https://github.com/example/plugin")
        #expect(await manager.installed().first?.enabled == false)
        #expect(await manager.definitions().isEmpty)
        #expect(await manager.guidance().isEmpty)
        #expect(await manager.adapter(named: "plugin_example__run") == nil)
        #expect(await PluginManager(store: store).installed().first?.enabled == false)
        await manager.setEnabled("example", true)
        #expect(await manager.definitions().count == 1)
        #expect(await manager.guidance().first?.contains("example") == true)
        await manager.setInstallationCommand(installer(version: "2"))
        try await manager.install(repository: "https://github.com/example/plugin")
        #expect(await manager.installed().first?.commit == "commit-2")
        #expect(await manager.installed().first?.enabled == true)
        await manager.setInstallationCommand(installer(failure: true))
        await #expect(throws: Error.self) { try await manager.install(repository: "https://github.com/example/plugin") }
        #expect(await manager.installed().first?.commit == "commit-2")
        try await manager.rollback("example")
        #expect(await manager.installed().first?.commit == "commit-1")
        await manager.setInstallationCommand(installer())
        await #expect(throws: Error.self) { try await manager.install(repository: "https://github.com/other/plugin") }
        await manager.setEnabled("example", false)
        #expect(await manager.definitions().isEmpty)
        #expect(await manager.adapter(named: "plugin_example__run") == nil)
        await #expect(throws: Error.self) { try await manager.configure("example", values: ["choice": "invalid"]) }
        store.setCodableSetting("plugins.state.example", ["kept": true] as JSONValue)
        try await manager.uninstall("example")
        #expect(await manager.installed().isEmpty)
        #expect(store.codableSetting("plugins.state.example", as: JSONValue.self)?["kept"] == true)
    }
    @Test func missingLockfileLeavesNoInstallation() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = PluginManager(store: try LocalStore(root: root))
        await manager.setInstallationCommand(installer(dependency: true))
        await #expect(throws: Error.self) { try await manager.install(repository: "https://github.com/example/plugin") }
        #expect(await manager.installed().isEmpty)
    }
    @Test func nativeWorkerRoundTripAndPolicy() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var repository = URL(filePath: #filePath)
        for _ in 0..<5 { repository.deleteLastPathComponent() }
        let runner = repository.appending(path: "PluginSupport/plugin-runner.mjs")
        let node = try PluginProcess.executable("node")
        #expect(FileManager.default.fileExists(atPath: runner.path))
        let store = try LocalStore(root: root)
        let service = ToolService(store: store, policy: { PolicySnapshot(enabledSources: [.plugins]) },
            presenter: { _ in Issue.record("Explicit plugin requests should not confirm"); return .rejected },
            pluginRuntime: .init(nodePath: node, runnerPath: runner.path))
        await service.plugins.setInstallationCommand(installer())
        try await service.plugins.install(repository: "https://github.com/example/plugin")
        await service.plugins.setEnabled("example", true)
        let text = "line one\n\"quotes\" `literal` $(literal) 中文"
        let request = ActionRequest(requestID: "stable-request", tool: "plugin_example__run", arguments: ["text": .string(text)], origin: .agent(sessionID: "s"), intent: .explicitRequest)
        let result = await service.submit(request)
        #expect(result.status == .completed)
        #expect(result.output?["text"] == .string(text))
        #expect(result.readback?["text"] == .string(text))
        #expect(await service.submit(request) == result)
        let suggestion = await service.submit(ActionRequest(tool: request.tool, arguments: request.arguments, origin: request.origin, intent: .aiSuggested))
        #expect(suggestion.status == .suggestion)
        #expect(await service.definitions(for: .mcp(instanceID: "unknown")).isEmpty)
        await service.plugins.setEnabled("example", false)
        let disabled = await service.submit(ActionRequest(tool: request.tool, arguments: request.arguments, origin: request.origin, intent: .explicitRequest))
        #expect(disabled.status == .failed || disabled.status == .rejected)
    }
    @Test func processCancellationAndOutputLimit() async throws {
        let start = ContinuousClock.now
        let task = Task { try await PluginProcess.command("/bin/sleep", ["30"]) }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        await #expect(throws: Error.self) { _ = try await task.value }
        #expect(start.duration(to: .now) < .seconds(3))
        await #expect(throws: ToolError.self) { _ = try await PluginProcess.command("/usr/bin/yes", [], seconds: 3) }
        let parent = PluginProcessControl()
        #expect(throws: ToolError.self) {
            try parent.withChild { child in
                _ = try PluginProcess.commandSync("/bin/sleep", ["10"], cwd: nil, seconds: 0.05, control: child)
            }
        }
        try parent.check()
    }
    @Test func updateWaitsForExecutionLeaseAndDisableBlocksNewCalls() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = PluginManager(store: try LocalStore(root: root))
        await manager.setInstallationCommand(installer())
        try await manager.install(repository: "https://github.com/example/plugin")
        await manager.setEnabled("example", true)
        try await manager.acquire("example", requestID: "lease")
        await manager.setInstallationCommand(installer(version: "2"))
        let update = Task { try await manager.install(repository: "https://github.com/example/plugin") }
        try await Task.sleep(for: .milliseconds(150))
        #expect(await manager.installed().first?.commit == "commit-1")
        await manager.setEnabled("example", false)
        #expect(await manager.definitions().isEmpty)
        await manager.release("example", requestID: "lease")
        try await update.value
        #expect(await manager.installed().first?.commit == "commit-2")
        #expect(await manager.installed().first?.enabled == false)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ASKY_ORCA_LIVE_TEST"] == "1"))
    func liveOrcaCLISkillAndProjectDiscovery() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "asky-orca-discovery-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var repository = URL(filePath: #filePath)
        for _ in 0..<5 { repository.deleteLastPathComponent() }
        let service = ToolService(store: try LocalStore(root: root),
            policy: { PolicySnapshot(enabledSources: [.plugins]) }, presenter: { _ in .rejected },
            pluginRuntime: .init(nodePath: try PluginProcess.executable("node"), runnerPath: repository.appending(path: "PluginSupport/plugin-runner.mjs").path))
        // Validate optional unpublished source through ToolService and its worker,
        // without changing the user's installed plugin or sending Agent prompts.
        if let source = ProcessInfo.processInfo.environment["ASKY_ORCA_PLUGIN_SOURCE"] {
            await service.plugins.setInstallationCommand { _, args, _, _ in
                if args.first == "clone" {
                    try FileManager.default.copyItem(at: URL(filePath: source), to: URL(filePath: args.last!))
                }
                return PluginCommandResult(stdout: "local-validation", stderr: "", exitCode: 0)
            }
        }
        try await service.plugins.install(repository: PluginManager.officialRepositories[0])
        await service.plugins.setEnabled("orca", true)
        let guide = await service.submit(ActionRequest(tool: "plugin_orca__cli_query",
            arguments: ["arguments": ["skills", "get", "orca-cli"]],
            origin: .agent(sessionID: "live-discovery"), intent: .explicitRequest))
        #expect(guide.status == .completed)
        #expect(guide.output?["stdout"]?.stringValue?.contains("repo list") == true)
        let inventory = await service.submit(ActionRequest(tool: "plugin_orca__cli_query",
            arguments: ["arguments": ["repo", "list"]],
            origin: .agent(sessionID: "live-discovery"), intent: .explicitRequest))
        #expect(inventory.status == .completed)
        let repos = try #require(inventory.output?["result"]?["repos"]?.arrayValue)
        #expect(repos.allSatisfy { $0["id"]?.stringValue != nil && $0["path"]?.stringValue != nil })
        print("Live Orca discovery: \(repos.count) projects; AGUI found: \(repos.contains { $0["displayName"]?.stringValue == "AGUI project" })")
    }

}
