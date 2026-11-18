import Foundation
import Contracts
import ToolService

public typealias TaskSnapshot = Contracts.TaskSnapshot

/// Everything the advisor may look at. Callers pass only sources the user allowed for AI use.
public struct AdvisorInput: Sendable {
    public var events: [EventSnapshot]
    public var tasks: [TaskSnapshot]
    public var memories: [ContextSnippet]
    /// Open items `MessageTriage` kept from Messages history. Empty unless the user opted in.
    public var messages: [MessageNote]
    /// Titles of suggestions the user already saw or handled recently, so the model does not repeat them.
    public var recentSuggestions: [String]
    public var now: Date
    public init(events: [EventSnapshot], tasks: [TaskSnapshot], memories: [ContextSnippet],
                messages: [MessageNote] = [], recentSuggestions: [String] = [], now: Date) {
        self.events = events
        self.tasks = tasks
        self.memories = memories
        self.messages = messages
        self.recentSuggestions = recentSuggestions
        self.now = now
    }

    /// Stable digest of the input; unchanged context does not need another model call.
    public var fingerprint: String {
        var h = StableHasher()
        for e in events.sorted(by: { $0.id < $1.id }) { h.add("e|\(e.id)|\(e.title)|\(e.fingerprint)") }
        for t in tasks.sorted(by: { $0.id < $1.id }) { h.add("t|\(t.id)|\(t.title)|\(t.due?.timeIntervalSince1970 ?? 0)") }
        for m in memories.sorted(by: { $0.sourceID < $1.sourceID }) { h.add("m|\(m.sourceID)|\(m.text)") }
        for s in messages.sorted(by: { $0.id < $1.id }) { h.add("s|\(s.id)|\(References.Ref.message(s).fingerprint)") }
        return h.hex
    }
}

/// Asks the configured model which items genuinely need the user's attention, then validates every answer
/// against the input: no evidence, unknown references or out-of-range times means the suggestion is dropped.
public struct SmartAdvisor: Sendable {
    public typealias Complete = @Sendable (_ system: String, _ user: String) async throws -> String

    public var maxSuggestions = 3
    public var horizon: TimeInterval = 7 * 24 * 3600
    public var calendar: Calendar
    let complete: Complete

    public init(calendar: Calendar = .current, complete: @escaping Complete) {
        self.calendar = calendar
        self.complete = complete
    }

    public func suggest(_ input: AdvisorInput) async throws -> [ReminderPlan] {
        let refs = References(input)
        guard !refs.isEmpty else { return [] }
        let reply = try await complete(Self.systemPrompt, prompt(input, refs))
        return plans(from: reply, input: input, refs: refs)
    }

    static let systemPrompt = """
        你是用户的私人助理，负责判断哪些事情值得主动提醒。你会看到用户未来几天的日程、未完成的待办、已授权的记忆，以及（如果用户开启）从近期短信和 iMessage 中摘出的待处理事项。

        只提醒日历和提醒事项本身做不到的事，例如：
        - 需要提前准备的事项：会前材料、礼物、订票、预约、带证件或物品；
        - 日程、待办与记忆之间的关联或矛盾：截止日期前已被日程排满、记忆里提过的事与某个日程有关、承诺过的事还没有对应待办；
        - 临近截止却没有安排时间的待办；
        - 短信中的明确预约、会议或出行尚未加入日程：尽早建议创建日程，不要等到开始时才提醒；
        - 短信事项里需要用户行动、且日程或待办里还没有对应安排的事：别人的请求或约定、用户答应过的事、取件/缴费/预约/改期等通知。

        不要做这些事：
        - 重复“某日程即将开始”这类普通提醒，系统日历已经会提醒；
        - 编造没有依据的信息，例如天气、路况、到货时间、对方的偏好；
        - 提醒广告、营销、群聊闲聊、已经处理完的事（短信事项如果日程或待办表明已安排、已完成或已过期，就不要提醒），或在提醒中复述验证码、账号等敏感内容；
        - 为了凑数给出建议。没有真正值得提醒的事时，返回空数组。

        只输出一个 JSON 对象，不要其他文字：
        {"suggestions":[{"anchor":"E1","title":"不超过20字","body":"不超过80字，说清为什么和建议做什么","fire_at":"ISO8601 带时区，建议在需要行动的合适时间","evidence":["E1","M2"]}]}
        anchor 和 evidence 只能使用输入中出现的编号（E 日程、T 待办、M 记忆、S 短信事项），anchor 不能是 M，evidence 至少包含 anchor。最多 3 条。
        """

