import AppKit
import QuartzCore
import ToolService

/// Local-only diagnostic tracer for rare cold-start window/menu flashes and
/// unexpected settings window presentation. Never uploads data and never logs
/// user text, queries, file paths, or window titles.
@MainActor
final class WindowDiagnostics: NSObject {
    static let shared = WindowDiagnostics()

    private var log: WindowDiagnosticLog?
    private var observing = false
    private let startTime = CACurrentMediaTime()
    private var firstOpenSampleTask: Task<Void, Never>?

    var logFileURL: URL? { log?.fileURL }

    func configure(root: URL) {
        log = WindowDiagnosticLog(directory: root.appending(path: "Diagnostics"))
        guard !observing else { return }
        observing = true
        let names: [Notification.Name] = [
            NSWindow.didExposeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.willCloseNotification,
        ]
        for name in names {
            NotificationCenter.default.addObserver(self, selector: #selector(windowNotification(_:)),
                                                   name: name, object: nil)
        }
    }

    func record(_ event: String, window: NSWindow? = nil, includeEvent: Bool = false,
                includeStack: Bool = false, extra: [(String, String)] = []) {
        guard let log else { return }
        var fields: [(String, String)] = [
            ("uptime", String(format: "%.3f", CACurrentMediaTime() - startTime)),
            ("appActive", NSApp.isActive ? "1" : "0"),
        ]
        if let window {
            fields.append(("win", describe(window)))
        }
        if includeEvent {
            fields.append(("input", describe(NSApp.currentEvent)))
        }
        fields.append(contentsOf: extra)
        if includeStack {
            fields.append(("stack", compactStack()))
        }
        log.record(event, fields: fields)
    }

    /// Samples Asky windows and on-screen windows in the launcher + below-left
    /// region right after the process's first launcher open.
    func recordLauncherFirstOpen(panel: NSWindow) {
        guard log != nil else { return }
        firstOpenSampleTask?.cancel()
        let quartzRegion = launcherInspectionQuartzRect(for: panel.frame)
        sampleFirstOpen(label: "0ms", panel: panel, quartzRegion: quartzRegion)
        firstOpenSampleTask = Task { @MainActor [weak self, weak panel] in
            for (delayMs, label) in [(50, "50ms"), (100, "150ms"), (150, "300ms")] {
                do { try await Task.sleep(for: .milliseconds(delayMs)) } catch { return }
                guard let self, let panel else { return }
                self.sampleFirstOpen(label: label, panel: panel, quartzRegion: quartzRegion)
            }
        }
    }

    private func sampleFirstOpen(label: String, panel: NSWindow, quartzRegion: CGRect) {
        let appWindows = NSApp.windows
            .filter { $0.isVisible || $0 === panel }
            .map { describe($0) }
            .joined(separator: ";")
        let screenSamples = ToolService.sampleOnScreenWindows(near: quartzRegion)
            .prefix(16)
            .map(\.summary)
            .joined(separator: ";")
        record("launcher-first-open-sample", window: panel, extra: [
            ("at", label),
            ("appWins", appWindows.isEmpty ? "none" : appWindows),
            ("screen", screenSamples.isEmpty ? "none" : screenSamples),
        ])
    }

    @objc private func windowNotification(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let kind: String
        switch notification.name {
        case NSWindow.didExposeNotification: kind = "win-expose"
        case NSWindow.didBecomeKeyNotification: kind = "win-key"
        case NSWindow.willCloseNotification: kind = "win-close"
        default: kind = notification.name.rawValue
        }
        record(kind, window: window)
    }

    private func describe(_ window: NSWindow) -> String {
        let name = String(describing: type(of: window))
        let f = window.frame
        let rect = "(\(Int(f.origin.x.rounded())),\(Int(f.origin.y.rounded())),\(Int(f.size.width.rounded()))x\(Int(f.size.height.rounded())))"
        return "\(name)#\(window.windowNumber)[vis=\(window.isVisible ? 1 : 0),key=\(window.isKeyWindow ? 1 : 0),a=\(String(format: "%.2f", window.alphaValue)),lvl=\(window.level.rawValue),\(rect)]"
    }

    private func describe(_ event: NSEvent?) -> String {
        guard let event else { return "none" }
        var parts = ["type=\(event.type.rawValue)"]
        if event.type == .keyDown || event.type == .keyUp {
            parts.append("key=\(event.keyCode)")
        }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue
        parts.append("mods=\(mods)")
        return parts.joined(separator: ",")
    }

    private func compactStack() -> String {
        Thread.callStackSymbols
            .dropFirst(2)
            .prefix(8)
            .map { frame -> String in
                let tokens = frame.split(whereSeparator: \.isWhitespace)
                if tokens.count >= 4 {
                    return "\(tokens[1]):\(tokens[3])"
                }
                return frame
            }
            .joined(separator: "<-")
    }

    /// Converts the launcher bar frame (AppKit bottom-left) plus 480pt below it
    /// into Quartz top-left coordinates for `CGWindowListCopyWindowInfo`.
    private func launcherInspectionQuartzRect(for appKitFrame: NSRect) -> CGRect {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? appKitFrame.maxY
        let topY = primaryMaxY - appKitFrame.maxY
        return CGRect(x: appKitFrame.minX - 24, y: topY - 24,
                      width: appKitFrame.width + 48, height: appKitFrame.height + 504)
    }
}
