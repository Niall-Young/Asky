import Foundation
import Contracts

// MARK: - Executions (dedupe + persistence of tool calls)

public struct ExecutionRecord: Sendable, Hashable {
    public var requestID: String
    public var tool: String
    public var argumentsDigest: String
    public var origin: String
    public var taskID: String?
    public var status: ExecutionStatus
    public var result: ExecutionResult?
    public var createdAt: Date
    public var updatedAt: Date

    public init(requestID: String, tool: String, argumentsDigest: String, origin: String, taskID: String?,
                status: ExecutionStatus, result: ExecutionResult?, createdAt: Date, updatedAt: Date) {
        self.requestID = requestID
        self.tool = tool
        self.argumentsDigest = argumentsDigest
        self.origin = origin
        self.taskID = taskID
        self.status = status
        self.result = result
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ExecutionStore: Sendable {
    let db: Database
    public init(_ store: LocalStore) { db = store.db }

    public func record(requestID: String) -> ExecutionRecord? {
        (try? db.query("SELECT * FROM executions WHERE request_id = ?", [requestID]))?.first.map(Self.decode)
    }

    /// Most recent completed / in-flight execution with the same digest inside `window` (for write dedupe).
    public func recent(digest: String, within window: TimeInterval, now: Date = Date()) -> ExecutionRecord? {
        (try? db.query("""
            SELECT * FROM executions WHERE args_digest = ? AND updated_at >= ?
              AND status IN ('completed','pendingVerification') ORDER BY updated_at DESC LIMIT 1
            """, [digest, now.addingTimeInterval(-window)]))?.first.map(Self.decode)
    }

    public func upsert(_ r: ExecutionRecord) throws {
        try db.run("""
            INSERT INTO executions(request_id, tool, args_digest, origin, task_id, status, result, created_at, updated_at)
            VALUES(?,?,?,?,?,?,?,?,?)
            ON CONFLICT(request_id) DO UPDATE SET status = excluded.status, result = excluded.result,
              updated_at = excluded.updated_at
            """, [r.requestID, r.tool, r.argumentsDigest, r.origin, r.taskID, r.status.rawValue,
                  r.result.map { JSONText.encode($0) }, r.createdAt, r.updatedAt])
    }

    public func pendingVerification(limit: Int = 50) -> [ExecutionRecord] {
        ((try? db.query("SELECT * FROM executions WHERE status = 'pendingVerification' ORDER BY updated_at DESC LIMIT ?",
                        [limit])) ?? []).map(Self.decode)
    }

    /// Completed web_search / web_read_page outputs for the given origins, newest first.
    public func completedWebOutputs(origins: [String], limit: Int = 80) -> [(tool: String, output: JSONValue)] {
        let unique = Array(Set(origins.filter { !$0.isEmpty }))
        guard !unique.isEmpty, limit > 0 else { return [] }
        let placeholders = Array(repeating: "?", count: unique.count).joined(separator: ",")
        let sql = """
            SELECT tool, result FROM executions
            WHERE origin IN (\(placeholders))
              AND tool IN ('web_search', 'web_read_page')
              AND status = 'completed'
              AND result IS NOT NULL
            ORDER BY updated_at DESC LIMIT ?
            """
        var bindings: [(any SQLBindable)?] = unique
        bindings.append(limit)
        guard let rows = try? db.query(sql, bindings) else { return [] }
        return rows.compactMap { row in
            guard let tool = row.string("tool"),
                  let result = JSONText.decode(row.string("result"), as: ExecutionResult.self),
                  let output = result.output else { return nil }
            return (tool, output)
        }
    }

    static func decode(_ row: Row) -> ExecutionRecord {
        ExecutionRecord(requestID: row.string("request_id") ?? "", tool: row.string("tool") ?? "",
                        argumentsDigest: row.string("args_digest") ?? "", origin: row.string("origin") ?? "",
                        taskID: row.string("task_id"),
                        status: ExecutionStatus(rawValue: row.string("status") ?? "") ?? .failed,
                        result: JSONText.decode(row.string("result"), as: ExecutionResult.self),
                        createdAt: row.date("created_at") ?? .distantPast, updatedAt: row.date("updated_at") ?? .distantPast)
    }
}

// MARK: - Sources & activity

public struct SourceRecord: Sendable, Hashable {
    public var id: String
    public var kind: String
    public var title: String
    public var permissions: SourcePermissions
    public var createdAt: Date
    public init(id: String, kind: String, title: String, permissions: SourcePermissions, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.title = title
        self.permissions = permissions
        self.createdAt = createdAt
    }
}

public struct SourceStore: Sendable {
    let db: Database
    public init(_ store: LocalStore) { db = store.db }

    public func upsert(_ s: SourceRecord) throws {
        try db.run("""
            INSERT INTO sources(id, kind, title, permissions, created_at) VALUES(?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET title = excluded.title, permissions = excluded.permissions
            """, [s.id, s.kind, s.title, s.permissions.rawValue, s.createdAt])
    }

    public func source(_ id: String) -> SourceRecord? {
        (try? db.query("SELECT * FROM sources WHERE id = ?", [id]))?.first.map {
            SourceRecord(id: $0.string("id") ?? "", kind: $0.string("kind") ?? "", title: $0.string("title") ?? "",
                         permissions: SourcePermissions(rawValue: $0.int("permissions") ?? 0),
                         createdAt: $0.date("created_at") ?? .distantPast)
        }
    }

    public func permissions(_ id: String) -> SourcePermissions {
        source(id)?.permissions ?? .none
    }

    public func isDeleted(_ id: String) -> Bool {
        ((try? db.scalarInt("SELECT COUNT(*) FROM deletion_markers WHERE source_id = ?", [id])) ?? 0) > 0
    }
}

public struct ActivityStore: Sendable {
    public static let retention: TimeInterval = 30 * 24 * 3600
    let db: Database
    public init(_ store: LocalStore) { db = store.db }

    public func append(kind: String, sourceID: String, text: String, now: Date = Date()) throws {
        try db.run("INSERT INTO activity(id, kind, source_id, text, created_at, expires_at) VALUES(?,?,?,?,?,?)",
                   [UUID().uuidString, kind, sourceID, text, now, now.addingTimeInterval(Self.retention)])
    }

    /// Expiry is not a deletion: derived memories keep their provenance and are not marked source-deleted.
    @discardableResult
    public func purgeExpired(now: Date = Date()) throws -> Int {
        try db.run("DELETE FROM activity WHERE expires_at < ?", [now])
    }

    public func count() -> Int { (try? db.scalarInt("SELECT COUNT(*) FROM activity")) ?? 0 }
}

// MARK: - Conversations & messages (display / search projection)

public struct ConversationSummary: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var runtimeSessionRef: String?
    public var updatedAt: Date
}

/// An explicitly selected excerpt or whole-message reply, retained with the user message.
public struct MessageQuote: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable { case selection, reply }
    public var id: String
    public var sourceMessageID: String
    public var text: String
    public var kind: Kind

