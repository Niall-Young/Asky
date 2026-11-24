import Foundation
import EventKit
import Contracts
import ToolService

/// Owns the single EKEventStore. Access is requested only when the user enables the source.
public final class EventKitBridge: @unchecked Sendable {
    private let eventStore = EKEventStore()
    private let accessLock = NSLock()
    private var access = EventStoreAccessState()
    public init() {
        _ = access.observe(calendar: calendarAuthorized, reminders: remindersAuthorized)
    }

    /// Settings may grant access using another store. Refresh this store before using any objects
    /// after a permission transition; refreshSourcesIfNecessary alone does not clear denied data.
    public var store: EKEventStore {
        accessLock.lock()
        defer { accessLock.unlock() }
        if access.observe(calendar: calendarAuthorized, reminders: remindersAuthorized) {
            eventStore.reset()
        }
        return eventStore
    }

    func calendars(for entity: EKEntityType) throws -> [EKCalendar] {
        let store = self.store
        store.refreshSourcesIfNecessary()
        var calendars = store.calendars(for: entity)
        if calendars.isEmpty {
            // One read-only recovery attempt for a stale connection/cache, never retry a write.
            store.reset()
            store.refreshSourcesIfNecessary()
            calendars = store.calendars(for: entity)
        }
        guard !calendars.isEmpty else {
            throw ToolError(.adapterFailure, CoreLocalization.format("系统授权已开启，但 EventKit 未返回%@。无法确认是账户为空还是系统数据连接异常；不能据此断言没有日历或提醒事项。请重新打开 Asky 后重试，并核对系统 App 与 Asky 设置 › 系统权限。", String(describing: CoreLocalization.text(entity == .event ? "日历" : "提醒列表"))))
        }
        return calendars
    }

    public var calendarAuthorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    public var remindersAuthorized: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    public func requestCalendar() async -> Bool { (try? await store.requestFullAccessToEvents()) ?? false }
    public func requestReminders() async -> Bool { (try? await store.requestFullAccessToReminders()) ?? false }

    func requireCalendar() throws {
        guard calendarAuthorized else { throw ToolError(.permissionDenied, CoreLocalization.text("未获得日历完全访问权限")) }
    }

    func requireReminders() throws {
        guard remindersAuthorized else { throw ToolError(.permissionDenied, CoreLocalization.text("未获得提醒事项访问权限")) }
    }

    func eventJSON(_ e: EKEvent) -> JSONValue {
        var o: [String: JSONValue] = [
            "id": .string(e.eventIdentifier ?? ""), "title": .string(e.title ?? ""),
            "start": .string(Args.iso(e.startDate)), "end": .string(Args.iso(e.endDate)),
            "allDay": .bool(e.isAllDay), "calendar": .string(e.calendar?.title ?? ""),
            "application": .string("Apple Calendar"),
            "calendarID": .string(e.calendar?.calendarIdentifier ?? ""),
            "account": .string(e.calendar?.source?.title ?? ""),
            "writable": .bool(e.calendar?.allowsContentModifications ?? false),
            "recurring": .bool(e.hasRecurrenceRules),
        ]
        if let l = e.location, !l.isEmpty { o["location"] = .string(l) }
        if let tz = e.timeZone { o["timeZone"] = .string(tz.identifier) }
        return .object(o)
    }

    func event(_ id: String) throws -> EKEvent {
        guard let e = store.event(withIdentifier: id) else { throw ToolError(.targetNotFound, CoreLocalization.format("找不到日程 %@", String(describing: id))) }
        return e
    }

    func overlapping(start: Date, end: Date, excluding: String? = nil) -> [EKEvent] {
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: pred).filter { !$0.isAllDay && $0.eventIdentifier != excluding && $0.availability != .free }
    }
}

// MARK: Calendar

public struct CalendarListTool: ToolAdapter {
    let ek: EventKitBridge
    public init(_ ek: EventKitBridge) { self.ek = ek }

