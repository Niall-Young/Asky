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
        enum Kind: String, Decodable { case text, select, radio, multi, date, time, duration }
        let id: String
        let type: Kind
        let label: String
        let required: Bool?
        let options: [String]?
        let allowCustom: Bool?
        let components: [TimeUnit]?

        var allowsCustomAnswer: Bool { allowCustom == true && (type == .radio || type == .select) }

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

        var isValid: Bool {
            guard !id.isEmpty, id.count <= 64, !label.isEmpty, label.count <= 200 else { return false }
            if allowCustom == true && !allowsCustomAnswer { return false }
            if type == .select || type == .radio || type == .multi {
                guard let options, (1...20).contains(options.count), Set(options).count == options.count,
                      options.allSatisfy({ !$0.isEmpty && $0.count <= 200 }) else { return false }
            }
            if type == .time || type == .duration {
                guard !timeUnits.isEmpty, timeUnits == TimeUnit.allCases.filter({ timeUnits.contains($0) }) else { return false }
            } else if components != nil { return false }
            return true
        }
    }
    let title: String
    var fields: [Field]
    var isComplete: Bool

    func accepts(_ values: [String: [String]]) -> Bool {
        isComplete && !fields.isEmpty && fields.allSatisfy { field in
            let answer = values[field.id] ?? []
            if field.required == true && answer.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return false }
            switch field.type {
            case .text: return answer.count <= 1 && answer.allSatisfy { $0.count <= 4000 }
            case .select, .radio:
                return answer.count <= 1 && answer.allSatisfy {
                    field.options!.contains($0) || (field.allowsCustomAnswer && $0.count <= 4000 && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            case .multi: return Set(answer).count == answer.count && answer.allSatisfy { field.options!.contains($0) }
            case .date: return answer.count <= 1 && answer.allSatisfy { Self.date($0) != nil }
            case .time, .duration: return answer.count <= 1 && answer.allSatisfy { field.temporalValues($0) != nil }
            }
        }
    }

    func reply(_ values: [String: [String]]) -> String {
        ([title] + fields.map { field in
            "\(field.label)：\(field.describedAnswer(values[field.id] ?? []))"
        }).joined(separator: "\n")
    }

    static func date(_ value: String) -> Date? {
        guard value.count == 10, let date = formatter().date(from: value), dateString(date) == value else { return nil }
        return date
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
        return parts
    }

    static func form(in text: String) -> ChatForm? {
        parse(text, streaming: false).compactMap { if case .form(let form) = $0.content { form } else { nil } }.first
    }
}