    public init(id: String = UUID().uuidString, sourceMessageID: String, text: String, kind: Kind = .selection) {
        self.id = id
        self.sourceMessageID = sourceMessageID
        self.text = text
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey { case id, sourceMessageID, text, kind }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        sourceMessageID = try values.decode(String.self, forKey: .sourceMessageID)
        text = try values.decode(String.self, forKey: .text)
        kind = try values.decodeIfPresent(Kind.self, forKey: .kind) ?? .selection
    }

    public static func contextText(_ quotes: [MessageQuote]) -> String {
        quotes.enumerated().map { index, quote in
            "[\(quote.kind == .reply ? "回复" : "引用") \(index + 1)，来源消息 \(quote.sourceMessageID)]\n" + quote.text
        }.joined(separator: "\n\n")
    }
}

/// Transcript presentation and user-selected context; no raw tool arguments or results.
public struct MessagePresentation: Sendable, Hashable, Codable {
    public var responseID: String?
    public var toolName: String?
    public var toolStatus: ExecutionStatus?
    public var toolError: String?
    public var needsPermissionSettings: Bool
    public var workSeconds: Int?
    public var completedAt: Date?
    /// Non-nil (including an empty dictionary) permanently marks a submitted form.
    public var submittedFormValues: [String: [String]]?
    public var quotes: [MessageQuote]?
    /// The assistant's single emoji reaction, attached to the user message.
    public var agentReaction: String?

    public init(responseID: String? = nil, toolName: String? = nil, toolStatus: ExecutionStatus? = nil,
                toolError: String? = nil, needsPermissionSettings: Bool = false,
                workSeconds: Int? = nil, completedAt: Date? = nil,
                submittedFormValues: [String: [String]]? = nil, quotes: [MessageQuote]? = nil,
                agentReaction: String? = nil) {
        self.responseID = responseID
        self.toolName = toolName
        self.toolStatus = toolStatus
        self.toolError = toolError
        self.needsPermissionSettings = needsPermissionSettings
        self.workSeconds = workSeconds
        self.completedAt = completedAt
        self.submittedFormValues = submittedFormValues
        self.quotes = quotes
        self.agentReaction = agentReaction
    }
}

