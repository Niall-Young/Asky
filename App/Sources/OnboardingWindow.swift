import AppKit
import Carbon.HIToolbox
import Combine
import Contracts
import SwiftUI
import Theme
import ToolService

/// First-launch welcome and setup window with diffused ambient light and Apple-inspired fluid motion.
@MainActor
enum OnboardingWindow {
    static let size = NSSize(width: 640, height: 520)

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

// MARK: - Ambient Diffused Light Backdrop

private struct OnboardingAmbientBackdrop: View {
    let step: OnboardingStep
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var opaque: Bool { reduceTransparency || contrast == .increased }

    var body: some View {
        ZStack {
            SettingsBackdrop()
            if !opaque {
                // Soft milky veil in light mode keeps the glass airy and luminous.
                (scheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.32))
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                    let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    ambientOrbs(time: t)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }

    private func ambientOrbs(time t: Double) -> some View {
        let phase = Double(step.rawValue) * 1.15
        let isDark = scheme == .dark
        let sky = Color(.sRGB, red: 0.36, green: 0.72, blue: 1.0, opacity: isDark ? 0.24 : 0.34)
        let lavender = Color(.sRGB, red: 0.62, green: 0.50, blue: 1.0, opacity: isDark ? 0.22 : 0.28)
        let peach = Color(.sRGB, red: 1.0, green: 0.64, blue: 0.72, opacity: isDark ? 0.16 : 0.26)
        let mint = Color(.sRGB, red: 0.36, green: 0.88, blue: 0.80, opacity: isDark ? 0.16 : 0.24)

        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [sky, .clear], center: .center, startRadius: 0, endRadius: 230))
                    .frame(width: 460, height: 460)
                    .position(
                        x: w * (0.24 + 0.08 * sin(t * 0.28 + phase)),
                        y: h * (0.22 + 0.07 * cos(t * 0.22 + phase))
                    )
                Circle()
                    .fill(RadialGradient(colors: [lavender, .clear], center: .center, startRadius: 0, endRadius: 240))
                    .frame(width: 480, height: 480)
                    .position(
                        x: w * (0.78 + 0.07 * cos(t * 0.24 + phase * 0.8)),
                        y: h * (0.26 + 0.08 * sin(t * 0.19 + phase))
                    )
                Circle()
                    .fill(RadialGradient(colors: [peach, .clear], center: .center, startRadius: 0, endRadius: 220))
                    .frame(width: 440, height: 440)
                    .position(
                        x: w * (0.68 + 0.09 * sin(t * 0.21 + 1.8 + phase)),
                        y: h * (0.82 + 0.06 * cos(t * 0.26 + phase))
                    )
                Circle()
                    .fill(RadialGradient(colors: [mint, .clear], center: .center, startRadius: 0, endRadius: 210))
                    .frame(width: 420, height: 420)
                    .position(
                        x: w * (0.20 + 0.07 * cos(t * 0.23 + 2.4 + phase)),
                        y: h * (0.78 + 0.07 * sin(t * 0.20 + phase))
                    )
            }
            .blur(radius: 38)
            .animation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.95), value: step)
        }
    }
}

// MARK: - Apple-style Cursive "hello" Calligraphy

