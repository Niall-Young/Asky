import Foundation

/// A bounded, declarative form carried in the existing text stream. Never executes model code.
struct ChatForm: Equatable {
    enum TimeUnit: String, Decodable, CaseIterable, Identifiable {
        case hour, minute, second
        var id: String { rawValue }
        var label: String {
            switch self { case .hour: "小时"; case .minute: "分钟"; case .second: "秒钟" }
        }
        var calendarComponent: Calendar.Component {
            switch self { case .hour: .hour; case .minute: .minute; case .second: .second }
        }
    }

    struct Field: Decodable, Equatable, Identifiable {
        enum Kind: String, Decodable {
            case text, radio, multi, date, time, datetime, duration
            case datetimeRange = "datetime_range"
            case dateRange = "date_range"
            case timeRange = "time_range"

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                let raw = try container.decode(String.self)
                // Historical or legacy "select" fields render and validate as radio choices.
                if raw == "select" {
                    self = .radio
                    return
                }
                switch raw {
                case "datetime-range", "datetimerange":
                    self = .datetimeRange
                    return
                case "date-range", "daterange":
                    self = .dateRange
                    return
                case "time-range", "timerange":
                    self = .timeRange
                    return
                default:
                    break
                }
                guard let kind = Kind(rawValue: raw) else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported field type: \(raw)")
                }
                self = kind
            }
        }
        enum DefaultValue: Decodable, Equatable {
            case scalar(String), multiple([String]), invalid

            init(from decoder: Decoder) throws {
                let value = try decoder.singleValueContainer()
                if let text = try? value.decode(String.self) { self = .scalar(text) }
                else if let choices = try? value.decode([String].self) { self = .multiple(choices) }
                else { self = .invalid }
            }
        }
        let id: String
        let type: Kind
        let label: String
        let required: Bool?
        let options: [String]?
        let allowCustom: Bool?
        let components: [TimeUnit]?
        let defaultValue: DefaultValue?

        var allowsCustomAnswer: Bool { allowCustom == true && type == .radio }

        var timeUnits: [TimeUnit] { components ?? (type == .duration ? [.minute, .second] : [.hour, .minute]) }
        func maximum(at index: Int) -> Int {
            type == .duration && index == 0 ? 99 : timeUnits[index] == .hour ? 23 : 59
        }
        func temporalValues(_ value: String) -> [Int]? {
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == timeUnits.count else { return nil }
            var result: [Int] = []
            for (index, part) in parts.enumerated() {
                guard part.utf8.count == 2, part.utf8.allSatisfy({ (48...57).contains($0) }),
                      let number = Int(part), number <= maximum(at: index) else { return nil }
                result.append(number)
            }
            return result
        }
        func temporalString(_ values: [Int]) -> String {
            values.map { String(format: "%02d", $0) }.joined(separator: ":")
        }
        var temporalPlaceholder: String {
            timeUnits.map {
                switch $0 {
                case .hour: "HH"
                case .minute: "MM"
                case .second: "SS"
                }
            }.joined(separator: ":")
        }
        var dateTimePlaceholder: String {
            "YYYY-MM-DD \(temporalPlaceholder)"
        }
        var dateTimeRangePlaceholder: String {
            "YYYY-MM-DD \(temporalPlaceholder)\(ChatForm.rangeSeparator)\(temporalPlaceholder)"
        }
        var dateRangePlaceholder: String {
            "YYYY-MM-DD\(ChatForm.rangeSeparator)YYYY-MM-DD"
        }
        var timeRangePlaceholder: String {
            "\(temporalPlaceholder)\(ChatForm.rangeSeparator)\(temporalPlaceholder)"
        }
        /// Strict `yyyy-MM-dd HH:mm` (or requested time components) validation for `datetime` fields.
        func dateTimeComponents(_ value: String) -> (date: Date, time: [Int])? {
            let parts = value.split(separator: " ", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let date = ChatForm.date(String(parts[0])),
                  let time = temporalValues(String(parts[1])) else { return nil }
            return (date, time)
        }
        func dateTimeString(date: Date, time: [Int]) -> String {
            "\(ChatForm.dateString(date)) \(temporalString(time))"
        }
        /// Accepts user-typed date+time variants such as `2026/11/5 9:5`, `20261125 1430`, or `2026-11-25T14:30`.
        func parseDateTimeInput(_ raw: String) -> (date: Date, time: [Int])? {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let normalized = trimmed
                .replacingOccurrences(of: "T", with: " ")
                .replacingOccurrences(of: "t", with: " ")
            let parts = normalized.split(whereSeparator: { $0.isWhitespace })
            guard parts.count == 2,
                  let date = ChatForm.parseDateInput(String(parts[0])),
                  let time = parseTemporalInput(String(parts[1])) else { return nil }
            return (date, time)
        }
        func initialDateTime(now: Date = Date()) -> String {
            dateTimeString(date: now, time: initialTemporalValues(now: now))
        }
        func combinedInstant(date: Date, time: [Int], calendar: Calendar = .current) -> Date? {
            var comps = calendar.dateComponents([.year, .month, .day], from: date)
            comps.hour = 0
            comps.minute = 0
            comps.second = 0
            for (unit, number) in zip(timeUnits, time) {
                switch unit {
                case .hour: comps.hour = number
                case .minute: comps.minute = number
                case .second: comps.second = number
                }
            }
            return calendar.date(from: comps)
        }
        func temporalRank(_ values: [Int]) -> Int {
            var total = 0
            for (unit, number) in zip(timeUnits, values) {
                switch unit {
                case .hour: total += number * 3600
                case .minute: total += number * 60
                case .second: total += number
                }
            }
            return total
        }
        func dateTimeRangeString(startDate: Date, startTime: [Int], endDate: Date, endTime: [Int]) -> String {
            let startDay = ChatForm.dateString(startDate)
            let endDay = ChatForm.dateString(endDate)
            if startDay == endDay {
                return "\(startDay) \(temporalString(startTime))\(ChatForm.rangeSeparator)\(temporalString(endTime))"
            }
            return "\(startDay) \(temporalString(startTime))\(ChatForm.rangeSeparator)\(endDay) \(temporalString(endTime))"
        }
        /// Strict validation for `datetime_range` (canonical `yyyy-MM-dd HH:mm – HH:mm` or `yyyy-MM-dd HH:mm – yyyy-MM-dd HH:mm`).
        func dateTimeRangeComponents(_ value: String) -> (startDate: Date, startTime: [Int], endDate: Date, endTime: [Int])? {
            guard let (left, right) = ChatForm.splitRangeParts(value, allowUnspacedHyphen: false),
                  let start = dateTimeComponents(left) else { return nil }
            let endDate: Date
            let endTime: [Int]
            if let fullEnd = dateTimeComponents(right) {
                endDate = fullEnd.date
                endTime = fullEnd.time
            } else if let sameDayTime = temporalValues(right) {
                endDate = start.date
                endTime = sameDayTime
            } else {
                return nil
            }
            guard let startInstant = combinedInstant(date: start.date, time: start.time),
                  let endInstant = combinedInstant(date: endDate, time: endTime),
                  endInstant > startInstant else { return nil }
            return (start.date, start.time, endDate, endTime)
        }
        /// Accepts flexible user-typed ranges such as `2026/11/26 19:00 - 20:00` or `2026-11-26 19:00 ~ 2026-11-27 10:00`.
        func parseDateTimeRangeInput(_ raw: String) -> (startDate: Date, startTime: [Int], endDate: Date, endTime: [Int])? {
            guard let (left, right) = ChatForm.splitRangeParts(raw, allowUnspacedHyphen: false),
                  let start = parseDateTimeInput(left) else { return nil }
            let endDate: Date
            let endTime: [Int]
            if let fullEnd = parseDateTimeInput(right) {
                endDate = fullEnd.date
                endTime = fullEnd.time
            } else if let sameDayTime = parseTemporalInput(right) {
                endDate = start.date
                endTime = sameDayTime
            } else {
                return nil
            }
            guard let startInstant = combinedInstant(date: start.date, time: start.time),
                  let endInstant = combinedInstant(date: endDate, time: endTime),
                  endInstant > startInstant else { return nil }
            return (start.date, start.time, endDate, endTime)
        }
        func initialDateTimeRange(now: Date = Date()) -> String {
            let calendar = Calendar.current
            let start = now
            let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
            return dateTimeRangeString(
                startDate: start,
                startTime: initialTemporalValues(now: start),
                endDate: end,
                endTime: initialTemporalValues(now: end)
            )
        }
        func dateRangeString(start: Date, end: Date) -> String {
            "\(ChatForm.dateString(start))\(ChatForm.rangeSeparator)\(ChatForm.dateString(end))"
        }
        func dateRangeComponents(_ value: String) -> (start: Date, end: Date)? {
            guard let (left, right) = ChatForm.splitRangeParts(value, allowUnspacedHyphen: false),
                  let start = ChatForm.date(left),
                  let end = ChatForm.date(right),
                  end >= start else { return nil }
            return (start, end)
        }
        func parseDateRangeInput(_ raw: String) -> (start: Date, end: Date)? {
            guard let (left, right) = ChatForm.splitRangeParts(raw, allowUnspacedHyphen: false),
                  let start = ChatForm.parseDateInput(left),
                  let end = ChatForm.parseDateInput(right),
                  end >= start else { return nil }
            return (start, end)
        }
        func initialDateRange(now: Date = Date()) -> String {
            let end = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
            return dateRangeString(start: now, end: end)
        }
        func timeRangeString(start: [Int], end: [Int]) -> String {
            "\(temporalString(start))\(ChatForm.rangeSeparator)\(temporalString(end))"
        }
        func timeRangeComponents(_ value: String) -> (start: [Int], end: [Int])? {
            guard let (left, right) = ChatForm.splitRangeParts(value, allowUnspacedHyphen: true),
                  let start = temporalValues(left),
                  let end = temporalValues(right),
                  temporalRank(end) > temporalRank(start) else { return nil }
            return (start, end)
        }
        func parseTimeRangeInput(_ raw: String) -> (start: [Int], end: [Int])? {
            guard let (left, right) = ChatForm.splitRangeParts(raw, allowUnspacedHyphen: true),
                  let start = parseTemporalInput(left),
                  let end = parseTemporalInput(right),
                  temporalRank(end) > temporalRank(start) else { return nil }
            return (start, end)
        }
        func initialTimeRange(now: Date = Date()) -> String {
            let startValues = initialTemporalValues(now: now)
            let startInstant = combinedInstant(date: now, time: startValues) ?? now
            let calendar = Calendar.current
            if let endInstant = calendar.date(byAdding: .hour, value: 1, to: startInstant),
               calendar.isDate(endInstant, inSameDayAs: startInstant) {
                let endValues = initialTemporalValues(now: endInstant)
                if temporalRank(endValues) > temporalRank(startValues) {
                    return timeRangeString(start: startValues, end: endValues)
                }
            }
            let maxEnd = timeUnits.enumerated().map { maximum(at: $0.offset) }
            if temporalRank(maxEnd) > temporalRank(startValues) {
                return timeRangeString(start: startValues, end: maxEnd)
            }
            let fallbackStart = timeUnits.map { $0 == .hour ? 9 : 0 }
            let fallbackEnd = timeUnits.map { $0 == .hour ? 10 : ($0 == .minute ? 30 : 30) }
            return timeRangeString(start: fallbackStart, end: fallbackEnd)
        }
        /// Accepts user-typed time/duration variants such as `9:5`, `14:30`, `14：30`, or `1430`.
        func parseTemporalInput(_ raw: String) -> [Int]? {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "：", with: ":")
                .replacingOccurrences(of: ".", with: ":")
            guard !normalized.isEmpty else { return nil }
            let parts: [Substring]
            if normalized.contains(":") {
                parts = normalized.split(separator: ":", omittingEmptySubsequences: false)
            } else if timeUnits.count == 1 {
                parts = [normalized[...]]
            } else if normalized.utf8.count == timeUnits.count * 2,
                      normalized.utf8.allSatisfy({ (48...57).contains($0) }) {
                var chunks: [Substring] = []
                var start = normalized.startIndex
                for _ in 0..<timeUnits.count {
                    let end = normalized.index(start, offsetBy: 2)
                    chunks.append(normalized[start..<end])
                    start = end
                }
                parts = chunks
            } else {
                return nil
            }
            guard parts.count == timeUnits.count else { return nil }
            var result: [Int] = []
            for (index, part) in parts.enumerated() {
                guard (1...2).contains(part.utf8.count),
                      part.utf8.allSatisfy({ (48...57).contains($0) }),
                      let number = Int(part),
                      number <= maximum(at: index) else { return nil }
                result.append(number)
            }
            return result
        }
        func initialTemporalValues(now: Date = Date()) -> [Int] {
            timeUnits.map { type == .duration ? 0 : Calendar.current.component($0.calendarComponent, from: now) }
        }
        func describedAnswer(_ answer: [String]) -> String {
            guard let value = answer.first, let numbers = temporalValues(value),
                  type == .duration || (type == .time && timeUnits != [.hour, .minute] && timeUnits != [.hour, .minute, .second]) else {
                return answer.joined(separator: "、")
            }
            return zip(numbers, timeUnits).map { "\($0.0) \(NSLocalizedString($0.1.label, comment: ""))" }.joined(separator: " ")
        }

        func accepts(_ answer: [String]) -> Bool {
            if required == true && answer.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return false }
            switch type {
            case .text: return answer.count <= 1 && answer.allSatisfy { $0.count <= 4000 }
            case .radio:
                return answer.count <= 1 && answer.allSatisfy {
                    (options ?? []).contains($0) || (allowsCustomAnswer && $0.count <= 4000 && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            case .multi: return Set(answer).count == answer.count && answer.allSatisfy { (options ?? []).contains($0) }
            case .date: return answer.count <= 1 && answer.allSatisfy { ChatForm.date($0) != nil }
            case .time, .duration: return answer.count <= 1 && answer.allSatisfy { temporalValues($0) != nil }
            case .datetime: return answer.count <= 1 && answer.allSatisfy { dateTimeComponents($0) != nil }
            case .datetimeRange: return answer.count <= 1 && answer.allSatisfy { dateTimeRangeComponents($0) != nil }
            case .dateRange: return answer.count <= 1 && answer.allSatisfy { dateRangeComponents($0) != nil }
            case .timeRange: return answer.count <= 1 && answer.allSatisfy { timeRangeComponents($0) != nil }
            }
        }

        /// Invalid optional defaults must not destroy an otherwise usable form.
        var initialAnswer: [String]? {
            let answer: [String]
            switch defaultValue {
            case .scalar(let text) where type != .multi:
                switch type {
                case .datetimeRange:
                    guard let parsed = parseDateTimeRangeInput(text) else { return nil }
                    answer = [dateTimeRangeString(startDate: parsed.startDate, startTime: parsed.startTime,
                                                  endDate: parsed.endDate, endTime: parsed.endTime)]
                case .dateRange:
                    guard let parsed = parseDateRangeInput(text) else { return nil }
                    answer = [dateRangeString(start: parsed.start, end: parsed.end)]
                case .timeRange:
                    guard let parsed = parseTimeRangeInput(text) else { return nil }
                    answer = [timeRangeString(start: parsed.start, end: parsed.end)]
                default:
                    answer = [text]
                }
            case .multiple(let choices) where type == .multi: answer = choices
            default: return nil
            }
            return accepts(answer) ? answer : nil
        }

        var isValid: Bool {
            guard !id.isEmpty, id.count <= 64, !label.isEmpty, label.count <= 200 else { return false }
            if allowCustom == true && !allowsCustomAnswer { return false }
            if type == .radio || type == .multi {
                guard let options, (1...20).contains(options.count), Set(options).count == options.count,
                      options.allSatisfy({ !$0.isEmpty && $0.count <= 200 }) else { return false }
            }
            if type == .time || type == .datetime || type == .duration || type == .datetimeRange || type == .timeRange {
                guard !timeUnits.isEmpty, timeUnits == TimeUnit.allCases.filter({ timeUnits.contains($0) }) else { return false }
            } else if components != nil { return false }
            return true
        }
    }
    static let rangeSeparator = " – "

    let title: String
    var fields: [Field]
    var isComplete: Bool

    /// Only absent answers inherit defaults. An explicitly cleared answer stays cleared.
    func prefilling(_ values: [String: [String]]) -> [String: [String]] {
        guard isComplete else { return values }
        var result = values
        for field in fields where result[field.id] == nil {
            if let initial = field.initialAnswer { result[field.id] = initial }
        }
        return result
    }

    func accepts(_ values: [String: [String]]) -> Bool {
        isComplete && !fields.isEmpty && fields.allSatisfy { field in
            field.accepts(values[field.id] ?? [])
        }
    }

    func reply(_ values: [String: [String]]) -> String {
        ([title] + fields.map { field in
            "\(field.label)：\(field.describedAnswer(values[field.id] ?? []))"
        }).joined(separator: "\n")
    }

    static func splitRangeParts(_ raw: String, allowUnspacedHyphen: Bool) -> (String, String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var separators = [" – ", " — ", " ~ ", " 至 ", " to ", " - ", "–", "—", "~", "至"]
        if allowUnspacedHyphen { separators.append("-") }
        for separator in separators {
            if let range = trimmed.range(of: separator) {
                let left = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let right = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !left.isEmpty, !right.isEmpty else { return nil }
                return (left, right)
            }
        }
        return nil
    }

    static func date(_ value: String) -> Date? {
        guard value.count == 10, let date = formatter().date(from: value), dateString(date) == value else { return nil }
        return date
    }
    /// Accepts user-typed date variants such as `2026-11-24`, `2026/11/5`, `2026.11.24`, or `20261124`.
    static func parseDateInput(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.utf8.count == 8, trimmed.utf8.allSatisfy({ (48...57).contains($0) }) {
            let y = trimmed.prefix(4)
            let m = trimmed.dropFirst(4).prefix(2)
            let d = trimmed.suffix(2)
            return date("\(y)-\(m)-\(d)")
        }
        let normalized = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let parts = normalized.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].utf8.count == 4, (1...2).contains(parts[1].utf8.count), (1...2).contains(parts[2].utf8.count),
              parts.allSatisfy({ $0.utf8.allSatisfy({ (48...57).contains($0) }) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        return date(String(format: "%04d-%02d-%02d", year, month, day))
    }
    static func dateString(_ date: Date) -> String { formatter().string(from: date) }
    private static func formatter(_ format: String = "yyyy-MM-dd") -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }
}

