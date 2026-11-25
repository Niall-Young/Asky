import AppKit
import SwiftUI
import Theme

/// Centered in-window Liquid Glass confirmation dialog for permanently deleting a chat message.
/// Shares Asky's unified `AppDialogCard` glass chrome, generous spacing, and native macOS 26 capsule controls.
struct ChatDeleteConfirmPresentation: ViewModifier {
    let isPresented: Bool
    let confirmDisabled: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var monitor: Any?
    @State private var anchorBox = AppDialogWeakViewBox()
    @State private var cardBox = AppDialogWeakViewBox()
    @State private var previousResponderBox = AppDialogWeakResponderBox()
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
            .background(AppDialogViewReader(box: anchorBox).allowsHitTesting(false))
            .overlay {
                if isPresented {
                    ZStack {
                        Color.clear
                            .contentShape(.rect)
                            .accessibilityHidden(true)

                        AppDialogCard(
                            title: NSLocalizedString("删除这条消息？", comment: ""),
                            message: NSLocalizedString("这会永久删除你的消息。此操作无法撤销", comment: ""),
                            buttons: [
                                AppDialogButtonSpec(
                                    id: 0,
                                    title: NSLocalizedString("删除", comment: ""),
                                    role: .destructive,
                                    keyEquivalent: "\r",
                                    isDisabled: confirmDisabled,
                                    accessibilityID: "chat-delete-confirm-delete",
                                    action: onConfirm
                                ),
                                AppDialogButtonSpec(
                                    id: 1,
                                    title: NSLocalizedString("取消", comment: ""),
                                    role: .neutral,
                                    keyEquivalent: "\u{1b}",
                                    accessibilityID: "chat-delete-confirm-cancel",
                                    action: onCancel
                                ),
                            ],
                            onClose: onCancel,
                            dialogAccessibilityID: "chat-delete-confirm-dialog",
                            closeAccessibilityID: "chat-delete-confirm-close"
                        )
                        .background(AppDialogViewReader(box: cardBox).allowsHitTesting(false))
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
