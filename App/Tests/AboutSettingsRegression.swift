import AppKit
import SwiftUI

@main @MainActor
enum AboutSettingsRegression {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                let root = FileManager.default.temporaryDirectory.appending(path: "Asky-about-\(UUID())")
                defer { try? FileManager.default.removeItem(at: root) }
                let model = try AppModel(root: root)
                model.settingsTab = SettingsPage.about.rawValue
                let window = SettingsWindow.make(app: model)
                let presentation = WindowPresentation()
                presentation.show(window)
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                try await Task.sleep(for: .milliseconds(450))

                @MainActor func allPushButtons(in view: NSView) -> [NSButton] {
                    var result: [NSButton] = []
                    if let button = view as? NSButton, button.title != "" {
                        result.append(button)
                    }
                    for child in view.subviews { result += allPushButtons(in: child) }
                    return result
                }

                @MainActor func capture(_ name: String) throws {
                    let path = "build/settings-about-\(name).png"
                    let capture = Process()
                    capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
                    capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
                    try capture.run()
                    capture.waitUntilExit()
                    precondition(capture.terminationStatus == 0, "screencapture failed for \(path)")
                }

                for (name, appearance) in [("light", "light"), ("dark", "dark")] {
                    model.preferences.appearance = appearance
                    window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
                    try await Task.sleep(for: .milliseconds(450))

                    let content = window.contentView!
                    let buttons = allPushButtons(in: content)
                    let titles = buttons.map(\.title)
                    precondition(!titles.contains("GitHub"),
                                 "Duplicate 'GitHub' button must be removed from About page (buttons: \(titles))")

                    let checkTitle = NSLocalizedString("检查更新", comment: "")
                    let viewRepoTitle = NSLocalizedString("查看仓库", comment: "")
                    let starRepoTitle = NSLocalizedString("去点 Star", comment: "")

                    let checkButtons = buttons.filter { $0.title == checkTitle }
                    let repoButtons = buttons.filter { $0.title == viewRepoTitle || $0.title == starRepoTitle }
                    precondition(checkButtons.count == 1, "Expected 1 update button, got \(checkButtons.count) (\(titles))")
                    precondition(repoButtons.count == 1, "Expected 1 repository button, got \(repoButtons.count) (\(titles))")
                    precondition(repoButtons[0].image != nil, "Single repository button must show GitHubMark icon")

                    let checkFrame = checkButtons[0].convert(checkButtons[0].bounds, to: content)
                    let repoFrame = repoButtons[0].convert(repoButtons[0].bounds, to: content)
                    let checkAboveRepo = content.isFlipped ? checkFrame.midY < repoFrame.midY : checkFrame.midY > repoFrame.midY
                    precondition(checkAboveRepo,
                                 "Software Update (\(checkFrame.midY)) must sit above Open Source (\(repoFrame.midY))")

                    try capture(name)
                }

                window.close()
                print("About page hierarchy regression passed in light and dark")
                exit(0)
            } catch {
                fputs("AboutSettingsRegression failed: \(error)\n", stderr)
                exit(1)
            }
        }
        application.run()
    }
}
