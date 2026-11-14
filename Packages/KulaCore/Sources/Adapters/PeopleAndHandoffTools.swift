import Foundation
import AppKit
@preconcurrency import Contacts
import Contracts
import ToolService
import DirectActions

// MARK: Contacts

public final class ContactsBridge: @unchecked Sendable {
    let store = CNContactStore()
    public init() {}

    public var authorized: Bool {
        CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    public func request() async -> Bool { (try? await store.requestAccess(for: .contacts)) ?? false }

    static let keys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor, CNContactBirthdayKey as CNKeyDescriptor,
    ]

    public struct Person: Sendable, Hashable {
        public var id: String
        public var name: String
        public var phones: [String]
        public var emails: [String]
        public var organization: String
        public var handles: [String] { phones + emails }
    }

    func person(_ c: CNContact) -> Person {
        Person(id: c.identifier, name: CNContactFormatter.string(from: c, style: .fullName) ?? "",
               phones: c.phoneNumbers.map { $0.value.stringValue }, emails: c.emailAddresses.map { $0.value as String },
               organization: c.organizationName)
    }

    public func search(_ name: String, limit: Int) throws -> [Person] {
        guard authorized else { throw ToolError(.permissionDenied, CoreLocalization.text("未获得通讯录访问权限")) }
        let found = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: Self.keys)
        return found.prefix(limit).map(person)
    }

    public func get(_ id: String) throws -> Person {
        guard authorized else { throw ToolError(.permissionDenied, CoreLocalization.text("未获得通讯录访问权限")) }
        do { return person(try store.unifiedContact(withIdentifier: id, keysToFetch: Self.keys)) } catch {
            throw ToolError(.targetNotFound, CoreLocalization.text("找不到联系人"))
        }
    }

    /// Normalized phone/email → display name, for labelling Messages senders. Empty without Contacts access.
    public func nameIndex() -> [String: String] {
        guard authorized else { return [:] }
        var index: [String: String] = [:]
        let request = CNContactFetchRequest(keysToFetch: Self.keys)
        try? store.enumerateContacts(with: request) { contact, _ in
            let p = self.person(contact)
            guard !p.name.isEmpty else { return }
            for handle in p.handles { index[MessagesHistoryReader.normalize(handle)] = p.name }
        }
        return index
    }
}

public struct ContactsSearchTool: ToolAdapter {
    let contacts: ContactsBridge
    public init(_ c: ContactsBridge) { contacts = c }
    public var definition: ToolDefinition {
        ToolDefinition(name: "contacts_search", summary: CoreLocalization.text("按姓名查找联系人（同名时返回全部候选）"),
                       inputSchema: Args.schema(["name": Args.stringProp, "limit": Args.intProp], required: ["name"]),
                       source: .contacts, effect: .read, confirmation: .never, externallyExposable: true)
    }
    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        let r = try contacts.search(try Args.requiredString(a, "name"), limit: Args.int(a["limit"], default: 10, max: 50))
        return AdapterOutput(output: .array(r.map {
            ["id": .string($0.id), "name": .string($0.name), "organization": .string($0.organization),
             "phones": .array($0.phones.map { .string($0) }), "emails": .array($0.emails.map { .string($0) })]
        }), targets: r.map { TargetRef(kind: "contact", identifier: $0.id) })
    }
}

// MARK: Messages draft hand-off

/// Prefills a draft in Messages; never sends and never reads history. Falls back to copying the body.
public struct MessagesDraftTool: ToolAdapter {
    let contacts: ContactsBridge
    public init(_ c: ContactsBridge) { contacts = c }

    public var definition: ToolDefinition {
        ToolDefinition(name: "messages_prepare_draft", summary: CoreLocalization.text("在 Messages 中准备草稿（明确请求直接打开；由用户手动发送）"),
                       inputSchema: Args.schema(["contactID": Args.stringProp,
                                                 "handle": ["type": "string", "description": .string(CoreLocalization.text("电话号码或邮箱；联系人有多个时必填"))],
                                                 "body": Args.stringProp], required: ["body"]),
                       source: .messages, effect: .write, writeKind: .handoff, confirmation: .explicitDirectOtherwiseConfirm, externallyExposable: true)
    }

