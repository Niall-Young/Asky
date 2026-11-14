import AppKit
import Carbon.HIToolbox
import LocalStore
import ToolService

enum FolderBackspaceBehavior: String, Codable, Sendable { case parent, exitNavigation }

struct SettingsPreferences: Codable, Equatable, Sendable {
    var folderBackspaceBehavior: FolderBackspaceBehavior = .parent
    var agentAvatarColor = "blue"
    var agentAvatarShape = "monster"
    var agentAvatarExpression = "smile"
    var appearance = "system"
    var showMenuBarIcon = true
    var showDockIcon = false
    var hasInitializedLoginItem = false
    var liquidGlass = true
    var automaticUpdates = true
    var language = ApplicationLanguage.system
    var provider = "custom"
    var hotKeyCode: UInt32 = UInt32(kVK_Space)
    var hotKeyModifiers: UInt32 = UInt32(optionKey)
    var hotKeyLabel = "⌥ Space"
    var clipboardHotKeyCode: UInt32 = Self.defaultClipboardHotKey.code
    var clipboardHotKeyModifiers: UInt32 = Self.defaultClipboardHotKey.modifiers
    var clipboardHotKeyLabel = Self.defaultClipboardHotKey.label
    var agentHotKeyCode: UInt32 = Self.defaultAgentHotKey.code
    var agentHotKeyModifiers: UInt32 = Self.defaultAgentHotKey.modifiers
    var agentHotKeyLabel = Self.defaultAgentHotKey.label
    var revealInFinderHotKey = LauncherActionShortcut.revealInFinder
    var copyPathHotKey = LauncherActionShortcut.copyPath
    var localShortcuts: [String: LauncherActionShortcut] = [:]
    var aliases: [LauncherAlias] = []
    var commandKeywords: [String: String] = [:]
    static let defaultDisabledBuiltInCommands: Set<String> = ["ds", "yt", "bd", "hb", "zh", "xhs", "wb"]
    var disabledBuiltInCommands = Self.defaultDisabledBuiltInCommands
    /// Search commands (screen picker, tabs, categories…) stay enabled by default.
    var disabledSearchCommands: Set<String> = []
    static let key = "app.preferences.v1"
    static let defaultClipboardHotKey = (code: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | shiftKey), label: "⌃⇧ C")

    static let defaultAgentHotKey = (code: UInt32(kVK_ANSI_Slash), modifiers: UInt32(controlKey | shiftKey), label: "⌃⇧ /")

    init() {}

    // Saved preferences from older builds lack newer fields; fill defaults instead of discarding everything.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SettingsPreferences()
        folderBackspaceBehavior = try c.decodeIfPresent(FolderBackspaceBehavior.self, forKey: .folderBackspaceBehavior) ?? d.folderBackspaceBehavior
        agentAvatarColor = try c.decodeIfPresent(String.self, forKey: .agentAvatarColor) ?? d.agentAvatarColor
        agentAvatarShape = try c.decodeIfPresent(String.self, forKey: .agentAvatarShape) ?? d.agentAvatarShape
        agentAvatarExpression = try c.decodeIfPresent(String.self, forKey: .agentAvatarExpression) ?? d.agentAvatarExpression
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? d.appearance
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? d.showMenuBarIcon
        showDockIcon = try c.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? d.showDockIcon
        // Existing installations retain their system login-item choice.
        hasInitializedLoginItem = try c.decodeIfPresent(Bool.self, forKey: .hasInitializedLoginItem) ?? true
        liquidGlass = try c.decodeIfPresent(Bool.self, forKey: .liquidGlass) ?? d.liquidGlass
        automaticUpdates = try c.decodeIfPresent(Bool.self, forKey: .automaticUpdates) ?? d.automaticUpdates
        let savedLanguage = try c.decodeIfPresent(String.self, forKey: .language)
        language = savedLanguage.flatMap(ApplicationLanguage.init(rawValue:)) ?? .system
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? d.provider
        hotKeyCode = try c.decodeIfPresent(UInt32.self, forKey: .hotKeyCode) ?? d.hotKeyCode
        hotKeyModifiers = try c.decodeIfPresent(UInt32.self, forKey: .hotKeyModifiers) ?? d.hotKeyModifiers
        hotKeyLabel = try c.decodeIfPresent(String.self, forKey: .hotKeyLabel) ?? d.hotKeyLabel
        clipboardHotKeyCode = try c.decodeIfPresent(UInt32.self, forKey: .clipboardHotKeyCode) ?? d.clipboardHotKeyCode
        clipboardHotKeyModifiers = try c.decodeIfPresent(UInt32.self, forKey: .clipboardHotKeyModifiers) ?? d.clipboardHotKeyModifiers
        clipboardHotKeyLabel = try c.decodeIfPresent(String.self, forKey: .clipboardHotKeyLabel) ?? d.clipboardHotKeyLabel
        agentHotKeyCode = try c.decodeIfPresent(UInt32.self, forKey: .agentHotKeyCode) ?? d.agentHotKeyCode
        agentHotKeyModifiers = try c.decodeIfPresent(UInt32.self, forKey: .agentHotKeyModifiers) ?? d.agentHotKeyModifiers
        agentHotKeyLabel = try c.decodeIfPresent(String.self, forKey: .agentHotKeyLabel) ?? d.agentHotKeyLabel
        revealInFinderHotKey = try c.decodeIfPresent(LauncherActionShortcut.self, forKey: .revealInFinderHotKey) ?? d.revealInFinderHotKey
        copyPathHotKey = try c.decodeIfPresent(LauncherActionShortcut.self, forKey: .copyPathHotKey) ?? d.copyPathHotKey
        localShortcuts = try c.decodeIfPresent([String: LauncherActionShortcut].self, forKey: .localShortcuts) ?? [:]
        aliases = try c.decodeIfPresent([LauncherAlias].self, forKey: .aliases) ?? d.aliases
        commandKeywords = try c.decodeIfPresent([String: String].self, forKey: .commandKeywords) ?? [:]
        disabledBuiltInCommands = try c.decodeIfPresent(Set<String>.self, forKey: .disabledBuiltInCommands) ?? d.disabledBuiltInCommands
        disabledSearchCommands = try c.decodeIfPresent(Set<String>.self, forKey: .disabledSearchCommands) ?? d.disabledSearchCommands
        // Move saved legacy defaults without overwriting custom bindings or creating conflicts.
        if let saved = localShortcuts[LocalShortcutAction.askAI.rawValue],
           saved.code == 36, [UInt32(256), UInt32(4096)].contains(saved.modifiers) {
            _ = setShortcut(.askAI, LocalShortcutAction.askAI.defaultShortcut)
        }
        if revealInFinderHotKey.hasSameKeys(as: .init(code: 3, modifiers: 256, label: "")) {
            _ = setShortcut(.reveal, .revealInFinder)
        }
    }
}

