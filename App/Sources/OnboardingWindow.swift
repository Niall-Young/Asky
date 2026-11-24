#if DEBUG
import AppKit
import Carbon.HIToolbox
import Combine
import Contracts
import SwiftUI
import Theme
import ToolService

/// First-launch welcome and setup window: spacious, quiet, native macOS Liquid Glass.
@MainActor
enum OnboardingWindow {
    static let size = NSSize(width: 600, height: 460)

    static func make(app: AppModel, onFinish: @escaping () -> Void, onDismiss: @escaping () -> Void) -> NSWindow {
        let controller = OnboardingContainerController(app: app, onFinish: onFinish, onDismiss: onDismiss)
        let window = SettingsEditingWindow(contentRect: NSRect(origin: .zero, size: size),
                                           styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                           backing: .buffered, defer: false)
        window.animationBehavior = .documentWindow
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentViewController = controller
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        let toolbar = NSToolbar(identifier: "AskyOnboarding")
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.title = NSLocalizedString("欢迎使用 Asky", comment: "")
        window.standardWindowButton(.zoomButton)?.isEnabled = false
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
        view = NSView(frame: NSRect(origin: .zero, size: OnboardingWindow.size))
        let backdrop = NSHostingView(rootView: OnboardingBackdrop().ignoresSafeArea())
        let content = NSHostingView(rootView: OnboardingView(app: app, onFinish: onFinish, onSkip: onDismiss) { [weak self] in
            self?.updateAppearance()
        }.ignoresSafeArea(.container, edges: .top))
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

// MARK: - Window Backdrop (Matches Native Window Corner Radius)

private struct OnboardingBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var opaque: Bool { reduceTransparency || contrast == .increased }

    var body: some View {
        if opaque {
            Rectangle().fill(SettingsPalette.surface(scheme, opaque: true))
        } else if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial {
            OnboardingRegularGlass(scheme: scheme)
                .overlay(ThemeColor.kBackgroundNeutral.color(for: scheme))
        } else {
            Color.clear.nativeGlassBackground(in: Rectangle())
        }
    }
}

@available(macOS 26, *)
private struct OnboardingRegularGlass: NSViewRepresentable {
    let scheme: ColorScheme

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.tintColor = NSColor(SettingsPalette.surface(scheme, opaque: true)).withAlphaComponent(0.25)
    }
}

// MARK: - Subtle Ambient Glow

private struct OnboardingAmbientGlow: View {
    let step: OnboardingStep
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var centerX: CGFloat {
        switch step {
        case .welcome: 0.50
        case .permissions: 0.32
        case .shortcuts: 0.52
        case .ai: 0.68
        }
    }

    var body: some View {
        if !reduceTransparency && contrast != .increased {
            RadialGradient(
                colors: [
                    Color.accentColor.opacity(scheme == .dark ? 0.12 : 0.08),
                    Color.accentColor.opacity(scheme == .dark ? 0.03 : 0.015),
                    .clear,
                ],
                center: UnitPoint(x: centerX, y: step == .welcome ? 0.18 : 0.05),
                startRadius: 12,
                endRadius: 320
            )
            .animation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.96), value: step)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Unified Controls & Surfaces

private struct OnboardingActionButtonStyle: ButtonStyle {
    var prominent: Bool
    var minWidth: CGFloat = 104
    var height: CGFloat = 38
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var useNativeGlass: Bool {
        if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial,
           !reduceTransparency, contrast != .increased {
            return true
        }
        return false
    }

    func makeBody(configuration: Configuration) -> some View {
        let base = configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(prominent ? Color.white : ThemeColor.kText.color(for: scheme))
            .padding(.horizontal, 22)
            .frame(minWidth: minWidth, minHeight: height)
            .contentShape(Capsule())

        Group {
            if #available(macOS 26, *), useNativeGlass {
                base
                    .glassEffect(
                        prominent ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                        in: Capsule()
                    )
            } else {
                base
                    .background {
                        if prominent {
                            Capsule()
                                .fill(Color.accentColor.opacity(hovered ? 0.92 : 1))
                        } else {
                            Capsule()
                                .fill(
                                    scheme == .dark
                                        ? Color.white.opacity(hovered ? 0.13 : 0.08)
                                        : Color.black.opacity(hovered ? 0.07 : 0.045)
                                )
                        }
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                prominent
                                    ? Color.white.opacity(scheme == .dark ? 0.16 : 0.22)
                                    : ThemeColor.kBorder.color(for: scheme),
                                lineWidth: 1
                            )
                    }
                    .scaleEffect(!reduceMotion && configuration.isPressed ? 0.975 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.11), value: configuration.isPressed)
            }
        }
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovered = $0 }
    }
}

