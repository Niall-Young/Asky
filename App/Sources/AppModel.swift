import AppKit
import Contracts
import LocalStore
import ToolService
import AgentHost
import Adapters
import Memory
import MCPGateway
import MCPLink
import DirectActions
import Router

/// Persisted user settings (non-secret). Secrets stay in Keychain.
struct AppSettings: Codable, Equatable, Sendable {
    var enabledSources: Set<DataSourceID> = [.calendar, .reminders, .notes, .contacts, .chrome, .shortcuts, .messages, .memory]
    var fileScopes: [String] = [FileManager.default.homeDirectoryForCurrentUser.path]
    var excludedDirectories: [String] = ["Library", ".Trash", "node_modules", ".git"]
    var notesFolders: [NotesFolder] = []
    var chromeBookmarkFolderAccess: Data?
    var clipboardEnabled = true
    var conversationRetentionDays: Int?
    var conversationRetention: ConversationRetention {
        get { conversationRetentionDays.flatMap(ConversationRetention.init(rawValue:)) ?? .thirtyDays }
        set { conversationRetentionDays = newValue.rawValue }
    }
    var clipboardRetentionHours: Int?
    var clipboardRetention: ClipboardRetention {
        get { clipboardRetentionHours.flatMap(ClipboardRetention.init(rawValue:)) ?? .threeDays }
        set { clipboardRetentionHours = newValue.rawValue }
    }
    var clipboardExcludedApps: [String] = ["com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
                                            "com.apple.keychainaccess", "com.apple.Passwords"]
    /// Optional so settings written before terminal selection still decode without resetting.
    var terminalApplicationID: String?
    var terminalWorkingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    /// Token that enters terminal mode; nil (settings saved before this option) means `>`.
    var terminalKeyword: String?
    var memoryExtractionPaused = false
    var backgroundAI = false
    /// Older settings enable public web search without resetting other source choices.
    var webSearchEnabled: Bool?
    var proactiveReminders = false
    /// Lets background AI read recent SMS/iMessage; nil (settings saved before this option) means off.
    /// Optional so older settings still decode. Also needs Full Disk Access.
    var advisorReadsMessages: Bool?
    /// How many recent days of messages AI may read (3, 7 or 30); nil means the 3-day default.
    var messagesLookbackDays: Int?
    /// Global AI-conversation approval mode; nil (settings saved before this option) means auto review.
    var approvalMode: ApprovalMode?
    /// User-edited AI system prompt; nil uses `NativeAgentPrompt.defaultSystemPrompt`.
    var agentSystemPrompt: String?

    static let key = "app.settings"
    static let messagesLookbackChoices = [3, 7, 30]

    var messagesLookback: Int {
        messagesLookbackDays.flatMap { Self.messagesLookbackChoices.contains($0) ? $0 : nil } ?? 3
    }

    var terminalCommandKeyword: String {
        terminalKeyword.flatMap { LauncherInputState.isValidTerminalKeyword($0) ? $0 : nil }
            ?? LauncherInputState.defaultTerminalKeyword
    }

    var effectiveAgentSystemPrompt: String {
        agentSystemPrompt.flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
        } ?? NativeAgentPrompt.defaultSystemPrompt
    }

    var hasCustomAgentSystemPrompt: Bool {
        guard let prompt = agentSystemPrompt,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return prompt != NativeAgentPrompt.defaultSystemPrompt
    }
}

/// Reads settings straight from SQLite so `@Sendable` policy closures need no main-actor hop.
struct SettingsReader: Sendable {
    let store: LocalStore
    func load() -> AppSettings { store.codableSetting(AppSettings.key, as: AppSettings.self) ?? AppSettings() }
}

enum ModelSettings {
    static let configKey = "model.config"
    static let keyAccount = "model-api-key"
}

@MainActor @Observable
final class AppModel {
    let store: LocalStore
    let tools: ToolService
    let native: NativeTools
    let memory: MemoryFolder
    let gateway: MCPGateway
    let keychain = Keychain()
    let confirmations: ConfirmationCenter
    let exchange: ExchangeRateService
    let terminal: TerminalRunner
    let updater = AppUpdater()
    private(set) var agent: AgentHost?
    private(set) var agentUnavailableReason: String?