public struct StoredMessage: Sendable, Hashable, Identifiable {
    public var id: String
    public var conversationID: String
    public var seq: Int
    public var role: String
    public var text: String
    public var createdAt: Date
    public var attachments: [AttachmentRef] = []
    public var presentation: MessagePresentation? = nil
}

public struct ConversationStore: Sendable {
    let db: Database
    public init(_ store: LocalStore) { db = store.db }

    public func create(title: String, now: Date = Date()) throws -> String {
        let id = UUID().uuidString
        try db.run("INSERT INTO conversations(id, title, created_at, updated_at) VALUES(?,?,?,?)", [id, title, now, now])
        return id
    }

    public func setRuntimeSession(_ id: String, ref: String?) throws {
        try db.run("UPDATE conversations SET runtime_session_ref = ? WHERE id = ?", [ref, id])
    }

    @discardableResult
    public func append(conversationID: String, role: String, text: String, attachments: [AttachmentRef] = [], id: String = UUID().uuidString,
                       presentation: MessagePresentation? = nil, now: Date = Date()) throws -> StoredMessage {
        let attachmentJSON = String(decoding: try JSONEncoder().encode(attachments), as: UTF8.self)
        return try db.transaction {
            let seq = try db.scalarInt("SELECT COALESCE(MAX(seq), 0) + 1 FROM messages WHERE conversation_id = ?", [conversationID])
            try db.run("INSERT INTO messages(id, conversation_id, seq, role, text, created_at, attachments_json, presentation_json) VALUES(?,?,?,?,?,?,?,?)",
                       [id, conversationID, seq, role, text, now, attachmentJSON, presentation.map(JSONText.encode)])
            try db.run("INSERT INTO messages_fts(id, conversation_id, text) VALUES(?,?,?)", [id, conversationID, text])
            try db.run("UPDATE conversations SET updated_at = ? WHERE id = ?", [now, conversationID])
            return StoredMessage(id: id, conversationID: conversationID, seq: seq, role: role, text: text, createdAt: now, attachments: attachments, presentation: presentation)
        }
    }

    public func message(_ id: String, conversationID: String) -> StoredMessage? {
        (try? db.query("SELECT * FROM messages WHERE id = ? AND conversation_id = ?", [id, conversationID]))?
            .first.map(Self.decode)
    }

    /// Resolve a quoted message across the continuous timeline's storage segments.
    public func message(_ id: String) -> StoredMessage? {
        (try? db.query("SELECT * FROM messages WHERE id = ?", [id]))?.first.map(Self.decode)
    }

    public enum FormReplyError: Error { case unavailable, alreadySubmitted }

    /// Save the answer and consume its source form together, even across timeline segments.
    /// A failed append leaves the form available; deleting the reply never unlocks the source.
    public func appendFormReply(sourceID: String, sourceConversationID: String,
                                conversationID: String, text: String,
                                values: [String: [String]]) throws -> StoredMessage {
        try db.transaction {
            guard let source = message(sourceID, conversationID: sourceConversationID),
                  source.role == "assistant" else { throw FormReplyError.unavailable }
            var presentation = source.presentation ?? MessagePresentation()
            guard presentation.submittedFormValues == nil else { throw FormReplyError.alreadySubmitted }
            presentation.submittedFormValues = values
            let reply = try append(conversationID: conversationID, role: "user", text: text)
            try db.run("UPDATE messages SET presentation_json = ? WHERE id = ? AND conversation_id = ?",
                       [JSONText.encode(presentation), sourceID, sourceConversationID])
            return reply
        }
    }

    /// Update a recorded step without changing its ordering or duplicating its search entry.
    public func updateMessage(_ id: String, conversationID: String, text: String, presentation: MessagePresentation) throws {
        try db.transaction {
            try db.run("UPDATE messages SET text = ?, presentation_json = ? WHERE id = ? AND conversation_id = ?",
                       [text, JSONText.encode(presentation), id, conversationID])
            try db.run("UPDATE messages_fts SET text = ? WHERE id = ? AND conversation_id = ?", [text, id, conversationID])
        }
    }

    public func list(limit: Int, before: Date? = nil) -> [ConversationSummary] {
        let rows = (try? db.query("""
            SELECT id, title, runtime_session_ref, updated_at FROM conversations
            WHERE updated_at < ? ORDER BY updated_at DESC LIMIT ?
            """, [before ?? .distantFuture, limit])) ?? []
        return rows.map {
            ConversationSummary(id: $0.string("id") ?? "", title: $0.string("title") ?? "",
                                runtimeSessionRef: $0.string("runtime_session_ref"), updatedAt: $0.date("updated_at") ?? .distantPast)
        }
    }

