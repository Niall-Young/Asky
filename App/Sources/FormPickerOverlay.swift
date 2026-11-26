import AppKit
import SwiftUI
import Theme

enum FormPickerMorphMotion {
    static let collapsedCornerRadius: CGFloat = ChatFormMetrics.controlCornerRadius
    static let expandedCornerRadius: CGFloat = 18
    static let edgeMargin: CGFloat = 12
    static let openFrameDelay: TimeInterval = 0.016
    static let openDuration: TimeInterval = 0.28
    static let closeDuration: TimeInterval = 0.22
    static let closeTeardownDelay: TimeInterval = closeDuration + 0.05

    static var openAnimation: Animation {
        .spring(response: openDuration, dampingFraction: 0.76)
    }

    static var closeAnimation: Animation {
        .spring(response: closeDuration, dampingFraction: 0.86)
    }
}

/// Coordinates in-window Liquid Glass date/time pickers that morph in-place
/// between their input-styled trigger button and the expanded glass picker surface.
@MainActor @Observable
final class FormPickerOverlayController {
    weak static var active: FormPickerOverlayController?

    private(set) var targetID: String?
    private(set) var sessionID: UUID?
    private(set) var anchorRect: CGRect?
    private(set) var preferredSize: CGSize = .zero
    private(set) var isExpanded: Bool = false
    private(set) var isClosing: Bool = false
    private(set) var revision: Int = 0
    @ObservationIgnored private var triggerBuilder: (() -> AnyView)?
    @ObservationIgnored private var contentBuilder: (() -> AnyView)?
    @ObservationIgnored weak var panelView: NSView?

    var isPresented: Bool { targetID != nil }

    func isOpen(_ id: String) -> Bool {
        targetID == id
    }

