import AppKit
import SwiftUI
import Contracts
import LocalStore
import ToolService

@main @MainActor
private enum PluginSettingsRegression {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw NSError(domain: "PluginSettings", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    static func switches(_ window: NSWindow) -> [NSSwitch] {
        descendants(window.contentView!).compactMap { $0 as? NSSwitch }
    }
    static func until(line: Int = #line, _ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: "PluginSettings", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out at line \(line)"])
    }
    static func fixture(_ id: String, name: String, functional: Bool, agentVisible: Bool,
                        repository: String? = nil) throws -> InstalledPlugin {
        let tool: JSONValue = ["name": "run", "description": .string("\(name) actions"), "effect": "read", "confirmation": "never", "agentVisible": .bool(agentVisible), "inputSchema": ["type": "object", "properties": [:]]]
        var manifest: [String: JSONValue] = ["id": .string(id), "name": .string(name), "version": "1.0.0", "apiVersion": 1, "entry": "index.mjs", "tools": .array([tool])]
        if functional { manifest["commands"] = [["name": "format", "title": "Format Text", "keyword": "fmt", "tool": "run", "mode": "action"]] }
        let record: JSONValue = ["manifest": .object(manifest), "repository": .string(repository ?? "https://github.com/example/" + id), "commit": "fixture", "enabled": .bool(id != "hybrid"), "configuration": [:]]
        return try JSONDecoder().decode(InstalledPlugin.self, from: record.canonicalData())
    }
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .leftMouseDown, .leftMouseUp, .mouseMoved]) { _ in nil }
        defer { if let monitor { NSEvent.removeMonitor(monitor) } }
        Task { @MainActor in
            do {
                try await check()
                print("Plugin settings tabs, mixed capabilities, shared enablement, global search, empty state and native snapshots passed")
                exit(0)
            } catch {
                fputs("Plugin settings regression failed: \(error)\n", stderr)
                exit(1)
            }
        }
        NSApp.run()
    }
    static func check() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-plugin-settings-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalStore(root: root)
        let ai = try fixture("agent_sample", name: "Agent Sample", functional: false, agentVisible: true)
        let function = try fixture("text_tools", name: "Text Tools", functional: true, agentVisible: false)
        let hybrid = try fixture("hybrid", name: "Hybrid", functional: true, agentVisible: true)
        try require(PluginSettingsCategory.ai.includes(ai.manifest) && !PluginSettingsCategory.function.includes(ai.manifest), "legacy Agent plugin must remain in AI category")
        try require(!PluginSettingsCategory.ai.includes(function.manifest) && PluginSettingsCategory.function.includes(function.manifest), "hidden tools with commands must be functional only")
        try require(PluginSettingsCategory.allCases.allSatisfy { $0.includes(hybrid.manifest) }, "mixed plugin must belong to both categories")
        try require(PluginSettingsCategory.matches(function, query: "FMT") && PluginSettingsCategory.matches(function, query: "Format Text"), "commands and keywords must be searchable")
        store.setCodableSetting("plugins.installed", [ai, function, hybrid])
        let app = try AppModel(root: root)
        app.settingsTab = SettingsPage.plugins.rawValue
        let window = SettingsWindow.make(app: app)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await until { switches(window).count == 2 }
        guard let search = descendants(window.contentView!).compactMap({ $0 as? NSTextField }).first(where: { $0.placeholderString == NSLocalizedString("搜索插件或命令", comment: "") }) else {
            throw NSError(domain: "PluginSettings", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing shared search or tabs"])
        }
        guard let tabs = descendants(window.contentView!).compactMap({ $0 as? NSSegmentedControl })
            .first(where: { $0.accessibilityIdentifier() == "plugin-tabs" }) else {
            throw NSError(domain: "PluginSettings", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing native plugin tabs"])
        }
        try require(tabs.segmentCount == 2, "plugin page must expose exactly two category tabs")
        func select(_ index: Int) {
            tabs.selectedSegment = index
            _ = tabs.sendAction(tabs.action, to: tabs.target)
        }
        func capture(_ suffix: String, in target: NSWindow? = nil) throws {
            let view = (target ?? window).contentView!
            view.layoutSubtreeIfNeeded()
            let language = Bundle.main.preferredLocalizations.first ?? "unknown"
            let capture = Process()
            capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String((target ?? window).windowNumber), "build/plugin-tabs-\(language)-\(suffix).png"]
            try capture.run()
            capture.waitUntilExit()
            try require(capture.terminationStatus == 0, "failed to capture native plugin controls")
        }
        for appearance in ["light", "dark"] {
            app.preferences.appearance = appearance
            select(0)
            try await until { switches(window).count == 2 }
            try require(switches(window).filter { $0.state == .on }.count == 1 && switches(window).filter { $0.state == .off }.count == 1, "AI tab must show enabled Agent plugin and disabled hybrid only")
            try await Task.sleep(for: .milliseconds(250))
            try capture("ai-" + appearance)
            select(1)
            try await until { switches(window).count == 2 }
            try require(switches(window).filter { $0.state == .on }.count == 1 && switches(window).filter { $0.state == .off }.count == 1, "functional tab must show enabled text tools and disabled hybrid only")
            try await Task.sleep(for: .milliseconds(250))
            try capture("function-" + appearance)
        }
        let toggle = switches(window).first { $0.state == .off }!
        toggle.state = .on
        NSApp.sendAction(toggle.action!, to: toggle.target, from: toggle)
        for _ in 0..<100 {
            if await app.tools.plugins.installed().first(where: { $0.id == "hybrid" })?.enabled == true { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        try require(await app.tools.plugins.installed().first(where: { $0.id == "hybrid" })?.enabled == true, "switch must persist enablement")
        select(0)
        try await until { switches(window).count == 2 && switches(window).allSatisfy { $0.state == .on } }
        window.makeFirstResponder(search)
        guard let editor = search.currentEditor() else { fatalError("missing search editor") }
        editor.selectAll(nil)
        editor.insertText("Hybrid")
        try await Task.sleep(for: .milliseconds(150))
        try await until { switches(window).count == 2 }
        try require(switches(window).allSatisfy { $0.state == .on }, "hybrid must share the enabled state across search groups")
        try capture("global-search")
        editor.selectAll(nil)
        editor.insertText("no-plugin-matches-84729")
        try await Task.sleep(for: .milliseconds(150))
        try await until { switches(window).isEmpty }
        try capture("empty")
        editor.selectAll(nil)
        editor.insertText("fmt")
        try await Task.sleep(for: .milliseconds(150))
        try await until { switches(window).count == 3 }
        editor.selectAll(nil)
        editor.insertText("")
        try await Task.sleep(for: .milliseconds(150))
        try await until { switches(window).count == 2 }
        try require(tabs.selectedSegment == 0 && switches(window).count == 2,
                    "clearing search must restore the selected tab")
        let buttons = descendants(window.contentView!).compactMap { $0 as? NSButton }
        try require(buttons.filter { $0.title == NSLocalizedString("安装", comment: "") }.count == 2,
                    "AI catalog must offer one install button per uninstalled official plugin")
        guard let add = buttons.first(where: { $0.title == NSLocalizedString("添加", comment: "") }) else {
            throw NSError(domain: "PluginSettings", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing add button"])
        }
        add.performClick(nil)
        // SwiftUI renders a styled prompt as an attributed placeholder, not `placeholderString`.
        let repositoryField = { descendants(window.contentView!).compactMap { $0 as? NSTextField }.first {
            ($0.placeholderString ?? $0.placeholderAttributedString?.string)
                == NSLocalizedString("GitHub 仓库链接", comment: "")
        } }
        try await until { repositoryField() != nil }
        // The in-window dialog is glass; cacheDisplay does not composite it, so capture the real window.
        let language = Bundle.main.preferredLocalizations.first ?? "unknown"
        for appearance in ["light", "dark"] {
            app.preferences.appearance = appearance
            try await Task.sleep(for: .milliseconds(400))
            let shot = Process()
            shot.executableURL = URL(filePath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-l", String(window.windowNumber), "build/plugin-tabs-\(language)-add-dialog-\(appearance).png"]
            try shot.run()
            shot.waitUntilExit()
            try require(shot.terminationStatus == 0, "native add-dialog capture must succeed")
        }
        if let cancel = descendants(window.contentView!).compactMap({ $0 as? NSButton }).first(where: { $0.title == NSLocalizedString("取消", comment: "") }) {
            cancel.performClick(nil)
        }
        try await until { repositoryField() == nil }
        window.close()
        let official = try fixture("official_orca", name: "Orca", functional: false, agentVisible: true,
                                   repository: PluginManager.officialRepositories[0])
        store.setCodableSetting("plugins.installed", [ai, official])
        let merged = try AppModel(root: root)
        merged.settingsTab = SettingsPage.plugins.rawValue
        let mergedWindow = SettingsWindow.make(app: merged)
        mergedWindow.isReleasedWhenClosed = false
        mergedWindow.makeKeyAndOrderFront(nil)
        try await until { switches(mergedWindow).count == 2 }
        let mergedButtons = descendants(mergedWindow.contentView!).compactMap { $0 as? NSButton }
        try require(mergedButtons.filter { $0.title == NSLocalizedString("安装", comment: "") }.count == 1,
                    "installed official plugin must replace its catalog install button")
        try capture("official-installed", in: mergedWindow)
        mergedWindow.close()
        store.setCodableSetting("plugins.installed", [ai])
        let onlyAI = try AppModel(root: root)
        onlyAI.settingsTab = SettingsPage.plugins.rawValue
        let emptyWindow = SettingsWindow.make(app: onlyAI)
        emptyWindow.isReleasedWhenClosed = false
        emptyWindow.makeKeyAndOrderFront(nil)
        defer { emptyWindow.close() }
        try await until { switches(emptyWindow).count == 1 }
        guard let emptyTabs = descendants(emptyWindow.contentView!).compactMap({ $0 as? NSSegmentedControl })
            .first(where: { $0.accessibilityIdentifier() == "plugin-tabs" }) else {
            throw NSError(domain: "PluginSettings", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing native plugin tabs"])
        }
        emptyTabs.selectedSegment = 1
        _ = emptyTabs.sendAction(emptyTabs.action, to: emptyTabs.target)
        try await until { switches(emptyWindow).isEmpty }
        try capture("function-empty", in: emptyWindow)
        try require(descendants(emptyWindow.contentView!).compactMap { $0 as? NSButton }.filter { $0.title == NSLocalizedString("添加", comment: "") }.count == 1,
                    "empty functional tab must retain the single add button")

    }
}