    public var definition: ToolDefinition {
        ToolDefinition(name: "calendar_list_calendars", summary: CoreLocalization.text("列出苹果日历中的实际日历名称、ID、账户、是否可写和系统默认日历；名称不代表其他应用"),
                       inputSchema: Args.schema([:], required: []), source: .calendar, effect: .read,
                       confirmation: .never, externallyExposable: true)
    }

    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        try ek.requireCalendar()
        let calendars = try ek.calendars(for: .event)
        let defaultID = ek.store.defaultCalendarForNewEvents?.calendarIdentifier
        return AdapterOutput(output: .array(calendars.map {
            ["application": .string("Apple Calendar"),
             "id": .string($0.calendarIdentifier), "name": .string($0.title),
             "account": .string($0.source.title), "writable": .bool($0.allowsContentModifications),
             "isDefault": .bool($0.calendarIdentifier == defaultID)]
        }))
    }
}

public struct CalendarSearchTool: ToolAdapter {
    let ek: EventKitBridge
    public init(_ ek: EventKitBridge) { self.ek = ek }

    public var definition: ToolDefinition {
        ToolDefinition(name: "calendar_search_events", summary: CoreLocalization.text("查询时间范围内的日程，可按关键词过滤"),
                       inputSchema: Args.schema(["start": Args.isoDateProp, "end": Args.isoDateProp,
                                                 "query": Args.stringProp, "limit": Args.intProp], required: ["start", "end"]),
                       source: .calendar, effect: .read, confirmation: .never, externallyExposable: true)
    }

    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        try ek.requireCalendar()
        let start = try Args.requiredDate(a, "start"), end = try Args.requiredDate(a, "end")
        guard end > start, end.timeIntervalSince(start) <= 366 * 86400 else {
            throw ToolError(.invalidArguments, CoreLocalization.text("时间范围无效或超过一年"))
        }
        let q = try Args.string(a["query"], "query", required: false)?.lowercased()
        let limit = Args.int(a["limit"], default: 50, max: 200)
        _ = try ek.calendars(for: .event)
        let events = ek.store.events(matching: ek.store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { q == nil || ($0.title ?? "").lowercased().contains(q!) || ($0.location ?? "").lowercased().contains(q!) }
            .prefix(limit)
        return AdapterOutput(output: .array(events.map(ek.eventJSON)),
                             targets: events.map { TargetRef(kind: "event", identifier: $0.eventIdentifier ?? "") })
    }
}

public struct CalendarCreateTool: ToolAdapter {
    let ek: EventKitBridge
    public init(_ ek: EventKitBridge) { self.ek = ek }

    public var definition: ToolDefinition {
        ToolDefinition(name: "calendar_create_event", summary: CoreLocalization.text("新建日程（存在冲突时不会直接创建）"),
                       inputSchema: Args.schema(["title": Args.stringProp, "start": Args.isoDateProp, "end": Args.isoDateProp,
                                                 "location": Args.stringProp, "notes": Args.stringProp,
                                                 "calendar": ["type": "string", "description": .string(CoreLocalization.text("日历 ID 或准确名称；先用 calendar_list_calendars 查询。缺省优先默认日历，否则仅在一个可写日历时自动选择"))],
                                                 "allowConflict": ["type": "boolean"]],
                                                required: ["title", "start", "end"]),
                       source: .calendar, effect: .write, writeKind: .create, confirmation: .createDirectOtherwiseConfirm,
                       externallyExposable: true)
    }

    func calendar(_ a: JSONValue) throws -> EKCalendar {
        let selector = try Args.string(a["calendar"], "calendar", required: false)
        let calendars = try ek.calendars(for: .event)
        let id = try CalendarSelection.resolve(selector: selector,
            defaultID: ek.store.defaultCalendarForNewEvents?.calendarIdentifier,
            calendars: calendars.map(CalendarChoice.init))
        guard let cal = calendars.first(where: { $0.calendarIdentifier == id }) else {
            throw ToolError(.targetNotFound, CoreLocalization.text("日历已变化，请调用 calendar_list_calendars 后重新选择"))
        }
        return cal
    }