    func toggle(
        id: String,
        anchor: CGRect,
        preferredSize: CGSize,
        trigger: @escaping () -> AnyView,
        content: @escaping () -> AnyView
    ) {
        if targetID == id, !isClosing {
            dismiss(animated: true)
            return
        }

        let newSessionID = UUID()
        sessionID = newSessionID
        targetID = id
        anchorRect = anchor
        self.preferredSize = preferredSize
        triggerBuilder = trigger
        contentBuilder = content
        isClosing = false
        revision &+= 1
        Self.active = self

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            isExpanded = true
        } else {
            isExpanded = false
            // Let Core Animation commit the collapsed trigger frame before morphing
            // the Liquid Glass surface into the expanded picker.
            DispatchQueue.main.asyncAfter(deadline: .now() + FormPickerMorphMotion.openFrameDelay) { [weak self] in
                guard let self, self.sessionID == newSessionID, !self.isClosing else { return }
                withAnimation(FormPickerMorphMotion.openAnimation) {
                    self.isExpanded = true
                }
            }
        }
    }

    func dismiss(animated: Bool = true) {
        guard let currentSession = sessionID else { return }
        if isClosing {
            if !animated { teardownImmediately() }
            return
        }
        if !animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            teardownImmediately()
            return
        }

        isClosing = true
        withAnimation(FormPickerMorphMotion.closeAnimation) {
            isExpanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + FormPickerMorphMotion.closeTeardownDelay) { [weak self] in
            guard let self, self.sessionID == currentSession else { return }
            self.teardownImmediately()
        }
    }

    private func teardownImmediately() {
        targetID = nil
        sessionID = nil
        anchorRect = nil
        preferredSize = .zero
        isExpanded = false
        isClosing = false
        triggerBuilder = nil
        contentBuilder = nil
        if Self.active === self {
            Self.active = nil
        }
    }

    func notifyChanged() {
        revision &+= 1
    }

    func buildTrigger() -> AnyView? {
        _ = revision
        return triggerBuilder?()
    }

    func buildContent() -> AnyView? {
        _ = revision
        return contentBuilder?()
    }

    /// Handles mouse, scroll, and Escape events for an open morphing picker overlay.
    /// Returns `true` when the event should be consumed.
    func handleLocalEvent(_ event: NSEvent) -> Bool {
        guard isPresented, !isClosing else { return false }
        let point = event.locationInWindow
        let window = event.window
        if event.type == .scrollWheel {
            if !contains(point: point, in: window) {
                dismiss(animated: true)
            }
            return false
        }
        if event.type == .keyDown {
            guard event.keyCode == 53 else { return false }
            dismiss(animated: true)
            return true
        }
        guard event.type == .leftMouseDown || event.type == .rightMouseDown else {
            return false
        }
        if contains(point: point, in: window) {
            return false
        }
        let sameWindow = window != nil && window === panelView?.window
        dismiss(animated: true)
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

/// Presents the active form date/time picker by morphing its trigger in-place into
/// an in-window Liquid Glass surface.
struct FormPickerOverlayPresentation: ViewModifier {
    var controller: FormPickerOverlayController
    var topInset: CGFloat = 12
    var onWillOpen: (() -> Void)? = nil

    @State private var monitor: Any?
    @State private var measuredSize: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var useNativeLiquidGlass: Bool {
        if #available(macOS 26, *) {
            return !SurfaceCompatibility.useLegacyMaterial && !reduceTransparency && contrast != .increased
        }
        return false
    }

    private var morphAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return controller.isExpanded ? FormPickerMorphMotion.openAnimation : FormPickerMorphMotion.closeAnimation
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        if let sessionID = controller.sessionID,
                           let trigger = controller.anchorRect {
                            let panelSize = effectiveSize
                            let panelRect = layout(
                                trigger: trigger,
                                panelSize: panelSize,
                                container: geometry.size
                            )
                            let isExpanded = controller.isExpanded
                            let currentWidth = isExpanded ? panelRect.width : trigger.width
                            let currentHeight = isExpanded ? panelRect.height : trigger.height
                            let currentCornerRadius = isExpanded
                                ? FormPickerMorphMotion.expandedCornerRadius
                                : FormPickerMorphMotion.collapsedCornerRadius
                            let currentMidX = isExpanded ? panelRect.midX : trigger.midX
                            let currentMidY = isExpanded ? panelRect.midY : trigger.midY
                            let shape = RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous)

                            morphSurface(
                                shape: shape,
                                triggerSize: trigger.size,
                                currentWidth: currentWidth,
                                currentHeight: currentHeight,
                                isExpanded: isExpanded
                            )
                            .background(ChatFormControlMarker(id: "form-picker-overlay"))
                            .background(FormPickerViewReader(controller: controller).allowsHitTesting(false))
                            .position(x: currentMidX, y: currentMidY)
                            .animation(morphAnimation, value: isExpanded)
                            .allowsHitTesting(!controller.isClosing)
                            .id(sessionID)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                }
                .allowsHitTesting(controller.isPresented && !controller.isClosing)
                .zIndex(20)
            }
            .onChange(of: controller.sessionID) { _, newSession in
                measuredSize = .zero
                if newSession != nil {
                    onWillOpen?()
                    startMonitoring()
                } else {
                    stopMonitoring()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { event in
                if let owner = controller.panelView?.window, event.object as? NSWindow === owner {
                    controller.dismiss(animated: false)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { event in
                if let owner = controller.panelView?.window, event.object as? NSWindow === owner {
                    controller.dismiss(animated: false)
                }
            }
            .onDisappear {
                controller.dismiss(animated: false)
                stopMonitoring()
            }
    }

    @ViewBuilder
    private func morphSurface(
        shape: RoundedRectangle,
        triggerSize: CGSize,
        currentWidth: CGFloat,
        currentHeight: CGFloat,
        isExpanded: Bool
    ) -> some View {
        if #available(macOS 26, *), useNativeLiquidGlass {
            GlassEffectContainer {
                shape
                    .fill(.clear)
                    .frame(width: currentWidth, height: currentHeight)
                    .glassEffect(.regular, in: shape)
                    .overlay {
                        morphForeground(
                            triggerSize: triggerSize,
                            currentWidth: currentWidth,
                            currentHeight: currentHeight,
                            isExpanded: isExpanded,
                            shape: shape
                        )
                    }
                    .glassEffect(.identity)
            }
        } else {
            morphForeground(
                triggerSize: triggerSize,
                currentWidth: currentWidth,
                currentHeight: currentHeight,
                isExpanded: isExpanded,
                shape: shape
            )
            .nativeGlassBackground(in: shape)
        }
    }

    private func morphForeground(
        triggerSize: CGSize,
        currentWidth: CGFloat,
        currentHeight: CGFloat,
        isExpanded: Bool,
        shape: RoundedRectangle
    ) -> some View {
        ZStack {
            if isExpanded {
                FormPickerOverlayContent(controller: controller)
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
                        if abs(newSize.width - effectiveSize.width) > 1
                            || abs(newSize.height - effectiveSize.height) > 1 {
                            measuredSize = newSize
                        }
                    }
                    .transition(.opacity)
            } else {
                FormPickerOverlayTriggerSnapshot(controller: controller)
                    .frame(width: triggerSize.width, height: triggerSize.height)
                    .transition(.opacity)
            }
        }
        .frame(width: currentWidth, height: currentHeight)
        .clipShape(shape)
    }

    private var effectiveSize: CGSize {
        if measuredSize.width > 0, measuredSize.height > 0 {
            return measuredSize
        }
        return controller.preferredSize
    }

    private func layout(trigger: CGRect, panelSize: CGSize, container: CGSize) -> CGRect {
        let edgeMargin = FormPickerMorphMotion.edgeMargin
        let topLimit = max(edgeMargin, topInset)
        let bottomLimit = container.height - edgeMargin

        // Right-align with the trigger's trailing edge (icon side) when it fits; otherwise
        // left-align with the trigger's leading edge, clamping inside the window bounds.
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

        // Expand in-place from the trigger's top edge downward, or from its bottom edge upward.
        let spaceBelow = bottomLimit - trigger.minY
        let spaceAbove = trigger.maxY - topLimit
        let rawY: CGFloat
        if panelSize.height <= spaceBelow || spaceBelow >= spaceAbove {
            rawY = trigger.minY
        } else {
            rawY = trigger.maxY - panelSize.height
        }
        let maxY = max(topLimit, bottomLimit - panelSize.height)
        let y = min(max(topLimit, rawY), maxY)

        return CGRect(
            x: round(x),
            y: round(y),
            width: ceil(panelSize.width),
            height: ceil(panelSize.height)
        )
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

private struct FormPickerOverlayTriggerSnapshot: View {
    var controller: FormPickerOverlayController

    var body: some View {
        let _ = controller.revision
        if let trigger = controller.buildTrigger() {
            trigger
                .environment(\.settingsInputHeight, ChatFormMetrics.controlHeight)
                .environment(\.settingsInputCornerRadius, ChatFormMetrics.controlCornerRadius)
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

/// Visual content of a date/time picker trigger styled identically to Asky's form input surface.
struct ChatFormPickerTriggerContent<Icon: View>: View {
    let text: String
    var unitSuffix: String? = nil
    let active: Bool
    var highlighted: Bool = false
    @ViewBuilder let icon: () -> Icon

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(active ? ThemeColor.kText : ThemeColor.kTextSubtle)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let unitSuffix, !unitSuffix.isEmpty {
                Text(unitSuffix)
                    .font(.system(size: 12))
                    .foregroundStyle(ThemeColor.kTextSubtlest)
            }

            icon()
                .foregroundStyle(ThemeColor.kIcon.color(for: scheme))
        }
        .settingsInputSurface(scheme: scheme, focused: highlighted && active)
    }
}

/// Pure trigger button keeping Asky's input-field styling, morphing in-place into
/// a Liquid Glass picker overlay when activated.
struct ChatFormPickerTrigger<Icon: View>: View {
    let text: String
    var unitSuffix: String? = nil
    let isOpen: Bool
    let active: Bool
    let fieldLabel: String
    let fieldMarkerID: String
    let pickerID: String
    let anchorBox: ChatBubbleAnchorBox
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ChatFormPickerTriggerContent(
                text: text,
                unitSuffix: unitSuffix,
                active: active,
                highlighted: hovered || isOpen,
                icon: icon
            )
            .contentShape(RoundedRectangle(cornerRadius: ChatFormMetrics.controlCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!active)
        .opacity(isOpen ? 0 : 1)
        .onHover { hovered = $0 }
        .background(ChatFormControlMarker(id: fieldMarkerID))
        .background(ChatFormControlMarker(id: pickerID))
        .background(ChatBubbleAnchorReader(box: anchorBox).allowsHitTesting(false))
        .actionArrowCursor(enabled: active)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: hovered)
        .accessibilityLabel(fieldLabel)
        .accessibilityValue(unitSuffix.map { "\(text) \($0)" } ?? text)
        .accessibilityIdentifier(pickerID)
    }
}
