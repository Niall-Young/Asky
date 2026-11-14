import SwiftUI
import Contracts
import Theme

struct LauncherAction {
    enum Kind { case moveWindowDisplay(Int), closeWindow, continueCalculation, deleteCalculation, editCommand(String), disableCommand(String), result(ResultAction), copyPath, copyFile, copyFileName, showFileInfo, enterFolder }
    var isNegative: Bool {
        if case .disableCommand = kind { return true }
        if case .deleteCalculation = kind { return true }
        if case .closeWindow = kind { return true }
        return false
    }
    let title: String
    let icon: String
    let shortcut: String?
    let kind: Kind

    init(title: String, icon: String, shortcut: String?, kind: Kind) {
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.kind = kind
    }

    init(action: ResultAction, source: SearchSource, shortcut: String? = nil) {
        let presentation: (String, String) = switch action {
        case .open: (source == .app ? "打开应用" : source == .clipboard ? "复制" : "打开", "arrow.up.right")
        case .revealInFinder: ("在访达中显示", "folder")
        case .switchTo: ("切换标签页", "globe")
        case .copy: ("复制结果", "doc.on.clipboard")
        case .openURL: ("打开链接", "link")
        case .runTerminal: ("运行命令", "terminal")
        case .runShortcut: ("运行快捷指令", "square.stack.3d.up")
        case .askAI: ("询问 AI", "sparkles")
        }
        self.init(title: presentation.0, icon: presentation.1, shortcut: shortcut, kind: .result(action))
    }
}

/// Floats over the scrolling results. The list owns the matching edge dissolve.
struct LauncherActionBar: View {
    @Bindable var model: LauncherModel

    var body: some View {
        HStack {
            if let primary = model.primaryLauncherAction {
                Button { model.performLauncherAction(primary) } label: {
                    LauncherActionLabel(title: primary.title, shortcut: primary.shortcut)
                }
                .buttonStyle(LauncherActionButtonStyle())
            }
            if let finder = model.finderLauncherAction {
                Button { model.performLauncherAction(finder) } label: {
                    LauncherActionLabel(title: finder.title, shortcut: finder.shortcut)
                }
                .buttonStyle(LauncherActionButtonStyle())
            }
            Spacer(minLength: 12)
            if !model.secondaryActions.isEmpty {
                LauncherActionLabel(title: "更多", shortcut: model.actionPreferences.shortcut(.launcherMore).label)
                    .hidden()
                    .accessibilityHidden(true)
                    .anchorPreference(key: LauncherMoreAnchorKey.self, value: .bounds) { $0 }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(height: LauncherLayout.actionBarHeight, alignment: .bottom)
    }

}

struct LauncherActionLabel: View {
    let title: String
    let shortcut: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString(title, tableName: "Launcher", comment: "Launcher action"))
            if let shortcut { LauncherActionKeyCap(value: shortcut) }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(ThemeColor.kText)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .contentShape(Capsule())
    }
}

struct LauncherActionButtonStyle: ButtonStyle {
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .nativeGlassBackground(in: Capsule(), interactive: true)
            .overlay {
                Capsule()
                    .fill(ThemeColor.kInteractionHover.color(for: colorScheme))
                    .opacity(isEnabled ? (configuration.isPressed ? 1 : isHovered ? 0.6 : 0) : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .contentShape(.interaction, Capsule())
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

struct LauncherActionKeyCap: View {
    let value: String
    var body: some View {
        Text(value)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ThemeColor.kTextSubtle)
            .padding(.horizontal, 5)
            .frame(height: 20)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(ThemeColor.kBorder, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Menu content shares the launcher window and leaves the native editor focused.
struct LauncherActionsMenu: View {
    @Bindable var model: LauncherModel
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(model.secondaryActions.enumerated()), id: \.offset) { index, action in
                Button { model.performLauncherAction(action) } label: {
                    HStack(spacing: 10) {
                        Text(NSLocalizedString(action.title, tableName: "Launcher", comment: "Launcher action"))
                        Spacer(minLength: 8)
                        if let shortcut = action.shortcut { LauncherActionKeyCap(value: shortcut) }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(action.isNegative ? ThemeColor.kTextNegative : ThemeColor.kText)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .background(model.actionSelection == index ? ThemeColor.kInteractionHover.color(for: colorScheme) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10))
                .onHover { if $0 { model.actionSelection = index } }
                .accessibilityAddTraits(model.actionSelection == index ? .isSelected : [])
                .id(index)
                .accessibilityIdentifier("launcher-action-\(index)")
            }
        }
        .padding(8)
        .frame(width: LauncherLayout.actionsMenuWidth)
        .foregroundStyle(ThemeColor.kText)
        .accessibilityIdentifier("launcher-actions-menu")
    }
}

/// The footer contributes only its anchor; the shell draws the transforming surface
/// above all result rows, without clipping it to the footer's 32-point height.
struct LauncherMoreAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct LauncherMorphingActions: View {
    @Bindable var model: LauncherModel
    let availableHeight: CGFloat
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated static func menuHeight(actionCount: Int) -> CGFloat {
        CGFloat(actionCount * 36 + max(0, actionCount - 1) * 4 + 16)
    }

    var body: some View {
        Group {
            if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial {
                GlassEffectContainer {
                    ZStack(alignment: .bottomTrailing) {
                        if model.isActionsMenuPresented {
                            menu
                                .nativeGlassBackground(in: RoundedRectangle(cornerRadius: 18))
                                .glassEffectID("more", in: glassNamespace)
                                .glassEffectTransition(.matchedGeometry)
                        } else {
                            button
                                .glassEffectID("more", in: glassNamespace)
                                .glassEffectTransition(.matchedGeometry)
                        }
                    }
                }
            } else {
                ZStack(alignment: .bottomTrailing) {
                    if model.isActionsMenuPresented {
                        menu.nativeGlassBackground(in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        button
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: model.isActionsMenuPresented)
    }

    private var button: some View {
        Button { model.toggleActionsMenu() } label: {
            LauncherActionLabel(title: "更多", shortcut: model.actionPreferences.shortcut(.launcherMore).label)
        }
        .buttonStyle(LauncherActionButtonStyle())
        .fixedSize()
        .focusable(false)
        .accessibilityIdentifier("launcher-more-button")
        .accessibilityValue("Off")
    }

    @ViewBuilder private var menu: some View {
        let height = Self.menuHeight(actionCount: model.secondaryActions.count)
        if height <= availableHeight {
            LauncherActionsMenu(model: model)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LauncherActionsMenu(model: model)
                }
                .scrollIndicators(.hidden)
                .focusable(false)
                .onChange(of: model.actionSelection) { _, selection in
                    proxy.scrollTo(selection, anchor: .center)
                }
            }
            .frame(width: LauncherLayout.actionsMenuWidth, height: availableHeight)
        }
    }
}
