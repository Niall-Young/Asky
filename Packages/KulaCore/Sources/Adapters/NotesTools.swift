import Foundation
import Contracts
import ToolService

/// An authorized Notes location ("account / folder"). Only these are searched, read or written.
public struct NotesFolder: Sendable, Hashable, Codable {
    public var account: String
    public var folder: String
    public var folderID: String?
    public init(account: String, folder: String, folderID: String? = nil) {
        self.account = account
        self.folder = folder
        self.folderID = folderID
    }
    var label: String { "\(account) › \(folder)" }
    var scriptRef: String {
        if let folderID { return "folder id \(AppleScript.literal(folderID))" }
        return "folder \(AppleScript.literal(folder)) of account \(AppleScript.literal(account))"
    }
    public func matchesLocation(_ other: Self) -> Bool {
        if let folderID, let otherID = other.folderID { return folderID == otherID }
        return account == other.account && folder == other.folder
    }
}

/// Notes via Apple Events. No locked notes, attachment editing or deletion.
public struct NotesBridge: Sendable {
    let runner: AppleScriptRunner
    let allowed: @Sendable () -> [NotesFolder]
    public init(runner: AppleScriptRunner = .shared, allowed: @escaping @Sendable () -> [NotesFolder]) {
        self.runner = runner
        self.allowed = allowed
    }

    /// Configuration discovery reads folder metadata only, before any content scope is selected.
    public func availableFolders() async throws -> [NotesFolder] {
        let source = """
        \(AppleScript.joinHandler)
        on collectFolders(parentObject, accountName, parentPath)
          set rows to {}
          tell application "Notes"
            repeat with f in folders of parentObject
              set folderName to name of f as text
              if parentPath is "" then
                set folderPath to folderName
              else
                set folderPath to parentPath & " / " & folderName
              end if
              set end of rows to my kjoin({accountName, folderPath, id of f as text}, \(AppleScript.us))
              set rows to rows & my collectFolders(f, accountName, folderPath)
            end repeat
          end tell
          return rows
        end collectFolders
        tell application "Notes"
          set rows to {}
          repeat with a in accounts
            set rows to rows & my collectFolders(a, name of a as text, "")
          end repeat
        end tell
        return my kjoin(rows, \(AppleScript.rs))
        """
        return AppleScript.parseRecords(try await runner.run(source), fields: 3)
            .map { NotesFolder(account: $0[0], folder: $0[1], folderID: $0[2]) }
            .sorted { ($0.account, $0.folder) < ($1.account, $1.folder) }
    }

    func folders() throws -> [NotesFolder] {
        let f = allowed()
        guard !f.isEmpty else { throw ToolError(.permissionDenied, CoreLocalization.text("尚未在设置中选择允许访问的 Notes 文件夹")) }
        return f
    }

    func folder(named label: String?) throws -> NotesFolder {
        let all = try folders()
        guard let label else {
            if all.count == 1 { return all[0] }
            throw ToolError(.ambiguousTarget, CoreLocalization.text("请选择文件夹：") + all.map(\.label).joined(separator: "、"))
        }
        let m = all.filter { $0.label == label || $0.folder == label }
        if m.count > 1 { throw ToolError(.ambiguousTarget, CoreLocalization.format("有多个名为「%@」的文件夹：", String(describing: label)) + m.map(\.label).joined(separator: "、")) }
        guard let f = m.first else { throw ToolError(.permissionDenied, CoreLocalization.format("文件夹「%@」未授权", String(describing: label))) }
        return f
    }

    public struct Note: Sendable, Hashable {
        public var id: String, name: String, folder: String
    }

    public func search(_ query: String, limit: Int) async throws -> [Note] {
        var out: [Note] = []
        for f in try folders() where out.count < limit {
            let src = """
            \(AppleScript.joinHandler)
            tell application "Notes"
              set out to {}
              set q to \(AppleScript.literal(query))
              repeat with n in (notes of \(f.scriptRef) whose name contains q or plaintext contains q)
                if not (password protected of n) then set end of out to my kjoin({id of n, name of n}, \(AppleScript.us))
                if (count of out) ≥ \(limit) then exit repeat
              end repeat
              return my kjoin(out, \(AppleScript.rs))
            end tell
            """
            out += AppleScript.parseRecords(try await runner.run(src), fields: 2).map { Note(id: $0[0], name: $0[1], folder: f.label) }
        }
        return Array(out.prefix(limit))
    }

