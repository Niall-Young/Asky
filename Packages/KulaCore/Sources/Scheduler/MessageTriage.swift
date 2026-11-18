import Foundation
import Contracts

/// A proposed appointment extracted from an opted-in message. No write happens during extraction.
public struct MessageCalendarDraft: Sendable, Hashable, Codable {
    public var title: String
    public var start: Date
    /// Missing end times are shown as an explicit one-hour proposal in the editor.
    public var end: Date?
    public var location: String?
    public var calendar: String?
    public var notes: String?

    public init(title: String, start: Date, end: Date? = nil, location: String? = nil,
                calendar: String? = nil, notes: String? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.calendar = calendar
        self.notes = notes
    }

    public var proposedEnd: Date { end ?? start.addingTimeInterval(3600) }
    public func isValid(at now: Date) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && start > now && proposedEnd > start
    }

    public func matchingEvent(in events: [EventSnapshot]) -> EventSnapshot? {
        events.first {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(
                title.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
                && abs($0.start.timeIntervalSince(start)) < 60
        }
    }

    public var arguments: JSONValue {
        var values: [String: JSONValue] = [
            "title": .string(title.trimmingCharacters(in: .whitespacesAndNewlines)),
            "start": .string(ISO8601DateFormatter().string(from: start)),
            "end": .string(ISO8601DateFormatter().string(from: proposedEnd)),
        ]
        if let location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values["location"] = .string(location.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let calendar, !calendar.isEmpty { values["calendar"] = .string(calendar) }
        if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values["notes"] = .string(notes)
        }
        return .object(values)
    }
}

/// A short note the model kept from Messages history: something that may still need the user's action.
public struct MessageNote: Sendable, Hashable, Codable {
    /// ID of the message that raised it.
    public var id: String
    public var sender: String
    public var date: Date
    /// One-line summary, already stripped of chit-chat; this, not the raw message, goes to the advisor.
    public var summary: String
    public var due: Date?
    public var messageIDs: [String]
    public var calendarDraft: MessageCalendarDraft?
    public init(id: String, sender: String, date: Date, summary: String, due: Date? = nil, messageIDs: [String], calendarDraft: MessageCalendarDraft? = nil) {
        self.id = id
        self.sender = sender
        self.date = date
        self.summary = summary
        self.due = due
        self.messageIDs = messageIDs
        self.calendarDraft = calendarDraft
    }
}

/// Notes plus the newest message already read, so each message is sent to the model once.
public struct MessageTriageState: Sendable, Codable, Equatable {
    public var notes: [MessageNote] = []
    public var watermark: Int64 = 0
    /// Older summaries are re-extracted once to recover appointment fields.
    public var calendarExtractionVersion: Int? = 1
    public init(notes: [MessageNote] = [], watermark: Int64 = 0) {
        self.notes = notes
        self.watermark = watermark
    }
}

/// First pass over Messages: new messages are read in small batches and boiled down to `MessageNote`s.
/// Later messages can close earlier notes. Only the notes reach `SmartAdvisor`, so the main request stays small
/// and a message already read never costs another call.
public struct MessageTriage: Sendable {
    public var batchCharacters = 2500
    /// Bounds a first run over up to 30 days of history; the rest is read on the next pass.
    public var maxBatchesPerRun = 6
    public var maxNotes = 30
    /// Notes older than this are dropped; the App sets it from the chosen look-back window.
    public var window: TimeInterval = 30 * 24 * 3600
    public var calendar: Calendar
    let complete: SmartAdvisor.Complete

    public init(calendar: Calendar = .current, complete: @escaping SmartAdvisor.Complete) {
        self.calendar = calendar
        self.complete = complete
    }

