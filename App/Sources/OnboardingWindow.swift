import AppKit
import Carbon.HIToolbox
import Combine
import Contracts
import SwiftUI
import Theme
import ToolService

/// First-launch welcome and setup window: airy light hierarchy, gentle silk glow, generous controls.
@MainActor
enum OnboardingWindow {
    static let size = NSSize(width: 560, height: 460)

    static func make(app: AppModel, onFinish: @escaping () -> Void, onDismiss: @escaping () -> Void) -> NSWindow {
        let controller = OnboardingContainerController(app: app, onFinish: onFinish, onDismiss: onDismiss)
        let window = SettingsEditingWindow(contentRect: NSRect(origin: .zero, size: size),
                                           styleMask: [.titled, .closable, .fullSizeContentView],
                                           backing: .buffered, defer: false)
        window.animationBehavior = .documentWindow
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
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
        let content = NSHostingView(rootView: OnboardingView(app: app, onFinish: onFinish, onSkip: onDismiss) { [weak self] in
            self?.updateAppearance()
        })
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
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

// MARK: - Refined Ink Palette (Soft, Never Harsh Black)

private enum OnboardingInk {
    static func primary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(.sRGB, red: 0.93, green: 0.94, blue: 0.97, opacity: 1)
            : Color(.sRGB, red: 0.16, green: 0.19, blue: 0.26, opacity: 1)
    }

    static func secondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(.sRGB, red: 0.62, green: 0.65, blue: 0.72, opacity: 1)
            : Color(.sRGB, red: 0.45, green: 0.49, blue: 0.56, opacity: 1)
    }

    static func tertiary(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(.sRGB, red: 0.46, green: 0.49, blue: 0.56, opacity: 1)
            : Color(.sRGB, red: 0.58, green: 0.61, blue: 0.68, opacity: 1)
    }

    static func positive(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(.sRGB, red: 0.34, green: 0.82, blue: 0.54, opacity: 1)
            : Color(.sRGB, red: 0.16, green: 0.60, blue: 0.36, opacity: 1)
    }
}

// MARK: - Whisper-Light Silk Ambient Backdrop

private struct OnboardingLuminousCanvas: View {
    let step: OnboardingStep
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var baseColor: Color {
        scheme == .dark
            ? Color(.sRGB, red: 0.085, green: 0.090, blue: 0.106, opacity: 1)
            : Color(.sRGB, red: 0.996, green: 0.997, blue: 1.0, opacity: 1)
    }

    var body: some View {
        ZStack {
            baseColor
            if #available(macOS 15, *) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                    let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    silkMesh(time: t)
                }
            } else {
                legacySilkGradient
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @available(macOS 15, *)
    private func silkMesh(time t: Double) -> some View {
        let phase = Double(step.rawValue) * 0.85
        let dx = Float(0.07 * sin(t * 0.32 + phase))
        let dy = Float(0.04 * cos(t * 0.25 + phase))
        let midY: Float = step == .welcome ? 0.44 : 0.30

        let colors: [Color] = scheme == .dark
            ? [
                Color(.sRGB, red: 0.10, green: 0.14, blue: 0.24, opacity: 1),
                Color(.sRGB, red: 0.13, green: 0.11, blue: 0.22, opacity: 1),
                Color(.sRGB, red: 0.16, green: 0.11, blue: 0.18, opacity: 1),
                Color(.sRGB, red: 0.088, green: 0.094, blue: 0.118, opacity: 1),
                Color(.sRGB, red: 0.088, green: 0.092, blue: 0.112, opacity: 1),
                Color(.sRGB, red: 0.092, green: 0.090, blue: 0.110, opacity: 1),
                baseColor, baseColor, baseColor,
            ]
            : [
                Color(.sRGB, red: 0.925, green: 0.958, blue: 1.0, opacity: 1),
                Color(.sRGB, red: 0.955, green: 0.938, blue: 1.0, opacity: 1),
                Color(.sRGB, red: 1.0, green: 0.945, blue: 0.962, opacity: 1),
                Color(.sRGB, red: 0.982, green: 0.990, blue: 1.0, opacity: 1),
                Color(.sRGB, red: 0.996, green: 0.996, blue: 1.0, opacity: 1),
                Color(.sRGB, red: 1.0, green: 0.988, blue: 0.992, opacity: 1),
                baseColor, baseColor, baseColor,
            ]

        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                SIMD2(0.0, 0.0), SIMD2(0.5 + dx, 0.0), SIMD2(1.0, 0.0),
                SIMD2(0.0, midY + dy), SIMD2(0.5 - dx * 0.6, midY - dy), SIMD2(1.0, midY + dy * 0.5),
                SIMD2(0.0, 1.0), SIMD2(0.5, 1.0), SIMD2(1.0, 1.0),
            ],
            colors: colors,
            smoothsColors: true
        )
        .animation(reduceMotion ? nil : .spring(response: 0.85, dampingFraction: 0.95), value: step)
    }

    private var legacySilkGradient: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(.sRGB, red: 0.12, green: 0.13, blue: 0.21, opacity: 1), baseColor]
                : [Color(.sRGB, red: 0.94, green: 0.96, blue: 1.0, opacity: 1), baseColor],
            startPoint: .top,
            endPoint: .center
        )
    }
}

