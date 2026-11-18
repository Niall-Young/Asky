import Foundation

/// Minimal snapshot of an authorised calendar event (never a full copy of the calendar database).
public struct EventSnapshot: Sendable, Hashable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var location: String?
    public var isAllDay: Bool
    public init(id: String, title: String, start: Date, end: Date, location: String? = nil, isAllDay: Bool = false) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.isAllDay = isAllDay
    }

    public var fingerprint: String {
        "\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)|\(location ?? "")"
    }
}

/// Minimal snapshot of an incomplete Reminders item.
public struct TaskSnapshot: Sendable, Hashable {
    public var id: String
    public var title: String
    public var due: Date?
    public var list: String
    public init(id: String, title: String, due: Date? = nil, list: String = "") {
        self.id = id
        self.title = title
        self.due = due
        self.list = list
    }
}
