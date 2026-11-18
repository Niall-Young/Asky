import AppKit
import EventKit
import Contracts
import LocalStore
import Memory
import Scheduler
import ToolService

/// Wires the Context Scheduler to EventKit change notifications, wake / time-zone changes and an hourly checkpoint,
/// and delivers plans as silent Asky reminder cards. Runs only while `proactiveReminders` is on.
/// With background AI on, the configured model also looks across events, open tasks and memories for things
/// worth preparing, and, when separately allowed, recent SMS/iMessage; its suggestions go through the same
/// dedupe, daily cap and quiet-hours rules.
@MainActor
final class ProactiveReminders: NSObject {
    private let app: AppModel
    private let scheduler: ContextScheduler
    private var observers: [NSObjectProtocol] = []
    private var checkpoint: Timer?
    private var deliveryTimer: Timer?
    private var creatingCalendar: Set<String> = []
    private let calendarCreation: MessageCalendarCreation
    private var bannerIDs: [String: UUID] = [:]
    private var pending: Task<Void, Never>?
    private var lastAdvisorCall: Date?
    private static let advisorCacheKey = "reminders.advisor.cache"
    /// Open items condensed from Messages and the newest message already read; cleared when message reading is off.
    private static let triageKey = "reminders.messages.triage"
    /// Unchanged context is re-judged at most this often; changed context at most every `advisorMinGap`.
    private static let advisorRefresh: TimeInterval = 6 * 3600
    private static let advisorMinGap: TimeInterval = 10 * 60

    private struct AdvisorCache: Codable {
        var fingerprint: String
        var generatedAt: Date
        var plans: [ReminderPlan]
    }

    init(app: AppModel) {
        self.app = app
        calendarCreation = MessageCalendarCreation(store: app.store)
        scheduler = ContextScheduler(store: ReminderStore(app.store))
        super.init()
    }