    public func preview(_ a: JSONValue) async throws -> ConfirmationPreview {
        try ek.requireCalendar()
        let title = try Args.requiredString(a, "title")
        let start = try Args.requiredDate(a, "start"), end = try Args.requiredDate(a, "end")
        guard end > start else { throw ToolError(.invalidArguments, CoreLocalization.text("结束时间必须晚于开始时间")) }
        let cal = try calendar(a)
        let clashes = ek.overlapping(start: start, end: end)
        if !clashes.isEmpty && a["allowConflict"]?.boolValue != true {
            throw ToolError(.conflict, CoreLocalization.text("与已有日程冲突：") + clashes.prefix(3).map { $0.title ?? "" }.joined(separator: "、"))
        }
        var changes = ["新建「\(title)」", "\(Args.iso(start)) – \(Args.iso(end))"]
        if let l = a["location"]?.stringValue { changes.append("地点：\(l)") }
        return ConfirmationPreview(target: "苹果日历 ·「\(cal.title)」", changes: changes,
                                   note: clashes.isEmpty ? nil : "与 \(clashes.count) 个日程时间重叠")
    }

    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        _ = try await preview(a)
        let e = EKEvent(eventStore: ek.store)
        e.title = try Args.requiredString(a, "title")
        e.startDate = try Args.requiredDate(a, "start")
        e.endDate = try Args.requiredDate(a, "end")
        e.timeZone = .current
        e.location = a["location"]?.stringValue
        e.notes = a["notes"]?.stringValue
        e.calendar = try calendar(a)
        do { try ek.store.save(e, span: .thisEvent, commit: true) } catch {
            throw ToolError(.adapterFailure, CoreLocalization.format("保存日程失败：%@", String(describing: error.localizedDescription)))
        }
        return AdapterOutput(output: ek.eventJSON(e), targets: [TargetRef(kind: "event", identifier: e.eventIdentifier ?? "")])
    }

    public func readback(_ a: JSONValue, output: AdapterOutput?) async -> JSONValue? {
        if let id = output?.targets.first?.identifier, let e = ek.store.event(withIdentifier: id) { return ek.eventJSON(e) }
        // Unknown outcome (timeout / cancel): look for an identical event.
        guard let title = a["title"]?.stringValue, let start = Args.date(a["start"]), let end = Args.date(a["end"]) else { return nil }
        let match = ek.store.events(matching: ek.store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .first { $0.title == title && $0.startDate == start && $0.endDate == end }
        return match.map(ek.eventJSON)
    }
}

public struct CalendarUpdateTool: ToolAdapter {
    let ek: EventKitBridge
    public init(_ ek: EventKitBridge) { self.ek = ek }

    public var definition: ToolDefinition {
        ToolDefinition(name: "calendar_update_event", summary: CoreLocalization.text("修改已有日程（明确请求直接执行；重复日程仅修改本次）"),
                       inputSchema: Args.schema(["id": Args.stringProp, "title": Args.stringProp, "start": Args.isoDateProp,
                                                 "end": Args.isoDateProp, "location": Args.stringProp], required: ["id"]),
                       source: .calendar, effect: .write, writeKind: .modify, confirmation: .explicitDirectOtherwiseConfirm, externallyExposable: true)
    }

