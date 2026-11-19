import AppKit
import Carbon.HIToolbox
import Contracts
import Search
import LocalStore
import Adapters
import ToolService

private struct WindowSearchProvider: SearchProvider {
    let source: SearchSource
    let delay: Duration
    let count: Int
    var matchingQueries: Set<String>? = nil

    func search(_ query: String, limit: Int) async -> [SearchResult] {
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled, query != "empty",
              matchingQueries.map({ $0.contains(query) }) ?? true else { return [] }
        // Every successive prefix has the same result geometry.
        return (0..<min(count, limit)).map {
            SearchResult(source: source, target: TargetRef(kind: "test", identifier: "\(source)-\($0)"),
                         title: "Safari \($0)", actions: [], score: 1)
        }
    }
}

/// Runs the real launcher tree/panel with delayed sources and an isolated store.
@main
@MainActor
enum LauncherWindowRegression {
    static func main() {
        // Launch Services starts app bundles with a different working directory.
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        _ = FileManager.default.changeCurrentDirectoryPath(root.path)
        let application = NSApplication.shared
        if CommandLine.arguments.contains("--scroll-background") {
            runScrollBackground()
            return
        }
        application.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                let appearances: [NSAppearance.Name] = CommandLine.arguments.contains("--dark-only")
                    ? [.darkAqua] : [.aqua, .darkAqua]
                for appearance in appearances {
                    application.appearance = NSAppearance(named: appearance)
                    if CommandLine.arguments.contains("--app-opening") {
                        try await checkAppOpening()
                    } else if CommandLine.arguments.contains("--shell-lifecycle") {
                        try await checkShellLifecycle()
                    } else if CommandLine.arguments.contains("--first-presentation") {
                        try await checkFirstPresentation()
                    } else if CommandLine.arguments.contains("--command-transition") {
                        try await checkCommandTransition()
                    } else if CommandLine.arguments.contains("--fixed-expanded") || CommandLine.arguments.contains("--result-shrink") {
                        try await checkFixedExpanded()
                    } else if CommandLine.arguments.contains("--result-motion") {
                        try await checkResultMotion()
                    } else if CommandLine.arguments.contains("--alias-results") {
                        try await checkAliasResults()
                    } else if CommandLine.arguments.contains("--command-actions") {
                        try await checkCommandActions()
                    } else if CommandLine.arguments.contains("--action-bar") {
                        try await checkActionBar()
                    } else if CommandLine.arguments.contains("--file-preview") {
                        try await checkFilePreview()
                    } else if CommandLine.arguments.contains("--compact-results") {
                        try await checkCompactResults()
                    } else if CommandLine.arguments.contains("--bookmarks") {
                        try await checkBookmarks()
                    } else if CommandLine.arguments.contains("--accessories-preview") {
                        try await previewAccessories()
                    } else if CommandLine.arguments.contains("--accessories") {
                        try await checkAccessories()
                    } else if CommandLine.arguments.contains("--command-icons") {
                        try await checkCommandIcons()
                    } else if CommandLine.arguments.contains("--system-app-names") {
                        try await checkSystemAppNames()
                    } else if CommandLine.arguments.contains("--alias-routing") || CommandLine.arguments.contains("--command-entry") {
                        try await checkAliasRouting()
                    } else if CommandLine.arguments.contains("--ai-routing") {
                        try await checkAIRouting()
                    } else {
                        try await checkWindow()
                    }
                    print("appearance=\(appearance.rawValue) passed")
                }
                print("LauncherWindow native regression checks passed")
                exit(0)
            } catch {
                fputs("LauncherWindow regression failed: \(error)\n", stderr)
                exit(1)
            }
        }
        application.run()
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "LauncherWindowRegression", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    private struct CompactProvider: SearchProvider {
        let source: SearchSource
        let results: [SearchResult]
        func search(_ query: String, limit: Int) async -> [SearchResult] { Array(results.prefix(limit)) }
    }

    private static func checkFilePreview() async throws {
        let systemKeys = CommandLine.arguments.contains("--system-keys")
        if systemKeys {
            try require(AXIsProcessTrusted() && CGPreflightPostEventAccess(),
                        "system shortcut checks require existing Accessibility permission")
        }
        let inputSource = systemKeys ? TISCopyCurrentKeyboardInputSource().takeRetainedValue() : nil
        defer {
            if let inputSource, !CFEqual(inputSource, TISCopyCurrentKeyboardInputSource().takeRetainedValue()) {
                TISSelectInputSource(inputSource)
            }
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-file-preview-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let markdown = root.appending(path: "Preview.MD")
        let image = root.appending(path: "Preview.png")
        let clipboardImage = root.appending(path: "clipboard.img")
        let other = root.appending(path: "Preview.zip")
        let csv = root.appending(path: "Preview.csv")
        let json = root.appending(path: "Preview.JSON")
        let source = root.appending(path: "Preview.swift")
        let csvText = "name,city\r\nAsky,上海\r\n"
        let jsonText = "{\n  \"name\": \"Asky\"\n}"
        let sourceText = "import Foundation\n\nfunc greet(_ name: String) -> String {\n    \"Hello, \\(name)\"\n}\n"
        let folder = root.appending(path: "Preview.folder.md", directoryHint: .isDirectory)
        let document = "# Project notes\n\n**Images** and Markdown share a preview.\n\n- One\n- Two\n\n![Example](Preview.png)\n\n```swift\nlet name = \"Asky\"\n```"
        try Data(document.utf8).write(to: markdown)
        try Data([0x50, 0x4b, 0x03, 0x04]).write(to: other)
        try Data(csvText.utf8).write(to: csv)
        try jsonText.data(using: .utf16)!.write(to: json)
        try Data(sourceText.utf8).write(to: source)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let bitmap = NSImage(size: NSSize(width: 320, height: 180), flipped: false) { frame in
            NSGradient(starting: .systemBlue, ending: .systemTeal)?.draw(in: frame, angle: 0)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: 108, y: 38, width: 104, height: 104)).fill()
            return true
        }
        let png = NSBitmapImageRep(data: bitmap.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: image)
        try png.write(to: clipboardImage)

        switch try await PreviewFile(url: markdown)?.load() {
        case .markdown(let text, let directory):
            try require(text == document && directory.path == root.resolvingSymlinksInPath().path,
                        "read the original Markdown and its directory")
        default:
            try require(false, "decode an uppercase Markdown extension")
        }
        let embedded = await PreviewFile.loadMarkdownImage(at: image, in: root, maxPixelSize: 320)
        try require(embedded?.width == 320, "resolve local images inside the Markdown directory")

        func key(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags, in window: NSWindow, repeatKey: Bool = false) {
            let character = switch code {
            case 36: "\r"
            case 40: "k"
            case 49: " "
            case 53: "\u{1B}"
            default: "p"
            }
            window.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: repeatKey, keyCode: code)!)
        }

        func capture(_ label: String, window: NSWindow) async throws {
            guard CommandLine.arguments.contains("--capture") else { return }
            try await Task.sleep(for: .milliseconds(250))
            let process = Process()
            process.executableURL = URL(filePath: "/usr/sbin/screencapture")
            let appearance = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue ?? "system"
            let frame = window.frame.integral
            let top = (NSScreen.screens.first?.frame.maxY ?? frame.maxY) - frame.maxY
            let region = [frame.minX, top, frame.width, frame.height].map { String(Int($0)) }.joined(separator: ",")
            process.arguments = ["-x", "-R" + region, "build/file-preview-\(appearance)-\(label).png"]
            try process.run()
            while process.isRunning { try await Task.sleep(for: .milliseconds(20)) }
            try require(process.terminationStatus == 0, "capture the visible window")
        }

        func previewShortcut(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags, in window: NSWindow) async throws {
            guard systemKeys else { key(code, modifiers, in: window); return }
            try require(window.isKeyWindow, "the target window must own the keyboard before posting a shortcut")
            var flags: CGEventFlags = .maskControl
            if modifiers.contains(.shift) { flags.insert(.maskShift) }
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
                event.flags = flags
                event.post(tap: .cghidEventTap)
                try await Task.sleep(for: .milliseconds(30))
            }
        }

        func open(_ label: String, from panel: NSWindow, code: UInt16 = 49,
                  modifiers: NSEvent.ModifierFlags = .control) async throws -> NSWindow {
            try await previewShortcut(code, modifiers, in: panel)
            for _ in 0..<15 {
                if let preview = ContentPreviewWindow.quick.window, preview.isKeyWindow, preview.title == label { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            if let inputSource {
                try require(CFEqual(inputSource, TISCopyCurrentKeyboardInputSource().takeRetainedValue()),
                            "opening a preview preserves the system input source")
            }
            let window = ContentPreviewWindow.quick.window
            try require(window?.title == label && window?.isKeyWindow == true && panel.isVisible,
                        "the shortcut opens \(label) above the originating panel. Key window: \(NSApp.keyWindow?.title ?? "none")")
            let preview = window!
            key(code, modifiers, in: preview, repeatKey: true)
            try require(preview.isVisible, "holding the shortcut keeps the preview open")
            let origin = panel is LauncherPanel ? "launcher" : "clipboard"
            try await capture("\(origin)-\(label)", window: preview)
            return preview
        }

        func checkText(_ expected: String, in window: NSWindow) async throws {
            func textView(in view: NSView) -> NSTextView? {
                if let text = view as? NSTextView { return text }
                return view.subviews.lazy.compactMap { textView(in: $0) }.first
            }
            for _ in 0..<30 {
                if let content = window.contentView, let view = textView(in: content), view.string == expected {
                    try require(view.isSelectable && !view.isEditable, "preview text is selectable and read-only")
                    return
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            try require(false, "the preview displays the original text of \(window.title)")
        }

        func checkLauncherPreview() async throws {
            let results = [markdown, image, csv, json, source, other, folder].map { url in
                SearchResult(source: .file, target: TargetRef(kind: "file", identifier: url.path),
                             title: url.lastPathComponent, actions: [.open, .revealInFinder], score: 100)
            }
            let model = LauncherModel(app: app, searchProviders: [CompactProvider(source: .file, results: results)])
            let launcher = LauncherController(model: model)
            model.query = "Preview"
            launcher.show()
            defer { launcher.hide() }
            guard let launcherPanel = NSApp.windows.first(where: { $0 is LauncherPanel }) as? LauncherPanel else {
                throw NSError(domain: "AskyFilePreview", code: 1)
            }
            for _ in 0..<80 {
                if model.results.filter({ $0.source == .file }).count == results.count { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            try require(launcherPanel.isVisible && model.results.filter({ $0.source == .file }).count == results.count,
                        "launcher and file fixtures must be visible before testing")
            func selectLauncherFile(_ url: URL) throws {
                guard let index = model.results.firstIndex(where: { $0.target.identifier == url.path }) else {
                    throw NSError(domain: "AskyFilePreview", code: 4,
                                  userInfo: [NSLocalizedDescriptionKey: "Missing launcher fixture \(url.lastPathComponent)"])
                }
                model.selection = index
            }

            for url in [markdown, image, csv, json, source] {
                try selectLauncherFile(url)
                try require(model.secondaryActions.first?.title == "快速预览" &&
                            model.secondaryActions.first?.shortcut == "⌃ Space",
                            "supported files show Quick Preview first with its shortcut")
                let preview = try await open(url.lastPathComponent, from: launcherPanel)
                if let expected = [csv: csvText, json: jsonText, source: sourceText][url] {
                    try await checkText(expected, in: preview)
                }
                key(53, [], in: preview)
                try await Task.sleep(for: .milliseconds(100))
                try require(!preview.isVisible && launcherPanel.isKeyWindow, "Escape restores the search field")
                try require(model.query == "Preview" && model.selectedActionResult?.target.identifier == url.path,
                            "closing a preview preserves the search and selected result")
            }
            try selectLauncherFile(markdown)
            key(40, .command, in: launcherPanel)
            try require(model.isActionsMenuPresented && model.actionSelection == 0 &&
                        model.secondaryActions.first?.title == "快速预览",
                        "More opens with Quick Preview highlighted")
            try await capture("launcher-more", window: launcherPanel)
            try require(app.preferences.setShortcut(.launcherPreview, .init(code: 35, modifiers: 4608, label: "⌃⇧ P")),
                        "launcher preview shortcut can be remapped")
            try require(model.secondaryActions.first?.shortcut == "⌃⇧ P", "More shows the configured shortcut")
            key(36, [], in: launcherPanel)
            guard let menuPreview = ContentPreviewWindow.quick.window else {
                throw NSError(domain: "AskyFilePreview", code: 3)
            }
            try require(menuPreview.isKeyWindow && menuPreview.title == markdown.lastPathComponent && !model.isActionsMenuPresented,
                        "Return on the first menu item opens the file preview")
            key(53, [], in: menuPreview)
            try await Task.sleep(for: .milliseconds(100))
            try selectLauncherFile(other)
            key(35, [.control, .shift], in: launcherPanel)
            try require(ContentPreviewWindow.quick.window?.isVisible == false, "archives have no preview")
            for url in [other, folder] {
                try selectLauncherFile(url)
                try require(!model.secondaryActions.contains { $0.title == "快速预览" },
                            "unsupported files and folders omit Quick Preview")
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        if !CommandLine.arguments.contains("--clipboard-only") { try await checkLauncherPreview() }

        let store = ClipboardStore(app.store)
        let entries = [
            ClipboardItem(kind: .image, filePath: clipboardImage.path, byteSize: png.count, contentHash: "image"),
            ClipboardItem(kind: .file, text: markdown.lastPathComponent, filePaths: [markdown.path], byteSize: 1, contentHash: "markdown"),
            ClipboardItem(kind: .file, text: csv.lastPathComponent, filePaths: [csv.path], byteSize: 1, contentHash: "csv"),
            ClipboardItem(kind: .file, text: "Multiple", filePaths: [image.path, markdown.path], byteSize: 1, contentHash: "multi"),
            ClipboardItem(kind: .text, text: "Clipboard text", byteSize: 14, contentHash: "text"),
            ClipboardItem(kind: .file, text: folder.lastPathComponent, filePaths: [folder.path], byteSize: 1, contentHash: "folder")
        ]
        for item in entries { try store.insert(item) }
        let clipboard = ClipboardController(app: app, pasteTargetProvider: { .unavailable })
        clipboard.show()
        defer { clipboard.hide() }
        for _ in 0..<80 {
            if clipboard.items.count == entries.count { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let clipboardPanel = NSApp.windows.first(where: {
            $0.title == NSLocalizedString("剪贴板历史", comment: "") && $0.isVisible
        }), clipboard.items.count == entries.count else {
            throw NSError(domain: "AskyFilePreview", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Clipboard and history fixtures must be visible before testing"])
        }
        for (item, title) in zip(entries, [entries[0].imageTitle, markdown.lastPathComponent, csv.lastPathComponent]) {
            clipboard.select(item)
            try require(clipboard.actionKinds == [.preview, .copy, .delete, .clearAll],
                        "supported clipboard entries show Quick Preview first")
            let preview = try await open(title, from: clipboardPanel)
            if item.filePaths == [csv.path] { try await checkText(csvText, in: preview) }
            try await previewShortcut(49, .control, in: preview)
            try await Task.sleep(for: .milliseconds(100))
            try require(!preview.isVisible && clipboardPanel.isKeyWindow && clipboard.selectedItem?.id == item.id,
                        "Control-Space closes the preview and restores the clipboard selection")
        }
        clipboard.select(entries[3])
        key(49, .control, in: clipboardPanel)
        try require(ContentPreviewWindow.quick.window?.isVisible == false, "a batch of files has no single-file preview")
        for item in entries.dropFirst(3) {
            clipboard.select(item)
            try require(clipboard.actionKinds == [.copy, .delete, .clearAll],
                        "clipboard multi-file records, text and folders omit Quick Preview")
        }
        clipboard.select(entries[0])
        key(40, .command, in: clipboardPanel)
        try require(clipboard.isActionsMenuPresented && clipboard.actionSelection == 0,
                    "Clipboard More opens with Quick Preview highlighted")
        try await capture("clipboard-more", window: clipboardPanel)
        key(36, [], in: clipboardPanel)
        try require(ContentPreviewWindow.quick.window?.isKeyWindow == true &&
                    ContentPreviewWindow.quick.window?.title == entries[0].imageTitle && !clipboard.isActionsMenuPresented,
                    "Return on the first clipboard menu item opens the original image")
        if let preview = ContentPreviewWindow.quick.window { key(53, [], in: preview) }
        try await Task.sleep(for: .milliseconds(100))
        clipboard.select(entries[1])
        try require(app.preferences.setShortcut(.clipboardPreview, .init(code: 35, modifiers: 4608, label: "⌃⇧ P")),
                    "an unused shortcut can replace the clipboard default")
        try require(clipboard.actionKinds.first?.shortcut.map { clipboard.shortcutPreferences.shortcut($0).label } == "⌃⇧ P",
                    "the Clipboard More row follows the configured preview shortcut")
        key(40, .command, in: clipboardPanel)
        try await Task.sleep(for: .milliseconds(250))
        let menuFrame = clipboard.actionsMenuFrame
        try require(clipboard.isActionsMenuPresented && !menuFrame.isEmpty, "the clipboard menu is laid out before clicking")
        let previewRow = NSPoint(x: menuFrame.midX, y: menuFrame.maxY - 26)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let click = NSEvent.mouseEvent(with: type, location: previewRow, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: clipboardPanel.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
            NSApp.postEvent(click, atStart: false)
        }
        try await Task.sleep(for: .milliseconds(150))
        try require(ContentPreviewWindow.quick.window?.isKeyWindow == true &&
                    ContentPreviewWindow.quick.window?.title == markdown.lastPathComponent && !clipboard.isActionsMenuPresented,
                    "clicking the first clipboard menu row opens the Markdown preview")
        if let preview = ContentPreviewWindow.quick.window { key(53, [], in: preview) }
        try await Task.sleep(for: .milliseconds(100))
        key(49, .control, in: clipboardPanel)
        try require(ContentPreviewWindow.quick.window?.isVisible == false, "the old shortcut is released on remap")
        let preview = try await open(markdown.lastPathComponent, from: clipboardPanel, code: 35, modifiers: [.control, .shift])
        clipboard.hide()
        try require(!preview.isVisible, "hiding the original panel closes its preview")
    }

    private static func checkAppOpening() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-app-opening-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        for kind in ["app", "launcher-alias"] {
            let target = URL(filePath: "/Applications/Slow Launch Fixture.app")
            let source: SearchSource = kind == "launcher-alias" ? .keyword : .app
            let result = SearchResult(source: source, target: TargetRef(kind: kind, identifier: target.path),
                                      title: "Slow Launch Fixture", actions: [.open], score: 100)
            var pending: CheckedContinuation<Void, Error>?
            var requestedURL: URL?
            var hiddenBeforeLaunch = false
            var completed = false
            let model = LauncherModel(app: app, searchProviders: [CompactProvider(source: source, results: [result])],
                                      applicationOpener: { url in
                requestedURL = url
                hiddenBeforeLaunch = !NSApp.windows.contains { $0 is LauncherPanel && $0.isVisible }
                try await withCheckedThrowingContinuation { pending = $0 }
                completed = true
            })
            let controller = LauncherController(model: model)
            defer { controller.hide() }
            controller.show()
            guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) as? LauncherPanel else {
                throw NSError(domain: "LauncherWindowRegression", code: 1)
            }
            panel.onBlur = {}
            model.query = "slowfixture"
            try await Task.sleep(for: .milliseconds(350))
            try require(model.results.first?.target == result.target,
                        "application result must be selected: kind=\(kind), query=\(model.query), results=\(model.results.map { $0.target })")
            guard let field = panel.contentView.flatMap({ searchField(in: $0) }) else {
                throw NSError(domain: "LauncherWindowRegression", code: 1)
            }
            panel.makeFirstResponder(field)
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                        windowNumber: panel.windowNumber, context: nil, characters: "\r",
                                        charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
            panel.sendEvent(event)
            try await Task.sleep(for: .milliseconds(30))
            try require(requestedURL == target && pending != nil, "Return must request exactly the selected application")
            try require(hiddenBeforeLaunch && !controller.isVisible && model.results.isEmpty,
                        "launcher must hide and release results before waiting for application startup")
            try require(model.query.isEmpty && !completed, "reset must complete while launch is pending")

            // A new session must remain usable while the old launch is suspended.
            controller.show()
            panel.onBlur = {}
            model.query = "next session"
            try await Task.sleep(for: .milliseconds(30))
            try require(controller.isVisible && model.query == "next session" && !completed,
                        "a slow target must not prevent reopening and typing")
            pending?.resume()
            pending = nil
            try await Task.sleep(for: .milliseconds(30))
            try require(completed && controller.isVisible && model.query == "next session",
                        "late launch completion must not reset or hide the newer session")
            controller.hide()
            print("PASS: \(kind) Return hides before slow startup; new session remains responsive")
        }
        do {
            try await ToolService.openLauncherApplication(root.appending(path: "Missing.app"))
            throw NSError(domain: "LauncherWindowRegression", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "missing application unexpectedly opened"])
        } catch let error as NSError where error.domain != "LauncherWindowRegression" {
            print("PASS: async launch reports missing application: \(error.domain) \(error.code)")
        }
    }

    private static func checkCommandActions() async throws {
        let appearance = NSApp.appearance?.name ?? .aqua
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-command-actions-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        app.preferences.appearance = appearance == .darkAqua ? "dark" : "light"
        let model = LauncherModel(app: app, searchProviders: [])
        let controller = LauncherController(model: model)
        var settings: NSWindow?
        app.onOpenSettings = {
            if settings == nil {
                settings = SettingsWindow.make(app: app)
                settings?.isReleasedWhenClosed = false
            }
            NSApp.activate(ignoringOtherApps: true)
            settings?.makeKeyAndOrderFront(nil)
        }
        defer { controller.hide(); settings?.close() }
        func selectGoogle() throws {
            guard let index = model.results.firstIndex(where: { $0.title.contains("Google") }) else {
                throw NSError(domain: "CommandActions", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing Google query=\(model.query) results=\(model.results.map(\.title))"])
            }
            model.selection = index
        }
        func action(_ editing: Bool) throws -> LauncherAction {
            guard let action = model.secondaryActions.first(where: {
                if editing, case .editCommand("go") = $0.kind { return true }
                if !editing, case .disableCommand("go") = $0.kind { return true }
                return false
            }) else { throw NSError(domain: "CommandActions", code: 2) }
            return action
        }
        func focusedTrigger() -> String? {
            (settings?.firstResponder as? NSTextView)?.string
        }
        for keyword in ["go", "google"] {
            app.preferences.commandKeywords["go"] = keyword == "go" ? nil : keyword
            NSApp.activate(ignoringOtherApps: true)
            controller.show()
            (NSApp.windows.first { $0 is LauncherPanel && $0.isVisible } as? LauncherPanel)?.onBlur = {}
            try await Task.sleep(for: .milliseconds(350))
            model.query = keyword
            try await Task.sleep(for: .milliseconds(200))
            try selectGoogle()
            try require(model.toggleActionsMenu(), "command must offer More")
            let disable = try action(false)
            try require(disable.isNegative, "Disable must use negative presentation")
            try await Task.sleep(for: .milliseconds(250))
            let panel = NSApp.windows.first { $0 is LauncherPanel && $0.isVisible }!
            let capture = Process()
            capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(panel.windowNumber),
                                 "build/command-actions-\(NSApp.appearance!.name.rawValue)-\(keyword).png"]
            try capture.run(); capture.waitUntilExit()
            try require(capture.terminationStatus == 0, "command menu screenshot must succeed")
            model.performLauncherAction(try action(true))
            try await Task.sleep(for: .milliseconds(500))
            try require(app.settingsTab == SettingsPage.keywords.rawValue, "Edit must open command settings")
            let settingsCapture = Process()
            settingsCapture.executableURL = URL(filePath: "/usr/sbin/screencapture")
            settingsCapture.arguments = ["-x", "-l", String(settings!.windowNumber),
                                 "build/command-settings-\(NSApp.appearance!.name.rawValue)-\(keyword).png"]
            try settingsCapture.run(); settingsCapture.waitUntilExit()
            try require(settingsCapture.terminationStatus == 0, "settings screenshot must succeed")
            try require(focusedTrigger() == keyword, "Edit must focus the matching trigger field")
            // Requesting the same command again must also focus an existing settings window.
            settings?.makeFirstResponder(nil)
            app.editCommand("go")
            try await Task.sleep(for: .milliseconds(250))
            try require(focusedTrigger() == keyword, "repeat Edit must restore focus")
            settings?.orderOut(nil)
            model.query = keyword + " SwiftUI"
            try await Task.sleep(for: .milliseconds(200))
            try selectGoogle()
            model.performLauncherAction(try action(false))
            try require(app.preferences.disabledBuiltInCommands.contains("go"), "Disable must clear settings checkbox state")
            try require(!model.results.contains { $0.title.contains("Google") }, "Disable must refresh search results")
            let saved = app.store.codableSetting(SettingsPreferences.key, as: SettingsPreferences.self)
            try require(saved?.disabledBuiltInCommands.contains("go") == true, "Disable must persist")
            app.preferences.disabledBuiltInCommands.remove("go")
            settings?.close()
            settings = nil
        }
        print("command actions: default/custom trigger, negative Disable, settings focus/repeat focus, scoped disable and persistence passed")
    }

    private static func checkActionBar() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-actions-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = root.appending(path: "Design reference.md")
        try Data("Action menu regression".utf8).write(to: fixture)
        let app = try AppModel(root: root.appending(path: "store"))
        var rows: [SearchResult] = []
        for index in 0..<15 {
            let path = index == 0 ? fixture.path : root.appending(path: "Design \(index).pdf").path
            let title = index == 0 ? "Design reference.md" : "Design \(index).pdf"
            rows.append(SearchResult(source: .file, target: TargetRef(kind: "file", identifier: path),
                                     title: title, actions: [.open, .revealInFinder], score: Double(100 - index)))
        }
        let provider = CompactProvider(source: .file, results: rows)
        struct AppCopyProvider: SearchProvider {
            let source = SearchSource.app
            func search(_ query: String, limit: Int) async -> [SearchResult] {
                guard query == "Notes" else { return [] }
                return [SearchResult(source: .app,
                    target: TargetRef(kind: "app", identifier: "/System/Applications/Notes.app"),
                    title: "Notes", actions: [.open, .revealInFinder], score: 100)]
            }
        }
        let model = LauncherModel(app: app, searchProviders: [provider, AppCopyProvider()])
        let controller = LauncherController(model: model)
        NSApp.activate(ignoringOtherApps: true)
        model.query = "Design"
        controller.show()
        guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) as? LauncherPanel else {
            throw NSError(domain: "ActionBar", code: 1)
        }
        panel.onBlur = {}
        defer { controller.hide() }
        for _ in 0..<80 {
            if !model.results.isEmpty && !model.isSearching { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try require(!model.results.isEmpty, "action fixtures must finish loading: query=\(model.query), searching=\(model.isSearching)")
        try await Task.sleep(for: .milliseconds(400))
        let responder = panel.firstResponder
        let resultID = model.results[model.selection].id
        let input = model.inputText
        let frame = panel.frame
        func key(_ code: UInt16, modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false) {
            let character: String = switch code {
            case 8: "c"
            case 40: "k"
            case 125: "\u{F701}"
            case 126: "\u{F700}"
            case 36: "\r"
            case 53: "\u{1B}"
            default: ""
            }
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                        timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                                        characters: character, charactersIgnoringModifiers: character,
                                        isARepeat: repeatKey, keyCode: code)!
            panel.sendEvent(event)
        }
        func capture(_ name: String, window: NSWindow? = nil) throws {
            let window = window ?? panel
            let process = Process()
            process.executableURL = URL(filePath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-l", String(window.windowNumber),
                                 "build/launcher-actions-\(NSApp.appearance!.name.rawValue)-\(name).png"]
            try process.run()
            process.waitUntilExit()
            try require(process.terminationStatus == 0, "action screenshot must succeed")
        }
        try require(model.primaryLauncherAction?.title == "打开", "file primary action must be Open")
        try require(model.finderLauncherAction?.title == "在访达中显示" &&
                    model.finderLauncherAction?.shortcut == model.actionPreferences.revealInFinderHotKey.label,
                    "file must expose Finder action with configured shortcut in the left action bar")
        try require(model.secondaryActions.count == 5 && model.secondaryActions.first?.title == "快速预览" && !model.secondaryActions.contains {
            if case .result(.revealInFinder) = $0.kind { return true }; return false
        }, "supported file menu must put preview before the file operations")
        if CommandLine.arguments.contains("--more-inspect") {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            print("More inspection ready")
            fflush(stdout)
            try await Task.sleep(for: .seconds(45))
            return
        }
        try capture("closed")
        key(40, modifiers: .command)
        try await Task.sleep(for: .milliseconds(200))
        try require(model.isActionsMenuPresented && model.actionSelection == 0, "Cmd K must open on first action")
        key(40, modifiers: .command, repeatKey: true)
        try require(model.isActionsMenuPresented, "held Cmd K must not flicker")
        key(125)
        try require(model.actionSelection == 1 && model.results[model.selection].id == resultID, "Down must navigate menu only")
        key(126)
        try require(model.actionSelection == 0, "Up must navigate menu")
        try require(panel.firstResponder === responder && model.inputText == input, "menu must retain native editor and query")
        try require(panel.frame == frame, "menu must overlay without resizing launcher")
        try require(panel.childWindows?.contains { $0.isVisible && abs($0.frame.width - LauncherLayout.actionsMenuWidth) < 2 } != true,
                    "More must transform inside the shell instead of opening a child window")
        try require(model.actionsMenuFrame.width == LauncherLayout.actionsMenuWidth &&
                    abs(model.actionsMenuFrame.minY - 12) <= 1 &&
                    model.actionsMenuFrame.maxY < panel.frame.height,
                    "menu must grow upward from the original footer button within the shell")
        try capture("open")
        key(40, modifiers: .command)
        try await Task.sleep(for: .milliseconds(100))
        try require(!model.isActionsMenuPresented, "second Cmd K must dismiss menu")
        if CommandLine.arguments.contains("--more-motion") {
            let recording = Process()
            recording.executableURL = URL(filePath: "/usr/sbin/screencapture")
            let recordingPath = "build/launcher-more-morph-\(NSApp.appearance!.name.rawValue)-\(UUID()).mov"
            recording.arguments = ["-x", "-v", "-V", "4", "-l", String(panel.windowNumber), recordingPath]
            try recording.run()
            try await Task.sleep(for: .milliseconds(700))
            key(40, modifiers: .command)
            try await Task.sleep(for: .milliseconds(900))
            key(53)
            try await Task.sleep(for: .milliseconds(900))
            key(40, modifiers: .command)
            try await Task.sleep(for: .milliseconds(900))
            key(53)
            while recording.isRunning { try await Task.sleep(for: .milliseconds(100)) }
            try require(recording.terminationStatus == 0, "morph recording must succeed")
            print("More morph recording: \(recordingPath)")
            // The system recording UI can temporarily take key status from this fixture.
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(responder)
        }
        key(125)
        try require(model.selection == 1, "Down must resume result navigation")
        model.selection = 0
        key(40, modifiers: .command)
        key(125)
        key(125)
        key(36)
        try require(!model.isActionsMenuPresented && NSPasteboard.general.string(forType: .string) == fixture.path,
                    "Return on Copy path must execute the selected menu action")
        try require(controller.isVisible, "Copy path must retain launcher")
        func copiedURLs() -> [URL] {
            (NSPasteboard.general.readObjects(forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        }
        guard let editor = panel.firstResponder as? NSTextView else {
            throw NSError(domain: "ActionBarEditor", code: 1)
        }
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        key(47, modifiers: [.command, .shift])
        try require(NSPasteboard.general.string(forType: .string) == fixture.lastPathComponent && copiedURLs().isEmpty,
                    "Cmd Shift period must copy the full filename including extension")
        key(40, modifiers: .command)
        key(47, modifiers: [.command, .shift])
        try require(!model.isActionsMenuPresented && controller.isVisible && model.inputText == input,
                    "filename shortcut must close More and retain the launcher query")
        key(40, modifiers: .command)
        key(125)
        key(125)
        key(125)
        key(36)
        try require(!model.isActionsMenuPresented && NSPasteboard.general.string(forType: .string) == fixture.lastPathComponent,
                    "Return on Copy filename must copy filename")
        try require(model.secondaryActions.contains {
            if case .showFileInfo = $0.kind { return $0.shortcut == "⌘ I" }; return false
        }, "file info action must advertise Cmd I")
        key(8, modifiers: .command)
        try require(copiedURLs() == [fixture], "Cmd C must copy a file URL, not path text")
        try require(controller.isVisible && model.inputText == input && model.results[model.selection].id == resultID,
                    "file copy must retain launcher, query and selection")
        editor.setSelectedRange(NSRange(location: 0, length: 3))
        let textCopy = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "c",
            charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
        try require(!model.handleActionKey(textCopy), "selected text must fall through to native Copy")
        // This harness dispatches directly to the panel, bypassing the application's Edit menu.
        editor.copy(nil)
        try require(NSPasteboard.general.string(forType: .string) == "Des" && copiedURLs().isEmpty,
                    "Cmd C must preserve selected search text copying")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        key(40, modifiers: .command)
        key(125)
        key(36)
        try require(!model.isActionsMenuPresented && copiedURLs() == [fixture],
                    "Return on Copy must copy file and close menu")
        key(40, modifiers: .command)
        key(8, modifiers: .command)
        try require(!model.isActionsMenuPresented && copiedURLs() == [fixture],
                    "Cmd C must also work with More open")
        let appURL = URL(fileURLWithPath: "/System/Applications/Notes.app")
        model.query = "Notes"
        try await Task.sleep(for: .milliseconds(400))
        model.selection = 0
        try require(model.finderLauncherAction != nil && model.secondaryActions.count == 4,
                    "app must expose Finder in action bar and all file operations in menu")
        try capture("app")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        key(8, modifiers: .command)
        try require(copiedURLs() == [appURL], "Cmd C on app must copy app bundle URL")
        try require(model.secondaryActions.contains {
            if case .showFileInfo = $0.kind { return $0.shortcut == "⌘ I" }; return false
        }, "app info action must advertise Cmd I")
        try require(!model.secondaryActions.contains {
            if case .enterFolder = $0.kind { return true }; return false
        }, "app bundles must not offer folder search")
        key(47, modifiers: [.command, .shift])
        try require(NSPasteboard.general.string(forType: .string) == appURL.lastPathComponent && copiedURLs().isEmpty,
                    "app filename shortcut must copy the bundle name including .app")
        key(40, modifiers: .command)
        key(125)
        key(125)
        key(36)
        try require(!model.isActionsMenuPresented && controller.isVisible && model.inputText == "Notes" &&
                    NSPasteboard.general.string(forType: .string) == appURL.lastPathComponent,
                    "app Copy filename menu action must retain the launcher query: visible=\(controller.isVisible), query=\(model.inputText), clipboard=\(NSPasteboard.general.string(forType: .string) ?? "nil")")
        model.query = "Design"
        try await Task.sleep(for: .milliseconds(400))
        model.selection = 1
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("preserve clipboard", forType: .string)
        key(8, modifiers: .command)
        try require(NSPasteboard.general.string(forType: .string) == "preserve clipboard",
                    "missing original must not erase clipboard")
        model.selection = 0


        key(40, modifiers: .command)
        key(53)
        try require(!model.isActionsMenuPresented && controller.isVisible, "Escape must close only menu")
        key(40, modifiers: .command)
        model.inputText = "Design new"
        try require(!model.isActionsMenuPresented, "query changes must dismiss stale actions")
        try await Task.sleep(for: .milliseconds(400))
        guard let lastFile = model.results.lastIndex(where: { $0.source == .file }) else {
            throw NSError(domain: "ActionBar", code: 2)
        }
        model.selection = lastFile
        try await Task.sleep(for: .milliseconds(300))
        try capture("last-row")
        model.selection = model.results.firstIndex(where: { $0.source == .askAI })!
        try require(model.primaryLauncherAction?.title == "询问 AI" && model.secondaryActions.isEmpty && model.finderLauncherAction == nil,
                    "AI must have its own primary action and no empty More button")
        key(40, modifiers: .command)
        try require(!model.isActionsMenuPresented, "Cmd K must not open an empty menu")
        try await Task.sleep(for: .milliseconds(200))
        try capture("ai")
        model.query = "1+2"
        try await Task.sleep(for: .milliseconds(400))
        try require(model.primaryLauncherAction?.title == "复制结果", "calculator must offer Copy result")
        try capture("calculation")
        model.inputText = ""
        try await Task.sleep(for: .milliseconds(400))
        try require(abs(panel.frame.height - LauncherLayout.inputHeight) <= 1 && !model.isActionsMenuPresented,
                    "clearing root search must remove action surfaces and collapse")
        print("action bar: keyboard toggle/navigation, focus, path execution, query dismissal, final row, AI/calculation passed")
    }

    private static func checkCompactResults() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-compact-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pdf = root.appending(path: "项目说明.pdf")
        try Data().write(to: pdf)
        let folder = root.appending(path: "Design.assets")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try require(ToolService.launcherFileType(filePath: pdf.path) == "PDF", "PDF must show its format")
        try require(ToolService.launcherFileType(filePath: folder.path) != "ASSETS", "directory extension must not become file format")
        let app = try AppModel(root: root.appending(path: "store"))
        let model = LauncherModel(app: app, searchProviders: [
            CompactProvider(source: .app, results: [
                SearchResult(source: .app, target: TargetRef(kind: "app", identifier: "/System/Applications/Notes.app"),
                             title: "备忘录", subtitle: "/System/Applications/Notes.app", actions: [.open], score: 100),
                SearchResult(source: .app, target: TargetRef(kind: "app", identifier: "/System/Applications/Utilities/Terminal.app"),
                             title: "终端", subtitle: "/System/Applications/Utilities/Terminal.app", actions: [.open], score: 99)]),
            CompactProvider(source: .file, results: [pdf, folder].enumerated().map { index, url in
                SearchResult(source: .file, target: TargetRef(kind: "file", identifier: url.path),
                             title: url.lastPathComponent, subtitle: root.path, actions: [.open], score: Double(90 - index))
            } + [SearchResult(source: .file, target: TargetRef(kind: "file", identifier: root.appending(path: "readme.md").path),
                              title: String(repeating: "很长的中英文项目名称 Design reference ", count: 4) + ".md",
                              subtitle: root.path, actions: [.open], score: 80)])
        ])
        let controller = LauncherController(model: model)
        model.query = "design"
        controller.show()
        guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) as? LauncherPanel else {
            throw NSError(domain: "CompactResults", code: 1)
        }
        panel.onBlur = {}
        defer { controller.hide() }
        try await Task.sleep(for: .milliseconds(800))
        try require(model.results.contains { $0.source == .file }, "file fixture must render")
        guard let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "CompactResults", code: 2)
        }
        try require(panel.contentView?.layer?.cornerRadius == 26, "expanded shell must retain the 26 pt radius")
        try require(panel.contentView?.layer?.cornerCurve == .circular, "expanded shell must retain circular corners")
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to:
            URL(filePath: "build/launcher-compact-\(NSApp.appearance!.name.rawValue).png"))
        model.inputText = ""
        try await Task.sleep(for: .milliseconds(1000))
        try require(abs(panel.frame.height - LauncherLayout.inputHeight) <= 1, "cleared root shell must collapse")
        try require(panel.contentView?.layer?.cornerRadius == 26, "empty shell must use a 26 pt radius")
        try require(panel.contentView?.layer?.cornerCurve == .circular, "empty shell ends must be circular")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(panel.windowNumber),
                             "build/launcher-compact-empty-\(NSApp.appearance!.name.rawValue).png"]
        try capture.run()
        capture.waitUntilExit()
        try require(capture.terminationStatus == 0, "empty capsule screenshot must succeed")
        print("compact results: PDF/folder types and mixed native rows rendered")
    }

    private static func checkBookmarks() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-bookmarks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let fixture = Data(#"{"roots":{"bookmark_bar":{"type":"folder","children":[{"type":"url","name":"DeepSeek 开放平台","url":"https://platform.deepseek.com/usage"}]}}}"#.utf8)
        let provider = ChromeBookmarksProvider(load: { ChromeBookmarkService.decode(fixture) })
        let denied = LauncherModel(app: app, searchProviders: [provider,
            WindowSearchProvider(source: .link, delay: .milliseconds(10), count: 1),
            WindowSearchProvider(source: .app, delay: .milliseconds(10), count: 1)],
            chromeBookmarkAccessAllowed: false)
        for text in ["deepseek", "https://deepseek.com", "bm deepseek"] {
            denied.query = text
            try await Task.sleep(for: .milliseconds(250))
            try require(!denied.isBookmarkScope, "ungranted bm must stay out of bookmark scope")
            try require(!denied.results.contains { [.link, .bookmark].contains($0.source) },
                        "ungranted link and bookmark features must not appear")
        }
        let staleEntry = SearchResult(source: .bookmark,
            target: TargetRef(kind: "bookmark-search", identifier: "deepseek"), title: "搜索书签", actions: [.open])
        denied.execute(staleEntry, action: .open)
        try require(!denied.isBookmarkScope, "stale bookmark entry cannot bypass authorization")
        let model = LauncherModel(app: app, searchProviders: [provider,
            WindowSearchProvider(source: .app, delay: .milliseconds(10), count: 1)])
        let controller = LauncherController(model: model)
        controller.show()
        (NSApp.windows.first { $0 is LauncherPanel && $0.isVisible } as? LauncherPanel)?.onBlur = {}
        defer { controller.hide() }
        model.query = "deepseek"
        try await Task.sleep(for: .milliseconds(350))
        guard let entry = model.results.first(where: { $0.target.kind == "bookmark-search" }) else {
            throw NSError(domain: "LauncherWindowRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: "bookmark entry must be available"])
        }
        model.execute(entry, action: entry.primaryAction)
        try await Task.sleep(for: .milliseconds(350))
        try require(model.isBookmarkScope && model.results.count == 1, "bookmark keyword must show matching result")
        print("Bookmark entry results", model.results.map(\.title))
        model.inputText = "deep"
        model.inputText = "deepseek"
        try await Task.sleep(for: .milliseconds(350))
        try require(model.results.count == 1 && !model.isSearching, "replacement bookmark queries must finish")
        if CommandLine.arguments.contains("--live-bookmarks") {
            let live = LauncherModel(app: app)
            for _ in 0..<40 {
                if live.chromeBookmarkAccessAllowed { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            live.query = "bm deepseek"
            try await Task.sleep(for: .milliseconds(500))
            try require(live.results.contains { $0.title == "DeepSeek 开放平台" }, "local Chrome DeepSeek bookmark must be delivered")
            live.query = "kimi"
            try await Task.sleep(for: .milliseconds(500))
            try require(live.results.contains { $0.source == .link }, "authorized known-site link search must be restored")
        }

    }

    private static func previewAccessories() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-preview-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let model = LauncherModel(app: app, searchProviders: [
            WindowSearchProvider(source: .app, delay: .milliseconds(10), count: 3),
            WindowSearchProvider(source: .file, delay: .milliseconds(250), count: 2),
            WindowSearchProvider(source: .shortcut, delay: .milliseconds(10), count: 2),
        ])
        let controller = LauncherController(model: model)
        defer { controller.hide() }
        if CommandLine.arguments.contains("--reveal-open") {
            let savedMouse = CGEvent(source: nil)?.location ?? .zero
            let mainBounds = CGDisplayBounds(CGMainDisplayID())
            CGWarpMouseCursorPosition(CGPoint(x: mainBounds.midX, y: mainBounds.midY))
            try await Task.sleep(for: .milliseconds(100))
            defer { CGWarpMouseCursorPosition(savedMouse) }
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? .zero
            let side = LauncherLayout.inputHeight
            let originX = visible.midX - LauncherLayout.toolbarWidth / 2
            let top = visible.maxY - visible.height * LauncherLayout.topInsetFraction
            let capture = Process()
            capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
            let screenHeight = screen?.frame.maxY ?? 0
            let region = "\(Int(originX - 20)),\(Int(screenHeight - top - 10)),\(Int(LauncherLayout.toolbarWidth + 60)),\(Int(side + 30))"
            let recording = "build/reveal-open-\(NSApp.appearance!.name.rawValue).mov"
            if FileManager.default.fileExists(atPath: recording) {
                try FileManager.default.removeItem(atPath: recording)
            }
            capture.arguments = ["-x", "-v", "-V", "4", "-R", region, recording]
            try capture.run()
            try await Task.sleep(for: .milliseconds(300))
            controller.show()
            (NSApp.windows.first { $0 is LauncherPanel && $0.isVisible } as? LauncherPanel)?.onBlur = {}
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .seconds(2.5))
            capture.waitUntilExit()
        } else if CommandLine.arguments.contains("--reveal-motion") {
            let savedMouse = CGEvent(source: nil)?.location ?? .zero
            let mainBounds = CGDisplayBounds(CGMainDisplayID())
            CGWarpMouseCursorPosition(CGPoint(x: mainBounds.midX, y: mainBounds.midY))
            try await Task.sleep(for: .milliseconds(100))
            defer { CGWarpMouseCursorPosition(savedMouse) }
            controller.show()
            guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) else {
                throw NSError(domain: "RevealMotion", code: 1)
            }
            (panel as? LauncherPanel)?.onBlur = {}
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .seconds(2))
            let capture = Process()
            capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
            let screenHeight = NSScreen.screens[0].frame.maxY
            let side = LauncherLayout.inputHeight
            let surfaceRight = panel.frame.maxX
            let region = "\(Int(surfaceRight - 2 * side - 20)),\(Int(screenHeight - panel.frame.maxY - 10)),\(Int(2 * side + 60)),\(Int(side + 30))"
            let recording = "build/reveal-motion-\(NSApp.appearance!.name.rawValue).mov"
            if FileManager.default.fileExists(atPath: recording) {
                try FileManager.default.removeItem(atPath: recording)
            }
            capture.arguments = ["-x", "-v", "-V", "4", "-R", region, recording]
            try capture.run()
            try await Task.sleep(for: .seconds(1))
            model.inputText = "Safari"
            try await Task.sleep(for: .seconds(0.8))
            model.inputText = ""
            try await Task.sleep(for: .seconds(0.8))
            capture.waitUntilExit()
        } else if CommandLine.arguments.contains("--motion") {
            try await Task.sleep(for: .seconds(1))
            for _ in 0..<3 {
                controller.show()
                (NSApp.windows.first { $0 is LauncherPanel && $0.isVisible } as? LauncherPanel)?.onBlur = {}
                NSApp.activate(ignoringOtherApps: true)
                try await Task.sleep(for: .seconds(2))
                model.inputText = "Safari"
                try await Task.sleep(for: .seconds(2))
                model.inputText = ""
                try await Task.sleep(for: .seconds(2))
                controller.hide()
                try await Task.sleep(for: .seconds(1))
            }
        } else {
            controller.show()
            (NSApp.windows.first { $0 is LauncherPanel && $0.isVisible } as? LauncherPanel)?.onBlur = {}
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .seconds(180))
        }
    }

    private static func checkAccessories() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-accessories-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let model = LauncherModel(app: app, searchProviders: [
            WindowSearchProvider(source: .app, delay: .milliseconds(10), count: 3),
            WindowSearchProvider(source: .file, delay: .milliseconds(250), count: 2),
            WindowSearchProvider(source: .shortcut, delay: .milliseconds(10), count: 2),
        ])
        let controller = LauncherController(model: model)
        controller.show()
        defer { controller.hide() }
        guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) as? LauncherPanel else {
            throw NSError(domain: "LauncherAccessories", code: 1)
        }
        try require(model.filter == .all, "launcher must default to root search")
        let dismissOnBlur = panel.onBlur
        // Keep the user's typing in their own app while checking this isolated window.
        panel.onBlur = {}
        NSApp.deactivate()
        try await Task.sleep(for: .milliseconds(80))
        try require(!NSApp.windows.contains { $0 is SurfacePanel && $0.isVisible },
                    "inline controls must not create separate visible surface windows")
        try require(abs(panel.frame.width - 640) <= 1 && abs(panel.frame.height - 52) <= 1,
                    "empty launcher must be a single 640 × 52 pt shell")
        try require(panel.hasShadow, "shell must retain its native shadow")
        let capture = Process()
        capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(panel.windowNumber), "build/launcher-search-icon-\(NSApp.appearance!.name.rawValue).png"]
        try capture.run()
        capture.waitUntilExit()
        try require(capture.terminationStatus == 0, "static search icon capture must succeed")
        let field = searchField(in: panel.contentView!)!
        let inputTop = panel.convertToScreen(field.convert(field.bounds, to: nil)).maxY
        let emptyFieldWidth = field.frame.width
        controller.show()
        try await Task.sleep(for: .milliseconds(100))
        try require(abs(panel.frame.width - LauncherLayout.toolbarWidth) <= 1,
                    "showing a visible launcher must preserve its full width")
        model.inputText = "Safari"
        try await Task.sleep(for: .milliseconds(300))
        try require(abs(field.frame.width - emptyFieldWidth) <= 1, "static search icon must keep field width stable while typing")
        try require(abs(panel.frame.width - LauncherLayout.toolbarWidth) <= 1, "typing must give the shell the full toolbar width")
        model.inputText = ""
        // A response of 0.18 is not a 180 ms completion deadline. Wait for the
        // existing spring to settle rather than sampling an arbitrary animation frame.
        for _ in 0..<60 {
            if abs(panel.frame.height - LauncherLayout.inputHeight) <= 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(abs(panel.frame.height - LauncherLayout.inputHeight) <= 1, "clearing root input must collapse")
        try require(abs(field.frame.width - emptyFieldWidth) <= 4, "clearing must restore the empty field width promptly: \(field.frame.width) vs \(emptyFieldWidth)")
        try await Task.sleep(for: .milliseconds(400))
        try require(abs(field.frame.width - emptyFieldWidth) <= 1, "clearing input must preserve the original field width")

        for filter in [LauncherFilter.applications, .files, .shortcuts, .quickLinks] {
            model.setFilter(filter)
            model.inputText = filter == .quickLinks ? "go" : "Safari"
            try await Task.sleep(for: .milliseconds(450))
            try require(!model.results.isEmpty && model.results.allSatisfy { filter.includes($0.source) }, "filter must return only requested category: \(filter)")
            let top = panel.convertToScreen(field.convert(field.bounds, to: nil)).maxY
            try require(abs(top - inputTop) <= 1, "filter/menu/result resizing must preserve field position")
        }
        model.setFilter(.files)
        model.inputText = "go query"
        try require(model.hasScope && model.commandInput == nil && model.inputText == "go query", "category scope must keep command-like filenames literal")
        model.inputText = "1+1"
        try require(model.calculation == nil, "files-only query must not display calculation")
        model.setFilter(.applications)
        model.inputText = "empty"
        try await Task.sleep(for: .milliseconds(450))
        try require(model.results.isEmpty, "empty filtered results must not fall back to AI")
        dismissOnBlur()
        try require(!controller.isVisible, "search must dismiss on blur")
        controller.show()
        panel.onEscape()
        try require(!controller.isVisible && model.filter == .all, "Escape must dismiss root search and reset session")
        for cycle in 0..<6 {
            controller.show()
            panel.onBlur = {}
            try await Task.sleep(for: .milliseconds(cycle.isMultiple(of: 2) ? 30 : 120))
            controller.show()
            try await Task.sleep(for: .milliseconds(650))
            try require(!NSApp.windows.contains { $0 is SurfacePanel && $0.isVisible },
                        "reopen cycle \(cycle) must not create accessory windows")
            try require(panel.frame.size == NSSize(width: 640, height: 52) && panel.hasShadow,
                        "reopening must preserve the single shell geometry and shadow")
            controller.hide()
        }
        print("search icon: category isolation, stable field geometry, blur/Escape and repeated show passed")
    }

    private static func checkCommandIcons() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-command-icons-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let model = LauncherModel(app: app, searchProviders: [])
        let controller = LauncherController(model: model)
        controller.show()
        guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) else {
            throw NSError(domain: "CommandIconsRegression", code: 1)
        }
        (panel as? LauncherPanel)?.onBlur = {}
        defer { controller.hide() }
        for command in app.keywords.commands {
            model.reset()
            panel.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            guard let field = commandSearchField(in: panel.contentView),
                  panel.makeFirstResponder(field), let editor = field.currentEditor() as? NSTextView else {
                throw NSError(domain: "CommandIconsRegression", code: 2)
            }
            for text in [command.keyword, " ", "SwiftUI"] {
                editor.insertText(text, replacementRange: editor.selectedRange())
                field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
            }
            try require(model.commandInput?.command.keyword == command.keyword && model.inputText == "SwiftUI",
                        "native field must consume \(command.keyword) on Space")
            try require(field.stringValue == "SwiftUI" && editor.string == "SwiftUI",
                        "the native editor must hide the command token")
            try require(model.results.count == 1 && model.keyword(for: model.results[0]) == command.keyword,
                        "scoped result must retain the matching command")
            try require(NSImage(named: CommandIcon.Brand(rawValue: command.keyword)!.asset) != nil,
                        "missing bundled logo for \(command.keyword)")
            try await Task.sleep(for: .milliseconds(200))
            panel.contentView?.layoutSubtreeIfNeeded()
            guard let view = panel.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                throw NSError(domain: "CommandIconsRegression", code: 3)
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let appearance = NSApp.appearance?.name.rawValue ?? "default"
            try bitmap.representation(using: .png, properties: [:])?.write(
                to: URL(filePath: "build/command-icon-\(appearance)-\(command.keyword).png"))
            model.inputText = ""
            try require(model.backspaceOnEmptyInput() && !model.hasScope,
                        "empty Backspace must leave \(command.keyword) mode")
        }
        model.query = "> pwd"
        try require(model.isTerminalScope && model.inputText == "pwd", "terminal scope must still work")
        try await Task.sleep(for: .milliseconds(200))
        panel.contentView?.layoutSubtreeIfNeeded()
        if let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(filePath:
                "build/command-icon-\(NSApp.appearance!.name.rawValue)-terminal.png"))
        }
        print("All \(app.keywords.commands.count) native command fields, bundled logos, scoped results and Backspace passed")
    }

    private static func commandSearchField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { commandSearchField(in: $0) }.first
    }

    private static func checkSystemAppNames() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-system-names-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let model = LauncherModel(app: app, searchProviders: [AppsProvider()])
        let controller = LauncherController(model: model)
        controller.show()
        let panel = NSApp.windows.first { $0 is LauncherPanel && $0.isVisible }
        (panel as? LauncherPanel)?.onBlur = {}
        defer { controller.hide() }
        for (query, file) in [("电话", "Phone.app"), ("备忘录", "Notes.app"),
                              ("计算器", "Calculator.app"), ("系统设置", "System Settings.app"),
                              ("音频MIDI设置", "Audio MIDI Setup.app"), ("活动监视器", "Activity Monitor.app"),
                              ("终端", "Terminal.app"), ("日历", "Calendar.app")] {
            model.query = query
            for _ in 0..<60 {
                if !model.isSearching { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            try require(!model.isSearching, "system app search must finish")
            try require(model.results.contains { $0.source == .app &&
                URL(fileURLWithPath: $0.target.identifier).lastPathComponent == file },
                "missing system app for \(query)")
            let result = model.results.first { URL(fileURLWithPath: $0.target.identifier).lastPathComponent == file }
            try require(result?.title == query, "expected Chinese title \(query), got \(result?.title ?? "nil")")
            print("\(query) => \(file), title=\(result!.title) passed")
            if query == "系统设置", let view = panel?.contentView,
               let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: URL(filePath: "build/launcher-system-names-" +
                        (NSApp.appearance?.name.rawValue ?? "default") + ".png"))
                }
            }
        }
    }

    private static func checkAliasResults() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-alias-results-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let appearance = NSApp.appearance?.name ?? .aqua
        let app = try AppModel(root: root)
        app.preferences.appearance = appearance == .darkAqua ? "dark" : "light"
        let target = "/System/Applications/Notes.app"
        app.preferences.aliases = [LauncherAlias(alias: "codex", kind: "app", target: target)]
        let model = LauncherModel(app: app, searchProviders: [CompactProvider(source: .app, results: [
            SearchResult(source: .app, target: TargetRef(kind: "app", identifier: target),
                         title: "Codex", actions: [.open, .revealInFinder]),
            SearchResult(source: .app, target: TargetRef(kind: "app", identifier: "/System/Applications/Safari.app"),
                         title: "Codex Helper", actions: [.open, .revealInFinder])
        ])])
        let controller = LauncherController(model: model)
        controller.show()
        guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) as? LauncherPanel,
              let content = panel.contentView else { throw NSError(domain: "AliasResults", code: 1) }
        panel.onBlur = {}
        defer { controller.hide() }
        model.query = "codex"
        try await Task.sleep(for: .milliseconds(700))
        try require(model.results.first?.target.kind == "launcher-alias", "alias must remain first: query=\(model.query), rows=\(model.results.map { $0.target.kind })")
        try require(model.results.filter { $0.target.identifier == target }.count == 1,
                    "alias target must appear only once after provider delivery")
        let commands = model.results.filter { $0.source == .keyword && $0.target.kind == "url" }
        let expectedURLs = app.keywords.commands.filter { $0.urlTemplate.contains("{query}") }
            .compactMap { $0.url(for: "codex")?.absoluteString }
        try require(!expectedURLs.isEmpty && commands.map(\.target.identifier) == expectedURLs,
                    "all query-capable search commands must remain available with the current query")
        try require(model.results.count == commands.count + 3 && model.results.last?.source == .askAI,
                    "alias, distinct app, search commands, and AI must remain available")
        guard let scroll = scrollView(in: content) else { throw NSError(domain: "AliasResults", code: 2) }
        let before = scroll.contentView.bounds.origin
        let oldPointer = CGEvent(source: nil)!.location
        defer { CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: oldPointer,
                        mouseButton: .left)?.post(tap: .cghidEventTap) }
        // Second section: one header and row, then its own header and row.
        let rect = panel.convertToScreen(scroll.convert(scroll.bounds, to: nil))
        let point = CGPoint(x: rect.midX,
                            y: NSScreen.screens[0].frame.maxY - rect.maxY + 2 * LauncherLayout.sectionHeaderHeight + 1.5 * LauncherLayout.rowHeight)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point,
                mouseButton: .left)?.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(300))
        try require(model.selection == 1, "moving pointer down must select the distinct app row")
        try require(scroll.contentView.bounds.origin == before, "hover must not scroll the row away")
        model.move(1)
        try await Task.sleep(for: .milliseconds(200))
        try require(model.results[model.selection].target.kind == "url" &&
                    model.results[model.selection].source == .keyword,
                    "keyboard must continue from hovered application into the default search commands")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(panel.windowNumber),
                             "build/launcher-alias-results-\(appearance.rawValue).png"]
        try capture.run()
        capture.waitUntilExit()
        try require(capture.terminationStatus == 0, "alias screenshot must succeed")
        model.move(model.results.count)
        try await Task.sleep(for: .milliseconds(300))
        try require(model.results[model.selection].source == .askAI && scroll.contentView.bounds.origin.y > before.y,
                    "keyboard must reveal results below the search commands")
        guard let document = scroll.documentView else { throw NSError(domain: "AliasResults", code: 3) }
        try require(abs(document.bounds.maxY - scroll.contentView.bounds.maxY) <= 1,
                    "last row must retain clearance above the floating action bar")
        print("alias results: search commands retained with current query, unique target, pointer/keyboard selection and bottom clearance passed")
    }

    private static func checkAliasRouting() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-alias-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let model = LauncherModel(app: app, searchProviders: [
            WindowSearchProvider(source: .app, delay: .milliseconds(10), count: 2),
            WindowSearchProvider(source: .shortcut, delay: .milliseconds(250), count: 1),
        ])
        let controller = LauncherController(model: model)
        controller.show()
        let panel = NSApp.windows.first { $0 is LauncherPanel && $0.isVisible }
        (panel as? LauncherPanel)?.onBlur = {}
        defer { controller.hide() }
        model.query = "GO"
        try require(model.results.first?.target.kind == "keyword-match" && model.selection == 0,
                    "exact case-insensitive keyword must be selected before provider batches")
        try require(model.keyword(for: model.results[0]) == "go", "exact match must retain its badge")
        try require(model.results[0].target.identifier == "https://www.google.com/search?q=",
                    "bare keyword must open its command without searching for the alias itself")
        for _ in 0..<60 {
            if !model.isSearching { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try require(!model.isSearching, "search providers must finish within three seconds")
        try require(model.results.prefix(2).map(\.source) == [.keyword, .shortcut] && model.selection == 0,
                    "late app and shortcut batches must leave the alias first and selected")
        if let view = panel?.contentView,
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                let file = "build/launcher-alias-" + (NSApp.appearance?.name.rawValue ?? "default") + ".png"
                try png.write(to: URL(filePath: file))
            }
        }
        for custom in [false, true] {
            app.preferences.commandKeywords["go"] = custom ? "google" : nil
            for command in app.keywords.commands {
                model.reset()
                try await Task.sleep(for: .milliseconds(80))
                guard let field = commandSearchField(in: panel?.contentView),
                      panel?.makeFirstResponder(field) == true,
                      let editor = field.currentEditor() as? NSTextView else {
                    throw NSError(domain: "CommandEntry", code: 1)
                }
                editor.insertText(command.keyword.uppercased(), replacementRange: editor.selectedRange())
                field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
                try require(model.results.first?.target.kind == "keyword-match" && model.results.first?.primaryAction == .open,
                            "bare trigger must offer command entry: \(command.keyword)")
                try await Task.sleep(for: .milliseconds(80))
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                            windowNumber: panel!.windowNumber, context: nil, characters: "\r",
                                            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
                panel!.sendEvent(event)
                try await Task.sleep(for: .milliseconds(80))
                try require(field.stringValue.isEmpty && editor.string.isEmpty, "native editor must consume the trigger")
                try require(model.commandInput?.command.keyword == command.keyword && model.inputText.isEmpty,
                            "Return must enter command with empty input: \(command.keyword)")
                try require(panel?.isVisible == true, "entering command must keep launcher visible")
                model.inputText = "SwiftUI"
                try require(model.results.first?.primaryAction == command.url(for: "SwiftUI").map { .openURL($0) },
                            "entered command must offer its query URL")
                model.inputText = ""
                try require(model.backspaceOnEmptyInput() && !model.hasScope, "Backspace must leave entered command")
                model.query = command.keyword + " SwiftUI"
                try require(model.commandInput?.command.keyword == command.keyword && model.inputText == "SwiftUI",
                            "Space must retain existing command entry")
            }
        }
        app.preferences.commandKeywords["go"] = nil
        if CommandLine.arguments.contains("--command-entry") {
            print("Command entry: all website commands, native Return, custom trigger, case folding, query URLs, Space and Backspace passed")
            return
        }
        model.query = "Safari"
        for _ in 0..<60 {
            if !model.isSearching { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try require(!model.isSearching, "search providers must finish within three seconds")
        try require(model.results.first?.source == .shortcut && model.selection == 0,
                    "shortcut results must precede apps")
        model.query = "go SwiftUI"
        try require(model.commandInput != nil && model.results.count == 1 &&
                    model.results[0].target.identifier.contains("q=SwiftUI"),
                    "space must still enter the explicit keyword query mode")
        model.query = "gopher"
        for _ in 0..<60 {
            if !model.isSearching { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try require(!model.isSearching, "search providers must finish within three seconds")
        try require(!model.results.contains { $0.target.kind == "keyword-match" },
                    "partial keywords must not count as exact aliases")
        // Use a valid custom alias; `sc` is reserved by the shortcuts search command.
        app.preferences.aliases = [LauncherAlias(alias: "daily", kind: "shortcut", target: "Daily")]
        model.query = "DAILY"
        try await Task.sleep(for: .milliseconds(500))
        try require(model.results.first?.target.kind == "launcher-alias" &&
                    model.results.first?.primaryAction == .runShortcut(name: "Daily"),
                    "configured shortcut aliases must survive late search batches and remain selected")
        let restored = try AppModel(root: root)
        try require(restored.preferences.aliases == app.preferences.aliases,
                    "aliases must survive app reload")
        app.preferences.appearance = "dark"
        app.preferences.hotKeyLabel = "⌃⌥ Space"
        let reloaded = try AppModel(root: root)
        try require(reloaded.preferences.appearance == "dark" && reloaded.preferences.hotKeyLabel == "⌃⌥ Space",
                    "appearance and hotkey preferences must survive reload")
        NSApp.appearance = NSAppearance(named: .aqua)
        let credentials = ModelCredentialSession()
        let fakeKeychain = Keychain(service: "app.asky.nonexistent-regression")
        await credentials.remember("synthetic", account: "model")
        for _ in 0..<2 {
            let value = try await credentials.read(account: "model", keychain: fakeKeychain,
                started: { fatalError("cached credentials must not request authorization") }, finished: {})
            try require(value == "synthetic", "capability checks and runtime must share session credentials")
        }
        await credentials.remember("replacement", account: "model")
        let replacement = try await credentials.read(account: "model", keychain: fakeKeychain,
            started: { fatalError("a freshly saved key must not request authorization") }, finished: {})
        try require(replacement == "replacement", "saving a new key must update the session credential")
        print("Exact alias, case folding, late batches, shortcut priority and spaced command passed")
    }

    private static func checkAIRouting() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-routing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let model = LauncherModel(app: app, searchProviders: [
            WindowSearchProvider(source: .app, delay: .milliseconds(300), count: 8,
                                 matchingQueries: ["Safari", "kimi"]),
            WindowSearchProvider(source: .file, delay: .milliseconds(10), count: 0),
            WindowSearchProvider(source: .bookmark, delay: .milliseconds(10), count: 4),
        ])
        var submitted: [String] = []
        model.onAskAI = { submitted.append($0) }
        let controller = LauncherController(model: model)
        controller.show()
        if let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) as? LauncherPanel {
            panel.onBlur = {}
            // Keep the routing test independent of typing in the user's app.
            panel.orderOut(nil)
        }
        defer { controller.hide() }
        let prompt = "帮我梳理一下日程"
        model.query = "Safari"
        try require(model.isSearching && model.results.isEmpty,
                    "debounce must not publish a premature AI-only fallback")
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(10))
            try require(model.results.isEmpty,
                        "empty fast sources must not show AI while app search is pending")
        }
        try await Task.sleep(for: .milliseconds(200))
        try require(model.results.first?.source == .app && model.results.last?.source == .askAI,
                    "local matches and AI action must appear together")
        model.query = "Saf"
        try require(model.results.first?.source == .app,
                    "matching concrete targets must remain visible during replacement search")
        model.query = "empty"
        try require(model.results.isEmpty && model.isSearching,
                    "an unrelated replacement must wait for its own results")
        model.submit(.executeSelection)
        try require(submitted.isEmpty, "Return during pending search must not submit premature AI")
        for _ in 0..<60 {
            if !model.isSearching { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try require(model.results.count == 1 && model.results.first?.source == .askAI && !model.isSearching,
                    "AI-only fallback must appear after all sources confirm no match: searching=\(model.isSearching), sources=\(model.results.map(\.source))")
        model.query = "Safari"
        try await Task.sleep(for: .milliseconds(150))
        model.query = prompt
        try require(submitted.isEmpty, "typing must not submit AI")
        try require(model.results.count == 1 && model.results[0].source == .askAI,
                    "conversation must show only the AI action, with no bookmark fallback")
        try require(model.selection == 0 && !model.isSearching, "AI must be the default selection")
        try require(model.results[0].subtitle.isEmpty, "AI row must have no shortcut subtitle")
        try await Task.sleep(for: .milliseconds(450))
        try require(model.results.count == 1, "cancelled local batches must not replace the AI selection")
        if let panel = NSApp.windows.first(where: { $0 is LauncherPanel }) as? LauncherPanel {
            try require(abs(panel.frame.height - 103) <= 1,
                        "single AI category must omit the 30 pt header from native window height")
        }
        model.submit(.executeSelection)
        try require(submitted == [prompt], "ordinary Return must hand the prompt to AI once")
        for text in ["你是谁啊", "你好", "随便聊聊", "我今天有点累", "明天有什么安排"] {
            model.query = text
            try require(model.isSearching && model.results.isEmpty,
                        "plain text must wait for local search before defaulting to AI")
            try await Task.sleep(for: .milliseconds(450))
            try require(model.results.count == 1 && model.results.first?.source == .askAI && model.selection == 0,
                        "empty local batches must leave only AI, not generic bookmark or Google actions")
            try require(submitted.last != text, "typing plain text must not send")
            model.submit(.executeSelection)
            try require(submitted.last == text, "Return must submit unmatched plain text: expected \(text), got \(submitted.last ?? "nil")")
        }
        model.query = "kimi"
        try await Task.sleep(for: .milliseconds(450))
        try require(model.results.first?.source == .app, "bare names must keep local search first")
        try require(model.results.filter { $0.source == .askAI }.count == 1, "local search retains one AI action")
        model.query = "go " + prompt
        try require(model.commandInput != nil && model.results.first?.source == .keyword,
                    "explicit keyword must keep its command result")
        print("Deferred AI fallback, mixed-speed sources, retained matches, Return handoff, cancelled batches and explicit scopes passed")
    }

    private static func searchField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.delegate is LauncherSearchField.Coordinator { return field }
        return view.subviews.lazy.compactMap { searchField(in: $0) }.first
    }

    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }

    private static func checkScrolling(panel: LauncherPanel, content: NSView,
                                       model: LauncherModel, editor: NSTextView) async throws {
        guard let scroll = scrollView(in: content) else {
            throw NSError(domain: "LauncherWindowRegression", code: 3)
        }
        let listRect = scroll.convert(scroll.bounds, to: nil)
        let inputPoint = NSPoint(x: listRect.midX, y: listRect.maxY + 32)
        let rowPoint = NSPoint(x: listRect.midX, y: listRect.midY)
        let selection = model.selection
        let text = editor.string
        for units in [CGScrollEventUnit.line, .pixel] {
            for point in [rowPoint, inputPoint] {
                let before = scroll.contentView.bounds.origin.y
                let cg = CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 1,
                                 wheel1: units == .line ? -4 : -80, wheel2: 0, wheel3: 0)!
                let event = NSEvent(cgEvent: cg)!
                try require(panel.routeScrollWheel(event, at: point), "shell must route wheel events")
                try await Task.sleep(for: .milliseconds(200))
                let after = scroll.contentView.bounds.origin.y
                try require(after > before, "mouse/precise scrolling must move actual results")
                let reverse = CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 1,
                                      wheel1: units == .line ? 4 : 80, wheel2: 0, wheel3: 0)!
                panel.routeScrollWheel(NSEvent(cgEvent: reverse)!, at: point)
                try await Task.sleep(for: .milliseconds(200))
                try require(scroll.contentView.bounds.origin.y < after, "reverse scrolling must work")
            }
        }
        let event = NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                           wheelCount: 1, wheel1: -4, wheel2: 0, wheel3: 0)!)!
        try require(!panel.routeScrollWheel(event, at: NSPoint(x: -1, y: -1)), "points outside the shell must not intercept scrolling")
        try require(model.selection == selection && editor.string == text && panel.firstResponder === editor,
                    "scrolling must preserve selection, text and input focus: selection \(model.selection)/\(selection), text \(editor.string == text), responder \(String(describing: panel.firstResponder)), key \(panel.isKeyWindow)")
        let target = model.results.lastIndex { $0.source == .file }!
        let steps = target - selection
        func pressArrow(_ keyCode: UInt16 = 125) async throws {
            let character = keyCode == 125 ? "\u{F701}" : "\u{F700}"
            let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                context: nil, characters: character, charactersIgnoringModifiers: character,
                isARepeat: false, keyCode: keyCode)!
            // Dispatch through NSApplication so currentEvent is this key, not
            // the wheel event left by the preceding scroll checks.
            NSApp.postEvent(down, atStart: false)
            try await Task.sleep(for: .milliseconds(20))
        }
        for _ in 0..<steps {
            try await pressArrow()
        }
        try await Task.sleep(for: .milliseconds(200))
        try require(model.selection == target, "keyboard navigation must remain available")
        try require(scroll.contentView.bounds.origin.y > 0, "keyboard must reveal an offscreen selection")
        for _ in 0..<(model.results.count + 3) {
            try await pressArrow()
        }
        try await Task.sleep(for: .milliseconds(200))
        try require(model.selection == model.results.count - 1, "repeated Down must stop at the last result")
        guard let document = scroll.documentView else {
            throw NSError(domain: "LauncherWindowRegression", code: 3)
        }
        let remaining = document.bounds.maxY - scroll.contentView.bounds.maxY
        try require(abs(remaining) <= 1,
                    "last selection must reveal the full document including bottom clearance, remaining=\(remaining)")
        let bottom = scroll.contentView.bounds.origin.y
        try await pressArrow()
        try await Task.sleep(for: .milliseconds(200))
        try require(scroll.contentView.bounds.origin.y == bottom, "Down at the last result must not scroll back to the top")
        try await pressArrow(126)
        try require(model.selection == model.results.count - 2, "Up must move away from the last result")
        try await Task.sleep(for: .milliseconds(200))
        let beforeLast = scroll.contentView.bounds.origin.y
        try await pressArrow()
        try await Task.sleep(for: .milliseconds(200))
        let lastReveal = scroll.contentView.bounds.origin.y - beforeLast
        try require(lastReveal >= -1 && lastReveal <= LauncherLayout.rowHeight + LauncherLayout.listBottomPadding + 1,
                    "returning to the final row must use minimal reveal, delta=\(lastReveal)")
        try require(abs(document.bounds.maxY - scroll.contentView.bounds.maxY) <= 1,
                    "returning to the final row must preserve bottom clearance")
        for _ in 0..<(model.results.count + 3) {
            try await pressArrow(126)
        }
        try await Task.sleep(for: .milliseconds(200))
        try require(model.selection == 0, "repeated Up must stop at the first result")
        let top = scroll.contentView.bounds.origin.y
        try await pressArrow(126)
        try await Task.sleep(for: .milliseconds(200))
        try require(scroll.contentView.bounds.origin.y == top, "Up at the first result must not scroll back to the bottom")
        try await pressArrow()
        try require(model.selection == 1 && panel.firstResponder === editor,
                    "Down must move away from the first result while preserving input focus")
        model.selection = selection
        try await Task.sleep(for: .milliseconds(200))
        print("wheel/precise forward/reverse over rows/input, focus and bounded keyboard navigation checks passed")
    }

    private static func runScrollBackground() {
        let args = CommandLine.arguments
        let report = URL(fileURLWithPath: args[2])
        let frame = NSRect(x: Double(args[3])!, y: Double(args[4])!,
                           width: Double(args[5])!, height: Double(args[6])!)
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: frame.size))
        let document = NSTextView(frame: NSRect(x: 0, y: 0, width: frame.width, height: 5000))
        document.string = String(repeating: "Synthetic background scroll target\n", count: 200)
        scroll.documentView = document
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            MainActor.assumeIsolated {
                try? String(describing: scroll.contentView.bounds.origin.y).write(to: report, atomically: true, encoding: .utf8)
            }
        }
        withExtendedLifetime((window, timer)) { NSApp.run() }
    }

    private static func checkSystemDelivery(controller: LauncherController, panel: LauncherPanel, content: NSView) async throws {
        try require(CGPreflightPostEventAccess(), "system scroll test requires existing event-post access")
        let report = FileManager.default.temporaryDirectory.appending(path: "Asky-scroll-\(UUID())")
        let background = Process()
        background.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        background.arguments = ["--scroll-background", report.path, String(describing: panel.frame.minX),
                                String(describing: panel.frame.minY), String(describing: panel.frame.width), String(describing: panel.frame.height)]
        background.terminationHandler = { _ in try? FileManager.default.removeItem(at: report) }
        try background.run()
        defer { background.terminate() }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: report.path) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(200))
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
        let foreground = scrollView(in: content)!
        foreground.contentView.scroll(to: NSPoint(x: 0, y: 200))
        foreground.reflectScrolledClipView(foreground.contentView)
        let oldPointer = CGEvent(source: nil)!.location
        defer { CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: oldPointer,
                        mouseButton: .left)?.post(tap: .cghidEventTap) }
        let rect = panel.convertToScreen(foreground.convert(foreground.bounds, to: nil))
        let points = [NSPoint(x: rect.midX, y: rect.midY),
                      NSPoint(x: rect.midX, y: rect.maxY + 32),
                      NSPoint(x: rect.minX + 3, y: rect.midY)]
        for units in [CGScrollEventUnit.line, .pixel] {
            for location in points {
                foreground.contentView.scroll(to: NSPoint(x: 0, y: 200))
                foreground.reflectScrolledClipView(foreground.contentView)
                let point = CGPoint(x: location.x, y: NSScreen.screens[0].frame.maxY - location.y)
                CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point,
                        mouseButton: .left)?.post(tap: .cghidEventTap)
                try await Task.sleep(for: .milliseconds(200))
                print("hit point=\(location) panelFrame=\(panel.frame) key=\(panel.isKeyWindow) active=\(NSApp.isActive)")
                let backBefore = try String(contentsOf: report, encoding: .utf8)
                let frontBefore = foreground.contentView.bounds.origin.y
                let event = CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 1,
                                    wheel1: units == .line ? -5 : -80, wheel2: 0, wheel3: 0)!
                event.location = point
                event.post(tap: .cghidEventTap)
                try await Task.sleep(for: .milliseconds(700))
                let backAfter = try String(contentsOf: report, encoding: .utf8)
                print("system delivery front=\(frontBefore)->\(foreground.contentView.bounds.origin.y) background=\(backBefore)->\(backAfter)")
                try require(foreground.contentView.bounds.origin.y != frontBefore, "system wheel must reach launcher")
                try require(backAfter == backBefore, "background app must not scroll under launcher")
            }
        }
    }

    private static func checkResultMotion() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-result-motion-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let model = LauncherModel(app: app, searchProviders: [
            WindowSearchProvider(source: .app, delay: .milliseconds(10), count: 8),
            WindowSearchProvider(source: .file, delay: .milliseconds(100), count: 4),
        ])
        let controller = LauncherController(model: model)
        controller.show()
        defer { controller.hide() }
        guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) as? LauncherPanel,
              let content = panel.contentView, let field = searchField(in: content) else {
            throw NSError(domain: "LauncherWindowRegression", code: 2)
        }
        panel.onBlur = {}
        panel.makeFirstResponder(field)
        try await Task.sleep(for: .milliseconds(50))
        let editor = field.currentEditor()
        let inputTop = panel.convertToScreen(field.convert(field.bounds, to: nil)).maxY
        let windowTop = panel.frame.maxY
        var intermediateHeights: [CGFloat] = []
        var maxDrift: CGFloat = 0
        var maxWindowDrift: CGFloat = 0
        model.inputText = "s"
        for _ in 0..<65 {
            try await Task.sleep(for: .milliseconds(8))
            let height = panel.frame.height
            if height > 53 && height < 432 { intermediateHeights.append(height) }
            let top = panel.convertToScreen(field.convert(field.bounds, to: nil)).maxY
            if abs(top - inputTop) > maxDrift {
                print("motion drift: input=\(top - inputTop) window=\(panel.frame.maxY - windowTop) frame=\(panel.frame) field=\(field.frame) content=\(content.frame)")
            }
            maxDrift = max(maxDrift, abs(top - inputTop))
            maxWindowDrift = max(maxWindowDrift, abs(panel.frame.maxY - windowTop))
        }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            try require(Set(intermediateHeights.map { Int($0) }).count >= 4,
                        "result reveal must visit multiple intermediate window heights")
        }
        try require(abs(panel.frame.height - 433) <= 1 && maxDrift < 0.01 && maxWindowDrift < 0.01,
                    "reveal must settle with stationary input/window: height=\(panel.frame.height), inputDrift=\(maxDrift), windowDrift=\(maxWindowDrift)")
        model.selection = 0
        model.move(1)
        try require(model.selection == 1 && field.currentEditor() === editor,
                    "keyboard selection must stay immediate and preserve the editor: selection=\(model.selection), editor=\(field.currentEditor() === editor), count=\(model.results.count)")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(panel.windowNumber),
                             "build/launcher-result-motion-\(NSApp.appearance!.name.rawValue).png"]
        try capture.run()
        capture.waitUntilExit()
        try require(capture.terminationStatus == 0, "result motion screenshot must succeed")
        model.inputText = ""
        for _ in 0..<65 {
            try await Task.sleep(for: .milliseconds(8))
            let top = panel.convertToScreen(field.convert(field.bounds, to: nil)).maxY
            try require(abs(top - inputTop) < 0.01 && abs(panel.frame.maxY - windowTop) < 0.01,
                        "clearing must preserve the input and window anchor")
        }
        try require(abs(panel.frame.height - LauncherLayout.inputHeight) <= 1 && field.currentEditor() === editor,
                    "clear must collapse and preserve the editor: height=\(panel.frame.height) editor=\(field.currentEditor() === editor) key=\(panel.isKeyWindow)")
        model.inputText = "s"
        try await Task.sleep(for: .milliseconds(500))
        model.inputText = ""
        try await Task.sleep(for: .milliseconds(60))
        model.inputText = "sa"
        try await Task.sleep(for: .milliseconds(500))
        try require(abs(panel.frame.height - 433) <= 1,
                    "typing again must retain expanded height")
        model.inputText = ""
        try await Task.sleep(for: .milliseconds(500))
        model.inputText = "sa"
        try await Task.sleep(for: .milliseconds(60))
        model.inputText = ""
        try await Task.sleep(for: .milliseconds(400))
        try require(abs(panel.frame.height - LauncherLayout.inputHeight) <= 1, "clear must collapse even during expansion")
        model.inputText = "s"
        try await Task.sleep(for: .milliseconds(60))
        controller.hide()
        controller.show()
        panel.onBlur = {}
        try await Task.sleep(for: .milliseconds(400))
        try require(abs(panel.frame.height - 52) <= 1, "reopen must not resume a stale reveal")
        print("result motion: intermediateSamples=\(intermediateHeights.count), inputDrift=\(maxDrift), keyboard/clear/fixed-height/interruption/reopen passed")
    }

    private static func checkCommandTransition() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-command-transition-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let model = LauncherModel(app: app, searchProviders: [])
        let controller = LauncherController(model: model)
        NSApp.activate(ignoringOtherApps: true)
        controller.show()
        defer { controller.hide() }
        guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) as? LauncherPanel else {
            throw NSError(domain: "LauncherWindowRegression", code: 2)
        }
        panel.onBlur = {}
        model.inputText = "sw"
        try await Task.sleep(for: .milliseconds(500))
        let commandHeight = panel.frame.height
        try require(model.results.first?.target.identifier == "windows", "sw must select the window command")
        model.submit(.executeSelection)
        try require(model.filter == .windows && model.isSearching && model.results.isEmpty,
                    "Return must enter the window search loading state")
        // Window enumeration starts after 100 ms; sample the real panel during
        // that empty interval to catch a collapse before results arrive.
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(8))
            try require(abs(panel.frame.height - commandHeight) <= 1,
                        "entering sw must retain list height while loading: before=\(commandHeight), now=\(panel.frame.height)")
        }
        try await Task.sleep(for: .milliseconds(500))
        model.reset()
        try await Task.sleep(for: .milliseconds(500))
        try require(abs(panel.frame.height - LauncherLayout.inputHeight) <= 1, "reset to empty root must collapse")
        print("PASS: sw retains expanded height; reset to empty root collapses")
    }

    private static func checkFixedExpanded() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-fixed-expanded-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let model = LauncherModel(app: app, searchProviders: [WindowSearchProvider(source: .app, delay: .milliseconds(100), count: 8)])
        let controller = LauncherController(model: model)
        NSApp.activate(ignoringOtherApps: true)
        controller.show()
        defer { controller.hide() }
        guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) as? LauncherPanel,
              let content = panel.contentView, let field = searchField(in: content) else {
            throw NSError(domain: "LauncherWindowRegression", code: 2)
        }
        panel.onBlur = {}
        panel.makeFirstResponder(field)
        try await Task.sleep(for: .milliseconds(100))
        try require(panel.frame.height == LauncherLayout.inputHeight, "new presentation must start compact")
        model.inputText = "help me test"
        try await Task.sleep(for: .milliseconds(650))
        try require(model.results.count == 1 && panel.frame.height == LauncherLayout.expandedHeight,
                    "a single result must open the full expanded height: height=\(panel.frame.height), results=\(model.results.count), query=\(model.query)")
        let expanded = panel.frame.height
        let top = panel.frame.maxY
        let inputTop = panel.convertToScreen(field.convert(field.bounds, to: nil)).maxY
        let editor = field.currentEditor()
        for query in ["many", "help me test", "1+2", "sw"] {
            model.inputText = query
            for _ in 0..<35 {
                try await Task.sleep(for: .milliseconds(16))
                try require(panel.frame.height == expanded && panel.frame.maxY == top,
                            "result counts and cards must retain expanded geometry")
                try require(abs(panel.convertToScreen(field.convert(field.bounds, to: nil)).maxY - inputTop) < 0.01 &&
                            field.currentEditor() === editor, "content changes must preserve editor and input position")
            }
        }
        model.submit(.executeSelection)
        try require(model.filter == .windows, "Return must enter window mode")
        for _ in 0..<35 {
            try await Task.sleep(for: .milliseconds(16))
            try require(panel.frame.height == expanded, "sw loading and completion must keep expanded height")
        }
        model.inputText = ""
        try await Task.sleep(for: .milliseconds(400))
        try require(panel.frame.height == expanded, "empty query inside sw must stay expanded")
        model.leaveCommand()
        try await Task.sleep(for: .milliseconds(500))
        try require(panel.frame.height == LauncherLayout.inputHeight,
                    "leaving empty sw for empty root must collapse")
        model.inputText = "help me test"
        try await Task.sleep(for: .milliseconds(500))
        model.inputText = "   "
        try await Task.sleep(for: .milliseconds(500))
        try require(panel.frame.height == LauncherLayout.inputHeight && field.currentEditor() === editor,
                    "whitespace-only root must collapse and retain the editor")
        model.inputText = "help me test"
        try await Task.sleep(for: .milliseconds(400))
        let capture = Process()
        capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(panel.windowNumber),
                             "build/launcher-fixed-expanded-\(NSApp.appearance!.name.rawValue).png"]
        try capture.run(); capture.waitUntilExit()
        try require(capture.terminationStatus == 0, "fixed expanded screenshot must succeed")
        controller.hide()
        controller.show()
        panel.onBlur = {}
        try await Task.sleep(for: .milliseconds(400))
        try require(panel.frame.height == LauncherLayout.inputHeight, "hide and reopen must reset to compact")
        print("PASS: fixed expanded height, single/many/calculation/sw, empty-root collapse, stable editor, compact reopen")
    }

    private static func checkShellLifecycle() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-shell-lifecycle-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let model = LauncherModel(app: app, searchProviders: [
            WindowSearchProvider(source: .app, delay: .milliseconds(20), count: 8),
            WindowSearchProvider(source: .file, delay: .milliseconds(100), count: 4)
        ])
        let controller = LauncherController(model: model)
        controller.show()
        defer { controller.hide() }
        guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) as? LauncherPanel,
              let surface = panel.contentView, let field = searchField(in: surface) else {
            throw NSError(domain: "LauncherWindowRegression", code: 2)
        }
        panel.onBlur = {}
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        guard let retainedHost = descendants(surface).first(where: {
            String(describing: type(of: $0)).contains("NSHostingView<AnyView>")
        }) else { throw NSError(domain: "LauncherWindowRegression", code: 3) }
        func residentKB() throws -> Int {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(filePath: "/bin/ps")
            process.arguments = ["-o", "rss=", "-p", String(ProcessInfo.processInfo.processIdentifier)]
            process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let value = Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
            else { throw NSError(domain: "LauncherWindowRegression", code: 4) }
            return value
        }
        var memorySamples: [Int] = []
        let baselineWindowCount = NSApp.windows.count
        var releasedScrollViews = 0
        for iteration in 0..<100 {
            controller.show()
            try require(panel.contentView === surface && searchField(in: surface) === field,
                        "shell and search input identities must remain stable")
            try require(descendants(surface).contains { $0 === retainedHost }, "hosting identity must remain stable")
            try require(field.currentEditor() != nil, "reopen must synchronously restore input focus")
            try require(panel.frame.height == LauncherLayout.inputHeight && model.inputText.isEmpty,
                        "each session starts with compact, empty input")
            if iteration % 10 == 0 {
                model.inputText = "s"
                for _ in 0..<100 {
                    if !model.results.isEmpty && panel.frame.height > LauncherLayout.inputHeight { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                try require(!model.results.isEmpty && panel.frame.height > LauncherLayout.inputHeight,
                            "fresh result content must mount and expand: iteration=\(iteration) results=\(model.results.count) height=\(panel.frame.height) query=\(model.inputText)")
                weak var scroll = descendants(surface).first { $0 is NSScrollView }
                try require(scroll != nil, "expanded results must own a scroll view")
                controller.hide()
                try await Task.sleep(for: .milliseconds(50))
                try require(scroll == nil, "hidden results must release their native scroll view")
                releasedScrollViews += 1
                memorySamples.append(try residentKB())
            } else {
                // Close while a provider and the resize callback may still be in flight.
                model.inputText = "s"
                controller.hide()
                try await Task.sleep(for: .milliseconds(3))
            }
            try require(!panel.isVisible && panel.contentView === surface && model.results.isEmpty,
                        "hidden shell must retain no results")
            try require(field.currentEditor() == nil, "hidden input must not retain active editing")
            try require(!descendants(surface).contains { $0 is NSScrollView }, "hidden result content must unmount")
            try require(panel.frame.height == LauncherLayout.inputHeight, "stale layouts must not expand hidden shell")
            try require((panel.childWindows ?? []).isEmpty, "hidden shell must remove child windows")
        }
        try await Task.sleep(for: .milliseconds(150))
        try require(model.results.isEmpty && !panel.isVisible, "late provider results cannot revive a closed session")
        try require(NSApp.windows.count <= baselineWindowCount + 2, "repeated show must not accumulate auxiliary windows")
        // Different screen sizes update the stable canvas, without replacing the field.
        for screen in NSScreen.screens {
            controller.show(on: screen)
            try require(panel.screen === screen && searchField(in: surface) === field,
                        "cross-screen show must reuse input and target the requested screen")
            controller.hide()
        }
        // Losing/reopening input must not commit an old IME composition into the next session.
        controller.show()
        if let editor = field.currentEditor() as? NSTextView {
            editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
            try require(editor.hasMarkedText(), "test must establish marked text")
            controller.hide()
            controller.show()
            try require((field.currentEditor() as? NSTextView)?.hasMarkedText() == false && field.stringValue.isEmpty,
                        "new session must clear old IME composition")
        }
        controller.hide()
        // A separate controller exercises actual first construction again.
        let cold = LauncherController(model: LauncherModel(app: app, searchProviders: []))
        cold.show()
        guard let coldPanel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }),
              let coldSurface = coldPanel.contentView, let coldField = searchField(in: coldSurface) else {
            throw NSError(domain: "LauncherWindowRegression", code: 2)
        }
        try require(coldSurface !== surface && coldField !== field, "new controller must create a separate shell")
        cold.hide()
        print("shell lifecycle RSS KiB after each 10-session group: \(memorySamples)")
        print("shell lifecycle: 100 sessions, \(releasedScrollViews) released scroll views, stable shell/input, cancellation, screens and marked text passed")
    }

    private static func checkFirstPresentation() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-first-presentation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let model = LauncherModel(app: app, searchProviders: [])
        let controller = LauncherController(model: model)
        defer { controller.hide() }
        var retainedSurface: NSView?
        var retainedField: NSTextField?
        for iteration in 0..<10 {
            controller.show()
            guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) as? LauncherPanel,
                  let surface = panel.contentView, let field = searchField(in: surface) else {
                throw NSError(domain: "LauncherWindowRegression", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "first presentation must already contain the search field"])
            }
            panel.onBlur = {}
            if let retainedSurface, let retainedField {
                try require(surface === retainedSurface && field === retainedField,
                            "reopen must reuse the original glass and input field")
            } else {
                retainedSurface = surface
                retainedField = field
            }
            try require(field.currentEditor() != nil, "editor must be ready before show returns")
            try require(panel.animationBehavior == .none, "shell presentation must not use an AppKit window transition")
            try require(panel.frame.width == LauncherLayout.toolbarWidth && panel.frame.height == LauncherLayout.inputHeight,
                        "first presentation must already have final shell geometry")
            for view in [surface, surface.superview].compactMap({ $0 }) {
                try require(view.layer?.masksToBounds == true && view.layer?.cornerRadius == LauncherLayout.shellCornerRadius,
                            "content and frame must be clipped before first presentation")
            }
            try await Task.sleep(for: .milliseconds(80))
            try require(field.currentEditor() != nil, "search must acquire its editor after presentation")
            if iteration == 0 {
                let capture = Process()
                capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-l", String(panel.windowNumber),
                                     "build/launcher-first-presentation-\(NSApp.appearance!.name.rawValue).png"]
                try capture.run()
                capture.waitUntilExit()
                let imageURL = URL(filePath: capture.arguments!.last!)
                try require(capture.terminationStatus == 0 && FileManager.default.fileExists(atPath: imageURL.path),
                            "first presentation screenshot must actually exist")
            }
            controller.show()
            try require(panel.isVisible, "a repeated show request must keep the shell visible")
            controller.hide()
            try require(!panel.isVisible && panel.contentView === surface && model.results.isEmpty,
                        "hide must keep the shell while releasing result payloads")
            try require(field.currentEditor() == nil, "hidden input must end field editing")
        }
        print("first presentation: one cold shell, 9 reused shells, initial geometry/clipping and synchronous editor passed")
    }

    private static func checkWindow() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-window-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let model = LauncherModel(app: app, searchProviders: [
            WindowSearchProvider(source: .app, delay: .milliseconds(10), count: 8),
            WindowSearchProvider(source: .file, delay: .milliseconds(300), count: 4),
        ])
        let controller = LauncherController(model: model)
        model.inputText = "s"
        controller.show()
        defer { controller.hide() }
        guard let panel = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible }) as? LauncherPanel else {
            throw NSError(domain: "LauncherWindowRegression", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "launcher panel not available"])
        }
        // This standalone accessory process is not the user's foreground app.
        // A desktop focus change must not dismiss the geometry test halfway through.
        panel.onBlur = {}
        try await Task.sleep(for: .milliseconds(50))
        guard let content = panel.contentView, let field = searchField(in: content) else {
            throw NSError(domain: "LauncherWindowRegression", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "launcher field not available"])
        }
        panel.makeFirstResponder(field)
        guard let editor = field.currentEditor() as? NSTextView else {
            throw NSError(domain: "LauncherWindowRegression", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "launcher editor not available"])
        }
        let initialTop = panel.convertToScreen(field.convert(field.bounds, to: nil)).maxY
        var initialInputDrift: CGFloat = 0
        for _ in 0..<70 {
            try await Task.sleep(for: .milliseconds(5))
            let top = panel.convertToScreen(field.convert(field.bounds, to: nil)).maxY
            initialInputDrift = max(initialInputDrift, abs(top - initialTop))
        }
        print("initialDeliverySamples=70 inputDrift=\(initialInputDrift)")
        try require(initialInputDrift <= 1, "first asynchronous results must preserve input position")
        try require(model.results.contains { $0.source == .app }, "initial search must finish")
        let baseline = panel.frame
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            try require(abs(baseline.width - 640) <= 1, "expanded launcher must be 640 pt wide")
            let expectedTop = visibleFrame.maxY - visibleFrame.height * 0.18
            try require(abs(baseline.maxY - expectedTop) <= 1, "launcher must open at the lowered screen anchor")
            let availableHeight = floor(visibleFrame.height * 0.82 - 24)
            // 52 pt field + 1 pt divider + 380 pt list; the window is exactly the shell.
            let expectedHeight = min(433, availableHeight)
            try require(abs(baseline.height - expectedHeight) <= 1,
                        "long results must use the 380 pt list budget within screen bounds")
        }
        print("launcherFrame=\(baseline)")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(panel.windowNumber),
                             "build/launcher-sizing-\(NSApp.appearance!.name.rawValue).png"]
        try capture.run()
        capture.waitUntilExit()
        try require(capture.terminationStatus == 0, "launcher sizing screenshot must succeed")
        if !CommandLine.arguments.contains("--bottom-clearance") {
            try await checkSystemDelivery(controller: controller, panel: panel, content: content)
        }
        try await checkScrolling(panel: panel, content: content, model: model, editor: editor)
        if CommandLine.arguments.contains("--bottom-clearance") { return }
        let inputTop = panel.convertToScreen(field.convert(field.bounds, to: nil)).maxY
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        var minHeight = baseline.height
        var maxInputDrift: CGFloat = 0
        let initialAppCount = model.results.filter { $0.source == .app }.count
        var minAppCount = initialAppCount
        var snapshots = 0
        for character in "afari" {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
            // AppKit may defer its delegate notification for programmatic insertText.
            (field.delegate as? LauncherSearchField.Coordinator)?.controlTextDidChange(
                Notification(name: NSControl.textDidChangeNotification, object: field))
            for _ in 0..<10 {
                try await Task.sleep(for: .milliseconds(5))
                minHeight = min(minHeight, panel.frame.height)
                let top = panel.convertToScreen(field.convert(field.bounds, to: nil)).maxY
                maxInputDrift = max(maxInputDrift, abs(top - inputTop))
                snapshots += 1
                minAppCount = min(minAppCount, model.results.filter { $0.source == .app }.count)
            }
        }
        for _ in 0..<80 {
            try await Task.sleep(for: .milliseconds(5))
            minHeight = min(minHeight, panel.frame.height)
            let top = panel.convertToScreen(field.convert(field.bounds, to: nil)).maxY
            maxInputDrift = max(maxInputDrift, abs(top - inputTop))
            snapshots += 1
        }
        print("samples=\(snapshots) baselineHeight=\(baseline.height) minHeight=\(minHeight) inputDrift=\(maxInputDrift) model=\(model.inputText) editor=\(editor.string)")
        try require(model.inputText == "safari" && editor.string == "safari", "native typing must preserve text")
        try require(abs(minHeight - baseline.height) <= 1, "results must not collapse while the replacement search is pending")
        try require(maxInputDrift <= 1, "input screen position must stay fixed during result delivery")
        try require(minAppCount == initialAppCount, "still-matching rows must remain visible between search batches")
        try require(field.currentEditor() === editor, "result delivery must preserve the editor")

        model.inputText = "empty"
        try await Task.sleep(for: .milliseconds(250))
        try require(model.isSearching, "slow source must still be pending")
        try require(abs(panel.frame.height - baseline.height) <= 1, "slow pending search must retain the result footprint")
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(5))
            let top = panel.convertToScreen(field.convert(field.bounds, to: nil)).maxY
            maxInputDrift = max(maxInputDrift, abs(top - inputTop))
        }
        try require(panel.frame.height == baseline.height, "settled smaller results must retain expanded height")
        try require(!model.results.contains { $0.source == .app || $0.source == .file }, "empty provider batches must remove old results")
        model.inputText = ""
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(5))
            let top = panel.convertToScreen(field.convert(field.bounds, to: nil)).maxY
            maxInputDrift = max(maxInputDrift, abs(top - inputTop))
        }
        try require(abs(panel.frame.height - LauncherLayout.inputHeight) <= 1, "clearing root input must collapse")
        print("settledChangeSamples=160 inputDrift=\(maxInputDrift)")
        try require(maxInputDrift <= 1, "shrinking/clearing results must preserve input position")

        model.inputText = "go "
        try await Task.sleep(for: .milliseconds(200))
        try require(model.commandInput != nil && editor.string.isEmpty, "keyword entry must consume its token")
        editor.insertText("safari", replacementRange: editor.selectedRange())
        (field.delegate as? LauncherSearchField.Coordinator)?.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: field))
        try await Task.sleep(for: .milliseconds(200))
        try require(model.commandInput?.text == "safari", "keyword query must remain editable")
    }
}
