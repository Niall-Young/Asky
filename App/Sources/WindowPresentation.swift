import AppKit

/// Foreground requests are one-shot. Ordinary windows never acquire a floating level.
@MainActor
final class WindowPresentation: NSObject {
    private weak var pendingWindow: NSWindow?
    private var pendingAlpha: CGFloat?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive),
                                               name: NSApplication.didBecomeActiveNotification, object: NSApp)
        NotificationCenter.default.addObserver(self, selector: #selector(cancelPending),
                                               name: NSApplication.didResignActiveNotification, object: NSApp)
        for name in [NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowDismissed(_:)),
                                                   name: name, object: nil)
        }
    }

    func show(_ window: NSWindow, afterActivation: Bool = false) {
        if pendingWindow !== window { cancelPending() }
        window.level = .normal
        window.hidesOnDeactivate = false
        if window.isMiniaturized { window.deminiaturize(nil) }
        pendingWindow = window
        // Accessory-app activation needs an ordered window. Keep a newly opened
        // glass surface transparent until it has the active key appearance.
        if afterActivation && !window.isVisible && pendingAlpha == nil {
            pendingAlpha = window.alphaValue
            window.alphaValue = 0
        }
        window.orderFrontRegardless()
        if afterActivation {
            // This is an explicit user request to open chat. Cooperative
            // activate() may be declined, leaving the prepared window invisible.
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.activate()
        }
        if NSApp.isActive { didBecomeActive() }
    }

    func yieldToAuthentication() {
        // A late activation notification must not take key focus from the
        // system password dialog once credential interaction has begun.
        cancelPending()
    }

    @objc private func didBecomeActive() {
        let window = pendingWindow
        let alpha = pendingAlpha
        pendingWindow = nil
        pendingAlpha = nil
        guard let window else { return }
        guard window.isVisible, !window.isMiniaturized else {
            if let alpha { window.alphaValue = alpha }
            return
        }
        if let alpha {
            window.makeKey()
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            window.alphaValue = alpha
        }
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func cancelPending() {
        let window = pendingWindow
        let alpha = pendingAlpha
        pendingWindow = nil
        pendingAlpha = nil
        if let window, let alpha {
            window.orderOut(nil)
            window.alphaValue = alpha
        }
    }

    @objc private func windowDismissed(_ notification: Notification) {
        if notification.object as? NSWindow === pendingWindow { cancelPending() }
    }
}

/// Handle settings before a non-activating panel forwards keys to its field editor.
enum SettingsShortcut {
    static func matches(_ event: NSEvent) -> Bool {
        event.type == .keyDown
            && event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
            && event.charactersIgnoringModifiers == ","
    }
}
