import AppKit
import SwiftUI
import Theme

/// Coordinates in-window Liquid Glass floating date/time pickers so they share Asky's
/// fast floating-overlay animation, native glass material, and click-outside dismissal.
@MainActor @Observable
final class FormPickerOverlayController {
    weak static var active: FormPickerOverlayController?

    private(set) var targetID: String?
    private(set) var anchorRect: CGRect?
    private(set) var preferredSize: CGSize = .zero
    private(set) var revision: Int = 0
    @ObservationIgnored private var contentBuilder: (() -> AnyView)?
    @ObservationIgnored weak var panelView: NSView?

    var isPresented: Bool { targetID != nil }

    func isOpen(_ id: String) -> Bool {
        targetID == id
    }

    func toggle(id: String, anchor: CGRect, preferredSize: CGSize, content: @escaping () -> AnyView) {
        if targetID == id {
            dismiss()
        } else {
            contentBuilder = content
            anchorRect = anchor
            self.preferredSize = preferredSize
            targetID = id
            revision &+= 1
            Self.active = self
        }
    }

    func dismiss() {
        targetID = nil
        anchorRect = nil
        preferredSize = .zero
        contentBuilder = nil
        if Self.active === self {
            Self.active = nil
        }
    }

    func notifyChanged() {
        revision &+= 1
    }

    func buildContent() -> AnyView? {
        _ = revision
        return contentBuilder?()
    }

    /// Handles mouse, scroll, and Escape events for an open floating picker overlay.
    /// Returns `true` when the event should be consumed.
    func handleLocalEvent(_ event: NSEvent) -> Bool {
        guard isPresented else { return false }
        let point = event.locationInWindow
        let window = event.window
        if event.type == .scrollWheel {
            if !contains(point: point, in: window) {
                dismiss()
            }
            return false
        }
        if event.type == .keyDown {
            guard event.keyCode == 53 else { return false }
            dismiss()
            return true
        }
        guard event.type == .leftMouseDown || event.type == .rightMouseDown else {
            return false
        }
        if contains(point: point, in: window) {
            return false
        }
        let sameWindow = window != nil && window === panelView?.window
        dismiss()
        return sameWindow
    }

    private func contains(point: NSPoint, in window: NSWindow?) -> Bool {
        guard let view = panelView, window === view.window else { return false }
        return view.bounds.contains(view.convert(point, from: nil))
    }
}

private struct FormPickerOverlayKey: EnvironmentKey {
    static let defaultValue: FormPickerOverlayController? = nil
}

extension EnvironmentValues {
    var formPickerOverlay: FormPickerOverlayController? {
        get { self[FormPickerOverlayKey.self] }
        set { self[FormPickerOverlayKey.self] = newValue }
    }
}

/// Presents the active form date/time picker as an in-window Liquid Glass floating overlay.
struct FormPickerOverlayPresentation: ViewModifier {
    var controller: FormPickerOverlayController
    var topInset: CGFloat = 12
    var onWillOpen: (() -> Void)? = nil

