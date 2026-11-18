import Foundation
import MapKit
import Contracts
import ToolService
import Memory

private func memoryError(_ e: Error) -> Error {
    switch e as? MemoryFolder.EditError {
    case .notFound?: ToolError(.targetNotFound, CoreLocalization.text("该记忆文件里没有这段文字，请按文件中的原文填写"))
    case .ambiguous?: ToolError(.ambiguousTarget, CoreLocalization.text("这段文字在记忆文件里出现了多次，请多带一些上下文"))
    case .empty?: ToolError(.invalidArguments, CoreLocalization.text("内容不能为空"))
    case .invalidFileName?: ToolError(.invalidArguments, CoreLocalization.text("文件名只能是 MEMORY.md 或小写英文短名，如 projects.md"))
    case nil: e
    }
}

private let fileProp: JSONValue = ["type": "string", "description": .string(CoreLocalization.text("记忆文件名；省略或 MEMORY.md 表示索引，主题文件如 projects.md"))]

/// Reads one topic file listed in the memory index. The index itself is already in every conversation's context.
public struct MemoryReadTool: ToolAdapter {
    let memory: MemoryFolder
    public init(_ memory: MemoryFolder) { self.memory = memory }
    public var definition: ToolDefinition {
        ToolDefinition(name: "memory_read", summary: CoreLocalization.text("读取记忆索引中列出的主题文件全文"),
                       inputSchema: Args.schema(["file": fileProp], required: ["file"]),
                       source: .memory, effect: .read, confirmation: .never, externallyExposable: false)
    }
    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        let name: String
        do { name = try MemoryFolder.fileName(a["file"]?.stringValue) } catch { throw memoryError(error) }
        let text = memory.read(name)
        guard !text.isEmpty else {
            throw ToolError(.targetNotFound, CoreLocalization.text("没有这个记忆文件；现有主题文件：") + memory.topicFiles().joined(separator: "、"))
        }
        return AdapterOutput(output: ["file": .string(name), "text": .string(String(text.prefix(MemoryFolder.maxTopicCharacters)))])
    }
}

/// Appends something the user explicitly asked Asky to remember. Inferred saves only become suggestions.
public struct MemorySaveTool: ToolAdapter {
    let memory: MemoryFolder
    public init(_ memory: MemoryFolder) { self.memory = memory }
    public var definition: ToolDefinition {
        ToolDefinition(name: "memory_save", summary: CoreLocalization.text("把用户明确要求记住的信息追加到记忆索引或主题文件"),
                       inputSchema: Args.schema([
                        "content": ["type": "string", "description": .string(CoreLocalization.text("一句完整、可独立理解的陈述，例如「用户的常用机场是浦东」"))],
                        "file": fileProp,
                        "section": ["type": "string", "enum": .array(MemoryFolder.sections.map(JSONValue.string)),
                                    "description": .string(CoreLocalization.format("写入 MEMORY.md 时的分组：%@（稳定事实）或%@", "关于我", "偏好"))],
                        "description": ["type": "string", "description": .string(CoreLocalization.text("新建主题文件时，一句话说明它记什么，会登记到索引"))],
                       ], required: ["content"]),
                       source: .memory, effect: .write, writeKind: .create, confirmation: .createDirectOtherwiseConfirm,
                       externallyExposable: false)
    }
    public func preview(_ a: JSONValue) async throws -> ConfirmationPreview {
        let name: String
        do { name = try MemoryFolder.fileName(a["file"]?.stringValue) } catch { throw memoryError(error) }
        return ConfirmationPreview(target: "记忆 \(name)", changes: ["添加：" + String(try Args.requiredString(a, "content").prefix(300))])
    }
    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        let content = try Args.requiredString(a, "content")
        guard content.count <= 500 else { throw ToolError(.invalidArguments, CoreLocalization.text("记忆内容过长，请精简为一句话")) }
        let name: String
        do {
            name = try MemoryFolder.fileName(a["file"]?.stringValue)
            try memory.add(content, section: a["section"]?.stringValue, file: name, description: a["description"]?.stringValue)
        } catch { throw memoryError(error) }
        return AdapterOutput(output: ["saved": true, "file": .string(name)], targets: [TargetRef(kind: "memory", identifier: name)])
    }
    public func readback(_ a: JSONValue, output: AdapterOutput?) async -> JSONValue? {
        guard let name = output?.targets.first?.identifier, let content = a["content"]?.stringValue,
              memory.read(name).contains(MemoryFolder.oneLine(content)) else { return nil }
        return ["saved": true]
    }
}

