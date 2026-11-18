import Foundation
import Contracts
import LocalStore

public typealias EventSnapshot = Contracts.EventSnapshot

/// An upcoming date backed by an allowed memory (relationship or prior intent). Without evidence no plan is made.
public struct ImportantDate: Sendable, Hashable {
    public var id: String
    public var title: String
    public var date: Date
    public var evidence: [String]
    public init(id: String, title: String, date: Date, evidence: [String]) {
        self.id = id
        self.title = title
        self.date = date
        self.evidence = evidence
    }
}

public struct SchedulerSettings: Sendable {
    public var travelBuffer: TimeInterval = 10 * 60
    public var importantDateLead: TimeInterval = 7 * 24 * 3600
    public var dailySuggestionCap = 2
    public var windowStartHour = 9
    public var windowEndHour = 21
    public var conflictLead: TimeInterval = 60 * 60
    /// When no ETA is available we only ask the user to check the route, this far ahead.
    public var routeCheckLead: TimeInterval = 60 * 60
    public var horizon: TimeInterval = 7 * 24 * 3600
    public init() {}
}

/// Deterministic rules only; no model calls.
public struct ReminderRules: Sendable {
    public var settings: SchedulerSettings
    public var calendar: Calendar

    public init(settings: SchedulerSettings = .init(), calendar: Calendar = .current) {
        self.settings = settings
        self.calendar = calendar
    }

    /// Overlaps, plus adjacent events whose gap is shorter than the known travel ETA between them.
    public func conflicts(_ events: [EventSnapshot], etaBetween: (EventSnapshot, EventSnapshot) -> TimeInterval? = { _, _ in nil },
                          now: Date) -> [ReminderPlan] {
        let timed = events.filter { !$0.isAllDay && $0.end > now }.sorted { $0.start < $1.start }
        var plans: [ReminderPlan] = []
        for (i, a) in timed.enumerated() {
            for b in timed[(i + 1)...] {
                if b.start >= a.end.addingTimeInterval(3 * 3600) { break }
                var evidence: [String] = []
                if b.start < a.end {
                    evidence = [CoreLocalization.format("「%@」与「%@」时间重叠", String(describing: a.title), String(describing: b.title))]
                } else if let eta = etaBetween(a, b), b.start.timeIntervalSince(a.end) < eta {
                    let gap = Int(b.start.timeIntervalSince(a.end) / 60), need = Int(eta / 60)
                    evidence = [CoreLocalization.format("「%@」结束后仅 %@ 分钟开始「%@」，路线约需 %@ 分钟", String(describing: a.title), String(describing: gap), String(describing: b.title), String(describing: need))]
                }
                guard !evidence.isEmpty else { continue }
                plans.append(ReminderPlan(eventID: b.id, reason: .conflict, title: CoreLocalization.text("日程可能冲突"),
                                          body: evidence[0] + CoreLocalization.text("。是否需要调整？（不会自动移动原日程）"),
                                          evidence: ["event:\(a.id)", "event:\(b.id)"] + evidence,
                                          fireDate: max(now, a.start.addingTimeInterval(-settings.conflictLead)),
                                          eventFingerprint: a.fingerprint + "#" + b.fingerprint))
            }
        }
        return plans
    }

    /// Travel preparation. With an ETA: leave-by time with buffer. Without: only "check route", never a fabricated time.
    public func travel(_ event: EventSnapshot, eta: TimeInterval?, now: Date) -> ReminderPlan? {
        guard !event.isAllDay, let loc = event.location, !loc.isEmpty, event.start > now else { return nil }
        if let eta {
            let leave = event.start.addingTimeInterval(-eta - settings.travelBuffer)
            let fmt = Self.timeFormatter(calendar)
            return ReminderPlan(eventID: event.id, reason: .travel, title: CoreLocalization.format("准备出发：%@", String(describing: event.title)),
                                body: CoreLocalization.format("建议 %@ 前出发前往 %@（路线约 %@ 分钟，含 %@ 分钟缓冲）", String(describing: fmt.string(from: leave)), String(describing: loc), String(describing: Int(eta / 60)), String(describing: Int(settings.travelBuffer / 60))),
                                evidence: ["event:\(event.id)", "eta:\(Int(eta))"],
                                fireDate: max(now, leave.addingTimeInterval(-15 * 60)), eventFingerprint: event.fingerprint)
        }
        return ReminderPlan(eventID: event.id, reason: .travel, title: CoreLocalization.format("检查路线：%@", String(describing: event.title)),
                            body: CoreLocalization.format("日程地点为 %@，暂无可用路线时间，请提前检查路线。", String(describing: loc)),
                            evidence: ["event:\(event.id)", "eta:unavailable"],
                            fireDate: max(now, event.start.addingTimeInterval(-settings.routeCheckLead)),
                            eventFingerprint: event.fingerprint)
    }

    public func importantDate(_ d: ImportantDate, now: Date) -> ReminderPlan? {
        guard !d.evidence.isEmpty, d.date > now else { return nil }
        let fire = d.date.addingTimeInterval(-settings.importantDateLead)
        return ReminderPlan(eventID: d.id, reason: .importantDate, title: d.title,
                            body: CoreLocalization.format("%@还有 %@ 天。需要准备什么吗？", String(describing: d.title), String(describing: max(1, Int(d.date.timeIntervalSince(max(now, fire)) / 86400)))),
                            evidence: d.evidence, fireDate: max(now, fire),
                            eventFingerprint: "\(d.date.timeIntervalSince1970)")
    }