    #if DEBUG
    func replaceAgentForTesting(_ host: AgentHost?) {
        agent = host
    }
    #endif
    private var mcpServer: MCPLinkServer?
    private(set) var mcpServerError: String?

    struct CommandEditRequest: Equatable {
        let id: String
        let token = UUID()
    }
    var commandEditRequest: CommandEditRequest?

    func editCommand(_ id: String) {
        commandEditRequest = CommandEditRequest(id: id)
        settingsTab = SettingsPage.keywords.rawValue
        openSettings()
    }

    var settingsTab = SettingsPage.general.rawValue
    let credentialSession = ModelCredentialSession()
    var hotKeyStatus = ""
    var clipboardHotKeyStatus = ""
    var agentHotKeyStatus = ""
    @ObservationIgnored var onHotKeyChange: ((UInt32, UInt32) -> Bool)?
    @ObservationIgnored var onClipboardHotKeyChange: ((UInt32, UInt32) -> Bool)?
    @ObservationIgnored var onAgentHotKeyChange: ((UInt32, UInt32) -> Bool)?
    @ObservationIgnored var onMenuBarIconVisibilityChange: ((Bool) -> Void)?
    @ObservationIgnored var onDockIconVisibilityChange: ((Bool) -> Void)?
    var preferences: SettingsPreferences {
        didSet {
            if preferences.showMenuBarIcon != oldValue.showMenuBarIcon {
                onMenuBarIconVisibilityChange?(preferences.showMenuBarIcon)
            }
            if preferences.showDockIcon != oldValue.showDockIcon {
                onDockIconVisibilityChange?(preferences.showDockIcon)
            }
            if preferences.liquidGlass != oldValue.liquidGlass {
                SurfaceCompatibility.state.liquidGlassEnabled = preferences.liquidGlass
            }
            if preferences.automaticUpdates != oldValue.automaticUpdates {
                updater.setAutomatic(preferences.automaticUpdates)
            }
            if preferences.language != oldValue.language {
                ToolService.setApplicationLanguage(preferences.language)
            }
            store.setCodableSetting(SettingsPreferences.key, preferences)
            NSApp.appearance = preferences.appearance == "system" ? nil : NSAppearance(named: preferences.appearance == "dark" ? .darkAqua : .aqua)
        }
    }
    let launchLanguage: ApplicationLanguage
    @ObservationIgnored var onOpenSettings: (() -> Void)?

    func openSettings(permissions: Bool = false) {
        if permissions { settingsTab = "permissions" }
        onOpenSettings?()
    }

    private(set) var chromeBookmarkAccessState: ChromeBookmarkService.AccessState?

    @discardableResult
    func refreshChromeBookmarkAccess() async -> ChromeBookmarkService.AccessState {
        let access = settings.chromeBookmarkFolderAccess
        let state = await Task.detached(priority: .userInitiated) {
            ChromeBookmarkService.accessState(accessBookmark: access)
        }.value
        guard !Task.isCancelled, access == settings.chromeBookmarkFolderAccess else {
            return chromeBookmarkAccessState ?? .denied
        }
        chromeBookmarkAccessState = state
        return state
    }

