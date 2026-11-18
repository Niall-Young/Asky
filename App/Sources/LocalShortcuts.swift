import AppKit
import SwiftUI

/// Stored by stable action ID; missing IDs retain their defaults on older installations.
enum LocalShortcutAction: String, CaseIterable, Identifiable {
    case windowPreviousDisplay, windowNextDisplay, reveal, copyPath, copyFile, copyName, fileInfo, execute, askAI, launcherPreview, launcherMore, launcherUp, launcherDown, enterFolder, back, launcherEscape, settings, paste, clipboardCopy, delete, clipboardPreview, clipboardMore, clipboardUp, clipboardDown, clipboardEscape, send, newline, newChat, closeChat, agentEscape
    var id: String { rawValue }
    var isConfigurable: Bool {
        switch self {
        case .execute, .launcherUp, .launcherDown, .enterFolder, .back, .launcherEscape,
             .paste, .clipboardUp, .clipboardDown, .clipboardEscape,
             .send, .newline, .agentEscape: false
        default: true
        }
    }
    var title: String {
        switch self {
        case .windowPreviousDisplay: "切换到上一块屏幕"
        case .windowNextDisplay: "切换到下一块屏幕"
        case .reveal: "在访达中显示"
        case .copyPath: "复制文件路径"
        case .copyFile: "复制文件"
        case .copyName: "复制文件名"
        case .fileInfo: "展示文件信息"
        case .launcherPreview, .clipboardPreview: "快速预览"
        case .execute: "执行选中结果"
        case .askAI: "询问 AI"
        case .launcherMore: "更多"
        case .launcherUp: "选择上一项"
        case .launcherDown: "选择下一项"
        case .enterFolder: "进入选中文件夹"
        case .back: "返回上级或退出导航"
        case .launcherEscape: "关闭菜单、退出导航或隐藏窗口"
        case .settings: "打开设置"
        case .paste: "粘贴到光标位置"
        case .clipboardCopy: "复制到剪贴板"
        case .delete: "删除记录"
        case .clipboardMore: "更多（列表布局）"
        case .clipboardUp: "选择上一项"
        case .clipboardDown: "选择下一项"
        case .clipboardEscape: "关闭菜单或剪贴板"
        case .send: "发送消息"
        case .newline: "输入换行"
        case .newChat: "新对话"
        case .closeChat: "关闭对话窗口"
        case .agentEscape: "关闭对话窗口"
        }
    }
    var scope: String {
        switch self {
        case .windowPreviousDisplay, .windowNextDisplay: "launcher"
        case .reveal: "launcher"
        case .copyPath: "launcher"
        case .copyFile: "launcher"
        case .copyName: "launcher"
        case .fileInfo: "launcher"
        case .launcherPreview: "launcher"
        case .execute: "launcher"
        case .askAI: "launcher"
        case .launcherMore: "launcher"
        case .launcherUp: "launcher"
        case .launcherDown: "launcher"
        case .enterFolder: "launcher"
        case .back: "launcher"
        case .launcherEscape: "launcher"
        case .settings: "all"
        case .paste: "clipboard"
        case .clipboardCopy: "clipboard"
        case .delete: "clipboard"
        case .clipboardPreview: "clipboard"
        case .clipboardMore: "clipboard"
        case .clipboardUp: "clipboard"
        case .clipboardDown: "clipboard"
        case .clipboardEscape: "clipboard"
        case .send: "agent"
        case .newline: "agent"
        case .newChat: "agent"
        case .closeChat: "agent"
        case .agentEscape: "agent"
        }
    }
    var defaultShortcut: LauncherActionShortcut {
        switch self {
        case .windowPreviousDisplay: .init(code: 123, modifiers: 512, label: "⇧ ←")
        case .windowNextDisplay: .init(code: 124, modifiers: 512, label: "⇧ →")
        case .reveal: .revealInFinder
        case .copyPath: .init(code: 8, modifiers: 2304, label: "⌥⌘ C")
        case .copyFile: .init(code: 8, modifiers: 256, label: "⌘ C")
        case .copyName: .init(code: 47, modifiers: 768, label: "⌘⇧ .")
        case .fileInfo: .init(code: 34, modifiers: 256, label: "⌘ I")
        case .launcherPreview, .clipboardPreview: .init(code: 49, modifiers: 4096, label: "⌃ Space")
        case .execute: .init(code: 36, modifiers: 0, label: "↵")
        case .askAI: .init(code: 36, modifiers: 768, label: "⇧⌘ ↵")
        case .launcherMore: .init(code: 40, modifiers: 256, label: "⌘ K")
        case .launcherUp: .init(code: 126, modifiers: 0, label: "↑")
        case .launcherDown: .init(code: 125, modifiers: 0, label: "↓")
        case .enterFolder: .init(code: 48, modifiers: 0, label: "Tab")
        case .back: .init(code: 51, modifiers: 0, label: "⌫")
        case .launcherEscape: .init(code: 53, modifiers: 0, label: "Esc")
        case .settings: .init(code: 43, modifiers: 256, label: "⌘ ,")
        case .paste: .init(code: 36, modifiers: 0, label: "↵")
        case .clipboardCopy: .init(code: 36, modifiers: 256, label: "⌘ ↵")
        case .delete: .init(code: 51, modifiers: 256, label: "⌘ ⌫")
        case .clipboardMore: .init(code: 40, modifiers: 256, label: "⌘ K")
        case .clipboardUp: .init(code: 126, modifiers: 0, label: "↑")
        case .clipboardDown: .init(code: 125, modifiers: 0, label: "↓")
        case .clipboardEscape: .init(code: 53, modifiers: 0, label: "Esc")
        case .send: .init(code: 36, modifiers: 0, label: "↵")
        case .newline: .init(code: 36, modifiers: 512, label: "⇧ ↵")
        case .newChat: .init(code: 45, modifiers: 256, label: "⌘ N")
        case .closeChat: .init(code: 13, modifiers: 256, label: "⌘ W")
        case .agentEscape: .init(code: 53, modifiers: 0, label: "Esc")
        }
    }
    func overlaps(_ other: Self) -> Bool { scope == "all" || other.scope == "all" || scope == other.scope }
}

