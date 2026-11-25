import AppKit
import Observation
import SwiftUI
import Theme

enum SettingsChoiceLayout {
    static let triggerHeight: CGFloat = 28
    static let menuCornerRadius: CGFloat = 14
    static let menuPadding: CGFloat = 6
    static let rowSpacing: CGFloat = 2
    static let rowHeight: CGFloat = 32
    static let rowCornerRadius: CGFloat = 8
    static let rowHorizontalPadding: CGFloat = 10
    static let iconSize: CGFloat = 16
    static let iconSpacing: CGFloat = 8
    static let checkmarkSize: CGFloat = 12
    static let minMenuWidth: CGFloat = 136
    static let maxMenuWidth: CGFloat = 340
    static let maxMenuHeight: CGFloat = 320
    static let edgeMargin: CGFloat = 12
    static let animationDuration: TimeInterval = 0.18
}

struct SettingsChoiceOption: Identifiable {
    let id: Int
    let title: String
    let image: NSImage?
}

struct SettingsChoiceMenuPlacement: Equatable {
    let menuRect: CGRect
    let alignment: Alignment
    let expandsUpward: Bool
    let isScrollable: Bool
    let collapsedTriggerWidth: CGFloat

    static func compute(
        triggerRect: CGRect,
        containerSize: CGSize,
        topInset: CGFloat,
        options: [SettingsChoiceOption],
        selectedIndex: Int,
        originalTriggerWidth: CGFloat,
        originalSelectedIndex: Int
    ) -> SettingsChoiceMenuPlacement {
        let margin = SettingsChoiceLayout.edgeMargin
        let hasAnyImage = options.contains { $0.image != nil }
        let rowFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let widestTitle = options.map { option in
            ceil((option.title as NSString).size(withAttributes: [.font: rowFont]).width)
        }.max() ?? 0

        let iconColumn: CGFloat = hasAnyImage ? (SettingsChoiceLayout.iconSize + SettingsChoiceLayout.iconSpacing) : 0
        let idealWidth = SettingsChoiceLayout.menuPadding * 2
            + SettingsChoiceLayout.rowHorizontalPadding * 2
            + iconColumn
            + widestTitle
            + 16
            + SettingsChoiceLayout.checkmarkSize
            + 8

        let maxAllowedWidth = max(SettingsChoiceLayout.minMenuWidth, min(SettingsChoiceLayout.maxMenuWidth, containerSize.width - margin * 2))
        let menuWidth = min(maxAllowedWidth, max(triggerRect.width, max(SettingsChoiceLayout.minMenuWidth, idealWidth)))

        let count = max(1, options.count)
        let naturalHeight = CGFloat(count) * SettingsChoiceLayout.rowHeight
            + CGFloat(max(0, count - 1)) * SettingsChoiceLayout.rowSpacing
            + SettingsChoiceLayout.menuPadding * 2

        let topLimit = max(margin, topInset + 8)
        let spaceBelow = max(triggerRect.height, containerSize.height - margin - triggerRect.minY)
        let spaceAbove = max(triggerRect.height, triggerRect.maxY - topLimit)

        let expandsUpward: Bool
        let availableHeight: CGFloat
        if naturalHeight <= spaceBelow || spaceBelow >= spaceAbove {
            expandsUpward = false
            availableHeight = spaceBelow
        } else {
            expandsUpward = true
            availableHeight = spaceAbove
        }

        let maxHeight = min(availableHeight, SettingsChoiceLayout.maxMenuHeight)
        let menuHeight = max(triggerRect.height, min(naturalHeight, maxHeight))
        let isScrollable = naturalHeight > menuHeight + 0.5

        let horizontal: HorizontalAlignment
        let minX: CGFloat
        if triggerRect.maxX - menuWidth >= margin {
            horizontal = .trailing
            minX = triggerRect.maxX - menuWidth
        } else if triggerRect.minX + menuWidth <= containerSize.width - margin {
            horizontal = .leading
            minX = triggerRect.minX
        } else {
            horizontal = .trailing
            minX = max(margin, min(containerSize.width - margin - menuWidth, triggerRect.maxX - menuWidth))
        }

        let vertical: VerticalAlignment = expandsUpward ? .bottom : .top
        let rawMinY = expandsUpward ? (triggerRect.maxY - menuHeight) : triggerRect.minY
        let minY = max(topLimit, min(containerSize.height - margin - menuHeight, rawMinY))

        let collapsedWidth: CGFloat
        if selectedIndex == originalSelectedIndex || !options.indices.contains(selectedIndex) {
            collapsedWidth = triggerRect.width
        } else {
            let naturalOriginal = naturalTriggerWidth(for: options.indices.contains(originalSelectedIndex) ? options[originalSelectedIndex] : nil)
            let naturalSelected = naturalTriggerWidth(for: options[selectedIndex])
            if originalTriggerWidth < naturalOriginal - 1 {
                collapsedWidth = originalTriggerWidth
            } else {
                collapsedWidth = min(menuWidth, naturalSelected)
            }
        }

        return SettingsChoiceMenuPlacement(
            menuRect: CGRect(x: round(minX), y: round(minY), width: ceil(menuWidth), height: ceil(menuHeight)),
            alignment: Alignment(horizontal: horizontal, vertical: vertical),
            expandsUpward: expandsUpward,
            isScrollable: isScrollable,
            collapsedTriggerWidth: collapsedWidth
        )
    }

