import Foundation

/// Ordered schema migrations, tracked with PRAGMA user_version.
public enum Schema {
    public static let migrations: [String] = [
        // v1
        """
        CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);

        CREATE TABLE sources (
            id TEXT PRIMARY KEY, kind TEXT NOT NULL, title TEXT NOT NULL DEFAULT '',
            permissions INTEGER NOT NULL, state TEXT NOT NULL DEFAULT 'active',
            created_at REAL NOT NULL);

        CREATE TABLE activity (
            id TEXT PRIMARY KEY, kind TEXT NOT NULL, source_id TEXT NOT NULL, text TEXT NOT NULL,
            created_at REAL NOT NULL, expires_at REAL NOT NULL);
        CREATE INDEX activity_expiry ON activity(expires_at);
        CREATE INDEX activity_source ON activity(source_id);

        CREATE TABLE memories (
            id TEXT PRIMARY KEY, content TEXT NOT NULL, kind TEXT NOT NULL, status TEXT NOT NULL,
            source_ids TEXT NOT NULL, subjects TEXT NOT NULL, project TEXT, confirmed INTEGER NOT NULL,
            pinned INTEGER NOT NULL, supersedes TEXT, superseded_by TEXT, permissions INTEGER NOT NULL,
            source_deleted INTEGER NOT NULL DEFAULT 0, created_at REAL NOT NULL, updated_at REAL NOT NULL);
        CREATE TABLE memory_sources (memory_id TEXT NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
            source_id TEXT NOT NULL, PRIMARY KEY (memory_id, source_id));
        CREATE INDEX memory_sources_source ON memory_sources(source_id);
        CREATE VIRTUAL TABLE memories_fts USING fts5(id UNINDEXED, content, subjects, project, tokenize = 'trigram');

        CREATE TABLE deletion_markers (source_id TEXT PRIMARY KEY, deleted_at REAL NOT NULL);
        CREATE TABLE extraction_queue (source_id TEXT PRIMARY KEY, enqueued_at REAL NOT NULL);

        CREATE TABLE executions (
            request_id TEXT PRIMARY KEY, tool TEXT NOT NULL, args_digest TEXT NOT NULL, origin TEXT NOT NULL,
            task_id TEXT, status TEXT NOT NULL, result TEXT, created_at REAL NOT NULL, updated_at REAL NOT NULL);
        CREATE INDEX executions_digest ON executions(args_digest);

        CREATE TABLE reminder_plans (
            id TEXT PRIMARY KEY, event_id TEXT NOT NULL, reason TEXT NOT NULL, title TEXT NOT NULL,
            body TEXT NOT NULL, evidence TEXT NOT NULL, fire_date REAL NOT NULL, status TEXT NOT NULL,
            fingerprint TEXT NOT NULL, user_requested INTEGER NOT NULL, dedupe_key TEXT NOT NULL,
            updated_at REAL NOT NULL);
        CREATE INDEX reminder_dedupe ON reminder_plans(dedupe_key);
        CREATE TABLE reminder_category_state (reason TEXT PRIMARY KEY, enabled INTEGER NOT NULL);

        CREATE TABLE conversations (
            id TEXT PRIMARY KEY, title TEXT NOT NULL, runtime_session_ref TEXT,
            created_at REAL NOT NULL, updated_at REAL NOT NULL);
        CREATE TABLE messages (
            id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
            seq INTEGER NOT NULL, role TEXT NOT NULL, text TEXT NOT NULL, created_at REAL NOT NULL,
            UNIQUE (conversation_id, seq));
        CREATE VIRTUAL TABLE messages_fts USING fts5(id UNINDEXED, conversation_id UNINDEXED, text, tokenize = 'trigram');
        CREATE TABLE attachments (
            id TEXT PRIMARY KEY, conversation_id TEXT REFERENCES conversations(id) ON DELETE CASCADE,
            kind TEXT NOT NULL, path TEXT NOT NULL, temporary INTEGER NOT NULL, created_at REAL NOT NULL);

        CREATE TABLE clipboard (
            id TEXT PRIMARY KEY, kind TEXT NOT NULL, text TEXT, file_path TEXT, thumb_path TEXT,
            byte_size INTEGER NOT NULL, source_app TEXT, pinned INTEGER NOT NULL DEFAULT 0,
            content_hash TEXT NOT NULL, created_at REAL NOT NULL);
        CREATE INDEX clipboard_created ON clipboard(created_at);
        CREATE VIRTUAL TABLE clipboard_fts USING fts5(id UNINDEXED, text, tokenize = 'trigram');

        CREATE TABLE mcp_instances (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, enabled INTEGER NOT NULL, read_only INTEGER NOT NULL,
            sources TEXT NOT NULL, credential_hash TEXT NOT NULL, created_at REAL NOT NULL);
        """,
        // v2: attachment references belong to the submitted message, in selection order.
        "ALTER TABLE messages ADD COLUMN attachments_json TEXT NOT NULL DEFAULT '[]';",
        // v3: bundle ID resolves source icons even when the app is not running or its name is localized.
        "ALTER TABLE clipboard ADD COLUMN source_bundle_id TEXT;",
        // v4: last time a memory was given to the model, for pruning unused memories.
        "ALTER TABLE memories ADD COLUMN last_used_at REAL;",
        // v5: one copied selection preserves all original file references.
        "ALTER TABLE clipboard ADD COLUMN file_paths_json TEXT NOT NULL DEFAULT '[]';",
        // v6: native transcript presentation, independent of the model session format.
        "ALTER TABLE messages ADD COLUMN presentation_json TEXT;",
        // v7: failed history file deletions survive process exits and can be retried.
        "CREATE TABLE conversation_file_cleanup (path TEXT PRIMARY KEY, kind TEXT NOT NULL);",
    ]