/// Replaces text in a memory file after a user correction.
/// The files are user-editable, so an explicit user request runs without an extra prompt.
public struct MemoryCorrectTool: ToolAdapter {
    let memory: MemoryFolder
    public init(_ memory: MemoryFolder) { self.memory = memory }
    public var definition: ToolDefinition {
        ToolDefinition(name: "memory_correct", summary: CoreLocalization.text("按用户的纠正修改记忆文件中的一段文字"),
                       inputSchema: Args.schema(["file": fileProp,
                                                 "old": ["type": "string", "description": .string(CoreLocalization.text("该文件中原样出现的旧文字"))],
                                                 "content": ["type": "string", "description": .string(CoreLocalization.text("替换后的完整陈述"))]],
                                                required: ["old", "content"]),
                       source: .memory, effect: .write, writeKind: .modify, confirmation: .explicitDirectOtherwiseConfirm,
                       externallyExposable: false)
    }
    public func preview(_ a: JSONValue) async throws -> ConfirmationPreview {
        let old = try Args.requiredString(a, "old")
        do { _ = try MemoryFolder.uniqueRange(of: old, in: memory.read(try MemoryFolder.fileName(a["file"]?.stringValue))) }
        catch { throw memoryError(error) }
        return ConfirmationPreview(target: "记忆「\(old.prefix(80))」",
                                   changes: ["改为：" + String(try Args.requiredString(a, "content").prefix(300))])
    }
    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        let name: String
        do {
            name = try MemoryFolder.fileName(a["file"]?.stringValue)
            try memory.replace(try Args.requiredString(a, "old"), with: try Args.requiredString(a, "content"), file: name)
        } catch { throw memoryError(error) }
        return AdapterOutput(output: ["corrected": true], targets: [TargetRef(kind: "memory", identifier: name)])
    }
    public func readback(_ a: JSONValue, output: AdapterOutput?) async -> JSONValue? {
        guard let name = output?.targets.first?.identifier, let content = a["content"]?.stringValue,
              memory.read(name).contains(MemoryFolder.oneLine(content)) else { return nil }
        return ["corrected": true]
    }
}

/// Removes the line the user asked Asky to forget from a memory file.
public struct MemoryForgetTool: ToolAdapter {
    let memory: MemoryFolder
    public init(_ memory: MemoryFolder) { self.memory = memory }
    public var definition: ToolDefinition {
        ToolDefinition(name: "memory_forget", summary: CoreLocalization.text("从记忆文件删除用户要求忘记的那一行"),
                       inputSchema: Args.schema(["file": fileProp,
                                                 "old": ["type": "string", "description": .string(CoreLocalization.text("该文件中原样出现的文字"))]],
                                                required: ["old"]),
                       source: .memory, effect: .write, writeKind: .delete, confirmation: .explicitDirectOtherwiseConfirm,
                       externallyExposable: false)
    }
    public func preview(_ a: JSONValue) async throws -> ConfirmationPreview {
        let old = try Args.requiredString(a, "old")
        do { _ = try MemoryFolder.uniqueRange(of: old, in: memory.read(try MemoryFolder.fileName(a["file"]?.stringValue))) }
        catch { throw memoryError(error) }
        return ConfirmationPreview(target: "记忆「\(old.prefix(80))」", changes: ["删除这一行"])
    }
    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        let name: String
        do {
            name = try MemoryFolder.fileName(a["file"]?.stringValue)
            try memory.remove(try Args.requiredString(a, "old"), file: name)
        } catch { throw memoryError(error) }
        return AdapterOutput(output: ["deleted": true], targets: [TargetRef(kind: "memory", identifier: name)])
    }
    public func readback(_ a: JSONValue, output: AdapterOutput?) async -> JSONValue? {
        guard let name = output?.targets.first?.identifier, let old = a["old"]?.stringValue,
              !memory.read(name).contains(old.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return ["deleted": true]
    }
}

