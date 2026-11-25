import Foundation

/// Structured native result card derived directly from a completed `ToolService` execution.
/// Cards are built deterministically from authoritative tool outputs/readbacks rather than
/// model-authored prose, and persisted inside `MessagePresentation`.
public struct ToolResultCard: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case calendarEvent
        case calendarSchedule
        case reminder
        case reminderList
        case note
        case messagesDraft
        case mapRoutes
        case mapPlaces
        case shortcut
        case memory
    }

    public struct Action: Sendable, Hashable, Codable {
        public enum Kind: String, Sendable, Hashable, Codable {
            case openCalendar
            case openReminders
            case openNotes
            case openMessagesDraft
            case openMaps
            case openMemoryFile
            case openShortcuts
        }

        public var kind: Kind
        public var label: String
        public var target: String?
        public var detail: String?

        public init(kind: Kind, label: String, target: String? = nil, detail: String? = nil) {
            self.kind = kind
            self.label = label
            self.target = target
            self.detail = detail
        }
    }

    public struct DetailRow: Sendable, Hashable, Codable, Identifiable {
        public var id: String
        public var title: String
        public var subtitle: String?
        public var trailing: String?
        public var badge: String?

        public init(id: String = UUID().uuidString, title: String, subtitle: String? = nil,
                    trailing: String? = nil, badge: String? = nil) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.trailing = trailing
            self.badge = badge
        }
    }

    public var id: String
    public var kind: Kind
    public var source: DataSourceID
    public var categoryTitle: String
    public var headline: String
    public var title: String
    public var subtitle: String?
    public var metadata: [String]
    public var rows: [DetailRow]
    public var footnote: String?
    public var action: Action?

    public init(id: String, kind: Kind, source: DataSourceID, categoryTitle: String,
                headline: String, title: String = "", subtitle: String? = nil,
                metadata: [String] = [], rows: [DetailRow] = [],
                footnote: String? = nil, action: Action? = nil) {
        self.id = id
        self.kind = kind
        self.source = source
        self.categoryTitle = categoryTitle
        self.headline = headline
        self.title = title
        self.subtitle = subtitle
        self.metadata = metadata
        self.rows = rows
        self.footnote = footnote
        self.action = action
    }

    /// Build a capability-specific result card from a completed tool execution.
    /// Returns `nil` for non-completed executions or tools without a dedicated card.
    public static func from(
        tool: String,
        arguments: JSONValue? = nil,
        result: ExecutionResult,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ToolResultCard? {
        guard result.status == .completed else { return nil }
        let payload = result.readback ?? result.output
        let id = result.requestID

        switch tool {
        case "calendar_create_event", "calendar_update_event":
            return calendarEventCard(id: id, isUpdate: tool == "calendar_update_event",
                                     payload: payload, calendar: calendar)
        case "calendar_search_events":
            return calendarScheduleCard(id: id, payload: result.output, calendar: calendar)
        case "reminders_create":
            return reminderCard(id: id, payload: payload, output: result.output,
                                arguments: arguments, calendar: calendar)
        case "reminders_list":
            return reminderListCard(id: id, payload: result.output, calendar: calendar)
        case "notes_create", "notes_append":
            return noteCard(id: id, isAppend: tool == "notes_append",
                            payload: payload, output: result.output,
                            arguments: arguments, targets: result.targets)
        case "messages_prepare_draft":
            return messagesDraftCard(id: id, output: result.output,
                                     arguments: arguments, targets: result.targets)
        case "maps_routes":
            return mapRoutesCard(id: id, output: result.output, calendar: calendar)
        case "maps_search_places":
            return mapPlacesCard(id: id, output: result.output)
        case "shortcuts_run":
            return shortcutCard(id: id, payload: payload, arguments: arguments)
        case "memory_save", "memory_correct", "memory_forget":
            return memoryCard(id: id, tool: tool, output: result.output,
                              arguments: arguments, targets: result.targets)
        default:
            return nil
        }
    }

    /// Normalizes legacy persisted cards (created before noise-cleanup & date-headline updates)
    /// into the current display representation. Safe and idempotent on newly built cards.
    public func normalizedForDisplay(calendar: Calendar = .current) -> ToolResultCard {
        var copy = self
        copy.footnote = nil

        switch kind {
        case .note:
            if copy.title.isEmpty, let legacyExcerpt = Self.nonEmpty(footnote) {
                copy.title = legacyExcerpt
            }
            copy.subtitle = nil
            copy.metadata = []

        case .reminder:
            copy.metadata = []
            if let subtitle = copy.subtitle {
                let parts = subtitle
                    .components(separatedBy: " · ")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !Self.isDefaultReminderList($0) }
                copy.subtitle = parts.isEmpty ? nil : parts.joined(separator: " · ")
            }

        case .memory:
            copy.subtitle = nil

        case .mapPlaces:
            if !copy.rows.isEmpty, Self.isLegacyCountHeadline(copy.headline, suffixes: ["个地点", "places", "place"]) {
                copy.headline = ""
            }

        case .calendarEvent:
            let allDayLabel = CoreLocalization.text("全天")
            let normalizedHeadline = copy.headline.trimmingCharacters(in: .whitespacesAndNewlines)
            if (normalizedHeadline == allDayLabel || normalizedHeadline == "全天" || normalizedHeadline.lowercased() == "all day"),
               normalizedHeadline != copy.title {
                let parts = (copy.subtitle ?? "")
                    .components(separatedBy: " · ")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let isoDate = copy.action?.target.flatMap(Self.parseISO)
                if let isoDate {
                    copy.headline = Self.formatMonthDayWeekday(isoDate, calendar: calendar)
                    var remaining = parts
                    if let first = remaining.first, Self.parseLeadingShortDate(first) != nil {
                        remaining.removeFirst()
                    }
                    copy.subtitle = ([allDayLabel] + remaining).joined(separator: " · ")
                } else if let first = parts.first, Self.parseLeadingShortDate(first) != nil {
                    copy.headline = first
                    let remaining = Array(parts.dropFirst())
                    copy.subtitle = ([allDayLabel] + remaining).joined(separator: " · ")
                }
            }

        case .calendarSchedule:
            if Self.isLegacyCountHeadline(copy.headline, suffixes: ["个日程", "events", "event"]) {
                let parsedRowDates = copy.rows.map { row -> (month: Int, day: Int)? in
                    guard let sub = row.subtitle else { return nil }
                    return Self.parseLeadingShortDate(sub)?.date
                }
                let validDates = parsedRowDates.compactMap { $0 }
                let allRowsHaveDate = validDates.count == copy.rows.count && !validDates.isEmpty
                let singleDay: Bool = {
                    guard allRowsHaveDate, let first = validDates.first else { return false }
                    return validDates.allSatisfy { $0.month == first.month && $0.day == first.day }
                }()

                let actionDate = copy.action?.target.flatMap(Self.parseISO)
                if singleDay, let first = validDates.first {
                    if let actionDate,
                       calendar.component(.month, from: actionDate) == first.month,
                       calendar.component(.day, from: actionDate) == first.day {
                        copy.headline = Self.formatMonthDayWeekday(actionDate, calendar: calendar)
                    } else {
                        copy.headline = "\(first.month)月\(first.day)日"
                    }
                } else if !validDates.isEmpty {
                    let ordered = Self.monthDayRange(validDates)
                    copy.headline = Self.formatMonthDayRange(ordered.earliest, ordered.latest)
                } else if let actionDate {
                    copy.headline = Self.formatMonthDayWeekday(actionDate, calendar: calendar)
                } else {
                    copy.headline = ""
                }

                copy.rows = zip(copy.rows, parsedRowDates).map { row, rowDate in
                    var updated = row
                    updated.subtitle = nil
                    if !singleDay, let rowDate {
                        let datePrefix = "\(rowDate.month)月\(rowDate.day)日"
                        if let trailing = Self.nonEmpty(updated.trailing) {
                            if !trailing.hasPrefix(datePrefix) {
                                let compactTime = trailing.components(separatedBy: "–").first?.trimmingCharacters(in: .whitespaces) ?? trailing
                                updated.trailing = "\(datePrefix) \(compactTime)"
                            }
                        } else {
                            updated.trailing = datePrefix
                        }
                    }
                    return updated
                }
            }

        case .reminderList:
            let legacyHeadline = Self.isLegacyCountHeadline(copy.headline, suffixes: ["条待办", "条提醒", "reminders", "reminder", "items", "item"])
            var parsedRowDates: [(date: (month: Int, day: Int), rest: String)?] = []
            copy.rows = copy.rows.map { row in
                var updated = row
                updated.subtitle = nil
                parsedRowDates.append(row.trailing.flatMap(Self.parseLeadingShortDate))
                return updated
            }
            if legacyHeadline {
                let validDates = parsedRowDates.compactMap { $0?.date }
                let allHaveDue = validDates.count == copy.rows.count && !validDates.isEmpty
                let singleDay: Bool = {
                    guard allHaveDue, let first = validDates.first else { return false }
                    return validDates.allSatisfy { $0.month == first.month && $0.day == first.day }
                }()
                if singleDay, let first = validDates.first {
                    copy.headline = "\(first.month)月\(first.day)日"
                    copy.rows = zip(copy.rows, parsedRowDates).map { row, parsed in
                        var updated = row
                        if let rest = Self.nonEmpty(parsed?.rest) {
                            updated.trailing = rest
                        }
                        return updated
                    }
                } else if allHaveDue {
                    let ordered = Self.monthDayRange(validDates)
                    copy.headline = Self.formatMonthDayRange(ordered.earliest, ordered.latest)
                } else {
                    copy.headline = ""
                }
            }

        case .messagesDraft, .mapRoutes, .shortcut:
            break
        }

        return copy
    }

    // MARK: - Builders

    private static func calendarEventCard(
        id: String, isUpdate: Bool, payload: JSONValue?, calendar: Calendar
    ) -> ToolResultCard? {
        guard let payload, let title = nonEmpty(payload["title"]?.stringValue) else { return nil }
        let startISO = payload["start"]?.stringValue
        let endISO = payload["end"]?.stringValue
        let allDay = payload["allDay"]?.boolValue ?? false
        let calName = nonEmpty(payload["calendar"]?.stringValue)
        let location = nonEmpty(payload["location"]?.stringValue)

        let startDate = startISO.flatMap(parseISO)
        let endDate = endISO.flatMap(parseISO)

        let headline: String
        var subtitleParts: [String] = []
        if allDay {
            headline = startDate.map { formatMonthDayWeekday($0, calendar: calendar) } ?? CoreLocalization.text("全天")
            if startDate != nil { subtitleParts.append(CoreLocalization.text("全天")) }
        } else if let startDate, let endDate {
            headline = "\(formatTime(startDate, calendar: calendar)) – \(formatTime(endDate, calendar: calendar))"
            subtitleParts.append(formatMonthDayWeekday(startDate, calendar: calendar))
        } else if let startDate {
            headline = formatTime(startDate, calendar: calendar)
            subtitleParts.append(formatMonthDayWeekday(startDate, calendar: calendar))
        } else {
            headline = title
        }
        if let calName { subtitleParts.append(calName) }

        var meta: [String] = []
        if let location { meta.append(location) }

        return ToolResultCard(
            id: id,
            kind: .calendarEvent,
            source: .calendar,
            categoryTitle: isUpdate ? CoreLocalization.text("已更新日程") : CoreLocalization.text("日历"),
            headline: headline,
            title: title,
            subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · "),
            metadata: meta,
            action: Action(kind: .openCalendar, label: CoreLocalization.text("查看日历"), target: startISO)
        )
    }

    private static func calendarScheduleCard(
        id: String, payload: JSONValue?, calendar: Calendar
    ) -> ToolResultCard? {
        guard let items = payload?.arrayValue, !items.isEmpty else { return nil }
        let shownItems = Array(items.prefix(5))
        let dates = shownItems.compactMap { $0["start"]?.stringValue.flatMap(parseISO) }
        let singleDay: Bool = {
            guard let first = dates.first else { return false }
            return dates.count == shownItems.count && dates.allSatisfy { calendar.isDate($0, inSameDayAs: first) }
        }()
        let headline: String = {
            guard let earliest = dates.min(), let latest = dates.max() else { return "" }
            return formatDateRange(earliest, latest, calendar: calendar)
        }()

        let rows: [DetailRow] = shownItems.enumerated().compactMap { index, item in
            guard let title = nonEmpty(item["title"]?.stringValue) else { return nil }
            let allDay = item["allDay"]?.boolValue ?? false
            let start = item["start"]?.stringValue.flatMap(parseISO)
            let end = item["end"]?.stringValue.flatMap(parseISO)
            let location = nonEmpty(item["location"]?.stringValue)

            let timePart: String?
            if allDay {
                timePart = CoreLocalization.text("全天")
            } else if let start, let end, singleDay {
                timePart = "\(formatTime(start, calendar: calendar))–\(formatTime(end, calendar: calendar))"
            } else if let start {
                timePart = formatTime(start, calendar: calendar)
            } else {
                timePart = nil
            }

            let trailing: String?
            if singleDay {
                trailing = timePart
            } else if let start, let timePart {
                trailing = "\(formatShortDate(start, calendar: calendar)) \(timePart)"
            } else if let start {
                trailing = formatShortDate(start, calendar: calendar)
            } else {
                trailing = timePart
            }

            return DetailRow(
                id: nonEmpty(item["id"]?.stringValue) ?? "\(id)-\(index)",
                title: title,
                subtitle: location,
                trailing: trailing
            )
        }
        guard !rows.isEmpty else { return nil }
        let firstStart = shownItems.first?["start"]?.stringValue

        return ToolResultCard(
            id: id,
            kind: .calendarSchedule,
            source: .calendar,
            categoryTitle: CoreLocalization.text("日历日程"),
            headline: headline,
            rows: rows,
            action: Action(kind: .openCalendar, label: CoreLocalization.text("查看日历"), target: firstStart)
        )
    }

    private static func reminderCard(
        id: String, payload: JSONValue?, output: JSONValue?, arguments: JSONValue?, calendar: Calendar
    ) -> ToolResultCard? {
        let title = nonEmpty(payload?["title"]?.stringValue)
            ?? nonEmpty(output?["title"]?.stringValue)
            ?? nonEmpty(arguments?["title"]?.stringValue)
        guard let title else { return nil }

        let dueISO = nonEmpty(payload?["due"]?.stringValue)
            ?? nonEmpty(output?["due"]?.stringValue)
            ?? nonEmpty(arguments?["due"]?.stringValue)
        let listName = nonEmpty(payload?["list"]?.stringValue)
            ?? nonEmpty(output?["list"]?.stringValue)

        let dueDate = dueISO.flatMap(parseISO)
        let headline = dueDate.map { formatTime($0, calendar: calendar) } ?? title
        let displayTitle = dueDate != nil ? title : ""

        var subParts: [String] = []
        if let dueDate { subParts.append(formatMonthDayWeekday(dueDate, calendar: calendar)) }
        if let listName, !isDefaultReminderList(listName) { subParts.append(listName) }

        return ToolResultCard(
            id: id,
            kind: .reminder,
            source: .reminders,
            categoryTitle: CoreLocalization.text("提醒事项"),
            headline: headline,
            title: displayTitle,
            subtitle: subParts.isEmpty ? nil : subParts.joined(separator: " · "),
            action: Action(kind: .openReminders, label: CoreLocalization.text("查看提醒事项"))
        )
    }

    private static func reminderListCard(
        id: String, payload: JSONValue?, calendar: Calendar
    ) -> ToolResultCard? {
        guard let items = payload?.arrayValue, !items.isEmpty else { return nil }
        let shownItems = Array(items.prefix(5))
        let dueDates = shownItems.compactMap { $0["due"]?.stringValue.flatMap(parseISO) }
        let allHaveDue = dueDates.count == shownItems.count
        let singleDay: Bool = {
            guard allHaveDue, let first = dueDates.first else { return false }
            return dueDates.allSatisfy { calendar.isDate($0, inSameDayAs: first) }
        }()
        let headline: String = {
            guard allHaveDue, let earliest = dueDates.min(), let latest = dueDates.max() else { return "" }
            return formatDateRange(earliest, latest, calendar: calendar)
        }()

        let rows: [DetailRow] = shownItems.enumerated().compactMap { index, item in
            guard let title = nonEmpty(item["title"]?.stringValue) else { return nil }
            let due = item["due"]?.stringValue.flatMap(parseISO)
            let trailing: String?
            if let due {
                trailing = singleDay
                    ? formatTime(due, calendar: calendar)
                    : "\(formatShortDate(due, calendar: calendar)) \(formatTime(due, calendar: calendar))"
            } else {
                trailing = nil
            }
            return DetailRow(
                id: nonEmpty(item["id"]?.stringValue) ?? "\(id)-\(index)",
                title: title,
                trailing: trailing
            )
        }
        guard !rows.isEmpty else { return nil }

        return ToolResultCard(
            id: id,
            kind: .reminderList,
            source: .reminders,
            categoryTitle: CoreLocalization.text("提醒事项"),
            headline: headline,
            rows: rows,
            action: Action(kind: .openReminders, label: CoreLocalization.text("查看提醒事项"))
        )
    }

    private static func noteCard(
        id: String, isAppend: Bool, payload: JSONValue?, output: JSONValue?,
        arguments: JSONValue?, targets: [TargetRef]
    ) -> ToolResultCard? {
        let title = nonEmpty(payload?["name"]?.stringValue)
            ?? nonEmpty(output?["name"]?.stringValue)
            ?? nonEmpty(arguments?["title"]?.stringValue)
            ?? CoreLocalization.text("备忘录")
        let excerpt = nonEmpty(arguments?["body"]?.stringValue)
            ?? nonEmpty(arguments?["text"]?.stringValue)
        let noteID = nonEmpty(payload?["id"]?.stringValue)
            ?? nonEmpty(output?["id"]?.stringValue)
            ?? targets.first?.identifier

        return ToolResultCard(
            id: id,
            kind: .note,
            source: .notes,
            categoryTitle: isAppend ? CoreLocalization.text("已追加备忘录") : CoreLocalization.text("备忘录"),
            headline: title,
            title: excerpt.map { truncate($0, limit: 120) } ?? "",
            action: Action(kind: .openNotes, label: CoreLocalization.text("打开备忘录"), target: noteID)
        )
    }

    private static func messagesDraftCard(
        id: String, output: JSONValue?, arguments: JSONValue?, targets: [TargetRef]
    ) -> ToolResultCard? {
        guard let output else { return nil }
        let recipient = nonEmpty(output["recipient"]?.stringValue) ?? targets.first?.identifier
        guard let recipient else { return nil }
        let body = nonEmpty(output["body"]?.stringValue) ?? nonEmpty(arguments?["body"]?.stringValue) ?? ""
        let handle = nonEmpty(output["handle"]?.stringValue) ?? targets.first?.identifier

        return ToolResultCard(
            id: id,
            kind: .messagesDraft,
            source: .messages,
            categoryTitle: CoreLocalization.text("信息草稿"),
            headline: recipient,
            title: truncate(body, limit: 160),
            action: Action(kind: .openMessagesDraft, label: CoreLocalization.text("在信息中打开"),
                           target: handle, detail: body)
        )
    }

    private static func mapRoutesCard(
        id: String, output: JSONValue?, calendar: Calendar
    ) -> ToolResultCard? {
        guard let output, let routes = output["routes"]?.arrayValue, !routes.isEmpty else { return nil }
        let origin = nonEmpty(output["origin"]?["name"]?.stringValue) ?? CoreLocalization.text("起点")
        let dest = nonEmpty(output["destination"]?["name"]?.stringValue) ?? CoreLocalization.text("终点")
        let destLat = output["destination"]?["latitude"]?.numberValue
        let destLon = output["destination"]?["longitude"]?.numberValue
        let coordTarget = (destLat != nil && destLon != nil) ? "\(destLat!),\(destLon!)" : nil

        let rows: [DetailRow] = routes.enumerated().compactMap { index, route in
            guard let mode = route["mode"]?.stringValue,
                  let seconds = route["durationSeconds"]?.numberValue else { return nil }
            let meters = route["distanceMeters"]?.numberValue
            let departISO = route["suggestedDepartureTime"]?.stringValue
            let departDate = departISO.flatMap(parseISO)

            var subParts: [String] = []
            if let meters, meters > 0 { subParts.append(formatDistance(meters)) }
            if let departDate {
                subParts.append(CoreLocalization.format("建议 %@ 出发", formatTime(departDate, calendar: calendar)))
            }

            return DetailRow(
                id: "\(id)-\(mode)-\(index)",
                title: transportLabel(mode),
                subtitle: subParts.isEmpty ? nil : subParts.joined(separator: " · "),
                trailing: formatDuration(seconds)
            )
        }
        guard !rows.isEmpty else { return nil }

        return ToolResultCard(
            id: id,
            kind: .mapRoutes,
            source: .maps,
            categoryTitle: CoreLocalization.text("路线时间"),
            headline: "\(origin) → \(dest)",
            rows: rows,
            action: Action(kind: .openMaps, label: CoreLocalization.text("在地图中查看"),
                           target: coordTarget, detail: dest)
        )
    }

    private static func mapPlacesCard(id: String, output: JSONValue?) -> ToolResultCard? {
        guard let places = output?["places"]?.arrayValue, !places.isEmpty else { return nil }
        let rows: [DetailRow] = places.prefix(4).enumerated().compactMap { index, place in
            guard let name = nonEmpty(place["name"]?.stringValue) else { return nil }
            let address = nonEmpty(place["address"]?.stringValue)
            return DetailRow(id: "\(id)-\(index)", title: name, subtitle: address)
        }
        guard !rows.isEmpty else { return nil }
        let first = places.first
        let lat = first?["latitude"]?.numberValue
        let lon = first?["longitude"]?.numberValue
        let coordTarget = (lat != nil && lon != nil) ? "\(lat!),\(lon!)" : nil
        let firstName = nonEmpty(first?["name"]?.stringValue)

        let headline = places.count == 1
            ? (firstName ?? CoreLocalization.text("地点"))
            : ""

        return ToolResultCard(
            id: id,
            kind: .mapPlaces,
            source: .maps,
            categoryTitle: CoreLocalization.text("地点"),
            headline: headline,
            subtitle: places.count == 1 ? nonEmpty(first?["address"]?.stringValue) : nil,
            rows: places.count == 1 ? [] : rows,
            action: Action(kind: .openMaps, label: CoreLocalization.text("在地图中查看"),
                           target: coordTarget, detail: firstName)
        )
    }

    private static func shortcutCard(
        id: String, payload: JSONValue?, arguments: JSONValue?
    ) -> ToolResultCard? {
        let name = nonEmpty(payload?["name"]?.stringValue) ?? nonEmpty(arguments?["name"]?.stringValue)
        guard let name else { return nil }
        let out = nonEmpty(payload?["output"]?.stringValue)
        return ToolResultCard(
            id: id,
            kind: .shortcut,
            source: .shortcuts,
            categoryTitle: CoreLocalization.text("快捷指令"),
            headline: name,
            subtitle: out.map { truncate($0, limit: 120) } ?? CoreLocalization.text("已运行完成"),
            action: Action(kind: .openShortcuts, label: CoreLocalization.text("打开快捷指令"))
        )
    }

    private static func memoryCard(
        id: String, tool: String, output: JSONValue?, arguments: JSONValue?, targets: [TargetRef]
    ) -> ToolResultCard? {
        let file = nonEmpty(output?["file"]?.stringValue)
            ?? targets.first?.identifier
            ?? nonEmpty(arguments?["file"]?.stringValue)
            ?? "MEMORY.md"
        let content = nonEmpty(arguments?["content"]?.stringValue)
            ?? nonEmpty(arguments?["old"]?.stringValue)
            ?? ""
        let headline: String
        switch tool {
        case "memory_save": headline = CoreLocalization.text("已记住")
        case "memory_correct": headline = CoreLocalization.text("已更新记忆")
        case "memory_forget": headline = CoreLocalization.text("已移除记忆")
        default: headline = CoreLocalization.text("记忆")
        }

        return ToolResultCard(
            id: id,
            kind: .memory,
            source: .memory,
            categoryTitle: CoreLocalization.text("记忆"),
            headline: headline,
            title: truncate(content, limit: 160),
            action: Action(kind: .openMemoryFile, label: CoreLocalization.text("查看记忆"), target: file)
        )
    }

    // MARK: - Formatting helpers

    private static func isDefaultReminderList(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "提醒" || normalized == "提醒事项" || normalized == "reminders"
    }

    private static func isLegacyCountHeadline(_ headline: String, suffixes: [String]) -> Bool {
        let trimmed = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return false }
        let remainder = trimmed.dropFirst(digits.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return suffixes.contains { remainder == $0.lowercased() }
    }

    private static func parseLeadingShortDate(_ raw: String) -> (date: (month: Int, day: Int), rest: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let monthDigits = trimmed.prefix { $0.isASCII && $0.isNumber }
        guard (1...2).contains(monthDigits.count), let month = Int(monthDigits), (1...12).contains(month) else {
            return nil
        }
        let afterMonth = trimmed.dropFirst(monthDigits.count)
        guard afterMonth.first == "月" else { return nil }
        let afterMonthMark = afterMonth.dropFirst()
        let dayDigits = afterMonthMark.prefix { $0.isASCII && $0.isNumber }
        guard (1...2).contains(dayDigits.count), let day = Int(dayDigits), (1...31).contains(day) else {
            return nil
        }
        let afterDay = afterMonthMark.dropFirst(dayDigits.count)
        guard afterDay.first == "日" else { return nil }
        let rest = String(afterDay.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        return ((month, day), rest)
    }

    private static func monthDayRange(_ dates: [(month: Int, day: Int)]) -> (earliest: (month: Int, day: Int), latest: (month: Int, day: Int)) {
        let key: ((month: Int, day: Int)) -> Int = { $0.month * 100 + $0.day }
        let minDate = dates.min { key($0) < key($1) }!
        let maxDate = dates.max { key($0) < key($1) }!
        if maxDate.month - minDate.month > 6 {
            let lateYear = dates.filter { $0.month >= 7 }.min { key($0) < key($1) } ?? minDate
            let earlyYear = dates.filter { $0.month <= 6 }.max { key($0) < key($1) } ?? maxDate
            return (lateYear, earlyYear)
        }
        return (minDate, maxDate)
    }

    private static func formatMonthDayRange(_ start: (month: Int, day: Int), _ end: (month: Int, day: Int)) -> String {
        if start.month == end.month && start.day == end.day {
            return "\(start.month)月\(start.day)日"
        }
        if start.month == end.month {
            return "\(start.month)月\(start.day)日 – \(end.day)日"
        }
        return "\(start.month)月\(start.day)日 – \(end.month)月\(end.day)日"
    }

    private static func formatDateRange(_ start: Date, _ end: Date, calendar: Calendar) -> String {
        if calendar.isDate(start, inSameDayAs: end) {
            return formatMonthDayWeekday(start, calendar: calendar)
        }
        let s = calendar.dateComponents([.year, .month, .day], from: start)
        let e = calendar.dateComponents([.year, .month, .day], from: end)
        if s.year == e.year, s.month == e.month, let eDay = e.day {
            return "\(formatShortDate(start, calendar: calendar)) – \(eDay)日"
        }
        return "\(formatShortDate(start, calendar: calendar)) – \(formatShortDate(end, calendar: calendar))"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func truncate(_ value: String, limit: Int) -> String {
        let single = value.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard single.count > limit else { return single }
        return String(single.prefix(limit)) + "…"
    }

    private static func parseISO(_ raw: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: raw) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: raw)
    }

    private static func formatTime(_ date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    private static func formatShortDate(_ date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.month, .day], from: date)
        return "\(comps.month ?? 0)月\(comps.day ?? 0)日"
    }

    private static func formatMonthDayWeekday(_ date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.month, .day, .weekday], from: date)
        let weekdays = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let wd = (comps.weekday ?? 0)
        let wdLabel = (1...7).contains(wd) ? weekdays[wd] : ""
        return "\(comps.month ?? 0)月\(comps.day ?? 0)日 \(wdLabel)".trimmingCharacters(in: .whitespaces)
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let totalMinutes = max(1, Int((seconds / 60).rounded()))
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if hours > 0 && mins > 0 { return "\(hours) 小时 \(mins) 分钟" }
        if hours > 0 { return "\(hours) 小时" }
        return "\(mins) 分钟"
    }

    private static func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters.rounded())) m"
    }

    private static func transportLabel(_ mode: String) -> String {
        switch mode {
        case "walking": CoreLocalization.text("步行")
        case "transit": CoreLocalization.text("公交")
        case "driving": CoreLocalization.text("驾车")
        default: mode
        }
    }
}
