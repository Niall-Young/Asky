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
            .background(ActionArrowCursor())
    }
}

extension View {
    /// Resolve action cursors without adding glass, illumination or press effects.
    func actionArrowCursor(enabled: Bool = true) -> some View {
        background {
            if enabled { ActionArrowCursor() }
        }
    }

    func glassPointerFeedback<S: Shape>(pressed: Bool, in shape: S, illumination: Bool = true) -> some View {
        modifier(GlassPointerFeedback(pressed: pressed, shape: shape, illumination: illumination))
    }
}

/// A continuous pool of light around the active icon, fading across one shared
/// glass surface. Separate clipped halves create an artificial seam at the center.
struct GlassCapsuleIllumination: View {
    var pressedIndex: Int?
    var hoveredIndex: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<2) { index in
                    Capsule()
                        .fill(RadialGradient(stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white.opacity(0.85), location: 0.28),
                            .init(color: .white.opacity(0.30), location: 0.65),
                            .init(color: .white.opacity(0), location: 1)
                        ], center: UnitPoint(x: index == 0 ? 0.25 : 0.75, y: 0.5),
                           startRadius: 0, endRadius: geometry.size.width * 0.70))
                        .opacity(pressedIndex == index ? 0.20
                            : pressedIndex == nil && hoveredIndex == index ? 0.065 : 0)
                }
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: pressedIndex)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredIndex)
    }
}

/// Reports pointer tracking while leaving action dispatch, keyboard activation and
/// drag-out cancellation with AppKit. The owner can illuminate each button separately.
final class GlassPointerButton: NSButton {
    var onPressChanged: ((Bool) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

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

/// Native text and SwiftUI may both update the cursor during one mouse event.
/// Resolve the visible action after AppKit finishes dispatching that event.
private struct ActionArrowCursor: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ view: CursorView, context: Context) {}

    final class CursorView: NSView {
        private struct Entry { weak var view: CursorView? }
        private static var regions: [Entry] = []
        private static var refreshPending = false
        private var cursorTrackingArea: NSTrackingArea?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            Self.regions.removeAll { $0.view == nil || $0.view === self }
            if window != nil { Self.regions.append(Entry(view: self)) }
            Self.refreshCursor()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let cursorTrackingArea { removeTrackingArea(cursorTrackingArea) }
            // SwiftUI's unclipped native backgrounds can have a visibleRect larger
            // than their bounds. Never let an action claim that surrounding text.
            let area = NSTrackingArea(rect: bounds.intersection(visibleRect),
                options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .activeAlways],
                owner: self, userInfo: nil)
            addTrackingArea(area)
            cursorTrackingArea = area
            Self.refreshCursor()
        }

        override func cursorUpdate(with event: NSEvent) { Self.refreshCursor() }
        override func mouseEntered(with event: NSEvent) { Self.refreshCursor() }
        override func mouseMoved(with event: NSEvent) { Self.refreshCursor() }
        override func mouseExited(with event: NSEvent) { Self.refreshCursor() }

        private static func refreshCursor() {
            guard !refreshPending else { return }
            refreshPending = true
            DispatchQueue.main.async {
                refreshPending = false
                let point = NSEvent.mouseLocation
                let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
                guard let window = NSApp.window(withWindowNumber: number),
                      let content = window.contentView else { return }
                let location = window.convertPoint(fromScreen: point)
                regions.removeAll { $0.view == nil }
                if regions.contains(where: { entry in
                    guard let view = entry.view, view.window === window,
                          !view.isHiddenOrHasHiddenAncestor else { return false }
                    return view.bounds.intersection(view.visibleRect).contains(view.convert(location, from: nil))
                }) {
                    NSCursor.arrow.set()
                } else if let target = content.hitTest(location),
                          let event = NSEvent.enterExitEvent(with: .cursorUpdate, location: location, modifierFlags: [],
                              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: number,
                              context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) {
                    // Restore the actual view's cursor, including text and link cursors.
                    target.cursorUpdate(with: event)
                }
            }
        }
    }
}