    /// Locates a note inside the authorized folders only; returns the folder it lives in.
    func locate(_ id: String) async throws -> NotesFolder {
        for f in try folders() {
            let src = """
            tell application "Notes"
              set c to count of (notes of \(f.scriptRef) whose id is \(AppleScript.literal(id)))
              return c as text
            end tell
            """
            if (try await runner.run(src)) != "0" { return f }
        }
        throw ToolError(.targetNotFound, CoreLocalization.text("在已授权文件夹中找不到该备忘录"))
    }

    public func read(_ id: String) async throws -> (name: String, text: String, folder: NotesFolder) {
        let f = try await locate(id)
        let src = """
        \(AppleScript.joinHandler)
        tell application "Notes"
          set n to note id \(AppleScript.literal(id))
          if password protected of n then error \(AppleScript.literal(CoreLocalization.text("锁定的备忘录不可访问"))) number -1728
          return my kjoin({name of n, plaintext of n}, \(AppleScript.us))
        end tell
        """
        guard let r = AppleScript.parseRecords(try await runner.run(src), fields: 2).first else {
            throw ToolError(.targetNotFound, CoreLocalization.text("找不到该备忘录"))
        }
        return (r[0], r[1], f)
    }

    public func create(title: String, body: String, in f: NotesFolder) async throws -> String {
        let html = "<div><h1>\(Self.html(title))</h1></div>" + Self.htmlParagraphs(body)
        let src = """
        tell application "Notes"
          set n to make new note at \(f.scriptRef) with properties {body:\(AppleScript.literal(html))}
          return id of n
        end tell
        """
        return try await runner.run(src)
    }

    public func append(_ id: String, text: String) async throws {
        _ = try await locate(id)
        let src = """
        tell application "Notes"
          set n to note id \(AppleScript.literal(id))
          if password protected of n then error \(AppleScript.literal(CoreLocalization.text("锁定的备忘录不可修改"))) number -1728
          set body of n to (body of n) & \(AppleScript.literal(Self.htmlParagraphs(text)))
          return "ok"
        end tell
        """
        _ = try await runner.run(src)
    }

    static func html(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func htmlParagraphs(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "<div><br></div>" : "<div>\(html(String($0)))</div>" }.joined()
    }
}

public struct NotesSearchTool: ToolAdapter {
    let notes: NotesBridge
    public init(_ notes: NotesBridge) { self.notes = notes }
    public var definition: ToolDefinition {
        ToolDefinition(name: "notes_search", summary: CoreLocalization.text("在已授权的 Notes 文件夹中按标题或正文搜索"),
                       inputSchema: Args.schema(["query": Args.stringProp, "limit": Args.intProp], required: ["query"]),
                       source: .notes, effect: .read, confirmation: .never, externallyExposable: true)
    }
    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        let r = try await notes.search(try Args.requiredString(a, "query"), limit: Args.int(a["limit"], default: 20, max: 50))
        return AdapterOutput(output: .array(r.map { ["id": .string($0.id), "name": .string($0.name), "folder": .string($0.folder)] }),
                             targets: r.map { TargetRef(kind: "note", identifier: $0.id) })
    }
}

public struct NotesReadTool: ToolAdapter {
    let notes: NotesBridge
    public init(_ notes: NotesBridge) { self.notes = notes }
    public var definition: ToolDefinition {
        ToolDefinition(name: "notes_read", summary: CoreLocalization.text("读取一条备忘录的纯文本"),
                       inputSchema: Args.schema(["id": Args.stringProp], required: ["id"]),
                       source: .notes, effect: .read, confirmation: .never, externallyExposable: true)
    }
    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        let id = try Args.requiredString(a, "id")
        let n = try await notes.read(id)
        return AdapterOutput(output: ["id": .string(id), "name": .string(n.name), "folder": .string(n.folder.label),
                                      "text": .string(String(n.text.prefix(32 * 1024)))],
                             targets: [TargetRef(kind: "note", identifier: id)])
    }
}

