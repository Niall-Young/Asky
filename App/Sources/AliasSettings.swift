import SwiftUI
import DirectActions
import Contracts
import ToolService
import Theme

struct AliasSettings: View {
    @Bindable var app: AppModel
    @State private var editor: AliasDraft?

    var body: some View {
        SettingsForm {
            Section {
                if app.preferences.aliases.isEmpty {
                    Text(label("暂无别名")).foregroundStyle(.secondary)
                }
                ForEach(app.preferences.aliases) { item in
                    HStack(spacing: 12) {
                        AliasTargetIcon(kind: item.kind, target: item.target, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AliasDraft.displayName(kind: item.kind, target: item.target)).lineLimit(1)
                            Text(label(item.kind == "app" ? "应用" : "快捷指令"))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        AliasChip(text: item.alias)
                        aliasMenu(item)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editor = AliasDraft(item) }
                }
                HStack {
                    Spacer()
                    SettingsButton(label("添加别名"), systemImage: "plus") { editor = AliasDraft() }
                }
            } header: {
                Text(label("应用与快捷指令别名"))
            }
        }
        .settingsDialog(isPresented: editor != nil) {
            if let draft = editor {
                AliasEditor(app: app, draft: draft) { editor = nil }
                    .id(draft.id)
            }
        }
    }

    private func aliasMenu(_ item: LauncherAlias) -> some View {
        SettingsMoreMenu {
            Button(label("编辑")) { editor = AliasDraft(item) }
            Divider()
            Button(label("删除"), role: .destructive) { app.preferences.aliases.removeAll { $0.id == item.id } }
        }
        .accessibilityLabel(label("更多操作") + " " + item.alias).help(label("更多操作"))
    }
}

private func label(_ key: String) -> String { NSLocalizedString(key, comment: "") }

private struct AliasDraft: Identifiable {
    let id: UUID
    let isNew: Bool
    var alias = ""
    var kind = "app"
    var target = ""

    init() { id = UUID(); isNew = true }
    init(_ item: LauncherAlias) {
        id = item.id; isNew = false; alias = item.alias; kind = item.kind; target = item.target
    }

    static func displayName(kind: String, target: String) -> String {
        kind == "app" ? URL(filePath: target).deletingPathExtension().lastPathComponent : target
    }
}

private struct AliasTargetIcon: View {
    let kind: String
    let target: String
    let size: CGFloat
    var body: some View {
        Image(nsImage: ToolService.launcherIcon(filePath: kind == "app" ? target : "/System/Applications/Shortcuts.app"))
            .resizable().scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct AliasChip: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .settingsInputChrome(scheme: scheme, focused: false, cornerRadius: 5)
            .help(label("别名"))
    }
}

