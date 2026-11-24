import AppKit
import SwiftUI
import Theme

extension View {
    /// Present above the entire settings split view, including its sidebar.
    func settingsDialog<Dialog: View>(isPresented: Bool, @ViewBuilder content: () -> Dialog) -> some View {
        background(SettingsDialogAnchor(content: isPresented ? AnyView(content()) : nil))
    }

    func settingsDialogSurface(width: CGFloat) -> some View {
        modifier(SettingsDialogSurface(width: width))
    }
}

/// Shared layout for centered Settings dialogs: circular glass close header, body, and stacked native actions.
struct SettingsDialogScaffold<Content: View>: View {
    let title: String
    let width: CGFloat
    let primaryTitle: String
    var primaryDisabled: Bool = false
    let primaryAction: () -> Void
    let cancelTitle: String
    let close: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsDialogHeader(title: title, close: close)
            content
                .padding(.top, 16)
            SettingsDialogActions(
                primaryTitle: primaryTitle,
                primaryDisabled: primaryDisabled,
                primaryAction: primaryAction,
                cancelTitle: cancelTitle,
                cancelAction: close
            )
            .padding(.top, 20)
        }
        .settingsDialogSurface(width: width)
        .onExitCommand(perform: close)
    }
}

/// Shared title bar for centered Settings dialogs, mirroring the circular glass close chrome.
struct SettingsDialogHeader: View {
    let title: String
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ThemeColor.kText)
                .lineLimit(1)
            Spacer(minLength: 0)
            SettingsDialogCloseButton(action: close)
        }
        .frame(minHeight: 28)
    }
}

/// Vertical stack of full-width native dialog actions: prominent primary above neutral secondary.
struct SettingsDialogActions: View {
    let primaryTitle: String
    var primaryDisabled: Bool = false
    let primaryAction: () -> Void
    let cancelTitle: String
    let cancelAction: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            SettingsDialogActionButton(primaryTitle, prominent: true, keyEquivalent: "\r", action: primaryAction)
                .disabled(primaryDisabled)
                .accessibilityLabel(primaryTitle)
            SettingsDialogActionButton(cancelTitle, prominent: false, keyEquivalent: "\u{1b}", action: cancelAction)
                .accessibilityLabel(cancelTitle)
        }
    }
}

private struct SettingsDialogCloseButton: NSViewRepresentable {
    static let accessibilityID = "settings-dialog-close"
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.press))
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.setAccessibilityIdentifier(Self.accessibilityID)
        button.setAccessibilityLabel(NSLocalizedString("关闭", comment: ""))
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.image = MingCute.image("xmark", size: 12.5)
        button.setAccessibilityLabel(NSLocalizedString("关闭", comment: ""))
        if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial,
           !reduceTransparency, contrast != .increased {
            button.bezelStyle = .glass
            button.borderShape = .circle
            button.tintProminence = .none
            button.isBordered = true
        } else {
            button.bezelStyle = .circular
            if #available(macOS 26, *) {
                button.borderShape = .circle
                button.tintProminence = .none
            }
            button.isBordered = true
        }
        button.controlSize = .regular
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: 28, height: 28)
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
}

private struct SettingsDialogActionButton: NSViewRepresentable {
    let title: String
    let prominent: Bool
    let keyEquivalent: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    init(_ title: String, prominent: Bool, keyEquivalent: String = "", action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.keyEquivalent = keyEquivalent
        self.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.press))
        button.font = .systemFont(ofSize: 14, weight: prominent ? .medium : .regular)
        if #available(macOS 26, *) { button.controlSize = .extraLarge } else { button.controlSize = .large }
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = enabled
        button.keyEquivalent = keyEquivalent
        button.title = title
        button.font = .systemFont(ofSize: 14, weight: prominent ? .medium : .regular)
        if #available(macOS 26, *) { button.controlSize = .extraLarge } else { button.controlSize = .large }
        button.isBordered = true

        if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial,
           !reduceTransparency, contrast != .increased {
            button.bezelStyle = .glass
            button.borderShape = .capsule
            button.tintProminence = prominent ? .primary : .none
        } else {
            button.bezelStyle = .rounded
            if #available(macOS 26, *) {
                button.borderShape = .automatic
                button.tintProminence = prominent ? .primary : .none
            }
        }
        button.bezelColor = prominent ? NSColor(SettingsPalette.monochromeTint(scheme)) : nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        let width = proposal.width ?? max(intrinsic.width, 160)
        return CGSize(width: width, height: 36)
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
}