public struct NotesCreateTool: ToolAdapter {
    let notes: NotesBridge
    public init(_ notes: NotesBridge) { self.notes = notes }
    public var definition: ToolDefinition {
        ToolDefinition(name: "notes_create", summary: CoreLocalization.text("在已授权文件夹中新建备忘录"),
                       inputSchema: Args.schema(["title": Args.stringProp, "body": Args.stringProp,
                                                 "folder": ["type": "string", "description": .string(CoreLocalization.text("「账户 › 文件夹」或文件夹名"))]],
                                                required: ["title"]),
                       source: .notes, effect: .write, writeKind: .create, confirmation: .createDirectOtherwiseConfirm,
                       externallyExposable: true)
    }
    public func preview(_ a: JSONValue) async throws -> ConfirmationPreview {
        let f = try notes.folder(named: try Args.string(a["folder"], "folder", required: false))
        let body = a["body"]?.stringValue ?? ""
        return ConfirmationPreview(target: "Notes「\(f.label)」",
                                   changes: ["新建「\(try Args.requiredString(a, "title"))」"] + (body.isEmpty ? [] : [String(body.prefix(200))]))
    }
    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        let f = try notes.folder(named: try Args.string(a["folder"], "folder", required: false))
        let id = try await notes.create(title: try Args.requiredString(a, "title"), body: a["body"]?.stringValue ?? "", in: f)
        return AdapterOutput(output: ["id": .string(id), "folder": .string(f.label)], targets: [TargetRef(kind: "note", identifier: id)])
    }
    public func readback(_ a: JSONValue, output: AdapterOutput?) async -> JSONValue? {
        if let id = output?.targets.first?.identifier, let n = try? await notes.read(id) {
            return ["id": .string(id), "name": .string(n.name)]
        }
        // Unknown outcome: look for a note with the exact title instead of creating again.
        guard let title = a["title"]?.stringValue, let hits = try? await notes.search(title, limit: 5),
              let hit = hits.first(where: { $0.name == title }) else { return nil }
        return ["id": .string(hit.id), "name": .string(hit.name)]
    }
}

public struct NotesAppendTool: ToolAdapter {
    let notes: NotesBridge
    public init(_ notes: NotesBridge) { self.notes = notes }
    public var definition: ToolDefinition {
        ToolDefinition(name: "notes_append", summary: CoreLocalization.text("向已有备忘录末尾追加文本（明确请求直接执行）"),
                       inputSchema: Args.schema(["id": Args.stringProp, "text": Args.stringProp], required: ["id", "text"]),
                       source: .notes, effect: .write, writeKind: .modify, confirmation: .explicitDirectOtherwiseConfirm, externallyExposable: true)
    }
    public func preview(_ a: JSONValue) async throws -> ConfirmationPreview {
        let n = try await notes.read(try Args.requiredString(a, "id"))
        return ConfirmationPreview(target: "备忘录「\(n.name)」（\(n.folder.label)）",
                                   changes: ["追加：" + String(try Args.requiredString(a, "text").prefix(300))])
    }
    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        let id = try Args.requiredString(a, "id")
        try await notes.append(id, text: try Args.requiredString(a, "text"))
        return AdapterOutput(output: ["id": .string(id)], targets: [TargetRef(kind: "note", identifier: id)])
    }
    public func readback(_ a: JSONValue, output: AdapterOutput?) async -> JSONValue? {
        guard let id = a["id"]?.stringValue, let text = a["text"]?.stringValue,
              let n = try? await notes.read(id) else { return nil }
        // Notes may normalise whitespace; check the last line of the appended text.
        let probe = text.split(separator: "\n").last.map(String.init) ?? text
        return n.text.contains(probe) ? ["id": .string(id), "verified": true] : nil
    }
}

/// Only the native settings UI may discover locations outside the content allowlist.
public struct NotesListFoldersTool: ToolAdapter {
    let notes: NotesBridge
    public init(_ notes: NotesBridge) { self.notes = notes }
    public var definition: ToolDefinition {
        ToolDefinition(name: "notes_list_folders", summary: CoreLocalization.text("列出备忘录账户和文件夹以配置访问范围"),
                       inputSchema: Args.schema([:], required: []), source: .notes, effect: .read,
                       confirmation: .never, externallyExposable: false, agentExposable: false)
    }
    public func execute(_ arguments: JSONValue) async throws -> AdapterOutput {
        let folders = try await notes.availableFolders()
        return AdapterOutput(output: .array(folders.map {
            .object(["account": .string($0.account), "folder": .string($0.folder),
                     "folderID": .string($0.folderID ?? "")])
        }))
    }
}