    func prompt(_ input: AdvisorInput, _ refs: References) -> String {
        let f = Self.formatter(calendar)
        var lines = ["当前时间：\(f.string(from: input.now))", "", "日程："]
        lines += refs.events.isEmpty ? ["（无）"] : refs.events.map { alias, e in
            let time = e.isAllDay ? "\(Self.day(calendar).string(from: e.start)) 全天" : "\(f.string(from: e.start)) – \(f.string(from: e.end))"
            return "\(alias) \(time) \(e.title)" + (e.location.map { $0.isEmpty ? "" : " @\($0)" } ?? "")
        }
        lines += ["", "待办："]
        lines += refs.tasks.isEmpty ? ["（无）"] : refs.tasks.map { alias, t in
            "\(alias) \(t.title)" + (t.due.map { "（截止 \(f.string(from: $0))）" } ?? "") + (t.list.isEmpty ? "" : " [\(t.list)]")
        }
        lines += ["", "记忆："]
        lines += refs.memories.isEmpty ? ["（无）"] : refs.memories.map { alias, m in "\(alias) \(m.text)" }
        if !refs.messages.isEmpty {
            lines += ["", "短信事项（从近期短信中摘出）："]
            lines += refs.messages.map { alias, n in
                "\(alias) \(f.string(from: n.date)) \(n.sender)：\(n.summary)" + (n.due.map { "（截止 \(f.string(from: $0))）" } ?? "")
                    + (n.calendarDraft.map { "（待创建日程：\($0.title)，开始 \(f.string(from: $0.start))）" } ?? "")
            }
        }
        if !input.recentSuggestions.isEmpty {
            lines += ["", "最近已经提醒过（不要重复）："] + input.recentSuggestions.map { "- \($0)" }
        }
        return lines.joined(separator: "\n")
    }

    func plans(from reply: String, input: AdvisorInput, refs: References) -> [ReminderPlan] {
        guard let data = Self.jsonObject(in: reply).data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Reply.self, from: data) else { return [] }
        let latest = input.now.addingTimeInterval(horizon)
        var out: [ReminderPlan] = []
        for s in decoded.suggestions {
            guard out.count < maxSuggestions, let anchor = refs.ref(s.anchor), anchor.canAnchor else { continue }
            let title = s.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = s.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !body.isEmpty, let fire = Self.parseDate(s.fire_at) else { continue }
            var cited = [s.anchor] + (s.evidence ?? [])
            cited = cited.reduce(into: []) { if refs.ref($1) != nil && !$0.contains($1) { $0.append($1) } }
            // Never later than the anchored event itself, never in the past or beyond the horizon.
            var fireDate = max(input.now, fire)
            if case .event(let e) = anchor { fireDate = min(fireDate, e.start) }
            guard fireDate <= latest, out.allSatisfy({ $0.eventID != anchor.key }) else { continue }
            if case .message(let note) = anchor, let draft = note.calendarDraft,
               (!draft.isValid(at: input.now) || draft.matchingEvent(in: input.events) != nil) { continue }
            out.append(ReminderPlan(eventID: anchor.key, reason: .insight, title: String(title.prefix(40)),
                                    body: String(body.prefix(200)),
                                    evidence: cited.compactMap { refs.ref($0)?.key } + cited.compactMap { refs.describe($0) },
                                    fireDate: fireDate, eventFingerprint: anchor.fingerprint))
        }
        return out
    }

    public static func matchesMessage(_ note: MessageNote, plan: ReminderPlan) -> Bool {
        plan.eventID == References.Ref.message(note).key && plan.eventFingerprint == References.Ref.message(note).fingerprint
    }

    /// An explicit appointment needs no second model decision to offer a calendar draft.
    public static func calendarSuggestions(in input: AdvisorInput) -> [ReminderPlan] {
        var seen = Set<String>()
        return input.messages.sorted { $0.date > $1.date }.compactMap { note in
            guard let draft = note.calendarDraft, draft.isValid(at: input.now),
                  draft.start <= input.now.addingTimeInterval(7 * 86400),
                  draft.matchingEvent(in: input.events) == nil else { return nil }
            let key = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                + "|\(Int(draft.start.timeIntervalSince1970 / 60))"
            guard seen.insert(key).inserted else { return nil }
            let anchor = References.Ref.message(note)
            return ReminderPlan(eventID: anchor.key, reason: .insight, title: CoreLocalization.format("待添加日程：%@", String(describing: draft.title)),
                body: note.summary, evidence: [anchor.key, CoreLocalization.format("短信（%@）：%@", note.sender, note.summary)],
                fireDate: input.now, eventFingerprint: anchor.fingerprint)
        }
    }

    /// Cached suggestions stay valid only while their anchor still exists unchanged in the current input.
    public static func stillValid(_ plans: [ReminderPlan], in input: AdvisorInput) -> [ReminderPlan] {
        let refs = References(input)
        let anchors = refs.events.map { References.Ref.event($0.1) } + refs.tasks.map { .task($0.1) } + refs.messages.map { .message($0.1) }
        let live = Dictionary(anchors.map { ($0.key, $0.fingerprint) },
                              uniquingKeysWith: { a, _ in a })
        return plans.filter { plan in
            guard plan.reason == .insight, live[plan.eventID] == plan.eventFingerprint else { return false }
            if let note = input.messages.first(where: { "message:\($0.id)" == plan.eventID }), let draft = note.calendarDraft {
                return draft.isValid(at: input.now) && draft.matchingEvent(in: input.events) == nil
            }
            return true
        }
    }

    // MARK: Parsing

    struct Reply: Decodable {
        struct Suggestion: Decodable {
            var anchor: String
            var title: String
            var body: String
            var fire_at: String
            var evidence: [String]?
        }
        var suggestions: [Suggestion]
    }

    /// Tolerates code fences or prose around the object.
    static func jsonObject(in text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return text }
        return String(text[start...end])
    }

    static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s)
    }

    static func formatter(_ cal: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd EEE HH:mm xxx"
        return f
    }

    static func day(_ cal: Calendar) -> DateFormatter {
        let f = formatter(cal)
        f.dateFormat = "yyyy-MM-dd EEE"
        return f
    }
}