    func authorizeChromeBookmarkFolder() async {
        guard let access = await ToolService.chooseChromeBookmarkFolder() else { return }
        settings.chromeBookmarkFolderAccess = access
        await refreshChromeBookmarkAccess()
    }

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            store.setCodableSetting(AppSettings.key, settings)
            if settings.clipboardRetention != oldValue.clipboardRetention {
                ClipboardMonitor.cleanup(clipboardStore)
            }
            if settings.conversationRetention != oldValue.conversationRetention {
                Task { await maintainConversationHistory() }
            }
            onSettingsChange?()
        }
    }
    @ObservationIgnored private var historyCleanupTask: Task<Void, Never>?
    private var historyOperations = 0
    @ObservationIgnored var activeConversationIDs: Set<String> = []
    @ObservationIgnored var conversationDraftPaths: (() -> Set<String>)?
    @ObservationIgnored var onConversationHistoryDeleted: ((Set<String>) -> Void)?
    private(set) var conversationCleanupError: String?
    var isCleaningConversationHistory: Bool { historyOperations > 0 }
    let conversationHistory: ConversationHistoryService

    func maintainConversationHistory(now: Date = Date()) async {
        historyOperations += 1
        defer { historyOperations -= 1 }
        do {
            let protected = activeConversationIDs.union(await tools.activeAgentSessionIDs)
            guard protected.isEmpty else { return }
            let result = try await conversationHistory.cleanup(retention: settings.conversationRetention,
                protecting: protected, draftPaths: conversationDraftPaths?() ?? [], now: now)
            await historyDidDelete(result)
        } catch {
            conversationCleanupError = NSLocalizedString("对话历史清理失败，将自动重试。", comment: "")
        }
    }

    @discardableResult func deleteConversationHistory(_ id: String) async -> Bool {
        historyOperations += 1
        defer { historyOperations -= 1 }
        do {
            let protected = activeConversationIDs.union(await tools.activeAgentSessionIDs)
            guard !protected.contains(id) else {
                conversationCleanupError = NSLocalizedString("对话仍有任务正在执行，请稍后重试。", comment: "")
                return false
            }
            let result = try await conversationHistory.delete(id, protecting: protected,
                draftPaths: conversationDraftPaths?() ?? [])
            await historyDidDelete(result)
            return result.pendingFiles == 0
        } catch {
            conversationCleanupError = NSLocalizedString("对话历史清理失败，将自动重试。", comment: "")
            return false
        }
    }

    func deleteConversationRound(_ message: StoredMessage) async {
        guard !isCleaningConversationHistory else { return }
        historyOperations += 1
        defer { historyOperations -= 1 }
        let protected = activeConversationIDs.union(await tools.activeAgentSessionIDs)
        guard protected.isEmpty else { return }
        do {
            await historyDidDelete(try await conversationHistory.deleteRound(message, protecting: protected,
                draftPaths: conversationDraftPaths?() ?? []))
        } catch { conversationCleanupError = NSLocalizedString("对话历史清理失败，将自动重试。", comment: "") }
    }

    @discardableResult func deleteConversationMessage(_ message: StoredMessage) async -> Bool {
        guard !isCleaningConversationHistory else { return false }
        historyOperations += 1
        defer { historyOperations -= 1 }
        let protected = activeConversationIDs.union(await tools.activeAgentSessionIDs)
        guard protected.isEmpty else {
            conversationCleanupError = NSLocalizedString("对话仍有任务正在执行，请稍后重试。", comment: "")
            return false
        }
        do {
            await historyDidDelete(try await conversationHistory.deleteMessage(message, protecting: protected,
                draftPaths: conversationDraftPaths?() ?? []))
            return true
        } catch {
            conversationCleanupError = NSLocalizedString("对话历史清理失败，将自动重试。", comment: "")
            return false
        }
    }

    func clearConversationHistory() async {
        guard !isCleaningConversationHistory else { return }
        let alert = AppDialog.make()
        alert.messageText = NSLocalizedString("清空对话历史？", comment: "")
        alert.informativeText = NSLocalizedString("删除全部聊天和附件，保留已保存的长期记忆。", comment: "")
        let confirm = alert.addButton(withTitle: NSLocalizedString("清空", comment: ""))
        confirm.hasDestructiveAction = true
        confirm.keyEquivalent = "\r"
        alert.addButton(withTitle: NSLocalizedString("取消", comment: "")).keyEquivalent = "\u{1b}"
        guard await AppDialog.present(alert) == .alertFirstButtonReturn else { return }
        historyOperations += 1
        defer { historyOperations -= 1 }
        let protected = activeConversationIDs.union(await tools.activeAgentSessionIDs)
        guard protected.isEmpty else {
            conversationCleanupError = NSLocalizedString("对话仍有任务正在执行，请稍后重试。", comment: "")
            return
        }
        do { await historyDidDelete(try await conversationHistory.clear(draftPaths: conversationDraftPaths?() ?? [])) }
        catch { conversationCleanupError = NSLocalizedString("对话历史清理失败，将自动重试。", comment: "") }
    }

    private func historyDidDelete(_ result: ConversationHistoryService.CleanupResult) async {
        conversationCleanupError = result.pendingFiles > 0
            ? NSLocalizedString("部分对话文件未能清理，将自动重试。", comment: "") : nil
        await agent?.forgetSessions(result.deletedIDs)
        onConversationHistoryDeleted?(result.deletedIDs)
    }

    var clipboardStore: ClipboardStore { ClipboardStore(store, retention: settings.clipboardRetention) }
    @ObservationIgnored var onSettingsChange: (() -> Void)?
    @ObservationIgnored var onModelAuthenticationFinished: (() -> Void)?
    @ObservationIgnored var onModelAuthenticationStarted: (() -> Void)?
    /// Stable preset identities keep enablement independent of custom trigger tokens.
    var keywords: KeywordRegistry {
        KeywordRegistry(disabledCommands: preferences.disabledBuiltInCommands,
                        triggerKeywords: preferences.commandKeywords)
    }

    static let searchCommands = [("colorPicker", "屏幕取色", "co"), ("tabs", "搜索开启的标签页", "st"), ("bookmark", "搜索书签", "bm"), ("link", "搜索链接", "link"), ("ai", "AI 搜索", "ai")] + LauncherFilter.commands

    func commandKeyword(_ id: String) -> String {
        preferences.commandKeywords[id]
            ?? Self.searchCommands.first(where: { $0.0 == id })?.2 ?? id
    }

    func isSearchCommandEnabled(_ id: String) -> Bool {
        !preferences.disabledSearchCommands.contains(id)
    }

    func commandKeywordProblem(_ value: String, id: String) -> String? {
        guard !value.isEmpty, !value.contains(where: \.isWhitespace) else {
            return NSLocalizedString("指令不能为空或包含空格。", comment: "")
        }
        let ids = KeywordCommand.builtIn.map(\.keyword) + Self.searchCommands.map { $0.0 }
        if value.caseInsensitiveCompare(settings.terminalCommandKeyword) == .orderedSame
            || ids.contains(where: { $0 != id && commandKeyword($0).caseInsensitiveCompare(value) == .orderedSame })
            || preferences.aliases.contains(where: { $0.alias.caseInsensitiveCompare(value) == .orderedSame }) {
            return NSLocalizedString("该指令与已有指令或别名重名。", comment: "")
        }
        return nil
    }

    /// Apply the fresh-install default once; never re-enable a user's disabled login item.
    func initializeLaunchAtLogin(register: () throws -> Void = { try ToolService.enableDefaultLaunchAtLogin() }) throws {
        guard !preferences.hasInitializedLoginItem else { return }
        try register()
        preferences.hasInitializedLoginItem = true
    }

    init(root: URL = LocalStore.defaultRoot) throws {
        AppDialogPresenter.installIfNeeded()
        let store = try LocalStore(root: root)
        self.store = store
        conversationHistory = ConversationHistoryService(store: store)
        let reader = SettingsReader(store: store)
        settings = reader.load()
        let savedPreferences = store.codableSetting(SettingsPreferences.key, as: SettingsPreferences.self) ?? SettingsPreferences()
        preferences = savedPreferences
        SurfaceCompatibility.state.liquidGlassEnabled = savedPreferences.liquidGlass
        launchLanguage = savedPreferences.language

        let confirmations = ConfirmationCenter()
        self.confirmations = confirmations
        memory = MemoryFolder(store)
        memory.migrateLegacy(store)
        let instances = MCPInstanceStore(store)
        tools = ToolService(store: store, policy: {
            let s = reader.load()
            return PolicySnapshot(enabledSources: s.enabledSources.union(s.webSearchEnabled == false ? [.plugins] : [.plugins, .web]),
                                  mcpInstances: Dictionary(uniqueKeysWithValues: instances.all().map { ($0.id, $0) }),
                                  approvalMode: s.approvalMode ?? .autoReview)
        }, presenter: { request in await confirmations.present(request) },
           pluginRuntime: .legacyCompatibility(bundleResources: Bundle.main.resourceURL),
           authorize: { source, origin in try await SystemPermissions.require(source, origin: origin) })
        native = NativeTools(notesFolders: { reader.load().notesFolders },
                             messagesEnabled: {
                                 let s = reader.load()
                                 return s.advisorReadsMessages == true && s.enabledSources.contains(.messages)
                             },
                             messagesDays: { reader.load().messagesLookback },
                             contactsEnabled: { reader.load().enabledSources.contains(.contacts) })
        gateway = MCPGateway(store: store, tools: tools)
        exchange = ExchangeRateService(cacheURL: store.root.appending(path: "ecb-rates.json"))
        terminal = TerminalRunner(spillDirectory: store.outputDirectory)
    }

    func start() async {
        Task { [exchange] in await ToolService.prefetchLauncherCurrency(service: exchange) }
        await native.register(into: tools, memory: memory)
        await tools.register(HistoryTool(store: store))
        await tools.register(HistoryTool(store: store, reading: true))
        agent = makeAgentHost()
        refreshMCPServer()
        ClipboardMonitor.cleanup(clipboardStore)
        _ = try? ActivityStore(store).purgeExpired()
        await maintainConversationHistory()
        historyCleanupTask?.cancel()
        historyCleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(86400)) } catch { return }
                guard let self else { return }
                await self.maintainConversationHistory()
            }
        }
        updater.setAutomatic(preferences.automaticUpdates)
    }

    func shutdown() async {
        historyCleanupTask?.cancel()
        historyCleanupTask = nil
        updater.setAutomatic(false)
        updater.installOnQuit()
        mcpServer?.stop()
        await agent?.shutdown()
    }

    // MARK: Agent runtime

    private func makeAgentHost() -> AgentHost? {
        let storage = AgentSessionStorage(root: store.root.appending(path: "runtime"))
        let store = store, tools = tools
        return AgentHost(launcher: { NativeRuntime(storage: storage) }, configProvider: { [weak self] in
            guard let cfg = store.codableSetting(ModelSettings.configKey, as: ModelConfiguration.self) else { return nil }
            guard let self else { return nil }
            let key = try await self.readModelCredential(account: cfg.credentialRef)
            guard let key, !key.isEmpty else { throw AgentHostError.credentialMissing }
            return RuntimeLaunchConfig(baseURL: cfg.baseURL.absoluteString, model: cfg.modelName, apiKey: key)
        }, toolsProvider: {
            await tools.definitions(for: .agent(sessionID: ""))
        }, guidanceProvider: { await tools.plugins.guidance() }, systemPromptProvider: {
            SettingsReader(store: store).load().agentSystemPrompt
        }, toolHandler: { request in
            await tools.submit(request)
        })
    }

    func readModelCredential(account: String) async throws -> String? {
        try await credentialSession.read(account: account, keychain: keychain,
            started: { [weak self] in await MainActor.run { self?.onModelAuthenticationStarted?() } },
            finished: { [weak self] in await MainActor.run { self?.onModelAuthenticationFinished?() } })
    }

    var modelConfiguration: ModelConfiguration? {
        get { store.codableSetting(ModelSettings.configKey, as: ModelConfiguration.self) }
        set { if let newValue { store.setCodableSetting(ModelSettings.configKey, newValue) } else { store.setSetting(ModelSettings.configKey, nil) } }
    }

    var isModelConfigured: Bool {
        guard let cfg = modelConfiguration else { return false }
        return keychain.contains(account: cfg.credentialRef)
    }

    // MARK: External MCP

    /// The link socket only listens while at least one instance is enabled.
    func refreshMCPServer() {
        let anyEnabled = MCPInstanceStore(store).all().contains { $0.enabled }
        if anyEnabled, mcpServer == nil {
            let server = MCPLinkServer(gateway: gateway)
            do {
                try server.start()
                mcpServer = server
                mcpServerError = nil
            } catch {
                mcpServerError = String(format: NSLocalizedString("本地连接启动失败：%@", comment: ""), String(describing: error))
            }
        } else if !anyEnabled, let server = mcpServer {
            server.stop()
            mcpServer = nil
        }
    }

    var isMCPListening: Bool { mcpServer != nil }
    /// External MCP clients are mid-request, or were within the last two minutes.
    var isMCPBusy: Bool { mcpServer?.isBusy(within: 120) == true }

    static var bridgeExecutablePath: String {
        Bundle.main.bundleURL.appending(path: "Contents/MacOS/asky-mcp").path
    }
}