private struct HelloWordmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Designed in a 260 x 100 coordinate canvas and scaled cleanly to rect.
        let sx = rect.width / 260
        let sy = rect.height / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }

        var path = Path()
        // h — graceful entry sweep into tall ascender loop, down to baseline, then soft arch
        path.move(to: p(14, 72))
        path.addCurve(to: p(46, 12), control1: p(30, 56), control2: p(52, 26))
        path.addCurve(to: p(36, 22), control1: p(42, 4), control2: p(38, 10))
        path.addCurve(to: p(28, 82), control1: p(32, 42), control2: p(29, 64))
        path.addCurve(to: p(52, 50), control1: p(33, 66), control2: p(42, 50))
        path.addCurve(to: p(66, 76), control1: p(61, 50), control2: p(59, 76))
        // e — flowing loop
        path.addCurve(to: p(94, 58), control1: p(75, 76), control2: p(88, 68))
        path.addCurve(to: p(82, 52), control1: p(99, 51), control2: p(90, 48))
        path.addCurve(to: p(86, 79), control1: p(72, 56), control2: p(74, 79))
        path.addCurve(to: p(114, 62), control1: p(97, 79), control2: p(106, 72))
        // l (first) — tall airy loop
        path.addCurve(to: p(134, 12), control1: p(126, 46), control2: p(138, 24))
        path.addCurve(to: p(124, 22), control1: p(131, 4), control2: p(126, 10))
        path.addCurve(to: p(124, 79), control1: p(119, 44), control2: p(116, 79))
        path.addCurve(to: p(150, 62), control1: p(134, 79), control2: p(142, 72))
        // l (second) — matching tall airy loop
        path.addCurve(to: p(170, 12), control1: p(162, 46), control2: p(174, 24))
        path.addCurve(to: p(160, 22), control1: p(167, 4), control2: p(162, 10))
        path.addCurve(to: p(160, 79), control1: p(155, 44), control2: p(152, 79))
        path.addCurve(to: p(190, 56), control1: p(170, 79), control2: p(180, 68))
        // o — smooth rounded bowl with an effortless exit flourish
        path.addCurve(to: p(214, 52), control1: p(198, 48), control2: p(208, 48))
        path.addCurve(to: p(190, 67), control1: p(202, 49), control2: p(190, 55))
        path.addCurve(to: p(206, 80), control1: p(190, 78), control2: p(198, 82))
        path.addCurve(to: p(222, 60), control1: p(216, 78), control2: p(224, 69))
        path.addCurve(to: p(212, 52), control1: p(221, 53), control2: p(216, 51))
        path.addCurve(to: p(246, 55), control1: p(222, 62), control2: p(235, 62))
        return path
    }
}

private struct HelloCalligraphyView: View {
    let progress: CGFloat
    @Environment(\.colorScheme) private var scheme

