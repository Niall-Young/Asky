import AppKit
import Carbon.HIToolbox
import SwiftUI
import LocalStore

@main @MainActor
enum LocalShortcutsRegression {
    static func event(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], window: NSWindow? = nil) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: window?.windowNumber ?? 0, context: nil, characters: "j",
                         charactersIgnoringModifiers: "j", isARepeat: false, keyCode: code)!
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                let root = FileManager.default.temporaryDirectory.appending(path: "Asky-shortcuts-\(UUID())")
                defer { try? FileManager.default.removeItem(at: root) }
                let app = try AppModel(root: root)
                let legacy = try JSONDecoder().decode(SettingsPreferences.self, from: Data("{}".utf8))
                for action in LocalShortcutAction.allCases {
                    precondition(legacy.shortcut(action) == action.defaultShortcut)
                }
                // Status bar menu items derive native NSMenuItem key equivalents from global shortcuts.
                precondition(legacy.launcherHotKey.menuKeyEquivalent == " ")
                precondition(legacy.launcherHotKey.modifierFlags == [.option])
                precondition(legacy.clipboardHotKey.menuKeyEquivalent == "c")
                precondition(legacy.clipboardHotKey.modifierFlags == [.control, .shift])
                precondition(legacy.agentHotKeyCode == UInt32(kVK_Space))
                precondition(legacy.agentHotKeyModifiers == UInt32(controlKey | cmdKey))
                precondition(legacy.agentHotKeyLabel == "⌃⌘ Space")
                precondition(legacy.agentHotKey.menuKeyEquivalent == " ")
                precondition(legacy.agentHotKey.modifierFlags == [.control, .command])
                let f5Shortcut = LauncherActionShortcut(code: 96, modifiers: 256, label: "⌘ F5")
                precondition(f5Shortcut.menuKeyEquivalent == String(UnicodeScalar(NSF5FunctionKey)!))
                precondition(f5Shortcut.modifierFlags == [.command])
                let unmappedShortcut = LauncherActionShortcut(code: 999, modifiers: 2048, label: "⌥ Key 999")
                precondition(unmappedShortcut.menuKeyEquivalent.isEmpty)
                let oldDefaults = Data(#"{"revealInFinderHotKey":{"code":3,"modifiers":256,"label":"⌘ F"},"localShortcuts":{"askAI":{"code":36,"modifiers":256,"label":"⌘ ↵"}}}"#.utf8)
                let migrated = try JSONDecoder().decode(SettingsPreferences.self, from: oldDefaults)
                precondition(migrated.shortcut(.reveal) == .revealInFinder)
                precondition(migrated.shortcut(.askAI) == LocalShortcutAction.askAI.defaultShortcut)
                let controlDefault = Data(#"{"localShortcuts":{"askAI":{"code":36,"modifiers":4096,"label":"⌃ ↵"}}}"#.utf8)
                let controlMigrated = try JSONDecoder().decode(SettingsPreferences.self, from: controlDefault)
                precondition(controlMigrated.shortcut(.askAI) == LocalShortcutAction.askAI.defaultShortcut)
                let migratedReloaded = try JSONDecoder().decode(SettingsPreferences.self, from: JSONEncoder().encode(migrated))
                precondition(migratedReloaded == migrated)
                var custom = SettingsPreferences()
                precondition(custom.setShortcut(.reveal, .init(code: 3, modifiers: 768, label: "⌘⇧ F")))
                precondition(custom.setShortcut(.askAI, .init(code: 38, modifiers: 4096, label: "⌃ J")))
                let customReloaded = try JSONDecoder().decode(SettingsPreferences.self, from: JSONEncoder().encode(custom))
                precondition(customReloaded == custom)
                for code: UInt16 in [36, 76] {
                    precondition(migrated.shortcut(.reveal).matches(event(code, .command)))
                    precondition(!migrated.shortcut(.askAI).matches(event(code, .command)))
                    precondition(!migrated.shortcut(.askAI).matches(event(code, .control)))
                    precondition(migrated.shortcut(.askAI).matches(event(code, [.shift, .command])))
                    precondition(!migrated.shortcut(.reveal).matches(event(code, .control)))
                }
                // Reject conflicts only where actions can run in the same window.
                precondition(!app.preferences.setShortcut(.execute, app.preferences.shortcut(.askAI)))
                precondition(!app.preferences.setShortcut(.clipboardCopy, app.preferences.shortcut(.settings)))
                precondition(app.preferences.setShortcut(.newChat, app.preferences.shortcut(.launcherMore)))
                app.preferences = SettingsPreferences()
                // Configurable actions round-trip; two legacy fields retain their existing storage.
                for (index, action) in LocalShortcutAction.allCases.enumerated() {
                    let value = LauncherActionShortcut(code: UInt32(index), modifiers: 6912, label: "⌃⌥⇧⌘ \(index)")
                    if action.isConfigurable {
                        precondition(app.preferences.setShortcut(action, value), "failed to edit \(action)")
                    } else {
                        precondition(!app.preferences.setShortcut(action, value))
                        app.preferences.localShortcuts[action.rawValue] = value
                        precondition(app.preferences.shortcut(action) == action.defaultShortcut,
                                     "saved overrides must not remap fixed keyboard operations")
                    }
                }
                let reloaded = try AppModel(root: root)
                precondition(reloaded.preferences == app.preferences)
                app.preferences = SettingsPreferences()
                app.settingsTab = "hotkey"
                let window = SettingsWindow.make(app: app)
                window.setContentSize(NSSize(width: 1000, height: 1100))
                window.makeKeyAndOrderFront(nil)
                try await Task.sleep(for: .milliseconds(350))
                @MainActor func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
                let content = window.contentView!
                let recorders = views(content).compactMap { $0 as? HotKeyRecorderField }
                guard let recorder = recorders.first(where: { $0.label == "⌘ C" }) else {
                    fatalError("Copy file must have a native editable recorder")
                }
                precondition(!recorders.contains { ["↑", "↓", "←", "→", "↵", "Tab", "⌫", "Esc", "⇧ ↵"].contains($0.label) },
                             "fixed keyboard operations must not appear as editable shortcuts")
                let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                               windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                                               clickCount: 1, pressure: 1)!
                recorder.mouseDown(with: click)
                precondition(window.firstResponder === recorder)
                recorder.keyDown(with: event(38, [.command, .shift], window: window))
                try await Task.sleep(for: .milliseconds(100))
                precondition(app.preferences.shortcut(.copyFile).code == 38)
                precondition(app.preferences.shortcut(.copyFile).modifiers == 768)
                let afterRecording = try AppModel(root: root)
                precondition(afterRecording.preferences.shortcut(.copyFile).code == 38)
                // Same native recorder accepts unmodified navigation keys and rejects occupied ones.
                recorder.mouseDown(with: click)
                recorder.keyDown(with: event(36, window: window))
                precondition(app.preferences.shortcut(.copyFile).code == 38, "occupied Return must be rejected")
                window.makeFirstResponder(nil)
                for appearance in ["light", "dark"] {
                    app.preferences.appearance = appearance
                    try await Task.sleep(for: .milliseconds(200))
                    content.layoutSubtreeIfNeeded()
                    let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
                    content.cacheDisplay(in: content.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/shortcut-edit-\(appearance).png"))
                }
                let launcher = LauncherModel(app: app, searchProviders: [])
                var prompts: [String] = []
                launcher.onAskAI = { prompts.append($0) }
                launcher.query = "hello shortcut"
                precondition(!launcher.handleActionKey(event(36, .control)))
                precondition(launcher.handleActionKey(event(36, [.shift, .command])))
                precondition(prompts == ["hello shortcut"])
                prompts.removeAll()
                var reveals = 0
                let field = CompletionTextField(frame: .zero)
                field.revealInFinder = { reveals += 1; return true }
                precondition(field.performKeyEquivalent(with: event(36, .command)))
                precondition(reveals == 1 && prompts.isEmpty)
                precondition(app.preferences.setShortcut(.askAI, .init(code: 38, modifiers: 4096, label: "⌃ J")))
                precondition(launcher.handleActionKey(event(38, .control)))
                precondition(prompts == ["hello shortcut"])
                precondition(!launcher.handleActionKey(event(36, .command)), "old AI shortcut must stop firing")
                let clipboard = ClipboardController(app: app)
                precondition(ClipboardHistoryAction.pasteKeepingOpen.shortcut == .clipboardPasteKeepingOpen)
                precondition(clipboard.handleActionKey(event(36, .option)))
                precondition(app.preferences.setShortcut(.clipboardPasteKeepingOpen, .init(code: 35, modifiers: 4096, label: "⌃ P")))
                precondition(clipboard.handleActionKey(event(35, .control)))
                precondition(!clipboard.handleActionKey(event(36, .option)), "old paste-keeping-open shortcut must stop firing")
                precondition(app.preferences.setShortcut(.clipboardCopy, .init(code: 38, modifiers: 4096, label: "⌃ J")))
                precondition(clipboard.handleActionKey(event(38, .control)))
                precondition(!clipboard.handleActionKey(event(36, .command)), "old clipboard shortcut must stop firing")
                precondition(app.preferences.setShortcut(.copyFile, LocalShortcutAction.copyFile.defaultShortcut))
                precondition(app.preferences.shortcut(.copyFile) == LocalShortcutAction.copyFile.defaultShortcut)
                var draft = "message"
                var sends = 0
                var agentPreferences = SettingsPreferences()
                precondition(!agentPreferences.setShortcut(.send, .init(code: 38, modifiers: 4096, label: "⌃ J")))
                precondition(!agentPreferences.setShortcut(.newline, .init(code: 40, modifiers: 4096, label: "⌃ K")))
                let composer = ComposerTextEditor(
                    height: .constant(44), isFocused: .constant(false), resetRevision: 0,
                    pendingInsertions: [], consumeInsertions: { _ in },
                    onSegmentsChanged: { segments in
                        draft = segments.compactMap { if case .text(let s) = $0 { return s } else { return nil } }.joined()
                    }, pasteAttachment: { false }, pasteLongText: { _ in nil },
                    submit: { sends += 1 }, shortcuts: agentPreferences)
                let host = NSHostingView(rootView: composer)
                host.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
                let composerWindow = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                composerWindow.contentView = host
                composerWindow.makeKeyAndOrderFront(nil)
                try await Task.sleep(for: .milliseconds(200))
                host.layoutSubtreeIfNeeded()
                let editor = views(host).compactMap { $0 as? NSTextView }.first!
                editor.string = draft
                precondition(editor.performKeyEquivalent(with: event(36, window: composerWindow)))
                precondition(sends == 1)
                precondition(editor.performKeyEquivalent(with: event(36, .shift, window: composerWindow)))
                precondition(editor.string.contains("\n") && sends == 1)
                editor.keyDown(with: event(36, window: composerWindow))
                precondition(sends == 2, "Return must retain the fixed send action")
                print("Local actions and fixed keyboard operations: migration, conflict scopes, persistence, native recording, reset, launcher, clipboard and AI composer dispatch passed")
                exit(0)
            } catch { fatalError("\(error)") }
        }
        NSApp.run()
    }
}
