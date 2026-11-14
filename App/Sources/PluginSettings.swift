import SwiftUI
import Contracts
import ToolService
import Theme

enum PluginSettingsCategory: String, CaseIterable, Identifiable {
    case ai, function
    var id: String { rawValue }
    var title: String {
        NSLocalizedString(self == .ai ? "AI 插件" : "功能插件", tableName: "Plugins", comment: "")
    }
    var emptyTitle: String {
        NSLocalizedString(self == .ai ? "尚未安装 AI 插件" : "尚未安装功能插件", tableName: "Plugins", comment: "")
    }
    func includes(_ manifest: PluginManifest) -> Bool {
        let hasCommands = !(manifest.commands ?? []).isEmpty
        switch self {
        case .ai:
            return manifest.tools.contains { $0.agentVisible != false } || manifest.instructions != nil || !hasCommands
        case .function:
            return hasCommands
        }
    }
    static func matches(_ plugin: InstalledPlugin, query: String) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        let m = plugin.manifest
        let fields = [m.name, m.id, plugin.repository]
            + m.tools.flatMap { [$0.name, $0.description] }
            + (m.commands ?? []).flatMap { [$0.name, $0.title, $0.keyword ?? "", $0.subtitle ?? ""] }
        return fields.contains { $0.localizedStandardContains(term) }
    }
}