struct ChatReplyPart: Equatable, Identifiable {
    enum Content: Equatable { case markdown(String), form(ChatForm) }
    let id: Int
    let content: Content
}

enum ChatFormParser {
    private struct Header: Decodable { let title: String }

    /// Some model replies put LaTeX delimiters such as \[ inside JSON strings without
    /// escaping the backslash. Repair only invalid string escapes; retain valid JSON
    /// escapes and leave structural/schema errors to the ordinary Markdown fallback.
    private static func decode<T: Decodable>(_ type: T.Type, from line: String) -> T? {
        let decoder = JSONDecoder()
        if let value = try? decoder.decode(type, from: Data(line.utf8)) { return value }
        var repaired = ""
        var inString = false
        var characters = line.makeIterator()
        while let character = characters.next() {
            if inString && character == "\\" {
                repaired.append(character)
                if let escaped = characters.next() {
                    if !"\"\\/bfnrtu".contains(escaped) { repaired.append("\\") }
                    repaired.append(escaped)
                }
            } else {
                if character == "\"" { inString.toggle() }
                repaired.append(character)
            }
        }
        guard repaired != line else { return nil }
        return try? decoder.decode(type, from: Data(repaired.utf8))
    }

    /// Fields are published only after their newline arrives; unfinished JSON never reaches Markdown.
    /// At most one form per reply. Other fenced code (including examples) stays ordinary Markdown.
    static func parse(_ text: String, streaming: Bool) -> [ChatReplyPart] {
        if !streaming, !text.contains("```asky-form") {
            return text.isEmpty ? [] : [.init(id: 0, content: .markdown(text))]
        }
        var parts: [ChatReplyPart] = []
        var markdown = ""
        var block: [String]? = nil
        var codeFence: (Character, Int)?
        var usedForm = false
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        func append(_ content: ChatReplyPart.Content) { parts.append(.init(id: parts.count, content: content)) }
        func flushMarkdown() {
            if !markdown.isEmpty { append(.markdown(markdown)); markdown = "" }
        }
        func renderBlock(_ raw: [String], closed: Bool) {
            let body = raw.dropFirst().filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard raw.joined(separator: "\n").utf8.count <= 32_768,
                  let first = body.first, let header = decode(Header.self, from: first),
                  !header.title.isEmpty, header.title.count <= 120, body.count <= 17 else {
                if closed || !streaming { append(.markdown(raw.joined(separator: "\n") + (closed ? "\n```" : ""))) }
                return
            }
            var fields: [ChatForm.Field] = []
            for line in body.dropFirst() {
                guard let field = decode(ChatForm.Field.self, from: line),
                      field.isValid, !fields.contains(where: { $0.id == field.id }) else {
                    append(.markdown(raw.joined(separator: "\n") + (closed ? "\n```" : "")))
                    return
                }
                fields.append(field)
            }
            append(.form(ChatForm(title: header.title, fields: fields, isComplete: closed && !fields.isEmpty)))
        }
        for (index, line) in lines.enumerated() {
            let line = String(line)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let last = index == lines.count - 1
            if var current = block {
                if trimmed == "```" {
                    renderBlock(current, closed: true)
                    block = nil
                } else if !last || !streaming {
                    current.append(line)
                    block = current
                }
                continue
            }
            if codeFence == nil, !usedForm, line == "```asky-form" {
                flushMarkdown()
                usedForm = true
                block = [line]
                continue
            }
            // Hide an opening marker arriving token by token, but only outside another code fence.
            if streaming, last, codeFence == nil, !usedForm, !line.isEmpty, "```asky-form".hasPrefix(line) { continue }
            if let first = trimmed.first, first == "`" || first == "~" {
                let count = trimmed.prefix(while: { $0 == first }).count
                if let fence = codeFence {
                    if first == fence.0, count >= fence.1, trimmed.count == count { codeFence = nil }
                } else if count >= 3 { codeFence = (first, count) }
            }
            markdown += line + (last ? "" : "\n")
        }
        if let block { renderBlock(block, closed: false) }
        flushMarkdown()
        return placingFormLast(parts)
    }

    /// Always keep the interactive form (and its submit button) as the final element of a bubble
    /// so prose never dangles below the submit action.
    private static func placingFormLast(_ parts: [ChatReplyPart]) -> [ChatReplyPart] {
        guard let formPart = parts.first(where: { if case .form = $0.content { true } else { false } }) else {
            return parts
        }
        let markdownChunks = parts.compactMap { part -> String? in
            guard case .markdown(let body) = part.content else { return nil }
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        var reordered: [ChatReplyPart] = []
        if !markdownChunks.isEmpty {
            reordered.append(.init(id: 0, content: .markdown(markdownChunks.joined(separator: "\n\n"))))
        }
        reordered.append(.init(id: reordered.count, content: formPart.content))
        return reordered
    }

    static func form(in text: String) -> ChatForm? {
        parse(text, streaming: false).compactMap { if case .form(let form) = $0.content { form } else { nil } }.first
    }
}