    func start() {
        Task { await LegacyReminderNotifications.removeAll() }

        let nc = NotificationCenter.default, ws = NSWorkspace.shared.notificationCenter
        let trigger: @Sendable (Notification) -> Void = { [weak self] _ in Task { @MainActor in self?.schedule() } }
        observers = [
            nc.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main, using: trigger),
            nc.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main, using: trigger),
            ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: trigger),
            ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Wake must revalidate before an overdue timer can present a stale plan.
                    self?.deliveryTimer?.invalidate()
                    self?.deliveryTimer = nil
                    self?.pending?.cancel()
                }
            },
        ]
        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.schedule() } }
        t.tolerance = 300
        RunLoop.main.add(t, forMode: .common)
        checkpoint = t
        schedule()
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        checkpoint?.invalidate()
        checkpoint = nil
        pending?.cancel()
        deliveryTimer?.invalidate()
        deliveryTimer = nil
        withdrawCards()
    }

    /// Debounced: bursts of EventKit changes collapse into one reconcile.
    func schedule() {
        deliveryTimer?.invalidate()
        deliveryTimer = nil
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.reconcile()
        }
    }

    private func reconcile() async {
        let s = app.settings
        guard s.proactiveReminders, s.enabledSources.contains(.calendar), app.native.eventKit.calendarAuthorized else {
            withdrawCards()
            return
        }
        let now = Date()
        let events = ToolService.upcomingEvents(in: app.native.eventKit.store, now: now)
        let insights = await smartSuggestions(events: events, settings: s, now: now)
        guard !Task.isCancelled else { return }
        guard let outcome = try? scheduler.reconcile(events: events, insights: insights,
                                                     travelEnabled: s.enabledSources.contains(.maps), now: now) else { return }
        guard !Task.isCancelled else { return }
        for id in outcome.cancel { withdrawCard(id) }
        armDelivery()
    }

    // MARK: Smart suggestions

    private func smartSuggestions(events: [EventSnapshot], settings s: AppSettings, now: Date) async -> [ReminderPlan] {
        guard s.backgroundAI, let cfg = app.modelConfiguration else { return [] }
        if s.advisorReadsMessages != true || !s.enabledSources.contains(.messages) { app.store.setSetting(Self.triageKey, nil) }
        var triage = app.store.codableSetting(Self.triageKey, as: MessageTriageState.self) ?? MessageTriageState()
        let tasks = s.enabledSources.contains(.reminders) ? await openTasks() : []
        func input() -> AdvisorInput {
            AdvisorInput(events: events, tasks: tasks,
                         memories: s.enabledSources.contains(.memory) ? memoryIndex() : [],
                         messages: s.advisorReadsMessages == true && s.enabledSources.contains(.messages) ? triage.notes : [],
                         recentSuggestions: ReminderStore(app.store).plans(status: [.delivered, .handled])
                            .filter { $0.reason == .insight }.suffix(10).map(\.title),
                         now: now)
        }
        let cached = app.store.codableSetting(Self.advisorCacheKey, as: AdvisorCache.self)
        func resolvedPlans(_ plans: [ReminderPlan]) -> [ReminderPlan] {
            let current = input()
            let calendar = SmartAdvisor.calendarSuggestions(in: current)
            let calendarIDs = Set(calendar.map(\.eventID))
            return calendar + SmartAdvisor.stillValid(plans, in: current).filter { !calendarIDs.contains($0.eventID) }
        }
        let fallback = { resolvedPlans(cached?.plans ?? []) }
        if lastAdvisorCall.map({ now.timeIntervalSince($0) < Self.advisorMinGap }) == true { return fallback() }

        let keychain = app.keychain, account = cfg.credentialRef
        // Background work never prompts for the keychain; without a readable key we simply skip.
        guard let key = await Task.detached(operation: { try? keychain.read(account: account, allowInteraction: false) }).value,
              !key.isEmpty else { return fallback() }
        let client = ChatCompletionClient(baseURL: cfg.baseURL, model: cfg.modelName, apiKey: key)
        let complete: SmartAdvisor.Complete = { system, user in try await client.complete(system: system, user: user) }

        // Pass 1: only messages not read before, in small batches, condensed to open items.
        if s.advisorReadsMessages == true && s.enabledSources.contains(.messages) {
            let days = s.messagesLookback
            let messages = await recentMessages(days: days, now: now)
            var triager = MessageTriage(complete: complete)
            triager.window = Double(days) * 86400
            let updated = await triager.update(triage, messages: messages, now: now)
            guard !Task.isCancelled else { return [] }
            if updated != triage {
                if updated.watermark != triage.watermark { lastAdvisorCall = now }
                triage = updated
                app.store.setCodableSetting(Self.triageKey, triage)
            }
        }

        // Pass 2: the advisor sees events, tasks, memories and those short items, never raw message text.
        let current = input()
        let fingerprint = current.fingerprint
        if let cached, cached.fingerprint == fingerprint, now.timeIntervalSince(cached.generatedAt) < Self.advisorRefresh {
            return resolvedPlans(cached.plans)
        }
        lastAdvisorCall = now
        guard let plans = try? await SmartAdvisor(complete: complete).suggest(current) else {
            return resolvedPlans(cached?.plans ?? [])
        }
        guard !Task.isCancelled else { return [] }
        app.store.setCodableSetting(Self.advisorCacheKey, AdvisorCache(fingerprint: fingerprint, generatedAt: now, plans: plans))
        return resolvedPlans(plans)
    }

    private func openTasks() async -> [TaskSnapshot] {
        guard app.native.eventKit.remindersAuthorized else { return [] }
        return await ToolService.openReminders(in: app.native.eventKit.store)
    }

    /// Recent Messages within the chosen window, read-only and redacted. Silently empty without Full Disk Access.
    private func recentMessages(days: Int, now: Date) async -> [MessageSnapshot] {
        let contacts = app.native.contacts
        return await Task.detached(priority: .utility) {
            let reader = MessagesHistoryReader()
            guard reader.isReadable else { return [] }
            let names = contacts.nameIndex()
            return (try? reader.recent(since: now.addingTimeInterval(-Double(days) * 86400), limit: 300) {
                names[MessagesHistoryReader.normalize($0)]
            }) ?? []
        }.value
    }

    /// The memory index (MEMORY.md); topic files are left out of background suggestions.
    private func memoryIndex() -> [ContextSnippet] {
        app.memory.context().map { [ContextSnippet(sourceID: "memory/\(MemoryFolder.indexName)", text: $0)] } ?? []
    }

    /// Rebuild from persisted plans after every reconcile, including unchanged and snoozed plans.
    private func armDelivery() {
        deliveryTimer?.invalidate()
        deliveryTimer = nil
        guard app.settings.proactiveReminders, app.settings.enabledSources.contains(.calendar),
              app.native.eventKit.calendarAuthorized else { return }
        let plans = ReminderStore(app.store).plans(status: [.scheduled, .snoozed]).sorted { $0.fireDate < $1.fireDate }
        let now = Date()
        for plan in plans where plan.fireDate <= now { deliver(plan) }
        guard let next = plans.first(where: { $0.fireDate > now }) else { return }
        let timer = Timer(fire: next.fireDate, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.armDelivery() }
        }
        RunLoop.main.add(timer, forMode: .common)
        deliveryTimer = timer
    }

    private func deliver(_ plan: ReminderPlan) {
        // Persist before presenting, so checkpoints and relaunches cannot show it twice.
        do { try scheduler.markDelivered(plan.id) } catch { return }
        withdrawCard(plan.id)
        var item = ReminderBannerItem(
            source: "Asky", timeLabel: NSLocalizedString("现在", comment: ""),
            title: plan.title, body: plan.body,
            symbol: plan.reason == .travel ? "car.fill" : "calendar",
            reasons: plan.evidence,
            actions: [
                .init(title: NSLocalizedString("稍后提醒", comment: "")) { [weak self] in self?.snooze(plan.id) },
                .init(title: NSLocalizedString("关闭此类", comment: "")) { [weak self] in self?.disable(plan) },
                .init(title: NSLocalizedString("已处理", comment: ""), prominent: true) { [weak self] in
                    try? self?.scheduler.markHandled(plan.id)
                    self?.bannerIDs[plan.id] = nil
                },
            ], lifetime: nil)
        if calendarNote(for: plan)?.calendarDraft?.isValid(at: Date()) == true {
            item.actions.removeLast()
            item.actions.append(.init(title: NSLocalizedString("创建日程", comment: ""), prominent: true,
                                      dismissesCard: false) { [weak self] in
                Task { @MainActor in await self?.createCalendarEvent(for: plan) }
            })
        }
        bannerIDs[plan.id] = item.id
        ReminderBannerCenter.shared.show(item)
    }

    private func calendarNote(for plan: ReminderPlan) -> MessageNote? {
        guard app.settings.advisorReadsMessages == true, app.settings.enabledSources.contains(.messages) else { return nil }
        return app.store.codableSetting(Self.triageKey, as: MessageTriageState.self)?.notes.first {
            "message:\($0.id)" == plan.eventID && SmartAdvisor.matchesMessage($0, plan: plan)
        }
    }

    private func createCalendarEvent(for plan: ReminderPlan) async {
        guard creatingCalendar.insert(plan.eventID).inserted else { return }
        defer { creatingCalendar.remove(plan.eventID) }
        guard let note = calendarNote(for: plan), let draft = note.calendarDraft,
              draft.isValid(at: Date()), app.settings.enabledSources.contains(.calendar) else {
            showCalendarError(NSLocalizedString("短信安排已变化或授权已关闭，请重新检查。", comment: ""))
            return
        }
        let tools = app.tools
        let result: ExecutionResult?
        if await calendarCreation.hasRequest(sourceID: note.id) {
            result = await calendarCreation.submit(sourceID: note.id, draft: draft) { await tools.submit($0) }
        } else {
            let listed = await tools.submit(ActionRequest(tool: "calendar_list_calendars", arguments: [:],
                                                         origin: .launcher, intent: .explicitRequest))
            let calendars = MessageCalendarChoice.writableChoices(listed.output)
            guard listed.status == .completed, !calendars.isEmpty else {
                showCalendarError(listed.error?.message ?? NSLocalizedString("没有可写的日历，请先在系统日历中配置。", comment: ""))
                return
            }
            result = await MessageCalendarEditor.present(draft, calendars: calendars, source: note.summary) { [weak self] edited in
                guard let self, self.calendarNote(for: plan)?.calendarDraft == draft,
                      self.app.settings.enabledSources.contains(.calendar), edited.isValid(at: Date()) else {
                    return .failure(UUID().uuidString, .invalidArguments, NSLocalizedString("安排已变化或授权已关闭，请重新检查。", comment: ""))
                }
                return await self.calendarCreation.submit(sourceID: note.id, draft: edited) { await tools.submit($0) }
            }
        }
        guard let result else { return }
        if result.status == .completed {
            try? scheduler.markHandled(plan.id)
            if var state = app.store.codableSetting(Self.triageKey, as: MessageTriageState.self) {
                state.notes.removeAll { $0.id == note.id }
                app.store.setCodableSetting(Self.triageKey, state)
            }
            withdrawCard(plan.id)
            schedule()
        } else {
            showCalendarError(result.status == .pendingVerification
                ? NSLocalizedString("创建结果待核实，请勿重复创建。", comment: "")
                : result.error?.message ?? NSLocalizedString("日程未创建，请重试。", comment: ""))
        }
    }

    private func showCalendarError(_ message: String) {
        let alert = AppDialog.make()
        alert.messageText = NSLocalizedString("日程创建结果", comment: "")
        alert.informativeText = message
        NSApp.activate()
        Task { @MainActor in await AppDialog.present(alert) }
    }

    private func snooze(_ id: String) {
        guard (try? scheduler.snooze(id)) != nil else { return }
        bannerIDs[id] = nil
        armDelivery()
    }

    private func disable(_ plan: ReminderPlan) {
        guard (try? scheduler.disableCategory(plan.reason)) != nil else { return }
        let ids = ReminderStore(app.store).plans(status: [.delivered, .cancelled])
            .filter { $0.reason == plan.reason && !$0.userRequested }.map(\.id)
        for id in ids { withdrawCard(id) }
        armDelivery()
    }

    private func withdrawCard(_ planID: String) {
        guard let id = bannerIDs.removeValue(forKey: planID) else { return }
        ReminderBannerCenter.shared.dismiss(id)
    }

    private func withdrawCards() {
        for id in Array(bannerIDs.keys) { withdrawCard(id) }
    }
}
