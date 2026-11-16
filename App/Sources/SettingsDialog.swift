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

private struct SettingsDialogSurface: ViewModifier {
    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(24)
            .frame(width: width)
            .font(.system(size: 14))
            .foregroundStyle(ThemeColor.kText)
            .nativeGlassBackground(in: RoundedRectangle(cornerRadius: 16))
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
                let controls = overlay.keyControls
                window.makeFirstResponder(controls.first ?? overlay.card)
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

    var keyControls: [NSView] {
        func collect(_ view: NSView) -> [NSView] {
            if view.acceptsFirstResponder, !view.isHidden,
               let control = view as? NSControl, control.isEnabled { return [view] }
            return view.subviews.flatMap(collect)
        }
        return collect(card)
    }
}
