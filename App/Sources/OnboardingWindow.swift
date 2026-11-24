#if DEBUG
import AppKit
import Carbon.HIToolbox
import Combine
import Contracts
import SwiftUI
import Theme
import ToolService

/// First-launch welcome and setup window sharing Asky's native Liquid Glass language.
@MainActor
enum OnboardingWindow {
    static let size = NSSize(width: 520, height: 488)

    static func make(app: AppModel, onFinish: @escaping () -> Void, onDismiss: @escaping () -> Void) -> NSWindow {
        let controller = OnboardingContainerController(app: app, onFinish: onFinish, onDismiss: onDismiss)
        let window = SettingsEditingWindow(contentRect: NSRect(origin: .zero, size: size),
                                           styleMask: [.titled, .closable, .fullSizeContentView],
                                           backing: .buffered, defer: false)
        window.animationBehavior = .documentWindow
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentViewController = controller
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = NSLocalizedString("欢迎使用 Asky", comment: "")
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
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
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true

        let backdrop = NSHostingView(rootView: SettingsBackdrop().ignoresSafeArea())
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

// MARK: - Subtle Ambient Glow Over Native Glass

private struct OnboardingAmbientGlow: View {
    let step: OnboardingStep
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var accentShiftX: CGFloat {
        switch step {
        case .welcome: 0.50
        case .permissions: 0.34
        case .shortcuts: 0.52
        case .ai: 0.68
        }
    }

    var body: some View {
        if !reduceTransparency && contrast != .increased {
            ZStack {
                RadialGradient(
                    colors: [
                        Color.accentColor.opacity(scheme == .dark ? 0.11 : 0.08),
                        Color.accentColor.opacity(scheme == .dark ? 0.03 : 0.02),
                        .clear,
                    ],
                    center: UnitPoint(x: accentShiftX, y: step == .welcome ? 0.14 : 0.06),
                    startRadius: 10,
                    endRadius: 290
                )

                RadialGradient(
                    colors: [
                        ToolIconPalette.indigo.opacity(scheme == .dark ? 0.07 : 0.045),
                        .clear,
                    ],
                    center: UnitPoint(x: 1 - accentShiftX * 0.65, y: 0.02),
                    startRadius: 0,
                    endRadius: 240
                )
            }
            .animation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.96), value: step)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Controls & Surfaces

private struct OnboardingActionButtonStyle: ButtonStyle {
    var prominent: Bool
    var minWidth: CGFloat = 92
    var height: CGFloat = 32
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
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(prominent ? Color.white : ThemeColor.kText.color(for: scheme))
            .padding(.horizontal, 18)
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

private struct OnboardingGhostButtonStyle: ButtonStyle {
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .regular))
            .foregroundStyle(hovered ? ThemeColor.kText.color(for: scheme) : ThemeColor.kTextSubtle.color(for: scheme))
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background {
                Capsule()
                    .fill(ThemeColor.kInteractionHover.color(for: scheme))
                    .opacity(hovered || configuration.isPressed ? 1 : 0)
            }
            .contentShape(Capsule())
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.975 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
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
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(tint)
                    .frame(width: 14, height: 14)
                Image(mingCute: "checkmark", size: 9)
                    .foregroundStyle(Color.white)
            }
            .accessibilityHidden(true)

            Text(NSLocalizedString("已开启", comment: ""))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(height: 26)
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
            : Color.white.opacity(0.56)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .background(fillColor, in: shape)
            .overlay {
                shape.strokeBorder(
                    scheme == .dark
                        ? Color.white.opacity(contrast == .increased ? 0.24 : 0.09)
                        : Color.black.opacity(contrast == .increased ? 0.22 : 0.065),
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
                    LauncherIconClip(radius: 7)
                        .fill(tint)
                    Image(mingCute: symbol, size: 15)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)
                .fixedSize()
                .drawingGroup()
            case .agentBrand:
                Image("Agent")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(LauncherIconClip(radius: 7))
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

    // Welcome stagger states
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
                    .frame(height: 36)
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
                .padding(.horizontal, 32)

                if step != .welcome {
                    footerBar
                        .transition(.opacity)
                }
            }
        }
        .frame(width: OnboardingWindow.size.width, height: OnboardingWindow.size.height)
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
        let enterX: CGFloat = transitionForward ? 18 : -18
        let exitX: CGFloat = transitionForward ? -14 : 14
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
        reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.92).delay(delay)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 4)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.accentColor.opacity(scheme == .dark ? 0.24 : 0.14),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 56
                        )
                    )
                    .frame(width: 112, height: 112)
                    .allowsHitTesting(false)

                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .shadow(color: Color.black.opacity(scheme == .dark ? 0.34 : 0.12), radius: 14, y: 6)
                    .shadow(color: Color.black.opacity(scheme == .dark ? 0.18 : 0.05), radius: 3, y: 1)
            }
            .frame(height: 82)
            .scaleEffect(entered || reduceMotion ? 1 : 0.94)
            .opacity(entered ? 1 : 0)
            .animation(entranceAnimation(delay: 0.0), value: entered)
            .accessibilityHidden(true)

            Spacer().frame(height: 12)

            VStack(spacing: 6) {
                Text(NSLocalizedString("你好，欢迎使用 Asky", comment: ""))
                    .font(.system(size: 23, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(ThemeColor.kText)

                Text(NSLocalizedString("搜索、剪贴板与 AI，一个快捷键呼出", comment: ""))
                    .font(.system(size: 13.5))
                    .foregroundStyle(ThemeColor.kTextSubtle)
            }
            .opacity(entered ? 1 : 0)
            .offset(y: entered || reduceMotion ? 0 : 8)
            .animation(entranceAnimation(delay: 0.06), value: entered)

            Spacer().frame(height: 24)

            OnboardingCard {
                VStack(spacing: 0) {
                    welcomeHighlightRow(
                        icon: .mingCute("magnifyingglass", ToolIconPalette.blue),
                        title: NSLocalizedString("快速搜索", comment: ""),
                        subtitle: NSLocalizedString("应用、文件、窗口、书签与计算，离线也能用", comment: ""),
                        delay: 0.11
                    )
                    rowDivider
                    welcomeHighlightRow(
                        icon: .mingCute("doc.on.clipboard", ToolIconPalette.teal),
                        title: NSLocalizedString("剪贴板历史", comment: ""),
                        subtitle: NSLocalizedString("自动记录文字、图片与文件，随时检索粘贴", comment: ""),
                        delay: 0.15
                    )
                    rowDivider
                    welcomeHighlightRow(
                        icon: .agentBrand,
                        title: NSLocalizedString("原生 AI 助手", comment: ""),
                        subtitle: NSLocalizedString("按需唤起对话与系统工具，自带 API Key 即用", comment: ""),
                        delay: 0.19
                    )
                }
            }
            .opacity(entered ? 1 : 0)
            .offset(y: entered || reduceMotion ? 0 : 8)
            .animation(entranceAnimation(delay: 0.10), value: entered)

            Spacer(minLength: 20)

            VStack(spacing: 6) {
                Button(NSLocalizedString("开始设置", comment: "")) {
                    navigate(to: .permissions)
                }
                .buttonStyle(OnboardingActionButtonStyle(prominent: true, minWidth: 196, height: 34))
                .keyboardShortcut(.defaultAction)

                Button(NSLocalizedString("跳过", comment: "")) {
                    app.preferences.hasCompletedOnboarding = true
                    onSkip()
                }
                .buttonStyle(OnboardingGhostButtonStyle())
            }
            .opacity(entered ? 1 : 0)
            .offset(y: entered || reduceMotion ? 0 : 8)
            .animation(entranceAnimation(delay: 0.22), value: entered)

            Spacer().frame(height: 22)
        }
    }

    private func welcomeHighlightRow(icon: OnboardingIconBadge.Icon, title: String, subtitle: String, delay: Double) -> some View {
        HStack(spacing: 12) {
            OnboardingIconBadge(icon: icon)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(ThemeColor.kText)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(ThemeColor.kTextSubtle)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(entered ? 1 : 0)
        .offset(y: entered || reduceMotion ? 0 : 5)
        .animation(entranceAnimation(delay: delay), value: entered)
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
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

            Text(NSLocalizedString("只申请必要能力，日历和备忘录会在首次使用时再询问", comment: ""))
                .font(.system(size: 12))
                .foregroundStyle(ThemeColor.kTextSubtlest)
                .padding(.horizontal, 4)

            Spacer(minLength: 0)
        }
    }

    private func permissionRow<Trailing: View>(
        icon: OnboardingIconBadge.Icon,
        title: String,
        description: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            OnboardingIconBadge(icon: icon)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(ThemeColor.kText)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(ThemeColor.kTextSubtle)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Step 3: Shortcuts

    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader(
                title: NSLocalizedString("设置快捷键", comment: ""),
                subtitle: NSLocalizedString("点击按钮即可录制新组合键，或直接保留默认设置", comment: "")
            )

            OnboardingCard {
                VStack(spacing: 0) {
                    shortcutRow(
                        icon: .mingCute("magnifyingglass", ToolIconPalette.blue),
                        title: NSLocalizedString("唤起启动器", comment: ""),
                        subtitle: NSLocalizedString("搜索应用、文件与指令", comment: ""),
                        label: app.preferences.hotKeyLabel,
                        status: app.hotKeyStatus,
                        apply: setLauncherHotKey
                    )
                    rowDivider
                    shortcutRow(
                        icon: .mingCute("doc.on.clipboard", ToolIconPalette.teal),
                        title: NSLocalizedString("打开剪贴板历史", comment: ""),
                        subtitle: NSLocalizedString("浏览并粘贴最近复制的内容", comment: ""),
                        label: app.preferences.clipboardHotKeyLabel,
                        status: app.clipboardHotKeyStatus,
                        apply: setClipboardHotKey
                    )
                    rowDivider
                    shortcutRow(
                        icon: .agentBrand,
                        title: NSLocalizedString("打开 AI 对话", comment: ""),
                        subtitle: NSLocalizedString("随时呼出对话窗口", comment: ""),
                        label: app.preferences.agentHotKeyLabel,
                        status: app.agentHotKeyStatus,
                        apply: setAgentHotKey
                    )
                }
            }

            Text(NSLocalizedString("Asky 常驻顶部菜单栏，随时通过快捷键唤起", comment: ""))
                .font(.system(size: 12))
                .foregroundStyle(ThemeColor.kTextSubtlest)
                .padding(.horizontal, 4)

            Spacer(minLength: 0)
        }
    }

    private func shortcutRow(
        icon: OnboardingIconBadge.Icon,
        title: String,
        subtitle: String,
        label: String,
        status: String,
        apply: @escaping (UInt32, UInt32, String) -> Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                OnboardingIconBadge(icon: icon)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(ThemeColor.kText)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(ThemeColor.kTextSubtle)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                HotKeyRecorder(label: label, allowsPlainKey: false, apply: apply)
                    .frame(width: 172, height: 30)
            }
            if !status.isEmpty, status != NSLocalizedString("已注册", comment: "") {
                Text(status)
                    .font(.system(size: 11.5))
                    .foregroundStyle(ThemeColor.kTextNegative)
                    .padding(.leading, 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Step 4: Optional AI Setup

    private var aiStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: NSLocalizedString("配置 AI 助手", comment: ""),
                subtitle: NSLocalizedString("不配置模型也能畅用搜索、剪贴板与预览", comment: "")
            )

            OnboardingCard {
                VStack(spacing: 0) {
                    HStack {
                        Text(NSLocalizedString("供应商", comment: ""))
                            .font(.system(size: 13.5))
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    rowDivider

                    if let preset = ModelProviderPreset.find(draft.provider) {
                        HStack {
                            Text(NSLocalizedString("模型", comment: ""))
                                .font(.system(size: 13.5))
                                .foregroundStyle(ThemeColor.kText)
                            Spacer()
                            SettingsChoice(selection: $draft.model, options: preset.models.map { ($0, $0) })
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        rowDivider
                    } else {
                        SettingsTextField(NSLocalizedString("API 地址", comment: ""), text: $draft.baseURL,
                                          prompt: Text("https://api.example.com/v1"))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                        rowDivider
                        SettingsTextField(NSLocalizedString("模型名", comment: ""), text: $draft.model)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                        rowDivider
                    }

                    SettingsSecureField(NSLocalizedString("API Key", comment: ""), text: $apiKey,
                                        prompt: Text(NSLocalizedString(canReuseKey ? "已保存，留空不变" : "输入 API Key", comment: "")))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .disabled(savingModel || checkingModel)
            }

            if let modelMessage {
                Text(modelMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(ThemeColor.kTextNegative)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
            } else {
                Text(NSLocalizedString("稍后也可随时在「设置 › 模型配置」中填写或更改", comment: ""))
                    .font(.system(size: 12))
                    .foregroundStyle(ThemeColor.kTextSubtlest)
                    .padding(.horizontal, 4)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Shared Header & Footer

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(ThemeColor.kText)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(ThemeColor.kTextSubtle)
        }
        .padding(.top, 8)
    }

    private var footerBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(SettingsPalette.separator(scheme))
                .frame(height: 1)
                .padding(.horizontal, 32)

            ZStack {
                HStack(spacing: 6) {
                    ForEach(OnboardingStep.setupSteps) { item in
                        Button { navigate(to: item) } label: {
                            Capsule()
                                .fill(item == step
                                      ? ThemeColor.kText.color(for: scheme).opacity(0.65)
                                      : ThemeColor.kTextSubtlest.color(for: scheme).opacity(0.45))
                                .frame(width: item == step ? 18 : 5, height: 5)
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
                    .buttonStyle(OnboardingActionButtonStyle(prominent: false, minWidth: 84, height: 32))

                    Spacer()

                    if step == .ai {
                        Button(NSLocalizedString("开始使用", comment: "")) {
                            app.preferences.hasCompletedOnboarding = true
                            onFinish()
                        }
                        .buttonStyle(OnboardingActionButtonStyle(prominent: true, minWidth: 96, height: 32))
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button(NSLocalizedString("继续", comment: "")) {
                            if let next = OnboardingStep(rawValue: step.rawValue + 1) {
                                navigate(to: next)
                            }
                        }
                        .buttonStyle(OnboardingActionButtonStyle(prominent: true, minWidth: 92, height: 32))
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .padding(.bottom, 22)
        }
    }

    // MARK: - Helpers

    private var rowDivider: some View {
        Rectangle()
            .fill(SettingsPalette.separator(scheme))
            .frame(height: 1)
            .padding(.horizontal, 16)
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
