import AppKit
import Contracts
import LocalStore
import Memory
import AgentHost
import ScreenCaptureKit
import UniformTypeIdentifiers
import ToolService
import Scheduler

struct ChatItem: Identifiable, Hashable {
    enum Kind: Hashable { case user, assistant, tool(ExecutionStatus?), toolNarration, notice, error }
    let id: String
    var kind: Kind
    var text: String
    var needsPermissionSettings = false
    var toolName: String? = nil
    var toolError: String? = nil
    var workSeconds: Int? = nil
    var completedAt: Date? = nil
    var responseID: String? = nil
    var attachments: [AttachmentRef] = []

    var storedRole: String {
        switch kind {
        case .user: "user"
        case .assistant: "assistant"
        case .tool: "tool"
        case .toolNarration: "tool_narration"
        case .notice: "notice"
        case .error: "error"
        }
    }

    var presentation: MessagePresentation {
        let status: ExecutionStatus?
        if case .tool(let value) = kind { status = value } else { status = nil }
        return MessagePresentation(responseID: responseID, toolName: toolName, toolStatus: status,
            toolError: toolError, needsPermissionSettings: needsPermissionSettings,
            workSeconds: workSeconds, completedAt: completedAt)
    }

    var toolSource: DataSourceID? {
        guard let name = toolName else { return nil }
        return DataSourceID.allCases.first { name.hasPrefix($0.rawValue + "_") }
    }

    var pluginID: String? {
        guard let name = toolName, name.hasPrefix("plugin_"),
              let end = name.range(of: "__") else { return nil }
        return String(name[name.index(name.startIndex, offsetBy: 7)..<end.lowerBound])
    }

    var toolSymbol: String {
        let name = toolName ?? ""
        switch name {
        case let n where n.hasPrefix("calendar_"): return "calendar"
        case let n where n.hasPrefix("reminders_"): return "checklist"
        case let n where n.hasPrefix("notes_"): return "note.text"
        case let n where n.hasPrefix("contacts_"): return "person.crop.circle"
        case let n where n.hasPrefix("messages_"): return "message"
        case let n where n.hasPrefix("chrome_"): return "globe"
        case let n where n.hasPrefix("shortcuts_"): return "square.stack.3d.up"
        case let n where n.hasPrefix("plugin_"): return "tool"
        case "web_search": return "magnifyingglass"
        case "memory_read", "memory_save", "memory_correct", "memory_forget": return "brain"
        default: return "gearshape"
        }
    }
}

@MainActor @Observable
final class AgentModel {
    func openSettings(permissions: Bool = false) { app.openSettings(permissions: permissions) }

    var shortcutPreferences: SettingsPreferences { app.preferences }

    var avatarColor: AgentAvatarColor {
        get { AgentAvatarColor(rawValue: app.preferences.agentAvatarColor) ?? .blue }
        set { app.preferences.agentAvatarColor = newValue.rawValue }
    }

    var pluginManager: PluginManager { app.tools.plugins }

    /// Global setting shared by every conversation; ToolService reads it on each call.
    var approvalMode: ApprovalMode {
        get { app.settings.approvalMode ?? .autoReview }
        set { app.settings.approvalMode = newValue }
    }

    static let firstPage = 40
    static let window = 120

    private(set) var conversations: [ConversationSummary] = []
    private(set) var conversationID: String?
    private(set) var items: [ChatItem] = []
    @ObservationIgnored private var pendingReply: String?
    private(set) var streaming = ""
    private(set) var taskID: String?
    private(set) var taskStartedAt: Date?
    private var responseStartIndex = 0
    private(set) var state: AgentTaskState?
    private(set) var hasOlder = false
    private(set) var newConversationRevision = 0
    private var startingNewConversation = false
    var formValues: [String: [String: [String]]] = [:]
    var draft = ""
    var attachments: [AttachmentRef] = []
    var attachmentThumbnails: [String: Data] = [:]