    private static func naturalTriggerWidth(for option: SettingsChoiceOption?) -> CGFloat {
        guard let option else { return 64 }
        let titleWidth = ceil((option.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14)]).width)
        let iconWidth: CGFloat = option.image != nil ? (SettingsChoiceLayout.iconSize + 6) : 0
        // leading 12 + icon + title + spacing 6 + chevron 12 + trailing 10
        return 12 + iconWidth + titleWidth + 6 + 12 + 10
    }
}

struct SettingsChoiceTriggerLabel: View {
    let title: String
    let image: NSImage?
    let enabled: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: SettingsChoiceLayout.iconSize, height: SettingsChoiceLayout.iconSize)
            }
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(enabled ? ThemeColor.kText : ThemeColor.kTextSubtlest)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(mingCute: "chevron.down", size: 12)
                .foregroundStyle(enabled ? ThemeColor.kIconSubtle : ThemeColor.kTextSubtlest)
                .accessibilityHidden(true)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: SettingsChoiceLayout.triggerHeight)
        .contentShape(Capsule())
    }
}

struct SettingsChoiceTriggerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .nativeGlassBackground(in: Capsule())
            .contentShape(.interaction, Capsule())
            .glassPointerFeedback(pressed: configuration.isPressed, in: Capsule(), scales: false, pressedOpacity: 0.10)
            .opacity(enabled ? 1 : 0.55)
    }
}

private struct SettingsChoiceRowButtonStyle: ButtonStyle {
    let keyboardHighlighted: Bool
    var cornerRadius: CGFloat = SettingsChoiceLayout.rowCornerRadius
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var useOpaqueHighlight: Bool {
        reduceTransparency || contrast == .increased || SurfaceCompatibility.useLegacyMaterial
    }

    func makeBody(configuration: Configuration) -> some View {
        let active = configuration.isPressed && enabled
        let highlighted = enabled && (active || hovered || keyboardHighlighted)
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let opaqueFill: Color = active
            ? ThemeColor.kBackgroundSelected.color(for: scheme)
            : highlighted
                ? ThemeColor.kInteractionHover.color(for: scheme)
                : .clear

        configuration.label
            .frame(maxWidth: .infinity)
            .contentShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                if useOpaqueHighlight {
                    shape.fill(opaqueFill)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } else {
                    shape.fill(.white.opacity(active ? 0.085 : highlighted ? 0.055 : 0))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: active)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: highlighted)
            .onHover { hovered = $0 }
            .actionArrowCursor(enabled: enabled)
    }
}

/// Captures a `SettingsChoice` trigger's AppKit view for exact window-space positioning
/// and provides a typed inspection hook for native Settings regression tests.
@MainActor
final class SettingsChoiceAnchorView: NSView {
    var itemTitles: [String] = []
    var selectedIndex: Int = -1
    var isMenuOpen: Bool = false
    var openAction: (() -> Void)?
    var selectAction: ((Int) -> Void)?
    var closeAction: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func openMenu() {
        openAction?()
    }