    /// Resolves exactly one recipient handle; multiple numbers require an explicit choice.
    func recipient(_ a: JSONValue) throws -> (handle: String, display: String) {
        let handle = try Args.string(a["handle"], "handle", required: false)
        if let cid = try Args.string(a["contactID"], "contactID", required: false) {
            let p = try contacts.get(cid)
            if let handle {
                guard p.handles.contains(handle) else { throw ToolError(.invalidArguments, CoreLocalization.format("该号码不属于「%@」", String(describing: p.name))) }
                return (handle, "\(p.name)（\(handle)）")
            }
            guard p.handles.count == 1 else {
                if p.handles.isEmpty { throw ToolError(.targetNotFound, CoreLocalization.format("「%@」没有电话或邮箱", String(describing: p.name))) }
                throw ToolError(.ambiguousTarget, CoreLocalization.format("请选择「%@」的号码：", String(describing: p.name)) + p.handles.joined(separator: "、"))
            }
            return (p.handles[0], "\(p.name)（\(p.handles[0])）")
        }
        guard let handle, Self.isValidHandle(handle) else { throw ToolError(.invalidArguments, CoreLocalization.text("缺少有效的收件人")) }
        return (handle, handle)
    }

    public static func isValidHandle(_ h: String) -> Bool {
        if h.contains("@") { return h.split(separator: "@").count == 2 && !h.contains(" ") }
        let digits = h.filter(\.isNumber)
        return digits.count >= 3 && h.allSatisfy { $0.isNumber || "+-() ".contains($0) }
    }

    public static func draftURL(handle: String, body: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        guard let h = handle.filter({ !" ()-".contains($0) }).addingPercentEncoding(withAllowedCharacters: allowed),
              let b = body.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "sms:\(h)&body=\(b)")
    }

    public func preview(_ a: JSONValue) async throws -> ConfirmationPreview {
        let r = try recipient(a)
        return ConfirmationPreview(target: "Messages：\(r.display)", changes: ["草稿：" + (try Args.requiredString(a, "body"))],
                                   note: "只会打开草稿，需要你在 Messages 中手动发送")
    }

    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        let r = try recipient(a)
        let body = try Args.requiredString(a, "body")
        let opened = await MainActor.run { () -> Bool in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body, forType: .string)
            guard let url = Self.draftURL(handle: r.handle, body: body) else { return false }
            return NSWorkspace.shared.open(url)
        }
        return AdapterOutput(output: ["recipient": .string(r.display), "opened": .bool(opened), "copiedToClipboard": true,
                                      "sent": false,
                                      "note": .string(opened ? CoreLocalization.text("已打开草稿；若正文未预填，可直接粘贴") : CoreLocalization.text("未能打开 Messages，正文已复制"))],
                             targets: [TargetRef(kind: "messagesDraft", identifier: r.handle)])
    }
}

// MARK: Shortcuts

public struct ShortcutsListTool: ToolAdapter {
    public init() {}
    public var definition: ToolDefinition {
        ToolDefinition(name: "shortcuts_list", summary: CoreLocalization.text("列出可用的快捷指令"), inputSchema: Args.schema([:], required: []),
                       source: .shortcuts, effect: .read, confirmation: .never, externallyExposable: false)
    }
    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        AdapterOutput(output: .array(await ShortcutsService.list().map { .string($0) }))
    }
}

public struct ShortcutsRunTool: ToolAdapter {
    public init() {}
    public var definition: ToolDefinition {
        ToolDefinition(name: "shortcuts_run", summary: CoreLocalization.text("运行指定快捷指令（需确认；报告开始与结束状态）"),
                       inputSchema: Args.schema(["name": Args.stringProp, "input": Args.stringProp], required: ["name"]),
                       source: .shortcuts, effect: .write, writeKind: .handoff, confirmation: .always, externallyExposable: false)
    }
    public func preview(_ a: JSONValue) async throws -> ConfirmationPreview {
        let name = try Args.requiredString(a, "name")
        guard await ShortcutsService.list().contains(name) else { throw ToolError(.targetNotFound, CoreLocalization.format("找不到快捷指令「%@」", String(describing: name))) }
        return ConfirmationPreview(target: "快捷指令「\(name)」",
                                   changes: a["input"]?.stringValue.map { ["输入：" + String($0.prefix(200))] } ?? ["无输入"],
                                   note: "快捷指令可能执行其自身定义的任意操作")
    }
    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        let name = try Args.requiredString(a, "name")
        for await state in ShortcutsService.run(name: name, input: a["input"]?.stringValue) {
            switch state {
            case .started: continue
            case .completed(let out): return AdapterOutput(output: ["name": .string(name), "output": .string(out)])
            case .failed(let m): throw ToolError(.adapterFailure, CoreLocalization.format("快捷指令失败：%@", String(describing: m)))
            }
        }
        throw ToolError(.cancelled, CoreLocalization.text("快捷指令已取消"))
    }
    /// A shortcut's effects cannot be read back; only report what the run itself returned.
    public func readback(_ a: JSONValue, output: AdapterOutput?) async -> JSONValue? { output?.output }
}
