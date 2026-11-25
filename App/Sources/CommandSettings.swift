import SwiftUI
import DirectActions
import Theme

struct CommandSettings: View {
    @Bindable var app: AppModel
    @State private var query = ""
    @State private var selectedTab = "search"
    @FocusState private var searchFocused: Bool
    @FocusState private var focusedCommand: String?

    private var filteredSearchCommands: [(String, String, String)] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return AppModel.searchCommands.filter {
            term.isEmpty || app.commandKeyword($0.0).localizedStandardContains(term) || $0.0.localizedStandardContains(term)
                || $0.1.localizedStandardContains(term)
                || NSLocalizedString($0.1, comment: "").localizedStandardContains(term)
        }
    }

    private var filteredCommands: [KeywordCommand] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return KeywordCommand.builtIn.filter {
            term.isEmpty || app.commandKeyword($0.keyword).localizedStandardContains(term) || $0.keyword.localizedStandardContains(term)
                || $0.name.localizedStandardContains(term)
                || NSLocalizedString($0.name, comment: "").localizedStandardContains(term)
        }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 24) {
                    SettingsSearchField(query: $query, focus: $searchFocused,
                                       placeholder: "搜索指令或名称", identifier: "command-search")
                        .frame(height: 28)
                    SettingsSegmentedControl(selection: $selectedTab, options: [
                        ("search", NSLocalizedString("搜索指令", comment: "")),
                        ("builtIn", NSLocalizedString("内置指令", comment: "")),
                    ], identifier: "command-tabs", accessibilityLabel: NSLocalizedString("指令", comment: ""))
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(height: 28)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)
                SettingsForm {
                    if isSearching || selectedTab == "search" {
                        Section {
                            if filteredSearchCommands.isEmpty {
                                Text(NSLocalizedString("未找到匹配的指令", comment: ""))
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(filteredSearchCommands, id: \.0) { item in
                                LabeledContent {
                                    CommandKeywordEditor(app: app, id: item.0, focus: $focusedCommand)
                                        .id(item.0)
                                } label: {
                                    HStack(spacing: 10) {
                                        Toggle(NSLocalizedString(item.1, comment: ""), isOn: Binding(
                                            get: { app.isSearchCommandEnabled(item.0) },
                                            set: { enabled in
                                                if enabled { app.preferences.disabledSearchCommands.remove(item.0) }
                                                else { app.preferences.disabledSearchCommands.insert(item.0) }
                                            }
                                        ))
                                        .toggleStyle(.checkbox)
                                        .labelsHidden()
                                        .accessibilityIdentifier("search-command-enabled-" + item.0)
                                        LauncherFunctionIcon(kind: .searchCommand(item.0))
                                            .accessibilityHidden(true)
                                        Text(NSLocalizedString(item.1, comment: ""))
                                    }
                                }
                            }
                        } header: {
                            if isSearching { Text(NSLocalizedString("搜索指令", comment: "")) }
                        }
                    }
                    if isSearching || selectedTab == "builtIn" {
                        Section {
                            if filteredCommands.isEmpty {
                                Text(NSLocalizedString("未找到匹配的指令", comment: ""))
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(filteredCommands) { command in
                                LabeledContent {
                                    CommandKeywordEditor(app: app, id: command.keyword, focus: $focusedCommand)
                                        .id(command.keyword)
                                } label: {
                                    HStack(spacing: 10) {
                                        Toggle(NSLocalizedString(command.name, comment: ""), isOn: Binding(
                                            get: { !app.preferences.disabledBuiltInCommands.contains(command.keyword) },
                                            set: { enabled in
                                                if enabled { app.preferences.disabledBuiltInCommands.remove(command.keyword) }
                                                else { app.preferences.disabledBuiltInCommands.insert(command.keyword) }
                                            }
                                        ))
                                        .toggleStyle(.checkbox)
                                        .labelsHidden()
                                        .accessibilityIdentifier("command-enabled-" + command.keyword)
                                        CommandIcon(keyword: command.keyword)
                                            .accessibilityHidden(true)
                                        Text(NSLocalizedString(command.name, comment: ""))
                                    }
                                }
                            }
                        } header: {
                            if isSearching { Text(NSLocalizedString("内置指令", comment: "")) }
                        }
                    }
                }
            }
            .task(id: app.commandEditRequest?.token) {
                guard let request = app.commandEditRequest else { return }
                query = ""
                selectedTab = AppModel.searchCommands.contains { $0.0 == request.id } ? "search" : "builtIn"
                await Task.yield()
                guard !Task.isCancelled else { return }
                proxy.scrollTo(request.id, anchor: .center)
                focusedCommand = request.id
                app.commandEditRequest = nil
            }
        }
    }
}


private struct CommandKeywordEditor: View {
    @Bindable var app: AppModel
    let id: String
    @State private var draft = ""
    @State private var error: String?
    @Environment(\.colorScheme) private var scheme
    var focus: FocusState<String?>.Binding
    private var focused: Bool { focus.wrappedValue == id }

    private var defaultValue: String {
        AppModel.searchCommands.first { $0.0 == id }?.2 ?? id
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                TextField(NSLocalizedString("触发指令", comment: ""), text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .focused(focus, equals: id)
                    .settingsInputSurface(scheme: scheme, focused: focused)
                    .frame(width: 90)
                    .accessibilityIdentifier("command-keyword-" + id)
                    .onSubmit(save)
                SettingsButton(NSLocalizedString("恢复默认", comment: "")) { reset() }
            }
            if let error { Text(error).font(.caption).foregroundStyle(ThemeColor.kTextNegative) }
        }
        .onAppear { draft = app.commandKeyword(id) }
        .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
        .onChange(of: draft) { _, _ in error = nil }
    }

    private func save() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let problem = app.commandKeywordProblem(value, id: id) { error = problem; return }
        if value == defaultValue { app.preferences.commandKeywords.removeValue(forKey: id) }
        else { app.preferences.commandKeywords[id] = value }
        draft = value
        error = nil
    }

    private func reset() {
        if let problem = app.commandKeywordProblem(defaultValue, id: id) {
            error = problem
            return
        }
        app.preferences.commandKeywords.removeValue(forKey: id)
        draft = defaultValue
        error = nil
    }
}
