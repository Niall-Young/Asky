import AppKit
import Observation
import SwiftUI
import Theme
import ToolService

/// Shared geometry and spacing tokens for all Liquid Glass alert and confirmation dialogs.
enum AppDialogLayout {
    static let cornerRadius: CGFloat = 24
    static let standardWidth: CGFloat = 360
    static let wideWidth: CGFloat = 400
    static let horizontalPadding: CGFloat = 22
    static let topPadding: CGFloat = 20
    static let bottomPadding: CGFloat = 22
    static let headerToBodySpacing: CGFloat = 14
    static let bodyToActionsSpacing: CGFloat = 26
    static let headerToActionsSpacing: CGFloat = 24
    static let buttonRowSpacing: CGFloat = 12
    static let buttonStackSpacing: CGFloat = 10
    static let buttonHeight: CGFloat = 36
    static let closeButtonSize: CGFloat = 28
    static let bodyLineSpacing: CGFloat = 5
    static let maxBodyHeight: CGFloat = 240
}

struct AppDialogButtonSpec: Identifiable {
    enum Role {
        case neutral
        case prominent
        case destructive
    }

    let id: Int
    let title: String
    let role: Role
    let keyEquivalent: String
    var isDisabled: Bool = false
    let accessibilityID: String
    let action: () -> Void
}

/// Unified Liquid Glass card shared by in-window confirmation dialogs and global `AppDialog` alerts.
struct AppDialogCard: View {
    let title: String
    let message: String
    var width: CGFloat = AppDialogLayout.standardWidth
    let buttons: [AppDialogButtonSpec]
    let onClose: () -> Void
    var dialogAccessibilityID: String = "app-dialog-card"
    var closeAccessibilityID: String = "app-dialog-close"
    var usesNativeGlassSurface: Bool = true

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var needsScrollableMessage: Bool {
        trimmedMessage.count > 240 || trimmedMessage.filter { $0 == "\n" }.count >= 5
    }

    var body: some View {
        let cardContent = VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ThemeColor.kText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                AppDialogCloseButton(accessibilityID: closeAccessibilityID, action: onClose)
            }
            .frame(minHeight: AppDialogLayout.closeButtonSize)

            if !trimmedMessage.isEmpty {
                Group {
                    if needsScrollableMessage {
                        ScrollView {
                            messageText
                        }
                        .frame(maxHeight: AppDialogLayout.maxBodyHeight)
                    } else {
                        messageText
                    }
                }
                .padding(.top, AppDialogLayout.headerToBodySpacing)
            }

