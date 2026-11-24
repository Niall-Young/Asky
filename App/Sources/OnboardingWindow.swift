#if DEBUG
import AppKit
import Carbon.HIToolbox
import Combine
import Contracts
import SwiftUI
import Theme
import ToolService

/// First-launch welcome and setup window: monochrome ink, diffused ambient light,
/// single-layer large-radius light-neumorphic liquid glass, and restrained typography.
@MainActor
enum OnboardingWindow {
    static let size = NSSize(width: 600, height: 472)

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

// MARK: - Window Backdrop & Diffused Ambient Mesh

private struct OnboardingBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var opaque: Bool { reduceTransparency || contrast == .increased }

    var body: some View {
        if opaque {
            Rectangle().fill(
                scheme == .dark
                    ? Color(.sRGB, red: 0.085, green: 0.09, blue: 0.105, opacity: 1)
                    : Color(.sRGB, red: 0.955, green: 0.96, blue: 0.975, opacity: 1)
            )
        } else if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial {
            OnboardingRegularGlass(scheme: scheme)
                .overlay(
                    scheme == .dark
                        ? Color(.sRGB, red: 0.065, green: 0.07, blue: 0.09, opacity: 0.56)
                        : Color(.sRGB, red: 0.955, green: 0.96, blue: 0.98, opacity: 0.64)
                )
        } else {
            Color.clear
                .nativeGlassBackground(in: Rectangle())
                .overlay(
                    scheme == .dark
                        ? Color(.sRGB, red: 0.065, green: 0.07, blue: 0.09, opacity: 0.52)
                        : Color(.sRGB, red: 0.955, green: 0.96, blue: 0.98, opacity: 0.60)
                )
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
        view.tintColor = NSColor(SettingsPalette.surface(scheme, opaque: true)).withAlphaComponent(0.16)
    }
}

/// Multi-orb atmospheric diffused light behind the single-layer frosted glass surface.
private struct OnboardingDiffusedGlow: View {
    let step: OnboardingStep
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var coolCenter: UnitPoint {
        switch step {
        case .welcome: UnitPoint(x: 0.22, y: 0.12)
        case .permissions: UnitPoint(x: 0.14, y: 0.18)
        case .shortcuts: UnitPoint(x: 0.34, y: 0.14)
        case .ai: UnitPoint(x: 0.80, y: 0.14)
        }
    }

    private var warmCenter: UnitPoint {
        switch step {
        case .welcome: UnitPoint(x: 0.82, y: 0.28)
        case .permissions: UnitPoint(x: 0.84, y: 0.44)
        case .shortcuts: UnitPoint(x: 0.80, y: 0.62)
        case .ai: UnitPoint(x: 0.18, y: 0.58)
        }
    }

    private var mistCenter: UnitPoint {
        switch step {
        case .welcome: UnitPoint(x: 0.50, y: 0.88)
        case .permissions: UnitPoint(x: 0.46, y: 0.86)
        case .shortcuts: UnitPoint(x: 0.24, y: 0.84)
        case .ai: UnitPoint(x: 0.68, y: 0.86)
        }
    }

