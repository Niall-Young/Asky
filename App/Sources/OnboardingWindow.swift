import AppKit
import Carbon.HIToolbox
import Combine
import Contracts
import SwiftUI
import Theme
import ToolService

/// First-launch welcome and setup window; shares the settings window's native glass backdrop.
@MainActor
enum OnboardingWindow {
    static let size = NSSize(width: 620, height: 536)

    static func make(app: AppModel, onFinish: @escaping () -> Void, onDismiss: @escaping () -> Void) -> NSWindow {
        let controller = OnboardingContainerController(app: app, onFinish: onFinish, onDismiss: onDismiss)
        let window = SettingsEditingWindow(contentRect: NSRect(origin: .zero, size: size),
                                           styleMask: [.titled, .closable, .fullSizeContentView],
                                           backing: .buffered, defer: false)
        window.animationBehavior = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentViewController = controller
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = NSLocalizedString("欢迎使用 Asky", comment: "")
        window.setContentSize(size)
        window.delegate = controller
        controller.updateAppearance()
        return window
    }
}

@MainActor
private final class OnboardingContainerController: NSViewController, NSWindowDelegate {
    private let app: AppModel
    private let onFinish: () -> Void
    private let onDismiss: () -> Void

    init(app: AppModel, onFinish: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.app = app
        self.onFinish = onFinish
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = LauncherLayout.shellCornerRadius
        view.layer?.masksToBounds = true
        let backdrop = NSHostingView(rootView: SettingsBackdrop().ignoresSafeArea())
        let content = NSHostingView(rootView: OnboardingView(app: app, onFinish: onFinish, onSkip: onDismiss) { [weak self] in
            self?.updateAppearance()
        })
        for child in [backdrop, content] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
            NSLayoutConstraint.activate([
                child.topAnchor.constraint(equalTo: view.topAnchor),
                child.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                child.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        }
    }

    func updateAppearance() {
        switch app.preferences.appearance {
        case "light": view.window?.appearance = NSAppearance(named: .aqua)
        case "dark": view.window?.appearance = NSAppearance(named: .darkAqua)
        default: view.window?.appearance = nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        if !app.preferences.hasCompletedOnboarding {
            app.preferences.hasCompletedOnboarding = true
        }
    }
}

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case permissions
    case shortcuts
    case ai

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .welcome: NSLocalizedString("欢迎", comment: "")
        case .permissions: NSLocalizedString("权限", comment: "")
        case .shortcuts: NSLocalizedString("快捷键", comment: "")
        case .ai: NSLocalizedString("AI 助手", comment: "")
        }
    }
}

