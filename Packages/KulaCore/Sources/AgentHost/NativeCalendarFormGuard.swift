import Foundation
import Contracts

/// Validates that calendar-creation `asky-form` drafts query live calendars first
/// and include a preselected `radio` selector when multiple writable calendars exist.
enum NativeCalendarFormGuard {
    struct WritableCalendar: Equatable, Sendable {
        let name: String
        let isDefault: Bool
    }

    struct FormField: Equatable, Sendable {
        let id: String
        let type: String
        let label: String
        let options: [String]
        let allowCustom: Bool
        let defaultValue: String?
    }

    static func writableCalendars(from toolResult: JSONValue) -> [WritableCalendar]? {
        guard toolResult["status"]?.stringValue == "completed",
              let rows = toolResult["output"]?.arrayValue else {
            return nil
        }
        return rows.compactMap { row in
            guard row["writable"]?.boolValue == true,
                  let rawName = row["name"]?.stringValue else { return nil }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return WritableCalendar(name: name, isDefault: row["isDefault"]?.boolValue == true)
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
        let expectedNames = uniqueNames(from: writableCalendars)
        guard expectedNames.count > 1 else { return true }
        let expectedSet = Set(expectedNames)
        return fields.contains { field in
            let kind = field.type.lowercased()
            guard (kind == "radio" || kind == "select"), !field.allowCustom else { return false }
            guard Set(field.options) == expectedSet else { return false }
            guard let def = field.defaultValue, expectedSet.contains(def) else { return false }
            return true
        }
    }

    static func correction(
        draft: String,
        userText: String,
        calendarListFetched: Bool,
        writableCalendars: [WritableCalendar]?
    ) -> String? {
        let fields = formFields(in: draft)
        guard isCalendarCreationForm(draft: draft, userText: userText, fields: fields) else { return nil }

        if !calendarListFetched {
            return "上一份草稿在未调用 calendar_list_calendars 的情况下直接输出了新建日程表单，已被拦截且没有展示。在输出新建日程的 asky-form 表单前，必须先在本轮调用 calendar_list_calendars 获取当前真实可写日历列表与默认日历；不要跳过该查询。调用后再根据返回结果输出表单：若存在多个可写日历，必须加入目标日历单选字段（type 为 radio，不设 allowCustom），options 严格列出本次返回的实时可写日历名称，并用 defaultValue 预选用户指定日历、可写默认日历或首个可写日历。请勿提及内部拦截。"
        }

        guard let writableCalendars else { return nil }
        let orderedNames = uniqueNames(from: writableCalendars)
        guard orderedNames.count > 1 else { return nil }
        guard !hasValidCalendarField(fields: fields, writableCalendars: writableCalendars) else { return nil }

        let recommended = writableCalendars.first(where: \.isDefault)?.name ?? orderedNames[0]
        let optionsLiteral = orderedNames.map { "\"\($0)\"" }.joined(separator: ",")
        return "上一份草稿的新建日程表单缺少目标日历单选字段（或选项、预选值不符合本次 calendar_list_calendars 返回的实时可写日历），已被拦截且没有展示。本次共有 \(orderedNames.count) 个可写日历：\(orderedNames.joined(separator: "、"))。请在表单中加入目标日历单选字段（type 为 radio，不设 allowCustom，options 严格使用 [\(optionsLiteral)]，并用 defaultValue 预选用户已指定日历或「\(recommended)」）。重新输出回复与表单，勿提及内部拦截。"
    }

    private static func uniqueNames(from calendars: [WritableCalendar]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for cal in calendars where seen.insert(cal.name).inserted {
            result.append(cal.name)
        }
        return result
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