    var body: some View {
        if !reduceTransparency && contrast != .increased {
            ZStack {
                // Cool silver-periwinkle diffused light
                RadialGradient(
                    colors: scheme == .dark
                        ? [
                            Color(.sRGB, red: 0.44, green: 0.52, blue: 0.78, opacity: 0.30),
                            Color(.sRGB, red: 0.28, green: 0.34, blue: 0.54, opacity: 0.12),
                            .clear,
                        ]
                        : [
                            Color(.sRGB, red: 0.74, green: 0.82, blue: 1.00, opacity: 0.62),
                            Color(.sRGB, red: 0.84, green: 0.88, blue: 1.00, opacity: 0.26),
                            .clear,
                        ],
                    center: coolCenter,
                    startRadius: 8,
                    endRadius: 330
                )

                // Soft warm-champagne / peach whisper
                RadialGradient(
                    colors: scheme == .dark
                        ? [
                            Color(.sRGB, red: 0.64, green: 0.46, blue: 0.48, opacity: 0.24),
                            Color(.sRGB, red: 0.42, green: 0.32, blue: 0.36, opacity: 0.08),
                            .clear,
                        ]
                        : [
                            Color(.sRGB, red: 1.00, green: 0.86, blue: 0.80, opacity: 0.56),
                            Color(.sRGB, red: 0.98, green: 0.90, blue: 0.87, opacity: 0.20),
                            .clear,
                        ],
                    center: warmCenter,
                    startRadius: 8,
                    endRadius: 310
                )

                // Subtle lilac-pearl lower diffusion
                RadialGradient(
                    colors: scheme == .dark
                        ? [
                            Color(.sRGB, red: 0.48, green: 0.46, blue: 0.66, opacity: 0.20),
                            .clear,
                        ]
                        : [
                            Color(.sRGB, red: 0.85, green: 0.83, blue: 0.99, opacity: 0.44),
                            Color(.sRGB, red: 0.91, green: 0.91, blue: 0.99, opacity: 0.14),
                            .clear,
                        ],
                    center: mistCenter,
                    startRadius: 10,
                    endRadius: 290
                )
            }
            .animation(reduceMotion ? nil : .spring(response: 0.72, dampingFraction: 0.94), value: step)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Single-Layer Large-Radius Light-Neumorphic Liquid Glass

private enum OnboardingInk {
    static func solidFill(_ scheme: ColorScheme, hovered: Bool = false) -> Color {
        if scheme == .dark {
            return hovered
                ? Color(.sRGB, red: 1.00, green: 1.00, blue: 1.00, opacity: 1)
                : Color(.sRGB, red: 0.94, green: 0.945, blue: 0.96, opacity: 1)
        }
        return hovered
            ? Color(.sRGB, red: 0.16, green: 0.17, blue: 0.20, opacity: 1)
            : Color(.sRGB, red: 0.085, green: 0.09, blue: 0.11, opacity: 1)
    }

    static func solidForeground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(.sRGB, red: 0.075, green: 0.08, blue: 0.095, opacity: 1)
            : Color.white
    }
}

/// One clean 24pt continuous-radius liquid-glass card with specular catchlight and soft shadow.
/// Rows sit directly inside without nested borders.
private struct OnboardingGlassCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var opaque: Bool { reduceTransparency || contrast == .increased }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        content
            .clipShape(shape)
            .background {
                if opaque {
                    shape.fill(
                        scheme == .dark
                            ? Color(.sRGB, red: 0.14, green: 0.145, blue: 0.16, opacity: 1)
                            : Color.white
                    )
                } else {
                    shape.fill(
                        LinearGradient(
                            colors: scheme == .dark
                                ? [Color.white.opacity(0.085), Color.white.opacity(0.032)]
                                : [Color.white.opacity(0.76), Color.white.opacity(0.54)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .overlay {
                // Soft directional catchlight rim — bright top-left, fading away at bottom-right.
                shape.strokeBorder(
                    LinearGradient(
                        colors: scheme == .dark
                            ? [
                                Color.white.opacity(opaque ? 0.26 : 0.22),
                                Color.white.opacity(opaque ? 0.12 : 0.06),
                                Color.white.opacity(opaque ? 0.08 : 0.02),
                            ]
                            : [
                                Color.white.opacity(0.96),
                                Color.white.opacity(0.45),
                                Color.black.opacity(opaque ? 0.14 : 0.045),
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.85
                )
                .allowsHitTesting(false)
            }
            .shadow(
                color: Color.black.opacity(scheme == .dark ? 0.34 : 0.055),
                radius: 22,
                y: 10
            )
            .shadow(
                color: Color.black.opacity(scheme == .dark ? 0.14 : 0.024),
                radius: 3,
                y: 1
            )
    }
}

/// Borderless row inside `OnboardingGlassCard` with subtle hover lift.
private struct OnboardingCardRow<Content: View>: View {
    var verticalPadding: CGFloat = 13
    var horizontalPadding: CGFloat = 20
    @ViewBuilder var content: Content
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                scheme == .dark
                    ? Color.white.opacity(hovered ? 0.035 : 0)
                    : Color.white.opacity(hovered ? 0.36 : 0)
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .onHover { hovered = $0 }
    }
}

/// Monochrome pill CTA button: solid ink in primary mode, frosted glass-neumorphic in secondary mode.
private struct OnboardingActionButtonStyle: ButtonStyle {
    var prominent: Bool
    var minWidth: CGFloat = 94
    var height: CGFloat = 34
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var opaque: Bool { reduceTransparency || contrast == .increased }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(
                prominent
                    ? OnboardingInk.solidForeground(scheme)
                    : ThemeColor.kText.color(for: scheme)
            )
            .padding(.horizontal, 20)
            .frame(minWidth: minWidth, minHeight: height)
            .contentShape(Capsule())
            .background {
                if prominent {
                    Capsule()
                        .fill(OnboardingInk.solidFill(scheme, hovered: hovered))
                } else if opaque {
                    Capsule()
                        .fill(
                            scheme == .dark
                                ? Color(.sRGB, red: 0.19, green: 0.195, blue: 0.215, opacity: 1)
                                : Color.white
                        )
                } else {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: scheme == .dark
                                    ? [
                                        Color.white.opacity(hovered ? 0.15 : 0.10),
                                        Color.white.opacity(hovered ? 0.08 : 0.05),
                                    ]
                                    : [
                                        Color.white.opacity(hovered ? 0.92 : 0.78),
                                        Color.white.opacity(hovered ? 0.74 : 0.58),
                                    ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: prominent
                                ? [
                                    Color.white.opacity(scheme == .dark ? 0.30 : 0.18),
                                    Color.clear,
                                ]
                                : (scheme == .dark
                                    ? [Color.white.opacity(0.20), Color.white.opacity(0.04)]
                                    : [Color.white.opacity(0.95), Color.black.opacity(0.06)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.85
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: Color.black.opacity(
                    prominent
                        ? (scheme == .dark ? 0.30 : 0.14)
                        : (scheme == .dark ? 0.20 : 0.045)
                ),
                radius: prominent ? 12 : 8,
                y: prominent ? 4 : 2.5
            )
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .opacity(isEnabled ? 1 : 0.36)
            .onHover { hovered = $0 }
    }
}

/// Compact inline frosted-pill action button used inside Onboarding rows.
private struct OnboardingRowPillButton: View {
    let title: String
    var isLoading: Bool = false
    var isComplete: Bool = false
    var loadingTitle: String? = nil
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isComplete {
                    Image(mingCute: "checkmark", size: 11)
                } else if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                    if let loadingTitle {
                        Text(loadingTitle)
                    }
                } else {
                    Text(title)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(ThemeColor.kText.color(for: scheme))
            .padding(.horizontal, 13)
            .frame(height: 28)
            .contentShape(Capsule())
            .background {
                Capsule().fill(
                    LinearGradient(
                        colors: scheme == .dark
                            ? [
                                Color.white.opacity(hovered ? 0.16 : 0.11),
                                Color.white.opacity(hovered ? 0.09 : 0.06),
                            ]
                            : [
                                Color.white.opacity(hovered ? 0.98 : 0.88),
                                Color.white.opacity(hovered ? 0.86 : 0.70),
                            ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: scheme == .dark
                                ? [Color.white.opacity(0.20), Color.white.opacity(0.04)]
                                : [Color.white.opacity(0.96), Color.black.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.85
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: Color.black.opacity(scheme == .dark ? 0.20 : 0.04),
                radius: 5,
                y: 2
            )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.42)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
        .onHover { hovered = $0 }
    }
}

/// Tactile monochrome pill switch for Onboarding (zero macOS blue).
private struct OnboardingMonochromeSwitchStyle: ToggleStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        Button {
            if reduceMotion {
                configuration.isOn.toggle()
            } else {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    configuration.isOn.toggle()
                }
            }
        } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule()
                    .fill(
                        on
                            ? OnboardingInk.solidFill(scheme)
                            : (scheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.11))
                    )
                    .frame(width: 36, height: 21)

                Circle()
                    .fill(
                        on && scheme == .dark
                            ? Color(.sRGB, red: 0.09, green: 0.095, blue: 0.11, opacity: 1)
                            : Color.white
                    )
                    .frame(width: 15, height: 15)
                    .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
                    .padding(3)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(on ? NSLocalizedString("已开启", comment: "") : NSLocalizedString("未开启", comment: ""))
    }
}

private struct OnboardingStatusBadge: View {
    @Environment(\.colorScheme) private var scheme

    private var dotColor: Color {
        scheme == .dark
            ? Color(.sRGB, red: 0.30, green: 0.82, blue: 0.52, opacity: 1)
            : Color(.sRGB, red: 0.16, green: 0.62, blue: 0.36, opacity: 1)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(NSLocalizedString("已开启", comment: ""))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(ThemeColor.kTextSubtle)
        }
        .padding(.horizontal, 11)
        .frame(height: 26)
        .background(
            scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.045),
            in: Capsule()
        )
        .accessibilityElement(children: .combine)
    }
}

/// Quiet soft-neumorphic monochrome icon badge (borderless soft well, no extra nested stroke).
private struct OnboardingIconWell: View {
    enum Icon {
        case mingCute(String)
        case agentBrand
    }

    let icon: Icon
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        ZStack {
            shape.fill(
                scheme == .dark
                    ? Color.white.opacity(0.085)
                    : Color.black.opacity(0.045)
            )

            switch icon {
            case let .mingCute(symbol):
                Image(mingCute: symbol, size: 15)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(ThemeColor.kText.color(for: scheme))
            case .agentBrand:
                Image("Agent")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }
}

/// Small frosted feature chip on the welcome screen.
private struct OnboardingFeatureChip: View {
    let symbol: String
    let title: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            Image(mingCute: symbol, size: 12)
                .foregroundStyle(ThemeColor.kTextSubtle)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(ThemeColor.kTextSubtle)
        }
        .padding(.horizontal, 11)
        .frame(height: 26)
        .background {
            Capsule().fill(
                scheme == .dark
                    ? Color.white.opacity(0.075)
                    : Color.white.opacity(0.70)
            )
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: scheme == .dark
                            ? [Color.white.opacity(0.16), Color.clear]
                            : [Color.white.opacity(0.92), Color.black.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
                .allowsHitTesting(false)
        }
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.16 : 0.03), radius: 5, y: 2)
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
            OnboardingDiffusedGlow(step: step)

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 48)
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
                .padding(.horizontal, 44)

                if step != .welcome {
                    footerBar
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .font(.system(size: 13))
        .foregroundStyle(ThemeColor.kText)
        .tint(SettingsPalette.monochromeTint(scheme))
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
        reduceMotion ? nil : .spring(response: 0.50, dampingFraction: 0.90).delay(delay)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: scheme == .dark
                                ? [Color.white.opacity(0.14), Color.white.opacity(0.03), .clear]
                                : [Color.white.opacity(0.85), Color.white.opacity(0.25), .clear],
                            center: .center,
                            startRadius: 12,
                            endRadius: 64
                        )
                    )
                    .frame(width: 128, height: 128)
                    .allowsHitTesting(false)

                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 76, height: 76)
                    .shadow(color: Color.black.opacity(scheme == .dark ? 0.38 : 0.12), radius: 18, y: 8)
                    .shadow(color: Color.black.opacity(scheme == .dark ? 0.16 : 0.05), radius: 3, y: 1)
            }
            .frame(height: 84)
            .scaleEffect(entered || reduceMotion ? 1 : 0.93)
            .opacity(entered ? 1 : 0)
            .animation(entranceAnimation(delay: 0.0), value: entered)
            .accessibilityHidden(true)

