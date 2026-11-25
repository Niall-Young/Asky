import AppKit
import SwiftUI
import ToolService
import Contracts
import Search
import DirectActions
import AgentHost
import Scheduler
import MCPLink
import LocalStore
import Security

private struct LanguageBrowserProvider: SearchProvider {
    let source: SearchSource
    func search(_ query: String, limit: Int) async -> [SearchResult] { [] }
}

@main @MainActor
enum ApplicationLanguageRegression {
    private static func snapshot(_ window: NSWindow, name: String) throws {
        guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fatalError("missing native snapshot")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/\(name).png"))
    }

    private static func checkOtherInterfaces(english: Bool, app: AppModel) async throws {
        let language = english ? "en" : "zh-Hans"
        let missing = await app.tools.submit(ActionRequest(tool: "missing 工具", arguments: [:], origin: .launcher, intent: .explicitRequest))
        precondition(missing.error?.code == .unknownTool)
        precondition(missing.error?.message == (english ? "Unknown tool: missing 工具" : "未知工具：missing 工具"))
        precondition(MCPLinkError.appUnavailable.description.hasPrefix(english ? "Asky is not running" : "Asky 未运行"))
        precondition(Keychain.KeychainError.status(errSecUserCanceled).localizedDescription.hasPrefix(english ? "Keychain authorization was cancelled" : "钥匙串授权已取消"))
        do {
            _ = try PluginManifest.resource("../中文.md", at: app.store.root)
            fatalError("invalid plugin path was accepted")
        } catch let error as ToolError {
            precondition(error.code == .invalidArguments && error.message.contains("../中文.md"))
            precondition(error.message.hasPrefix(english ? "The plugin file is missing" : "插件文件不存在"))
        }
        let invalid = await MessageCalendarCreation(store: app.store).submit(sourceID: "invalid", draft: .init(title: "Review", start: Date().addingTimeInterval(-86400))) { _ in
            fatalError("invalid calendar draft reached a write")
        }
        precondition(invalid.error?.code == .invalidArguments)
        precondition(invalid.error?.message == (english ? "The event information is invalid or its start time has passed" : "日程信息无效或开始时间已过"))
        let runtime = AgentHostError.handshakeFailed("raw service detail").localizedDescription
        precondition(runtime.contains("raw service detail"))
        precondition(runtime.hasPrefix(english ? "AI runtime connection failed:" : "AI 运行时连接失败："))
        for status in [401, 402, 403, 429, 500] {
            let report = await ModelCapabilityCheck.run(baseURL: URL(string: "https://example.invalid/v1")!, model: "test", apiKey: "private-key") { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (Data(#"{"error":{"message":"raw service detail private-key"}}"#.utf8), response)
            }
            precondition(report.failures.count == 3)
            for failure in report.failures {
                precondition(!failure.contains("private-key") && failure.contains("[redacted]"))
                if english { precondition(!failure.contains { $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }) }
            }
        }
        let requests: [(String, String, [String], String?)] = [
            ("calendar_create_event", "苹果日历 ·「Work」", ["新建「Review」", "2026-10-18T14:00:00+08:00 – 2026-10-18T15:00:00+08:00", "地点：Room 3"], "与 1 个日程时间重叠"),
            ("calendar_update_event", "日程「Review」", ["开始：2026-10-18T14:00:00+08:00 → 2026-10-18T16:00:00+08:00"], "重复日程：仅修改本次"),
            ("calendar_delete_event", "日程「Review」", ["删除 2026-10-18T14:00:00+08:00 的这次日程"], "重复日程：仅删除本次"),
            ("notes_create", "Notes「Work」", ["新建「Plan」", "preserve A → B and https://example.com"], nil),
            ("notes_append", "备忘录「Plan」（Work）", ["追加：preserve A → B"], nil),
            ("reminders_create", "提醒列表「Work」", ["新建提醒「Report」", "到期：2026-10-18T18:00:00+08:00"], nil),
            ("messages_prepare_draft", "Messages：Alex", ["草稿：Meet at 3"], "只会打开草稿，需要你在 Messages 中手动发送"),
            ("shortcuts_run", "快捷指令「Inbox」", ["无输入"], "快捷指令可能执行其自身定义的任意操作"),
            ("chrome_activate_tab", "Chrome 标签页", ["切换到「Project」", "https://example.com"], nil),
            ("memory_save", "记忆 MEMORY.md", ["添加：Afternoon meetings"], nil),
            ("memory_correct", "记忆「Morning meetings」", ["改为：Afternoon meetings"], nil),
            ("memory_forget", "记忆「Morning meetings」", ["删除这一行"], nil),
        ]
        for (tool, target, changes, note) in requests {
            let request = ConfirmationRequest(requestID: UUID().uuidString, tool: tool, target: target, changes: changes,
                note: note, argumentsDigest: "test", origin: .mcp(instanceID: "test"))
            let body = ConfirmationCenter.message(for: request, remaining: 2)
            precondition(body.hasPrefix(english ? "An external app" : "外部应用"))
            if english { precondition(!body.contains { $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }, body) }
        }
        let preserved = ConfirmationRequest(requestID: "preserve", tool: "notes_append", target: "备忘录「中文标题」",
            changes: ["追加：中文内容：A → B"], argumentsDigest: "test", origin: .launcher)
        let body = ConfirmationCenter.message(for: preserved, remaining: 0)
        precondition(body.contains("中文标题") && body.contains("中文内容：A → B"))
        let calendarModel = MessageCalendarEditorModel(.init(title: "Review", start: Date().addingTimeInterval(86400)),
            calendars: [.init(id: "work", name: "Work", account: "iCloud", isDefault: true)], source: "Bring prototype")
        for saving in [false, true] {
            calendarModel.saving = saving
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: MessageCalendarEditor.windowSize), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: MessageCalendarEditorView(model: calendarModel, cancel: {}, create: {}))
            host.sizingOptions = []
            host.frame = window.contentRect(forFrameRect: window.frame)
            window.contentView = WindowSurface.glassContentView(host, cornerRadius: 24)
            window.center()
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(200))
            try snapshot(window, name: "calendar-\(saving ? "saving" : "ready")-\(language)")
            window.close()
        }
        AppDialogPresenter.installIfNeeded()
        let owner = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false
        owner.center()
        owner.makeKeyAndOrderFront(nil)
        let center = ConfirmationCenter()
        let task = Task { await center.present(preserved) }
        var overlay: AppDialogOverlay?
        for _ in 0..<40 {
            if let found = AppDialogPresenter.shared.activeOverlay(in: owner),
               found.button(at: 0) != nil, found.button(at: 1) != nil {
                overlay = found
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard overlay != nil else {
            fatalError("missing confirmation dialog overlay")
        }
        try await Task.sleep(for: .milliseconds(400))
        try snapshot(owner, name: "confirmation-\(language)")
        center.rejectAll()
        _ = await task.value
        owner.close()
        print("PASS: model HTTP errors and redaction, runtime errors, all built-in confirmation bodies, user content preservation, calendar and confirmation native snapshots")
    }

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                let english = Bundle.main.preferredLocalizations.first == "en"
                let legacy = Data(#"{"appearance":"dark","hotKeyLabel":"custom shortcut"}"#.utf8)
                let migrated = try JSONDecoder().decode(SettingsPreferences.self, from: legacy)
                guard migrated.language == .system, migrated.appearance == "dark",
                      migrated.hotKeyLabel == "custom shortcut" else { fatalError("legacy preferences lost") }
                let unknown = try JSONDecoder().decode(SettingsPreferences.self, from: Data(#"{"language":"unknown","appearance":"light"}"#.utf8))
                guard unknown.language == .system, unknown.appearance == "light" else { fatalError("unsupported language didn't fall back") }
                let root = FileManager.default.temporaryDirectory.appending(path: "Asky-language-\(UUID())")
                defer { try? FileManager.default.removeItem(at: root) }
                let model = try AppModel(root: root)
                let coreAtLaunch = CoreLocalization.text("未获得日历完全访问权限")
                precondition(coreAtLaunch == (english ? "Full calendar access has not been granted" : "未获得日历完全访问权限"))
                model.preferences.language = .english
                let restored = try AppModel(root: root)
                guard restored.preferences.language == .english, model.launchLanguage == .system else {
                    fatalError("language didn't persist or changed the running language")
                }
                model.preferences.language = .system
                guard let identifier = Bundle.main.bundleIdentifier,
                      UserDefaults.standard.persistentDomain(forName: identifier)?["AppleLanguages"] == nil else {
                    fatalError("Follow System retained an app-specific override")
                }
                guard SettingsPage.general.title == (english ? "General" : "通用"),
                      NSLocalizedString("应用语言", comment: "") == (english ? "App language" : "应用语言"),
                      NSLocalizedString("退出 Asky", comment: "") == (english ? "Quit Asky" : "退出 Asky") else {
                    fatalError("native bundle localization mismatch")
                }
                precondition(CoreLocalization.text("未获得日历完全访问权限") == coreAtLaunch)
                try await checkOtherInterfaces(english: english, app: model)
                let launcher = LauncherModel(app: model, searchProviders: [LanguageBrowserProvider(source: .chromeTab), LanguageBrowserProvider(source: .bookmark)], chromeBookmarkAccessAllowed: true)
                for (trigger, expected) in [("st", "Search Open Tabs"), ("bm", "Search bookmarks"), ("link", "Search links"), ("ai", "AI search")] {
                    launcher.query = trigger
                    try await Task.sleep(for: .milliseconds(200))
                    guard let row = launcher.results.first, let action = launcher.primaryLauncherAction,
                          row.target.kind == "search-command",
                          row.title == (english ? expected : AppModel.searchCommands.first { $0.2 == trigger }!.1),
                          NSLocalizedString(action.title, tableName: "Launcher", comment: "") == row.title else {
                        fatalError("search entry/action localization mismatch: \(trigger)")
                    }
                }
                for command in KeywordCommand.builtIn {
                    let name = NSLocalizedString(command.name, comment: "")
                    launcher.query = command.keyword
                    try await Task.sleep(for: .milliseconds(200))
                    guard launcher.results.contains(where: { $0.target.kind == "keyword-match" && $0.title == name }),
                          !english || !name.contains(where: { $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }) else {
                        fatalError("website suggestion localization mismatch: \(command.keyword)")
                    }
                    launcher.query = command.keyword + " 原样 query"
                    let title = command.supportsQuery
                        ? (english ? "\(name): 原样 query" : "\(name)：原样 query")
                        : (english ? "Open \(name)" : "打开 \(name)")
                    guard launcher.results.first?.title == title else { fatalError("website result localization mismatch") }
                }
                let controller = LauncherController(model: launcher)
                controller.show()
                guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) as? LauncherPanel else {
                    fatalError("missing launcher language panel")
                }
                panel.onBlur = {}
                launcher.query = "yt"
                try await Task.sleep(for: .milliseconds(350))
                guard let index = launcher.results.firstIndex(where: { $0.target.kind == "tab-search" }) else {
                    fatalError("missing tab search fallback")
                }
                launcher.selection = index
                guard let action = launcher.primaryLauncherAction,
                      NSLocalizedString(action.title, tableName: "Launcher", comment: "") == (english ? "Search Open Tabs" : "搜索开启的标签页") else {
                    fatalError("tab search footer localization mismatch")
                }
                try await Task.sleep(for: .milliseconds(200))
                guard let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    fatalError("missing launcher snapshot")
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/launcher-language-\(english ? "en" : "zh-Hans").png"))
                controller.hide()
                print("PASS: all search entry actions, website suggestions and query results, tab footer, launcher snapshot")
                EditMenu.install()
                guard NSApp.mainMenu?.items.last?.submenu?.title == (english ? "Edit" : "编辑") else {
                    fatalError("AppKit edit menu didn't localize")
                }
                let window = SettingsWindow.make(app: model)
                window.center()
                window.makeKeyAndOrderFront(nil)
                try await Task.sleep(for: .milliseconds(800))
                for page in SettingsPage.allCases {
                    model.settingsTab = page.rawValue
                    try await Task.sleep(for: .milliseconds(100))
                    let suffix = english ? "Asky Settings" : "Asky 设置"
                    guard window.title == "\(page.title) — \(suffix)" else { fatalError("window title didn't localize") }
                    try snapshot(window, name: "settings-\(page.rawValue)-\(english ? "en" : "zh-Hans")")
                }
                model.settingsTab = SettingsPage.general.rawValue
                try await Task.sleep(for: .milliseconds(300))
                guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    fatalError("missing native window snapshot")
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let png = try bitmap.representation(using: .png, properties: [:]).unwrap()
                try png.write(to: URL(filePath: "build/application-language-\(english ? "en" : "zh-Hans").png"))
                print("PASS: legacy migration, language persistence, system reset, native localization, all settings titles, native snapshot (\(Bundle.main.preferredLocalizations))")
                window.close()
                application.terminate(nil)
            } catch { fatalError("language regression: \(error)") }
        }
        application.run()
    }
}

private extension Optional {
    func unwrap() throws -> Wrapped {
        guard let value = self else { throw CocoaError(.fileWriteUnknown) }
        return value
    }
}