/// Route ETA via MapKit. Returns nil when the location or route cannot be resolved — callers must not invent a time.
public enum RouteETA {
    public static func eta(to address: String, transport: MKDirectionsTransportType = .automobile,
                           arrival: Date? = nil) async -> TimeInterval? {
        let dest: MKMapItem
        if #available(macOS 26, *) {
            guard let req = MKGeocodingRequest(addressString: address),
                  let item = try? await req.mapItems.first else { return nil }
            dest = item
        } else {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = address
            guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
            dest = item
        }
        let r = MKDirections.Request()
        r.source = MKMapItem.forCurrentLocation()
        r.destination = dest
        r.transportType = transport
        if let arrival { r.arrivalDate = arrival }
        return try? await MKDirections(request: r).calculateETA().expectedTravelTime
    }
}

/// All native tool adapters, wired once by the App.
public struct NativeTools: Sendable {
    public let eventKit = EventKitBridge()
    public let contacts = ContactsBridge()
    public let chrome = ChromeBridge()
    public let notes: NotesBridge
    private let messagesEnabled: @Sendable () -> Bool
    private let contactsEnabled: @Sendable () -> Bool
    private let messagesDays: @Sendable () -> Int

    public init(notesFolders: @escaping @Sendable () -> [NotesFolder],
                messagesEnabled: @escaping @Sendable () -> Bool = { false },
                messagesDays: @escaping @Sendable () -> Int = { 3 },
                contactsEnabled: @escaping @Sendable () -> Bool = { false }) {
        self.messagesEnabled = messagesEnabled
        self.messagesDays = messagesDays
        self.contactsEnabled = contactsEnabled
        notes = NotesBridge(allowed: notesFolders)
    }

    public func adapters(memory: MemoryFolder?) -> [any ToolAdapter] {
        var all: [any ToolAdapter] = [
            CalendarListTool(eventKit), CalendarSearchTool(eventKit), CalendarCreateTool(eventKit), CalendarUpdateTool(eventKit), CalendarDeleteTool(eventKit),
            RemindersListTool(eventKit), RemindersCreateTool(eventKit),
            NotesListFoldersTool(notes), NotesSearchTool(notes), NotesReadTool(notes), NotesCreateTool(notes), NotesAppendTool(notes),
            ContactsSearchTool(contacts), MessagesDraftTool(contacts),
            MessagesSearchTool(enabled: messagesEnabled, days: messagesDays, names: { [contacts, contactsEnabled] in
                contactsEnabled() ? contacts.nameIndex() : [:]
            }),
            ChromeListTabsTool(chrome), ChromeActivateTabTool(chrome),
            ShortcutsListTool(), ShortcutsRunTool(), WebSearchTool(), WebReadPageTool(), MapsSearchPlacesTool(), MapsRoutesTool(),
        ]
        if let memory {
            all += [MemoryReadTool(memory), MemorySaveTool(memory), MemoryCorrectTool(memory), MemoryForgetTool(memory)] as [any ToolAdapter]
        }
        return all
    }

    public func register(into service: ToolService, memory: MemoryFolder?) async {
        for a in adapters(memory: memory) { await service.register(a) }
    }
}