            Spacer().frame(height: 18)

            Text(NSLocalizedString("你好，欢迎使用 Asky", comment: ""))
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.35)
                .foregroundStyle(ThemeColor.kText)
                .opacity(entered ? 1 : 0)
                .offset(y: entered || reduceMotion ? 0 : 7)
                .animation(entranceAnimation(delay: 0.06), value: entered)

            Spacer().frame(height: 7)

            Text(NSLocalizedString("搜索、剪贴板与 AI，一个快捷键呼出", comment: ""))
                .font(.system(size: 13))
                .foregroundStyle(ThemeColor.kTextSubtle)
                .opacity(entered ? 1 : 0)
                .offset(y: entered || reduceMotion ? 0 : 7)
                .animation(entranceAnimation(delay: 0.11), value: entered)

            Spacer().frame(height: 18)

            HStack(spacing: 8) {
                OnboardingFeatureChip(symbol: "magnifyingglass", title: NSLocalizedString("快速搜索", comment: ""))
                OnboardingFeatureChip(symbol: "doc.on.clipboard", title: NSLocalizedString("剪贴板", comment: ""))
                OnboardingFeatureChip(symbol: "sparkles", title: "AI")
            }
            .opacity(entered ? 1 : 0)
            .offset(y: entered || reduceMotion ? 0 : 7)
            .animation(entranceAnimation(delay: 0.15), value: entered)