    /// Messages newer than the watermark, oldest first, split by text length.
    public func batches(_ messages: [MessageSnapshot], after watermark: Int64) -> [[MessageSnapshot]] {
        var out: [[MessageSnapshot]] = [], current: [MessageSnapshot] = [], size = 0
        for m in messages.filter({ $0.sequence > watermark }).sorted(by: { $0.sequence < $1.sequence }) {
            if !current.isEmpty && size + m.text.count > batchCharacters {
                out.append(current)
                current = []
                size = 0
            }
            current.append(m)
            size += m.text.count
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Notes older than the window are dropped first. Each batch that succeeds moves the watermark, so a failure
    /// part way through resumes from the first unread batch next time.
    public func update(_ state: MessageTriageState, messages: [MessageSnapshot], now: Date) async -> MessageTriageState {
        var state = state
        if state.calendarExtractionVersion != 1 {
            state.watermark = 0
            state.calendarExtractionVersion = 1
        }
        state.notes.removeAll { $0.date < now.addingTimeInterval(-window) }
        for batch in batches(messages, after: state.watermark).prefix(maxBatchesPerRun) {
            let context = Self.context(for: batch, in: messages)
            let prompt = prompt(batch: batch, context: context, open: state.notes, now: now)
            guard let reply = try? await complete(Self.systemPrompt, prompt) else { break }
            guard let notes = apply(reply, batch: batch, open: state.notes, now: now) else { break }
            state.notes = notes
            state.watermark = batch.map(\.sequence).max() ?? state.watermark
        }
        state.notes = Array(state.notes.sorted { $0.date > $1.date }.prefix(maxNotes))
        return state
    }

    static let systemPrompt = """
        你在帮用户整理短信和 iMessage，找出仍需要用户行动或留意的事。只做摘录，不做提醒决定，不创建日程。

        值得记下的：别人对用户的请求、约定的时间地点、用户自己答应过的事、取件/缴费/还款/预约/改期/到期等需要处理的通知。
        不要记：广告营销、闲聊、纯告知且无需行动的消息、已经在同一批或上下文中处理完的事。
        如果新消息表明某条“已记下的事项”已经完成、取消或过期，把它的编号放进 resolved。

        仅对有明确开始日期和时间、用户确实需要参加的会议、预约或出行，附带 calendar 候选。
        取件、缴费、交材料等截止事项、模糊邀约、广告、验证码不能生成 calendar。不要把截止时间当开始时间。
        title/start/location 只用消息明确给出的信息；相对时间以消息发送时间和当前时区推算。
        未明确结束时间时 end 写 null，不要编造时长；未明确地点时 location 写 null。
        新消息改期或取消预约时，将旧事项加入 resolved，仅保留最新有效安排。

        只输出一个 JSON 对象，不要其他文字：
        {"items":[{"source":["S2","S3"],"summary":"不超过40字，写清谁、要做什么","due":"ISO8601 带时区，没有明确时间就写 null","calendar":{"kind":"event","title":"预约标题","start":"ISO8601 带时区","end":null,"location":null}}],"resolved":["N1"]}
        calendar 不适用时写 null。
        source 只能使用本批的 S 编号；上下文（C 编号）只用于理解，不要单独为它记事项。没有就返回空数组。
        """

    /// Up to 3 earlier messages from each conversation in the batch, so a reply is read with what it answers.
    static func context(for batch: [MessageSnapshot], in all: [MessageSnapshot]) -> [MessageSnapshot] {
        guard let first = batch.map(\.sequence).min() else { return [] }
        let chats = Set(batch.map(\.conversation))
        return chats.sorted().flatMap { chat in
            all.filter { $0.conversation == chat && $0.sequence < first }.sorted { $0.sequence < $1.sequence }.suffix(3)
        }.sorted { $0.sequence < $1.sequence }
    }

    func prompt(batch: [MessageSnapshot], context: [MessageSnapshot], open: [MessageNote], now: Date) -> String {
        let f = SmartAdvisor.formatter(calendar)
        func line(_ alias: String, _ m: MessageSnapshot) -> String {
            "\(alias) \(f.string(from: m.date)) \(m.isFromMe ? "我" : m.sender)\(m.group.map { "（\($0)）" } ?? "")：\(m.text)"
        }
        var lines = ["当前时间：\(f.string(from: now))", "", "已记下的事项："]
        lines += open.isEmpty ? ["（无）"] : open.enumerated().map { i, n in
            "N\(i + 1) \(n.sender)：\(n.summary)" + (n.due.map { "（截止 \(f.string(from: $0))）" } ?? "")
        }
        if !context.isEmpty {
            lines += ["", "上下文（之前的消息）："] + context.enumerated().map { line("C\($0 + 1)", $1) }
        }
        lines += ["", "本批新消息（“我”表示用户发出）："] + batch.enumerated().map { line("S\($0 + 1)", $1) }
        return lines.joined(separator: "\n")
    }

    struct Reply: Decodable {
        struct CalendarItem: Decodable {
            var kind: String
            var title: String
            var start: String
            var end: String?
            var location: String?
        }
        struct Item: Decodable {
            var source: [String]
            var summary: String
            var due: String?
            var calendar: CalendarItem?
        }
        var items: [Item]?
        var resolved: [String]?
    }

    /// Unknown aliases are ignored; an unreadable reply leaves the notes unchanged.
    func apply(_ reply: String, batch: [MessageSnapshot], open: [MessageNote], now: Date = Date()) -> [MessageNote]? {
        guard let data = SmartAdvisor.jsonObject(in: reply).data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Reply.self, from: data), decoded.items != nil || decoded.resolved != nil else { return nil }
        func index(_ alias: String, _ prefix: Character) -> Int? {
            let a = alias.trimmingCharacters(in: .whitespaces).uppercased()
            guard a.first == prefix, let n = Int(a.dropFirst()), n > 0 else { return nil }
            return n - 1
        }
        let closed = Set((decoded.resolved ?? []).compactMap { index($0, "N") })
        var notes = open.enumerated().filter { !closed.contains($0.offset) }.map(\.element)
        for item in decoded.items ?? [] {
            let sources = item.source.compactMap { index($0, "S") }.filter(batch.indices.contains).map { batch[$0] }
            let summary = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let anchor = sources.first(where: { !$0.isFromMe }) ?? sources.first, !summary.isEmpty else { continue }
            notes.removeAll { $0.id == anchor.id }
            var draft: MessageCalendarDraft?
            if let candidate = item.calendar, candidate.kind == "event",
               let start = SmartAdvisor.parseDate(candidate.start),
               candidate.end == nil || candidate.end.flatMap(SmartAdvisor.parseDate) != nil {
                let proposed = MessageCalendarDraft(title: String(candidate.title.prefix(120)), start: start,
                    end: candidate.end.flatMap(SmartAdvisor.parseDate), location: candidate.location.map { String($0.prefix(200)) })
                if proposed.isValid(at: now) { draft = proposed }
            }
            notes.append(MessageNote(id: anchor.id, sender: anchor.sender, date: anchor.date, summary: String(summary.prefix(80)),
                                     due: item.due.flatMap(SmartAdvisor.parseDate), messageIDs: sources.map(\.id), calendarDraft: draft))
        }
        return notes
    }
}