    /// Page of messages ending before `beforeSeq` (newest page when nil), returned in ascending order.
    public func messages(conversationID: String, limit: Int, beforeSeq: Int? = nil, dialogueOnly: Bool = false) -> [StoredMessage] {
        let roleFilter = dialogueOnly ? "AND role IN ('user', 'assistant')" : ""
        let rows = (try? db.query("""
            SELECT * FROM messages WHERE conversation_id = ? AND seq < ? \(roleFilter) ORDER BY seq DESC LIMIT ?
            """, [conversationID, beforeSeq ?? Int.max, limit])) ?? []
        return rows.reversed().map(Self.decode)
    }

    public func search(_ text: String, limit: Int = 20) -> [StoredMessage] {
        let tokens = FTSQuery.tokens(text)
        guard !tokens.isEmpty else { return [] }
        let rows: [Row]
        if FTSQuery.canUseIndex(tokens) {
            rows = (try? db.query("""
                SELECT m.* FROM messages_fts f JOIN messages m ON m.id = f.id
                WHERE messages_fts MATCH ? ORDER BY m.created_at DESC LIMIT ?
                """, [FTSQuery.match(tokens), limit])) ?? []
        } else {
            let clause = tokens.map { _ in "text LIKE ? ESCAPE '\\'" }.joined(separator: " AND ")
            let args: [SQLBindable?] = tokens.map { FTSQuery.likePattern($0) } + [limit]
            rows = (try? db.query("SELECT * FROM messages WHERE \(clause) ORDER BY created_at DESC LIMIT ?", args)) ?? []
        }
        return rows.map(Self.decode)
    }

    /// Global transcript projection; IDs remain owned by their original storage segment.
    public func timeline(limit: Int = 40, before: StoredMessage? = nil) -> [StoredMessage] {
        let rows = (try? db.query("""
            SELECT * FROM messages WHERE created_at < ? OR
              (created_at = ? AND id < ?) ORDER BY created_at DESC, id DESC LIMIT ?
            """, [before?.createdAt ?? .distantFuture, before?.createdAt ?? .distantFuture,
                   before?.id ?? "", limit])) ?? []
        return rows.reversed().map(Self.decode)
    }

    public static let historyAnchorSettingKey = "agent.historyAnchorMessageID"

    /// UTF-8 byte cost used to bound history context snippets.
    public static func contextByteCount(_ message: StoredMessage) -> Int {
        message.text.utf8.count + MessageQuote.contextText(message.presentation?.quotes ?? []).utf8.count
    }

    /// Most recent user/assistant messages across the global timeline in chronological order.
    public func recentDialogue(limit: Int = 80) -> [StoredMessage] {
        let rows = (try? db.query("""
            SELECT * FROM messages WHERE role IN ('user', 'assistant')
            ORDER BY created_at DESC, id DESC LIMIT ?
            """, [limit])) ?? []
        return rows.reversed().map(Self.decode)
    }

    /// Chronological user/assistant messages starting at and including `anchor`.
    public func dialogue(from anchor: StoredMessage, limit: Int = 200) -> [StoredMessage] {
        let rows = (try? db.query("""
            SELECT * FROM messages WHERE role IN ('user', 'assistant')
              AND (created_at > ? OR (created_at = ? AND id >= ?))
            ORDER BY created_at ASC, id ASC LIMIT ?
            """, [anchor.createdAt, anchor.createdAt, anchor.id, limit])) ?? []
        return rows.map(Self.decode)
    }

    /// Append-only history window for prompt prefix caching.
    /// Keeps the starting anchor fixed across consecutive turns until the window exceeds `maxBytes`
    /// or `maxMessages`, then rolls the anchor forward in one batch to leave headroom for future appends.
    public func anchoredDialogue(
        in store: LocalStore,
        maxBytes: Int = 40_000,
        rolloverBytes: Int = 20_000,
        maxMessages: Int = 80,
        rolloverMessages: Int = 40
    ) -> [StoredMessage] {
        if let anchorID = store.setting(Self.historyAnchorSettingKey),
           let anchor = message(anchorID),
           anchor.role == "user" || anchor.role == "assistant" {
            let current = dialogue(from: anchor, limit: maxMessages + 1)
            let bytes = current.reduce(0) { $0 + Self.contextByteCount($1) }
            if !current.isEmpty, current.count <= maxMessages, bytes <= maxBytes {
                return current
            }
        }
        let recent = recentDialogue(limit: maxMessages)
        var selected: [StoredMessage] = []
        var bytes = 0
        for item in recent.reversed() {
            let size = Self.contextByteCount(item)
            if selected.isEmpty {
                guard size <= maxBytes else { continue }
                selected.append(item)
                bytes += size
            } else if selected.count < rolloverMessages, bytes + size <= rolloverBytes {
                selected.append(item)
                bytes += size
            } else {
                break
            }
        }
        selected.reverse()
        store.setSetting(Self.historyAnchorSettingKey, selected.first?.id)
        return selected
    }

