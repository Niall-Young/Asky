import SwiftUI
import DirectActions
import Router
import Theme
import ToolService

struct TerminalSettings: View {
    @Bindable var app: AppModel
    @State private var terminals: [LauncherTerminalApplication] = []

    var body: some View {
        SettingsForm {
            Section(NSLocalizedString("终端指令", comment: "")) {
                HStack(spacing: 10) {
                    CommandIcon(terminalIcon: ToolService.launcherTerminalIcon(selectedTerminal))
                        .accessibilityHidden(true)
                    SettingsTextField(NSLocalizedString("触发指令", comment: ""), text: keyword,
                                      prompt: Text(LauncherInputState.defaultTerminalKeyword))
                    SettingsButton(NSLocalizedString("恢复默认", comment: "")) {
                        app.settings.terminalKeyword = nil
                    }
                }
                if let keywordProblem {
                    Text(keywordProblem).foregroundStyle(ThemeColor.kTextNegative)
                }
            }
            Section(NSLocalizedString("终端", comment: "")) {
                LabeledContent(NSLocalizedString("执行命令的终端", comment: "")) {
                    SettingsChoice(selection: Binding(
                        get: { app.settings.terminalApplicationID ?? LauncherTerminalApplication.system.rawValue },
                        set: { app.settings.terminalApplicationID = $0 }),
                        options: terminalChoices.map { terminal in
                            (terminal.rawValue, terminal.name + (terminals.contains(terminal) ? "" : NSLocalizedString("（未安装）", comment: "")))
                        },
                        images: Dictionary(uniqueKeysWithValues: terminalChoices.compactMap { terminal in
                            ToolService.launcherTerminalIcon(terminal).map { (terminal.rawValue, $0) }
                        }))
                }
                SettingsTextField(NSLocalizedString("工作目录", comment: ""), text: $app.settings.terminalWorkingDirectory)
            }
        }
        .onAppear { terminals = ToolService.installedLauncherTerminals() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            terminals = ToolService.installedLauncherTerminals()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            terminals = ToolService.installedLauncherTerminals()
        }
    }

    private var keyword: Binding<String> {
        Binding(get: { app.settings.terminalKeyword ?? LauncherInputState.defaultTerminalKeyword },
                set: { app.settings.terminalKeyword = $0.trimmingCharacters(in: .whitespaces) })
    }

    private var keywordProblem: String? {
        let value = app.settings.terminalKeyword ?? LauncherInputState.defaultTerminalKeyword
        guard LauncherInputState.isValidTerminalKeyword(value) else {
            return String(format: NSLocalizedString("指令不能为空、包含空格或使用 bm，当前仍使用 %@。", comment: ""),
                          LauncherInputState.defaultTerminalKeyword)
        }
        let clashes = AppModel.searchCommands.contains { app.commandKeyword($0.0).caseInsensitiveCompare(value) == .orderedSame }
            || app.keywords.commands.contains { $0.keyword.caseInsensitiveCompare(value) == .orderedSame }
            || app.preferences.aliases.contains { $0.alias.caseInsensitiveCompare(value) == .orderedSame }
        return clashes ? NSLocalizedString("该指令与已有指令或别名重名，输入时将优先进入终端。", comment: "") : nil
    }

    private var selectedTerminal: LauncherTerminalApplication {
        app.settings.terminalApplicationID.flatMap(LauncherTerminalApplication.init(rawValue:)) ?? .system
    }

    private var terminalChoices: [LauncherTerminalApplication] {
        terminals.contains(selectedTerminal) ? terminals : terminals + [selectedTerminal]
    }
}