    public static func migrate(_ db: Database) throws {
        let current = try db.scalarInt("PRAGMA user_version")
        guard current < migrations.count else { return }
        for v in current..<migrations.count {
            try db.transaction {
                try db.execute(migrations[v])
                try db.execute("PRAGMA user_version = \(v + 1)")
            }
        }
    }
}

/// Builds a safe query for trigram FTS. Tokens shorter than 3 characters cannot be served by
/// the trigram index; callers fall back to bounded LIKE matching for those.
public enum FTSQuery {
    public static func tokens(_ input: String) -> [String] {
        input.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
    }

    public static func canUseIndex(_ tokens: [String]) -> Bool {
        !tokens.isEmpty && tokens.allSatisfy { $0.count >= 3 }
    }

    /// Quotes each token as a phrase so user input is never interpreted as FTS syntax.
    public static func match(_ tokens: [String]) -> String {
        tokens.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " AND ")
    }

    public static func likePattern(_ token: String) -> String {
        "%" + token.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
    }
}

public final class LocalStore: Sendable {
    public let db: Database
    public let root: URL

    public var attachmentsDirectory: URL { root.appendingPathComponent("Attachments", isDirectory: true) }
    public var clipboardDirectory: URL { root.appendingPathComponent("Clipboard", isDirectory: true) }
    public var outputDirectory: URL { root.appendingPathComponent("Output", isDirectory: true) }

    public init(root: URL) throws {
        self.root = root
        db = try Database(path: root.appendingPathComponent("kulahere.sqlite").path)
        try Schema.migrate(db)
        for d in [attachmentsDirectory, clipboardDirectory, outputDirectory] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }

    /// In-memory store for tests.
    public init(inMemoryWithRoot root: URL) throws {
        self.root = root
        db = try Database(path: ":memory:")
        try Schema.migrate(db)
    }

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KulaHere", isDirectory: true)
    }

    // MARK: settings

    public func setting(_ key: String) -> String? {
        try? db.query("SELECT value FROM settings WHERE key = ?", [key]).first?.string("value")
    }

    public func setSetting(_ key: String, _ value: String?) {
        if let value {
            _ = try? db.run("INSERT INTO settings(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [key, value])
        } else {
            _ = try? db.run("DELETE FROM settings WHERE key = ?", [key])
        }
    }

    public func codableSetting<T: Decodable>(_ key: String, as: T.Type) -> T? {
        setting(key).flatMap { try? JSONDecoder().decode(T.self, from: Data($0.utf8)) }
    }

    public func setCodableSetting<T: Encodable>(_ key: String, _ value: T) {
        if let d = try? JSONEncoder().encode(value) { setSetting(key, String(decoding: d, as: UTF8.self)) }
    }
}

public enum JSONText {
    public static func encode<T: Encodable>(_ v: T) -> String {
        (try? JSONEncoder().encode(v)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }
    public static func decode<T: Decodable>(_ s: String?, as: T.Type) -> T? {
        guard let s else { return nil }
        return try? JSONDecoder().decode(T.self, from: Data(s.utf8))
    }
}