struct OnboardingView: View {
    @Bindable var app: AppModel
    let onFinish: () -> Void
    let onSkip: () -> Void
    let onAppearanceChange: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var permissionModel = PermissionSettingsModel()
    @State private var requestingChrome = false
    @State private var draft = ModelConfigurationDraft(provider: "custom", baseURL: nil, model: nil)
    @State private var apiKey = ""
    @State private var modelMessage: String?
    @State private var savingModel = false
    @State private var checkingModel = false
    @State private var modelSaved = false
    @State private var editingModel = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 16)
            Rectangle()
                .fill(SettingsPalette.separator(scheme))
                .frame(height: 1)
            footerBar
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: OnboardingWindow.size.width, height: OnboardingWindow.size.height)
        .font(.system(size: 14))
        .foregroundStyle(ThemeColor.kText)
        .onAppear {
            loadModelDraft()
            Task { await refreshPermissions() }
        }
        .onChange(of: app.preferences.appearance) { _, _ in onAppearanceChange() }
        .onChange(of: step) { _, next in
            if next == .permissions { Task { await refreshPermissions() } }
            if next == .ai { loadModelDraft() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if step == .permissions { Task { await refreshPermissions() } }
        }
        .onReceive(permissionTimer) { _ in
            if step == .permissions && !requestingChrome {
                Task { await refreshPermissions() }
            }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases) { item in
                    Button { navigate(to: item) } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(item == step ? ThemeColor.kText.color(for: scheme)
                                      : item.rawValue < step.rawValue ? ThemeColor.kTextSubtle.color(for: scheme)
                                      : ThemeColor.kBorder.color(for: scheme))
                                .frame(width: 6, height: 6)
                            Text(item.label)
                                .font(.system(size: 12, weight: item == step ? .medium : .regular))
                                .foregroundStyle(item == step ? ThemeColor.kText : ThemeColor.kTextSubtlest)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(item == step ? ThemeColor.kBackgroundSelected.color(for: scheme) : Color.clear,
                                    in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.label)
                    .accessibilityAddTraits(item == step ? .isSelected : [])
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .padding(.top, 2)
        .compatibleWindowDrag()
    }

    // MARK: Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeStep
        case .permissions: permissionsStep
        case .shortcuts: shortcutsStep
        case .ai: aiStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image("AskyLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                Text(NSLocalizedString("欢迎使用 Asky", comment: ""))
                    .font(.system(size: 22, weight: .semibold))
                Text(NSLocalizedString("搜索、剪贴板与 AI，一个快捷键呼出", comment: ""))
                    .font(.system(size: 14))
                    .foregroundStyle(ThemeColor.kTextSubtle)
            }
            .padding(.top, 4)

            VStack(spacing: 0) {
                featureRow(icon: .applications,
                           title: NSLocalizedString("快速搜索", comment: ""),
                           subtitle: NSLocalizedString("本地检索应用、文件、窗口、书签与计算，不联网也能用", comment: ""),
                           shortcut: app.preferences.hotKeyLabel)
                divider
                featureRow(icon: .clipboardText,
                           title: NSLocalizedString("剪贴板历史", comment: ""),
                           subtitle: NSLocalizedString("自动记录文字、图片与文件，支持搜索、预览与快速粘贴", comment: ""),
                           shortcut: app.preferences.clipboardHotKeyLabel)
                divider
                featureRow(icon: .ai,
                           title: NSLocalizedString("AI 助手", comment: ""),
                           subtitle: NSLocalizedString("按需唤起的原生助手，自带 API Key 即可对话与调用系统工具", comment: ""),
                           shortcut: app.preferences.agentHotKeyLabel)
            }
            .background(SettingsPalette.card(scheme), in: RoundedRectangle(cornerRadius: 12))

            Text(NSLocalizedString("Asky 常驻顶部菜单栏，随时通过快捷键唤起", comment: ""))
                .font(.system(size: 12))
                .foregroundStyle(ThemeColor.kTextSubtlest)
        }
    }

    private func featureRow(icon: LauncherFunctionIcon.Kind, title: String, subtitle: String, shortcut: String) -> some View {
        HStack(spacing: 14) {
            LauncherFunctionIcon(kind: icon)
                .scaleEffect(1.15)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(ThemeColor.kTextSubtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            shortcutBadge(shortcut)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader(title: NSLocalizedString("授予常用权限", comment: ""),
                       subtitle: NSLocalizedString("只需按需授权，日历、提醒事项和备忘录会在首次使用时再请求", comment: ""))

            VStack(spacing: 0) {
                permissionRow(
                    symbol: "accessibility",
                    color: .blue,
                    title: NSLocalizedString("辅助功能", comment: ""),
                    badge: NSLocalizedString("推荐", comment: ""),
                    description: NSLocalizedString("用于剪贴板自动粘贴与应用窗口搜索", comment: ""),
                    authorized: permissionModel.states[.accessibility] == .authorized,
                    statusLabel: accessibilityStatusLabel
                ) {
                    SettingsButton(NSLocalizedString(permissionModel.states[.accessibility] == .authorized ? "重新授权" : "去授权", comment: "")) {
                        PermissionAuthorizationWindow.shared.show(.accessibility, colorScheme: scheme)
                    }
                }
                divider
                permissionRow(
                    symbol: "bookmark",
                    color: ToolIconPalette.orange,
                    title: NSLocalizedString("Chrome 书签与链接", comment: ""),
                    badge: NSLocalizedString("可选", comment: ""),
                    description: NSLocalizedString("用于检索 Chrome 本地书签与已知站点，不读取浏览历史", comment: ""),
                    authorized: app.chromeBookmarkAccessState == .authorized,
                    statusLabel: chromeStatusLabel
                ) {
                    SettingsButton(NSLocalizedString(requestingChrome ? "正在请求…" :
                        app.chromeBookmarkAccessState == .authorized ? "重新授权" : "去授权", comment: "")) {
                        requestingChrome = true
                        Task {
                            await app.authorizeChromeBookmarkFolder()
                            await app.refreshChromeBookmarkAccess()
                            requestingChrome = false
                        }
                    }
                    .disabled(requestingChrome)
                }
            }
            .background(SettingsPalette.card(scheme), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 8) {
                Image(mingCute: "info.circle", size: 14)
                    .foregroundStyle(ThemeColor.kTextSubtlest)
                    .accessibilityHidden(true)
                Text(NSLocalizedString("权限随时可在「设置 › 系统权限」中调整或撤销", comment: ""))
                    .font(.system(size: 12))
                    .foregroundStyle(ThemeColor.kTextSubtlest)
            }
        }
    }

    private func permissionRow<Action: View>(
        symbol: String,
        color: Color,
        title: String,
        badge: String,
        description: String,
        authorized: Bool,
        statusLabel: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color, in: RoundedRectangle(cornerRadius: 8))
                .drawingGroup()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                    Text(badge)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ThemeColor.kTextSubtle)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ThemeColor.kBackgroundNeutral.color(for: scheme), in: Capsule())
                }
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(ThemeColor.kTextSubtle)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Image(mingCute: authorized ? "checkmark" : "info.circle", size: 12)
                    Text(statusLabel)
                }
                .font(.system(size: 12))
                .foregroundStyle(authorized ? ThemeColor.kTextPositive : ThemeColor.kTextSubtlest)
            }
            Spacer(minLength: 12)
            action()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(title: NSLocalizedString("确认触发快捷键", comment: ""),
                       subtitle: NSLocalizedString("点击按钮即可录制新组合键，或直接保留默认设置", comment: ""))

            VStack(spacing: 0) {
                onboardingShortcutRow(
                    title: NSLocalizedString("唤起启动器", comment: ""),
                    label: app.preferences.hotKeyLabel,
                    status: app.hotKeyStatus,
                    apply: setLauncherHotKey
                )
                divider
                onboardingShortcutRow(
                    title: NSLocalizedString("打开剪贴板历史", comment: ""),
                    label: app.preferences.clipboardHotKeyLabel,
                    status: app.clipboardHotKeyStatus,
                    apply: setClipboardHotKey
                )
                divider
                onboardingShortcutRow(
                    title: NSLocalizedString("打开 AI 对话", comment: ""),
                    label: app.preferences.agentHotKeyLabel,
                    status: app.agentHotKeyStatus,
                    apply: setAgentHotKey
                )
            }
            .background(SettingsPalette.card(scheme), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 10) {
                Text(NSLocalizedString("常用内置指令", comment: ""))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ThemeColor.kTextSubtle)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 10) {
                    triggerTip("app / file", NSLocalizedString("分类检索应用或文件", comment: ""))
                    triggerTip("sw", NSLocalizedString("切换已打开的应用窗口", comment: ""))
                    triggerTip("co / calc", NSLocalizedString("屏幕取色与计算历史", comment: ""))
                    triggerTip("go / >", NSLocalizedString("网页搜索与终端命令", comment: ""))
                }
            }
            .padding(14)
            .background(SettingsPalette.card(scheme), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func onboardingShortcutRow(title: String, label: String, status: String,
                                       apply: @escaping (UInt32, UInt32, String) -> Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                HotKeyRecorder(label: label, allowsPlainKey: false, apply: apply)
                    .frame(width: 156, height: 30)
            }
            if !status.isEmpty, status != NSLocalizedString("已注册", comment: "") {
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(ThemeColor.kTextNegative)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func triggerTip(_ trigger: String, _ description: String) -> some View {
        HStack(spacing: 8) {
            shortcutBadge(trigger)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(ThemeColor.kTextSubtle)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var aiStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(title: NSLocalizedString("配置 AI 助手（可选）", comment: ""),
                       subtitle: NSLocalizedString("不配置模型也能使用搜索、剪贴板与快速预览；API Key 仅保存在本机钥匙串", comment: ""))

            if app.isModelConfigured && !editingModel, let cfg = app.modelConfiguration {
                HStack(spacing: 14) {
                    LauncherFunctionIcon(kind: .ai)
                        .scaleEffect(1.15)
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(mingCute: "checkmark", size: 13)
                                .foregroundStyle(ThemeColor.kTextPositive)
                            Text(NSLocalizedString("AI 模型已就绪", comment: ""))
                                .font(.system(size: 14, weight: .medium))
                        }
                        Text("\(cfg.modelName) · \(cfg.baseURL.host ?? cfg.baseURL.absoluteString)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(ThemeColor.kTextSubtle)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    SettingsButton(NSLocalizedString("修改配置", comment: "")) {
                        loadModelDraft()
                        editingModel = true
                    }
                }
                .padding(16)
                .background(SettingsPalette.card(scheme), in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Text(NSLocalizedString("供应商", comment: ""))
                        Spacer(minLength: 16)
                        SettingsChoice(selection: Binding(get: { draft.provider }, set: { value in
                            draft.select(value)
                            apiKey = ""
                            modelMessage = nil
                            modelSaved = false
                        }), options: ModelProviderPreset.all.map { ($0.id, NSLocalizedString($0.name, comment: "")) } + [
                            ("custom", NSLocalizedString("完全自定义（OpenAI 兼容）", comment: ""))
                        ])
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    divider

                    if let preset = ModelProviderPreset.find(draft.provider) {
                        HStack(spacing: 16) {
                            Text(NSLocalizedString("模型", comment: ""))
                            Spacer(minLength: 16)
                            SettingsChoice(selection: $draft.model, options: preset.models.map { ($0, $0) })
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        divider
                    } else {
                        SettingsTextField(NSLocalizedString("API 地址", comment: ""), text: $draft.baseURL,
                                          prompt: Text("https://api.example.com/v1"))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        divider
                        SettingsTextField(NSLocalizedString("模型名", comment: ""), text: $draft.model)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        divider
                    }

                    SettingsSecureField(NSLocalizedString("API Key", comment: ""), text: $apiKey,
                                        prompt: Text(NSLocalizedString(canReuseKey ? "已保存，留空不变" : "输入 API Key", comment: "")))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    divider

                    HStack(spacing: 12) {
                        if let preset = ModelProviderPreset.find(draft.provider) {
                            Button {
                                _ = ToolService.openLauncherURL(preset.keyURL)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(NSLocalizedString("获取 API Key", comment: ""))
                                    Image(mingCute: "arrow.up.right", size: 12)
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(ThemeColor.kTextSubtle)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 8)
                        if editingModel && app.isModelConfigured {
                            SettingsButton(NSLocalizedString("取消", comment: "")) {
                                editingModel = false
                                modelMessage = nil
                            }
                        }
                        SettingsButton(NSLocalizedString("保存并检查", comment: ""),
                                       isLoading: savingModel || checkingModel,
                                       isComplete: modelSaved,
                                       loadingTitle: NSLocalizedString(savingModel ? "保存中…" : "检查中…", comment: "")) {
                            Task { await saveAndCheckModel() }
                        }
                        .disabled(savingModel || checkingModel || modelSaved)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(SettingsPalette.card(scheme), in: RoundedRectangle(cornerRadius: 12))
                .disabled(savingModel || checkingModel)

                if let modelMessage {
                    Text(modelMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(ThemeColor.kTextNegative)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Image(mingCute: "info.circle", size: 14)
                    .foregroundStyle(ThemeColor.kTextSubtlest)
                    .accessibilityHidden(true)
                Text(NSLocalizedString("稍后也可随时在「设置 › 模型配置」中填写或更改", comment: ""))
                    .font(.system(size: 12))
                    .foregroundStyle(ThemeColor.kTextSubtlest)
            }
        }
    }

    // MARK: Footer

    private var footerBar: some View {
        HStack {
            if step == .welcome {
                Button(NSLocalizedString("跳过引导", comment: "")) {
                    app.preferences.hasCompletedOnboarding = true
                    onSkip()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(ThemeColor.kTextSubtle)
            } else {
                SettingsButton(NSLocalizedString("上一步", comment: "")) {
                    if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
                        navigate(to: previous)
                    }
                }
            }

            Spacer()

            if step == .ai {
                Button(NSLocalizedString("开始使用 Asky", comment: "")) {
                    app.preferences.hasCompletedOnboarding = true
                    onFinish()
                }
                .compatibleGlassButtonStyle(prominent: true)
                .controlSize(.large)
            } else {
                Button(NSLocalizedString("继续", comment: "")) {
                    if let next = OnboardingStep(rawValue: step.rawValue + 1) {
                        navigate(to: next)
                    }
                }
                .compatibleGlassButtonStyle(prominent: true)
                .controlSize(.large)
            }
        }
    }

    // MARK: Helpers

    private var divider: some View {
        Rectangle()
            .fill(SettingsPalette.separator(scheme))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(ThemeColor.kTextSubtle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(ThemeColor.kTextSubtle)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ThemeColor.kBackgroundNeutral.color(for: scheme), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(ThemeColor.kBorder.color(for: scheme), lineWidth: 1)
            }
    }

    private func navigate(to target: OnboardingStep) {
        if reduceMotion {
            step = target
        } else {
            withAnimation(.easeInOut(duration: 0.16)) {
                step = target
            }
        }
    }

    private var accessibilityStatusLabel: String {
        switch permissionModel.states[.accessibility] {
        case .authorized: NSLocalizedString("已授权", comment: "")
        case nil: NSLocalizedString("正在检查…", comment: "")
        default: NSLocalizedString("未授权", comment: "")
        }
    }

    private var chromeStatusLabel: String {
        switch app.chromeBookmarkAccessState {
        case .authorized: NSLocalizedString("已授权", comment: "")
        case nil: NSLocalizedString("正在检查…", comment: "")
        default: NSLocalizedString("未授权", comment: "")
        }
    }

    private func refreshPermissions() async {
        await permissionModel.refresh()
        await app.refreshChromeBookmarkAccess()
    }

    private func conflictsWithLocal(_ code: UInt32, _ modifiers: UInt32) -> Bool {
        LocalShortcutAction.allCases.contains {
            let shortcut = app.preferences.shortcut($0)
            return shortcut.code == code && shortcut.modifiers == modifiers
        }
    }

    private func setLauncherHotKey(_ code: UInt32, _ modifiers: UInt32, _ label: String) -> Bool {
        guard !conflictsWithLocal(code, modifiers), app.onHotKeyChange?(code, modifiers) == true else { return false }
        app.preferences.hotKeyCode = code
        app.preferences.hotKeyModifiers = modifiers
        app.preferences.hotKeyLabel = label
        return true
    }

    private func setClipboardHotKey(_ code: UInt32, _ modifiers: UInt32, _ label: String) -> Bool {
        guard !conflictsWithLocal(code, modifiers), app.onClipboardHotKeyChange?(code, modifiers) == true else { return false }
        app.preferences.clipboardHotKeyCode = code
        app.preferences.clipboardHotKeyModifiers = modifiers
        app.preferences.clipboardHotKeyLabel = label
        return true
    }

    private func setAgentHotKey(_ code: UInt32, _ modifiers: UInt32, _ label: String) -> Bool {
        guard !conflictsWithLocal(code, modifiers), app.onAgentHotKeyChange?(code, modifiers) == true else { return false }
        app.preferences.agentHotKeyCode = code
        app.preferences.agentHotKeyModifiers = modifiers
        app.preferences.agentHotKeyLabel = label
        return true
    }

    private var canReuseKey: Bool {
        draft.canReuseCredential(savedBaseURL: app.modelConfiguration?.baseURL.absoluteString)
    }

    private func loadModelDraft() {
        draft = ModelConfigurationDraft(provider: app.preferences.provider,
                                        baseURL: app.modelConfiguration?.baseURL.absoluteString,
                                        model: app.modelConfiguration?.modelName)
    }

    private func saveAndCheckModel() async {
        modelMessage = nil
        apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        savingModel = true
        guard let url = URL(string: draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host)),
              !draft.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            savingModel = false
            modelMessage = NSLocalizedString("请填写有效的 https 地址与模型名。", comment: "")
            return
        }
        do {
            let account = app.modelConfiguration?.credentialRef ?? ModelSettings.keyAccount
            guard !apiKey.isEmpty || (canReuseKey && app.keychain.contains(account: account)) else {
                savingModel = false
                modelMessage = NSLocalizedString("请填写此服务商的 API Key；切换 API 地址后不能沿用原来的 Key。", comment: "")
                return
            }
            if !apiKey.isEmpty {
                try app.keychain.set(apiKey, account: account)
                await app.credentialSession.remember(apiKey, account: account)
            }
            app.preferences.provider = draft.provider
            var cfg = ModelConfiguration(baseURL: url,
                                         modelName: draft.model.trimmingCharacters(in: .whitespacesAndNewlines),
                                         credentialRef: account)
            app.modelConfiguration = cfg
            apiKey = ""
            await app.agent?.shutdown()
            savingModel = false

            checkingModel = true
            defer { checkingModel = false }
            guard let key = try await app.readModelCredential(account: cfg.credentialRef) else {
                modelMessage = NSLocalizedString("请先保存 API Key。", comment: "")
                return
            }
            let report = await ModelCapabilityCheck.run(baseURL: cfg.baseURL, model: cfg.modelName, apiKey: key)
            cfg.capabilities = report.capabilities
            app.modelConfiguration = cfg
            if report.failures.isEmpty {
                modelSaved = true
                editingModel = false
                Task {
                    try? await Task.sleep(for: .milliseconds(1500))
                    modelSaved = false
                }
            } else {
                modelMessage = report.failures.joined(separator: "\n")
            }
        } catch {
            savingModel = false
            checkingModel = false
            modelMessage = String(format: NSLocalizedString("钥匙串写入失败：%@", comment: ""), String(describing: error))
        }
    }
}
