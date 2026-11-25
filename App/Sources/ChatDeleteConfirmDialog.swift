import AppKit
import SwiftUI
import Theme

/// Centered in-window Liquid Glass confirmation dialog for permanently deleting a chat message.
/// Matches Asky's shared SettingsDialog glass chrome, typography, and native macOS 26 capsule controls.
struct ChatDeleteConfirmPresentation: ViewModifier {
    let isPresented: Bool
    let confirmDisabled: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var monitor: Any?
    @State private var anchorBox = ChatDialogWeakViewBox()
    @State private var cardBox = ChatDialogWeakViewBox()
    @State private var previousResponderBox = ChatDialogWeakResponderBox()
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
        return isPresented
            ? .spring(response: 0.26, dampingFraction: 0.86)
            : .easeOut(duration: 0.14)
    }

    func body(content: Content) -> some View {
        content
            .background(ChatDialogViewReader(box: anchorBox).allowsHitTesting(false))
            .overlay {
                if isPresented {
                    ZStack {
                        Color.clear
                            .contentShape(.rect)
                            .accessibilityHidden(true)

                        ChatDeleteConfirmCard(
                            confirmDisabled: confirmDisabled,
                            onCancel: onCancel,
                            onConfirm: onConfirm
                        )
                        .background(ChatDialogViewReader(box: cardBox).allowsHitTesting(false))
                        .transition(cardTransition)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .actionArrowCursor(enabled: isPresented)
                }
            }
            .animation(presentationAnimation, value: isPresented)
            .onAppear {
                if isPresented {
                    suspendWindowFocus()
                    startMonitoring()
                }
            }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    suspendWindowFocus()
                    startMonitoring()
                } else {
                    stopMonitoring()
                    restoreWindowFocus()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { event in
                if isPresented, let owner = anchorBox.view?.window, event.object as? NSWindow === owner {
                    onCancel()
                }
            }
            .onDisappear {
                stopMonitoring()
                previousResponderBox.responder = nil
            }
    }

    private func suspendWindowFocus() {
        let captureAndClear = {
            guard let window = anchorBox.view?.window else { return }
            if previousResponderBox.responder == nil {
                if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor {
                    previousResponderBox.responder = editor.delegate as? NSResponder
                } else {
                    previousResponderBox.responder = window.firstResponder
                }
            }
            window.makeFirstResponder(nil)
        }
        captureAndClear()
        DispatchQueue.main.async {
            if isPresented { captureAndClear() }
        }
    }

    private func restoreWindowFocus() {
        guard let window = anchorBox.view?.window else {
            previousResponderBox.responder = nil
            return
        }
        if let view = previousResponderBox.responder as? NSView, view.window === window {
            window.makeFirstResponder(view)
        }
        previousResponderBox.responder = nil
    }

    private func startMonitoring() {
        stopMonitoring()
        let anchorBox = self.anchorBox
        let cardBox = self.cardBox
        let confirmDisabled = { self.confirmDisabled }
        let onCancel = self.onCancel
        let onConfirm = self.onConfirm

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { event in
            let ownerWindow = MainActor.assumeIsolated { anchorBox.view?.window }
            guard let ownerWindow, event.window === ownerWindow else { return event }

            switch event.type {
            case .scrollWheel:
                return nil
            case .leftMouseDown, .rightMouseDown:
                let insideCard = MainActor.assumeIsolated {
                    guard let cardView = cardBox.view, cardView.window === ownerWindow else { return false }
                    return cardView.bounds.contains(cardView.convert(event.locationInWindow, from: nil))
                }
                if insideCard { return event }
                MainActor.assumeIsolated { onCancel() }
                return nil
            case .keyDown:
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if event.keyCode == 53 {
                    MainActor.assumeIsolated { onCancel() }
                    return nil
                }
                if (event.keyCode == 36 || event.keyCode == 76) && flags.isEmpty {
                    MainActor.assumeIsolated {
                        if !confirmDisabled() { onConfirm() }
                    }
                    return nil
                }
                if flags.contains(.command) {
                    return event
                }
                return nil
            default:
                return event
            }
        }
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct ChatDeleteConfirmCard: View {
    let confirmDisabled: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(NSLocalizedString("删除这条消息？", comment: ""))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ThemeColor.kText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                ChatDialogCloseButton(action: onCancel)
            }
            .frame(minHeight: 28)

            Text(NSLocalizedString("这会永久删除你的消息。此操作无法撤销", comment: ""))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(ThemeColor.kTextSubtle)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            HStack(spacing: 10) {
                ChatDialogActionButton(
                    NSLocalizedString("取消", comment: ""),
                    role: .neutral,
                    keyEquivalent: "\u{1b}",
                    accessibilityID: "chat-delete-confirm-cancel",
                    action: onCancel
                )
                .frame(maxWidth: .infinity)
                .accessibilityLabel(NSLocalizedString("取消", comment: ""))

                ChatDialogActionButton(
                    NSLocalizedString("删除", comment: ""),
                    role: .destructive,
                    keyEquivalent: "\r",
                    accessibilityID: "chat-delete-confirm-delete",
                    action: onConfirm
                )
                .frame(maxWidth: .infinity)
                .disabled(confirmDisabled)
                .accessibilityLabel(NSLocalizedString("删除", comment: ""))
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(width: 340)
        .font(.system(size: 14))
        .foregroundStyle(ThemeColor.kText)
        .nativeGlassBackground(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-delete-confirm-dialog")
    }
}

private struct ChatDialogCloseButton: NSViewRepresentable {
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.press))
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.setAccessibilityIdentifier("chat-delete-confirm-close")
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

private struct ChatDialogActionButton: NSViewRepresentable {
    enum Role {
        case neutral
        case destructive
    }

    let title: String
    let role: Role
    let keyEquivalent: String
    let accessibilityID: String
    let action: () -> Void

    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        _ title: String,
        role: Role,
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
        button.font = .systemFont(ofSize: 14, weight: role == .destructive ? .medium : .regular)
        if #available(macOS 26, *) { button.controlSize = .extraLarge } else { button.controlSize = .large }
        button.setAccessibilityIdentifier(accessibilityID)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = enabled
        button.keyEquivalent = keyEquivalent
        button.title = title
        button.font = .systemFont(ofSize: 14, weight: role == .destructive ? .medium : .regular)
        button.setAccessibilityIdentifier(accessibilityID)
        button.setAccessibilityLabel(title)
        if #available(macOS 26, *) { button.controlSize = .extraLarge } else { button.controlSize = .large }
        button.isBordered = true

        if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial,
           !reduceTransparency, contrast != .increased {
            button.bezelStyle = .glass
            button.borderShape = .capsule
            button.tintProminence = role == .destructive ? .primary : .none
        } else {
            button.bezelStyle = .rounded
            if #available(macOS 26, *) {
                button.borderShape = .automatic
                button.tintProminence = role == .destructive ? .primary : .none
            }
        }

        if role == .destructive {
            button.bezelColor = scheme == .dark
                ? NSColor(srgbRed: 0.88, green: 0.25, blue: 0.24, alpha: 1)
                : NSColor(srgbRed: 0.86, green: 0.21, blue: 0.20, alpha: 1)
        } else {
            button.bezelColor = nil
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        let width = proposal.width ?? max(intrinsic.width, 120)
        return CGSize(width: width, height: 36)
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
}

@MainActor
private final class ChatDialogWeakViewBox {
    weak var view: NSView?
}

@MainActor
private final class ChatDialogWeakResponderBox {
    weak var responder: NSResponder?
}

private struct ChatDialogViewReader: NSViewRepresentable {
    let box: ChatDialogWeakViewBox

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
