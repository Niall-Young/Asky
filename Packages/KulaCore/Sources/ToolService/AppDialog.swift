import AppKit

/// Optional host-provided presentation for app-owned alerts (for example, Liquid Glass overlays).
@MainActor
public protocol AppDialogPresenting: AnyObject {
    func present(_ alert: NSAlert, for owner: NSWindow?) async -> NSApplication.ModalResponse
    func dismiss(_ alert: NSAlert)
}

/// Shared presentation for app-owned alerts. System permission and file panels remain system-owned.
@MainActor
public enum AppDialog {
    public static var presenter: (any AppDialogPresenting)?

    public static func make() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        return alert
    }

    /// Delegate to the installed host presenter when available; otherwise fall back to AppKit sheets/modals.
    @discardableResult
    public static func present(_ alert: NSAlert, for owner: NSWindow? = nil) async -> NSApplication.ModalResponse {
        if let presenter {
            return await presenter.present(alert, for: owner)
        }
        let candidates = [owner, NSApp.keyWindow, NSApp.mainWindow]
            + NSApp.orderedWindows.filter { $0.canBecomeMain }.map { Optional($0) }
        let parent = candidates.compactMap { $0?.sheetParent ?? $0 }
            .first { $0.isVisible && $0 !== alert.window }
        guard let parent else {
            return alert.runModal()
        }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: parent) { response in
                continuation.resume(returning: response)
            }
        }
    }

    public static func dismiss(_ alert: NSAlert) {
        if let presenter {
            presenter.dismiss(alert)
            return
        }
        if let parent = alert.window.sheetParent {
            parent.endSheet(alert.window, returnCode: .abort)
        } else if NSApp.modalWindow === alert.window {
            NSApp.abortModal()
        }
        alert.window.orderOut(nil)
    }

}
