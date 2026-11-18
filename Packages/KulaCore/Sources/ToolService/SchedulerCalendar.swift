import Foundation
import EventKit
import Contracts

extension ToolService {
    @MainActor public static func upcomingEvents(in ek: EKEventStore, now: Date) -> [EventSnapshot] {
        let pred = ek.predicateForEvents(withStart: now, end: now.addingTimeInterval(7 * 24 * 3600), calendars: nil)
        return ek.events(matching: pred).filter { $0.availability != .free }.map {
            EventSnapshot(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "", start: $0.startDate,
                          end: $0.endDate, location: $0.location, isAllDay: $0.isAllDay)
        }
    }

    @MainActor public static func openReminders(in ek: EKEventStore) async -> [TaskSnapshot] {
        let pred = ek.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { cont in
            ek.fetchReminders(matching: pred) { rs in
                let items = (rs ?? []).prefix(60).map {
                    TaskSnapshot(id: $0.calendarItemIdentifier, title: $0.title ?? "", due: $0.dueDateComponents?.date,
                                 list: $0.calendar?.title ?? "")
                }
                // Dated tasks first: they are the ones that can collide with the calendar.
                cont.resume(returning: items.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) })
            }
        }
    }
}