    func selectItem(at index: Int) {
        selectAction?(index)
    }

    func closeMenu() {
        closeAction?()
    }

    func resolveWindowPlacement() -> (window: NSWindow, contentView: NSView, rect: CGRect, topInset: CGFloat)? {
        guard let window, let contentView = window.contentView else { return nil }
        let inWindow = convert(bounds, to: nil)
        let inContent = contentView.convert(inWindow, from: nil)
        let swiftUIRect: CGRect
        if contentView.isFlipped {
            swiftUIRect = inContent
        } else {
            swiftUIRect = CGRect(
                x: inContent.minX,
                y: contentView.bounds.height - inContent.maxY,
                width: inContent.width,
                height: inContent.height
            )
        }
        let layoutTopInset = max(0, contentView.bounds.height - window.contentLayoutRect.maxY)
        let topInset = max(layoutTopInset, contentView.safeAreaInsets.top)
        return (window, contentView, swiftUIRect, topInset)
    }
}

@MainActor
final class SettingsChoiceAnchorBox {
    weak var view: SettingsChoiceAnchorView?
}

struct SettingsChoiceAnchorReader: NSViewRepresentable {
    let box: SettingsChoiceAnchorBox
    let titles: [String]
    let selectedIndex: Int
    let isMenuOpen: Bool
    let onOpen: () -> Void
    let onSelect: (Int) -> Void
    let onClose: () -> Void

    func makeNSView(context: Context) -> SettingsChoiceAnchorView {
        let view = SettingsChoiceAnchorView()
        update(view)
        return view
    }

    func updateNSView(_ view: SettingsChoiceAnchorView, context: Context) {
        update(view)
    }

    private func update(_ view: SettingsChoiceAnchorView) {
        box.view = view
        view.itemTitles = titles
        view.selectedIndex = selectedIndex
        view.isMenuOpen = isMenuOpen
        view.openAction = onOpen
        view.selectAction = onSelect
        view.closeAction = onClose
    }
}

@MainActor @Observable
final class SettingsChoiceOverlayModel {
    let id: UUID
    let options: [SettingsChoiceOption]
    let triggerRect: CGRect
    let containerSize: CGSize
    let topInset: CGFloat
    let hasAnyImage: Bool
    let originalSelectedIndex: Int
    var selectedIndex: Int
    var highlightedIndex: Int
    var keyboardNavigationActive: Bool = false
    var isExpanded: Bool = false
    var isClosing: Bool = false
    let onSelect: (Int) -> Void
    let onRequestClose: () -> Void

    init(
        id: UUID = UUID(),
        options: [SettingsChoiceOption],
        selectedIndex: Int,
        triggerRect: CGRect,
        containerSize: CGSize,
        topInset: CGFloat,
        onSelect: @escaping (Int) -> Void,
        onRequestClose: @escaping () -> Void
    ) {
        self.id = id
        self.options = options
        self.originalSelectedIndex = selectedIndex
        self.selectedIndex = selectedIndex
        self.highlightedIndex = options.indices.contains(selectedIndex) ? selectedIndex : 0
        self.triggerRect = triggerRect
        self.containerSize = containerSize
        self.topInset = topInset
        self.hasAnyImage = options.contains { $0.image != nil }
        self.onSelect = onSelect
        self.onRequestClose = onRequestClose
    }

    var placement: SettingsChoiceMenuPlacement {
        SettingsChoiceMenuPlacement.compute(
            triggerRect: triggerRect,
            containerSize: containerSize,
            topInset: topInset,
            options: options,
            selectedIndex: selectedIndex,
            originalTriggerWidth: triggerRect.width,
            originalSelectedIndex: originalSelectedIndex
        )
    }

    var currentOption: SettingsChoiceOption? {
        options.indices.contains(selectedIndex) ? options[selectedIndex] : options.first
    }
}