// MARK: - Generous Pill Buttons

private struct OnboardingPillButtonStyle: ButtonStyle {
    var prominent: Bool
    var minWidth: CGFloat = 104
    var height: CGFloat = 38
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(prominent ? Color.white : OnboardingInk.primary(scheme))
            .padding(.horizontal, 20)
            .frame(minWidth: minWidth, minHeight: height)
            .background {
                if prominent {
                    Capsule().fill(Color.accentColor)
                } else {
                    Capsule().fill(scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.045))
                }
            }
            .overlay {
                if !prominent {
                    Capsule().strokeBorder(scheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.06), lineWidth: 1)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

private struct OnboardingInlinePillButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(OnboardingInk.primary(scheme))
            .padding(.horizontal, 14)
            .frame(minHeight: 30)
            .background(
                Capsule().fill(scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.045))
            )
            .overlay {
                Capsule().strokeBorder(scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06), lineWidth: 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

// MARK: - Clean Surface Card

private struct OnboardingCleanCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .background(
                scheme == .dark
                    ? Color(.sRGB, red: 0.132, green: 0.138, blue: 0.158, opacity: 0.90)
                    : Color.white.opacity(0.92),
                in: shape
            )
            .overlay {
                shape.strokeBorder(
                    scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.055),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.18 : 0.025), radius: 12, y: 4)
    }
}

// MARK: - Silky Light-Sweep Reveal

private struct SilkSweepReveal: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .mask {
                GeometryReader { geo in
                    let w = max(geo.size.width, 1)
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: max(0, progress - 0.18)),
                            .init(color: .clear, location: min(1, progress)),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: w * 1.25)
                }
            }
    }
}

// MARK: - Onboarding Steps & View

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case permissions
    case ready

    var id: Int { rawValue }
}

struct OnboardingView: View {
    @Bindable var app: AppModel
    let onFinish: () -> Void
    let onSkip: () -> Void
    let onAppearanceChange: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var transitionForward = true

    // Welcome choreography
    @State private var showLogo = false
    @State private var greetingSweep: CGFloat = 0
    @State private var showSubtitle = false
    @State private var showActions = false

    // Permissions
    @State private var permissionModel = PermissionSettingsModel()
    @State private var requestingChrome = false
    @State private var loginStatus = ToolService.launchAtLoginStatus