private struct AliasEditor: View {
    @Bindable var app: AppModel
    @State var draft: AliasDraft
    let close: () -> Void
    @State private var shortcuts: [String] = []
    @State private var loadingShortcuts = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        SettingsDialogScaffold(
            title: label(draft.isNew ? "添加别名" : "编辑别名"),
            width: 480,
            primaryTitle: label("保存"),
            primaryDisabled: !canSave,
            primaryAction: save,
            cancelTitle: label("取消"),
            close: close
        ) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 0) {
                    cardRow {
                        LabeledContent(label("类型")) { AliasKindPicker(selection: $draft.kind) }
                            .onChange(of: draft.kind) { _, _ in draft.target = "" }
                    }
                    cardSeparator
                    cardRow {
                        if draft.kind == "app" { appPicker } else { shortcutPicker }
                    }
                    cardSeparator
                    cardRow {
                        SettingsTextField(label("别名"), text: $draft.alias,
                                          prompt: Text(verbatim: label("不能包含空格，不区分大小写。")))
                            .onSubmit(save)
                    }
                }
                .background(SettingsPalette.card(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if let error = validationError {
                    Text(error).foregroundStyle(ThemeColor.kTextNegative)
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .labeledContentStyle(AliasRowStyle())
        .task { await refreshShortcuts() }
    }

    private var cardSeparator: some View {
        Rectangle().fill(SettingsPalette.separator(scheme)).frame(height: 1).padding(.horizontal, 16)
    }

    private func cardRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var appPicker: some View {
        LabeledContent(label("应用")) {
            HStack(spacing: 8) {
                if !draft.target.isEmpty {
                    AliasTargetIcon(kind: "app", target: draft.target, size: 22)
                    Text(AliasDraft.displayName(kind: "app", target: draft.target)).lineLimit(1)
                }
                SettingsButton(label(draft.target.isEmpty ? "选择应用…" : "更换…")) { chooseApp() }
            }
        }
    }

    private var shortcutPicker: some View {
        LabeledContent(label("快捷指令")) {
            HStack(spacing: 8) {
                if shortcutChoices.isEmpty && !loadingShortcuts {
                    Text(label("暂无快捷指令")).foregroundStyle(.secondary)
                } else {
                    SettingsChoice(selection: $draft.target, options:
                        [("", label("请选择"))] + shortcutChoices.map { ($0, $0) },
                        images: Dictionary(uniqueKeysWithValues: shortcutChoices.map {
                            ($0, ToolService.launcherIcon(filePath: "/System/Applications/Shortcuts.app"))
                        }))
                }
                SettingsButton("", systemImage: "arrow.clockwise", isLoading: loadingShortcuts) {
                    Task { await refreshShortcuts() }
                }
                .help(label("刷新快捷指令")).accessibilityLabel(label("刷新快捷指令"))
            }
        }
    }

    private var shortcutChoices: [String] {
        Array(Set(shortcuts + (draft.kind == "shortcut" && !draft.target.isEmpty ? [draft.target] : []))).sorted()
    }

    private var trimmedAlias: String { draft.alias.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var validationError: String? {
        let name = trimmedAlias
        guard !name.isEmpty else { return nil }
        let terminalKeyword = app.settings.terminalCommandKeyword
        if name.contains(where: \.isWhitespace) || name.caseInsensitiveCompare(terminalKeyword) == .orderedSame
            || AppModel.searchCommands.contains(where: { app.commandKeyword($0.0).caseInsensitiveCompare(name) == .orderedSame }) {
            return label("该指令与已有指令或别名重名。")
        }
        if app.preferences.aliases.contains(where: { $0.id != draft.id && $0.alias.caseInsensitiveCompare(name) == .orderedSame })
            || app.keywords.commands.contains(where: { $0.keyword.caseInsensitiveCompare(name) == .orderedSame }) {
            return label("这个别名或关键词已存在。")
        }
        return nil
    }

    private var canSave: Bool { !trimmedAlias.isEmpty && !draft.target.isEmpty && validationError == nil }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.target = url.path
        // Suggest a short alias from the app name so the common case needs no typing.
        if trimmedAlias.isEmpty {
            draft.alias = AliasDraft.displayName(kind: "app", target: url.path)
                .split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
        }
    }

    private func refreshShortcuts() async {
        loadingShortcuts = true
        shortcuts = await ToolService.listLauncherShortcuts()
        loadingShortcuts = false
    }

    private func save() {
        guard canSave else { return }
        let item = LauncherAlias(id: draft.id, alias: trimmedAlias, kind: draft.kind, target: draft.target)
        if let index = app.preferences.aliases.firstIndex(where: { $0.id == item.id }) {
            app.preferences.aliases[index] = item
        } else {
            app.preferences.aliases.append(item)
        }
        close()
    }
}

private struct AliasRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 24) {
            configuration.label
            Spacer(minLength: 24)
            configuration.content
        }
    }
}

/// Matches the settings input surface instead of the system accent-filled segmented control.
private struct AliasKindPicker: View {
    @Binding var selection: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            option("app", label("应用"))
            option("shortcut", label("快捷指令"))
        }
        .padding(2)
        .background(scheme == .dark ? ThemeColor.kBackgroundNeutral.color(for: scheme) : SettingsPalette.surface(scheme),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(ThemeColor.kBorder.color(for: scheme), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label("类型"))
    }

    private func option(_ value: String, _ title: String) -> some View {
        let selected = selection == value
        return Button { selection = value } label: {
            Text(title).font(.system(size: 13))
                .foregroundStyle(selected ? ThemeColor.kText : ThemeColor.kTextSubtle)
                .padding(.horizontal, 12).frame(height: 22)
                .background(selected ? ThemeColor.kBackgroundSelected.color(for: scheme) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
