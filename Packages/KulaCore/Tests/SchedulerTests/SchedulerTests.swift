import Testing
import Foundation
import Contracts
import LocalStore
@testable import Scheduler

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return c
}

/// 2026-10-12 08:00 Asia/Shanghai.
private let base = utc.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 8))!
private func at(_ h: Double) -> Date { base.addingTimeInterval(h * 3600) }

private func scheduler() throws -> ContextScheduler {
    let s = try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory)
    return ContextScheduler(store: ReminderStore(s), rules: ReminderRules(calendar: utc))
}

@Suite struct SchedulerTests {
    let rules = ReminderRules(calendar: utc)

    @Test func overlapAndShortGapConflicts() {
        let a = EventSnapshot(id: "a", title: "A", start: at(2), end: at(3))
        let b = EventSnapshot(id: "b", title: "B", start: at(2.5), end: at(4))
        let c = EventSnapshot(id: "c", title: "C", start: at(4.25), end: at(5))
        let allDay = EventSnapshot(id: "d", title: "D", start: at(0), end: at(24), isAllDay: true)
        let noEta = rules.conflicts([a, b, c, allDay], now: base)
        #expect(noEta.map(\.eventID) == ["b"])
        let withEta = rules.conflicts([a, b, c], etaBetween: { _, _ in 30 * 60 }, now: base)
        #expect(Set(withEta.map(\.eventID)) == ["b", "c"])
    }

    @Test func travelWithoutETANeverInventsATime() throws {
        let e = EventSnapshot(id: "e", title: "看牙", start: at(6), end: at(7), location: "某诊所")
        let p = try #require(rules.travel(e, eta: nil, now: base))
        #expect(p.title == CoreLocalization.format("检查路线：%@", e.title) && p.evidence.contains("eta:unavailable"))
        let q = try #require(rules.travel(e, eta: 40 * 60, now: base))
        // leave = 14:00 - 40m - 10m = 13:10
        #expect(q.body.contains("13:10"))
        #expect(rules.travel(EventSnapshot(id: "x", title: "x", start: at(6), end: at(7)), eta: nil, now: base) == nil)
    }

    @Test func importantDateNeedsEvidence() {
        let d = ImportantDate(id: "bd", title: "妈妈生日", date: at(24 * 10), evidence: [])
        #expect(rules.importantDate(d, now: base) == nil)
        var e = d
        e.evidence = ["memory:1"]
        #expect(rules.importantDate(e, now: base)?.fireDate == at(24 * 3))
    }

    @Test func deliveryWindow() {
        #expect(utc.component(.hour, from: rules.fitToWindow(at(-2))) == 9)          // 06:00 → 09:00
        #expect(utc.component(.hour, from: rules.fitToWindow(at(14))) == 20)         // 22:00 → next morning
        #expect(rules.fitToWindow(at(3)) == at(3))
    }

    @Test func dailyCapAndIdempotentReconcile() throws {
        let s = try scheduler()
        // Three overlapping pairs on the same day → three conflict candidates, cap is 2.
        let events = (0..<3).flatMap { i -> [EventSnapshot] in
            let h = Double(4 + i * 3)
            return [EventSnapshot(id: "a\(i)", title: "A\(i)", start: at(h), end: at(h + 1)),
                    EventSnapshot(id: "b\(i)", title: "B\(i)", start: at(h + 0.5), end: at(h + 1.5))]
        }
        let first = try s.reconcile(events: events, travelEnabled: false, now: base)
        #expect(first.schedule.count == 2)
        let again = try s.reconcile(events: events, travelEnabled: false, now: base)
        #expect(again.schedule.isEmpty && again.cancel.isEmpty)
    }

    @Test func changedOrRemovedEventCancelsStalePlan() throws {
        let s = try scheduler()
        let e = EventSnapshot(id: "e", title: "会议", start: at(6), end: at(7), location: "国贸")
        let r1 = try s.reconcile(events: [e], travelEnabled: true, now: base)
        let planID = try #require(r1.schedule.first?.id)
        var moved = e
        moved.start = at(8); moved.end = at(9)
        let r2 = try s.reconcile(events: [moved], travelEnabled: true, now: base)
        #expect(r2.cancel == [planID] && r2.schedule.first?.id == planID)
        let r3 = try s.reconcile(events: [], travelEnabled: true, now: base)
        #expect(r3.cancel == [planID])
        #expect(s.store.plans(status: [.scheduled]).isEmpty)
    }

    @Test func disablingCategoryCancelsAndSuppresses() throws {
        let s = try scheduler()
        let e = EventSnapshot(id: "e", title: "会议", start: at(6), end: at(7), location: "国贸")
        _ = try s.reconcile(events: [e], travelEnabled: true, now: base)
        #expect(try s.disableCategory(.travel).count == 1)
        #expect(try s.reconcile(events: [e], travelEnabled: true, now: base).schedule.isEmpty)
    }

    @Test func snoozeStaysInWindow() throws {
        let s = try scheduler()
        let e = EventSnapshot(id: "e", title: "会议", start: at(6), end: at(7), location: "国贸")
        let id = try #require(try s.reconcile(events: [e], travelEnabled: true, now: base).schedule.first?.id)
        let when = try s.snooze(id, by: 14 * 3600, now: base)  // 22:00 → next morning
        #expect(when == utc.date(byAdding: .hour, value: 25, to: base))
    }
}