extension SettingsPreferences {
    func shortcut(_ action: LocalShortcutAction) -> LauncherActionShortcut {
        guard action.isConfigurable else { return action.defaultShortcut }
        if action == .reveal { return revealInFinderHotKey }
        if action == .copyPath { return copyPathHotKey }
        return localShortcuts[action.rawValue] ?? action.defaultShortcut
    }

    mutating func setShortcut(_ action: LocalShortcutAction, _ shortcut: LauncherActionShortcut) -> Bool {
        guard action.isConfigurable else { return false }
        let global = [(hotKeyCode, hotKeyModifiers), (clipboardHotKeyCode, clipboardHotKeyModifiers),
                      (agentHotKeyCode, agentHotKeyModifiers)]
        guard !global.contains(where: { $0.0 == shortcut.code && $0.1 == shortcut.modifiers }),
              !LocalShortcutAction.allCases.contains(where: {
                  $0 != action && action.overlaps($0) && self.shortcut($0).hasSameKeys(as: shortcut)
              }) else { return false }
        if action == .reveal { revealInFinderHotKey = shortcut }
        else if action == .copyPath { copyPathHotKey = shortcut }
        else { localShortcuts[action.rawValue] = shortcut }
        return true
    }
}

extension LauncherActionShortcut {
    func hasSameKeys(as other: Self) -> Bool { code == other.code && modifiers == other.modifiers }

    var eventModifiers: EventModifiers {
        var flags: EventModifiers = []
        for (carbon, flag) in [(256, EventModifiers.command), (512, .shift), (2048, .option), (4096, .control)] {
            if modifiers & UInt32(carbon) != 0 { flags.insert(flag) }
        }
        return flags
    }

    var keyEquivalent: KeyEquivalent {
        let special: [UInt32: KeyEquivalent] = [36: .return, 48: .tab, 49: .space, 51: .delete,
            53: .escape, 123: .leftArrow, 124: .rightArrow, 125: .downArrow, 126: .upArrow]
        if let value = special[code] { return value }
        let functionCodes: [UInt32] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        if let index = functionCodes.firstIndex(of: code), let scalar = UnicodeScalar(0xF704 + index) {
            return KeyEquivalent(Character(scalar))
        }
        return KeyEquivalent(label.last.map { Character(String($0).lowercased()) } ?? " ")
    }
}
