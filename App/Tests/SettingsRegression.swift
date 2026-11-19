import AppKit
import SwiftUI
import Adapters
import DirectActions
import LocalStore
import Router
import ToolService
import Contracts
import Search

private struct TabCommandProvider: SearchProvider {
    let source: SearchSource
    var count = 1
    func search(_ query: String, limit: Int) async -> [SearchResult] {
        (0..<min(count, limit)).map { index in
            SearchResult(source: source, target: TargetRef(kind: "fixture", identifier: "\(query)-\(index)"),
                         title: "\(query) \(index)", actions: [], score: 1)
        }
    }
}

@main @MainActor
enum SettingsRegression {
    static func main() {
        let application = NSApplication.shared
        let preview = CommandLine.arguments.contains("--preview")
        application.setActivationPolicy(preview ? .regular : .accessory)
        Task { @MainActor in
            do {
                try await assertModelCheckFailures()
                if CommandLine.arguments.contains("--model-check-only") {
                    print("Model capability HTTP diagnostics regression passed")
                    exit(0)
                }
                let root = FileManager.default.temporaryDirectory.appending(path: "Asky-settings-\(UUID())")
                let legacyStore = try LocalStore(root: root)
                if CommandLine.arguments.contains("--plugin-icons") {
                    var samples: [InstalledPlugin] = []
                    for (id, name, icon) in [("custom", "Custom artwork", "icon.png"), ("fallback", "Missing artwork", "missing.png")] {
                        let json = """
                        {"id":"\(id)","name":"\(name)","version":"1","apiVersion":1,"entry":"index.mjs","icon":"\(icon)","tools":[]}
                        """
                        let record = """
                        {"manifest":\(json),"repository":"https://github.com/example/\(id)","commit":"fixture","enabled":false,"configuration":{}}
                        """
                        samples.append(try JSONDecoder().decode(InstalledPlugin.self, from: Data(record.utf8)))
                        let directory = root.appending(path: "plugins/\(id)")
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        if id == "custom" {
                            guard let png = NSImage(named: "Bookmark")?.tiffRepresentation else { fatalError("missing custom icon fixture") }
                            try png.write(to: directory.appending(path: icon))
                        }
                    }
                    legacyStore.setCodableSetting("plugins.installed", samples)
                }
                // Retired custom-website data must never override the built-in registry.
                legacyStore.setCodableSetting("keywords", ["commands": [
                    ["keyword": "go", "name": "Custom", "urlTemplate": "https://example.com"],
                ]])
                let model = try AppModel(root: root)
                if CommandLine.arguments.contains("--command-reset") {
                    try await assertCommandReset(model, root: root)
                    exit(0)
                }
                if CommandLine.arguments.contains("--conversation-retention") {
                    defer { try? FileManager.default.removeItem(at: root) }
                    precondition(model.settings.conversationRetention == .thirtyDays)
                    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(model.settings)) as! [String: Any]
                    legacy.removeValue(forKey: "conversationRetentionDays")
                    legacy["clipboardEnabled"] = false
                    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
                    precondition(decoded.conversationRetention == .thirtyDays && !decoded.clipboardEnabled)
                    var invalid = decoded
                    invalid.conversationRetentionDays = 999
                    precondition(invalid.conversationRetention == .thirtyDays)
                    try model.memory.ensureExists()
                    let memoryBefore = try Data(contentsOf: model.memory.indexURL)
                    let chat = AgentModel(app: model)
                    model.settingsTab = SettingsPage.data.rawValue
                    let window = SettingsWindow.make(app: model)
                    let presentation = WindowPresentation()
                    presentation.show(window)
                    let labels = ["7 天", "30 天", "90 天", "永久"].map { NSLocalizedString($0, comment: "") }
                    func popup(in view: NSView) -> NSPopUpButton? {
                        if let button = view as? NSPopUpButton, button.itemTitles == labels { return button }
                        return view.subviews.lazy.compactMap { popup(in: $0) }.first
                    }
                    try await Task.sleep(for: .milliseconds(350))
                    let choice = popup(in: window.contentView!)!
                    precondition(choice.indexOfSelectedItem == 1)
                    choice.selectItem(at: 2)
                    _ = choice.sendAction(choice.action, to: choice.target)
                    try await Task.sleep(for: .milliseconds(100))
                    precondition(model.settings.conversationRetention == .ninetyDays)
                    let old = Date().addingTimeInterval(-40 * 86400)
                    let cid = try ConversationStore(model.store).create(title: "Retained conversation", now: old)
                    try ConversationStore(model.store).append(conversationID: cid, role: "user", text: "历史正文", now: old)
                    chat.open(cid)
                    precondition(!chat.items.isEmpty)
                    await model.maintainConversationHistory()
                    precondition(ConversationStore(model.store).list(limit: 10).contains { $0.id == cid })
                    choice.selectItem(at: 0)
                    _ = choice.sendAction(choice.action, to: choice.target)
                    try await Task.sleep(for: .milliseconds(150))
                    await model.maintainConversationHistory()
                    precondition(model.settings.conversationRetention == .sevenDays)
                    precondition(ConversationStore(model.store).list(limit: 10).isEmpty)
                    precondition(chat.conversationID == nil && chat.items.isEmpty)
                    let manualID = try ConversationStore(model.store).create(title: "Manual deletion")
                    chat.open(manualID)
                    chat.delete(manualID)
                    try await Task.sleep(for: .milliseconds(150))
                    precondition(chat.conversationID == nil && ConversationStore(model.store).list(limit: 10).isEmpty)
                    let memoryAfter = try Data(contentsOf: model.memory.indexURL)
                    precondition(memoryAfter == memoryBefore)
                    let reopened = try AppModel(root: root)
                    precondition(reopened.settings.conversationRetention == .sevenDays)
                    for appearance in ["light", "dark"] {
                        model.preferences.appearance = appearance
                        try await Task.sleep(for: .milliseconds(300))
                        choice.scrollToVisible(choice.bounds)
                        window.contentView?.layoutSubtreeIfNeeded()
                        let view = window.contentView!
                        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("capture") }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/settings-conversation-history-\(appearance).png"))
                    }
                    choice.selectItem(at: 3)
                    _ = choice.sendAction(choice.action, to: choice.target)
                    try await Task.sleep(for: .milliseconds(100))
                    precondition(model.settings.conversationRetention == .forever)
                    print("Conversation retention settings: native choices, legacy defaults, persistence, immediate cleanup and unchanged memory passed")
                    window.close()
                    exit(0)
                }
                if CommandLine.arguments.contains("--settings-chrome") {
                    defer { try? FileManager.default.removeItem(at: root) }
                    model.settingsTab = "keywords"
                    let window = SettingsWindow.make(app: model)
                    window.isReleasedWhenClosed = false
                    let presentation = WindowPresentation()
                    for appearance in ["light", "dark"] {
                        model.preferences.appearance = appearance
                        presentation.show(window)
                        try await Task.sleep(for: .milliseconds(400))
                        try await assertSettingsChrome(window, appearance: appearance)
                    }
                    print("Settings chrome: native 28pt buttons, input alignment and key-window transitions passed")
                    exit(0)
                }
                if CommandLine.arguments.contains("--command-layout") {
                    defer { try? FileManager.default.removeItem(at: root) }
                    model.settingsTab = "keywords"
                    let window = SettingsWindow.make(app: model)
                    window.makeKeyAndOrderFront(nil)
                    try await Task.sleep(for: .milliseconds(400))
                    try await assertCommandTabsAndGlobalSearch(window, model: model)
                    exit(0)
                }
                if CommandLine.arguments.contains("--settings-focus") {
                    defer { try? FileManager.default.removeItem(at: root) }
                    model.settingsTab = "keywords"
                    let window = SettingsWindow.make(app: model)
                    window.makeKeyAndOrderFront(nil)
                    for appearance in ["light", "dark"] {
                        model.preferences.appearance = appearance
                        try await Task.sleep(for: .milliseconds(400))
                        window.contentView?.layoutSubtreeIfNeeded()
                        assertSettingsClickOutsideEndsEditing(window)
                        guard let view = window.contentView,
                              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                            fatalError("missing settings focus view")
                        }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        try bitmap.representation(using: .png, properties: [:])!.write(
                            to: URL(filePath: "build/settings-focus-\(appearance).png"))
                    }
                    exit(0)
                }
                if CommandLine.arguments.contains("--clipboard-retention") {
                    defer { try? FileManager.default.removeItem(at: root) }
                    precondition(model.settings.clipboardRetention == .threeDays)
                    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(model.settings)) as! [String: Any]
                    legacy.removeValue(forKey: "clipboardRetentionHours")
                    legacy["clipboardEnabled"] = false
                    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
                    precondition(decoded.clipboardRetention == .threeDays && !decoded.clipboardEnabled)
                    var invalid = decoded
                    invalid.clipboardRetentionHours = 99
                    precondition(invalid.clipboardRetention == .threeDays)
                    model.settingsTab = SettingsPage.clipboard.rawValue
                    let window = SettingsWindow.make(app: model)
                    let presentation = WindowPresentation()
                    presentation.show(window)
                    func retentionPopup(in view: NSView) -> NSPopUpButton? {
                        if let button = view as? NSPopUpButton, button.numberOfItems == 5 { return button }
                        return view.subviews.lazy.compactMap { retentionPopup(in: $0) }.first
                    }
                    for appearance in ["light", "dark"] {
                        model.preferences.appearance = appearance
                        try await Task.sleep(for: .milliseconds(300))
                        let popup = retentionPopup(in: window.contentView!)!
                        precondition(popup.itemTitles == ["8 小时", "1 天", "3 天", "7 天", "30 天"].map { NSLocalizedString($0, comment: "") })
                        for (index, retention) in ClipboardRetention.allCases.enumerated() {
                            popup.selectItem(at: index)
                            NSApp.sendAction(popup.action!, to: popup.target, from: popup)
                            precondition(model.settings.clipboardRetention == retention)
                            let reloaded = try AppModel(root: root)
                            precondition(reloaded.settings.clipboardRetention == retention)
                            precondition(model.clipboardStore.retentionInterval == retention.interval)
                        }
                        popup.selectItem(at: 2)
                        NSApp.sendAction(popup.action!, to: popup.target, from: popup)
                        try await Task.sleep(for: .milliseconds(100))
                        let view = window.contentView!
                        view.layoutSubtreeIfNeeded()
                        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        try bitmap.representation(using: .png, properties: [:])!.write(
                            to: URL(filePath: "build/clipboard-retention-\(appearance).png"))
                    }
                    model.settings.clipboardRetention = .thirtyDays
                    let recent = ClipboardItem(kind: .text, text: "retention recent", byteSize: 1, contentHash: "recent",
                                               createdAt: Date().addingTimeInterval(-3600))
                    let old = ClipboardItem(kind: .text, text: "retention old", byteSize: 1, pinned: true, contentHash: "old",
                                            createdAt: Date().addingTimeInterval(-86400))
                    try model.clipboardStore.insert(recent)
                    try model.clipboardStore.insert(old)
                    model.settings.clipboardRetention = .eightHours
                    precondition(model.clipboardStore.recent(limit: 10).map(\.id) == [recent.id])
                    let monitor = ClipboardMonitor(app: model)
                    monitor.start()
                    try model.clipboardStore.insert(ClipboardItem(kind: .text, text: "periodic expired", byteSize: 1,
                        contentHash: "expired", createdAt: Date().addingTimeInterval(-9 * 3600)))
                    try await Task.sleep(for: .milliseconds(1500))
                    monitor.stop()
                    precondition(model.clipboardStore.recent(limit: 10).map(\.id) == [recent.id])
                    print("PASS: five retention choices, 3-day default, legacy/invalid settings, persistence, shortening cleanup and idle monitor cleanup; light/dark UI captured")
                    exit(0)
                }
                if CommandLine.arguments.contains("--general-defaults") {
                    precondition(model.preferences.showMenuBarIcon && !model.preferences.showDockIcon)
                    precondition(model.preferences.appearance == "system" && model.preferences.language == .system)
                    precondition(model.preferences.liquidGlass && !model.preferences.hasInitializedLoginItem)
                    enum RegistrationFailure: Error { case denied }
                    do {
                        try model.initializeLaunchAtLogin { throw RegistrationFailure.denied }
                        preconditionFailure("Registration failure must propagate")
                    } catch RegistrationFailure.denied {}
                    precondition(!model.preferences.hasInitializedLoginItem)
                    var registrations = 0
                    try model.initializeLaunchAtLogin { registrations += 1 }
                    try model.initializeLaunchAtLogin { registrations += 1 }
                    let relaunched = try AppModel(root: root)
                    try relaunched.initializeLaunchAtLogin { registrations += 1 }
                    precondition(registrations == 1 && relaunched.preferences.hasInitializedLoginItem)
                    let legacy = try JSONDecoder().decode(SettingsPreferences.self, from: Data(
                        #"{"showMenuBarIcon":false,"showDockIcon":true,"appearance":"dark","language":"en"}"#.utf8))
                    precondition(legacy.hasInitializedLoginItem && !legacy.showMenuBarIcon && legacy.showDockIcon)
                    precondition(legacy.appearance == "dark" && legacy.language == .english)
                    model.preferences = legacy
                    try model.initializeLaunchAtLogin { registrations += 1 }
                    precondition(registrations == 1)
                    print("General defaults: fresh install, one-time registration, retry, relaunch and legacy preferences passed")
                    exit(0)
                }
                if CommandLine.arguments.contains("--dock-only") {
                    let legacy = try JSONDecoder().decode(SettingsPreferences.self,
                        from: Data(#"{"appearance":"dark","showMenuBarIcon":false}"#.utf8))
                    precondition(!legacy.showDockIcon && legacy.appearance == "dark" && !legacy.showMenuBarIcon)
                    precondition(!model.preferences.showDockIcon)
                    let dock = DockVisibilityController()
                    model.onDockIconVisibilityChange = { dock.showDockIcon = $0 }
                    dock.showDockIcon = model.preferences.showDockIcon
                    precondition(application.activationPolicy() == .accessory)
                    let window = SettingsWindow.make(app: model)
                    window.isReleasedWhenClosed = false
                    let presentation = WindowPresentation()
                    @MainActor func openAndCheckFocus() async throws {
                        precondition(!window.isVisible, "Exercise opening a hidden settings window")
                        let observer = NotificationCenter.default.addObserver(
                            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
                        ) { _ in
                            MainActor.assumeIsolated {
                                precondition(window.alphaValue == 0, "Settings must acquire focus before being revealed")
                            }
                        }
                        defer { NotificationCenter.default.removeObserver(observer) }
                        presentation.show(window)
                        precondition(window.alphaValue == 0 || (application.isActive && window.isKeyWindow))
                        for _ in 0..<50 where !window.isKeyWindow || window.alphaValue == 0 {
                            try await Task.sleep(for: .milliseconds(20))
                        }
                        precondition(application.isActive && window.isKeyWindow && window.alphaValue == 1)
                    }
                    application.deactivate()
                    for _ in 0..<50 where application.isActive {
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    precondition(!application.isActive, "Exercise the first open from the background")
                    try await openAndCheckFocus()
                    precondition(application.activationPolicy() == .accessory)
                    precondition(window.isVisible && window.isKeyWindow)
                    if let view = window.contentView,
                       let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        try bitmap.representation(using: .png, properties: [:])?.write(
                            to: URL(fileURLWithPath: "build/dock-settings.png"))
                    }
                    model.preferences.showDockIcon = true
                    let enabled = try AppModel(root: root).preferences.showDockIcon
                    precondition(enabled)
                    window.close()
                    precondition(application.activationPolicy() == .regular)
                    try await openAndCheckFocus()
                    precondition(application.activationPolicy() == .regular)
                    precondition(window.isVisible && window.isKeyWindow)
                    model.preferences.showDockIcon = false
                    precondition(application.activationPolicy() == .accessory)
                    presentation.show(window)
                    try await Task.sleep(for: .milliseconds(600))
                    precondition(window.isVisible && window.isKeyWindow)
                    precondition(application.activationPolicy() == .accessory)
                    window.close()
                    precondition(application.activationPolicy() == .accessory)
                    let disabled = try AppModel(root: root).preferences.showDockIcon
                    precondition(!disabled)
                    // Simulate launch with the saved enabled preference and no windows.
                    model.preferences.showDockIcon = true
                    let relaunched = DockVisibilityController()
                    relaunched.showDockIcon = try AppModel(root: root).preferences.showDockIcon
                    precondition(application.activationPolicy() == .regular)
                    print("Dock visibility: legacy defaults, persistence, live changes with settings open, settings focus, window close and relaunch passed")
                    exit(0)
                }
                guard model.keywords.commands.map(\.keyword) == ["go", "chat", "dy", "tb", "jd", "bl", "gh", "x"],
                      model.keywords.match("go hello")?.0.urlTemplate.contains("google.com") == true,
                      model.keywords.match("chat hello")?.0.url(for: "hello")?.host == "chatgpt.com",
                      SettingsPage.allCases.contains(.keywords),
                      SettingsPage.resolve("keywords") == .keywords else {
                    fatalError("legacy settings changed fixed presets or command settings are missing")
                }
                let legacyCommands = try JSONDecoder().decode(SettingsPreferences.self, from: Data("{}".utf8))
                let defaults: Set<String> = ["ds", "yt", "bd", "hb", "zh", "xhs", "wb"]
                precondition(SettingsPreferences().disabledBuiltInCommands == defaults)
                precondition(legacyCommands.disabledBuiltInCommands == defaults)
                precondition(SettingsPreferences().disabledSearchCommands.isEmpty)
                precondition(legacyCommands.disabledSearchCommands.isEmpty)
                let disabledTabCommand = try JSONDecoder().decode(SettingsPreferences.self,
                    from: Data(#"{"disabledSearchCommands":["tabs"]}"#.utf8))
                precondition(disabledTabCommand.disabledSearchCommands == ["tabs"])
                let explicitlyEnabled = try JSONDecoder().decode(SettingsPreferences.self,
                    from: Data(#"{"disabledBuiltInCommands":[]}"#.utf8))
                precondition(explicitlyEnabled.disabledBuiltInCommands.isEmpty)
                let customized = try JSONDecoder().decode(SettingsPreferences.self,
                    from: Data(#"{"disabledBuiltInCommands":["go"]}"#.utf8))
                precondition(customized.disabledBuiltInCommands == ["go"])
                for keyword in defaults {
                    precondition(model.keywords.matchInput(keyword + " query") == nil)
                }
                let launcher = LauncherModel(app: model, searchProviders: [])
                for command in KeywordCommand.builtIn {
                    model.preferences.disabledBuiltInCommands.insert(command.keyword)
                    precondition(model.keywords.matchInput(command.keyword + " ") == nil)
                    launcher.query = command.keyword + " hello"
                    precondition(launcher.commandInput == nil && launcher.inputText == command.keyword + " hello")
                    precondition(!launcher.results.contains { $0.source == .keyword && $0.title == command.name })
                    launcher.query = command.keyword
                    precondition(!launcher.results.contains { $0.target.kind == "keyword-match" })
                    let restored = try AppModel(root: root)
                    precondition(restored.preferences.disabledBuiltInCommands.contains(command.keyword))
                    precondition(restored.keywords.matchInput(command.keyword + " hello") == nil)
                    model.preferences.disabledBuiltInCommands.remove(command.keyword)
                    launcher.query = command.keyword + " hello"
                    precondition(launcher.commandInput?.command.keyword == command.keyword)
                    launcher.query = ""
                }
                model.preferences.disabledBuiltInCommands = Set(KeywordCommand.builtIn.map(\.keyword))
                let allDisabled = try AppModel(root: root)
                precondition(allDisabled.keywords.commands.isEmpty)
                model.preferences.disabledBuiltInCommands = []
                let allEnabled = try AppModel(root: root)
                precondition(allEnabled.keywords.commands == KeywordCommand.builtIn)
                print("Built-in command defaults, disable/enable routing, suggestions and persistence passed")
                precondition(model.commandKeyword("tabs") == "st")
                precondition(model.commandKeywordProblem("ST", id: "ai") != nil)
                let tabLauncher = LauncherModel(app: model, searchProviders: [
                    TabCommandProvider(source: .chromeTab), TabCommandProvider(source: .app, count: 8),
                    TabCommandProvider(source: .shortcut, count: 3)
                ])
                tabLauncher.query = "st"
                try await Task.sleep(for: .milliseconds(300))
                precondition(tabLauncher.results.first?.target.kind == "search-command")
                precondition(tabLauncher.results.filter { $0.source == .app }.count == 8)
                precondition(tabLauncher.results.filter { $0.source == .shortcut }.count == 3)
                model.preferences.disabledSearchCommands.insert("tabs")
                tabLauncher.query = "st"
                try await Task.sleep(for: .milliseconds(300))
                precondition(!tabLauncher.results.contains {
                    $0.target.kind == "search-command" && $0.target.identifier == "tabs"
                })
                tabLauncher.query = "st fixture"
                precondition(!tabLauncher.isTabScope && tabLauncher.inputText == "st fixture")
                let disabledTabs = try AppModel(root: root)
                precondition(disabledTabs.preferences.disabledSearchCommands.contains("tabs"))
                model.preferences.disabledSearchCommands.remove("tabs")
                tabLauncher.query = "st"
                print("Search command defaults, disabled routing and persistence passed")
                if CommandLine.arguments.contains("--search-commands") {
                    let controller = LauncherController(model: tabLauncher)
                    controller.show()
                    guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) as? LauncherPanel else { fatalError("missing tab entry panel") }
                    panel.onBlur = {}
                    tabLauncher.query = "st"
                    for appearance in ["light", "dark"] {
                        model.preferences.appearance = appearance
                        try await Task.sleep(for: .milliseconds(400))
                        precondition(tabLauncher.results.first?.target.kind == "search-command")
                        guard let view = panel.contentView,
                              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("missing tab entry view") }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/tab-entry-\(appearance).png"))
                    }
                    controller.hide()
                    tabLauncher.query = "st"
                }
                guard let tabEntry = tabLauncher.results.first(where: { $0.target.kind == "search-command" }) else { fatalError("missing tab entry") }
                tabLauncher.execute(tabEntry, action: .open)
                precondition(tabLauncher.isTabScope && tabLauncher.inputText.isEmpty)
                tabLauncher.inputText = "fixture"
                try await Task.sleep(for: .milliseconds(300))
                precondition(tabLauncher.results.count == 1 && tabLauncher.results[0].source == .chromeTab)
                tabLauncher.leaveCommand()
                model.preferences.commandKeywords["tabs"] = "tabs"
                let savedTabCommands = try AppModel(root: root)
                precondition(savedTabCommands.commandKeyword("tabs") == "tabs")
                tabLauncher.query = "TABS"
                try await Task.sleep(for: .milliseconds(300))
                precondition(tabLauncher.results.first?.target.kind == "search-command")
                tabLauncher.query = "TABS fixture"
                precondition(tabLauncher.isTabScope && tabLauncher.inputText == "fixture")
                tabLauncher.inputText = ""
                precondition(tabLauncher.backspaceOnEmptyInput() && !tabLauncher.hasScope)
                model.preferences.commandKeywords.removeValue(forKey: "tabs")
                precondition(NSImage(named: "Tabs") != nil)
                if CommandLine.arguments.contains("--search-commands") {
                    let controller = LauncherController(model: tabLauncher)
                    controller.show()
                    guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) as? LauncherPanel else { fatalError("missing launcher panel") }
                    panel.onBlur = {}
                    tabLauncher.query = "st fixture"
                    for appearance in ["light", "dark"] {
                        model.preferences.appearance = appearance
                        try await Task.sleep(for: .milliseconds(400))
                        guard let view = panel.contentView,
                              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("missing tab view") }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/tab-search-\(appearance).png"))
                    }
                    controller.hide()
                }
                print("Tab search entry, isolated provider, custom token, persistence and exit passed")
                let searchLauncher = LauncherModel(app: model, searchProviders: [
                    TabCommandProvider(source: .chromeTab), TabCommandProvider(source: .bookmark),
                    TabCommandProvider(source: .app, count: 8), TabCommandProvider(source: .shortcut, count: 3)
                ])
                var unexpectedPrompts: [String] = []
                searchLauncher.onAskAI = { unexpectedPrompts.append($0) }
                let searchController = LauncherController(model: searchLauncher)
                if CommandLine.arguments.contains("--search-commands") { searchController.show() }
                for command in AppModel.searchCommands {
                    for customized in [false, true] {
                        let token = customized ? "custom" + command.0 : command.2
                        if customized { model.preferences.commandKeywords[command.0] = token }
                        searchLauncher.query = token.uppercased()
                        try await Task.sleep(for: .milliseconds(300))
                        precondition(searchLauncher.results.first?.target == TargetRef(kind: "search-command", identifier: command.0),
                                     "missing \(command.0) entry for \(customized ? "custom" : "default") token; got \(String(describing: searchLauncher.results.prefix(3).map { "\($0.target.kind):\($0.target.identifier)" }))")
                        precondition(!searchLauncher.results.contains { ["tab-search", "bookmark-search"].contains($0.target.kind) })
                        if !customized, CommandLine.arguments.contains("--search-commands") {
                            guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) as? LauncherPanel else { fatalError("missing search commands panel") }
                            panel.onBlur = {}
                            for appearance in ["light", "dark"] {
                                model.preferences.appearance = appearance
                                try await Task.sleep(for: .milliseconds(200))
                                guard let view = panel.contentView,
                                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("missing command view") }
                                view.cacheDisplay(in: view.bounds, to: bitmap)
                                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/search-entry-\(command.0)-\(appearance).png"))
                            }
                        }
                        // The screen picker is a one-shot action, not an input scope.
                        if command.0 != "colorPicker" {
                            searchLauncher.submit(.executeSelection)
                            precondition(searchLauncher.hasScope && searchLauncher.inputText.isEmpty)
                            precondition(searchLauncher.isTabScope == (command.0 == "tabs"))
                            precondition(searchLauncher.isBookmarkScope == (command.0 == "bookmark"))
                            precondition(searchLauncher.isLinkScope == (command.0 == "link"))
                            precondition(searchLauncher.isAIScope == (command.0 == "ai"))
                            precondition(unexpectedPrompts.isEmpty)
                            precondition(searchLauncher.backspaceOnEmptyInput() && !searchLauncher.hasScope)
                            searchLauncher.query = token + " "
                            precondition(searchLauncher.hasScope && searchLauncher.inputText.isEmpty)
                            searchLauncher.leaveCommand()
                        }
                        model.preferences.commandKeywords.removeValue(forKey: command.0)
                    }
                }
                searchController.hide()
                print("All search commands: exact match, priority, custom triggers, Return/Space entry and no premature AI submission passed")
                precondition(legacyCommands.commandKeywords.isEmpty)
                precondition(model.commandKeywordProblem("GO", id: "ai") != nil)
                precondition(model.commandKeywordProblem("X", id: "ai") != nil)
                model.preferences.commandKeywords["x"] = "twitter"
                let savedX = try AppModel(root: root)
                precondition(savedX.keywords.matchInput("x ") == nil)
                launcher.query = "twitter SwiftUI"
                precondition(launcher.commandInput?.command.keyword == "twitter")
                precondition(launcher.keyword(for: launcher.results[0]) == "x")
                precondition(savedX.keywords.match("twitter SwiftUI")?.0.url(for: "SwiftUI")?.host == "x.com")
                launcher.leaveCommand()
                model.preferences.commandKeywords.removeValue(forKey: "x")
                precondition(model.commandKeywordProblem(">", id: "link") != nil)
                precondition(model.commandKeywordProblem("a b", id: "ai") != nil)
                model.preferences.commandKeywords = ["ai": "ask", "link": "url", "bookmark": "saved", "go": "web"]
                let savedCommands = try AppModel(root: root)
                precondition(savedCommands.commandKeyword("ai") == "ask")
                precondition(savedCommands.keywords.match("web hello")?.0.name == "Google 搜索")
                precondition(savedCommands.keywords.match("go hello") == nil)
                var aiPrompts: [String] = []
                launcher.onAskAI = { aiPrompts.append($0) }
                launcher.query = "ask 1 + 2"
                precondition(launcher.isAIScope && launcher.inputText == "1 + 2")
                precondition(launcher.results.count == 1 && launcher.results[0].primaryAction == .askAI(prompt: "1 + 2"))
                precondition(aiPrompts.isEmpty)
                launcher.submit(.executeSelection)
                launcher.submit(.submitToAI)
                precondition(aiPrompts == ["1 + 2", "1 + 2"])
                launcher.leaveCommand()
                precondition(!launcher.hasScope)
                launcher.query = "url example.com"
                precondition(launcher.isLinkScope && launcher.results.count == 1)
                precondition(launcher.results[0].primaryAction == .openURL(URL(string: "https://example.com")!))
                launcher.query = "url "
                precondition(launcher.hasScope && launcher.results.isEmpty)
                precondition(launcher.backspaceOnEmptyInput() && !launcher.hasScope)
                launcher.query = "web hello"
                precondition(launcher.commandInput?.command.keyword == "web")
                precondition(launcher.keyword(for: launcher.results[0]) == "go")
                model.preferences.commandKeywords = [:]
                launcher.query = "ai hello"
                precondition(launcher.isAIScope && launcher.results.count == 1)
                launcher.query = ""
                print("Custom search commands: migration, collision validation, persistence, AI/link routing, exit and brand identity passed")
                try await assertCommandReset(model, root: root)
                if CommandLine.arguments.contains("--website-commands") { exit(0) }
                if CommandLine.arguments.contains("--search-commands") {
                    model.settingsTab = "keywords"
                    let window = SettingsWindow.make(app: model)
                    window.makeKeyAndOrderFront(nil)
                    for appearance in ["light", "dark"] {
                        model.preferences.appearance = appearance
                        try await Task.sleep(for: .milliseconds(400))
                        window.contentView?.layoutSubtreeIfNeeded()
                        if appearance == "light" { assertSettingsClickOutsideEndsEditing(window) }
                        guard let view = window.contentView,
                              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("missing commands view") }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/search-commands-\(appearance).png"))
                    }
                    try await assertCommandTabsAndGlobalSearch(window, model: model)
                    window.setContentSize(SettingsWindow.minimumSize)
                    try await Task.sleep(for: .milliseconds(400))
                    window.contentView?.layoutSubtreeIfNeeded()
                    if let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/search-commands-minimum.png"))
                    }
                    exit(0)
                }
                model.settings.notesFolders = [NotesFolder(account: "Fixture", folder: "Parent / Child")]
                model.settings.notesFolders = [NotesFolder(account: "Fixture", folder: "Parent / Child", folderID: "fixture-id")]
                guard try AppModel(root: root).settings.notesFolders.first?.folderID == "fixture-id" else {
                    fatalError("Notes folder identifier migration was not persisted")
                }
                model.settings.notesFolders = []
                guard try AppModel(root: root).settings.notesFolders.isEmpty else {
                    fatalError("Notes folder deselection was not persisted")
                }
                var input = LauncherInputState()
                input.edit("> pwd", keywords: model.keywords)
                guard input.terminal, input.text == "pwd" else {
                    fatalError("terminal preset failed without user configuration")
                }
                let legacy = Data(#"{"appearance":"dark","hotKeyCode":49,"hotKeyModifiers":6144,"hotKeyLabel":"⌃⌥ Space","clipboardHotKeyLabel":"custom clipboard"}"#.utf8)
                let migrated = try JSONDecoder().decode(SettingsPreferences.self, from: legacy)
                guard migrated.appearance == "dark", migrated.hotKeyLabel == "⌃⌥ Space",
                      migrated.clipboardHotKeyLabel == "custom clipboard",
                      migrated.agentHotKeyCode == SettingsPreferences.defaultAgentHotKey.code,
                      migrated.agentHotKeyModifiers == SettingsPreferences.defaultAgentHotKey.modifiers,
                      migrated.agentHotKeyLabel == SettingsPreferences.defaultAgentHotKey.label else {
                    fatalError("AI hotkey migration lost existing preferences or default binding")
                }
                model.preferences.agentHotKeyCode = 17
                model.preferences.agentHotKeyModifiers = 6144
                model.preferences.agentHotKeyLabel = "⌃⌥ T"
                let reloaded = try AppModel(root: root)
                guard reloaded.preferences.agentHotKeyCode == 17,
                      reloaded.preferences.agentHotKeyModifiers == 6144,
                      reloaded.preferences.agentHotKeyLabel == "⌃⌥ T" else {
                    fatalError("custom AI hotkey did not survive preference reload")
                }
                let defaultAgent = SettingsPreferences.defaultAgentHotKey
                model.preferences.agentHotKeyCode = defaultAgent.code
                model.preferences.agentHotKeyModifiers = defaultAgent.modifiers
                model.preferences.agentHotKeyLabel = defaultAgent.label
                if CommandLine.arguments.contains("--dark") { model.preferences.appearance = "dark" }
                var hotKey: HotKey?
                model.onHotKeyChange = { code, modifiers in
                    do {
                        let candidate = try HotKey(keyCode: code, modifiers: modifiers) {}
                        hotKey?.unregister()
                        hotKey = candidate
                        model.hotKeyStatus = "已注册"
                        return true
                    } catch { model.hotKeyStatus = "组合键已被占用"; return false }
                }
                try await assertPermissionRefreshRace()
                if (CommandLine.arguments.contains("--plugins") || CommandLine.arguments.contains("--plugins-only")) { model.settingsTab = SettingsPage.plugins.rawValue }
                let window = SettingsWindow.make(app: model)
                guard let split = window.contentViewController?.children.first as? NSSplitViewController,
                      split.splitViewItems.count == 2,
                      split.splitViewItems[0].minimumThickness == 220,
                      window.styleMask.contains(.resizable),
                      window.contentMinSize == SettingsWindow.minimumSize else {
                    fatalError("missing native settings sidebar or resize constraints")
                }
                window.center()
                window.makeKeyAndOrderFront(nil)
                if CommandLine.arguments.contains("--permissions-only") {
                    model.settingsTab = SettingsPage.permissions.rawValue
                    await model.refreshChromeBookmarkAccess()
                    for appearance in ["light", "dark"] {
                        model.preferences.appearance = appearance
                        try await Task.sleep(for: .milliseconds(500))
                        window.contentView?.layoutSubtreeIfNeeded()
                        assertDetailBelowToolbar(split, window: window)
                        guard model.chromeBookmarkAccessState != nil,
                              let view = window.contentView,
                              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                            fatalError("Chrome bookmark access must be checked on the permissions page")
                        }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        try bitmap.representation(using: .png, properties: [:])!.write(
                            to: URL(filePath: "build/settings-permissions-access-\(appearance).png"))
                    }
                    try? FileManager.default.removeItem(at: root)
                    print("Chrome bookmark permission page snapshots passed")
                    exit(0)
                }
                if preview {
                    if CommandLine.arguments.contains("--commands") { model.settingsTab = "keywords" }
                    application.activate(); return
                }
                if CommandLine.arguments.contains("--plugins-only") {
                    for appearance in ["light", "dark"] {
                        model.preferences.appearance = appearance
                        try await Task.sleep(for: .milliseconds(350))
                        window.contentView?.layoutSubtreeIfNeeded()
                        assertDetailBelowToolbar(split, window: window)
                        guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("missing plugin view") }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        let language = Bundle.main.preferredLocalizations.first ?? "unknown"
                        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/plugins-\(language)-\(appearance).png"))
                    }
                    try? FileManager.default.removeItem(at: root)
                    print("Plugin native snapshots passed: \(Bundle.main.preferredLocalizations)")
                    exit(0)
                }
                _ = try model.gateway.register(name: "Settings layout fixture")
                for appearance in ["light", "dark"] {
                    model.preferences.appearance = appearance
                    let pages: [SettingsPage] = CommandLine.arguments.contains("--hotkeys-only")
                        ? [.hotkey] : CommandLine.arguments.contains("--sources-only")
                        ? [.sources] : CommandLine.arguments.contains("--navigation-settings")
                        ? [.general, .search, .clipboard] : SettingsPage.allCases
                    for page in pages {
                        let tab = page.rawValue
                        model.settingsTab = tab
                        try await Task.sleep(for: .milliseconds(250))
                        window.contentView?.layoutSubtreeIfNeeded()
                        assertDetailBelowToolbar(split, window: window)
                        guard window.title == "\(page.title) — \(NSLocalizedString("Asky 设置", comment: ""))" else {
                            fatalError("settings title did not follow selection: \(tab)")
                        }
                        if page == .search {
                            func popup(in view: NSView) -> NSPopUpButton? {
                                if let button = view as? NSPopUpButton { return button }
                                return view.subviews.lazy.compactMap { popup(in: $0) }.first
                            }
                            guard let choice = popup(in: split.splitViewItems[1].viewController.view) else {
                                fatalError("missing folder navigation choice")
                            }
                            choice.selectItem(at: 1)
                            NSApp.sendAction(choice.action!, to: choice.target, from: choice)
                            precondition(model.preferences.folderBackspaceBehavior == .exitNavigation)
                            let reloadedNavigation = try AppModel(root: root)
                            precondition(reloadedNavigation.preferences.folderBackspaceBehavior == .exitNavigation)
                            choice.selectItem(at: 0)
                            NSApp.sendAction(choice.action!, to: choice.target, from: choice)
                            precondition(model.preferences.folderBackspaceBehavior == .parent)
                        }
                        if page == .mcp {
                            try await assertMCPCheckboxLayout(in: split.splitViewItems[1].viewController.view)
                        }
                        guard let view = window.contentView,
                              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("missing settings view") }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("missing settings snapshot") }
                        try png.write(to: URL(filePath: "build/settings-\(appearance)-\(tab).png"))
                        if page == .sources || page == .hotkey {
                            guard let scroll = findScrollView(in: split.splitViewItems[1].viewController.view),
                                  let document = scroll.documentView else {
                                fatalError("missing settings scroll view")
                            }
                            let bottom = max(0, document.bounds.height - scroll.contentView.bounds.height)
                            guard bottom > 0 else { fatalError("settings reference no longer scrolls: \(tab)") }
                            scroll.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? bottom : 0))
                            scroll.reflectScrolledClipView(scroll.contentView)
                            try await Task.sleep(for: .milliseconds(250))
                            assertDetailBelowToolbar(split, window: window)
                            view.cacheDisplay(in: view.bounds, to: bitmap)
                            let scrolled = bitmap.representation(using: .png, properties: [:])!
                            try scrolled.write(to: URL(filePath: "build/settings-\(appearance)-\(tab)-scrolled.png"))
                        }
                    }
                }
                if CommandLine.arguments.contains("--hotkeys-only") {
                    try? FileManager.default.removeItem(at: root)
                    print("Shortcut reference native snapshots and scrolling passed")
                    exit(0)
                }
                if CommandLine.arguments.contains("--sources-only") {
                    try? FileManager.default.removeItem(at: root)
                    print("Data source native snapshots passed")
                    exit(0)
                }
                if CommandLine.arguments.contains("--navigation-settings") {
                    try? FileManager.default.removeItem(at: root)
                    print("General, search and clipboard native snapshots and navigation choice persistence passed")
                    exit(0)
                }
                model.openSettings(permissions: true)
                try await Task.sleep(for: .milliseconds(250))
                guard model.settingsTab == "permissions", window.title.hasPrefix(SettingsPage.permissions.title) else {
                    fatalError("permission recovery did not select its sidebar page")
                }
                window.setContentSize(SettingsWindow.minimumSize)
                window.contentView?.layoutSubtreeIfNeeded()
                assertDetailBelowToolbar(split, window: window)
                guard split.splitViewItems[0].isCollapsed == false,
                      split.splitViewItems[1].viewController.view.bounds.width >= 540 else {
                    fatalError("settings detail clipped at minimum window size")
                }
                try await assertStandaloneAuthorizationFlow(parent: window)
                try await assertNativeCardDrag(parent: window)
                try? FileManager.default.removeItem(at: root)
                print("Settings native snapshots, authorization lifecycle and card drag restoration passed")
                exit(0)
            } catch { fputs("Settings regression failed: \(error)\n", stderr); exit(1) }
        }
        application.run()
    }

    private static func assertModelCheckFailures() async throws {
        let base = URL(string: "https://api.minimax.cn/v1")!
        let secret = "fixture-secret-never-display"
        for (code, body, expected) in [
            (402, "{\"type\":\"insufficient_balance_error\",\"message\":\"insufficient balance (1008)\"}", "1008"),
            (401, "{\"error\":{\"message\":\"invalid key fixture-secret-never-display\"}}", "[redacted]"),
            (403, "{\"error\":{\"message\":\"permission denied\"}}", "permission denied"),
            (400, "{\"error\":{\"message\":\"unknown model\"}}", "unknown model"),
            (503, "<html>fixture-secret-never-display</html>", "HTTP 503"),
        ] {
            let report = await ModelCapabilityCheck.run(baseURL: base, model: "MiniMax-M3", apiKey: secret) { req in
                guard req.url?.absoluteString == "https://api.minimax.cn/v1/chat/completions",
                      req.value(forHTTPHeaderField: "Authorization") == "Bearer \(secret)" else {
                    fatalError("capability probe changed endpoint or authentication")
                }
                return (Data(body.utf8), HTTPURLResponse(url: req.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
            }
            guard report.capabilities.text == .unknown, report.capabilities.tools == .unknown,
                  report.capabilities.image == .unknown, report.failures.count == 3,
                  report.failures.allSatisfy({ $0.contains("HTTP \(code)") && $0.contains(expected) && !$0.contains(secret) }) else {
                fatalError("HTTP \(code) was hidden, leaked a credential, or marked a capability unsupported")
            }
        }
        let timedOut = await ModelCapabilityCheck.run(baseURL: base, model: "MiniMax-M3", apiKey: secret) { _ in
            throw URLError(.timedOut)
        }
        guard timedOut.capabilities.text == .unknown, timedOut.failures.count == 3 else {
            fatalError("network error was mistaken for unsupported model capabilities")
        }
        let mixed = await ModelCapabilityCheck.run(baseURL: base, model: "MiniMax-M3", apiKey: secret) { req in
            let json = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
            let code = json["tools"] == nil ? 200 : 400
            return (Data("{\"error\":{\"message\":\"tools rejected\"}}".utf8),
                    HTTPURLResponse(url: req.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
        }
        guard mixed.capabilities.text == .available, mixed.capabilities.image == .available,
              mixed.capabilities.tools == .unknown, mixed.failures.count == 1 else {
            fatalError("one rejected probe changed the other capability results")
        }
    }

    private static func assertNativeCardDrag(parent: NSWindow) async throws {
        var started = 0
        var accepted: [Bool] = []
        let card = PermissionCardHostingView(rootView: PermissionAppCard(colorScheme: .light, reduceTransparency: false),
            onStarted: { started += 1 }, onEnded: { accepted.append($0) })
        card.frame = NSRect(x: 12, y: 12, width: 320, height: 80)
        guard card.acceptsFirstMouse(for: nil), !card.mouseDownCanMoveWindow else {
            fatalError("dragging the inactive panel's card must not require a second click or move the window")
        }
        parent.contentView?.addSubview(card)
        defer { card.removeFromSuperview() }
        try await Task.sleep(for: .milliseconds(150))
        guard let snapshot = card.cardSnapshot(), snapshot.size == NSSize(width: 320, height: 80),
              let tiff = snapshot.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("drag preview is missing the full card")
        }
        try png.write(to: URL(filePath: "build/permission-drag-card.png"))
        card.beginCardDrag()
        guard card.alphaValue == 0, started == 1 else { fatalError("source card remained visible when dragging began") }
        card.finishCardDrag(operation: [])
        guard card.alphaValue == 1, accepted == [false] else { fatalError("cancelled drag did not restore the source card") }
        card.beginCardDrag()
        card.finishCardDrag(operation: .copy)
        guard card.alphaValue == 0, accepted == [false, true] else { fatalError("accepted drag incorrectly restored the source card") }
    }

    private static func assertPermissionRefreshRace() async throws {
        var pendingRead: CheckedContinuation<PermissionState, Never>?
        let model = PermissionSettingsModel(readState: { _ in
            await withCheckedContinuation { pendingRead = $0 }
        }, requestAccess: { _ in .authorized })
        let refresh = Task { await model.refresh() }
        while pendingRead == nil { await Task.yield() }
        await model.request(.calendar)
        guard model.states[.calendar] == .authorized, model.requesting == nil else {
            fatalError("successful request did not immediately update permission status")
        }
        pendingRead?.resume(returning: .notDetermined)
        await refresh.value
        guard model.states[.calendar] == .authorized else {
            fatalError("stale background read overwrote the completed request")
        }
    }

    /// Simulate permission changes without granting real TCC access or opening System Settings.
    private static func assertStandaloneAuthorizationFlow(parent: NSWindow) async throws {
        for regrant in [false, true] {
            var reads = 0
            var opened = 0
            var dismissed = 0
            var resets = 0
            let controller = PermissionAuthorizationWindow(readState: { _ in
                reads += 1
                if regrant {
                    return reads == 3 ? .denied : .authorized
                }
                return reads < 3 ? .denied : .authorized
            }, openSettings: { _ in
                opened += 1
                return PermissionAuthorizationSettingsHandle(windowFrame: { parent.frame }, dismiss: { dismissed += 1 })
            }, resetAuthorization: { _ in resets += 1 })
            controller.show(.accessibility, colorScheme: .light)
            try await Task.sleep(for: .milliseconds(150))
            guard let panel = controller.window, panel.isVisible,
                  panel.sheetParent == nil, parent.attachedSheet == nil,
                  panel.styleMask.contains(.nonactivatingPanel),
                  panel.level == .floating, !panel.hidesOnDeactivate,
                  opened == 1, dismissed == 0,
                  resets == (regrant ? 0 : 1) else {
                fatalError("authorization is modal or dismissed before a fresh grant")
            }
            try assertAuthorizationSurface(panel, appearance: regrant ? "light-regrant" : "light")
            for _ in 0..<30 where controller.window != nil {
                try await Task.sleep(for: .milliseconds(100))
            }
            guard controller.window == nil, dismissed == 1 else {
                fatalError("authorization completion failed to close the panel and its settings session")
            }
        }
        var pendingReset: CheckedContinuation<Void, Never>?
        var openedWhilePreparing = false
        let preparing = PermissionAuthorizationWindow(readState: { _ in .denied },
            openSettings: { _ in
                openedWhilePreparing = true
                return PermissionAuthorizationSettingsHandle(windowFrame: { parent.frame }, dismiss: {})
            }, resetAuthorization: { _ in
                await withCheckedContinuation { pendingReset = $0 }
            })
        preparing.show(.screenRecording, colorScheme: .light)
        while pendingReset == nil { await Task.yield() }
        guard !openedWhilePreparing else { fatalError("settings opened before stale entry reset completed") }
        // Closing while the reset is pending must not reopen settings when it returns.
        preparing.cancel()
        pendingReset?.resume()
        try await Task.sleep(for: .milliseconds(150))
        guard preparing.window == nil, !openedWhilePreparing else {
            fatalError("cancelled reset reopened the authorization flow")
        }
        var dismissed = false
        let cancelled = PermissionAuthorizationWindow(readState: { _ in .denied },
            openSettings: { _ in
                PermissionAuthorizationSettingsHandle(windowFrame: { parent.frame }, dismiss: { dismissed = true })
            }, resetAuthorization: { _ in })
        cancelled.show(.screenRecording, colorScheme: .dark)
        try await Task.sleep(for: .milliseconds(150))
        guard let darkPanel = cancelled.window else { fatalError("missing dark authorization panel") }
        try assertAuthorizationSurface(darkPanel, appearance: "dark")
        cancelled.window?.close()
        try await Task.sleep(for: .milliseconds(600))
        guard cancelled.window == nil, !dismissed else {
            fatalError("cancelling authorization should stop observation without dismissing System Settings")
        }
    }

    private static func assertAuthorizationSurface(_ panel: NSPanel, appearance: String) throws {
        guard let surface = panel.contentView,
              abs(panel.frame.width - 360) < 1, panel.hasShadow,
              surface.layer?.cornerRadius == 24, surface.layer?.masksToBounds == true else {
            fatalError("authorization window must fit its clipped glass with no transparent padding")
        }
        if #available(macOS 26, *), WindowSurface.usesNativeGlass {
            guard surface is NSGlassEffectView else { fatalError("authorization must use the native glass surface") }
        }
        let expectedAppearance: NSAppearance.Name = appearance == "dark" ? .darkAqua : .aqua
        guard panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expectedAppearance else {
            fatalError("authorization glass appearance must match its content")
        }
        let capture = Process()
        capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(panel.windowNumber), "build/authorization-\(appearance).png"]
        try capture.run()
        capture.waitUntilExit()
        guard capture.terminationStatus == 0 else { fatalError("authorization window capture failed") }
    }

    private static func assertDetailBelowToolbar(_ split: NSSplitViewController, window: NSWindow) {
        guard let hosting = split.splitViewItems[1].viewController.children.first else {
            fatalError("missing settings detail host")
        }
        let viewport = hosting.view.convert(hosting.view.bounds, to: nil)
        guard viewport.maxY <= window.contentLayoutRect.maxY + 0.5,
              viewport.height > 400 else {
            fatalError("settings scroll viewport overlaps toolbar: \(viewport), layout: \(window.contentLayoutRect)")
        }
    }

    private static func assertCommandReset(_ model: AppModel, root: URL) async throws {
        let preferences = model.preferences
        let settings = model.settings
        let tab = model.settingsTab
        defer { model.preferences = preferences; model.settings = settings; model.settingsTab = tab }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

        for scenario in ["website", "category", "alias", "terminal", "search-command", "available"] {
            model.preferences = preferences
            model.settings = settings
            model.preferences.disabledBuiltInCommands = []
            let id = scenario == "search-command" ? "ai" : "go"
            let custom = id == "ai" ? "ask" : "g2"
            model.preferences.commandKeywords = [id: custom]
            model.preferences.aliases = []
            switch scenario {
            case "website": model.preferences.commandKeywords["yt"] = "go"
            case "category": model.preferences.commandKeywords["ai"] = "go"
            case "alias": model.preferences.aliases = [LauncherAlias(alias: "GO", kind: "shortcut", target: "Daily")]
            case "terminal": model.settings.terminalKeyword = "go"
            case "search-command": model.preferences.commandKeywords["go"] = "ai"
            default: break
            }
            let before = model.preferences.commandKeywords
            model.settingsTab = "keywords"
            let window = SettingsWindow.make(app: model)
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            try await Task.sleep(for: .milliseconds(250))
            if id == "go" {
                let tabs = descendants(window.contentView!).compactMap { $0 as? NSSegmentedControl }.first!
                tabs.selectedSegment = 1
                _ = tabs.sendAction(tabs.action, to: tabs.target)
                try await Task.sleep(for: .milliseconds(150))
            }
            let views = descendants(window.contentView!)
            guard let field = views.compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable && $0.stringValue == custom }) else {
                fatalError("Missing command editor for reset scenario: \(scenario)")
            }
            let fieldCenter = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)
            guard let reset = views.compactMap({ $0 as? NSButton }).first(where: {
                $0.title == NSLocalizedString("恢复默认", comment: "") &&
                abs($0.convert(NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: nil).y - fieldCenter.y) < 1
            }) else { fatalError("Missing reset control for \(scenario)") }
            reset.performClick(nil)
            try await Task.sleep(for: .milliseconds(150))
            let restored = try AppModel(root: root)
            if scenario == "available" {
                precondition(model.preferences.commandKeywords[id] == nil && restored.commandKeyword(id) == "go")
                precondition(field.stringValue == "go", "Successful reset must update the editor")
            } else {
                precondition(model.preferences.commandKeywords == before && restored.preferences.commandKeywords == before,
                             "Conflicting reset must preserve both persisted command assignments: \(scenario)")
                precondition(field.stringValue == custom, "Rejected reset must preserve the editable trigger")
                if scenario == "website" {
                    precondition(model.keywords.match("go cats")?.0.url(for: "cats")?.host == "www.youtube.com")
                    let view = window.contentView!
                    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/command-reset-conflict-fixed.png"))
                }
            }
        }
        precondition(NSLocalizedString("撤销", comment: "") != NSLocalizedString("撤销 MCP 授权", comment: "") ||
                     Bundle.main.preferredLocalizations.first != "en", "Revoke must not reuse the edit-menu Undo translation")
        print("Command reset passed: website, category, alias, terminal and search-command conflicts, preserved routing/storage and successful reset")
    }

    private static func assertCommandTabsAndGlobalSearch(_ window: NSWindow, model: AppModel) async throws {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func fields() -> [NSTextField] {
            descendants(window.contentView!).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
        }
        func keywords() -> Set<String> { Set(fields().map(\.stringValue)) }
        func capture(_ name: String) throws {
            let view = window.contentView!
            view.layoutSubtreeIfNeeded()
            let capture = Process()
            capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(window.windowNumber), "build/command-tabs-\(name).png"]
            try capture.run()
            capture.waitUntilExit()
            precondition(capture.terminationStatus == 0, "failed to capture native command controls")
        }
        guard let tabs = descendants(window.contentView!).compactMap({ $0 as? NSSegmentedControl })
            .first(where: { $0.accessibilityIdentifier() == "command-tabs" }) else {
            fatalError("missing native command tabs")
        }
        precondition(tabs.segmentCount == 2, "missing command tabs")
        precondition(tabs.selectedSegment == 0, "first tab must start selected")
        precondition(keywords().contains("ql") && !keywords().contains("go"))
        precondition(AppModel.searchCommands.first { $0.0 == "quickLinks" }?.1 == "搜索指令")
        try capture("search")
        tabs.selectedSegment = 1
        _ = tabs.sendAction(tabs.action, to: tabs.target)
        try await Task.sleep(for: .milliseconds(200))
        precondition(tabs.selectedSegment == 1, "selected tab must move")
        precondition(keywords().contains("go") && !keywords().contains("ql"))
        try capture("built-in")
        guard let search = fields().first(where: { $0.placeholderString == NSLocalizedString("搜索指令或名称", comment: "") }) else {
            fatalError("missing global command search")
        }
        precondition(fields().filter { $0.placeholderString == search.placeholderString }.count == 1)
        window.makeFirstResponder(search)
        let editor = search.currentEditor()!
        editor.selectAll(nil)
        editor.insertText("搜索")
        try await Task.sleep(for: .milliseconds(200))
        precondition(keywords().contains("ql") && keywords().contains("go"), "search must include both groups")
        try capture("global-search")
        editor.selectAll(nil)
        editor.insertText("no-command-matches-179259")
        try await Task.sleep(for: .milliseconds(200))
        precondition(fields().count == 1, "unmatched search must hide every command editor")
        model.editCommand("quickLinks")
        try await Task.sleep(for: .milliseconds(250))
        precondition(keywords().contains("ql") && !keywords().contains("go"))
        precondition(fields().first(where: { $0.stringValue == "ql" })?.currentEditor() != nil)
        model.editCommand("go")
        try await Task.sleep(for: .milliseconds(250))
        precondition(keywords().contains("go") && !keywords().contains("ql"))
        precondition(fields().first(where: { $0.stringValue == "go" })?.currentEditor() != nil)
        print("Command tabs, ql label, global cross-tab search, empty results and edit focus passed")
    }

    private static func assertSettingsChrome(_ window: NSWindow, appearance: String) async throws {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func check() {
            window.contentView?.layoutSubtreeIfNeeded()
            let views = descendants(window.contentView!)
            let buttons = views.compactMap { $0 as? NSButton }.filter {
                $0.title == NSLocalizedString("恢复默认", comment: "") && !$0.isHiddenOrHasHiddenAncestor
            }
            precondition(!buttons.isEmpty)
            let tabs = views.compactMap { $0 as? NSSegmentedControl }.first!
            precondition(tabs.controlSize == .large, "focus transitions must not reset segmented control size")
            for button in buttons {
                precondition(button.controlSize == .large, "focus transitions must not reset button size")
                precondition(abs(button.bounds.height - 28) < 0.5, "native button must have the same 28pt surface height as inputs")
                let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
                let fields = views.compactMap { $0 as? NSTextField }.filter { $0.isEditable }
                precondition(fields.contains { field in
                    let point = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)
                    return abs(point.y - center.y) < 1
                }, "input and reset button must stay vertically aligned")
            }
        }
        func capture(_ state: String) throws {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-l", String(window.windowNumber), "build/settings-chrome-\(appearance)-\(state).png"]
            try process.run()
            process.waitUntilExit()
            precondition(process.terminationStatus == 0)
        }
        // Other desktop apps can activate while this standalone harness runs.
        window.makeKey()
        precondition(window.isKeyWindow)
        check()
        try capture("active")
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
                             styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(250))
        precondition(!window.isKeyWindow, "must exercise loss of key-window status")
        check()
        try capture("inactive")
        other.close()
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(250))
        // Other desktop apps can activate while this standalone harness runs.
        window.makeKey()
        precondition(window.isKeyWindow)
        check()
        try capture("restored")
    }

    private static func assertSettingsClickOutsideEndsEditing(_ window: NSWindow) {
        func fields(in view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { $0.isEditable ? [$0] : [] } ?? view.subviews.flatMap { fields(in: $0) }
        }
        guard let content = window.contentView else { fatalError("missing settings content") }
        let inputs = fields(in: content).filter { !$0.isHiddenOrHasHiddenAncestor }
        precondition(inputs.count >= 2, "expected actual command inputs")
        let first = inputs[0], second = inputs[1]
        func click(_ point: NSPoint) {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                window.sendEvent(event)
            }
        }
        func center(_ field: NSTextField) -> NSPoint {
            field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)
        }
        window.makeFirstResponder(first)
        precondition(first.currentEditor() != nil, "input must start editing")
        click(center(first))
        precondition(first.currentEditor() != nil, "clicking inside must preserve editing")
        click(center(second))
        precondition(second.currentEditor() != nil, "clicking another input must transfer editing")
        let original = second.stringValue
        // The sidebar gutter is outside every input and contains no action.
        click(content.convert(NSPoint(x: 3, y: content.bounds.midY), to: nil))
        precondition(!(window.firstResponder is NSTextView), "outside click must end editing")
        precondition(second.stringValue == original, "ending editing must preserve the value")
        print("Settings inputs: inside click, input switching, outside blur and value preservation passed")
    }

    private static func assertMCPCheckboxLayout(in view: NSView) async throws {
        // Both the modern LazyVGrid and legacy grouped form realize offscreen rows lazily.
        if let scroll = findScrollView(in: view), let document = scroll.documentView {
            scroll.contentView.scroll(to: NSPoint(x: 0,
                y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(for: .milliseconds(200))
            view.layoutSubtreeIfNeeded()
        }
        func buttons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        let labels = ["calendar", "reminders", "notes", "contacts", "chrome", "shortcuts", "messages"]
        let controls = buttons(in: view).filter { labels.contains($0.title) }
        guard Set(controls.map(\.title)) == Set(labels),
              controls.allSatisfy({ $0.bounds.height <= 32 && $0.bounds.width > 40 }) else {
            fatalError("MCP tool checkbox labels disappeared or controls expanded vertically")
        }
    }

    private static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { findScrollView(in: $0) }.first
    }
}
