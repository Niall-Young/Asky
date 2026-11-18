import Foundation
import Contracts
import LocalStore

/// Long-term memory is a folder of Markdown files maintained by Asky, laid out like Codex's memory summary:
/// `MEMORY.md` is a short index (who the user is, preferences, and one line per topic file) given to every
/// conversation; topic files hold details and are read on demand. Extraction and the memory tools change files by
/// appending a line or replacing / removing exact text; `MemoryConsolidator` periodically rewrites the whole folder.
public struct MarkdownMemoryFolder: Sendable {
    public static let directoryName = "Memory"
    public static let indexName = "MEMORY.md"
    public static let sections = ["关于我", "偏好"]
    public static let topicsSection = "主题文件"
    /// Upper bound on the index handed to every conversation; topic files are not included.
    public static let maxIndexCharacters = 6000
    /// Upper bound on one topic file returned by `memory_read`.
    public static let maxTopicCharacters = 12000

    public let root: URL
    private static let lock = NSLock()

    public init(root: URL) { self.root = root }
    public init(_ store: LocalStore) { root = store.root.appendingPathComponent(Self.directoryName, isDirectory: true) }

    public var indexURL: URL { root.appendingPathComponent(Self.indexName) }

    public static let template = """
        # Asky 记忆

        这是记忆索引，由 Asky 自动维护，每次对话都会读取。只记以后对话仍然有用的长期信息，保持简短；
        某个主题的细节放在同目录的主题文件里，并在「\(topicsSection)」下用一行说明它记了什么。

        \((sections + [topicsSection]).map { "## \($0)\n" }.joined(separator: "\n"))
        """

    public enum EditError: Error, Equatable {
        case notFound
        case ambiguous
        case empty
        case invalidFileName
    }