private struct SettingsDialogSurface: ViewModifier {
    let width: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 20)
            .frame(width: width)
            .font(.system(size: 14))
            .foregroundStyle(ThemeColor.kText)
            .tint(SettingsPalette.monochromeTint(scheme))
            .nativeGlassBackground(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct SettingsDialogAnchor: NSViewRepresentable {
    let content: AnyView?

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        view.dialog = content
        view.updateDialog()
    }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.removeDialog() }

    final class Anchor: NSView {
        var dialog: AnyView?
        private var overlay: SettingsDialogOverlay?
        private weak var previousResponder: NSResponder?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateDialog()
        }

        func updateDialog() {
            guard let dialog, let window, let container = window.contentView else {
                removeDialog()
                return
            }
            if let overlay {
                overlay.card.rootView = dialog
                return
            }
            if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor {
                previousResponder = editor.delegate as? NSView
            } else {
                previousResponder = window.firstResponder
            }
            let overlay = SettingsDialogOverlay(content: dialog)
            self.overlay = overlay
            overlay.frame = container.bounds
            overlay.autoresizingMask = [.width, .height]
            container.addSubview(overlay)
            container.layoutSubtreeIfNeeded()
            // Give the native field focus after SwiftUI has created its AppKit controls.
            DispatchQueue.main.async { [weak self, weak overlay] in
                guard let self, let overlay, self.overlay === overlay else { return }
                window.makeFirstResponder(overlay.initialFocusControl ?? overlay.card)
            }
        }

        func removeDialog() {
            guard let overlay else { return }
            let window = overlay.window
            overlay.removeFromSuperview()
            self.overlay = nil
            if let view = previousResponder as? NSView, view.window === window {
                window?.makeFirstResponder(view)
            } else {
                window?.makeFirstResponder(nil)
            }
            previousResponder = nil
        }
    }
}

/// A full-window hit target with a naturally sized card at the window's center.
final class SettingsDialogOverlay: NSView {
    let card: NSHostingView<AnyView>
    init(content: AnyView) {
        card = NSHostingView(rootView: content)
        super.init(frame: .zero)
        setAccessibilityIdentifier("settings-dialog-overlay")
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func mouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    func moveFocus(backwards: Bool) {
        let controls = keyControls
        guard !controls.isEmpty, let window else { return }
        let responder: NSResponder? = (window.firstResponder as? NSTextView).flatMap {
            $0.isFieldEditor ? $0.delegate as? NSResponder : $0
        } ?? window.firstResponder
        let current = controls.firstIndex { $0 === responder }
        let next = current.map { ($0 + (backwards ? -1 : 1) + controls.count) % controls.count }
            ?? (backwards ? controls.count - 1 : 0)
        window.makeFirstResponder(controls[next])
    }

    var initialFocusControl: NSView? {
        let controls = keyControls
        return controls.first { ($0 as? NSTextField)?.isEditable == true }
            ?? controls.first { $0.accessibilityIdentifier() != SettingsDialogCloseButton.accessibilityID }
            ?? controls.first
    }

    var keyControls: [NSView] {
        func collect(_ view: NSView) -> [NSView] {
            if view.acceptsFirstResponder, !view.isHidden,
               let control = view as? NSControl, control.isEnabled { return [view] }
            return view.subviews.flatMap(collect)
        }
        return collect(card)
    }
}