            actionButtons
                .padding(.top, trimmedMessage.isEmpty
                    ? AppDialogLayout.headerToActionsSpacing
                    : AppDialogLayout.bodyToActionsSpacing)
        }
        .padding(.horizontal, AppDialogLayout.horizontalPadding)
        .padding(.top, AppDialogLayout.topPadding)
        .padding(.bottom, AppDialogLayout.bottomPadding)
        .frame(width: width)
        .font(.system(size: 14))
        .foregroundStyle(ThemeColor.kText)

        Group {
            if usesNativeGlassSurface {
                cardContent
                    .nativeGlassBackground(in: RoundedRectangle(cornerRadius: AppDialogLayout.cornerRadius, style: .continuous))
            } else {
                cardContent
                    .windowSurfaceBackground(in: RoundedRectangle(cornerRadius: AppDialogLayout.cornerRadius, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(dialogAccessibilityID)
    }

    private var messageText: some View {
        Text(trimmedMessage)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(ThemeColor.kTextSubtle)
            .lineSpacing(AppDialogLayout.bodyLineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if buttons.count == 2 {
            HStack(spacing: AppDialogLayout.buttonRowSpacing) {
                buttonView(buttons[1])
                    .frame(maxWidth: .infinity)
                buttonView(buttons[0])
                    .frame(maxWidth: .infinity)
            }
        } else if buttons.count == 1 {
            buttonView(buttons[0])
                .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: AppDialogLayout.buttonStackSpacing) {
                ForEach(buttons) { spec in
                    buttonView(spec)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func buttonView(_ spec: AppDialogButtonSpec) -> some View {
        AppDialogActionButton(
            spec.title,
            role: spec.role,
            keyEquivalent: spec.keyEquivalent,
            accessibilityID: spec.accessibilityID,
            action: spec.action
        )
        .disabled(spec.isDisabled)
        .accessibilityLabel(spec.title)
    }
}

struct AppDialogCloseButton: NSViewRepresentable {
    let accessibilityID: String
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.press))
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.setAccessibilityIdentifier(accessibilityID)
        button.setAccessibilityLabel(NSLocalizedString("关闭", comment: ""))
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.image = MingCute.image("xmark", size: 12.5)
        button.setAccessibilityIdentifier(accessibilityID)
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
        CGSize(width: AppDialogLayout.closeButtonSize, height: AppDialogLayout.closeButtonSize)
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
}

struct AppDialogActionButton: NSViewRepresentable {
    let title: String
    let role: AppDialogButtonSpec.Role
    let keyEquivalent: String
    let accessibilityID: String
    let action: () -> Void

    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        _ title: String,
        role: AppDialogButtonSpec.Role,
        keyEquivalent: String = "",
        accessibilityID: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.role = role
        self.keyEquivalent = keyEquivalent
        self.accessibilityID = accessibilityID
        self.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.press))
        button.font = .systemFont(ofSize: 14, weight: role == .neutral ? .regular : .medium)
        if #available(macOS 26, *) { button.controlSize = .extraLarge } else { button.controlSize = .large }
        button.setAccessibilityIdentifier(accessibilityID)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = enabled
        button.keyEquivalent = keyEquivalent
        button.title = title
        button.font = .systemFont(ofSize: 14, weight: role == .neutral ? .regular : .medium)
        button.setAccessibilityIdentifier(accessibilityID)
        button.setAccessibilityLabel(title)
        if #available(macOS 26, *) { button.controlSize = .extraLarge } else { button.controlSize = .large }
        button.isBordered = true

        let prominent = role != .neutral
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

        switch role {
        case .destructive:
            button.bezelColor = scheme == .dark
                ? NSColor(srgbRed: 0.88, green: 0.25, blue: 0.24, alpha: 1)
                : NSColor(srgbRed: 0.86, green: 0.21, blue: 0.20, alpha: 1)
        case .prominent:
            button.bezelColor = NSColor(SettingsPalette.monochromeTint(scheme))
        case .neutral:
            button.bezelColor = nil
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        let width = proposal.width ?? max(intrinsic.width, 120)
        return CGSize(width: width, height: AppDialogLayout.buttonHeight)
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
}

@MainActor
final class AppDialogWeakViewBox {
    weak var view: NSView?
}

@MainActor
final class AppDialogWeakResponderBox {
    weak var responder: NSResponder?
}

struct AppDialogViewReader: NSViewRepresentable {
    let box: AppDialogWeakViewBox

    func makeNSView(context: Context) -> NSView {
        let view = PassiveReaderView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }

    private final class PassiveReaderView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

// MARK: - Global AppDialog Presenter

/// Full-window Liquid Glass alert overlay mounted inside an owning window's content container.
@MainActor
final class AppDialogOverlay: NSView {
    let hostingView: NSHostingView<AppDialogOverlayView>
    let cardBox: AppDialogWeakViewBox

    init(model: AppDialogOverlayModel, cardBox: AppDialogWeakViewBox) {
        self.cardBox = cardBox
        self.hostingView = NSHostingView(rootView: AppDialogOverlayView(model: model, cardBox: cardBox))
        super.init(frame: .zero)
        setAccessibilityIdentifier("app-dialog-overlay")
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

    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    func button(at index: Int) -> NSButton? {
        allButtons.first { $0.accessibilityIdentifier() == "app-dialog-button-\(index)" }
    }

    var closeButton: NSButton? {
        allButtons.first { $0.accessibilityIdentifier() == "app-dialog-close" }
    }

    func moveFocus(backwards: Bool) {
        let controls = keyControls
        guard !controls.isEmpty, let window else { return }
        let current = controls.firstIndex { $0 === window.firstResponder }
        let next = current.map { ($0 + (backwards ? -1 : 1) + controls.count) % controls.count }
            ?? (backwards ? controls.count - 1 : 0)
        window.makeFirstResponder(controls[next])
    }

    private var allButtons: [NSButton] {
        func collect(_ view: NSView) -> [NSButton] {
            var found: [NSButton] = []
            if let button = view as? NSButton { found.append(button) }
            for subview in view.subviews { found.append(contentsOf: collect(subview)) }
            return found
        }
        return collect(hostingView)
    }

    private var keyControls: [NSView] {
        allButtons.filter { !$0.isHidden && $0.isEnabled && $0.acceptsFirstResponder }
    }
}

/// Spotlight-style standalone Liquid Glass dialog panel used when no suitable parent window is visible.
@MainActor
final class AppDialogPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func button(at index: Int) -> NSButton? {
        guard let root = contentView else { return nil }
        func collect(_ view: NSView) -> [NSButton] {
            var found: [NSButton] = []
            if let button = view as? NSButton { found.append(button) }
            for subview in view.subviews { found.append(contentsOf: collect(subview)) }
            return found
        }
        return collect(root).first { $0.accessibilityIdentifier() == "app-dialog-button-\(index)" }
    }
}

@MainActor @Observable
final class AppDialogOverlayModel {
    let title: String
    let message: String
    let width: CGFloat
    let buttons: [AppDialogButtonSpec]
    let onClose: () -> Void
    var isPresented: Bool = false

    init(
        title: String,
        message: String,
        width: CGFloat,
        buttons: [AppDialogButtonSpec],
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.width = width
        self.buttons = buttons
        self.onClose = onClose
    }
}

struct AppDialogOverlayView: View {
    let model: AppDialogOverlayModel
    let cardBox: AppDialogWeakViewBox
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cardTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .scale(scale: 0.94, anchor: .center)
                .combined(with: .offset(y: 6))
                .combined(with: .opacity),
            removal: .scale(scale: 0.96, anchor: .center)
                .combined(with: .opacity)
        )
    }

    private var presentationAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.12)
        }
        return model.isPresented
            ? .spring(response: 0.26, dampingFraction: 0.86)
            : .easeOut(duration: 0.14)
    }

    var body: some View {
        ZStack {
            if model.isPresented {
                Color.clear
                    .contentShape(.rect)
                    .accessibilityHidden(true)

                AppDialogCard(
                    title: model.title,
                    message: model.message,
                    width: model.width,
                    buttons: model.buttons,
                    onClose: model.onClose
                )
                .background(AppDialogViewReader(box: cardBox).allowsHitTesting(false))
                .transition(cardTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .actionArrowCursor(enabled: model.isPresented)
        .animation(presentationAnimation, value: model.isPresented)
    }
}

/// Global presenter installed into `AppDialog.presenter` so every alert and confirmation dialog
/// across Asky renders with the unified Liquid Glass style.
@MainActor
final class AppDialogPresenter: AppDialogPresenting {
    static let shared = AppDialogPresenter()

    static func installIfNeeded() {
        if AppDialog.presenter == nil {
            AppDialog.presenter = shared
        }
    }

    private final class Session {
        let alertID: ObjectIdentifier
        weak var ownerWindow: NSWindow?
        var overlay: AppDialogOverlay?
        var overlayModel: AppDialogOverlayModel?
        var panel: AppDialogPanel?
        var monitor: Any?
        var closeObserver: NSObjectProtocol?
        weak var previousResponder: NSResponder?
        var continuation: CheckedContinuation<NSApplication.ModalResponse, Never>?
        var finished = false
        var cancelResponse: NSApplication.ModalResponse

        init(alertID: ObjectIdentifier, ownerWindow: NSWindow?, cancelResponse: NSApplication.ModalResponse) {
            self.alertID = alertID
            self.ownerWindow = ownerWindow
            self.cancelResponse = cancelResponse
        }
    }

    private var sessions: [ObjectIdentifier: Session] = [:]

    func isPresenting(in window: NSWindow?) -> Bool {
        guard let window else { return false }
        return sessions.values.contains { !$0.finished && $0.ownerWindow === window }
    }

    func activeOverlay(in window: NSWindow) -> AppDialogOverlay? {
        sessions.values.first { !$0.finished && $0.ownerWindow === window }?.overlay
    }

    var activeStandalonePanel: AppDialogPanel? {
        sessions.values.first { !$0.finished && $0.panel != nil }?.panel
    }

    func present(_ alert: NSAlert, for owner: NSWindow?) async -> NSApplication.ModalResponse {
        let alertID = ObjectIdentifier(alert)
        let title = alert.messageText
        let message = alert.informativeText
        let rawButtons = alert.buttons

        let cancelIndex: Int
        if rawButtons.count <= 1 {
            cancelIndex = 0
        } else if let escapeIndex = rawButtons.firstIndex(where: { $0.keyEquivalent == "\u{1b}" }) {
            cancelIndex = escapeIndex
        } else {
            cancelIndex = rawButtons.count - 1
        }
        let cancelResponse = Self.response(forIndex: cancelIndex)

        let preferredWidth = preferredCardWidth(title: title, message: message, buttonCount: max(rawButtons.count, 1))
        let parent = resolveParentWindow(owner: owner)

        return await withCheckedContinuation { continuation in
            let session = Session(alertID: alertID, ownerWindow: parent, cancelResponse: cancelResponse)
            session.continuation = continuation
            sessions[alertID] = session

            let finish: @MainActor (NSApplication.ModalResponse, Bool) -> Void = { [weak self] result, animated in
                self?.complete(session: session, response: result, animated: animated)
            }

            let buttonSpecs = makeButtonSpecs(from: rawButtons) { index in
                finish(Self.response(forIndex: index), true)
            }

            if let parent,
               let container = Self.overlayContainer(for: parent),
               canPresentOverlay(in: container, width: preferredWidth, title: title, message: message, buttons: buttonSpecs) {
                presentInWindow(
                    session: session,
                    parent: parent,
                    container: container,
                    title: title,
                    message: message,
                    width: preferredWidth,
                    buttons: buttonSpecs,
                    finish: finish
                )
            } else {
                presentStandalone(
                    session: session,
                    relativeTo: parent,
                    title: title,
                    message: message,
                    width: preferredWidth,
                    buttons: buttonSpecs,
                    finish: finish
                )
            }
        }
    }

    func dismiss(_ alert: NSAlert) {
        guard let session = sessions[ObjectIdentifier(alert)] else { return }
        complete(session: session, response: .abort, animated: false)
    }

    private func presentInWindow(
        session: Session,
        parent: NSWindow,
        container: NSView,
        title: String,
        message: String,
        width: CGFloat,
        buttons: [AppDialogButtonSpec],
        finish: @escaping @MainActor (NSApplication.ModalResponse, Bool) -> Void
    ) {
        captureAndClearFocus(in: parent, session: session)

        let cardBox = AppDialogWeakViewBox()
        let model = AppDialogOverlayModel(
            title: title,
            message: message,
            width: width,
            buttons: buttons,
            onClose: { finish(session.cancelResponse, true) }
        )
        let overlay = AppDialogOverlay(model: model, cardBox: cardBox)
        overlay.frame = container.bounds
        overlay.autoresizingMask = [.width, .height]
        container.addSubview(overlay)
        container.layoutSubtreeIfNeeded()

        session.overlay = overlay
        session.overlayModel = model

        let alertID = session.alertID
        session.closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: parent,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let active = self.sessions[alertID] else { return }
                self.complete(session: active, response: active.cancelResponse, animated: false)
            }
        }

        session.monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]
        ) { [weak self, weak parent, weak overlay] event in
            let swallow: Bool = MainActor.assumeIsolated {
                guard let parent, let overlay, event.window === parent else { return false }
                switch event.type {
                case .scrollWheel:
                    if let cardView = overlay.cardBox.view,
                       cardView.window === parent,
                       cardView.bounds.contains(cardView.convert(event.locationInWindow, from: nil)),
                       Self.containsScrollableView(cardView) {
                        return false
                    }
                    return true
                case .leftMouseDown, .rightMouseDown:
                    if let cardView = overlay.cardBox.view,
                       cardView.window === parent,
                       cardView.bounds.contains(cardView.convert(event.locationInWindow, from: nil)) {
                        return false
                    }
                    if let self, let active = self.sessions[alertID] {
                        self.complete(session: active, response: active.cancelResponse, animated: true)
                    }
                    return true
                case .keyDown:
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if event.keyCode == 53 {
                        if let self, let active = self.sessions[alertID] {
                            self.complete(session: active, response: active.cancelResponse, animated: true)
                        }
                        return true
                    }
                    if (event.keyCode == 36 || event.keyCode == 76) && flags.isEmpty {
                        if let self, let active = self.sessions[alertID] {
                            self.complete(session: active, response: .alertFirstButtonReturn, animated: true)
                        }
                        return true
                    }
                    if event.keyCode == 48 && flags.intersection([.command, .control, .option]).isEmpty {
                        overlay.moveFocus(backwards: flags.contains(.shift))
                        return true
                    }
                    if event.keyCode == 49 && flags.isEmpty, parent.firstResponder is NSButton {
                        return false
                    }
                    if flags.contains(.command) {
                        return false
                    }
                    return true
                default:
                    return false
                }
            }
            return swallow ? nil : event
        }

        DispatchQueue.main.async { [weak parent, weak session] in
            guard let session, !session.finished else { return }
            if let parent { parent.makeFirstResponder(nil) }
            session.overlayModel?.isPresented = true
        }
    }

    private func presentStandalone(
        session: Session,
        relativeTo parent: NSWindow?,
        title: String,
        message: String,
        width: CGFloat,
        buttons: [AppDialogButtonSpec],
        finish: @escaping @MainActor (NSApplication.ModalResponse, Bool) -> Void
    ) {
        let card = AppDialogCard(
            title: title,
            message: message,
            width: width,
            buttons: buttons,
            onClose: { finish(session.cancelResponse, false) },
            usesNativeGlassSurface: false
        )
        let size = SurfacePanel.fittingSize(of: card, maxWidth: width)
        let panel = AppDialogPanel(contentRect: NSRect(origin: .zero, size: size))
        if let appearance = parent?.effectiveAppearance ?? NSApp.effectiveAppearance as NSAppearance? {
            panel.appearance = appearance
        }
        let host = NSHostingView(rootView: card)
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = WindowSurface.glassContentView(host, cornerRadius: AppDialogLayout.cornerRadius)
        if let surface = panel.contentView {
            WindowSurface.updateCorners(of: surface, radius: AppDialogLayout.cornerRadius, circular: false)
        }

        let origin = standaloneOrigin(for: size, relativeTo: parent)
        panel.setFrameOrigin(origin)
        session.panel = panel

        let alertID = session.alertID
        session.closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let active = self.sessions[alertID] else { return }
                self.complete(session: active, response: active.cancelResponse, animated: false)
            }
        }

        session.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self, weak panel] event in
            let swallow: Bool = MainActor.assumeIsolated {
                guard let panel, event.window === panel else { return false }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if event.keyCode == 53 {
                    if let self, let active = self.sessions[alertID] {
                        self.complete(session: active, response: active.cancelResponse, animated: false)
                    }
                    return true
                }
                if (event.keyCode == 36 || event.keyCode == 76) && flags.isEmpty {
                    if let self, let active = self.sessions[alertID] {
                        self.complete(session: active, response: .alertFirstButtonReturn, animated: false)
                    }
                    return true
                }
                return false
            }
            return swallow ? nil : event
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func complete(session: Session, response: NSApplication.ModalResponse, animated: Bool) {
        guard !session.finished else { return }
        session.finished = true

        if let monitor = session.monitor {
            NSEvent.removeMonitor(monitor)
            session.monitor = nil
        }
        if let observer = session.closeObserver {
            NotificationCenter.default.removeObserver(observer)
            session.closeObserver = nil
        }

        let cleanupAndResume: @MainActor () -> Void = { [weak self] in
            if let overlay = session.overlay {
                overlay.removeFromSuperview()
                session.overlay = nil
            }
            session.overlayModel = nil
            if let panel = session.panel {
                panel.orderOut(nil)
                session.panel = nil
            }
            if let owner = session.ownerWindow {
                if let responder = session.previousResponder as? NSView, responder.window === owner {
                    owner.makeFirstResponder(responder)
                }
            }
            session.previousResponder = nil
            self?.sessions.removeValue(forKey: session.alertID)
            let continuation = session.continuation
            session.continuation = nil
            continuation?.resume(returning: response)
        }

        if animated,
           session.overlay != nil,
           let model = session.overlayModel,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            model.isPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                cleanupAndResume()
            }
        } else {
            cleanupAndResume()
        }
    }

    private func captureAndClearFocus(in window: NSWindow, session: Session) {
        if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor {
            session.previousResponder = editor.delegate as? NSResponder
        } else {
            session.previousResponder = window.firstResponder
        }
        window.makeFirstResponder(nil)
    }

    private func resolveParentWindow(owner: NSWindow?) -> NSWindow? {
        let candidates = [owner, NSApp.keyWindow, NSApp.mainWindow]
            + NSApp.orderedWindows.filter { $0.canBecomeMain }.map { Optional($0) }
        return candidates
            .compactMap { $0?.sheetParent ?? $0 }
            .first { $0.isVisible && !($0 is AppDialogPanel) }
    }

    private func canPresentOverlay(
        in container: NSView,
        width: CGFloat,
        title: String,
        message: String,
        buttons: [AppDialogButtonSpec]
    ) -> Bool {
        let minWidth = width + 32
        guard container.bounds.width >= minWidth else { return false }
        let probe = AppDialogCard(title: title, message: message, width: width, buttons: buttons, onClose: {})
        let size = SurfacePanel.fittingSize(of: probe, maxWidth: width)
        return container.bounds.height >= size.height + 32
    }

    private func preferredCardWidth(title: String, message: String, buttonCount: Int) -> CGFloat {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 90 || trimmed.contains("\n\n") || buttonCount >= 3 || title.count > 22 {
            return AppDialogLayout.wideWidth
        }
        return AppDialogLayout.standardWidth
    }

    private func makeButtonSpecs(
        from rawButtons: [NSButton],
        onSelect: @escaping @MainActor (Int) -> Void
    ) -> [AppDialogButtonSpec] {
        if rawButtons.isEmpty {
            return [
                AppDialogButtonSpec(
                    id: 0,
                    title: NSLocalizedString("好", comment: ""),
                    role: .prominent,
                    keyEquivalent: "\r",
                    accessibilityID: "app-dialog-button-0",
                    action: { onSelect(0) }
                )
            ]
        }

        return rawButtons.enumerated().map { index, button in
            let role: AppDialogButtonSpec.Role
            if button.hasDestructiveAction {
                role = .destructive
            } else if index == 0 {
                role = .prominent
            } else {
                role = .neutral
            }
            let keyEquivalent: String
            if !button.keyEquivalent.isEmpty {
                keyEquivalent = button.keyEquivalent
            } else if index == 0 {
                keyEquivalent = "\r"
            } else if index == rawButtons.count - 1 && rawButtons.count > 1 {
                keyEquivalent = "\u{1b}"
            } else {
                keyEquivalent = ""
            }
            return AppDialogButtonSpec(
                id: index,
                title: button.title,
                role: role,
                keyEquivalent: keyEquivalent,
                accessibilityID: "app-dialog-button-\(index)",
                action: { onSelect(index) }
            )
        }
    }

    private func standaloneOrigin(for size: NSSize, relativeTo parent: NSWindow?) -> NSPoint {
        if let parent, parent.isVisible {
            let screenFrame = (parent.screen ?? NSScreen.main)?.visibleFrame ?? .zero
            let x = min(max(parent.frame.midX - size.width / 2, screenFrame.minX + 16),
                        screenFrame.maxX - size.width - 16)
            let y = min(max(parent.frame.midY - size.height / 2, screenFrame.minY + 16),
                        screenFrame.maxY - size.height - 16)
            return NSPoint(x: round(x), y: round(y))
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(
            x: round(frame.midX - size.width / 2),
            y: round(frame.midY - size.height / 2 + 40)
        )
    }

    private static func overlayContainer(for window: NSWindow) -> NSView? {
        guard let root = window.contentView else { return nil }
        if #available(macOS 26, *), let glass = root as? NSGlassEffectView, let content = glass.contentView {
            return content
        }
        return root
    }

    private static func containsScrollableView(_ view: NSView) -> Bool {
        if let scroll = view as? NSScrollView,
           let document = scroll.documentView,
           document.frame.height > scroll.contentView.bounds.height + 1 {
            return true
        }
        return view.subviews.contains(where: containsScrollableView)
    }

    private static func response(forIndex index: Int) -> NSApplication.ModalResponse {
        NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index)
    }
}