    /// Adjacent newer page, including presentation-only records, in transcript order.
    public func newerMessages(conversationID: String, afterSeq: Int, limit: Int) -> [StoredMessage] {
        ((try? db.query("SELECT * FROM messages WHERE conversation_id = ? AND seq > ? ORDER BY seq ASC LIMIT ?",
                       [conversationID, afterSeq, limit])) ?? []).map(Self.decode)
    }

    public func newerTimeline(after: StoredMessage, limit: Int = 40) -> [StoredMessage] {
        ((try? db.query("""
            SELECT * FROM messages WHERE created_at > ? OR
              (created_at = ? AND id > ?) ORDER BY created_at ASC, id ASC LIMIT ?
            """, [after.createdAt, after.createdAt, after.id, limit])) ?? []).map(Self.decode)
    }

    public func after(conversationID: String, seq: Int, limit: Int) -> [StoredMessage] {
        ((try? db.query("SELECT * FROM messages WHERE conversation_id = ? AND seq > ? AND role IN ('user','assistant') ORDER BY seq LIMIT ?",
                       [conversationID, seq, limit])) ?? []).map(Self.decode)
    }

    public func delete(_ id: String) throws {
        try db.transaction {
            try db.run("DELETE FROM messages_fts WHERE conversation_id = ?", [id])
            try db.run("DELETE FROM conversations WHERE id = ?", [id])
        }
    }

    static func decode(_ r: Row) -> StoredMessage {
        StoredMessage(id: r.string("id") ?? "", conversationID: r.string("conversation_id") ?? "", seq: r.int("seq") ?? 0,
                      role: r.string("role") ?? "", text: r.string("text") ?? "", createdAt: r.date("created_at") ?? .distantPast,
                      attachments: (try? JSONDecoder().decode([AttachmentRef].self,
                          from: Data((r.string("attachments_json") ?? "[]").utf8))) ?? [],
                      presentation: JSONText.decode(r.string("presentation_json"), as: MessagePresentation.self))
    }
}

// MARK: - Clipboard history

public enum ClipboardKind: String, Sendable, Codable {
    case text, image, file
}

public struct ClipboardItem: Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: ClipboardKind
    public var text: String?
    public var filePath: String?
    /// Original file references; never owned or deleted by clipboard history.
    public var filePaths: [String]
    public var thumbPath: String?
    public var byteSize: Int
    public var sourceApp: String?
    public var sourceBundleID: String?
    public var pinned: Bool
    public var contentHash: String
    public var createdAt: Date

    /// Image display name based on the record's copy time in the current time zone.
    public var imageTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy_MM_dd_HH_mm_ss"
        return formatter.string(from: createdAt)
    }

    public init(id: String = UUID().uuidString, kind: ClipboardKind, text: String? = nil, filePath: String? = nil,
                thumbPath: String? = nil, filePaths: [String] = [], byteSize: Int, sourceApp: String? = nil, sourceBundleID: String? = nil,
                pinned: Bool = false, contentHash: String, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.text = text
        self.filePath = filePath
        self.thumbPath = thumbPath
        self.filePaths = filePaths.isEmpty && kind == .file ? filePath.map { [$0] } ?? [] : filePaths
        self.byteSize = byteSize
        self.sourceApp = sourceApp
        self.sourceBundleID = sourceBundleID
        self.pinned = pinned
        self.contentHash = contentHash
        self.createdAt = createdAt
    }
}

public enum ClipboardRetention: Int, Codable, CaseIterable, Sendable {
    case eightHours = 8, oneDay = 24, threeDays = 72, sevenDays = 168, thirtyDays = 720
    public var interval: TimeInterval { TimeInterval(rawValue) * 3600 }
}

public struct ClipboardStore: Sendable {
    public static let retention: TimeInterval = 3 * 24 * 3600
    public static let byteBudget = 200 * 1024 * 1024
    let db: Database
    public let retentionInterval: TimeInterval
    public init(_ store: LocalStore, retention: ClipboardRetention = .threeDays) {
        db = store.db
        retentionInterval = retention.interval
    }

