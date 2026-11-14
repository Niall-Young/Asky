import Foundation
import Contracts
import LocalStore

public actor PluginManager {
    public static let officialRepositories = ["https://github.com/Niall-Young/asky-plugin-orca", "https://github.com/Niall-Young/asky-plugin-lark"]
    private let store: LocalStore
    private let runtime: PluginRuntimeConfiguration
    private let root: URL
    private var installationCommand: @Sendable (String, [String], URL?, Double) async throws -> PluginCommandResult = { executable, args, cwd, seconds in
        try await PluginProcess.command(executable, args, cwd: cwd, seconds: seconds)
    }
    // Test seam for deterministic clone/install failure and recovery coverage.
    func setInstallationCommand(_ command: @escaping @Sendable (String, [String], URL?, Double) async throws -> PluginCommandResult) { installationCommand = command }
    private var active: [String: Int] = [:]
    private var changing = false
    private var leases: [String: InstalledPlugin] = [:]
    private var records: [InstalledPlugin]
    public init(store: LocalStore, runtime: PluginRuntimeConfiguration = .init()) {
        self.store = store; self.runtime = runtime
        root = store.root.appending(path: "plugins")
        records = store.codableSetting("plugins.installed", as: [InstalledPlugin].self) ?? []
    }
    public func installed() -> [InstalledPlugin] { records }
    /// Read presentation resources through the same confined path rules as plugin code.
    public func iconData(for id: String) -> Data? {
        guard let plugin = records.first(where: { $0.id == id }), let path = plugin.manifest.icon,
              let file = try? PluginManifest.resource(path, at: root.appending(path: plugin.id)),
              let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 2 * 1024 * 1024,
              let data = try? Data(contentsOf: file), data.count <= 2 * 1024 * 1024 else { return nil }
        return data
    }
    private func save() { store.setCodableSetting("plugins.installed", records) }
    public static func repositoryURL(_ input: String) throws -> String {
        guard let u = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              u.scheme == "https", u.host?.lowercased() == "github.com", u.user == nil, u.password == nil,
              u.query == nil, u.fragment == nil, u.port == nil else { throw ToolError(.invalidArguments, CoreLocalization.text("请输入公开 GitHub HTTPS 仓库链接")) }
        let pieces = u.path.split(separator: "/").map(String.init)
        guard pieces.count == 2 else { throw ToolError(.invalidArguments, CoreLocalization.text("链接必须指向仓库根目录")) }
        let repo = pieces[1].hasSuffix(".git") ? String(pieces[1].dropLast(4)) : pieces[1]
        guard [pieces[0], repo].allSatisfy({ $0.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil && $0 != "." && $0 != ".." }) else {
            throw ToolError(.invalidArguments, CoreLocalization.text("GitHub 仓库链接无效"))
        }
        // GitHub names are case insensitive. Preserve canonical official spelling for display.
        let url = "https://github.com/\(pieces[0])/\(repo)"
        return officialRepositories.first { $0.lowercased() == url.lowercased() } ?? url
    }
    private func beginChange() throws {
        guard !changing else { throw ToolError(.conflict, CoreLocalization.text("已有插件安装或更新正在进行")) }
        changing = true
    }
    private func waitUntilIdle(_ id: String) async throws {
        while (active[id] ?? 0) > 0 { try await Task.sleep(for: .milliseconds(100)) }
    }
    private func checked(_ r: PluginCommandResult) throws -> String {
        guard r.exitCode == 0 else { throw ToolError(.adapterFailure, r.stderr.isEmpty ? r.stdout : r.stderr) }
        return r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func manifest(at directory: URL) throws -> PluginManifest {
        let data = try Data(contentsOf: directory.appending(path: "asky-plugin.json"))
        guard data.count <= 128 * 1024 else { throw ToolError(.invalidArguments, CoreLocalization.text("插件清单过大")) }
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        try manifest.validate(at: directory)
        return manifest
    }
    public func install(repository: String) async throws {
        let source = try Self.repositoryURL(repository)
        try beginChange(); defer { changing = false }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staging = root.appending(path: ".install-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        _ = try checked(await installationCommand("git", ["clone", "--depth", "1", "--", source + ".git", staging.path], nil, 120))
        let m = try manifest(at: staging)
        if let existing = records.first(where: { $0.id == m.id }) {
            guard existing.repository.lowercased() == source.lowercased() else { throw ToolError(.conflict, CoreLocalization.text("插件 ID 已被另一个仓库占用")) }
            try await waitUntilIdle(m.id)
        }
        let package = staging.appending(path: "package.json")
        if m.apiVersion == 1 && FileManager.default.fileExists(atPath: package.path) {
            let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: package))
            if !(value["dependencies"]?.objectValue ?? [:]).isEmpty {
                guard FileManager.default.fileExists(atPath: staging.appending(path: "package-lock.json").path) else { throw ToolError(.invalidArguments, CoreLocalization.text("插件依赖需要 package-lock.json")) }
                _ = try checked(await installationCommand("npm", ["ci", "--omit=dev", "--ignore-scripts", "--no-audit", "--no-fund"], staging, 120))
            }
        }
        // Revalidate after installing dependencies; do not execute plugin code during installation.
        try m.validate(at: staging)
        let commit = try checked(await installationCommand("git", ["rev-parse", "HEAD"], staging, 60))
        let destination = root.appending(path: m.id), previous = root.appending(path: m.id + ".previous")
        let old = records.first { $0.id == m.id }
        let hasPrevious = old != nil && FileManager.default.fileExists(atPath: destination.path)
        if hasPrevious {
            try? FileManager.default.removeItem(at: previous)
            try FileManager.default.moveItem(at: destination, to: previous)
        }
        do { try FileManager.default.moveItem(at: staging, to: destination) }
        catch { if hasPrevious { try? FileManager.default.moveItem(at: previous, to: destination) }; throw error }
        var config = old?.configuration ?? [:]
        for f in m.configuration ?? [] where config[f.key] == nil { config[f.key] = f.defaultValue }
        let installed = InstalledPlugin(manifest: m, repository: source, commit: commit, enabled: old?.enabled ?? false,
                                        configuration: config, previousCommit: hasPrevious ? old?.commit : nil)
        records.removeAll { $0.id == m.id }; records.append(installed); save()
    }
    public func rollback(_ id: String) async throws {
        try beginChange(); defer { changing = false }
        try await waitUntilIdle(id)
        guard let index = records.firstIndex(where: { $0.id == id }), let commit = records[index].previousCommit else { throw ToolError(.unavailable, CoreLocalization.text("没有可回退的版本")) }
        let current = root.appending(path: id), previous = root.appending(path: id + ".previous"), temporary = root.appending(path: ".rollback-" + UUID().uuidString)
        let m = try manifest(at: previous)
        guard m.id == id else { throw ToolError(.invalidArguments, CoreLocalization.text("旧版插件 ID 不匹配")) }
        try FileManager.default.moveItem(at: current, to: temporary)
        do { try FileManager.default.moveItem(at: previous, to: current) }
        catch { try? FileManager.default.moveItem(at: temporary, to: current); throw error }
        try FileManager.default.moveItem(at: temporary, to: previous)
        records[index].previousCommit = records[index].commit; records[index].commit = commit; records[index].manifest = m; save()
    }
    public func uninstall(_ id: String) async throws {
        try beginChange(); defer { changing = false }
        try await waitUntilIdle(id)
        let directory = root.appending(path: id)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try? FileManager.default.removeItem(at: root.appending(path: id + ".previous"))
        records.removeAll { $0.id == id }; save()
        // Handoff state and execution history deliberately remain in LocalStore.
    }
    public func setEnabled(_ id: String, _ enabled: Bool) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].enabled = enabled; save()
    }
    public func configure(_ id: String, values: [String: JSONValue]) throws {
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw ToolError(.targetNotFound, CoreLocalization.text("插件未安装")) }
        for field in records[index].manifest.configuration ?? [] {
            guard let value = values[field.key] else { continue }
            let valid: Bool
            switch field.type {
            case "boolean": valid = value.boolValue != nil
            case "enum": valid = (field.options ?? []).contains(value.stringValue ?? "")
            default: valid = value.stringValue != nil
            }
            guard valid else { throw ToolError(.invalidArguments, CoreLocalization.format("配置值类型错误：%@", String(describing: field.label))) }
        }
        records[index].configuration = values; save()
    }
    public func definitions() -> [ToolDefinition] {
        records.filter { $0.enabled && !$0.needsConfiguration }.flatMap { p in
            p.manifest.tools.filter { $0.agentVisible != false }.map { definition($0, plugin: p.id) }
        }
    }
    public func launcherCommands() -> [PluginLauncherCommand] {
        records.filter { $0.enabled && !$0.needsConfiguration }.flatMap { plugin in
            (plugin.manifest.commands ?? []).map {
                PluginLauncherCommand(pluginID: plugin.id, pluginName: plugin.manifest.name, command: $0)
            }
        }
    }
    private func definition(_ t: PluginTool, plugin: String) -> ToolDefinition {
        ToolDefinition(name: "plugin_\(plugin)__\(t.name)", summary: t.description, inputSchema: t.inputSchema,
                       source: .plugins, effect: t.effect, writeKind: t.effect == .write ? .handoff : nil,
                       confirmation: t.confirmation, externallyExposable: false)
    }
    public func adapter(named name: String, origin: CallerOrigin = .launcher) -> (any ToolAdapter)? {
        for p in records where p.enabled && !p.needsConfiguration {
            if let t = p.manifest.tools.first(where: { "plugin_\(p.id)__\($0.name)" == name }) {
                if case .agent = origin, t.agentVisible == false { return nil }
                return PluginAdapter(definition: definition(t, plugin: p.id), executionTimeout: .seconds(t.timeoutSeconds ?? 20),
                                     pluginID: p.id, pluginName: p.manifest.name, toolName: t.name, manager: self)
            }
        }
        return nil
    }
    public func guidance() -> [String] {
        records.filter { $0.enabled && !$0.needsConfiguration }.compactMap { p in
            guard let path = p.manifest.instructions,
                  let file = try? PluginManifest.resource(path, at: root.appending(path: p.id)),
                  let data = try? Data(contentsOf: file), data.count <= 64 * 1024 else { return nil }
            return "插件 \(p.id)：\n" + String(decoding: data, as: UTF8.self)
        }
    }
    func acquire(_ id: String, requestID: String) async throws {
        while (active[id] ?? 0) > 0 {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(50))
        }
        guard !changing, let p = records.first(where: { $0.id == id }), p.enabled && !p.needsConfiguration else {
            throw ToolError(.sourceDisabled, CoreLocalization.text("插件已停用或正在更新"))
        }
        active[id, default: 0] += 1; leases[requestID] = p
    }
    func release(_ id: String, requestID: String) {
        if leases.removeValue(forKey: requestID) != nil { active[id, default: 1] -= 1 }
    }
    func invoke(pluginID: String, tool: String, arguments: JSONValue, requestID: String, readback: Bool, output: JSONValue?) async throws -> JSONValue {
        guard let p = leases[requestID], p.id == pluginID,
              readback || records.first(where: { $0.id == pluginID })?.enabled == true else { throw ToolError(.sourceDisabled, CoreLocalization.text("插件已停用或正在更新")) }
        let directory = root.appending(path: pluginID)
        let entry = try PluginManifest.resource(p.manifest.entry, at: directory)
        let stateKey = "plugins.state.\(pluginID)"
        let currentState = store.codableSetting(stateKey, as: JSONValue.self) ?? [:]
        let payload: JSONValue = ["entry": .string(entry.path), "tool": .string(tool), "arguments": arguments,
                                  "requestID": .string(requestID), "configuration": .object(p.configuration),
                                  "state": currentState, "inputSchema": p.manifest.tools.first(where: { $0.name == tool })?.inputSchema ?? [:], "readback": .bool(readback), "output": output ?? .null]
        if !readback { try PluginArguments.validate(arguments, schema: payload["inputSchema"] ?? [:]) }
        let executable: String, workerArguments: [String]
        if p.manifest.apiVersion == 2 {
            executable = entry.path; workerArguments = []
        } else {
            guard let node = runtime.nodePath ?? (try? PluginProcess.executable("node")), let runner = runtime.runnerPath else {
                throw ToolError(.unavailable, CoreLocalization.text("此旧版 JavaScript 插件需要本机 Node.js 22+；请安装 Node 或更新为原生 API v2 插件。"))
            }
            executable = node; workerArguments = [runner]
        }
        return try await PluginWorker.run(executable: executable, arguments: workerArguments, directory: directory, payload: payload,
                                         saveState: { [store] value in store.setCodableSetting(stateKey, value) })
    }
}
private struct PluginAdapter: ToolAdapter {
    let definition: ToolDefinition
    let executionTimeout: Duration?
    var deduplicatesArguments: Bool { false }
    let pluginID: String
    let pluginName: String
    let toolName: String
    let manager: PluginManager
    func preview(_ arguments: JSONValue) async throws -> ConfirmationPreview {
        PluginConfirmation.preview(pluginName: pluginName, arguments: arguments)
    }
    func prepare(requestID: String) async throws { try await manager.acquire(pluginID, requestID: requestID) }
    func finish(requestID: String) async { await manager.release(pluginID, requestID: requestID) }
    func execute(_ arguments: JSONValue) async throws -> AdapterOutput {
        let id = UUID().uuidString
        try await prepare(requestID: id)
        do { let output = try await execute(arguments, requestID: id); await finish(requestID: id); return output }
        catch { await finish(requestID: id); throw error }
    }
    func execute(_ arguments: JSONValue, requestID: String) async throws -> AdapterOutput {
        AdapterOutput(output: try await manager.invoke(pluginID: pluginID, tool: toolName, arguments: arguments, requestID: requestID, readback: false, output: nil))
    }
    func readback(_ arguments: JSONValue, output: AdapterOutput?, requestID: String) async -> JSONValue? {
        let manager = manager, pluginID = pluginID, toolName = toolName
        let value = try? await withTimeout(.seconds(20)) {
            try await manager.invoke(pluginID: pluginID, tool: toolName, arguments: arguments, requestID: requestID, readback: true, output: output?.output)
        }
        return value == .null ? nil : value
    }
}