/// Short aliases (E1, T1, M1) so the model never has to echo long system identifiers.
struct References {
    enum Ref {
        case event(EventSnapshot), task(TaskSnapshot), memory(ContextSnippet), message(MessageNote)

        /// Memories only support a suggestion; they change too rarely to be its trigger.
        var canAnchor: Bool { if case .memory = self { false } else { true } }

        var key: String {
            switch self {
            case .event(let e): "event:\(e.id)"
            case .task(let t): "task:\(t.id)"
            case .memory(let m): m.sourceID
            case .message(let m): "message:\(m.id)"
            }
        }

        var fingerprint: String {
            switch self {
            case .event(let e): e.fingerprint
            case .task(let t): "\(t.title)|\(t.due?.timeIntervalSince1970 ?? 0)"
            case .memory(let m): m.text
            case .message(let n): "\(n.summary)|\(n.due?.timeIntervalSince1970 ?? 0)|\(n.calendarDraft.map { $0.arguments.canonicalData().base64EncodedString() } ?? "")"
            }
        }
    }

    var events: [(String, EventSnapshot)]
    var tasks: [(String, TaskSnapshot)]
    var memories: [(String, ContextSnippet)]
    var messages: [(String, MessageNote)]
    private var table: [String: Ref] = [:]

    init(_ input: AdvisorInput) {
        events = input.events.sorted { $0.start < $1.start }.prefix(40).enumerated().map { ("E\($0 + 1)", $1) }
        tasks = input.tasks.prefix(30).enumerated().map { ("T\($0 + 1)", $1) }
        memories = input.memories.prefix(20).enumerated().map { ("M\($0 + 1)", $1) }
        messages = input.messages.sorted { $0.date > $1.date }.prefix(30).enumerated().map { ("S\($0 + 1)", $1) }
        for (a, e) in events { table[a] = .event(e) }
        for (a, t) in tasks { table[a] = .task(t) }
        for (a, m) in memories { table[a] = .memory(m) }
        for (a, m) in messages { table[a] = .message(m) }
    }

    var isEmpty: Bool { events.isEmpty && tasks.isEmpty && messages.isEmpty }

    func ref(_ alias: String) -> Ref? { table[alias.trimmingCharacters(in: .whitespaces).uppercased()] }

    /// Human-readable evidence line shown under “提醒原因”.
    func describe(_ alias: String) -> String? {
        switch ref(alias) {
        case .event(let e): CoreLocalization.format("日程：%@", String(describing: e.title))
        case .task(let t): CoreLocalization.format("待办：%@", String(describing: t.title))
        case .memory(let m): CoreLocalization.format("记忆：%@", String(describing: m.text.prefix(80)))
        case .message(let n): CoreLocalization.format("短信（%@）：%@", String(describing: n.sender), String(describing: n.summary))
        case nil: nil
        }
    }
}

/// FNV-1a; `Hasher` is randomly seeded per process and cannot be persisted.
struct StableHasher {
    private var value: UInt64 = 0xcbf2_9ce4_8422_2325
    mutating func add(_ s: String) {
        for b in s.utf8 { value = (value ^ UInt64(b)) &* 0x100_0000_01b3 }
        value = (value ^ 0x0a) &* 0x100_0000_01b3
    }
    var hex: String { String(value, radix: 16) }
}

/// OpenAI-compatible chat completions call, the same protocol the configured runtime uses.
public struct ChatCompletionClient: Sendable {
    public var baseURL: URL
    public var model: String
    public var apiKey: String
    public init(baseURL: URL, model: String, apiKey: String) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
    }

    public func complete(system: String, user: String) async throws -> String {
        var req = URLRequest(url: try ModelHTTPConnection.endpoint(baseURL.absoluteString), timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "model": model, "temperature": 0.2, "max_tokens": 1200,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        if baseURL.host?.lowercased() == "api.deepseek.com" { body["thinking"] = ["type": "disabled"] }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await ModelHTTPConnection.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        struct Body: Decodable {
            struct Choice: Decodable { struct Message: Decodable { var content: String? }; var message: Message }
            var choices: [Choice]
        }
        return try JSONDecoder().decode(Body.self, from: data).choices.first?.message.content ?? ""
    }
}