    /// Inserts, or bumps the existing row with the same content hash to the top.
    public func insert(_ item: ClipboardItem) throws {
        try db.transaction {
            if let existing = try db.query("SELECT id FROM clipboard WHERE content_hash = ? LIMIT 1", [item.contentHash]).first?.string("id") {
                try db.run("UPDATE clipboard SET created_at = ?, source_app = ?, source_bundle_id = ? WHERE id = ?",
                           [item.createdAt, item.sourceApp, item.sourceBundleID, existing])
                return
            }
            try db.run("""
                INSERT INTO clipboard(id, kind, text, file_path, thumb_path, byte_size, source_app, source_bundle_id, pinned, content_hash, created_at, file_paths_json)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
                """, [item.id, item.kind.rawValue, item.text, item.filePath, item.thumbPath, item.byteSize, item.sourceApp,
                      item.sourceBundleID, item.pinned, item.contentHash, item.createdAt, JSONText.encode(item.filePaths)])
            if let t = item.text { try db.run("INSERT INTO clipboard_fts(id, text) VALUES(?,?)", [item.id, t]) }
        }
    }

    public func recent(limit: Int, before: Date? = nil, offset: Int = 0) -> [ClipboardItem] {
        ((try? db.query("SELECT * FROM clipboard WHERE created_at < ? ORDER BY pinned DESC, created_at DESC, id DESC LIMIT ? OFFSET ?",
                        [before ?? .distantFuture, limit, max(0, offset)])) ?? []).map(Self.decode)
    }

    public var changeRevision: Int { (try? db.query("SELECT total_changes() AS revision"))?.first?.int("revision") ?? 0 }

    /// Stable keyset pages; new captures do not shift an older page's boundary.
    public func page(limit: Int, before: ClipboardItem? = nil) -> [ClipboardItem] {
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        let boundary = before == nil ? "" : " AND (created_at < ? OR (created_at = ? AND id < ?))"
        var arguments: [any SQLBindable] = [cutoff]
        if let before { arguments += [before.createdAt, before.createdAt, before.id] }
        arguments.append(limit)
        return ((try? db.query("SELECT * FROM clipboard WHERE created_at > ?" + boundary
            + " ORDER BY created_at DESC, id DESC LIMIT ?", arguments)) ?? []).map(Self.decode)
    }

    public func search(_ text: String, limit: Int = 20) -> [ClipboardItem] {
        let tokens = FTSQuery.tokens(text)
        guard !tokens.isEmpty else { return recent(limit: limit) }
        // Match image names before limiting results, including records without stored text.
        // Keep the existing localized type keywords searchable as well.
        let matchesImageTitle = ["图片", "Image"].contains { title in
            tokens.allSatisfy { title.localizedCaseInsensitiveContains($0) }
        }
        let imageNameClause = tokens.map { _ in
            "strftime('%Y_%m_%d_%H_%M_%S', CAST(c.created_at AS INTEGER), 'unixepoch', 'localtime') LIKE ? ESCAPE '\\'"
        }.joined(separator: " AND ")
        let imageNameArguments = tokens.map { FTSQuery.likePattern($0) }
        let rows: [Row]
        if FTSQuery.canUseIndex(tokens) {
            rows = (try? db.query("""
                SELECT c.* FROM clipboard c
                WHERE c.id IN (SELECT id FROM clipboard_fts WHERE clipboard_fts MATCH ?)
                    OR (c.kind = 'image' AND (? OR (\(imageNameClause))))
                ORDER BY c.created_at DESC LIMIT ?
                """, [FTSQuery.match(tokens), matchesImageTitle] + imageNameArguments + [limit])) ?? []
        } else {
            let clause = tokens.map { _ in "text LIKE ? ESCAPE '\\'" }.joined(separator: " AND ")
            rows = (try? db.query("""
                SELECT c.* FROM clipboard c WHERE (\(clause))
                    OR (c.kind = 'image' AND (? OR (\(imageNameClause))))
                ORDER BY created_at DESC LIMIT ?
                """, tokens.map { FTSQuery.likePattern($0) } + [matchesImageTitle] + imageNameArguments + [limit])) ?? []
        }
        return rows.map(Self.decode)
    }

    public func setPinned(_ id: String, _ pinned: Bool) throws {
        try db.run("UPDATE clipboard SET pinned = ? WHERE id = ?", [pinned, id])
    }