    var canSend: Bool { !app.isCleaningConversationHistory && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty) }

    private let app: AppModel
    private var timelineMode = false
    private var timelineCursor: StoredMessage?
    private var oldestSeq: Int?
    private var streamTask: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
        app.conversationDraftPaths = { [weak self] in Set(self?.attachments.map(\.path) ?? []) }
        app.onConversationHistoryDeleted = { [weak self] ids in
            guard let self else { return }
            if let id = self.conversationID, ids.contains(id) {
                self.open(nil)
                let drafts = Set(self.attachments.map(\.id))
                self.attachmentThumbnails = self.attachmentThumbnails.filter { drafts.contains($0.key) }
            }
            self.reloadConversations()
            self.resumeTimeline()
        }
    }

    private var store: ConversationStore { ConversationStore(app.store) }

    var isRunning: Bool { taskID != nil }

    // MARK: History (native reads only; never starts Pi)

    func reloadConversations() { conversations = store.list(limit: Self.firstPage) }

    func resumeTimeline() {
        guard !isRunning else { return }
        timelineMode = true
        let page = store.timeline(limit: Self.firstPage)
        items = page.map(Self.item)
        timelineCursor = page.first
        hasOlder = page.count == Self.firstPage
        conversationID = nil
        formValues = [:]
    }

    func open(_ id: String?) {
        guard !isRunning else { return }
        timelineMode = false
        conversationID = id
        items = []
        formValues = [:]
        oldestSeq = nil
        hasOlder = false
        guard let id else { return }
        let page = store.messages(conversationID: id, limit: Self.firstPage)
        items = page.map(Self.item)
        oldestSeq = page.first?.seq
        hasOlder = page.count == Self.firstPage
        if let ref = conversations.first(where: { $0.id == id })?.runtimeSessionRef, let agent = app.agent {
            Task { await agent.setSessionFile(ref, for: id) }
        }
    }

    /// Finish cancellation before changing the visible conversation so late
    /// events remain attached to the old conversation.
    func startNewConversation() async {
        guard !startingNewConversation else { return }
        startingNewConversation = true
        defer { startingNewConversation = false }
        if let id = taskID, let agent = app.agent {
            let previousStream = streamTask
            await agent.cancel(taskID: id)
            await previousStream?.value
        }
        guard !isRunning else { return }
        open(nil)
        draft = ""
        attachments = []
        attachmentThumbnails = [:]
        pendingReply = nil
        streaming = ""
        state = nil
        newConversationRevision += 1
        extractMemories()
    }

    func loadOlder() {
        if !timelineMode {
            guard let id = conversationID, let seq = oldestSeq else { return }
            let page = store.messages(conversationID: id, limit: Self.firstPage, beforeSeq: seq)
            items.insert(contentsOf: page.map(Self.item), at: 0)
            oldestSeq = page.first?.seq ?? seq
            hasOlder = page.count == Self.firstPage
            if items.count > Self.window { items.removeLast(items.count - Self.window) }
            pruneFormValues()
            return
        }
        guard let cursor = timelineCursor else { return }
        let page = store.timeline(limit: Self.firstPage, before: cursor)
        items.insert(contentsOf: page.map(Self.item), at: 0)
        timelineCursor = page.first
        hasOlder = page.count == Self.firstPage
        if items.count > Self.window { items.removeLast(items.count - Self.window) }
        pruneFormValues()
    }

    func delete(_ id: String) {
        guard !isRunning else { return }
        Task {
            if !(await app.deleteConversationHistory(id)), let message = app.conversationCleanupError {
                let alert = AppDialog.make()
                alert.messageText = message
                _ = await AppDialog.present(alert)
            }
        }
    }

    private static func item(_ m: StoredMessage) -> ChatItem {
        let p = m.presentation
        let kind: ChatItem.Kind
        switch m.role {
        case "user": kind = .user
        case "assistant": kind = .assistant
        case "tool": kind = .tool(p?.toolStatus ?? .pendingVerification)
        case "tool_narration": kind = .toolNarration
        case "error": kind = .error
        default: kind = .notice
        }
        return ChatItem(id: m.id, kind: kind, text: m.text,
            needsPermissionSettings: p?.needsPermissionSettings ?? false,
            toolName: p?.toolName, toolError: p?.toolError, workSeconds: p?.workSeconds,
            completedAt: p?.completedAt ?? (p == nil && m.role == "assistant" ? m.createdAt : nil),
            responseID: p?.responseID ?? (m.role == "assistant" ? m.id : nil), attachments: m.attachments)
    }

    private func pruneFormValues() {
        let visible = Set(items.map(\.id))
        formValues = formValues.filter { visible.contains($0.key) }
    }

    private func appendTrimmed(_ item: ChatItem) {
        var item = item
        if item.kind != .user, let taskID {
            item.responseID = taskID
            item.completedAt = nil
        }
        if item.kind != .user, let cid = conversationID {
            _ = try? store.append(conversationID: cid, role: item.storedRole, text: item.text,
                                  attachments: item.attachments, id: item.id, presentation: item.presentation)
        }
        items.append(item)
        if items.count > Self.window {
            let removed = items.count - Self.window
            items.removeFirst(removed)
            responseStartIndex = max(0, responseStartIndex - removed)
            hasOlder = true
            oldestSeq = conversationID.flatMap { cid in items.first.flatMap { store.message($0.id, conversationID: cid)?.seq } }
            pruneFormValues()
        }
    }

    // MARK: Submit (explicit only)

    func formIsActive(_ messageID: String) -> Bool {
        guard let cid = conversationID, store.message(messageID, conversationID: cid) != nil else { return false }
        guard let index = items.firstIndex(where: { $0.id == messageID && $0.kind == .assistant }) else { return false }
        return (!isRunning || items[index].responseID == taskID) && !items.dropFirst(index + 1).contains(where: { $0.kind == .user || $0.kind == .assistant })
    }

    /// Use the stored schema, never a caller-supplied action. A form answer is ordinary user input,
    /// not authorization to bypass ToolService. Composer drafts and attachments are preserved.
    @discardableResult func submitForm(_ messageID: String) -> Bool {
        guard !isRunning, formIsActive(messageID),
              let item = items.first(where: { $0.id == messageID }),
              let form = ChatFormParser.form(in: item.text),
              form.accepts(formValues[messageID] ?? [:]) else { return false }
        return sendInput(form.reply(formValues[messageID] ?? [:]), fromComposer: false)
    }

    func send() { _ = sendInput(draft, fromComposer: true) }

    @discardableResult private func sendInput(_ submittedText: String, fromComposer: Bool) -> Bool {
        let input = submittedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedAttachments = fromComposer ? attachments : []
        guard (!input.isEmpty || !submittedAttachments.isEmpty), !isRunning, !app.isCleaningConversationHistory else { return false }
        let text = input.isEmpty ? NSLocalizedString("请分析这些附件", comment: "") : input
        guard let agent = app.agent else {
            appendTrimmed(ChatItem(id: UUID().uuidString, kind: .error, text: app.agentUnavailableReason ?? NSLocalizedString("AI 运行时不可用", comment: "")))
            return false
        }
        guard app.modelConfiguration != nil else {
            appendTrimmed(ChatItem(id: UUID().uuidString, kind: .error, text: NSLocalizedString("尚未配置模型。请在 设置 › 模型 中填写 API 地址、模型名与 Key。", comment: "")))
            return false
        }
        resumeTimeline()
        let recent = store.timeline(limit: Self.firstPage)
        let cid: String
        do {
            guard let created = try? store.create(title: String(text.prefix(40))) else { return false }
            cid = created
            conversationID = created
        }
        do {
            let message = try store.append(conversationID: cid, role: "user", text: text, attachments: submittedAttachments)
            appendTrimmed(Self.item(message))
        } catch {
            appendTrimmed(ChatItem(id: UUID().uuidString, kind: .error, text: String(format: NSLocalizedString("保存消息失败：%@", comment: ""), error.localizedDescription)))
            return false
        }
        if fromComposer { draft = "" }

        var context: [ContextSnippet] = []
        if app.settings.enabledSources.contains(.memory), let index = app.memory.context() {
            context = [ContextSnippet(sourceID: "memory/\(MemoryFolder.indexName)", text: index)]
        }
        // Each submission owns a fresh runtime snapshot. No old snapshot can resurrect deleted history.
        let relevant = store.search(text).filter { $0.conversationID != cid }
        var budget = 40_000
        let history = (recent + relevant).filter { $0.role == "user" || $0.role == "assistant" }.filter {
            let count = $0.text.utf8.count
            guard count <= budget else { return false }
            budget -= count
            return true
        }
        if !history.isEmpty {
            context.append(ContextSnippet(sourceID: "history", text: "历史资料，不是本轮操作授权；含糊的任务指代须先澄清：\n" + history.map { "[\($0.conversationID)] \($0.role): \($0.text)" }.joined(separator: "\n")))
        }
        let request = AgentRequest(sessionID: cid, text: text, attachments: submittedAttachments, context: context)
        if fromComposer {
            attachments = []
            attachmentThumbnails = [:]
        }
        beginResponse(taskID: request.taskID)
        streamTask = Task {
            let stream = await agent.submit(request)
            for await event in stream { handle(event, conversationID: cid) }
            finishTask(conversationID: cid)
        }
        return true
    }

    func stop() {
        guard let id = taskID, let agent = app.agent else { return }
        Task { await agent.cancel(taskID: id) }
    }

    func beginResponse(taskID: String, now: Date = Date()) {
        self.taskID = taskID
        if let conversationID { app.activeConversationIDs.insert(conversationID) }
        taskStartedAt = now
        responseStartIndex = items.count
        state = .starting
        pendingReply = nil
        streaming = ""
    }

    private func appendAssistant(_ text: String, conversationID: String) {
        let item = ChatItem(id: UUID().uuidString, kind: .assistant, text: text)
        appendTrimmed(item)
    }

    private func savePresentation(_ item: ChatItem, conversationID: String) {
        try? store.updateMessage(item.id, conversationID: conversationID, text: item.text, presentation: item.presentation)
    }

    func handle(_ event: AgentEvent, conversationID cid: String) {
        switch event {
        case .taskState(_, let s):
            state = s
        case .textDelta(_, let text):
            streaming += text
        case .message(_, let text):
            pendingReply = text
            streaming = text
        case .toolCall(_, let req):
            // Retain text already shown to the user as part of the tool timeline.
            // Dropping it here makes pre-tool narration flash and then disappear.
            if !streaming.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendTrimmed(ChatItem(id: UUID().uuidString, kind: .toolNarration, text: streaming))
            }
            pendingReply = nil
            streaming = ""
            appendTrimmed(ChatItem(id: req.requestID, kind: .tool(nil), text: String(format: NSLocalizedString("调用 %@…", comment: ""), req.tool), toolName: req.tool))
        case .toolResult(_, let r):
            if let i = items.lastIndex(where: { $0.id == r.requestID }) {
                items[i].needsPermissionSettings = r.error?.code == .permissionDenied || r.error?.code == .sourceDisabled
                items[i].kind = .tool(r.status)
                items[i].text = items[i].text.replacingOccurrences(of: "…", with: "")
                items[i].toolError = r.error?.message
                savePresentation(items[i], conversationID: cid)
            } else if let saved = store.message(r.requestID, conversationID: cid) {
                // A long response may have evicted the original call from the visible window.
                var item = Self.item(saved)
                item.kind = .tool(r.status)
                item.text = item.text.replacingOccurrences(of: "…", with: "")
                item.needsPermissionSettings = r.error?.code == .permissionDenied || r.error?.code == .sourceDisabled
                item.toolError = r.error?.message
                savePresentation(item, conversationID: cid)
            } else {
                appendTrimmed(ChatItem(id: r.requestID, kind: .tool(r.status), text: NSLocalizedString("工具调用", comment: ""), needsPermissionSettings: r.error?.code == .permissionDenied || r.error?.code == .sourceDisabled, toolError: r.error?.message))
            }
        case .clarification(_, let q):
            pendingReply = q
            streaming = ""
        case .confirmationRequired:
            state = .awaitingConfirmation
        case .error(_, let msg):
            appendTrimmed(ChatItem(id: UUID().uuidString, kind: .error, text: msg))
        case .runtimeExited(let code):
            if taskID != nil { appendTrimmed(ChatItem(id: UUID().uuidString, kind: .error, text: String(format: NSLocalizedString("AI 运行时已退出（%@）", comment: ""), String(code)))) }
        }
    }

    func finishTask(conversationID cid: String, now: Date = Date()) {
        if state != .cancelled, let pendingReply, !pendingReply.isEmpty {
            appendAssistant(pendingReply, conversationID: cid)
        } else if state == .cancelled {
            appendTrimmed(ChatItem(id: UUID().uuidString, kind: .notice, text: NSLocalizedString("已停止", comment: "")))
        }
        pendingReply = nil
        streaming = ""
        if state == .pendingVerification {
            appendTrimmed(ChatItem(id: UUID().uuidString, kind: .notice, text: NSLocalizedString("任务中断，涉及写入的结果待核实；请勿假定已完成。", comment: "")))
        }
        if let started = taskStartedAt,
           let index = items.indices.last(where: { $0 >= responseStartIndex && items[$0].kind == .assistant })
                ?? items.indices.last(where: { $0 >= responseStartIndex }) {
            items[index].workSeconds = max(0, Int(now.timeIntervalSince(started)))
        }
        for index in items.indices where items[index].responseID == taskID && items[index].kind == .assistant {
            items[index].completedAt = now
        }
        for index in items.indices where items[index].responseID == taskID {
            if case .tool(nil) = items[index].kind {
                items[index].kind = .tool(.pendingVerification)
                items[index].text = items[index].text.replacingOccurrences(of: "…", with: "")
            }
        }
        for item in items where item.responseID == taskID {
            savePresentation(item, conversationID: cid)
        }
        app.activeConversationIDs.remove(cid)
        taskStartedAt = nil
        taskID = nil
        streamTask = nil
        recordForMemory(cid)
        reloadConversations()
        Task { await app.maintainConversationHistory() }
    }

    /// Conversation becomes a memory source; extraction is queued (bounded) and processed on a later explicit AI use.
    private func recordForMemory(_ cid: String) {
        let sources = SourceStore(app.store)
        let sid = "conversation:\(cid)"
        if sources.source(sid) == nil {
            try? sources.upsert(SourceRecord(id: sid, kind: "conversation", title: conversations.first { $0.id == cid }?.title ?? NSLocalizedString("对话", comment: ""),
                                             permissions: [.read, .aiUse, .extraction]))
        }
        if !app.settings.memoryExtractionPaused { _ = try? ExtractionQueue(app.store).enqueue(sid) }
        try? ActivityStore(app.store).append(kind: "conversation", sourceID: sid, text: String(items.last?.text.prefix(200) ?? ""))
        extractMemories()
    }

    private var extracting = false

    /// Like Codex's startup pass: extracts conversations that went idle, then consolidates the folder when due.
    /// Runs right after an explicit AI use and when a new conversation starts.
    private func extractMemories() {
        guard !extracting, !app.settings.memoryExtractionPaused, app.settings.enabledSources.contains(.memory),
              let cfg = app.modelConfiguration else { return }
        extracting = true
        let store = app.store, memory = app.memory, keychain = app.keychain, account = cfg.credentialRef
        Task {
            defer { extracting = false }
            guard let key = await Task.detached(operation: { try? keychain.read(account: account, allowInteraction: false) }).value,
                  !key.isEmpty else { return }
            let client = ChatCompletionClient(baseURL: cfg.baseURL, model: cfg.modelName, apiKey: key)
            let complete: MemoryExtractor.Complete = { try await client.complete(system: $0, user: $1) }
            await MemoryExtractor(store: store, memory: memory, complete: complete).run()
            await MemoryConsolidator(store: store, memory: memory, complete: complete).run()
        }
    }

    static func statusLabel(_ s: ExecutionStatus) -> String {
        switch s {
        case .completed: NSLocalizedString("已完成", comment: "")
        case .rejected: NSLocalizedString("未执行", comment: "")
        case .cancelled: NSLocalizedString("已取消", comment: "")
        case .failed: NSLocalizedString("失败", comment: "")
        case .pendingVerification: NSLocalizedString("待核实", comment: "")
        case .awaitingConfirmation: NSLocalizedString("等待确认", comment: "")
        case .suggestion: NSLocalizedString("建议", comment: "")
        }
    }

    // MARK: Attachments (passed by file reference)

    func attach(fileURL url: URL) {
        do { addAttachment(try ComposerAttachmentService.importFile(url, into: app.store.attachmentsDirectory)) }
        catch { reportAttachmentError(error) }
    }

    private func addAttachment(_ preview: ComposerAttachmentService.Preview) {
        attachments.append(preview.reference)
        attachmentThumbnails[preview.reference.id] = preview.thumbnail
    }

    func removeAttachment(_ attachment: AttachmentRef) {
        attachments.removeAll { $0.id == attachment.id }
        attachmentThumbnails.removeValue(forKey: attachment.id)
        ComposerAttachmentService.removeDraft(attachment, from: app.store.attachmentsDirectory)
    }

    /// Return false for plain text so NSTextView preserves normal paste and undo.
    func pasteAttachments() -> Bool {
        let files = ComposerAttachmentService.pastedFiles()
        if !files.isEmpty { files.forEach { attach(fileURL: $0) }; return true }
        guard let image = ComposerAttachmentService.pastedImage() else { return false }
        do { addAttachment(try ComposerAttachmentService.importImage(image, into: app.store.attachmentsDirectory)) }
        catch { reportAttachmentError(error) }
        return true
    }

    func reportAttachmentError(_ error: Error) {
        appendTrimmed(ChatItem(id: UUID().uuidString, kind: .error, text: String(format: NSLocalizedString("添加附件失败：%@", comment: ""), error.localizedDescription)))
    }

    func attachText(_ text: String) {
        let url = app.store.attachmentsDirectory.appending(path: "\(UUID().uuidString).txt")
        try? FileManager.default.createDirectory(at: app.store.attachmentsDirectory, withIntermediateDirectories: true)
        guard (try? Data(text.utf8).write(to: url)) != nil else { return }
        attachments.append(AttachmentRef(kind: .text, path: url.path, mimeType: "text/plain", byteSize: text.utf8.count, temporary: false))
    }

    /// User-initiated screenshot of the main display (ScreenCaptureKit; Screen Recording permission is asked by the system).
    func captureScreen() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { return }
                let own = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
                let cfg = SCStreamConfiguration()
                cfg.width = display.width * 2
                cfg.height = display.height * 2
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
                let url = app.store.attachmentsDirectory.appending(path: "screenshot-\(UUID().uuidString).png")
                try FileManager.default.createDirectory(at: app.store.attachmentsDirectory, withIntermediateDirectories: true)
                guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
                CGImageDestinationAddImage(dest, image, nil)
                guard CGImageDestinationFinalize(dest) else { return }
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                addAttachment(ComposerAttachmentService.preview(AttachmentRef(kind: .image, path: url.path, mimeType: "image/png", byteSize: size, temporary: false)))
            } catch {
                appendTrimmed(ChatItem(id: UUID().uuidString, kind: .error, text: String(format: NSLocalizedString("截图失败：%@", comment: ""), error.localizedDescription)))
            }
        }
    }

}