private struct OnboardingStatusBadge: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var tint: Color {
        scheme == .dark
            ? Color(.sRGB, red: 0.28, green: 0.80, blue: 0.50, opacity: 1)
            : Color(.sRGB, red: 0.14, green: 0.58, blue: 0.34, opacity: 1)
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(tint)
                    .frame(width: 15, height: 15)
                Image(mingCute: "checkmark", size: 9)
                    .foregroundStyle(Color.white)
            }
            .accessibilityHidden(true)

            Text(NSLocalizedString("已开启", comment: ""))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(tint)
        }
        .padding(.leading, 7)
        .padding(.trailing, 11)
        .frame(height: 28)
        .background(tint.opacity(scheme == .dark ? 0.14 : 0.10), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(contrast == .increased ? 0.45 : 0.22), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var fillColor: Color {
        if reduceTransparency || contrast == .increased {
            return scheme == .dark
                ? Color(.sRGB, red: 0.16, green: 0.165, blue: 0.18, opacity: 1)
                : Color.white
        }
        return scheme == .dark
            ? Color.white.opacity(0.055)
            : Color.white.opacity(0.58)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content
            .background(fillColor, in: shape)
            .overlay {
                shape.strokeBorder(
                    scheme == .dark
                        ? Color.white.opacity(contrast == .increased ? 0.24 : 0.085)
                        : Color.black.opacity(contrast == .increased ? 0.22 : 0.06),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
            }
    }
}

private struct OnboardingIconBadge: View {
    enum Icon {
        case mingCute(String, Color)
        case agentBrand
    }

    let icon: Icon

    var body: some View {
        Group {
            switch icon {
            case let .mingCute(symbol, tint):
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint)
                    Image(mingCute: symbol, size: 17)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 17, height: 17)
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)
                .fixedSize()
                .drawingGroup()
            case .agentBrand:
                Image("Agent")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Onboarding Steps & View

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case permissions
    case shortcuts
    case ai

    var id: Int { rawValue }
    static let setupSteps: [OnboardingStep] = [.permissions, .shortcuts, .ai]
}

struct OnboardingView: View {
    @Bindable var app: AppModel
    let onFinish: () -> Void
    let onSkip: () -> Void
    let onAppearanceChange: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var transitionForward = true
    @State private var entered = false

    // Permissions
    @State private var permissionModel = PermissionSettingsModel()
    @State private var requestingChrome = false
    @State private var loginStatus = ToolService.launchAtLoginStatus

    // Optional AI setup
    @State private var draft = ModelConfigurationDraft(provider: "custom", baseURL: nil, model: nil)
    @State private var apiKey = ""
    @State private var modelMessage: String?
    @State private var savingModel = false
    @State private var checkingModel = false
    @State private var modelSaved = false
    @State private var hoverKeyLink = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let permissionTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            OnboardingAmbientGlow(step: step)

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 44)
                    .compatibleWindowDrag()

                ZStack {
                    switch step {
                    case .welcome:
                        welcomeStep.transition(stepTransition)
                    case .permissions:
                        permissionsStep.transition(stepTransition)
                    case .shortcuts:
                        shortcutsStep.transition(stepTransition)
                    case .ai:
                        aiStep.transition(stepTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 48)

                if step != .welcome {
                    footerBar
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .font(.system(size: 14))
        .foregroundStyle(ThemeColor.kText)
        .onAppear {
            loadModelDraft()
            loginStatus = ToolService.launchAtLoginStatus
            Task { await refreshPermissions() }
            triggerEntrance()
        }
        .onChange(of: app.preferences.appearance) { _, _ in onAppearanceChange() }
        .onChange(of: step) { _, next in
            if next == .permissions {
                loginStatus = ToolService.launchAtLoginStatus
                Task { await refreshPermissions() }
            }
            if next == .ai {
                loadModelDraft()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if step == .permissions {
                loginStatus = ToolService.launchAtLoginStatus
                Task { await refreshPermissions() }
            }
        }
        .onReceive(permissionTimer) { _ in
            if step == .permissions && !requestingChrome {
                Task { await refreshPermissions() }
            }
        }
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let enterX: CGFloat = transitionForward ? 20 : -20
        let exitX: CGFloat = transitionForward ? -16 : 16
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: enterX)),
            removal: .opacity.combined(with: .offset(x: exitX))
        )
    }

    private func triggerEntrance() {
        if reduceMotion {
            entered = true
            return
        }
        entered = false
        DispatchQueue.main.async {
            entered = true
        }
    }

    private func entranceAnimation(delay: Double) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.92).delay(delay)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.accentColor.opacity(scheme == .dark ? 0.24 : 0.14),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 68
                        )
                    )
                    .frame(width: 136, height: 136)
                    .allowsHitTesting(false)

                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .shadow(color: Color.black.opacity(scheme == .dark ? 0.36 : 0.12), radius: 18, y: 8)
                    .shadow(color: Color.black.opacity(scheme == .dark ? 0.18 : 0.05), radius: 4, y: 1)
            }
            .frame(height: 100)
            .scaleEffect(entered || reduceMotion ? 1 : 0.94)
            .opacity(entered ? 1 : 0)
            .animation(entranceAnimation(delay: 0.0), value: entered)
            .accessibilityHidden(true)

            Spacer().frame(height: 22)

            Text(NSLocalizedString("你好，欢迎使用 Asky", comment: ""))
                .font(.system(size: 27, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(ThemeColor.kText)
                .opacity(entered ? 1 : 0)
                .offset(y: entered || reduceMotion ? 0 : 8)
                .animation(entranceAnimation(delay: 0.07), value: entered)

            Spacer().frame(height: 10)

            Text(NSLocalizedString("搜索、剪贴板与 AI，一个快捷键呼出", comment: ""))
                .font(.system(size: 14.5))
                .foregroundStyle(ThemeColor.kTextSubtle)
                .opacity(entered ? 1 : 0)
                .offset(y: entered || reduceMotion ? 0 : 8)
                .animation(entranceAnimation(delay: 0.13), value: entered)

            Spacer()

            HStack(spacing: 14) {
                Button(NSLocalizedString("跳过", comment: "")) {
                    app.preferences.hasCompletedOnboarding = true
                    onSkip()
                }
                .buttonStyle(OnboardingActionButtonStyle(prominent: false, minWidth: 112, height: 40))

                Button(NSLocalizedString("开始设置", comment: "")) {
                    navigate(to: .permissions)
                }
                .buttonStyle(OnboardingActionButtonStyle(prominent: true, minWidth: 156, height: 40))
                .keyboardShortcut(.defaultAction)
            }
            .opacity(entered ? 1 : 0)
            .offset(y: entered || reduceMotion ? 0 : 8)
            .animation(entranceAnimation(delay: 0.19), value: entered)

            Spacer().frame(height: 44)
        }
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeader(
                title: NSLocalizedString("开启常用权限", comment: ""),
                subtitle: NSLocalizedString("按需开启，随时可在设置中调整", comment: "")
            )

            OnboardingCard {
                VStack(spacing: 0) {
                    permissionRow(
                        icon: .mingCute("accessibility", ToolIconPalette.blue),
                        title: NSLocalizedString("辅助功能", comment: ""),
                        description: NSLocalizedString("自动粘贴与窗口切换", comment: "")
                    ) {
                        if permissionModel.states[.accessibility] == .authorized {
                            OnboardingStatusBadge()
                        } else {
                            SettingsButton(NSLocalizedString("去授权", comment: "")) {
                                PermissionAuthorizationWindow.shared.show(.accessibility, colorScheme: scheme)
                            }
                        }
                    }

                    rowDivider

                    permissionRow(
                        icon: .mingCute("bookmark", ToolIconPalette.orange),
                        title: NSLocalizedString("Chrome 书签", comment: ""),
                        description: NSLocalizedString("快速搜索本地书签", comment: "")
                    ) {
                        if app.chromeBookmarkAccessState == .authorized {
                            OnboardingStatusBadge()
                        } else {
                            SettingsButton(NSLocalizedString(requestingChrome ? "正在请求…" : "去授权", comment: "")) {
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

                    rowDivider

                    permissionRow(
                        icon: .mingCute("power", ToolIconPalette.green),
                        title: NSLocalizedString("登录时启动", comment: ""),
                        description: NSLocalizedString("开机自动在菜单栏就绪", comment: "")
                    ) {
                        Toggle("", isOn: Binding(
                            get: { loginStatus == .enabled },
                            set: { on in
                                _ = try? ToolService.setLaunchAtLogin(on)
                                loginStatus = ToolService.launchAtLoginStatus
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func permissionRow<Trailing: View>(
        icon: OnboardingIconBadge.Icon,
        title: String,
        description: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 14) {
            OnboardingIconBadge(icon: icon)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ThemeColor.kText)
                Text(description)
                    .font(.system(size: 12.5))
                    .foregroundStyle(ThemeColor.kTextSubtle)
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    // MARK: - Step 3: Shortcuts

    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeader(
                title: NSLocalizedString("设置快捷键", comment: ""),
                subtitle: NSLocalizedString("点击按钮即可录制新组合键，或直接保留默认设置", comment: "")
            )

            OnboardingCard {
                VStack(spacing: 0) {
                    shortcutRow(
                        icon: .mingCute("magnifyingglass", ToolIconPalette.blue),
                        title: NSLocalizedString("唤起启动器", comment: ""),
                        label: app.preferences.hotKeyLabel,
                        status: app.hotKeyStatus,
                        apply: setLauncherHotKey
                    )
                    rowDivider
                    shortcutRow(
                        icon: .mingCute("doc.on.clipboard", ToolIconPalette.teal),
                        title: NSLocalizedString("打开剪贴板历史", comment: ""),
                        label: app.preferences.clipboardHotKeyLabel,
                        status: app.clipboardHotKeyStatus,
                        apply: setClipboardHotKey
                    )
                    rowDivider
                    shortcutRow(
                        icon: .agentBrand,
                        title: NSLocalizedString("打开 AI 对话", comment: ""),
                        label: app.preferences.agentHotKeyLabel,
                        status: app.agentHotKeyStatus,
                        apply: setAgentHotKey
                    )
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func shortcutRow(
        icon: OnboardingIconBadge.Icon,
        title: String,
        label: String,
        status: String,
        apply: @escaping (UInt32, UInt32, String) -> Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                OnboardingIconBadge(icon: icon)

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ThemeColor.kText)

                Spacer(minLength: 16)

                HotKeyRecorder(label: label, allowsPlainKey: false, apply: apply)
                    .frame(width: 172, height: 30)
            }
            if !status.isEmpty, status != NSLocalizedString("已注册", comment: "") {
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(ThemeColor.kTextNegative)
                    .padding(.leading, 46)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    // MARK: - Step 4: Optional AI Setup

    private var aiStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader(
                title: NSLocalizedString("配置 AI 助手", comment: ""),
                subtitle: NSLocalizedString("不配置模型也能畅用搜索、剪贴板与预览", comment: "")
            )

            OnboardingCard {
                VStack(spacing: 0) {
                    HStack {
                        Text(NSLocalizedString("供应商", comment: ""))
                            .foregroundStyle(ThemeColor.kText)
                        Spacer()
                        SettingsChoice(selection: Binding(get: { draft.provider }, set: { value in
                            draft.select(value)
                            apiKey = ""
                            modelMessage = nil
                            modelSaved = false
                        }), options: ModelProviderPreset.all.map { ($0.id, NSLocalizedString($0.name, comment: "")) } + [
                            ("custom", NSLocalizedString("完全自定义（OpenAI 兼容）", comment: ""))
                        ])
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    rowDivider

                    if let preset = ModelProviderPreset.find(draft.provider) {
                        HStack {
                            Text(NSLocalizedString("模型", comment: ""))
                                .foregroundStyle(ThemeColor.kText)
                            Spacer()
                            SettingsChoice(selection: $draft.model, options: preset.models.map { ($0, $0) })
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        rowDivider
                    } else {
                        SettingsTextField(NSLocalizedString("API 地址", comment: ""), text: $draft.baseURL,
                                          prompt: Text("https://api.example.com/v1"))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                        rowDivider
                        SettingsTextField(NSLocalizedString("模型名", comment: ""), text: $draft.model)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                        rowDivider
                    }

                    SettingsSecureField(NSLocalizedString("API Key", comment: ""), text: $apiKey,
                                        prompt: Text(NSLocalizedString(canReuseKey ? "已保存，留空不变" : "输入 API Key", comment: "")))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                    rowDivider

                    HStack {
                        if let preset = ModelProviderPreset.find(draft.provider) {
                            Button {
                                _ = ToolService.openLauncherURL(preset.keyURL)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(NSLocalizedString("获取 API Key", comment: ""))
                                    Image(mingCute: "arrow.up.right", size: 12)
                                }
                                .font(.system(size: 12.5))
                                .foregroundStyle(hoverKeyLink ? ThemeColor.kText.color(for: scheme) : ThemeColor.kTextSubtle.color(for: scheme))
                            }
                            .buttonStyle(.plain)
                            .onHover { hoverKeyLink = $0 }
                        }
                        Spacer()
                        SettingsButton(NSLocalizedString("保存并检查", comment: ""),
                                       isLoading: savingModel || checkingModel,
                                       isComplete: modelSaved,
                                       loadingTitle: NSLocalizedString(savingModel ? "保存中…" : "检查中…", comment: "")) {
                            Task { await saveAndCheckModel() }
                        }
                        .disabled(savingModel || checkingModel || modelSaved)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                }
                .disabled(savingModel || checkingModel)
            }

            if let modelMessage {
                Text(modelMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(ThemeColor.kTextNegative)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Shared Header & Footer

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(ThemeColor.kText)
            Text(subtitle)
                .font(.system(size: 13.5))
                .foregroundStyle(ThemeColor.kTextSubtle)
        }
        .padding(.top, 10)
    }

    private var footerBar: some View {
        ZStack {
            HStack(spacing: 7) {
                ForEach(OnboardingStep.setupSteps) { item in
                    Button { navigate(to: item) } label: {
                        Capsule()
                            .fill(item == step
                                  ? ThemeColor.kText.color(for: scheme).opacity(0.65)
                                  : ThemeColor.kTextSubtlest.color(for: scheme).opacity(0.45))
                            .frame(width: item == step ? 18 : 6, height: 6)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.rawValue)")
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.90), value: step)

            HStack {
                Button(NSLocalizedString("上一步", comment: "")) {
                    if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
                        navigate(to: previous)
                    }
                }
                .buttonStyle(OnboardingActionButtonStyle(prominent: false, minWidth: 96, height: 38))

                Spacer()

                if step == .ai {
                    Button(NSLocalizedString("开始使用", comment: "")) {
                        app.preferences.hasCompletedOnboarding = true
                        onFinish()
                    }
                    .buttonStyle(OnboardingActionButtonStyle(prominent: true, minWidth: 112, height: 38))
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(NSLocalizedString("继续", comment: "")) {
                        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
                            navigate(to: next)
                        }
                    }
                    .buttonStyle(OnboardingActionButtonStyle(prominent: true, minWidth: 104, height: 38))
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.top, 10)
        .padding(.bottom, 28)
    }

    // MARK: - Helpers

    private var rowDivider: some View {
        Rectangle()
            .fill(SettingsPalette.separator(scheme))
            .frame(height: 1)
            .padding(.horizontal, 18)
    }

    private func navigate(to target: OnboardingStep) {
        guard target != step else { return }
        transitionForward = target.rawValue > step.rawValue
        if target == .welcome {
            entered = true
        }
        if reduceMotion {
            step = target
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.95)) {
                step = target
            }
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
            modelMessage = NSLocalizedString("请填写有效的 https 地址与模型名", comment: "")
            return
        }
        do {
            let account = app.modelConfiguration?.credentialRef ?? ModelSettings.keyAccount
            guard !apiKey.isEmpty || (canReuseKey && app.keychain.contains(account: account)) else {
                savingModel = false
                modelMessage = NSLocalizedString("请填写此服务商的 API Key；切换 API 地址后不能沿用原来的 Key", comment: "")
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
                modelMessage = NSLocalizedString("请先保存 API Key", comment: "")
                return
            }
            let report = await ModelCapabilityCheck.run(baseURL: cfg.baseURL, model: cfg.modelName, apiKey: key)
            cfg.capabilities = report.capabilities
            app.modelConfiguration = cfg
            if report.failures.isEmpty {
                modelSaved = true
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
#endif
