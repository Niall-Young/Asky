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

// MARK: - Generous Native Liquid Glass Pill Buttons

private struct OnboardingPillButtonStyle: ButtonStyle {
    var prominent: Bool
    var minWidth: CGFloat = 104
    var height: CGFloat = 38
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
            .foregroundStyle(prominent ? Color.white : OnboardingInk.primary(scheme))
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
                    .scaleEffect(configuration.isPressed ? 0.975 : 1)
                    .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct OnboardingInlinePillButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(OnboardingInk.primary(scheme))
            .padding(.horizontal, 14)
            .frame(minHeight: 30)
            .contentShape(Capsule())

        Group {
            if #available(macOS 26, *), useNativeGlass {
                base
                    .glassEffect(.regular.interactive(), in: Capsule())
            } else {
                base
                    .background(
                        Capsule().fill(scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.045))
                    )
                    .overlay {
                        Capsule().strokeBorder(scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06), lineWidth: 1)
                    }
                    .scaleEffect(configuration.isPressed ? 0.97 : 1)
                    .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - Granted Status Badge

private struct OnboardingGrantedBadge: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var fillGradient: LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(.sRGB, red: 0.24, green: 0.80, blue: 0.48, opacity: 0.14),
                    Color(.sRGB, red: 0.18, green: 0.72, blue: 0.42, opacity: 0.20),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [
                Color(.sRGB, red: 0.16, green: 0.72, blue: 0.42, opacity: 0.08),
                Color(.sRGB, red: 0.14, green: 0.66, blue: 0.38, opacity: 0.14),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var borderColor: Color {
        let boosted = contrast == .increased
        if scheme == .dark {
            return Color(.sRGB, red: 0.36, green: 0.86, blue: 0.56, opacity: boosted ? 0.42 : 0.22)
        }
        return Color(.sRGB, red: 0.14, green: 0.64, blue: 0.36, opacity: boosted ? 0.38 : 0.18)
    }

    private var emblemGradient: LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(.sRGB, red: 0.30, green: 0.84, blue: 0.54, opacity: 1),
                    Color(.sRGB, red: 0.18, green: 0.70, blue: 0.42, opacity: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [
                Color(.sRGB, red: 0.24, green: 0.78, blue: 0.46, opacity: 1),
                Color(.sRGB, red: 0.14, green: 0.64, blue: 0.36, opacity: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(emblemGradient)
                    .frame(width: 16, height: 16)
                    .shadow(
                        color: Color(.sRGB, red: 0.14, green: 0.64, blue: 0.36, opacity: scheme == .dark ? 0.28 : 0.24),
                        radius: 2,
                        y: 1
                    )
                Image(mingCute: "checkmark", size: 10)
                    .foregroundStyle(Color.white)
            }
            .accessibilityHidden(true)

            Text(NSLocalizedString("已开启", comment: ""))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OnboardingInk.positive(scheme))
        }
        .padding(.leading, 6)
        .padding(.trailing, 11)
        .frame(height: 28)
        .background(fillGradient, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(borderColor, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
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
    case shortcuts
    case ai

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
                    case .shortcuts:
                        shortcutsStep.transition(stepTransition)
                    case .ai:
                        aiStep.transition(stepTransition)
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
            Spacer().frame(height: 52)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 84, height: 84)
                .shadow(color: Color.black.opacity(scheme == .dark ? 0.30 : 0.08), radius: 16, y: 6)
                .scaleEffect(showLogo ? 1 : 0.88)
                .opacity(showLogo ? 1 : 0)
                .blur(radius: showLogo ? 0 : 8)
                .accessibilityHidden(true)

            Spacer().frame(height: 22)

            Text(NSLocalizedString("你好，欢迎使用 Asky", comment: ""))
                .font(.system(size: 23, weight: .medium))
                .tracking(-0.3)
                .foregroundStyle(OnboardingInk.primary(scheme))
                .modifier(SilkSweepReveal(progress: greetingSweep))
                .offset(y: greetingSweep > 0 ? 0 : 8)

            Spacer().frame(height: 14)

            Text(NSLocalizedString("搜索、剪贴板与 AI，一个快捷键呼出", comment: ""))
                .font(.system(size: 13.5))
                .foregroundStyle(OnboardingInk.secondary(scheme))
                .opacity(showSubtitle ? 1 : 0)
                .offset(y: showSubtitle ? 0 : 8)

            Spacer()

            HStack(spacing: 12) {
                Button(NSLocalizedString("跳过", comment: "")) {
                    app.preferences.hasCompletedOnboarding = true
                    onSkip()
                }
                .buttonStyle(OnboardingPillButtonStyle(prominent: false, minWidth: 112, height: 40))

                Button(NSLocalizedString("开始设置", comment: "")) {
                    navigate(to: .permissions)
                }
                .buttonStyle(OnboardingPillButtonStyle(prominent: true, minWidth: 136, height: 40))
            }
            .opacity(showActions ? 1 : 0)
            .offset(y: showActions ? 0 : 10)

            Spacer().frame(height: 44)
        }
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(NSLocalizedString("开启常用权限", comment: ""))
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(OnboardingInk.primary(scheme))
                .padding(.top, 14)

            OnboardingCleanCard {
                VStack(spacing: 0) {
                    permissionRow(
                        iconAsset: "Onboarding-accessibility",
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
                        iconAsset: "Onboarding-bookmarks",
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
                        iconAsset: "Onboarding-launch",
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
        iconAsset: String,
        title: String,
        description: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 14) {
            Image(iconAsset)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
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
        OnboardingGrantedBadge()
    }

    // MARK: - Step 3: Shortcuts

    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(NSLocalizedString("设置快捷键", comment: ""))
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(OnboardingInk.primary(scheme))
                .padding(.top, 14)

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

            Spacer(minLength: 0)
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
                    .frame(width: 172, height: 32)
            }
            if !status.isEmpty, status != NSLocalizedString("已注册", comment: "") {
                Text(status)
                    .font(.system(size: 11.5))
                    .foregroundStyle(ThemeColor.kTextNegative)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Step 4: Optional AI Setup

    private var aiStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(NSLocalizedString("配置 AI 助手", comment: ""))
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(OnboardingInk.primary(scheme))
                .padding(.top, 14)

            OnboardingCleanCard {
                VStack(spacing: 0) {
                    HStack {
                        Text(NSLocalizedString("供应商", comment: ""))
                            .foregroundStyle(OnboardingInk.primary(scheme))
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
                                .foregroundStyle(OnboardingInk.primary(scheme))
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
                            .padding(.vertical, 10)
                        rowDivider
                        SettingsTextField(NSLocalizedString("模型名", comment: ""), text: $draft.model)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
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
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                }
                .disabled(savingModel || checkingModel)
            }

            if let modelMessage {
                Text(modelMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(ThemeColor.kTextNegative)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Footer (Steps 2–4)

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

                if step == .ai {
                    Button(NSLocalizedString("开始使用", comment: "")) {
                        app.preferences.hasCompletedOnboarding = true
                        onFinish()
                    }
                    .buttonStyle(OnboardingPillButtonStyle(prominent: true, minWidth: 112, height: 38))
                } else {
                    Button(NSLocalizedString("继续", comment: "")) {
                        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
                            navigate(to: next)
                        }
                    }
                    .buttonStyle(OnboardingPillButtonStyle(prominent: true, minWidth: 104, height: 38))
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