/// Local launcher actions share the recorder's Carbon representation, without global registration.
struct LauncherActionShortcut: Codable, Equatable, Sendable {
    var code: UInt32
    var modifiers: UInt32
    var label: String

    static let revealInFinder = Self(code: UInt32(kVK_Return), modifiers: UInt32(cmdKey), label: "⌘ ↵")
    static let copyPath = Self(code: UInt32(kVK_ANSI_C), modifiers: UInt32(optionKey | cmdKey), label: "⌥⌘ C")

    func matches(_ event: NSEvent) -> Bool {
        var flags: NSEvent.ModifierFlags = []
        for (carbon, flag) in [(cmdKey, NSEvent.ModifierFlags.command), (optionKey, .option), (controlKey, .control), (shiftKey, .shift)] {
            if modifiers & UInt32(carbon) != 0 { flags.insert(flag) }
        }
        return event.type == .keyDown && (UInt32(event.keyCode) == code || (code == 36 && event.keyCode == 76))
            && event.modifierFlags.intersection([.command, .option, .control, .shift]) == flags
    }
}

struct LauncherAlias: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var alias: String
    var kind: String
    var target: String
}

/// One credential read per account per app session; concurrent users share the read.
actor ModelCredentialSession {
    private var values: [String: String] = [:]
    private var generations: [String: Int] = [:]
    private var pending: [String: Task<String?, Error>] = [:]

    func remember(_ value: String, account: String) {
        generations[account, default: 0] += 1
        values[account] = value
    }

    func read(account: String, keychain: Keychain,
              started: @escaping @Sendable () async -> Void,
              finished: @escaping @Sendable () async -> Void) async throws -> String? {
        if let value = values[account] { return value }
        if let task = pending[account] {
            let value = try await task.value
            return values[account] ?? value
        }
        let generation = generations[account, default: 0]
        let task = Task.detached { () throws -> String? in
            do { return try keychain.read(account: account, allowInteraction: false) }
            catch let error as Keychain.KeychainError where error.requiresAuthentication {
                await started()
                do {
                    let value = try keychain.read(account: account)
                    await finished()
                    return value
                } catch {
                    await finished()
                    throw error
                }
            }
        }
        pending[account] = task
        defer { pending[account] = nil }
        let value = try await task.value
        if generation != generations[account, default: 0] { return values[account] }
        if let value { values[account] = value }
        return value
    }
}
