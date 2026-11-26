import Foundation
import Contracts

/// Validates that calendar-creation `asky-form` drafts query live calendars first,
/// block form submission when calendar lookup fails, and include a preselected `radio`
/// selector (disambiguating duplicate names by account) when multiple writable calendars exist.
enum NativeCalendarFormGuard {
    struct WritableCalendar: Equatable, Sendable {
        let id: String
        let name: String
        let account: String
        let isDefault: Bool

        init(id: String = "", name: String, account: String = "", isDefault: Bool) {
            self.id = id
            self.name = name
            self.account = account
            self.isDefault = isDefault
        }
    }

    enum CalendarListState: Equatable, Sendable {
        case notFetched
        case failed(String?)
        case loaded([WritableCalendar])
    }

    struct FormField: Equatable, Sendable {
        let id: String
        let type: String
        let label: String
        let options: [String]
        let allowCustom: Bool
        let defaultValue: String?
    }

    static func calendarListState(from toolResult: JSONValue) -> CalendarListState {
        guard toolResult["status"]?.stringValue == "completed" else {
            let reason = toolResult["error"]?["message"]?.stringValue
                ?? toolResult["message"]?.stringValue
            return .failed(reason?.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let rows = toolResult["output"]?.arrayValue else {
            return .failed(nil)
        }
        var seenIDs = Set<String>()
        var result: [WritableCalendar] = []
        for row in rows {
            guard row["writable"]?.boolValue == true,
                  let rawName = row["name"]?.stringValue else { continue }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let id = (row["id"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty, !seenIDs.insert(id).inserted { continue }
            let account = (row["account"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(WritableCalendar(
                id: id,
                name: name,
                account: account,
                isDefault: row["isDefault"]?.boolValue == true
            ))
        }
        return .loaded(result)
    }

    static func optionLabels(for calendars: [WritableCalendar]) -> [String] {
        var nameCounts: [String: Int] = [:]
        var nameAccountCounts: [String: Int] = [:]
        for cal in calendars {
            nameCounts[cal.name, default: 0] += 1
            nameAccountCounts["\(cal.name)\u{0}\(cal.account)", default: 0] += 1
        }
        return calendars.map { cal in
            guard nameCounts[cal.name, default: 0] > 1 else { return cal.name }
            if cal.account.isEmpty {
                return cal.id.isEmpty ? cal.name : "\(cal.name)（\(cal.id)）"
            }
            if nameAccountCounts["\(cal.name)\u{0}\(cal.account)", default: 0] > 1, !cal.id.isEmpty {
                return "\(cal.name)（\(cal.account)，\(cal.id)）"
            }
            return "\(cal.name)（\(cal.account)）"
        }
    }

    static func formFields(in text: String) -> [FormField] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var outerFence: (char: Character, length: Int)?
        var inForm = false
        var fields: [FormField] = []

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if inForm {
                if isClosingFence(trimmed, char: "`", minLength: 3) {
                    break
                }
                guard !trimmed.isEmpty,
                      let data = trimmed.data(using: .utf8),
                      let json = try? JSONDecoder().decode(JSONValue.self, from: data),
                      let id = json["id"]?.stringValue,
                      let type = json["type"]?.stringValue,
                      let label = json["label"]?.stringValue else {
                    continue
                }
                let options = json["options"]?.arrayValue?.compactMap(\.stringValue) ?? []
                let allowCustom = json["allowCustom"]?.boolValue == true
                let defaultValue = json["defaultValue"]?.stringValue
                fields.append(FormField(
                    id: id,
                    type: type,
                    label: label,
                    options: options,
                    allowCustom: allowCustom,
                    defaultValue: defaultValue
                ))
                continue
            }

            if let fence = outerFence {
                if isClosingFence(trimmed, char: fence.char, minLength: fence.length) {
                    outerFence = nil
                }
                continue
            }

            if let opened = openingFence(trimmed) {
                if opened.char == "`" && opened.length == 3 && opened.info == "asky-form" {
                    inForm = true
                } else {
                    outerFence = (opened.char, opened.length)
                }
            }
        }
        return fields
    }

    static func isCalendarCreationForm(draft: String, userText: String, fields: [FormField]) -> Bool {
        guard !fields.isEmpty else { return false }

        let normalizedTypes = Set(fields.map { $0.type.lowercased() })
        let hasDateTimeRange = !normalizedTypes.isDisjoint(with: ["datetime_range", "datetime-range", "datetimerange"])
        let hasTitleField = fields.contains { field in
            let id = field.id.lowercased()
            let label = field.label.lowercased()
            return id.contains("title") || id.contains("subject") || id.contains("summary") || id.contains("event")
                || label.contains("标题") || label.contains("主题") || label.contains("名称") || label.contains("日程") || label.contains("会议")
        }
        let hasTimeField = hasDateTimeRange || fields.contains { field in
            ["datetime", "date", "time", "time_range", "time-range", "timerange"].contains(field.type.lowercased())
                || field.label.contains("时间") || field.label.contains("日期")
        }
        guard hasDateTimeRange || (hasTitleField && hasTimeField) else { return false }

        let combined = (userText + "\n" + draft).lowercased()
        let explicitCalendarKeywords = ["日程", "日历", "calendar", "schedule"]
        if explicitCalendarKeywords.contains(where: { combined.contains($0) }) {
            return true
        }
        let meetingKeywords = ["会议", "约会", "meeting", "appointment"]
        if hasDateTimeRange, meetingKeywords.contains(where: { combined.contains($0) }) {
            return true
        }
        return false
    }

    static func hasValidCalendarField(fields: [FormField], writableCalendars: [WritableCalendar]) -> Bool {
        let expectedOptions = optionLabels(for: writableCalendars)
        guard expectedOptions.count > 1 else { return true }
        let expectedSet = Set(expectedOptions)
        return fields.contains { field in
            let kind = field.type.lowercased()
            guard (kind == "radio" || kind == "select"), !field.allowCustom else { return false }
            guard field.options.count == expectedOptions.count, Set(field.options) == expectedSet else { return false }
            guard let def = field.defaultValue, expectedSet.contains(def) else { return false }
            return true
        }
    }

    static func correction(
        draft: String,
        userText: String,
        calendarListState: CalendarListState
    ) -> String? {
        let fields = formFields(in: draft)
        guard isCalendarCreationForm(draft: draft, userText: userText, fields: fields) else { return nil }

        switch calendarListState {
        case .notFetched:
            return "上一份草稿在未调用 calendar_list_calendars 的情况下直接输出了新建日程表单，已被拦截且没有展示。在输出新建日程的 asky-form 表单前，必须先在本轮调用 calendar_list_calendars 获取当前真实可写日历列表与默认日历；不要跳过该查询。调用后再根据返回结果决定回复：若查询失败或没有可写日历，严禁展示新建日程表单，应说明原因并给出单选「重试」选项；若存在多个可写日历，必须加入目标日历单选字段（type 为 radio，不设 allowCustom），同名日历须在选项中附带所属账户区分，并用 defaultValue 预选用户指定日历、可写默认日历或首个可写日历。请勿提及内部拦截。"

        case .failed(let reason):
            let detail = reason.flatMap { $0.isEmpty ? nil : "（原因：\($0)）" } ?? ""
            return "上一份草稿在 calendar_list_calendars 查询失败\(detail)的情况下仍输出了新建日程表单，已被拦截且没有展示。目标日历未确认时，严禁展示新建日程表单让用户提交。请简短说明无法读取苹果日历的原因，并在回复末尾仅输出一个单选「重试」表单：\n```asky-form\n{\"id\":\"retry_calendar_list\",\"type\":\"radio\",\"label\":\"重新获取日历\",\"options\":[\"重试\"]}\n```\n不要输出标题或时间等日程填写字段，勿提及内部拦截。"

        case .loaded(let writableCalendars):
            if writableCalendars.isEmpty {
                return "上一份草稿在没有可用可写日历的情况下输出了新建日程表单，已被拦截且没有展示。当前苹果日历中没有可写日历，请说明需在系统日历中启用账户或创建日历，不要输出新建日程表单；可附一个单选「重试」表单方便用户处理后重新查询。勿提及内部拦截。"
            }
            guard writableCalendars.count > 1 else { return nil }
            guard !hasValidCalendarField(fields: fields, writableCalendars: writableCalendars) else { return nil }

            let expectedOptions = optionLabels(for: writableCalendars)
            let defaultIndex = writableCalendars.firstIndex(where: \.isDefault) ?? 0
            let recommended = expectedOptions[defaultIndex]
            let optionsLiteral = expectedOptions.map(jsonQuoted).joined(separator: ",")
            let calendarDetails = zip(writableCalendars, expectedOptions).map { cal, label in
                cal.id.isEmpty ? label : "\(label) [ID: \(cal.id)]"
            }.joined(separator: "、")
            return "上一份草稿的新建日程表单缺少目标日历单选字段（或选项、预选值不符合本次 calendar_list_calendars 返回的实时可写日历），已被拦截且没有展示。本次共有 \(writableCalendars.count) 个可写日历：\(calendarDetails)。请在表单中加入目标日历单选字段（type 为 radio，不设 allowCustom，options 严格使用 [\(optionsLiteral)]，并用 defaultValue 预选用户已指定日历或「\(recommended)」）。用户提交后调用 calendar_create_event 时请务必传入所选日历对应的 ID。重新输出回复与表单，勿提及内部拦截。"
        }
    }

    private static func jsonQuoted(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "\"\(value)\""
        }
        return text
    }

    private static func openingFence(_ trimmed: String) -> (char: Character, length: Int, info: String)? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let length = trimmed.prefix(while: { $0 == first }).count
        guard length >= 3 else { return nil }
        let info = trimmed.dropFirst(length).trimmingCharacters(in: .whitespaces)
        if first == "`", info.contains("`") { return nil }
        return (first, length, info)
    }

    private static func isClosingFence(_ trimmed: String, char: Character, minLength: Int) -> Bool {
        guard trimmed.first == char else { return false }
        let length = trimmed.prefix(while: { $0 == char }).count
        guard length >= minLength else { return false }
        return trimmed.dropFirst(length).trimmingCharacters(in: .whitespaces).isEmpty
    }
}