    /// Normalises a file argument: nil or `MEMORY.md` means the index; topic files are plain `name.md` in the folder.
    public static func fileName(_ raw: String?) throws -> String {
        guard var name = raw?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return indexName }
        if !name.lowercased().hasSuffix(".md") { name += ".md" }
        if name.caseInsensitiveCompare(indexName) == .orderedSame { return indexName }
        name = name.lowercased()
        let stem = name.dropLast(3)
        guard !stem.isEmpty, stem.count <= 60, !stem.hasPrefix("."),
              stem.unicodeScalars.allSatisfy({ ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || "-_".unicodeScalars.contains($0) })
        else { throw EditError.invalidFileName }
        return name
    }

    /// Content of a memory file; empty when it does not exist.
    public func read(_ file: String? = nil) -> String {
        let name: String
        if let file, file.utf8.count <= 255, !file.contains("/"), file.hasSuffix(".md"),
           !file.hasPrefix("."), FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path) {
            name = file  // Retain access to files created under the former naming rules.
        } else {
            guard let canonical = try? Self.fileName(file) else { return "" }
            name = canonical
        }
        return (try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)) ?? ""
    }

    /// Topic files in the folder, newest first.
    public func topicFiles() -> [String] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys)) ?? []
        return urls.filter { $0.pathExtension == "md" && $0.lastPathComponent != Self.indexName }
            .map { ($0.lastPathComponent, (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Creates the folder and index from the template when missing, so the user has something to open.
    public func ensureExists() throws {
        try Self.lock.withLock {
            guard !FileManager.default.fileExists(atPath: indexURL.path) else { return }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Self.template.write(to: indexURL, atomically: true, encoding: .utf8)
        }
    }

    /// The index as model context, or nil when it holds nothing beyond the template.
    public func context() -> String? {
        let text = read()
        let hasBody = text.split(separator: "\n").contains { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !t.isEmpty && !t.hasPrefix("#") && !Self.template.contains(t)
        }
        guard hasBody || !topicFiles().isEmpty else { return nil }
        guard text.count > Self.maxIndexCharacters else { return text }
        return String(text.prefix(Self.maxIndexCharacters)) + CoreLocalization.text("\n（记忆索引过长，后面的内容已省略）")
    }

    /// Appends `- content` to a file. In the index it goes under `section`; a new topic file starts with a title and
    /// gets an index line carrying `description`. Text already in the file is not repeated.
    @discardableResult
    public func add(_ content: String, section: String? = nil, file: String? = nil, description: String? = nil) throws -> Bool {
        let line = Self.oneLine(content)
        guard !line.isEmpty else { throw EditError.empty }
        let name = try Self.fileName(file)
        try ensureExists()
        return try Self.lock.withLock {
            if name == Self.indexName {
                let heading = section.flatMap { Self.sections.contains($0) ? $0 : nil } ?? Self.sections[0]
                return try update(Self.indexName) { Self.append("- " + line, under: heading, in: &$0) }
            }
            let added = try update(name) { text in
                guard !text.contains(line) else { return false }
                if text.isEmpty { text = "# \(name.dropLast(3))\n\n" }
                if !text.hasSuffix("\n") { text += "\n" }
                text += "- \(line)\n"
                return true
            }
            let summary = Self.oneLine(description ?? "")
            try update(Self.indexName) { index in
                guard !index.contains("(\(name))") else { return false }
                let entry = "- [\(name)](\(name))" + (summary.isEmpty ? "" : " — \(summary)")
                return Self.append(entry, under: Self.topicsSection, in: &index)
            }
            return added
        }
    }

    /// Replaces exact text that occurs once in a file.
    public func replace(_ old: String, with new: String, file: String? = nil) throws {
        let replacement = Self.oneLine(new)
        guard !replacement.isEmpty else { throw EditError.empty }
        let name = try Self.fileName(file)
        try Self.lock.withLock {
            try update(name) { text in
                text.replaceSubrange(try Self.uniqueRange(of: old, in: text), with: replacement)
                return true
            }
        }
    }

    /// Removes the line containing exact text that occurs once in a file.
    public func remove(_ old: String, file: String? = nil) throws {
        let name = try Self.fileName(file)
        try Self.lock.withLock {
            try update(name) { text in
                text.removeSubrange(text.lineRange(for: try Self.uniqueRange(of: old, in: text)))
                return true
            }
        }
    }

    /// Writes a complete new version of the folder: the given files replace their old content and topic files not
    /// given are deleted. Used by consolidation.
    public func replaceAll(_ files: [String: String], ifMatching previous: [String: String]? = nil) throws {
        try Self.lock.withLock {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if let previous {
                let names = [Self.indexName] + topicFiles()
                guard Set(names) == Set(previous.keys), names.allSatisfy({ read($0) == previous[$0] }) else {
                    throw EditError.ambiguous
                }
                let backup = root.appendingPathComponent(".previous", isDirectory: true)
                if FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.removeItem(at: backup) }
                try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                for (name, text) in previous where !text.isEmpty {
                    try text.write(to: backup.appendingPathComponent(name), atomically: true, encoding: .utf8)
                }
            }
            for name in topicFiles() where files[name] == nil {
                try FileManager.default.removeItem(at: root.appendingPathComponent(name))
            }
            for (name, text) in files {
                try text.write(to: root.appendingPathComponent(try Self.fileName(name)), atomically: true, encoding: .utf8)
            }
        }
    }

    @discardableResult
    private func update(_ name: String, _ change: (inout String) throws -> Bool) throws -> Bool {
        var text = read(name)
        guard try change(&text) else { return false }
        try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        return true
    }

    /// Inserts `line` at the end of `## heading` (created at the end when missing) unless it is already present.
    static func append(_ line: String, under heading: String, in text: inout String) -> Bool {
        guard !text.contains(line) else { return false }
        var lines = text.components(separatedBy: "\n")
        if let h = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## " + heading }) {
            var end = lines[(h + 1)...].firstIndex { $0.hasPrefix("#") } ?? lines.endIndex
            while end > h + 1, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
            lines.insert(line, at: end)
        } else {
            while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
            lines += ["", "## " + heading, line]
        }
        text = lines.joined(separator: "\n")
        if !text.hasSuffix("\n") { text += "\n" }
        return true
    }

    public static func uniqueRange(of old: String, in text: String) throws -> Range<String.Index> {
        let needle = old.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, let first = text.range(of: needle) else { throw EditError.notFound }
        guard text.range(of: needle, range: first.upperBound..<text.endIndex) == nil else { throw EditError.ambiguous }
        return first
    }

    public static func oneLine(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("- ") { t.removeFirst(2) }
        return t
    }

    /// One-time export of memories confirmed or pinned in the old database store, so switching to files keeps what
    /// the user had already approved. Projects go to `projects.md`. Does nothing once the index exists.
    public func migrateLegacy(_ store: LocalStore) {
        guard !FileManager.default.fileExists(atPath: indexURL.path) else { return }
        try? ensureExists()
        let rows = (try? store.db.query("""
            SELECT content, kind FROM memories WHERE status = 'active' AND (confirmed = 1 OR pinned = 1)
              AND (permissions & 2) = 2 ORDER BY created_at
            """)) ?? []
        for r in rows {
            guard let content = r.string("content") else { continue }
            switch r.string("kind") {
            case "preference": _ = try? add(content, section: Self.sections[1])
            case "episode": _ = try? add(content, file: "projects.md", description: "长期项目与目标")
            default: _ = try? add(content, section: Self.sections[0])
            }
        }
    }
}