    // Optional AI setup
    @State private var showAIForm = false
    @State private var draft = ModelConfigurationDraft(provider: "custom", baseURL: nil, model: nil)
    @State private var apiKey = ""
    @State private var modelMessage: String?
    @State private var savingModel = false
    @State private var checkingModel = false
    @State private var modelSaved = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let permissionTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            OnboardingLuminousCanvas(step: step)

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 30)
                    .compatibleWindowDrag()

                ZStack {
                    switch step {
                    case .welcome:
                        welcomeStep.transition(stepTransition)
                    case .permissions:
                        permissionsStep.transition(stepTransition)
                    case .ready:
                        readyStep.transition(stepTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)

                if step != .welcome {
                    footerBar
                        .padding(.horizontal, 40)
                        .padding(.top, 8)
                        .padding(.bottom, 26)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: OnboardingWindow.size.width, height: OnboardingWindow.size.height)
        .font(.system(size: 14))
        .foregroundStyle(OnboardingInk.primary(scheme))
        .onAppear {
            loadModelDraft()
            loginStatus = ToolService.launchAtLoginStatus
            Task { await refreshPermissions() }
            playWelcomeChoreography()
        }
        .onChange(of: app.preferences.appearance) { _, _ in onAppearanceChange() }
        .onChange(of: step) { _, next in
            if next == .permissions {
                loginStatus = ToolService.launchAtLoginStatus
                Task { await refreshPermissions() }
            }
            if next == .ready {
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
        let enterX: CGFloat = transitionForward ? 24 : -24
        let exitX: CGFloat = transitionForward ? -20 : 20
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: enterX)),
            removal: .opacity.combined(with: .offset(x: exitX))
        )
    }

    private func playWelcomeChoreography() {
        if reduceMotion {
            showLogo = true
            greetingSweep = 1.2
            showSubtitle = true
            showActions = true
            return
        }
        showLogo = false
        greetingSweep = 0
        showSubtitle = false
        showActions = false

        withAnimation(.spring(response: 0.78, dampingFraction: 0.90)) {
            showLogo = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.9)) {
                greetingSweep = 1.2
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.92)) {
                showSubtitle = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.74) {
            withAnimation(.spring(response: 0.58, dampingFraction: 0.92)) {
                showActions = true
            }
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("AskyLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .shadow(color: Color.black.opacity(scheme == .dark ? 0.30 : 0.06), radius: 16, y: 6)
                .scaleEffect(showLogo ? 1 : 0.88)
                .opacity(showLogo ? 1 : 0)
                .blur(radius: showLogo ? 0 : 8)
                .accessibilityHidden(true)

            Spacer().frame(height: 24)

            Text(NSLocalizedString("你好，欢迎使用 Asky", comment: ""))
                .font(.system(size: 23, weight: .medium))
                .tracking(-0.3)
                .foregroundStyle(OnboardingInk.primary(scheme))
                .modifier(SilkSweepReveal(progress: greetingSweep))
                .offset(y: greetingSweep > 0 ? 0 : 8)

            Spacer().frame(height: 8)

            Text(NSLocalizedString("搜索、剪贴板与 AI，一个快捷键呼出", comment: ""))
                .font(.system(size: 13.5))
                .foregroundStyle(OnboardingInk.secondary(scheme))
                .opacity(showSubtitle ? 1 : 0)
                .offset(y: showSubtitle ? 0 : 8)

            Spacer()

            VStack(spacing: 14) {
                Button(NSLocalizedString("开始设置", comment: "")) {
                    navigate(to: .permissions)
                }
                .buttonStyle(OnboardingPillButtonStyle(prominent: true, minWidth: 164, height: 40))

                Button(NSLocalizedString("跳过", comment: "")) {
                    app.preferences.hasCompletedOnboarding = true
                    onSkip()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(OnboardingInk.tertiary(scheme))
            }
            .opacity(showActions ? 1 : 0)
            .offset(y: showActions ? 0 : 10)

            Spacer().frame(height: 28)
        }
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text(NSLocalizedString("开启常用权限", comment: ""))
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(OnboardingInk.primary(scheme))
                Text(NSLocalizedString("按需开启，随时可在设置中调整", comment: ""))
                    .font(.system(size: 13))
                    .foregroundStyle(OnboardingInk.secondary(scheme))
            }
            .padding(.top, 12)

            OnboardingCleanCard {
                VStack(spacing: 0) {
                    permissionRow(
                        symbol: "accessibility",
                        tint: ToolIconPalette.blue,
                        title: NSLocalizedString("辅助功能", comment: ""),
                        description: NSLocalizedString("自动粘贴与窗口切换", comment: "")
                    ) {
                        if permissionModel.states[.accessibility] == .authorized {
                            grantedLabel
                        } else {
                            Button(NSLocalizedString("去授权", comment: "")) {
                                PermissionAuthorizationWindow.shared.show(.accessibility, colorScheme: scheme)
                            }
                            .buttonStyle(OnboardingInlinePillButtonStyle())
                        }
                    }

                    rowDivider

                    permissionRow(
                        symbol: "bookmark",
                        tint: ToolIconPalette.orange,
                        title: NSLocalizedString("Chrome 书签", comment: ""),
                        description: NSLocalizedString("快速搜索本地书签", comment: "")
                    ) {
                        if app.chromeBookmarkAccessState == .authorized {
                            grantedLabel
                        } else {
                            Button(NSLocalizedString(requestingChrome ? "正在请求…" : "去授权", comment: "")) {
                                requestingChrome = true
                                Task {
                                    await app.authorizeChromeBookmarkFolder()
                                    await app.refreshChromeBookmarkAccess()
                                    requestingChrome = false
                                }
                            }
                            .buttonStyle(OnboardingInlinePillButtonStyle())
                            .disabled(requestingChrome)
                        }
                    }

                    rowDivider

                    permissionRow(
                        symbol: "power",
                        tint: ToolIconPalette.teal,
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
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func permissionRow<Trailing: View>(
        symbol: String,
        tint: Color,
        title: String,
        description: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(scheme == .dark ? 0.18 : 0.10))
                Image(systemName: symbol)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(OnboardingInk.primary(scheme))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(OnboardingInk.secondary(scheme))
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    private var grantedLabel: some View {
        HStack(spacing: 4) {
            Image(mingCute: "checkmark", size: 12)
            Text(NSLocalizedString("已开启", comment: ""))
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(OnboardingInk.positive(scheme))
    }

    // MARK: - Step 3: Shortcuts & Optional AI

    private var readyStep: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(NSLocalizedString("随时呼出 Asky", comment: ""))
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(OnboardingInk.primary(scheme))
                    Text(NSLocalizedString("随时按快捷键呼出", comment: ""))
                        .font(.system(size: 13))
                        .foregroundStyle(OnboardingInk.secondary(scheme))
                }
                .padding(.top, 12)

                OnboardingCleanCard {
                    VStack(spacing: 0) {
                        shortcutRow(title: NSLocalizedString("唤起启动器", comment: ""),
                                    label: app.preferences.hotKeyLabel,
                                    status: app.hotKeyStatus,
                                    apply: setLauncherHotKey)
                        rowDivider
                        shortcutRow(title: NSLocalizedString("打开剪贴板历史", comment: ""),
                                    label: app.preferences.clipboardHotKeyLabel,
                                    status: app.clipboardHotKeyStatus,
                                    apply: setClipboardHotKey)
                        rowDivider
                        shortcutRow(title: NSLocalizedString("打开 AI 对话", comment: ""),
                                    label: app.preferences.agentHotKeyLabel,
                                    status: app.agentHotKeyStatus,
                                    apply: setAgentHotKey)
                    }
                }

                aiOptionalCard
            }
            .padding(.bottom, 8)
        }
    }

    private func shortcutRow(title: String, label: String, status: String,
                             apply: @escaping (UInt32, UInt32, String) -> Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(OnboardingInk.primary(scheme))
                Spacer(minLength: 12)
                HotKeyRecorder(label: label, allowsPlainKey: false, apply: apply)
                    .frame(width: 140, height: 28)
            }
            if !status.isEmpty, status != NSLocalizedString("已注册", comment: "") {
                Text(status)
                    .font(.system(size: 11.5))
                    .foregroundStyle(ThemeColor.kTextNegative)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var aiOptionalCard: some View {
        OnboardingCleanCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    LauncherFunctionIcon(kind: .ai)
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("AI 助手", comment: ""))
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(OnboardingInk.primary(scheme))
                        if app.isModelConfigured && !showAIForm, let cfg = app.modelConfiguration {
                            Text(cfg.modelName)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(OnboardingInk.positive(scheme))
                        } else {
                            Text(NSLocalizedString("不配置模型也能畅用搜索、剪贴板与预览", comment: ""))
                                .font(.system(size: 12))
                                .foregroundStyle(OnboardingInk.secondary(scheme))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Button(NSLocalizedString(showAIForm ? "收起" : (app.isModelConfigured ? "修改配置" : "现在配置"), comment: "")) {
                        let toggle = { showAIForm.toggle() }
                        if reduceMotion { toggle() } else { withAnimation(.spring(response: 0.4, dampingFraction: 0.92), toggle) }
                    }
                    .buttonStyle(OnboardingInlinePillButtonStyle())
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                if showAIForm {
                    rowDivider
                    VStack(spacing: 10) {
                        HStack {
                            Text(NSLocalizedString("供应商", comment: ""))
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
                        if let preset = ModelProviderPreset.find(draft.provider) {
                            HStack {
                                Text(NSLocalizedString("模型", comment: ""))
                                Spacer()
                                SettingsChoice(selection: $draft.model, options: preset.models.map { ($0, $0) })
                            }
                        } else {
                            SettingsTextField(NSLocalizedString("API 地址", comment: ""), text: $draft.baseURL,
                                              prompt: Text("https://api.example.com/v1"))
                            SettingsTextField(NSLocalizedString("模型名", comment: ""), text: $draft.model)
                        }
                        SettingsSecureField(NSLocalizedString("API Key", comment: ""), text: $apiKey,
                                            prompt: Text(NSLocalizedString(canReuseKey ? "已保存，留空不变" : "输入 API Key", comment: "")))
                        HStack {
                            if let preset = ModelProviderPreset.find(draft.provider) {
                                Button {
                                    _ = ToolService.openLauncherURL(preset.keyURL)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(NSLocalizedString("获取 API Key", comment: ""))
                                        Image(mingCute: "arrow.up.right", size: 12)
                                    }
                                    .font(.system(size: 12))
                                    .foregroundStyle(OnboardingInk.secondary(scheme))
                                }
                                .buttonStyle(.plain)
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
                        if let modelMessage {
                            Text(modelMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(ThemeColor.kTextNegative)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(18)
                    .disabled(savingModel || checkingModel)
                    .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Footer (Steps 2 & 3)

    private var footerBar: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases) { item in
                    Button { navigate(to: item) } label: {
                        Capsule()
                            .fill(item == step
                                  ? OnboardingInk.primary(scheme).opacity(0.60)
                                  : OnboardingInk.tertiary(scheme).opacity(0.32))
                            .frame(width: item == step ? 16 : 6, height: 6)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.rawValue + 1)")
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.88), value: step)

            HStack {
                Button(NSLocalizedString("上一步", comment: "")) {
                    if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
                        navigate(to: previous)
                    }
                }
                .buttonStyle(OnboardingPillButtonStyle(prominent: false, minWidth: 96, height: 38))

                Spacer()

                if step == .permissions {
                    Button(NSLocalizedString("继续", comment: "")) {
                        navigate(to: .ready)
                    }
                    .buttonStyle(OnboardingPillButtonStyle(prominent: true, minWidth: 104, height: 38))
                } else {
                    Button(NSLocalizedString("开始使用", comment: "")) {
                        app.preferences.hasCompletedOnboarding = true
                        onFinish()
                    }
                    .buttonStyle(OnboardingPillButtonStyle(prominent: true, minWidth: 112, height: 38))
                }
            }
        }
    }

    // MARK: - Helpers

    private var rowDivider: some View {
        Rectangle()
            .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
            .frame(height: 1)
            .padding(.horizontal, 18)
    }

    private func navigate(to target: OnboardingStep) {
        guard target != step else { return }
        transitionForward = target.rawValue > step.rawValue
        if reduceMotion {
            step = target
        } else {
            withAnimation(.spring(response: 0.44, dampingFraction: 0.94)) {
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
                Task {
                    try? await Task.sleep(for: .milliseconds(1200))
                    modelSaved = false
                    if reduceMotion {
                        showAIForm = false
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.92)) {
                            showAIForm = false
                        }
                    }
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