    public func preview(_ a: JSONValue) async throws -> ConfirmationPreview {
        try ek.requireCalendar()
        let e = try ek.event(try Args.requiredString(a, "id"))
        guard e.calendar?.allowsContentModifications == true else { throw ToolError(.targetReadOnly, CoreLocalization.text("该日程所在日历只读")) }
        for key in ["start", "end"] where a[key] != nil { _ = try Args.requiredDate(a, key) }
        guard (Args.date(a["end"]) ?? e.endDate) > (Args.date(a["start"]) ?? e.startDate) else {
            throw ToolError(.invalidArguments, CoreLocalization.text("结束时间必须晚于开始时间"))
        }
        var changes: [String] = []
        if let t = a["title"]?.stringValue { changes.append("标题：\(e.title ?? "") → \(t)") }
        if let s = Args.date(a["start"]) { changes.append("开始：\(Args.iso(e.startDate)) → \(Args.iso(s))") }
        if let s = Args.date(a["end"]) { changes.append("结束：\(Args.iso(e.endDate)) → \(Args.iso(s))") }
        if let l = a["location"]?.stringValue { changes.append("地点：\(e.location ?? CoreLocalization.text("无")) → \(l)") }
        guard !changes.isEmpty else { throw ToolError(.invalidArguments, CoreLocalization.text("没有要修改的字段")) }
        return ConfirmationPreview(target: "日程「\(e.title ?? "")」", changes: changes,
                                   note: e.hasRecurrenceRules ? "重复日程：仅修改本次" : nil)
    }

    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        _ = try await preview(a)
        let e = try ek.event(try Args.requiredString(a, "id"))
        if let t = a["title"]?.stringValue { e.title = t }
        if let s = Args.date(a["start"]) { e.startDate = s }
        if let s = Args.date(a["end"]) { e.endDate = s }
        if let l = a["location"]?.stringValue { e.location = l }
        guard e.endDate > e.startDate else { throw ToolError(.invalidArguments, CoreLocalization.text("结束时间必须晚于开始时间")) }
        do { try ek.store.save(e, span: .thisEvent, commit: true) } catch {
            throw ToolError(.adapterFailure, CoreLocalization.format("修改失败：%@", String(describing: error.localizedDescription)))
        }
        return AdapterOutput(output: ek.eventJSON(e), targets: [TargetRef(kind: "event", identifier: e.eventIdentifier ?? "")])
    }

    public func readback(_ a: JSONValue, output: AdapterOutput?) async -> JSONValue? {
        ek.store.refreshSourcesIfNecessary()
        guard let id = a["id"]?.stringValue, let e = ek.store.event(withIdentifier: id) else { return nil }
        // Only report "completed" when the stored event really carries the requested values.
        if let t = a["title"]?.stringValue, e.title != t { return nil }
        if let s = Args.date(a["start"]), e.startDate != s { return nil }
        if let end = Args.date(a["end"]), e.endDate != end { return nil }
        if let location = a["location"]?.stringValue, (e.location ?? "") != location { return nil }
        return ek.eventJSON(e)
    }
}

public struct CalendarDeleteTool: ToolAdapter {
    let ek: EventKitBridge
    public init(_ ek: EventKitBridge) { self.ek = ek }

    public var definition: ToolDefinition {
        ToolDefinition(name: "calendar_delete_event", summary: CoreLocalization.text("删除日程（需用户确认；重复日程仅删除本次）"),
                       inputSchema: Args.schema(["id": Args.stringProp], required: ["id"]),
                       source: .calendar, effect: .write, writeKind: .delete, confirmation: .always, externallyExposable: true)
    }

    public func preview(_ a: JSONValue) async throws -> ConfirmationPreview {
        try ek.requireCalendar()
        let e = try ek.event(try Args.requiredString(a, "id"))
        guard e.calendar?.allowsContentModifications == true else { throw ToolError(.targetReadOnly, CoreLocalization.text("该日程所在日历只读")) }
        return ConfirmationPreview(target: "日程「\(e.title ?? "")」", changes: ["删除 \(Args.iso(e.startDate)) 的这次日程"],
                                   note: e.hasRecurrenceRules ? "重复日程：仅删除本次" : nil)
    }

    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        _ = try await preview(a)
        let id = try Args.requiredString(a, "id")
        let e = try ek.event(id)
        do { try ek.store.remove(e, span: .thisEvent, commit: true) } catch {
            throw ToolError(.adapterFailure, CoreLocalization.format("删除失败：%@", String(describing: error.localizedDescription)))
        }
        return AdapterOutput(output: ["deleted": .string(id)], targets: [TargetRef(kind: "event", identifier: id)])
    }

    public func readback(_ a: JSONValue, output: AdapterOutput?) async -> JSONValue? {
        guard let id = a["id"]?.stringValue else { return nil }
        return ek.store.event(withIdentifier: id) == nil ? ["deleted": .string(id), "verified": true] : nil
    }
}

// MARK: Reminders

public struct RemindersListTool: ToolAdapter {
    let ek: EventKitBridge
    public init(_ ek: EventKitBridge) { self.ek = ek }

