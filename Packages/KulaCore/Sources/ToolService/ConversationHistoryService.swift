import Foundation
import Contracts
import LocalStore

public enum ConversationRetention: Int, Codable, CaseIterable, Sendable {
    case sevenDays = 7, thirtyDays = 30, ninetyDays = 90, forever = 0
    public var interval: TimeInterval? { self == .forever ? nil : Double(rawValue) * 86400 }
}

/// Owns history deletion and its filesystem work. Long-term memory is deliberately outside this service.
public actor ConversationHistoryService {
    public struct CleanupResult: Sendable {
        public var deletedIDs: Set<String>
        public var pendingFiles: Int
    }

    private let store: LocalStore
    private let files = FileManager.default
    public init(store: LocalStore) { self.store = store }

    public func cleanup(retention: ConversationRetention, protecting active: Set<String> = [],
                        draftPaths: Set<String> = [], now: Date = Date()) throws -> CleanupResult {
        var deleted = Set<String>()
        if let interval = retention.interval {
            // A keyset cursor keeps both the scan and each transaction bounded, including protected sessions.
            var cursor = ""
            while true {
                let rows = try store.db.query("SELECT id FROM conversations WHERE updated_at <= ? AND id > ? ORDER BY id LIMIT 100",
                                              [now.addingTimeInterval(-interval), cursor])
                guard !rows.isEmpty else { break }
                for row in rows {
                    guard let id = row.string("id") else { continue }
                    cursor = id
                    if !active.contains(id) { try removeRecord(id); deleted.insert(id) }
                }
            }
        }
        deleted.formUnion(try removeOrphanRecords(protecting: active, now: now))
        try queueOrphans(protecting: active, draftPaths: draftPaths, now: now)
        let pending = try drainFiles(draftPaths: draftPaths)
        return CleanupResult(deletedIDs: deleted, pendingFiles: pending)
    }

    public func delete(_ id: String, protecting active: Set<String> = [], draftPaths: Set<String> = []) throws -> CleanupResult {
        guard !active.contains(id) else { return CleanupResult(deletedIDs: [], pendingFiles: 0) }
        try removeRecord(id)
        return CleanupResult(deletedIDs: [id], pendingFiles: try drainFiles(draftPaths: draftPaths))
    }

    private func queue(_ path: String, kind: String) throws {
        // Do not store or remove external originals, memory files, or paths through a symlinked parent.
        guard let url = ownedURL(path, kind: kind) else { return }
        try store.db.run("INSERT OR IGNORE INTO conversation_file_cleanup(path, kind) VALUES(?, ?)", [url.path, kind])
    }

    private func removeRecord(_ id: String) throws {
        try store.db.transaction {
            let legacy = try store.db.query("SELECT runtime_session_ref FROM conversations WHERE id = ?", [id]).first?.string("runtime_session_ref")
            if id.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil {
                try queue(store.root.appending(path: "runtime/native-sessions/\(id).json").path, kind: "runtime")
            }
            if let legacy { try queue(legacy, kind: "runtime") }
            let paths = try store.db.query("""
                SELECT DISTINCT json_extract(j.value, '$.path') AS path FROM messages m,
                    json_each(m.attachments_json) j WHERE m.conversation_id = ?
                UNION SELECT path FROM attachments WHERE conversation_id = ?
                """, [id, id])
            for row in paths { if let path = row.string("path") { try queue(path, kind: "attachment") } }
            try store.db.run("DELETE FROM executions WHERE origin = ?", ["agent:\(id)"])
            let source = "conversation:\(id)"
            try store.db.run("DELETE FROM extraction_queue WHERE source_id = ?", [source])
            try store.db.run("DELETE FROM activity WHERE source_id = ?", [source])
            try store.db.run("DELETE FROM sources WHERE id = ?", [source])
            try store.db.run("DELETE FROM settings WHERE key = ?", ["memory.extracted.\(source)"])
            try store.db.run("DELETE FROM messages_fts WHERE conversation_id = ?", [id])
            try store.db.run("DELETE FROM conversations WHERE id = ?", [id])
        }
    }

    private func ownedURL(_ path: String, kind: String) -> URL? {
        let root = store.root.resolvingSymlinksInPath().standardizedFileURL
        let original = URL(filePath: path).standardizedFileURL
        // Resolve parents, but unlink a final symlink itself instead of its target.
        let url = original.deletingLastPathComponent().resolvingSymlinksInPath().appending(path: original.lastPathComponent)
        let relativeRoots = kind == "attachment" ? ["Attachments"] : ["runtime/native-sessions", "runtime/pi/sessions"]
        for relative in relativeRoots {
            let allowed = root.appending(path: relative).standardizedFileURL
            guard allowed.resolvingSymlinksInPath().path == allowed.path,
                  url.path.hasPrefix(allowed.path + "/") else { continue }
            return url
        }
        return nil
    }

    private func aliases(_ path: String) -> [String] {
        let roots = [store.root.path, store.root.resolvingSymlinksInPath().path]
        for root in roots where path.hasPrefix(root + "/") {
            let suffix = String(path.dropFirst(root.count))
            return [path, roots[0] + suffix, roots[1] + suffix]
        }
        return [path, path, path]
    }

    private func isDraft(_ path: String, drafts: Set<String>) -> Bool {
        let canonical = URL(filePath: path).resolvingSymlinksInPath().path
        return drafts.contains { URL(filePath: $0).resolvingSymlinksInPath().path == canonical }
    }

    private func isReferenced(_ path: String, kind: String) throws -> Bool {
        let names = aliases(path)
        if kind == "attachment" {
            return try store.db.scalarInt("""
                SELECT EXISTS(SELECT 1 FROM messages m, json_each(m.attachments_json) j
                    WHERE json_extract(j.value, '$.path') IN (?, ?, ?))
                    OR EXISTS(SELECT 1 FROM attachments WHERE path IN (?, ?, ?))
                """, names + names) != 0
        }
        let id = URL(filePath: path).deletingPathExtension().lastPathComponent
        return try store.db.scalarInt("SELECT EXISTS(SELECT 1 FROM conversations WHERE runtime_session_ref IN (?, ?, ?) OR id = ?)", names + [id]) != 0
    }

    private func drainFiles(draftPaths: Set<String>) throws -> Int {
        var cursor = ""
        while true {
            let rows = try store.db.query("SELECT path, kind FROM conversation_file_cleanup WHERE path > ? ORDER BY path LIMIT 100", [cursor])
            guard !rows.isEmpty else { break }
            for row in rows {
                guard let path = row.string("path"), let kind = row.string("kind") else { continue }
                cursor = path
                if isDraft(path, drafts: draftPaths) { continue }
                if try isReferenced(path, kind: kind) {
                    try store.db.run("DELETE FROM conversation_file_cleanup WHERE path = ?", [path])
                    continue
                }
                guard let url = ownedURL(path, kind: kind) else { continue }
                do {
                    if files.fileExists(atPath: path) || (try? files.destinationOfSymbolicLink(atPath: path)) != nil {
                        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                        guard values.isDirectory != true || values.isSymbolicLink == true else { continue }
                        try files.removeItem(at: url)
                        if kind == "attachment" { removeEmptyParents(url.deletingLastPathComponent()) }
                    }
                    try store.db.run("DELETE FROM conversation_file_cleanup WHERE path = ?", [path])
                } catch {
                    // The durable row survives restarts and is retried on the next maintenance pass.
                    continue
                }
            }
        }
        return try store.db.scalarInt("SELECT COUNT(*) FROM conversation_file_cleanup")
    }

    private func removeEmptyParents(_ start: URL) {
        let root = store.attachmentsDirectory.resolvingSymlinksInPath()
        var parent = start
        while parent.path.hasPrefix(root.path + "/"),
              (try? files.contentsOfDirectory(atPath: parent.path).isEmpty) == true {
            do { try files.removeItem(at: parent) } catch { break }
            parent.deleteLastPathComponent()
        }
    }

    private func removeOrphanRecords(protecting active: Set<String>, now: Date) throws -> Set<String> {
        var removed = Set<String>(), cursor = ""
        while true {
            let rows = try store.db.query("""
                SELECT id FROM (
                    SELECT substr(e.origin, 7) AS id FROM executions e
                    WHERE e.origin LIKE 'agent:%' AND e.updated_at <= ?
                      AND NOT EXISTS(SELECT 1 FROM conversations c WHERE c.id = substr(e.origin, 7))
                    UNION
                    SELECT substr(s.id, 14) AS id FROM sources s
                    WHERE s.kind = 'conversation' AND s.id LIKE 'conversation:%' AND s.created_at <= ?
                      AND NOT EXISTS(SELECT 1 FROM conversations c WHERE c.id = substr(s.id, 14))
                ) WHERE id > ? ORDER BY id LIMIT 100
                """, [now.addingTimeInterval(-86400), now.addingTimeInterval(-86400), cursor])
            guard !rows.isEmpty else { break }
            for row in rows {
                guard let id = row.string("id") else { continue }
                cursor = id
                if !active.contains(id) { try removeRecord(id); removed.insert(id) }
            }
        }
        return removed
    }

    /// Reclaims leftovers from older versions; a one-day grace period also protects fresh unattached imports.
    private func queueOrphans(protecting active: Set<String>, draftPaths: Set<String>, now: Date) throws {
        for (relative, kind) in [("Attachments", "attachment"), ("runtime/native-sessions", "runtime"), ("runtime/pi/sessions", "runtime")] {
            let directory = store.root.resolvingSymlinksInPath().appending(path: relative).standardizedFileURL
            guard directory.resolvingSymlinksInPath().path == store.root.resolvingSymlinksInPath().appending(path: relative).path,
                  let enumerator = files.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]) else { continue }
                if values.isSymbolicLink == true { enumerator.skipDescendants() }
                guard values.isDirectory != true, !isDraft(url.path, drafts: draftPaths),
                      let modified = values.contentModificationDate, modified <= now.addingTimeInterval(-86400),
                      !active.contains(url.deletingPathExtension().lastPathComponent),
                      try !isReferenced(url.path, kind: kind) else { continue }
                try queue(url.path, kind: kind)
            }
        }
    }
}
