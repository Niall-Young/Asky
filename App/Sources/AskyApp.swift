import AppKit
import SwiftUI
import Resources
import Carbon.HIToolbox
import ToolService
import Contracts

@main
@MainActor
enum AskyMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        _ = delegate
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var launcher: LauncherController!
    private var launcherModel: LauncherModel!
    private var agentWindow: AgentWindowController!
    private var clipboard: ClipboardMonitor!
    private var clipboardWindow: ClipboardController!
    private var clipboardHotKey: HotKey?
    private var reminders: ProactiveReminders!
    private var hotKey: HotKey?
    private var newAgentHotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var pressure: MemoryPressureMonitor?
    private let termination = ApplicationTermination()
    private let dockVisibility = DockVisibilityController()
    private let windowPresentation = WindowPresentation()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if CommandLine.arguments.contains("--diagnose-launcher") {
            runLauncherPresentationDiagnostic()
            return
        }
        if CommandLine.arguments.contains("--test-launcher-sheet") {
            ConfirmationPreviews.runLauncherSheet()
            return
        }
        if CommandLine.arguments.contains("--test-banner") || CommandLine.arguments.contains("--test-notification") {
            // Preview only: no app data, permissions, scheduler or AI runtime are started.
            ReminderBannerCenter.shared.showPreview()
            return
        }
        if CommandLine.arguments.contains("--test-confirmation-matrix") {
            ConfirmationPreviews.run()
            return
        }
        if CommandLine.arguments.contains("--test-image-attachments") {
            ChatImageAttachmentPreview.run()
            return
        }
        if CommandLine.arguments.contains("--test-confirmations") {
            // Exercise the real shared UI without starting the model or executing tools.
            NSApp.setActivationPolicy(.regular)
            let previewWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
                                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
            previewWindow.title = "Asky"
            previewWindow.center()
            previewWindow.makeKeyAndOrderFront(nil)
            let confirmations = ConfirmationCenter()
            Task { @MainActor in
                defer { previewWindow.close() }
                let reference = AppDialog.make()
                reference.messageText = "Save this message as a draft?"
                reference.informativeText = "This message has not been sent and contains unsaved changes. You can save it as a draft to work on later."
                reference.addButton(withTitle: "Save")
                reference.addButton(withTitle: "Delete").hasDestructiveAction = true
                reference.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
                NSApp.activate()
                _ = await AppDialog.present(reference, for: previewWindow)
                let previews: [(String, CallerOrigin)] = [
                    ("plugin_lark__execute", .agent(sessionID: "preview")),
                    ("calendar_update_event", .agent(sessionID: "preview")),
                    ("messages_prepare_draft", .agent(sessionID: "preview")),
                    ("notes_append", .mcp(instanceID: "preview"))
                ]
                for (tool, origin) in previews {
                    let decision = await confirmations.present(ConfirmationRequest(
                        requestID: UUID().uuidString, tool: tool,
                        target: tool == "plugin_lark__execute" ? "将通过「飞书」创建知识库内容。"
                            : tool == "calendar_update_event" ? "日程「产品评审」"
                            : tool == "messages_prepare_draft" ? "小李" : "备忘录「项目想法」",
                        changes: tool == "plugin_lark__execute" ? ["标题：项目说明"]
                            : tool == "calendar_update_event" ? ["地点：3 号会议室 → 5 号会议室"]
                            : tool == "messages_prepare_draft" ? ["草稿：我周末来看你。"]
                            : ["追加：下周先完成登录页面。"],
                        note: "这是预览，点击确认不会执行真实操作。",
                        argumentsDigest: "preview", origin: origin,
                        title: tool == "plugin_lark__execute" ? "通过飞书创建知识库内容？" : nil,
                        details: tool == "plugin_lark__execute" ? #"{"argv":["wiki","spaces","node-create","--data","{\"title\":\"示例\"}"]}"# : nil))
                    print("confirmation-preview \(tool): \(decision.rawValue)")
                }
                for title in ["安装可信插件", "安装新版本？", "图片下载失败"] {
                    let alert = AppDialog.make()
                    alert.messageText = NSLocalizedString(title, comment: "")
                    alert.informativeText = "样式预览：不会安装、更新或下载。"
                    alert.addButton(withTitle: NSLocalizedString("好", comment: ""))
                    NSApp.activate()
                    _ = await AppDialog.present(alert)
                }
                NSApp.terminate(nil)
            }
            return
        }
        #endif
        guard !AppInstallationPrompt.handleLaunchIfNeeded() else { return }
        do { model = try AppModel() } catch {
            let alert = AppDialog.make()
            alert.messageText = NSLocalizedString("Asky 无法打开本地数据", comment: "")
            alert.informativeText = "\(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        do { try model.initializeLaunchAtLogin() }
        catch { NSLog("Unable to initialize launch at login: %@", error.localizedDescription) }
        model.onOpenSettings = { [weak self] in self?.openSettings() }
        dockVisibility.showDockIcon = model.preferences.showDockIcon
        model.onDockIconVisibilityChange = { [weak self] visible in
            self?.dockVisibility.showDockIcon = visible
        }
        EditMenu.install()
        launcherModel = LauncherModel(app: model)
        launcher = LauncherController(model: launcherModel)
        launcher.onOpenSettings = { [weak self] in self?.openSettings() }
        agentWindow = AgentWindowController(model: AgentModel(app: model), presentation: windowPresentation)
        model.onModelAuthenticationStarted = { [weak self] in
            self?.agentWindow.prepareForAuthentication()
        }
        model.onModelAuthenticationFinished = { [weak self] in
            self?.agentWindow.restoreAfterAuthentication()
        }
        launcherModel.onAskAI = { [weak self] prompt in
            self?.launcher.hide()
            self?.agentWindow.show(prompt: prompt)
        }

        NSApp.appearance = model.preferences.appearance == "system" ? nil : NSAppearance(named: model.preferences.appearance == "dark" ? .darkAqua : .aqua)
        model.onHotKeyChange = { [weak self] code, modifiers in self?.registerHotKey(code: code, modifiers: modifiers) ?? false }
        _ = registerHotKey(code: model.preferences.hotKeyCode, modifiers: model.preferences.hotKeyModifiers)

        clipboardWindow = ClipboardController(app: model)
        model.onClipboardHotKeyChange = { [weak self] code, modifiers in self?.registerClipboardHotKey(code: code, modifiers: modifiers) ?? false }
        _ = registerClipboardHotKey(code: model.preferences.clipboardHotKeyCode, modifiers: model.preferences.clipboardHotKeyModifiers)
        model.onAgentHotKeyChange = { [weak self] code, modifiers in self?.registerAgentHotKey(code: code, modifiers: modifiers) ?? false }
        _ = registerAgentHotKey(code: model.preferences.agentHotKeyCode, modifiers: model.preferences.agentHotKeyModifiers)
        installStatusItem()
        model.onMenuBarIconVisibilityChange = { [weak self] visible in
            self?.statusItem?.isVisible = visible
        }
        clipboard = ClipboardMonitor(app: model)
        clipboard.start()
        reminders = ProactiveReminders(app: model)
        model.onSettingsChange = { [weak self] in self?.reminders.schedule() }
        model.updater.isQuiet = { [weak self] in self?.isQuietForUpdate ?? false }
        ToolService.removeStaleAppUpdates()
        pressure = MemoryPressureMonitor { [weak self] _ in
            Task { @MainActor in self?.launcher.hide() }
        }
        #if DEBUG
        if CommandLine.arguments.contains("--show-agent") { agentWindow.show() }
        if CommandLine.arguments.contains("--test-clipboard") {
            clipboardWindow.pinned = true
            clipboardWindow.show()
            clipboardWindow.query = ProcessInfo.processInfo.environment["ASKY_CLIPBOARD_TEST_QUERY"] ?? ""
        }
        #endif
        Task {
            await model.start()
            reminders.start()
        }
    }

    #if DEBUG
    /// Isolated renderer cold start: no live providers, permissions, updater or agent startup.
    private func runLauncherPresentationDiagnostic() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--diagnostic-root"), args.indices.contains(index + 1),
              args[index + 1].hasPrefix("/") else {
            NSLog("--diagnose-launcher requires an absolute --diagnostic-root")
            NSApp.terminate(nil)
            return
        }
        do {
            LauncherPresentationTrace.start()
            LauncherPresentationTrace.record("process-ready")
            model = try AppModel(root: URL(filePath: args[index + 1]))
            NSApp.appearance = NSAppearance(named: args.contains("--diagnostic-dark") ? .darkAqua : .aqua)
            launcherModel = LauncherModel(app: model, searchProviders: [])
            launcher = LauncherController(model: launcherModel)
            // Recording must not stop when another app owns focus during a test run.
            launcher.onOpenSettings = {}
            let displayID = args.firstIndex(of: "--diagnostic-screen").flatMap { index in
                args.indices.contains(index + 1) ? UInt32(args[index + 1]) : nil
            }
            let screen = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == displayID
            }
            Task { @MainActor in
                self.launcher.show(on: screen)
                try? await Task.sleep(for: .milliseconds(350))
                self.launcher.hide()
                try? await Task.sleep(for: .milliseconds(100))
                self.launcher.show(on: screen)
                try? await Task.sleep(for: .milliseconds(350))
                self.launcher.hide()
                NSApp.terminate(nil)
            }
        } catch {
            NSLog("Launcher diagnostic failed: %@", error.localizedDescription)
            NSApp.terminate(nil)
        }
    }
    #endif

    /// Silent relaunch only when nothing is open, running or waiting for the user.
    private var isQuietForUpdate: Bool {
        !launcher.isVisible && !clipboardWindow.isVisible && !agentWindow.isVisible && !agentWindow.model.isRunning
            && settingsWindow?.isVisible != true && model.confirmations.queue.isEmpty
            && !model.terminal.isRunning && !model.isMCPBusy
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard model != nil else { return true }
        if let settingsWindow, settingsWindow.isVisible {
            windowPresentation.show(settingsWindow)
        } else {
            openLauncher()
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        #if DEBUG
        if CommandLine.arguments.contains("--diagnose-launcher") { return .terminateNow }
        #endif
        guard let model else { return .terminateNow }
        return termination.request { [self] in
            clipboard?.stop()
            clipboardWindow?.hide()
            clipboardHotKey?.unregister()
            reminders?.stop()
            newAgentHotKey?.unregister()
            hotKey?.unregister()
            model.confirmations.rejectAll()
            // Pi and its process group must be gone before the app exits (no orphans).
            await model.shutdown()
        }
    }

    private func registerHotKey(code: UInt32, modifiers: UInt32) -> Bool {
        let previous = model.preferences
        hotKey?.unregister()
        do {
            hotKey = try HotKey(keyCode: code, modifiers: modifiers) { [weak self] in self?.launcher.toggle() }
            model.hotKeyStatus = NSLocalizedString("已注册", comment: "")
            return true
        } catch {
            model.hotKeyStatus = NSLocalizedString("组合键已被占用或无法注册，请选择其他快捷键。", comment: "")
            hotKey = try? HotKey(keyCode: previous.hotKeyCode, modifiers: previous.hotKeyModifiers) { [weak self] in self?.launcher.toggle() }
            return false
        }
    }

    private func registerClipboardHotKey(code: UInt32, modifiers: UInt32) -> Bool {
        let previous = model.preferences
        let action: () -> Void = { [weak self] in
            self?.launcher.hide()
            self?.clipboardWindow.toggle()
        }
        clipboardHotKey?.unregister()
        do {
            clipboardHotKey = try HotKey(keyCode: code, modifiers: modifiers, action: action)
            model.clipboardHotKeyStatus = NSLocalizedString("已注册", comment: "")
            return true
        } catch HotKey.Failure.alreadyInUse {
            model.clipboardHotKeyStatus = NSLocalizedString("组合键已被占用，请选择其他快捷键，或从菜单栏打开剪贴板。", comment: "")
        } catch {
            model.clipboardHotKeyStatus = String(format: NSLocalizedString("快捷键注册失败：%@。请选择其他快捷键，或从菜单栏打开剪贴板。", comment: ""), String(describing: error))
        }
        if code != previous.clipboardHotKeyCode || modifiers != previous.clipboardHotKeyModifiers {
            clipboardHotKey = try? HotKey(keyCode: previous.clipboardHotKeyCode, modifiers: previous.clipboardHotKeyModifiers, action: action)
        } else {
            clipboardHotKey = nil
        }
        return false
    }

    private func registerAgentHotKey(code: UInt32, modifiers: UInt32) -> Bool {
        let previous = model.preferences
        let action: () -> Void = { [weak self] in self?.openNewAgentConversation() }
        newAgentHotKey?.unregister()
        do {
            newAgentHotKey = try HotKey(keyCode: code, modifiers: modifiers, action: action)
            model.agentHotKeyStatus = NSLocalizedString("已注册", comment: "")
            return true
        } catch HotKey.Failure.alreadyInUse {
            model.agentHotKeyStatus = NSLocalizedString("组合键已被占用，请选择其他快捷键，或从菜单栏打开 AI 对话。", comment: "")
        } catch {
            model.agentHotKeyStatus = String(format: NSLocalizedString("快捷键注册失败：%@。请选择其他快捷键，或从菜单栏打开 AI 对话。", comment: ""), String(describing: error))
        }
        if code != previous.agentHotKeyCode || modifiers != previous.agentHotKeyModifiers {
            newAgentHotKey = try? HotKey(keyCode: previous.agentHotKeyCode, modifiers: previous.agentHotKeyModifiers, action: action)
        } else {
            newAgentHotKey = nil
        }
        return false
    }

    // MARK: Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(named: "StatusIcon")
        icon?.size = NSSize(width: 18, height: 18)
        icon?.isTemplate = true
        icon?.accessibilityDescription = "Asky"
        item.button?.image = icon
        item.button?.setAccessibilityLabel("Asky")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.isVisible = model.preferences.showMenuBarIcon
        statusItem = item
    }

    /// Rebuilt on every open so check marks always mirror the current settings.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        menu.removeAllItems()
        add(menu, "打开启动器", #selector(openLauncher))
        add(menu, "剪贴板历史", #selector(openClipboard))
        add(menu, "AI 对话", #selector(openAgent))
        menu.addItem(.separator())
        add(menu, "记录剪贴板历史", #selector(toggleClipboardRecording), on: model.settings.clipboardEnabled)
        add(menu, "允许 AI 搜索公开网页", #selector(toggleWebSearch), on: model.settings.webSearchEnabled != false)
        add(menu, "主动提醒", #selector(toggleProactiveReminders), on: model.settings.proactiveReminders)
        let approval = submenu(menu, "AI 审批模式")
        let mode = model.settings.approvalMode ?? .autoReview
        for (option, title) in [(ApprovalMode.autoReview, "自动审批"), (.fullAccess, "完全访问")] {
            add(approval, title, #selector(selectApprovalMode(_:)), on: mode == option).representedObject = option.rawValue
        }
        let appearance = submenu(menu, "外观")
        for (value, title) in [("system", "跟随系统"), ("light", "浅色"), ("dark", "深色")] {
            add(appearance, title, #selector(selectAppearance(_:)), on: model.preferences.appearance == value).representedObject = value
        }
        add(menu, "登录时启动", #selector(toggleLaunchAtLogin), on: ToolService.launchAtLoginEnabled)
        #if DEBUG
        add(menu, "预览提醒卡片", #selector(previewReminderBanner))
        #endif
        menu.addItem(.separator())
        add(menu, "设置…", #selector(openSettings), key: ",")
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: NSLocalizedString("退出 Asky", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        hideAutomaticImage(quit)
    }

    /// macOS 27 auto-attaches SF Symbols to items whose (English) titles it recognizes, e.g. "Settings…".
    private func hideAutomaticImage(_ item: NSMenuItem) {
        if #available(macOS 27.0, *) { item.preferredImageVisibility = .hidden }
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "", on: Bool? = nil) -> NSMenuItem {
        let item = menu.addItem(withTitle: NSLocalizedString(title, comment: ""), action: action, keyEquivalent: key)
        item.target = self
        if let on { item.state = on ? .on : .off }
        hideAutomaticImage(item)
        return item
    }

    private func submenu(_ menu: NSMenu, _ title: String) -> NSMenu {
        let item = menu.addItem(withTitle: NSLocalizedString(title, comment: ""), action: nil, keyEquivalent: "")
        hideAutomaticImage(item)
        let sub = NSMenu()
        item.submenu = sub
        return sub
    }

    @objc private func toggleClipboardRecording() { model.settings.clipboardEnabled.toggle() }
    @objc private func toggleWebSearch() { model.settings.webSearchEnabled = model.settings.webSearchEnabled == false }
    @objc private func toggleProactiveReminders() { model.settings.proactiveReminders.toggle() }
    #if DEBUG
    @objc private func previewReminderBanner() { ReminderBannerCenter.shared.showPreview() }
    #endif
    @objc private func selectApprovalMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = ApprovalMode(rawValue: raw) else { return }
        model.settings.approvalMode = mode
    }
    @objc private func selectAppearance(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        model.preferences.appearance = value
    }
    @objc private func toggleLaunchAtLogin() {
        do {
            try ToolService.setLaunchAtLogin(!ToolService.launchAtLoginEnabled)
        } catch {
            let alert = AppDialog.make()
            alert.messageText = NSLocalizedString("无法更改登录时启动", comment: "")
            alert.informativeText = error.localizedDescription
            NSApp.activate()
            Task { @MainActor in await AppDialog.present(alert) }
        }
    }

    @objc private func openLauncher() { clipboardWindow.hide(); launcher.show() }
    @objc private func openClipboard() { launcher.hide(); clipboardWindow.show() }
    @objc private func openAgent() {
        launcher.hide()
        agentWindow.show()
    }

    private func openNewAgentConversation() {
        launcher.hide()
        clipboardWindow.hide()
        agentWindow.showNewConversation()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let w = SettingsWindow.make(app: model)
            w.level = .normal
            w.collectionBehavior = [.moveToActiveSpace, .primary]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        launcher.hide()
        clipboardWindow.hide()
        if let settingsWindow { windowPresentation.show(settingsWindow) }
    }
}