    /// Moves a suggestion into the delivery window (09:00–21:00 by default).
    public func fitToWindow(_ date: Date) -> Date {
        let h = calendar.component(.hour, from: date)
        let day = calendar.startOfDay(for: date)
        if h < settings.windowStartHour {
            return calendar.date(byAdding: .hour, value: settings.windowStartHour, to: day) ?? date
        }
        if h >= settings.windowEndHour {
            // Earlier is better than missing it: deliver at the end of today's window.
            return calendar.date(byAdding: .minute, value: settings.windowEndHour * 60 - 1, to: day) ?? date
        }
        return date
    }

    static func timeFormatter(_ cal: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.dateFormat = "HH:mm"
        return f
    }
}

public struct ReconcileOutcome: Sendable {
    /// Plans whose delivery must be (re)scheduled.
    public var schedule: [ReminderPlan] = []
    /// Plan IDs whose pending delivery and visible cards must be removed.
    public var cancel: [String] = []
}

/// Context Scheduler: re-evaluates on calendar changes, checkpoints, memory changes, wake and time-zone changes.
public struct ContextScheduler: Sendable {
    public let store: ReminderStore
    public let rules: ReminderRules

    public init(store: ReminderStore, rules: ReminderRules = .init()) {
        self.store = store
        self.rules = rules
    }

    public func reconcile(events: [EventSnapshot], importantDates: [ImportantDate] = [], insights: [ReminderPlan] = [],
                          eta: (EventSnapshot) -> TimeInterval? = { _ in nil },
                          etaBetween: (EventSnapshot, EventSnapshot) -> TimeInterval? = { _, _ in nil },
                          travelEnabled: Bool, now: Date = Date()) throws -> ReconcileOutcome {
        let horizonEnd = now.addingTimeInterval(rules.settings.horizon)
        let inHorizon = events.filter { $0.start < horizonEnd }
        var candidates = rules.conflicts(inHorizon, etaBetween: travelEnabled ? etaBetween : { _, _ in nil }, now: now)
        if travelEnabled { candidates += inHorizon.compactMap { rules.travel($0, eta: eta($0), now: now) } }
        candidates += importantDates.compactMap { rules.importantDate($0, now: now) }
        // Model suggestions are placed after deterministic ones, so they never take a real conflict's daily slot.
        candidates += insights.filter { $0.reason == .insight && $0.fireDate < horizonEnd }
        candidates = candidates.filter { store.isCategoryEnabled($0.reason) }

        var out = ReconcileOutcome()
        var liveKeys = Set<String>()
        let byKey = Dictionary(candidates.map { ($0.dedupeKey, $0) }, uniquingKeysWith: { a, _ in a })

        let ordered = byKey.sorted { a, b in
            let ai = a.value.reason == .insight, bi = b.value.reason == .insight
            return ai != bi ? !ai : a.value.fireDate < b.value.fireDate
        }
        for (key, var plan) in ordered {
            liveKeys.insert(key)
            if let existing = store.plan(dedupeKey: key) {
                if existing.status == .handled || existing.status == .delivered {
                    if existing.eventFingerprint == plan.eventFingerprint { continue }
                } else if existing.status == .snoozed, existing.eventFingerprint == plan.eventFingerprint {
                    continue
                } else if existing.status == .scheduled, existing.eventFingerprint == plan.eventFingerprint {
                    continue
                }
                plan.id = existing.id
                out.cancel.append(existing.id)
            }
            if !plan.userRequested {
                plan.fireDate = rules.fitToWindow(plan.fireDate)
                let day = rules.calendar.startOfDay(for: plan.fireDate)
                let next = rules.calendar.date(byAdding: .day, value: 1, to: day) ?? day
                // Plans scheduled earlier in this pass are already persisted, so the store count includes them.
                let already = store.deliveredSuggestions(from: day, to: next)
                    + store.plans(status: [.scheduled]).filter { !$0.userRequested && $0.id != plan.id
                        && rules.calendar.isDate($0.fireDate, inSameDayAs: day) && !out.cancel.contains($0.id) }.count
                if already >= rules.settings.dailySuggestionCap { continue }
            }
            plan.status = .scheduled
            try store.upsert(plan, now: now)
            out.schedule.append(plan)
        }

        // Plans whose basis disappeared (event deleted / changed / category disabled) are cancelled.
        for stale in store.plans(status: [.scheduled, .snoozed]) where !liveKeys.contains(stale.dedupeKey) && !stale.userRequested {
            try store.setStatus(stale.id, .cancelled, now: now)
            out.cancel.append(stale.id)
        }
        return out
    }

    public func snooze(_ planID: String, by interval: TimeInterval = 3600, now: Date = Date()) throws -> Date {
        let requested = now.addingTimeInterval(max(1, interval))
        let when: Date
        if rules.calendar.component(.hour, from: requested) >= rules.settings.windowEndHour {
            var start = DateComponents()
            start.hour = rules.settings.windowStartHour
            start.minute = 0
            when = rules.calendar.nextDate(after: requested, matching: start, matchingPolicy: .nextTime) ?? requested
        } else {
            when = max(requested, rules.fitToWindow(requested))
        }
        try store.setStatus(planID, .snoozed, fireDate: when, now: now)
        return when
    }

    public func markHandled(_ planID: String) throws { try store.setStatus(planID, .handled) }
    public func markDelivered(_ planID: String) throws { try store.setStatus(planID, .delivered) }

    public func disableCategory(_ reason: ReminderReason) throws -> [String] {
        try store.setCategory(reason, enabled: false)
        let ids = store.plans(status: [.scheduled, .snoozed]).filter { $0.reason == reason && !$0.userRequested }.map(\.id)
        for id in ids { try store.setStatus(id, .cancelled) }
        return ids
    }
}