    /// Deletes rows and returns the file paths the caller must remove from disk.
    @discardableResult
    public func delete(ids: [String]) throws -> [String] {
        guard !ids.isEmpty else { return [] }
        return try db.transaction {
            var paths: [String] = []
            for id in ids {
                if let r = try db.query("SELECT kind, file_path, thumb_path FROM clipboard WHERE id = ?", [id]).first {
                    if r.string("kind") == ClipboardKind.image.rawValue {
                        paths += [r.string("file_path"), r.string("thumb_path")].compactMap { $0 }
                    }
                }
                try db.run("DELETE FROM clipboard_fts WHERE id = ?", [id])
                try db.run("DELETE FROM clipboard WHERE id = ?", [id])
            }
            return paths
        }
    }

    /// Clears the entire history, including pinned rows and the search index.
    /// Only owned image assets are returned; original file references are preserved.
    @discardableResult
    public func clearAll() throws -> [String] {
        try db.transaction {
            let paths = try db.query("SELECT file_path, thumb_path FROM clipboard WHERE kind = ?", [ClipboardKind.image.rawValue])
                .flatMap { [$0.string("file_path"), $0.string("thumb_path")].compactMap { $0 } }
            try db.run("DELETE FROM clipboard_fts")
            try db.run("DELETE FROM clipboard")
            return paths
        }
    }

    /// Removes all expired items (including legacy pinned rows), then oldest unpinned items over budget.
    /// Returns file paths to remove.
    public func cleanup(now: Date = Date(), budget: Int = ClipboardStore.byteBudget) throws -> [String] {
        let expired = try db.query("SELECT id FROM clipboard WHERE created_at <= ?",
                                   [now.addingTimeInterval(-retentionInterval)]).compactMap { $0.string("id") }
        var paths = try delete(ids: expired)
        var total = try db.scalarInt("SELECT COALESCE(SUM(byte_size), 0) FROM clipboard")
        guard total > budget else { return paths }
        let rows = try db.query("SELECT id, byte_size FROM clipboard WHERE pinned = 0 ORDER BY created_at ASC LIMIT 1000")
        var victims: [String] = []
        for r in rows where total > budget {
            victims.append(r.string("id") ?? "")
            total -= r.int("byte_size") ?? 0
        }
        paths += try delete(ids: victims)
        return paths
    }

    public func totalBytes() -> Int { (try? db.scalarInt("SELECT COALESCE(SUM(byte_size), 0) FROM clipboard")) ?? 0 }

    static func decode(_ r: Row) -> ClipboardItem {
        ClipboardItem(id: r.string("id") ?? "", kind: ClipboardKind(rawValue: r.string("kind") ?? "") ?? .text,
                      text: r.string("text"), filePath: r.string("file_path"), thumbPath: r.string("thumb_path"),
                      filePaths: JSONText.decode(r.string("file_paths_json"), as: [String].self) ?? [],
                      byteSize: r.int("byte_size") ?? 0, sourceApp: r.string("source_app"),
                      sourceBundleID: r.string("source_bundle_id"), pinned: r.bool("pinned"),
                      contentHash: r.string("content_hash") ?? "", createdAt: r.date("created_at") ?? .distantPast)
    }
}

// MARK: - Reminder plans

public struct ReminderStore: Sendable {
    let db: Database
    public init(_ store: LocalStore) { db = store.db }

    public func upsert(_ p: ReminderPlan, now: Date = Date()) throws {
        try db.run("""
            INSERT INTO reminder_plans(id, event_id, reason, title, body, evidence, fire_date, status, fingerprint,
              user_requested, dedupe_key, updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET title = excluded.title, body = excluded.body, evidence = excluded.evidence,
              fire_date = excluded.fire_date, status = excluded.status, fingerprint = excluded.fingerprint,
              updated_at = excluded.updated_at
            """, [p.id, p.eventID, p.reason.rawValue, p.title, p.body, JSONText.encode(p.evidence), p.fireDate,
                  p.status.rawValue, p.eventFingerprint, p.userRequested, p.dedupeKey, now])
    }

    public func plan(dedupeKey: String) -> ReminderPlan? {
        (try? db.query("SELECT * FROM reminder_plans WHERE dedupe_key = ? ORDER BY updated_at DESC LIMIT 1", [dedupeKey]))?
            .first.map(Self.decode)
    }

    public func plans(status: [ReminderPlanStatus], limit: Int = 200) -> [ReminderPlan] {
        let marks = status.map { _ in "?" }.joined(separator: ",")
        let args: [SQLBindable?] = status.map(\.rawValue) + [limit]
        return ((try? db.query("SELECT * FROM reminder_plans WHERE status IN (\(marks)) ORDER BY fire_date LIMIT ?", args)) ?? [])
            .map(Self.decode)
    }

