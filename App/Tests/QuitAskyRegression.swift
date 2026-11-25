import AppKit
import Contracts
import Search

private struct QuitAppsProvider: SearchProvider {
    let source = SearchSource.app
    func search(_ query: String, limit: Int) async -> [SearchResult] {
        try? await Task.sleep(for: .milliseconds(120))
        return [SearchResult(source: .app, target: TargetRef(kind: "app", identifier: "/Applications/Asky.app"),
                             title: "Asky", actions: [.open], score: 100)]
    }
}

@main @MainActor
enum QuitAskyRegression {
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "QuitAskyRegression", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    application.appearance = NSAppearance(named: appearance)
                    try await check(appearance.rawValue)
                }
                print("Quit Asky native regression passed: ranking, scope, sheet, cancellation, confirmation")
                exit(0)
            } catch {
                fputs("Quit Asky regression failed: \(error)\n", stderr)
                exit(1)
            }
        }
        application.run()
    }

    private static func check(_ appearance: String) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-quit-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let model = LauncherModel(app: app, searchProviders: [QuitAppsProvider()], chromeBookmarkAccessAllowed: false)
        for query in ["asky", "ASKY", "  AsKy  "] {
            model.query = query
            try require(model.results.first.map(QuitAskyCommand.isResult) == true, "quit must appear immediately first")
            try await Task.sleep(for: .milliseconds(350))
            try require(model.results.first.map(QuitAskyCommand.isResult) == true, "async apps must not outrank quit")
            try require(model.results.contains { $0.source == .app }, "app result must remain")
        }
        for query in ["ask", "asky other", "> asky", ""] {
            model.query = query
            try require(!model.results.contains(where: QuitAskyCommand.isResult), "unrelated/scoped query must not offer quit")
        }
        model.setFilter(.applications)
        model.query = "asky"
        try require(!model.results.contains(where: QuitAskyCommand.isResult), "app filter must remain apps only")
        model.setFilter(.all)
        model.query = "asky"
        var quits = 0
        model.onQuit = { quits += 1 }
        let controller = LauncherController(model: model)
        controller.show()
        defer { controller.hide() }
        try await Task.sleep(for: .milliseconds(400))
        guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) else {
            throw NSError(domain: "QuitPanelMissing", code: 1)
        }
        try snapshot(panel, "build/quit-asky-results-\(appearance).png")
        model.submit(.executeSelection)
        model.submit(.executeSelection)
        var overlay: AppDialogOverlay?
        for _ in 0..<40 {
            if let found = AppDialogPresenter.shared.activeOverlay(in: panel),
               found.button(at: 0) != nil, found.button(at: 1) != nil {
                overlay = found
                break
            }
            try await Task.sleep(for: .milliseconds(30))
        }
        guard let overlay else { throw NSError(domain: "QuitDialogMissing", code: 1) }
        try await Task.sleep(for: .milliseconds(350))
        try require(panel.isVisible && model.isConfirmingQuit && quits == 0, "confirmation must keep launcher visible without quitting")
        try snapshot(panel, "build/quit-asky-alert-\(appearance).png")
        let alert = QuitAskyCommand.makeAlert()
        try require(alert.buttons.count == 2 && alert.buttons[1].keyEquivalent == "\u{1b}", "cancel must support Escape")
        overlay.button(at: 1)!.performClick(nil)
        try await Task.sleep(for: .milliseconds(350))
        try require(quits == 0 && !model.isConfirmingQuit && panel.isVisible, "cancel must preserve app and search")
        model.execute(QuitAskyCommand.result, action: .open)
        var confirmedOverlay: AppDialogOverlay?
        for _ in 0..<40 {
            if let found = AppDialogPresenter.shared.activeOverlay(in: panel),
               found.button(at: 0) != nil {
                confirmedOverlay = found
                break
            }
            try await Task.sleep(for: .milliseconds(30))
        }
        guard let confirmedOverlay else { throw NSError(domain: "SecondQuitDialogMissing", code: 1) }
        try await Task.sleep(for: .milliseconds(250))
        confirmedOverlay.button(at: 0)!.performClick(nil)
        try await Task.sleep(for: .milliseconds(350))
        try require(quits == 1 && !model.isConfirmingQuit, "confirmation must request application termination exactly once")
        await app.shutdown()
    }

    private static func snapshot(_ window: NSWindow, _ path: String) throws {
        guard let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "QuitSnapshotMissing", code: 1)
        }
        let capture = Process()
        capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
        try capture.run()
        capture.waitUntilExit()
        if capture.terminationStatus == 0 { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
    }
}