    @State private var monitor: Any?
    @State private var measuredSize: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    AnchoredOverlayLayout {
                        if let targetID = controller.targetID,
                           let trigger = controller.anchorRect {
                            let panelSize = effectiveSize
                            let placement = layout(
                                trigger: trigger,
                                panelSize: panelSize,
                                container: geometry.size
                            )
                            let anchorPoint = AnchoredPopoverMotion.anchor(
                                for: trigger,
                                menuOrigin: placement.origin,
                                menuSize: panelSize,
                                placedAbove: placement.placedAbove
                            )
                            FormPickerOverlayContent(controller: controller)
                                .nativeGlassBackground(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .background(ChatFormControlMarker(id: "form-picker-overlay"))
                                .background(FormPickerViewReader(controller: controller).allowsHitTesting(false))
                                .fixedSize()
                                .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
                                    if abs(newSize.width - effectiveSize.width) > 1
                                        || abs(newSize.height - effectiveSize.height) > 1 {
                                        measuredSize = newSize
                                    }
                                }
                                .anchoredOverlayOrigin(placement.origin)
                                .transition(
                                    AnchoredPopoverMotion.pickerTransition(
                                        anchor: anchorPoint,
                                        placedAbove: placement.placedAbove,
                                        reduceMotion: reduceMotion
                                    )
                                )
                                .id(targetID)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    .animation(
                        AnchoredPopoverMotion.pickerAnimation(
                            isPresented: controller.isPresented,
                            reduceMotion: reduceMotion
                        ),
                        value: controller.targetID
                    )
                }
                .allowsHitTesting(controller.isPresented)
                .zIndex(20)
            }
            .onChange(of: controller.targetID) { _, newTarget in
                measuredSize = .zero
                if newTarget != nil {
                    onWillOpen?()
                    startMonitoring()
                } else {
                    stopMonitoring()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { event in
                if let owner = controller.panelView?.window, event.object as? NSWindow === owner {
                    controller.dismiss()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { event in
                if let owner = controller.panelView?.window, event.object as? NSWindow === owner {
                    controller.dismiss()
                }
            }
            .onDisappear {
                controller.dismiss()
                stopMonitoring()
            }
    }

    private var effectiveSize: CGSize {
        if measuredSize.width > 0, measuredSize.height > 0 {
            return measuredSize
        }
        return controller.preferredSize
    }

    private struct Placement {
        let origin: CGPoint
        let placedAbove: Bool
    }

    private func layout(trigger: CGRect, panelSize: CGSize, container: CGSize) -> Placement {
        let edgeMargin: CGFloat = 12
        let gap: CGFloat = 6
        let topLimit = topInset
        let bottomLimit = container.height - edgeMargin

        // Right-align with the unified input's trailing icon when it fits; otherwise left-align
        // with the input's leading edge, clamping inside the window bounds.
        let rightAlignedX = trigger.maxX - panelSize.width
        let maxX = max(edgeMargin, container.width - edgeMargin - panelSize.width)
        let preferredX: CGFloat
        if rightAlignedX >= edgeMargin {
            preferredX = rightAlignedX
        } else if trigger.minX + panelSize.width <= container.width - edgeMargin {
            preferredX = trigger.minX
        } else {
            preferredX = rightAlignedX
        }
        let x = min(max(edgeMargin, preferredX), maxX)

        let belowY = trigger.maxY + gap
        let aboveY = trigger.minY - gap - panelSize.height
        let spaceBelow = bottomLimit - belowY
        let spaceAbove = trigger.minY - gap - topLimit

        let placedAbove: Bool
        let y: CGFloat
        if belowY + panelSize.height <= bottomLimit {
            placedAbove = false
            y = belowY
        } else if aboveY >= topLimit {
            placedAbove = true
            y = aboveY
        } else if spaceAbove > spaceBelow {
            placedAbove = true
            y = max(topLimit, min(aboveY, bottomLimit - panelSize.height))
        } else {
            placedAbove = false
            y = max(topLimit, min(belowY, bottomLimit - panelSize.height))
        }

        return Placement(origin: CGPoint(x: x, y: y), placedAbove: placedAbove)
    }

    private func startMonitoring() {
        stopMonitoring()
        let controller = self.controller
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { event in
            let consumed = MainActor.assumeIsolated {
                controller.handleLocalEvent(event)
            }
            return consumed ? nil : event
        }
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct FormPickerOverlayContent: View {
    var controller: FormPickerOverlayController

    var body: some View {
        let _ = controller.revision
        if let content = controller.buildContent() {
            content
        }
    }
}

private struct FormPickerViewReader: NSViewRepresentable {
    let controller: FormPickerOverlayController

    func makeNSView(context: Context) -> NSView {
        let view = PassiveView()
        controller.panelView = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        controller.panelView = view
    }

    private final class PassiveView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Inline trailing icon button embedded inside a unified `settingsInputSurface` field.
struct ChatFormInlinePickerIcon<Icon: View>: View {
    let isOpen: Bool
    let enabled: Bool
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            icon()
                .foregroundStyle(
                    isOpen || (hovered && enabled)
                        ? ThemeColor.kText.color(for: scheme)
                        : ThemeColor.kIcon.color(for: scheme)
                )
                .frame(width: 26, height: 26)
                .background(
                    isOpen || (hovered && enabled)
                        ? ThemeColor.kInteractionHover.color(for: scheme)
                        : .clear,
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .padding(.trailing, -5)
        .onHover { hovered = $0 }
        .background(ChatFormControlMarker(id: accessibilityIdentifier))
        .actionArrowCursor(enabled: enabled)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: hovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isOpen)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