    public func setStatus(_ id: String, _ status: ReminderPlanStatus, fireDate: Date? = nil, now: Date = Date()) throws {
        if let fireDate {
            try db.run("UPDATE reminder_plans SET status = ?, fire_date = ?, updated_at = ? WHERE id = ?",
                       [status.rawValue, fireDate, now, id])
        } else {
            try db.run("UPDATE reminder_plans SET status = ?, updated_at = ? WHERE id = ?", [status.rawValue, now, id])
        }
    }

    /// Delivered non-user-requested suggestions within [start, end).
    public func deliveredSuggestions(from start: Date, to end: Date) -> Int {
        (try? db.scalarInt("""
            SELECT COUNT(*) FROM reminder_plans WHERE user_requested = 0 AND status IN ('delivered','handled')
              AND fire_date >= ? AND fire_date < ?
            """, [start, end])) ?? 0
    }

    public func isCategoryEnabled(_ reason: ReminderReason) -> Bool {
        let rows = (try? db.query("SELECT enabled FROM reminder_category_state WHERE reason = ?", [reason.rawValue])) ?? []
        return rows.first.map { $0.bool("enabled") } ?? true
    }

    public func setCategory(_ reason: ReminderReason, enabled: Bool) throws {
        try db.run("""
            INSERT INTO reminder_category_state(reason, enabled) VALUES(?,?)
            ON CONFLICT(reason) DO UPDATE SET enabled = excluded.enabled
            """, [reason.rawValue, enabled])
    }

    static func decode(_ r: Row) -> ReminderPlan {
        ReminderPlan(id: r.string("id") ?? "", eventID: r.string("event_id") ?? "",
                     reason: ReminderReason(rawValue: r.string("reason") ?? "") ?? .conflict,
                     title: r.string("title") ?? "", body: r.string("body") ?? "",
                     evidence: JSONText.decode(r.string("evidence"), as: [String].self) ?? [],
                     fireDate: r.date("fire_date") ?? .distantPast,
                     status: ReminderPlanStatus(rawValue: r.string("status") ?? "") ?? .cancelled,
                     eventFingerprint: r.string("fingerprint") ?? "", userRequested: r.bool("user_requested"))
    }
}

// MARK: - MCP instances

public struct MCPInstance: Sendable, Hashable, Identifiable, Codable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var readOnly: Bool
    public var sources: [DataSourceID]
    public var createdAt: Date
    public init(id: String = UUID().uuidString, name: String, enabled: Bool = false, readOnly: Bool = true,
                sources: [DataSourceID] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.readOnly = readOnly
        self.sources = sources
        self.createdAt = createdAt
    }
}

public struct MCPInstanceStore: Sendable {
    let db: Database
    public init(_ store: LocalStore) { db = store.db }

    /// Stores only the credential hash; the credential itself lives in Keychain / the client config.
    public func save(_ i: MCPInstance, credentialHash: String) throws {
        try db.run("""
            INSERT INTO mcp_instances(id, name, enabled, read_only, sources, credential_hash, created_at) VALUES(?,?,?,?,?,?,?)
            ON CONFLICT(id) DO UPDATE SET name = excluded.name, enabled = excluded.enabled, read_only = excluded.read_only,
              sources = excluded.sources, credential_hash = excluded.credential_hash
            """, [i.id, i.name, i.enabled, i.readOnly, JSONText.encode(i.sources), credentialHash, i.createdAt])
    }

    public func update(_ i: MCPInstance) throws {
        try db.run("UPDATE mcp_instances SET name = ?, enabled = ?, read_only = ?, sources = ? WHERE id = ?",
                   [i.name, i.enabled, i.readOnly, JSONText.encode(i.sources), i.id])
    }

    public func all() -> [MCPInstance] {
        ((try? db.query("SELECT * FROM mcp_instances ORDER BY created_at LIMIT 100")) ?? []).map(Self.decode)
    }

    public func instance(credentialHash: String) -> MCPInstance? {
        (try? db.query("SELECT * FROM mcp_instances WHERE credential_hash = ?", [credentialHash]))?.first.map(Self.decode)
    }

    public func delete(_ id: String) throws { try db.run("DELETE FROM mcp_instances WHERE id = ?", [id]) }

    static func decode(_ r: Row) -> MCPInstance {
        MCPInstance(id: r.string("id") ?? "", name: r.string("name") ?? "", enabled: r.bool("enabled"),
                    readOnly: r.bool("read_only"), sources: JSONText.decode(r.string("sources"), as: [DataSourceID].self) ?? [],
                    createdAt: r.date("created_at") ?? .distantPast)
    }
}
