import SwiftUI
import Carbon.HIToolbox
import Contracts
import LocalStore
import DirectActions
import Memory
import MCPGateway
import Adapters
import Theme
import ToolService

struct SettingsView: View {
    @Bindable var app: AppModel
    var body: some View {
        Group {
            switch SettingsPage.resolve(app.settingsTab) {
            case .model: SettingsForm {
                ModelSettingsView(app: app)
                ConversationHistorySettings(app: app)
                MemorySettings(app: app)
                MCPSettings(app: app)
            }
            case .hotkey: HotKeySettings(app: app)
            case .aliases: AliasSettings(app: app)
            case .keywords: CommandSettings(app: app)
            case .terminal: TerminalSettings(app: app)
            case .general: GeneralSettings(app: app)
            case .search: SearchNavigationSettings(app: app)
            case .clipboard: ClipboardSettings(app: app)
            case .sources: SourceSettings(app: app)
            case .permissions: PermissionSettings(app: app)
            case .plugins: PluginSettings(app: app)
            case .about: AboutSettings(app: app)
            case .author: AuthorSettings()
            }
        }
        .toggleStyle(.switch)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HotKeySettings: View {
    @Bindable var app: AppModel
    var body: some View {
        SettingsForm {
            Section {
                shortcutRow("唤起启动器", label: app.preferences.hotKeyLabel, status: app.hotKeyStatus,
                            apply: setLauncher) { setLauncher(UInt32(kVK_Space), UInt32(optionKey), "⌥ Space") }
                shortcutRow("打开剪贴板历史", label: app.preferences.clipboardHotKeyLabel, status: app.clipboardHotKeyStatus,
                            apply: setClipboard) {
                    let d = SettingsPreferences.defaultClipboardHotKey
                    return setClipboard(d.code, d.modifiers, d.label)
                }
                shortcutRow("打开 AI 对话", label: app.preferences.agentHotKeyLabel, status: app.agentHotKeyStatus,
                            apply: setAgent) {
                    let d = SettingsPreferences.defaultAgentHotKey
                    return setAgent(d.code, d.modifiers, d.label)
                }
            } header: {
                Text(NSLocalizedString("全局快捷键", comment: ""))
            }
            Section {
                localRows([.settings])
            } header: {
                Text(NSLocalizedString("通用", comment: ""))
            }
            Section {
                localRows([.reveal, .copyPath, .copyFile, .copyName, .fileInfo])
            } header: {
                Text(NSLocalizedString("文件与应用", comment: ""))
            }
            Section {
                localRows([.askAI, .launcherMore, .windowPreviousDisplay, .windowNextDisplay])
            } header: {
                Text(NSLocalizedString("启动器", comment: ""))
            }
            Section {
                localRows([.clipboardCopy, .delete, .clipboardMore])
            } header: {
                Text(NSLocalizedString("剪贴板历史", comment: ""))
            }
            Section {
                localRows([.closeChat])
            } header: {
                Text(NSLocalizedString("AI 对话", comment: ""))
            }
        }.formStyle(.grouped)
    }

    private func localRows(_ actions: [LocalShortcutAction]) -> some View {
        ForEach(actions) { action in
            shortcutRow(action.title, label: app.preferences.shortcut(action).label,
                        allowsPlainKey: true, apply: { code, modifiers, label in
                app.preferences.setShortcut(action, .init(code: code, modifiers: modifiers, label: label))
            }, reset: {
                app.preferences.setShortcut(action, action.defaultShortcut)
            })
        }
    }

    private func shortcutRow(_ title: String, label: String, status: String = "", allowsPlainKey: Bool = false,
                             apply: @escaping (UInt32, UInt32, String) -> Bool,
                             reset: @escaping () -> Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(NSLocalizedString(title, comment: ""))
                Spacer()
                HotKeyRecorder(label: label, allowsPlainKey: allowsPlainKey, apply: apply).frame(width: 180, height: 30)
                SettingsButton(NSLocalizedString("恢复默认", comment: "")) { _ = reset() }
            }
            if !status.isEmpty, status != NSLocalizedString("已注册", comment: "") {
                Text(status).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private func conflictsWithLocal(_ code: UInt32, _ modifiers: UInt32) -> Bool {
        LocalShortcutAction.allCases.contains {
            let shortcut = app.preferences.shortcut($0)
            return shortcut.code == code && shortcut.modifiers == modifiers
        }
    }

    @discardableResult private func setAgent(_ code: UInt32, _ modifiers: UInt32, _ label: String) -> Bool {
        guard !conflictsWithLocal(code, modifiers), app.onAgentHotKeyChange?(code, modifiers) == true else { return false }
        app.preferences.agentHotKeyCode = code
        app.preferences.agentHotKeyModifiers = modifiers
        app.preferences.agentHotKeyLabel = label
        return true
    }

    @discardableResult private func setLauncher(_ code: UInt32, _ modifiers: UInt32, _ label: String) -> Bool {
        guard !conflictsWithLocal(code, modifiers), app.onHotKeyChange?(code, modifiers) == true else { return false }
        app.preferences.hotKeyCode = code
        app.preferences.hotKeyModifiers = modifiers
        app.preferences.hotKeyLabel = label
        return true
    }

    @discardableResult private func setClipboard(_ code: UInt32, _ modifiers: UInt32, _ label: String) -> Bool {
        guard !conflictsWithLocal(code, modifiers), app.onClipboardHotKeyChange?(code, modifiers) == true else { return false }
        app.preferences.clipboardHotKeyCode = code
        app.preferences.clipboardHotKeyModifiers = modifiers
        app.preferences.clipboardHotKeyLabel = label
        return true
    }
}

private struct HotKeyRecorder: View {
    let label: String
    let allowsPlainKey: Bool
    let apply: (UInt32, UInt32, String) -> Bool

    var body: some View {
        HotKeyRecorderControl(label: label, allowsPlainKey: allowsPlainKey, apply: apply)
            .fixedSize()
    }
}

private struct HotKeyRecorderControl: NSViewRepresentable {
    let label: String
    let allowsPlainKey: Bool
    let apply: (UInt32, UInt32, String) -> Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func makeNSView(context: Context) -> Recorder { Recorder(label: label, allowsPlainKey: allowsPlainKey, apply: apply) }
    func updateNSView(_ view: Recorder, context: Context) {
        if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial,
           !reduceTransparency, contrast != .increased {
            view.bezelStyle = .glass
            view.borderShape = .capsule
        } else {
            view.bezelStyle = .rounded
            if #available(macOS 26, *) { view.borderShape = .automatic }
        }
        view.label = label
        view.apply = apply
        view.allowsPlainKey = allowsPlainKey
        if !view.recording { view.title = label }
        view.setAccessibilityLabel(String(format: NSLocalizedString("快捷键 %@，点击录制", comment: ""), label))
    }
    final class Recorder: NSButton {
        var label: String
        var apply: (UInt32, UInt32, String) -> Bool
        var allowsPlainKey: Bool
        var recording = false
        override var acceptsFirstResponder: Bool { true }
        init(label: String, allowsPlainKey: Bool, apply: @escaping (UInt32, UInt32, String) -> Bool) {
            self.label = label
            self.allowsPlainKey = allowsPlainKey
            self.apply = apply
            super.init(frame: .zero)
            bezelStyle = .rounded
            target = self
            action = #selector(begin)
            title = label
            toolTip = NSLocalizedString("录制快捷键", comment: "")
            setAccessibilityLabel(String(format: NSLocalizedString("快捷键 %@，点击录制", comment: ""), label))
        }
        required init?(coder: NSCoder) { fatalError() }
        @objc func begin() { recording = true; title = NSLocalizedString("按下组合键，Esc 取消", comment: ""); window?.makeFirstResponder(self) }
        override func resignFirstResponder() -> Bool {
            recording = false
            title = label
            return super.resignFirstResponder()
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }
        override func keyDown(with event: NSEvent) {
            guard recording else { return }
            if event.keyCode == 53 { window?.makeFirstResponder(nil); return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard allowsPlainKey || !flags.intersection([.command, .option, .control]).isEmpty else {
                title = NSLocalizedString("请包含 ⌘、⌥ 或 ⌃", comment: ""); return
            }
            var modifiers: UInt32 = 0
            var label = ""
            for (flag, carbon, symbol) in [(NSEvent.ModifierFlags.control, controlKey, "⌃"), (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")] {
                if flags.contains(flag) { modifiers |= UInt32(carbon); label += symbol }
            }
            label += (label.isEmpty ? "" : " ") + Self.keyName(event)
            if apply(event.keyCode == 76 ? 36 : UInt32(event.keyCode), modifiers, label) {
                window?.makeFirstResponder(nil)
            } else {
                title = NSLocalizedString("已被占用，换一个组合键", comment: "")
            }
        }
        // charactersIgnoringModifiers is mangled by ⌥ (e.g. ⌥V → √), so use the layout-independent key name where possible.
        static func keyName(_ event: NSEvent) -> String {
            let special: [Int: String] = [kVK_Space: "Space", kVK_Return: "Return", kVK_ANSI_KeypadEnter: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
                                          kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
                                          kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
                                          kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"]
            if let name = special[Int(event.keyCode)] { return name }
            let chars = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? ""
            return chars.isEmpty ? "Key \(event.keyCode)" : chars.uppercased()
        }
    }
}

// MARK: General

private struct GeneralSettings: View {
    @Bindable var app: AppModel
    @State private var launchAtLogin = ToolService.launchAtLoginEnabled
    @State private var loginError: String?

    var body: some View {
        SettingsForm {
            Section(NSLocalizedString("启动", comment: "")) {
                Toggle(NSLocalizedString("显示菜单栏图标", comment: ""), isOn: $app.preferences.showMenuBarIcon)
                Toggle(NSLocalizedString("在 Dock 栏显示", comment: ""), isOn: $app.preferences.showDockIcon)
                Toggle(NSLocalizedString("登录时启动", comment: ""), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { try ToolService.setLaunchAtLogin(on); loginError = nil }
                        catch { loginError = error.localizedDescription; launchAtLogin = !on }
                    }
                if let loginError { Text(loginError).foregroundStyle(ThemeColor.kTextNegative) }
            }
            Section(NSLocalizedString("外观", comment: "")) {
                LabeledContent(NSLocalizedString("应用主题", comment: "")) {
                    SettingsChoice(selection: $app.preferences.appearance, options: [
                        ("system", NSLocalizedString("跟随系统", comment: "")),
                        ("light", NSLocalizedString("浅色", comment: "")),
                        ("dark", NSLocalizedString("深色", comment: ""))
                    ]).fixedSize()
                }
                if SurfaceCompatibility.supportsLiquidGlass {
                    LabeledContent {
                        Toggle("", isOn: $app.preferences.liquidGlass).labelsHidden()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("液态玻璃", comment: ""))
                            Text(NSLocalizedString("关闭后使用背景模糊与描边", comment: ""))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent {
                    SettingsChoice(selection: $app.preferences.language, options: [
                        (ApplicationLanguage.system, NSLocalizedString("跟随系统", comment: "")),
                        (ApplicationLanguage.simplifiedChinese, "简体中文"),
                        (ApplicationLanguage.english, "English")
                    ]).fixedSize()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("应用语言", comment: ""))
                        Text(NSLocalizedString("语言更改将在下次启动应用时生效。跟随系统会使用 macOS 的首选语言", comment: ""))
                            .foregroundStyle(.secondary)
                    }
                }
                if app.preferences.language != app.launchLanguage {
                    Text(NSLocalizedString("已保存，下次启动生效。", comment: ""))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SearchNavigationSettings: View {
    @Bindable var app: AppModel

    var body: some View {
        SettingsForm {
            Section(NSLocalizedString("文件搜索范围", comment: "")) {
                SettingsEditableList(title: NSLocalizedString("包含的文件夹", comment: ""),
                                     emptyText: NSLocalizedString("尚未添加搜索目录", comment: ""),
                                     systemImage: "folder",
                                     items: $app.settings.fileScopes) {
                    await ToolService.chooseLauncherSearchFolder()?.path
                }
                SettingsExclusionList(title: NSLocalizedString("排除的目录名", comment: ""),
                                      selection: .directory,
                                      items: $app.settings.excludedDirectories)
            }
            Section(NSLocalizedString("文件夹导航", comment: "")) {
                LabeledContent(NSLocalizedString("输入框为空时按退格键", comment: "")) {
                    SettingsChoice(selection: $app.preferences.folderBackspaceBehavior, options: [
                        (FolderBackspaceBehavior.parent, NSLocalizedString("返回上一层", comment: "")),
                        (FolderBackspaceBehavior.exitNavigation, NSLocalizedString("退出文件夹导航", comment: ""))
                    ]).fixedSize()
                }
            }
        }
    }
}

private struct ClipboardSettings: View {
    @Bindable var app: AppModel

    var body: some View {
        SettingsForm {
            Section(NSLocalizedString("剪贴板", comment: "")) {
                Toggle(NSLocalizedString("记录剪贴板历史", comment: ""), isOn: $app.settings.clipboardEnabled)
                LabeledContent(NSLocalizedString("历史保留时间", comment: "")) {
                    SettingsChoice(selection: $app.settings.clipboardRetention, options: [
                        (ClipboardRetention.eightHours, NSLocalizedString("8 小时", comment: "")),
                        (ClipboardRetention.oneDay, NSLocalizedString("1 天", comment: "")),
                        (ClipboardRetention.threeDays, NSLocalizedString("3 天", comment: "")),
                        (ClipboardRetention.sevenDays, NSLocalizedString("7 天", comment: "")),
                        (ClipboardRetention.thirtyDays, NSLocalizedString("30 天", comment: ""))
                    ]).fixedSize()
                }
                SettingsExclusionList(title: NSLocalizedString("排除的应用 Bundle ID", comment: ""),
                                      selection: .application,
                                      items: $app.settings.clipboardExcludedApps)
                SettingsButton(NSLocalizedString("清空未固定的剪贴板历史", comment: ""), role: .destructive) {
                    let store = app.clipboardStore
                    let ids = store.recent(limit: 100_000).filter { !$0.pinned }.map(\.id)
                    ClipboardMonitor.removeFiles((try? store.delete(ids: ids)) ?? [])
                }
            }
        }
    }
}

// MARK: Sources

private struct SourceSettings: View {
    @Bindable var app: AppModel
    @State private var availableFolders: [NotesFolder] = []
    @State private var loadingFolders = false
    @State private var foldersLoaded = false
    @State private var folderError: String?

    private var displayedFolders: [NotesFolder] {
        availableFolders + app.settings.notesFolders.filter { !availableFolders.contains($0) }
    }

    private func connectNotes() async {
        guard !loadingFolders else { return }
        loadingFolders = true
        folderError = nil
        defer { loadingFolders = false }
        app.settings.enabledSources.insert(.notes)
        let result = await app.tools.submit(ActionRequest(tool: "notes_list_folders", arguments: .object([:]),
                                                         origin: .launcher, intent: .explicitRequest))
        guard result.status == .completed, let output = result.output else {
            folderError = result.error?.message ?? NSLocalizedString("无法读取备忘录文件夹，请重试。", comment: "")
            return
        }
        do {
            availableFolders = try JSONDecoder().decode([NotesFolder].self, from: output.canonicalData())
            foldersLoaded = true
            // Refresh identifiers for existing selections without expanding their access scope.
            app.settings.notesFolders = app.settings.notesFolders.map { saved in
                availableFolders.first(where: { $0.matchesLocation(saved) }) ?? saved
            }
        } catch {
            folderError = NSLocalizedString("无法读取备忘录文件夹，请重试。", comment: "")
        }
    }

    static let labels: [(DataSourceID, String)] = [
        (.calendar, NSLocalizedString("日历", comment: "")), (.reminders, NSLocalizedString("提醒事项", comment: "")), (.notes, NSLocalizedString("备忘录", comment: "")), (.contacts, NSLocalizedString("通讯录", comment: "")), (.chrome, NSLocalizedString("Chrome 标签与书签", comment: "")),
        (.shortcuts, NSLocalizedString("快捷指令", comment: "")), (.messages, NSLocalizedString("信息（查询与草稿交接）", comment: "")), (.memory, NSLocalizedString("个人记忆", comment: "")), (.maps, NSLocalizedString("路线时间（MapKit）", comment: "")),
    ]

    var body: some View {
        SettingsForm {
            Section(NSLocalizedString("AI 与工具可使用的来源", comment: "")) {
                ForEach(Self.labels, id: \.0) { id, label in
                    Toggle(isOn: Binding(
                        get: { app.settings.enabledSources.contains(id) },
                        set: { on in if on { app.settings.enabledSources.insert(id) } else { app.settings.enabledSources.remove(id) } })) {
                        HStack(spacing: 8) {
                            sourceIcon(id)
                                .frame(width: 24, height: 24)
                                .accessibilityHidden(true)
                            Text(label)
                        }
                    }
                }
            }
            Text(NSLocalizedString("开启 MapKit 后，地点搜索与路线查询会向地图服务发送必要地点；无需 API Key，不会自动获取当前位置", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
            Section(NSLocalizedString("联网搜索", comment: "")) {
                Toggle(NSLocalizedString("允许 AI 搜索公开网页", comment: ""), isOn: Binding(
                    get: { app.settings.webSearchEnabled != false },
                    set: { app.settings.webSearchEnabled = $0 }))
            }
            Section(NSLocalizedString("授权的备忘录文件夹", comment: "")) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsListHeader(title: NSLocalizedString("允许访问的文件夹", comment: "")) {
                        if loadingFolders { ProgressView().controlSize(.small) }
                        SettingsButton(NSLocalizedString(foldersLoaded ? "刷新" : "连接", comment: ""),
                                       systemImage: foldersLoaded ? "arrow.clockwise" : "link") {
                            Task { await connectNotes() }
                        }
                        .accessibilityLabel(NSLocalizedString(foldersLoaded ? "刷新文件夹" : "连接备忘录", comment: ""))
                        .disabled(loadingFolders)
                    }
                    SettingsInsetBox {
                        if displayedFolders.isEmpty {
                            Text(NSLocalizedString(foldersLoaded ? "未找到文件夹，请先在 Apple 备忘录中添加账户或创建文件夹，再刷新。" : "连接备忘录后，选择允许 AI 访问的文件夹", comment: ""))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(Set(displayedFolders.map(\.account))).sorted(), id: \.self) { account in
                            Text(account).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                                .padding(.top, 4)
                            ForEach(displayedFolders.filter { $0.account == account }, id: \.self) { folder in
                                Toggle(isOn: Binding(
                                    get: { app.settings.notesFolders.contains(folder) },
                                    set: { selected in
                                        app.settings.notesFolders.removeAll { $0 == folder }
                                        if selected { app.settings.notesFolders.append(folder) }
                                    })) {
                                    HStack {
                                        Label { Text(folder.folder) } icon: { Image(mingCute: "folder") }
                                        if foldersLoaded && !availableFolders.contains(folder) {
                                            Text(NSLocalizedString("未找到，请取消选择或刷新", comment: "")).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                if let folderError {
                    Text(folderError).foregroundStyle(.red)
                    SettingsButton(NSLocalizedString("打开自动化权限设置…", comment: "")) {
                        do { try SystemPermissions.openSettings(.automation) }
                        catch { self.folderError = error.localizedDescription }
                    }
                }
            }

            Section(NSLocalizedString("情境提醒", comment: "")) {
                Toggle(NSLocalizedString("主动提醒（冲突、出行准备、重要日期）", comment: ""), isOn: $app.settings.proactiveReminders)
                Toggle(NSLocalizedString("后台 AI 判断（默认关闭）", comment: ""), isOn: $app.settings.backgroundAI)
            }
            Section(NSLocalizedString("短信读取", comment: "")) {
                Toggle(NSLocalizedString("让 AI 读取短信与 iMessage", comment: ""), isOn: Binding(
                    get: { app.settings.advisorReadsMessages ?? false },
                    set: { app.settings.advisorReadsMessages = $0 }))
                if app.settings.advisorReadsMessages == true {
                    LabeledContent(NSLocalizedString("读取时间范围", comment: "")) {
                        SettingsChoice(selection: Binding(
                            get: { app.settings.messagesLookback },
                            set: { app.settings.messagesLookbackDays = $0 }),
                            options: AppSettings.messagesLookbackChoices.map {
                                ($0, String(format: NSLocalizedString("最近 %d 天", comment: ""), $0))
                            })
                    }
                }
            }
        }
    }

    @ViewBuilder private func sourceIcon(_ source: DataSourceID) -> some View {
        DataSourceIcon(source: source)
            // The bundled logo has no native Icon Services drop shadow.
            .shadow(color: .black.opacity(source == .memory ? 0.22 : 0), radius: 1, x: 0, y: 1)
            .overlay {
                if source == .chrome || source == .memory {
                    // Preserve the native plate and shadow. Enlarge only the central
                    // mark, whose white inset is much larger than the filled app tiles.
                    DataSourceIcon(source: source)
                        .frame(width: 24, height: 24)
                        .scaleEffect(source == .chrome ? 1.14 : 1.4)
                        .frame(width: 18, height: 18)
                        .clipShape(Circle())
                }
            }
    }
}

// MARK: Model

private struct ModelSettingsView: View {
    let app: AppModel
    @State private var draft = ModelConfigurationDraft(provider: "custom", baseURL: nil, model: nil)
    @State private var key = ""
    @State private var message: String?
    @State private var capabilities: ModelCapabilities?
    @State private var checking = false
    @State private var saving = false
    @State private var checked = false
    @State private var checkFailed = false

    var body: some View {
        Section(NSLocalizedString("供应商与模型", comment: "")) {
            LabeledContent(NSLocalizedString("供应商", comment: "")) {
                SettingsChoice(selection: Binding(get: { draft.provider }, set: { value in
                    draft.select(value)
                    key = ""
                    message = nil
                    checked = false
                }), options: ModelProviderPreset.all.map { ($0.id, NSLocalizedString($0.name, comment: "")) } + [
                    ("custom", NSLocalizedString("完全自定义（OpenAI 兼容）", comment: ""))
                ])
            }
            // Lifecycle lives on a row: modifiers on this multi-section body would repeat per section.
            .task(id: checked) {
                guard checked else { return }
                do { try await Task.sleep(for: .milliseconds(1500)); checked = false }
                catch { }
            }
            .onAppear {
                draft = ModelConfigurationDraft(provider: app.preferences.provider,
                    baseURL: app.modelConfiguration?.baseURL.absoluteString, model: app.modelConfiguration?.modelName)
            }
            if let preset = ModelProviderPreset.find(draft.provider) {
                LabeledContent(NSLocalizedString("模型", comment: "")) {
                    SettingsChoice(selection: $draft.model, options: preset.models.map { ($0, $0) })
                }
                LabeledContent(NSLocalizedString("API 地址", comment: "")) {
                    Text(preset.baseURL).font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary).textSelection(.enabled)
                }
            } else {
                SettingsTextField(NSLocalizedString("API 地址", comment: ""), text: $draft.baseURL, prompt: Text("https://api.example.com/v1"))
                SettingsTextField(NSLocalizedString("模型名", comment: ""), text: $draft.model)
                Text(NSLocalizedString("填写 OpenAI 兼容的基础地址，不要包含 /chat/completions；模型名需与服务商提供的名称一致", comment: ""))
                    .foregroundStyle(.secondary)
            }
            SettingsSecureField(NSLocalizedString("API Key", comment: ""), text: $key,
                                prompt: Text(NSLocalizedString(canReuseKey ? "已保存，留空不变" : "输入 API Key", comment: "")))
            HStack {
                Text(statusText).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                SettingsButton(actionTitle, isLoading: saving || checking, isComplete: checked,
                               loadingTitle: NSLocalizedString(saving ? "保存中…" : "检查中…", comment: "")) {
                    Task { await saveAndCheck() }
                }
                .disabled(saving || checking || checked)
                .accessibilityLabel(checked ? NSLocalizedString("检查完成", comment: "") : actionTitle)
            }
            if let message { Text(message).foregroundStyle(ThemeColor.kTextNegative) }
        }
        .disabled(saving || checking)
        if matchesSavedConfiguration, let c = capabilities ?? app.modelConfiguration?.capabilities {
            Section(NSLocalizedString("模型能力", comment: "")) {
                LabeledContent(NSLocalizedString("文本", comment: ""), value: capabilityLabel(c.text))
                LabeledContent(NSLocalizedString("工具调用", comment: ""), value: capabilityLabel(c.tools))
                LabeledContent(NSLocalizedString("图像输入", comment: ""), value: capabilityLabel(c.image))
            }
        }
    }

    private var canReuseKey: Bool {
        draft.canReuseCredential(savedBaseURL: app.modelConfiguration?.baseURL.absoluteString)
    }

    private var matchesSavedConfiguration: Bool {
        guard let configuration = app.modelConfiguration else { return false }
        return canReuseKey && draft.model == configuration.modelName && key.isEmpty
    }

    private var actionTitle: String {
        NSLocalizedString(matchesSavedConfiguration ? "重新检查" : "保存并检查", comment: "")
    }

    private var statusText: String {
        if app.modelConfiguration == nil { return NSLocalizedString("尚未配置模型", comment: "") }
        return NSLocalizedString(matchesSavedConfiguration ? "当前配置已生效" : "有未保存的更改", comment: "")
    }

    private func saveAndCheck() async {
        if !matchesSavedConfiguration {
            guard await save() else { return }
        }
        await check()
    }

    private func capabilityLabel(_ value: CapabilityStatus) -> String {
        switch value {
        case .available: NSLocalizedString("可用", comment: "")
        case .unavailable: NSLocalizedString("不可用", comment: "")
        case .unknown: checkFailed ? NSLocalizedString("检查失败", comment: "") : NSLocalizedString("未检查", comment: "")
        }
    }

    @discardableResult
    private func save() async -> Bool {
        message = nil
        key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        saving = true
        defer { saving = false }
        guard let url = URL(string: draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host)),
              !draft.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = NSLocalizedString("请填写有效的 https 地址与模型名。", comment: "")
            return false
        }
        do {
            if let agent = app.agent, await agent.state == .busy {
                message = NSLocalizedString("请等待当前 AI 任务结束后保存模型设置。", comment: ""); return false
            }
            let account = app.modelConfiguration?.credentialRef ?? ModelSettings.keyAccount
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (canReuseKey && app.keychain.contains(account: account)) else {
                message = NSLocalizedString("请填写此服务商的 API Key；切换 API 地址后不能沿用原来的 Key。", comment: "")
                return false
            }
            if !key.isEmpty {
                key = key.trimmingCharacters(in: .whitespacesAndNewlines)
                try app.keychain.set(key, account: account)
                await app.credentialSession.remember(key, account: account)
            }
            app.preferences.provider = draft.provider
            app.modelConfiguration = ModelConfiguration(baseURL: url, modelName: draft.model.trimmingCharacters(in: .whitespacesAndNewlines), credentialRef: account)
            key = ""
            await app.agent?.shutdown()
            capabilities = nil
            checkFailed = false
            return true
        } catch {
            message = String(format: NSLocalizedString("钥匙串写入失败：%@", comment: ""), String(describing: error))
            return false
        }
    }

    private func check() async {
        guard var cfg = app.modelConfiguration else { return }
        message = nil
        checking = true
        defer { checking = false }
        do {
            guard let key = try await app.readModelCredential(account: cfg.credentialRef) else {
                message = NSLocalizedString("请先保存 API Key。", comment: ""); return
            }
            let report = await ModelCapabilityCheck.run(baseURL: cfg.baseURL, model: cfg.modelName, apiKey: key)
            cfg.capabilities = report.capabilities
            app.modelConfiguration = cfg
            capabilities = report.capabilities
            checkFailed = !report.failures.isEmpty
            message = report.failures.isEmpty ? nil : report.failures.joined(separator: "\n")
            checked = true
        } catch { message = error.localizedDescription }
    }

}

private struct ConversationHistorySettings: View {
    @Bindable var app: AppModel

    var body: some View {
        Section(NSLocalizedString("对话历史", comment: "")) {
            LabeledContent(NSLocalizedString("保留时间", comment: "")) {
                SettingsChoice(selection: $app.settings.conversationRetention, options: [
                    (.sevenDays, NSLocalizedString("7 天", comment: "")),
                    (.thirtyDays, NSLocalizedString("30 天", comment: "")),
                    (.ninetyDays, NSLocalizedString("90 天", comment: "")),
                    (.forever, NSLocalizedString("永久", comment: ""))
                ]).fixedSize()
            }
            SettingsButton(NSLocalizedString("清空对话历史", comment: ""), role: .destructive) {
                Task { await app.clearConversationHistory() }
            }.disabled(app.isCleaningConversationHistory || !app.activeConversationIDs.isEmpty)
            if let error = app.conversationCleanupError {
                Text(error).foregroundStyle(.red)
            }
        }
    }
}

// MARK: Memory

private struct MemorySettings: View {
    @Bindable var app: AppModel

    var body: some View {
        Section(NSLocalizedString("记忆", comment: "")) {
            Toggle(NSLocalizedString("开启记忆", comment: ""), isOn: Binding(
                get: { !app.settings.memoryExtractionPaused },
                set: { app.settings.memoryExtractionPaused = !$0 }
            ))
            Button {
                try? app.memory.ensureExists()
                NSWorkspace.shared.activateFileViewerSelecting([app.memory.indexURL])
            } label: {
                LabeledContent {
                    Image(mingCute: "arrow.up.forward.app").foregroundStyle(.secondary)
                } label: {
                    Text(NSLocalizedString("记忆文件", comment: ""))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: External MCP

private struct MCPSettings: View {
    @Bindable var app: AppModel
    @State private var instances: [MCPInstance] = []
    @State private var newName = ""
    @State private var issued: (name: String, credential: String)?
    @State private var error: String?

    /// Never exposed externally regardless of instance settings.
    static let exposable: [DataSourceID] = [.calendar, .reminders, .notes, .contacts, .chrome, .shortcuts, .messages]

    var body: some View {
        Section(NSLocalizedString("外部 MCP", comment: "")) {
            LabeledContent(NSLocalizedString("本地连接", comment: ""), value: app.isMCPListening ? NSLocalizedString("监听中", comment: "") : NSLocalizedString("未监听（无已启用实例）", comment: ""))
                .onAppear(perform: reload)
            if let e = app.mcpServerError { Text(e).foregroundStyle(ThemeColor.kTextNegative) }
        }
        if let issued {
            Section(String(format: NSLocalizedString("新实例“%@”的配置（凭据只显示这一次）", comment: ""), issued.name)) {
                Text(Self.configSnippet(credential: issued.credential))
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                HStack(spacing: 12) {
                    SettingsButton(NSLocalizedString("复制配置", comment: "")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.configSnippet(credential: issued.credential), forType: .string)
                    }
                    SettingsButton(NSLocalizedString("我已保存", comment: "")) { self.issued = nil }
                    Spacer()
                }
            }
        }
        Section(NSLocalizedString("MCP 实例", comment: "")) {
            ForEach($instances) { $inst in
                VStack(alignment: .leading) {
                    HStack {
                        Text(inst.name).textStyle(.button)
                        Spacer()
                        SettingsButton(NSLocalizedString("撤销", comment: ""), role: .destructive) {
                            try? MCPInstanceStore(app.store).delete(inst.id)
                            reload()
                        }
                    }
                    Toggle(NSLocalizedString("启用", comment: ""), isOn: $inst.enabled).onChange(of: inst.enabled) { save(inst) }
                    Toggle(NSLocalizedString("只读", comment: ""), isOn: $inst.readOnly).onChange(of: inst.readOnly) { save(inst) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), alignment: .leading)],
                              alignment: .leading, spacing: 12) {
                        ForEach(Self.exposable, id: \.self) { s in
                            SettingsCheckbox(title: s.rawValue, isOn: Binding(
                                get: { inst.sources.contains(s) },
                                set: { on in
                                    if on { inst.sources.append(s) } else { inst.sources.removeAll { $0 == s } }
                                    save(inst)
                                }))
                            .fixedSize()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            HStack(alignment: .settingsInput) {
                SettingsTextField(NSLocalizedString("实例名称（如 Claude Desktop）", comment: ""), text: $newName)
                SettingsButton(NSLocalizedString("创建", comment: "")) {
                    do {
                        let (inst, cred) = try app.gateway.register(name: newName.isEmpty ? NSLocalizedString("MCP 客户端", comment: "") : newName)
                        issued = (inst.name, cred)
                        newName = ""
                        reload()
                    } catch { self.error = "\(error)" }
                }
            }
            if let error { Text(error).foregroundStyle(ThemeColor.kTextNegative) }
        }
    }

    private func save(_ inst: MCPInstance) {
        try? MCPInstanceStore(app.store).update(inst)
        app.refreshMCPServer()
    }

    private func reload() {
        instances = MCPInstanceStore(app.store).all()
        app.refreshMCPServer()
    }

    static func configSnippet(credential: String) -> String {
        """
        {
          "mcpServers": {
            "asky": {
              "command": "\(AppModel.bridgeExecutablePath)",
              "env": { "ASKY_MCP_CREDENTIAL": "\(credential)" }
            }
          }
        }
        """
    }
}
