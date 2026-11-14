import AppKit
import SwiftUI

/// Shared pointer response for app-owned action buttons. Transforms never
/// change layout or delay the button's native action.
private struct LiquidGlassButtonFeedback: ViewModifier {
    let pressed: Bool
    let hovered: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion || !enabled ? 1 : pressed ? 1.08 : hovered ? 1.015 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.45), value: pressed)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.75), value: hovered)
    }
}

extension View {
    func liquidGlassInteraction(pressed: Bool, hovered: Bool = false) -> some View {
        modifier(LiquidGlassButtonFeedback(pressed: pressed, hovered: hovered))
    }
}

/// Preserve an icon action's existing label, shape and surface while giving it
/// the same pointer response as a glass button. Keyboard actions stay immediate.
struct LiquidGlassPlainButtonStyle: ButtonStyle {
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .liquidGlassInteraction(pressed: configuration.isPressed, hovered: hovered)
            .onHover { hovered = $0 }
    }
}

/// Observe native mouse tracking without replacing NSButton's action, drag-out
/// cancellation, keyboard activation or accessibility behavior.
class LiquidGlassPressButton: NSButton {
    var onPressChanged: ((Bool) -> Void)?
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { super.mouseDown(with: event); return }
        onPressChanged?(true)
        defer { onPressChanged?(false) }
        super.mouseDown(with: event)
    }
}
