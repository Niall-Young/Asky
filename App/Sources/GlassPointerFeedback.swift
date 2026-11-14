import AppKit
import SwiftUI

/// Custom macOS feedback referenced to the supplied iOS recording, not a system animation.
/// Hover changes light only; pressing expands the existing surface without changing layout.
private struct GlassPointerFeedback<S: Shape>: ViewModifier {
    let pressed: Bool
    let shape: S
    var illumination: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let active = pressed && enabled
        let animatesScale = !reduceMotion
        content
            .overlay {
                if illumination {
                    shape.fill(.white.opacity(enabled ? (active ? 0.16 : hovered ? 0.055 : 0) : 0))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .visualEffect { effect, geometry in
                // Desktop feedback is deliberately subtler than the touch reference.
                // Cap both relative growth and the total increase of a wide capsule.
                let growth = min(0.06, 3 / max(geometry.size.width, geometry.size.height, 1))
                return effect.scaleEffect(active && animatesScale ? 1 + growth : 1)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .animation(reduceMotion ? nil : active
                       ? .easeOut(duration: 0.10)
                       : .spring(response: 0.34, dampingFraction: 0.42), value: active)
            .onHover { hovered = $0 }
    }
}

extension View {
    func glassPointerFeedback<S: Shape>(pressed: Bool, in shape: S, illumination: Bool = true) -> some View {
        modifier(GlassPointerFeedback(pressed: pressed, shape: shape, illumination: illumination))
    }
}

/// Reports pointer tracking while leaving action dispatch, keyboard activation and
/// drag-out cancellation with AppKit. The shared capsule receives a single state.
final class GlassPointerButton: NSButton {
    var onPressChanged: ((Bool) -> Void)?
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { super.mouseDown(with: event); return }
        onPressChanged?(true)
        defer { onPressChanged?(false) }
        super.mouseDown(with: event)
    }
}

/// A morphing button owns its glass outside the label, so observe the press and
/// apply the feedback after that glass rather than scaling just the label.
struct GlassPressObserverStyle: ButtonStyle {
    @Binding var pressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, value in pressed = value }
            .onDisappear { pressed = false }
    }
}