    public var definition: ToolDefinition {
        ToolDefinition(name: "reminders_list", summary: CoreLocalization.text("列出未完成的提醒事项"),
                       inputSchema: Args.schema(["limit": Args.intProp], required: []),
                       source: .reminders, effect: .read, confirmation: .never, externallyExposable: true)
    }

    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        try ek.requireReminders()
        let limit = Args.int(a["limit"], default: 50, max: 200)
        _ = try ek.calendars(for: .reminder)
        let pred = ek.store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let items: [JSONValue] = try await withCheckedThrowingContinuation { cont in
            ek.store.fetchReminders(matching: pred) { rs in
                guard let rs else {
                    cont.resume(throwing: ToolError(.adapterFailure, CoreLocalization.text("系统提醒事项读取失败，不能据此判断没有提醒事项。请重新打开 Asky 后重试。")))
                    return
                }
                cont.resume(returning: rs.prefix(limit).map { r in
                    var o: [String: JSONValue] = ["id": .string(r.calendarItemIdentifier), "title": .string(r.title ?? ""),
                                                  "list": .string(r.calendar?.title ?? "")]
                    if let d = r.dueDateComponents?.date { o["due"] = .string(Args.iso(d)) }
                    return .object(o)
                })
            }
        }
        return AdapterOutput(output: .array(items))
    }
}

public struct RemindersCreateTool: ToolAdapter {
    let ek: EventKitBridge
    public init(_ ek: EventKitBridge) { self.ek = ek }

    public var definition: ToolDefinition {
        ToolDefinition(name: "reminders_create", summary: CoreLocalization.text("新建提醒事项"),
                       inputSchema: Args.schema(["title": Args.stringProp, "due": Args.isoDateProp, "notes": Args.stringProp],
                                                required: ["title"]),
                       source: .reminders, effect: .write, writeKind: .create, confirmation: .createDirectOtherwiseConfirm,
                       externallyExposable: true)
    }

    public func preview(_ a: JSONValue) async throws -> ConfirmationPreview {
        try ek.requireReminders()
        _ = try ek.calendars(for: .reminder)
        guard let cal = ek.store.defaultCalendarForNewReminders(), cal.allowsContentModifications else {
            throw ToolError(.targetReadOnly, CoreLocalization.text("默认提醒列表不可写"))
        }
        var changes = ["新建提醒「\(try Args.requiredString(a, "title"))」"]
        if let d = Args.date(a["due"]) { changes.append("到期：\(Args.iso(d))") }
        return ConfirmationPreview(target: "提醒列表「\(cal.title)」", changes: changes)
    }

    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        _ = try await preview(a)
        let r = EKReminder(eventStore: ek.store)
        r.title = try Args.requiredString(a, "title")
        r.notes = a["notes"]?.stringValue
        r.calendar = ek.store.defaultCalendarForNewReminders()
        if let d = Args.date(a["due"]) {
            r.dueDateComponents = Calendar.current.dateComponents(in: .current, from: d)
            r.addAlarm(EKAlarm(absoluteDate: d))
        }
        do { try ek.store.save(r, commit: true) } catch {
            throw ToolError(.adapterFailure, CoreLocalization.format("保存提醒失败：%@", String(describing: error.localizedDescription)))
        }
        var out: [String: JSONValue] = [
            "id": .string(r.calendarItemIdentifier),
            "title": .string(r.title ?? ""),
            "list": .string(r.calendar?.title ?? ""),
        ]
        if let d = r.dueDateComponents?.date { out["due"] = .string(Args.iso(d)) }
        return AdapterOutput(output: .object(out),
                             targets: [TargetRef(kind: "reminder", identifier: r.calendarItemIdentifier)])
    }

    public func readback(_ a: JSONValue, output: AdapterOutput?) async -> JSONValue? {
        guard let id = output?.targets.first?.identifier, let item = ek.store.calendarItem(withIdentifier: id) as? EKReminder else { return nil }
        var out: [String: JSONValue] = [
            "id": .string(id),
            "title": .string(item.title ?? ""),
            "completed": .bool(item.isCompleted),
            "list": .string(item.calendar?.title ?? ""),
        ]
        if let d = item.dueDateComponents?.date { out["due"] = .string(Args.iso(d)) }
        return .object(out)
    }
}