private struct SettingsChoiceOverlayView: View {
    let model: SettingsChoiceOverlayModel
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let placement = model.placement
        ZStack(alignment: .topLeading) {
            Color.clear
            Group {
                if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial {
                    GlassEffectContainer {
                        ZStack(alignment: placement.alignment) {
                            if model.isExpanded {
                                menuContainer(placement: placement)
                                    .nativeGlassBackground(in: RoundedRectangle(cornerRadius: SettingsChoiceLayout.menuCornerRadius))
                                    .glassEffectID("settings-choice", in: glassNamespace)
                                    .glassEffectTransition(.matchedGeometry)
                            } else {
                                collapsedTrigger(width: placement.collapsedTriggerWidth)
                                    .nativeGlassBackground(in: Capsule())
                                    .glassEffectID("settings-choice", in: glassNamespace)
                                    .glassEffectTransition(.matchedGeometry)
                            }
                        }
                    }
                } else {
                    ZStack(alignment: placement.alignment) {
                        if model.isExpanded {
                            menuContainer(placement: placement)
                                .nativeGlassBackground(in: RoundedRectangle(cornerRadius: SettingsChoiceLayout.menuCornerRadius))
                        } else {
                            collapsedTrigger(width: placement.collapsedTriggerWidth)
                                .nativeGlassBackground(in: Capsule())
                        }
                    }
                }
            }
            .frame(width: placement.menuRect.width, height: placement.menuRect.height, alignment: placement.alignment)
            .position(x: placement.menuRect.midX, y: placement.menuRect.midY)
            .animation(reduceMotion ? nil : .smooth(duration: SettingsChoiceLayout.animationDuration), value: model.isExpanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .allowsHitTesting(!model.isClosing)
        .onAppear {
            guard !model.isClosing, !model.isExpanded else { return }
            if reduceMotion {
                model.isExpanded = true
            } else {
                let targetID = model.id
                DispatchQueue.main.async {
                    guard SettingsChoicePresenter.shared.isActive(sessionID: targetID), !model.isClosing else { return }
                    model.isExpanded = true
                }
            }
        }
    }

    private func collapsedTrigger(width: CGFloat) -> some View {
        SettingsChoiceTriggerLabel(
            title: model.currentOption?.title ?? "",
            image: model.currentOption?.image,
            enabled: true
        )
        .frame(width: width, height: model.triggerRect.height)
    }

    @ViewBuilder
    private func menuContainer(placement: SettingsChoiceMenuPlacement) -> some View {
        if placement.isScrollable {
            ScrollViewReader { proxy in
                ScrollView {
                    menuRows
                }
                .scrollIndicators(.hidden)
                .frame(width: placement.menuRect.width, height: placement.menuRect.height)
                .onAppear {
                    if model.options.indices.contains(model.selectedIndex) {
                        proxy.scrollTo(model.selectedIndex, anchor: .center)
                    }
                }
                .onChange(of: model.highlightedIndex) { _, next in
                    if model.keyboardNavigationActive {
                        proxy.scrollTo(next, anchor: .center)
                    }
                }
            }
        } else {
            menuRows
                .frame(width: placement.menuRect.width, height: placement.menuRect.height)
        }
    }

    private var menuRows: some View {
        VStack(alignment: .leading, spacing: SettingsChoiceLayout.rowSpacing) {
            ForEach(model.options) { option in
                let isSelected = option.id == model.selectedIndex
                let isKeyboardHighlighted = model.keyboardNavigationActive && option.id == model.highlightedIndex
                Button {
                    model.onSelect(option.id)
                } label: {
                    HStack(spacing: 0) {
                        if model.hasAnyImage {
                            Group {
                                if let image = option.image {
                                    Image(nsImage: image)
                                        .resizable()
                                        .interpolation(.high)
                                        .scaledToFit()
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(width: SettingsChoiceLayout.iconSize, height: SettingsChoiceLayout.iconSize)
                            .padding(.trailing, SettingsChoiceLayout.iconSpacing)
                        }
                        Text(option.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                        Spacer(minLength: 16)
                        Image(mingCute: "checkmark", size: SettingsChoiceLayout.checkmarkSize)
                            .frame(width: SettingsChoiceLayout.checkmarkSize, height: SettingsChoiceLayout.checkmarkSize)
                            .opacity(isSelected ? 1 : 0)
                            .accessibilityHidden(!isSelected)
                    }
                    .foregroundStyle(ThemeColor.kText)
                    .padding(.horizontal, SettingsChoiceLayout.rowHorizontalPadding)
                    .frame(height: SettingsChoiceLayout.rowHeight)
                }
                .buttonStyle(SettingsChoiceRowButtonStyle(keyboardHighlighted: isKeyboardHighlighted))
                .onHover { hovering in
                    if hovering {
                        model.keyboardNavigationActive = false
                        model.highlightedIndex = option.id
                    }
                }
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("settings-choice-option-\(option.id)")
                .id(option.id)
            }
        }
        .padding(SettingsChoiceLayout.menuPadding)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-choice-menu")
    }
}

/// Topmost window overlay hosting a single morphing `SettingsChoice` menu.
@MainActor
final class SettingsChoiceOverlay: NSView {
    let model: SettingsChoiceOverlayModel
    private let hostingView: NSHostingView<SettingsChoiceOverlayView>

    init(model: SettingsChoiceOverlayModel) {
        self.model = model
        self.hostingView = NSHostingView(rootView: SettingsChoiceOverlayView(model: model))
        super.init(frame: .zero)
        setAccessibilityIdentifier("settings-choice-overlay")
        hostingView.safeAreaRegions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func containsWindowPoint(_ pointInWindow: NSPoint) -> Bool {
        let local = convert(pointInWindow, from: nil)
        let swiftUIPoint = isFlipped
            ? local
            : CGPoint(x: local.x, y: bounds.height - local.y)
        return model.placement.menuRect.contains(swiftUIPoint)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !model.isClosing else { return nil }
        let local = convert(point, from: superview)
        let swiftUIPoint = isFlipped
            ? local
            : CGPoint(x: local.x, y: bounds.height - local.y)
        guard model.placement.menuRect.contains(swiftUIPoint) else { return nil }
        return super.hitTest(point)
    }
}

@MainActor
final class SettingsChoicePresenter {
    static let shared = SettingsChoicePresenter()

    private final class Session {
        let id: UUID
        weak var window: NSWindow?
        let model: SettingsChoiceOverlayModel
        let overlay: SettingsChoiceOverlay
        let onDismissed: () -> Void
        var monitor: Any?
        var observers: [NSObjectProtocol] = []

        init(
            model: SettingsChoiceOverlayModel,
            window: NSWindow,
            overlay: SettingsChoiceOverlay,
            onDismissed: @escaping () -> Void
        ) {
            self.id = model.id
            self.window = window
            self.model = model
            self.overlay = overlay
            self.onDismissed = onDismissed
        }
    }

    private var activeSession: Session?

    func isActive(sessionID: UUID) -> Bool {
        activeSession?.id == sessionID
    }

    var activeOverlay: SettingsChoiceOverlay? {
        activeSession?.overlay
    }

    @discardableResult
    func present(
        from anchor: SettingsChoiceAnchorView,
        options: [SettingsChoiceOption],
        selectedIndex: Int,
        onSelect: @escaping (Int) -> Void,
        onOpenChanged: @escaping (Bool) -> Void
    ) -> UUID? {
        guard !options.isEmpty,
              let resolved = anchor.resolveWindowPlacement() else { return nil }

        teardownImmediately()

        let window = resolved.window
        let contentView = resolved.contentView

        let sessionID = UUID()
        let model = SettingsChoiceOverlayModel(
            id: sessionID,
            options: options,
            selectedIndex: selectedIndex,
            triggerRect: resolved.rect,
            containerSize: contentView.bounds.size,
            topInset: resolved.topInset,
            onSelect: { [weak self] index in
                self?.choose(index: index, sessionID: sessionID, apply: onSelect)
            },
            onRequestClose: { [weak self] in
                self?.dismiss(sessionID: sessionID, animated: true)
            }
        )

        let overlay = SettingsChoiceOverlay(model: model)
        overlay.frame = contentView.bounds
        overlay.autoresizingMask = [.width, .height]
        contentView.addSubview(overlay, positioned: .above, relativeTo: nil)
        contentView.layoutSubtreeIfNeeded()

        let session = Session(
            model: model,
            window: window,
            overlay: overlay,
            onDismissed: { onOpenChanged(false) }
        )
        activeSession = session
        onOpenChanged(true)
        installMonitors(for: session, onSelect: onSelect)
        return session.id
    }

    func dismiss(sessionID: UUID? = nil, animated: Bool) {
        guard let session = activeSession else { return }
        if let sessionID, session.id != sessionID { return }
        if session.model.isClosing {
            if !animated { teardownImmediately() }
            return
        }

        removeMonitors(for: session)
        let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !shouldAnimate {
            teardownImmediately()
            return
        }

        session.model.isClosing = true
        session.model.isExpanded = false
        let closingID = session.id
        DispatchQueue.main.asyncAfter(deadline: .now() + SettingsChoiceLayout.animationDuration + 0.02) { [weak self] in
            guard let self, self.activeSession?.id == closingID else { return }
            self.teardownImmediately()
        }
    }

    private func choose(index: Int, sessionID: UUID, apply: (Int) -> Void) {
        guard let session = activeSession, session.id == sessionID, !session.model.isClosing else { return }
        guard session.model.options.indices.contains(index) else { return }
        session.model.selectedIndex = index
        session.model.highlightedIndex = index
        apply(index)
        dismiss(sessionID: sessionID, animated: true)
    }

    private func teardownImmediately() {
        guard let session = activeSession else { return }
        activeSession = nil
        removeMonitors(for: session)
        session.overlay.removeFromSuperview()
        session.onDismissed()
    }

    private func installMonitors(for session: Session, onSelect: @escaping (Int) -> Void) {
        let sessionID = session.id
        let center = NotificationCenter.default
        if let window = session.window {
            let names: [Notification.Name] = [
                NSWindow.didResignKeyNotification,
                NSWindow.willCloseNotification,
                NSWindow.didResizeNotification,
            ]
            session.observers = names.map { name in
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.dismiss(sessionID: sessionID, animated: false)
                    }
                }
            }
        }

        session.monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]
        ) { [weak self] event in
            let action: Bool = MainActor.assumeIsolated {
                guard let self, let current = self.activeSession, current.id == sessionID,
                      !current.model.isClosing else { return false }
                let sameWindow = event.window != nil && event.window === current.window

                switch event.type {
                case .leftMouseDown, .rightMouseDown:
                    if sameWindow && current.overlay.containsWindowPoint(event.locationInWindow) {
                        return false
                    }
                    self.dismiss(sessionID: sessionID, animated: true)
                    return sameWindow

                case .scrollWheel:
                    if sameWindow && current.overlay.containsWindowPoint(event.locationInWindow) {
                        return !current.model.placement.isScrollable
                    }
                    self.dismiss(sessionID: sessionID, animated: true)
                    return false

                case .keyDown:
                    guard sameWindow || event.window == nil else { return false }
                    switch event.keyCode {
                    case 53: // Escape
                        self.dismiss(sessionID: sessionID, animated: true)
                        return true
                    case 126: // Up arrow
                        guard !current.model.options.isEmpty else { return true }
                        current.model.keyboardNavigationActive = true
                        current.model.highlightedIndex = (current.model.highlightedIndex - 1 + current.model.options.count) % current.model.options.count
                        return true
                    case 125: // Down arrow
                        guard !current.model.options.isEmpty else { return true }
                        current.model.keyboardNavigationActive = true
                        current.model.highlightedIndex = (current.model.highlightedIndex + 1) % current.model.options.count
                        return true
                    case 36, 76, 49: // Return, Keypad Enter, Space
                        if current.model.options.indices.contains(current.model.highlightedIndex) {
                            self.choose(index: current.model.highlightedIndex, sessionID: sessionID, apply: onSelect)
                        } else {
                            self.dismiss(sessionID: sessionID, animated: true)
                        }
                        return true
                    case 48: // Tab
                        self.dismiss(sessionID: sessionID, animated: true)
                        return true
                    default:
                        return false
                    }

                default:
                    return false
                }
            }
            return action ? nil : event
        }
    }

    private func removeMonitors(for session: Session) {
        if let monitor = session.monitor {
            NSEvent.removeMonitor(monitor)
            session.monitor = nil
        }
        let center = NotificationCenter.default
        for observer in session.observers {
            center.removeObserver(observer)
        }
        session.observers = []
    }
}