            Spacer()

            HStack(spacing: 12) {
                Button(NSLocalizedString("跳过", comment: "")) {
                    app.preferences.hasCompletedOnboarding = true
                    onSkip()
                }
                .buttonStyle(OnboardingActionButtonStyle(prominent: false, minWidth: 96, height: 35))

                Button(NSLocalizedString("开始设置", comment: "")) {
                    navigate(to: .permissions)
                }
                .buttonStyle(OnboardingActionButtonStyle(prominent: true, minWidth: 130, height: 35))
                .keyboardShortcut(.defaultAction)
            }
            .opacity(entered ? 1 : 0)
            .offset(y: entered || reduceMotion ? 0 : 7)
            .animation(entranceAnimation(delay: 0.20), value: entered)

            Spacer().frame(height: 36)
        }
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader(
                title: NSLocalizedString("开启常用权限", comment: ""),
                subtitle: NSLocalizedString("按需开启，随时可在设置中调整", comment: "")
            )

            OnboardingGlassCard {
                VStack(spacing: 0) {
                    permissionRow(
                        icon: .mingCute("accessibility"),
                        title: NSLocalizedString("辅助功能", comment: ""),
                        description: NSLocalizedString("自动粘贴与窗口切换", comment: "")
                    ) {
                        if permissionModel.states[.accessibility] == .authorized {
                            OnboardingStatusBadge()
                        } else {
                            OnboardingRowPillButton(title: NSLocalizedString("去授权", comment: "")) {
                                PermissionAuthorizationWindow.shared.show(.accessibility, colorScheme: scheme)
                            }
                        }
                    }

                    rowHairline

                    permissionRow(
                        icon: .mingCute("bookmark"),
                        title: NSLocalizedString("Chrome 书签", comment: ""),
                        description: NSLocalizedString("快速搜索本地书签", comment: "")
                    ) {
                        if app.chromeBookmarkAccessState == .authorized {
                            OnboardingStatusBadge()
                        } else {
                            OnboardingRowPillButton(
                                title: NSLocalizedString("去授权", comment: ""),
                                isLoading: requestingChrome,
                                loadingTitle: NSLocalizedString("正在请求…", comment: "")
                            ) {
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

                    rowHairline

                    permissionRow(
                        icon: .mingCute("power"),
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
                        .toggleStyle(OnboardingMonochromeSwitchStyle())
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func permissionRow<Trailing: View>(
        icon: OnboardingIconWell.Icon,
        title: String,
        description: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        OnboardingCardRow(verticalPadding: 14, horizontalPadding: 20) {
            HStack(spacing: 12) {
                OnboardingIconWell(icon: icon)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ThemeColor.kText)
                    Text(description)
                        .font(.system(size: 11.5))
                        .foregroundStyle(ThemeColor.kTextSubtle)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                trailing()
            }
        }
    }

    // MARK: - Step 3: Shortcuts

    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader(
                title: NSLocalizedString("设置快捷键", comment: ""),
                subtitle: NSLocalizedString("点击按钮即可录制新组合键，或直接保留默认设置", comment: "")
            )

            OnboardingGlassCard {
                VStack(spacing: 0) {
                    shortcutRow(
                        icon: .mingCute("magnifyingglass"),
                        title: NSLocalizedString("唤起启动器", comment: ""),
                        label: app.preferences.hotKeyLabel,
                        status: app.hotKeyStatus,
                        apply: setLauncherHotKey
                    )
                    rowHairline
                    shortcutRow(
                        icon: .mingCute("doc.on.clipboard"),
                        title: NSLocalizedString("打开剪贴板历史", comment: ""),
                        label: app.preferences.clipboardHotKeyLabel,
                        status: app.clipboardHotKeyStatus,
                        apply: setClipboardHotKey
                    )
                    rowHairline
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
        icon: OnboardingIconWell.Icon,
        title: String,
        label: String,
        status: String,
        apply: @escaping (UInt32, UInt32, String) -> Bool
    ) -> some View {
        OnboardingCardRow(verticalPadding: 14, horizontalPadding: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    OnboardingIconWell(icon: icon)

                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ThemeColor.kText)

                    Spacer(minLength: 12)

                    HotKeyRecorder(label: label, allowsPlainKey: false, apply: apply)
                        .frame(width: 170, height: 30)
                }
                if !status.isEmpty, status != NSLocalizedString("已注册", comment: "") {
                    Text(status)
                        .font(.system(size: 11.5))
                        .foregroundStyle(ThemeColor.kTextNegative)
                        .padding(.leading, 44)
                }
            }
        }
    }

    // MARK: - Step 4: Optional AI Setup

    private var aiStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader(
                title: NSLocalizedString("配置 AI 助手", comment: ""),
                subtitle: NSLocalizedString("不配置模型也能畅用搜索、剪贴板与预览", comment: "")
            )

            OnboardingGlassCard {
                VStack(spacing: 0) {
                    OnboardingCardRow(verticalPadding: 12, horizontalPadding: 20) {
                        HStack {
                            Text(NSLocalizedString("供应商", comment: ""))
                                .font(.system(size: 13, weight: .medium))
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
                    }

                    rowHairline

                    if let preset = ModelProviderPreset.find(draft.provider) {
                        OnboardingCardRow(verticalPadding: 12, horizontalPadding: 20) {
                            HStack {
                                Text(NSLocalizedString("模型", comment: ""))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(ThemeColor.kText)
                                Spacer()
                                SettingsChoice(selection: $draft.model, options: preset.models.map { ($0, $0) })
                            }
                        }
                    } else {
                        OnboardingCardRow(verticalPadding: 10, horizontalPadding: 20) {
                            SettingsTextField(NSLocalizedString("API 地址", comment: ""), text: $draft.baseURL,
                                              prompt: Text("https://api.example.com/v1"))
                        }
                        rowHairline
                        OnboardingCardRow(verticalPadding: 10, horizontalPadding: 20) {
                            SettingsTextField(NSLocalizedString("模型名", comment: ""), text: $draft.model)
                        }
                    }

                    rowHairline

                    OnboardingCardRow(verticalPadding: 11, horizontalPadding: 20) {
                        SettingsSecureField(NSLocalizedString("API Key", comment: ""), text: $apiKey,
                                            prompt: Text(NSLocalizedString(canReuseKey ? "已保存，留空不变" : "输入 API Key", comment: "")))
                    }

                    rowHairline

                    HStack {
                        if let preset = ModelProviderPreset.find(draft.provider) {
                            Button {
                                _ = ToolService.openLauncherURL(preset.keyURL)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(NSLocalizedString("获取 API Key", comment: ""))
                                    Image(mingCute: "arrow.up.right", size: 11)
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(hoverKeyLink ? ThemeColor.kText.color(for: scheme) : ThemeColor.kTextSubtle.color(for: scheme))
                            }
                            .buttonStyle(.plain)
                            .onHover { hoverKeyLink = $0 }
                        }
                        Spacer()
                        OnboardingRowPillButton(
                            title: NSLocalizedString("保存并检查", comment: ""),
                            isLoading: savingModel || checkingModel,
                            isComplete: modelSaved,
                            loadingTitle: NSLocalizedString(savingModel ? "保存中…" : "检查中…", comment: "")
                        ) {
                            Task { await saveAndCheckModel() }
                        }
                        .disabled(savingModel || checkingModel || modelSaved)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .disabled(savingModel || checkingModel)
            }

            if let modelMessage {
                Text(modelMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(ThemeColor.kTextNegative)
                    .lineLimit(2)
                    .padding(.horizontal, 6)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Shared Header, Divider & Footer

    private var rowHairline: some View {
        Rectangle()
            .fill(
                scheme == .dark
                    ? Color.white.opacity(0.065)
                    : Color.black.opacity(0.055)
            )
            .frame(height: 0.75)
            .padding(.horizontal, 20)
    }

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.25)
                .foregroundStyle(ThemeColor.kText)
            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(ThemeColor.kTextSubtle)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }

    private var footerBar: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(OnboardingStep.setupSteps) { item in
                    Button { navigate(to: item) } label: {
                        Capsule()
                            .fill(item == step
                                  ? OnboardingInk.solidFill(scheme)
                                  : ThemeColor.kTextSubtlest.color(for: scheme).opacity(0.36))
                            .frame(width: item == step ? 18 : 5, height: 5)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.rawValue)")
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.88), value: step)

            HStack {
                Button(NSLocalizedString("上一步", comment: "")) {
                    if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
                        navigate(to: previous)
                    }
                }
                .buttonStyle(OnboardingActionButtonStyle(prominent: false, minWidth: 86, height: 34))

                Spacer()

                if step == .ai {
                    Button(NSLocalizedString("开始使用", comment: "")) {
                        app.preferences.hasCompletedOnboarding = true
                        onFinish()
                    }
                    .buttonStyle(OnboardingActionButtonStyle(prominent: true, minWidth: 102, height: 34))
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(NSLocalizedString("继续", comment: "")) {
                        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
                            navigate(to: next)
                        }
                    }
                    .buttonStyle(OnboardingActionButtonStyle(prominent: true, minWidth: 92, height: 34))
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 44)
        .padding(.top, 10)
        .padding(.bottom, 24)
    }

    // MARK: - Helpers

    private func navigate(to target: OnboardingStep) {
        guard target != step else { return }
        transitionForward = target.rawValue > step.rawValue
        if target == .welcome {
            entered = true
        }
        if reduceMotion {
            step = target
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.94)) {
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
