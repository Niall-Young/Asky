import SwiftUI

/// Shared spring popup motion and trigger-anchored layout for non-morphing in-window
/// Liquid Glass menus and floating pickers (chat bubble menus, approval mode menu,
/// and form date/time pickers).
enum AnchoredPopoverMotion {
    static let openAnimation: Animation = .spring(response: 0.26, dampingFraction: 0.78)
    static let closeAnimation: Animation = .easeOut(duration: 0.15)
    static let pickerOpenAnimation: Animation = .spring(response: 0.15, dampingFraction: 0.90)
    static let pickerCloseAnimation: Animation = .easeOut(duration: 0.10)

    static func animation(isPresented: Bool, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return isPresented ? openAnimation : closeAnimation
    }

    static func pickerAnimation(isPresented: Bool, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return isPresented ? pickerOpenAnimation : pickerCloseAnimation
    }

    /// Computes a local `UnitPoint` on the popup's edge facing `trigger`, aligned to the
    /// trigger's horizontal center so the scale transition originates directly from the trigger.
    static func anchor(
        for trigger: CGRect,
        menuOrigin: CGPoint,
        menuSize: CGSize,
        placedAbove: Bool
    ) -> UnitPoint {
        let rawX = menuSize.width > 0 ? (trigger.midX - menuOrigin.x) / menuSize.width : 0.5
        let clampedX = min(max(rawX, 0.12), 0.88)
        return UnitPoint(x: clampedX, y: placedAbove ? 1.0 : 0.0)
    }

    static func transition(
        anchor: UnitPoint,
        placedAbove: Bool,
        reduceMotion: Bool
    ) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let insertionOffsetY: CGFloat = placedAbove ? 6 : -6
        let removalOffsetY: CGFloat = placedAbove ? 4 : -4
        return .asymmetric(
            insertion: .scale(scale: 0.86, anchor: anchor)
                .combined(with: .offset(y: insertionOffsetY))
                .combined(with: .opacity),
            removal: .scale(scale: 0.90, anchor: anchor)
                .combined(with: .offset(y: removalOffsetY))
                .combined(with: .opacity)
        )
    }

    static func pickerTransition(
        anchor: UnitPoint,
        placedAbove: Bool,
        reduceMotion: Bool
    ) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let insertionOffsetY: CGFloat = placedAbove ? 4 : -4
        let removalOffsetY: CGFloat = placedAbove ? 3 : -3
        return .asymmetric(
            insertion: .scale(scale: 0.94, anchor: anchor)
                .combined(with: .offset(y: insertionOffsetY))
                .combined(with: .opacity),
            removal: .scale(scale: 0.96, anchor: anchor)
                .combined(with: .offset(y: removalOffsetY))
                .combined(with: .opacity)
        )
    }
}

private struct AnchoredOverlayOriginKey: LayoutValueKey {
    static let defaultValue: CGPoint = .zero
}

/// Places floating overlay children at explicit top-leading coordinates in the container so each
/// child retains its intrinsic bounds and `.transition(.scale(anchor:))` pivots accurately
/// around the popup's own corner/edge instead of the full window frame.
struct AnchoredOverlayLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let origin = subview[AnchoredOverlayOriginKey.self]
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }
}

extension View {
    func anchoredOverlayOrigin(_ origin: CGPoint) -> some View {
        layoutValue(key: AnchoredOverlayOriginKey.self, value: origin)
    }
}