struct PluginSettings: View {
    @Bindable var app: AppModel
    @State private var selectedCategory = PluginSettingsCategory.ai
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var plugins: [InstalledPlugin] = []
    @State private var adding = false
    @State private var repository = ""
    @State private var repositoryError = ""
    @State private var pendingRepository = ""
    @State private var confirmInstall = false
    @State private var busy = false
    @State private var status = ""
    @State private var editing: InstalledPlugin?
    @State private var icons: [String: NSImage] = [:]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var manager: PluginManager { app.tools.plugins }
    private func label(_ key: String) -> String { NSLocalizedString(key, comment: "") }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var categories: [PluginSettingsCategory] { isSearching ? PluginSettingsCategory.allCases : [selectedCategory] }
    private var trimmedRepository: String { repository.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// One showcase row per repository: official catalog entries appear whether or not they are installed.
    private struct PluginEntry: Identifiable {
        let repository: String
        let installed: InstalledPlugin?
        var id: String { repository }
    }
    private func entries(in category: PluginSettingsCategory) -> [PluginEntry] {
        var result: [PluginEntry] = []
        for source in PluginManager.officialRepositories {
            if let plugin = plugins.first(where: { $0.repository == source }) {
                if category.includes(plugin.manifest) && PluginSettingsCategory.matches(plugin, query: query) {
                    result.append(PluginEntry(repository: source, installed: plugin))
                }
            } else if category == .ai && matchesOfficial(source) {
                result.append(PluginEntry(repository: source, installed: nil))
            }
        }
        for plugin in plugins where !plugin.isOfficial
            && category.includes(plugin.manifest) && PluginSettingsCategory.matches(plugin, query: query) {
            result.append(PluginEntry(repository: plugin.repository, installed: plugin))
        }
        return result
    }
    private func matchesOfficial(_ source: String) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || [officialName(source), officialDescription(source), source].contains {
            $0.localizedStandardContains(term)
        }
    }
    private func officialName(_ source: String) -> String { source.hasSuffix("asky-plugin-lark") ? label("飞书") : "Orca" }
    private func officialDescription(_ source: String) -> String {
        label(source.hasSuffix("asky-plugin-lark") ? "通过飞书 CLI 管理文档、日程、任务和消息" : "添加项目，启动指定 Agent 并提交任务")
    }
    private func sectionTitle(_ category: PluginSettingsCategory) -> String {
        isSearching ? category.title : label("插件")
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                SettingsSearchField(query: $query, focus: $searchFocused,
                                    placeholder: "搜索插件或命令", identifier: "plugin-search")
                    .frame(height: 28)
                SettingsSegmentedControl(selection: $selectedCategory,
                                         options: PluginSettingsCategory.allCases.map { ($0, $0.title) },
                                         identifier: "plugin-tabs", accessibilityLabel: label("插件"))
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(height: 28)
                SettingsButton(label("添加"), systemImage: "plus") { openAddDialog() }
                    .accessibilityLabel(label("添加插件"))
                    .accessibilityIdentifier("plugin-add")
                    .disabled(busy)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
            SettingsForm {
                ForEach(categories) { category in
                    let entries = entries(in: category)
                    if !entries.isEmpty || !isSearching {
                        Section(sectionTitle(category)) {
                            if entries.isEmpty { Text(category.emptyTitle).foregroundStyle(.secondary) }
                            ForEach(entries) { entry in
                                if let plugin = entry.installed {
                                    installedRow(plugin, category: category)
                                } else {
                                    catalogRow(entry.repository)
                                }
                            }
                        }
                    }
                }
                if isSearching && categories.allSatisfy({ entries(in: $0).isEmpty }) {
                    Section {
                        Text(NSLocalizedString("未找到匹配的插件", tableName: "Plugins", comment: ""))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("plugin-no-results")
                    }
                }
                if busy || !status.isEmpty {
                    Section {
                        if busy { ProgressView(label("正在处理插件…")) }
                        Text(status).font(.system(size: 12)).textSelection(.enabled)
                    }
                }
            }
        }
        .task { await reload() }
        .overlay {
            if adding { addDialog }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: adding)
        .appDialog(label("安装可信插件"), isPresented: $confirmInstall,
                   message: label("此仓库的插件将能够在本机执行代码。安装表示你信任该来源") + "\n\n" + pendingRepository,
                   buttons: [label("安装"), label("取消")]) { response in
            if response == 0 {
                let source = pendingRepository
                perform("安装插件", selectInstalledRepository: source) { try await manager.install(repository: source) }
            }
        }
        .sheet(item: $editing) { plugin in
            PluginConfigurationEditor(plugin: plugin, manager: manager) { Task { await reload() } }
        }
    }
    private func catalogRow(_ source: String) -> some View {
        HStack(spacing: 12) {
            pluginIcon(repository: source)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(officialName(source))
                    officialTag()
                }
                Text(officialDescription(source)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            SettingsButton(label("安装")) { requestInstall(source) }
                .accessibilityLabel(label("安装"))
                .disabled(busy)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plugin-official-" + source.split(separator: "/").last.map(String.init)!)
    }
    private func officialTag() -> some View {
        Text(label("官方"))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ThemeColor.kTextSubtle)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(ThemeColor.kBackgroundSelected.color(for: scheme), in: Capsule())
    }
    private func installedRow(_ plugin: InstalledPlugin, category: PluginSettingsCategory) -> some View {
        HStack(spacing: 12) {
            pluginIcon(repository: plugin.repository)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(plugin.manifest.name)
                    if plugin.isOfficial { officialTag() }
                }
                pluginSubtitle(plugin)
            }
            Spacer(minLength: 12)
            Toggle(label("启用"), isOn: Binding(get: { plugin.enabled }, set: { value in
                Task { await manager.setEnabled(plugin.id, value); await reload() }
            }))
            .labelsHidden().toggleStyle(.switch).controlSize(.small).fixedSize()
            .accessibilityLabel(label("启用"))
            .accessibilityIdentifier("plugin-enabled-" + category.rawValue + "-" + plugin.id)
            .help(label("启用")).disabled(busy)
            pluginMenu(plugin)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plugin-installed-" + category.rawValue + "-" + plugin.id)
    }
    private func requestInstall(_ url: String) {
        do { pendingRepository = try PluginManager.repositoryURL(url); confirmInstall = true }
        catch { status = error.localizedDescription }
    }
    private func openAddDialog() {
        repository = ""
        repositoryError = ""
        adding = true
    }
    private func installFromDialog() {
        do {
            let source = try PluginManager.repositoryURL(trimmedRepository)
            adding = false
            repository = ""
            repositoryError = ""
            perform("安装插件", selectInstalledRepository: source) { try await manager.install(repository: source) }
        } catch {
            repositoryError = error.localizedDescription
        }
    }
    private var addDialog: some View {
        ZStack {
            Color.clear.ignoresSafeArea()
                .contentShape(Rectangle()).onTapGesture {}
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(label("添加插件")).font(.system(size: 16))
                    Spacer()
                    Button { adding = false } label: {
                        Image(mingCute: "xmark", size: 12)
                            .frame(width: 28, height: 28).contentShape(.circle)
                    }
                    .buttonStyle(.plain).foregroundStyle(ThemeColor.kTextSubtle)
                    .accessibilityLabel(label("关闭"))
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 24) {
                        Text(label("GitHub 仓库链接")).lineLimit(1).fixedSize()
                        Spacer(minLength: 24)
                        SettingsInputField(label("GitHub 仓库链接"), text: $repository)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(SettingsPalette.card(scheme), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("plugin-repository")
                    Text(label("插件会在本机执行代码。请只安装你信任的仓库。"))
                        .font(.system(size: 12)).foregroundStyle(ThemeColor.kTextSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                    if !repositoryError.isEmpty {
                        Text(repositoryError).font(.system(size: 12))
                            .foregroundStyle(ThemeColor.kTextNegative)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    Spacer()
                    SettingsButton(label("取消")) { adding = false }
                    SettingsButton(label("安装")) { installFromDialog() }
                        .disabled(busy || trimmedRepository.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 520)
            .font(.system(size: 14))
            .foregroundStyle(ThemeColor.kText)
            .nativeGlassBackground(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.12), radius: 24, y: 8)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            .onExitCommand { adding = false }
            .accessibilityIdentifier("plugin-add-dialog")
        }
    }
    private func pluginSubtitle(_ plugin: InstalledPlugin) -> some View {
        HStack(spacing: 6) {
            Text(plugin.isOfficial ? "v\(plugin.manifest.version)" : "\(label("自行安装")) · v\(plugin.manifest.version)")
                .foregroundStyle(.secondary)
            if let commands = plugin.manifest.commands, !commands.isEmpty {
                Text(String(format: NSLocalizedString("%d 个命令", tableName: "Plugins", comment: ""), commands.count))
                    .foregroundStyle(.secondary)
            }
            if plugin.needsConfiguration { Text(label("需要配置")).foregroundStyle(.orange) }
        }
        .help(plugin.isOfficial ? "" : plugin.repository)
    }
    private func pluginMenu(_ plugin: InstalledPlugin) -> some View {
        SettingsMoreMenu {
            if !(plugin.manifest.configuration ?? []).isEmpty {
                Button(label("配置")) { editing = plugin }
            }
            Button(label("更新")) { perform("更新插件") { try await manager.install(repository: plugin.repository) } }
            Button(label("回退")) { perform("回退插件") { try await manager.rollback(plugin.id) } }
                .disabled(plugin.previousCommit == nil)
            if let url = URL(string: plugin.repository) {
                Button(label("在 GitHub 查看项目")) { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button(label("卸载"), role: .destructive) { perform("卸载插件") { try await manager.uninstall(plugin.id) } }
        }
        .accessibilityLabel(label("更多操作")).help(label("更多操作")).disabled(busy)
    }
    private func pluginIcon(repository: String) -> some View {
        Group {
            if let icon = icons[repository] {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image("Plugin").resizable().scaledToFit()
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
    private func reload() async {
        let installed = await manager.installed()
        var artwork: [String: NSImage] = [:]
        for source in PluginManager.officialRepositories {
            artwork[source] = ToolService.pluginApplicationIcon(repository: source)
        }
        for plugin in installed {
            if let data = await manager.iconData(for: plugin.id), let image = NSImage(data: data), image.isValid {
                artwork[plugin.repository] = image
            } else {
                artwork[plugin.repository] = ToolService.pluginApplicationIcon(repository: plugin.repository)
            }
        }
        icons = artwork
        plugins = installed
    }
    private func perform(_ title: String, selectInstalledRepository: String? = nil, operation: @escaping () async throws -> Void) {
        busy = true; status = label(title)
        Task {
            var succeeded = false
            do { try await operation(); status = label("操作完成"); succeeded = true }
            catch { status = error.localizedDescription }
            busy = false
            await reload()
            if succeeded, let source = selectInstalledRepository, let plugin = plugins.first(where: { $0.repository == source }) {
                selectedCategory = PluginSettingsCategory.function.includes(plugin.manifest) ? .function : .ai
                query = ""
            }
        }
    }
}
private struct PluginConfigurationEditor: View {
    let plugin: InstalledPlugin
    let manager: PluginManager
    let saved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: JSONValue]
    @State private var error = ""
    init(plugin: InstalledPlugin, manager: PluginManager, saved: @escaping () -> Void) {
        self.plugin = plugin; self.manager = manager; self.saved = saved
        _values = State(initialValue: plugin.configuration)
    }
    var body: some View {
        VStack(alignment: .leading) {
            Text(plugin.manifest.name).font(.headline)
            SettingsForm {
                ForEach(plugin.manifest.configuration ?? []) { field in
                    if field.type == "boolean" {
                        Toggle(field.label, isOn: Binding(get: { values[field.key]?.boolValue ?? false }, set: { values[field.key] = .bool($0) }))
                    } else if field.type == "enum" {
                        LabeledContent(field.label) {
                            SettingsChoice(selection: text(field.key), options: (field.options ?? []).map { ($0, $0) })
                        }
                    } else {
                        SettingsTextField(field.label, text: text(field.key))
                    }
                }
            }.formStyle(.grouped)
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                SettingsButton(NSLocalizedString("取消", comment: "")) { dismiss() }.accessibilityLabel(NSLocalizedString("取消", comment: ""))
                SettingsButton(NSLocalizedString("保存", comment: "")) {
                    Task {
                        do { try await manager.configure(plugin.id, values: values); saved(); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.accessibilityLabel(NSLocalizedString("保存", comment: "")).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 520, height: 360)
    }
    private func text(_ key: String) -> Binding<String> {
        Binding(get: { values[key]?.stringValue ?? "" }, set: { values[key] = .string($0) })
    }
}