    private var strokeGradient: LinearGradient {
        let colors: [Color] = scheme == .dark
            ? [
                Color(.sRGB, red: 0.48, green: 0.78, blue: 1.0, opacity: 1),
                Color(.sRGB, red: 0.72, green: 0.58, blue: 1.0, opacity: 1),
                Color(.sRGB, red: 1.0, green: 0.58, blue: 0.76, opacity: 1),
                Color(.sRGB, red: 1.0, green: 0.76, blue: 0.52, opacity: 1),
            ]
            : [
                Color(.sRGB, red: 0.16, green: 0.46, blue: 0.96, opacity: 1),
                Color(.sRGB, red: 0.48, green: 0.32, blue: 0.92, opacity: 1),
                Color(.sRGB, red: 0.86, green: 0.30, blue: 0.58, opacity: 1),
                Color(.sRGB, red: 0.92, green: 0.48, blue: 0.24, opacity: 1),
            ]
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        ZStack {
            HelloWordmarkShape()
                .trim(from: 0, to: progress)
                .stroke(strokeGradient, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                .opacity(scheme == .dark ? 0.35 : 0.22)
                .blur(radius: 10)
            HelloWordmarkShape()
                .trim(from: 0, to: progress)
                .stroke(strokeGradient, style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 224, height: 86)
        .accessibilityLabel("Hello")
    }
}

// MARK: - Airy Translucent Surface Card

private struct OnboardingGlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var opaque: Bool { reduceTransparency || contrast == .increased }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content
            .background {
                if opaque {
                    shape.fill(SettingsPalette.surface(scheme, opaque: true))
                } else {
                    shape.fill(scheme == .dark ? Color.white.opacity(0.065) : Color.white.opacity(0.52))
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: scheme == .dark
                            ? [Color.white.opacity(0.16), Color.white.opacity(0.04)]
                            : [Color.white.opacity(0.85), Color.black.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.16 : 0.04), radius: 14, y: 6)
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

    // Hero welcome entrance choreography
    @State private var helloProgress: CGFloat = 0
    @State private var showBrand = false
    @State private var showChips = false
    @State private var showCTA = false

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
            OnboardingAmbientBackdrop(step: step)

            VStack(spacing: 0) {
                // Invisible drag handle across the titlebar area
                Color.clear
                    .frame(height: 36)
                    .compatibleWindowDrag()

                ZStack {
                    switch step {
                    case .welcome:
                        welcomeStep
                            .transition(stepTransition)
                    case .permissions:
                        permissionsStep
                            .transition(stepTransition)
                    case .ready:
                        readyStep
                            .transition(stepTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 36)

                footerBar
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    .padding(.bottom, 22)
            }
        }
        .frame(width: OnboardingWindow.size.width, height: OnboardingWindow.size.height)
        .font(.system(size: 14))
        .foregroundStyle(ThemeColor.kText)
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
        let insertionOffset: CGFloat = transitionForward ? 28 : -28
        let removalOffset: CGFloat = transitionForward ? -24 : 24
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: insertionOffset)).combined(with: .scale(scale: 0.985)),
            removal: .opacity.combined(with: .offset(x: removalOffset)).combined(with: .scale(scale: 0.985))
        )
    }

    private func playWelcomeChoreography() {
        if reduceMotion {
            helloProgress = 1
            showBrand = true
            showChips = true
            showCTA = true
            return
        }
        helloProgress = 0
        showBrand = false
        showChips = false
        showCTA = false

        withAnimation(.timingCurve(0.28, 0.05, 0.22, 1.0, duration: 1.75)) {
            helloProgress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.92)) {
                showBrand = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            withAnimation(.spring(response: 0.68, dampingFraction: 0.90)) {
                showChips = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.32) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.92)) {
                showCTA = true
            }
        }
    }

    // MARK: - Step 1: Welcome ("hello")

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)

            HelloCalligraphyView(progress: helloProgress)
                .padding(.bottom, 18)

            VStack(spacing: 12) {
                Image("AskyLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .shadow(color: Color.black.opacity(scheme == .dark ? 0.35 : 0.10), radius: 14, y: 6)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text(NSLocalizedString("欢迎使用 Asky", comment: ""))
                        .font(.system(size: 26, weight: .semibold))
                        .tracking(-0.4)
                    Text(NSLocalizedString("搜索、剪贴板与 AI，一个快捷键呼出", comment: ""))
                        .font(.system(size: 14.5))
                        .foregroundStyle(ThemeColor.kTextSubtle)
                }
            }
            .opacity(showBrand ? 1 : 0)
            .offset(y: showBrand ? 0 : 14)
            .blur(radius: showBrand ? 0 : 6)

            Spacer(minLength: 24)

            HStack(spacing: 10) {
                welcomeChip(icon: .applications, title: NSLocalizedString("快速搜索", comment: ""), shortcut: app.preferences.hotKeyLabel)
                welcomeChip(icon: .clipboardText, title: NSLocalizedString("剪贴板历史", comment: ""), shortcut: app.preferences.clipboardHotKeyLabel)
                welcomeChip(icon: .ai, title: NSLocalizedString("AI 助手", comment: ""), shortcut: app.preferences.agentHotKeyLabel)
            }
            .opacity(showChips ? 1 : 0)
            .offset(y: showChips ? 0 : 12)
            .blur(radius: showChips ? 0 : 4)

            Spacer(minLength: 18)

            Text(NSLocalizedString("Asky 常驻顶部菜单栏，随时通过快捷键唤起", comment: ""))
                .font(.system(size: 12))
                .foregroundStyle(ThemeColor.kTextSubtlest)
                .opacity(showCTA ? 1 : 0)

            Spacer(minLength: 8)
        }
    }

    private func welcomeChip(icon: LauncherFunctionIcon.Kind, title: String, shortcut: String) -> some View {
        OnboardingGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    LauncherFunctionIcon(kind: icon)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    shortcutPill(shortcut)
                }
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Step 2: Essential Permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("开启常用权限", comment: ""))
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.3)
                Text(NSLocalizedString("只申请必要能力，日历和备忘录会在首次使用时再询问", comment: ""))
                    .font(.system(size: 13.5))
                    .foregroundStyle(ThemeColor.kTextSubtle)
            }
            .padding(.top, 4)

            VStack(spacing: 10) {
                permissionCard(
                    symbol: "accessibility",
                    tint: ToolIconPalette.blue,
                    title: NSLocalizedString("辅助功能", comment: ""),
                    badge: NSLocalizedString("必备", comment: ""),
                    badgeHighlighted: true,
                    description: NSLocalizedString("用于剪贴板自动粘贴与应用窗口搜索", comment: ""),
                    granted: permissionModel.states[.accessibility] == .authorized
                ) {
                    if permissionModel.states[.accessibility] == .authorized {
                        grantedBadge
                    } else {
                        SettingsButton(NSLocalizedString("去授权", comment: "")) {
                            PermissionAuthorizationWindow.shared.show(.accessibility, colorScheme: scheme)
                        }
                    }
                }

                permissionCard(
                    symbol: "bookmark",
                    tint: ToolIconPalette.orange,
                    title: NSLocalizedString("Chrome 书签与链接", comment: ""),
                    badge: NSLocalizedString("推荐", comment: ""),
                    badgeHighlighted: false,
                    description: NSLocalizedString("用于检索 Chrome 本地书签与已知站点，不读取浏览历史", comment: ""),
                    granted: app.chromeBookmarkAccessState == .authorized
                ) {
                    if app.chromeBookmarkAccessState == .authorized {
                        grantedBadge
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

                permissionCard(
                    symbol: "power",
                    tint: ToolIconPalette.teal,
                    title: NSLocalizedString("登录时启动", comment: ""),
                    badge: NSLocalizedString("推荐", comment: ""),
                    badgeHighlighted: false,
                    description: NSLocalizedString("开机自动在菜单栏就绪，随时用快捷键呼出", comment: ""),
                    granted: loginStatus == .enabled
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

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Image(mingCute: "info.circle", size: 13)
                    .foregroundStyle(ThemeColor.kTextSubtlest)
                    .accessibilityHidden(true)
                Text(NSLocalizedString("权限随时可在「设置 › 系统权限」中调整或撤销", comment: ""))
                    .font(.system(size: 12))
                    .foregroundStyle(ThemeColor.kTextSubtlest)
            }
        }
    }

    private func permissionCard<Trailing: View>(
        symbol: String,
        tint: Color,
        title: String,
        badge: String,
        badgeHighlighted: Bool,
        description: String,
        granted: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        OnboardingGlassCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.gradient)
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
                .shadow(color: tint.opacity(scheme == .dark ? 0.35 : 0.25), radius: 8, y: 3)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                        Text(badge)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(badgeHighlighted ? tint : ThemeColor.kTextSubtle.color(for: scheme))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                badgeHighlighted ? tint.opacity(scheme == .dark ? 0.22 : 0.12)
                                    : ThemeColor.kBackgroundNeutral.color(for: scheme),
                                in: Capsule()
                            )
                    }
                    Text(description)
                        .font(.system(size: 12.5))
                        .foregroundStyle(ThemeColor.kTextSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                trailing()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var grantedBadge: some View {
        HStack(spacing: 5) {
            Image(mingCute: "checkmark", size: 12)
            Text(NSLocalizedString("已开启", comment: ""))
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(ThemeColor.kTextPositive)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(ThemeColor.kTextPositive.color(for: scheme).opacity(0.14), in: Capsule())
    }

    // MARK: - Step 3: Ready — Shortcuts & Optional AI

    private var readyStep: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("一切就绪", comment: ""))
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.3)
                    Text(NSLocalizedString("随时按快捷键呼出 Asky，AI 助手可在需要时再配置", comment: ""))
                        .font(.system(size: 13.5))
                        .foregroundStyle(ThemeColor.kTextSubtle)
                }
                .padding(.top, 4)

                OnboardingGlassCard {
                    VStack(spacing: 0) {
                        shortcutRow(title: NSLocalizedString("唤起启动器", comment: ""),
                                    label: app.preferences.hotKeyLabel,
                                    status: app.hotKeyStatus,
                                    apply: setLauncherHotKey)
                        cardDivider
                        shortcutRow(title: NSLocalizedString("打开剪贴板历史", comment: ""),
                                    label: app.preferences.clipboardHotKeyLabel,
                                    status: app.clipboardHotKeyStatus,
                                    apply: setClipboardHotKey)
                        cardDivider
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
                Spacer(minLength: 12)
                HotKeyRecorder(label: label, allowsPlainKey: false, apply: apply)
                    .frame(width: 148, height: 28)
            }
            if !status.isEmpty, status != NSLocalizedString("已注册", comment: "") {
                Text(status)
                    .font(.system(size: 11.5))
                    .foregroundStyle(ThemeColor.kTextNegative)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var aiOptionalCard: some View {
        OnboardingGlassCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    LauncherFunctionIcon(kind: .ai)
                        .scaleEffect(1.15)
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(NSLocalizedString("AI 助手", comment: ""))
                                .font(.system(size: 14, weight: .medium))
                            Text(NSLocalizedString("可选", comment: ""))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(ThemeColor.kTextSubtle)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(ThemeColor.kBackgroundNeutral.color(for: scheme), in: Capsule())
                        }
                        if app.isModelConfigured && !showAIForm, let cfg = app.modelConfiguration {
                            HStack(spacing: 5) {
                                Image(mingCute: "checkmark", size: 12)
                                    .foregroundStyle(ThemeColor.kTextPositive)
                                Text("\(cfg.modelName) · \(cfg.baseURL.host ?? cfg.baseURL.absoluteString)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(ThemeColor.kTextSubtle)
                                    .lineLimit(1)
                            }
                        } else {
                            Text(NSLocalizedString("不配置模型也能畅用搜索、剪贴板与预览", comment: ""))
                                .font(.system(size: 12.5))
                                .foregroundStyle(ThemeColor.kTextSubtle)
                        }
                    }
                    Spacer(minLength: 8)
                    SettingsButton(NSLocalizedString(showAIForm ? "收起" : (app.isModelConfigured ? "修改配置" : "现在配置"), comment: "")) {
                        let toggle = { showAIForm.toggle() }
                        if reduceMotion { toggle() } else { withAnimation(.spring(response: 0.42, dampingFraction: 0.9), toggle) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if showAIForm {
                    cardDivider
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
                                    .foregroundStyle(ThemeColor.kTextSubtle)
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
                    .padding(16)
                    .disabled(savingModel || checkingModel)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        ZStack {
            // Centered morphing step dots
            HStack(spacing: 7) {
                ForEach(OnboardingStep.allCases) { item in
                    Button { navigate(to: item) } label: {
                        Capsule()
                            .fill(item == step
                                  ? ThemeColor.kText.color(for: scheme).opacity(0.85)
                                  : ThemeColor.kTextSubtlest.color(for: scheme).opacity(0.35))
                            .frame(width: item == step ? 18 : 6, height: 6)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.rawValue + 1)")
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.85), value: step)

            HStack {
                if step == .welcome {
                    Button(NSLocalizedString("跳过", comment: "")) {
                        app.preferences.hasCompletedOnboarding = true
                        onSkip()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(ThemeColor.kTextSubtle)
                    .opacity(showCTA ? 1 : 0)
                } else {
                    SettingsButton(NSLocalizedString("上一步", comment: "")) {
                        if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
                            navigate(to: previous)
                        }
                    }
                }

                Spacer()

                switch step {
                case .welcome:
                    Button(NSLocalizedString("开始设置", comment: "")) {
                        navigate(to: .permissions)
                    }
                    .compatibleGlassButtonStyle(prominent: true)
                    .controlSize(.large)
                    .opacity(showCTA ? 1 : 0)
                    .scaleEffect(showCTA ? 1 : 0.95)
                case .permissions:
                    Button(NSLocalizedString("继续", comment: "")) {
                        navigate(to: .ready)
                    }
                    .compatibleGlassButtonStyle(prominent: true)
                    .controlSize(.large)
                case .ready:
                    Button(NSLocalizedString("开始使用 Asky", comment: "")) {
                        app.preferences.hasCompletedOnboarding = true
                        onFinish()
                    }
                    .compatibleGlassButtonStyle(prominent: true)
                    .controlSize(.large)
                }
            }
        }
    }

    // MARK: - Helpers

    private var cardDivider: some View {
        Rectangle()
            .fill(SettingsPalette.separator(scheme))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private func shortcutPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
            .foregroundStyle(ThemeColor.kTextSubtle)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05), in: Capsule())
    }

    private func navigate(to target: OnboardingStep) {
        guard target != step else { return }
        transitionForward = target.rawValue > step.rawValue
        if reduceMotion {
            step = target
        } else {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.92)) {
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
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
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
