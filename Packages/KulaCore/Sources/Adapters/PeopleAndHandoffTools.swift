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
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactMiddleNameKey as CNKeyDescriptor,
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactPhoneticGivenNameKey as CNKeyDescriptor,
        CNContactPhoneticFamilyNameKey as CNKeyDescriptor,
        CNContactPhoneticMiddleNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactBirthdayKey as CNKeyDescriptor,
    ]

    public struct Person: Sendable, Hashable {
        public var id: String
        public var name: String
        public var nickname: String
        public var phones: [String]
        public var emails: [String]
        public var organization: String
        public var handles: [String] { phones + emails }

        public init(id: String, name: String, nickname: String = "", phones: [String], emails: [String], organization: String) {
            self.id = id
            self.name = name
            self.nickname = nickname
            self.phones = phones
            self.emails = emails
            self.organization = organization
        }
    }

    struct SearchRecord: Sendable {
        var person: Person
        var primaryNames: [String]
        var secondaryNames: [String]
    }

    func person(_ c: CNContact) -> Person {
        let formatted = CNContactFormatter.string(from: c, style: .fullName)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nickname = c.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let organization = c.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName: String
        if !formatted.isEmpty {
            displayName = formatted
        } else if !nickname.isEmpty {
            displayName = nickname
        } else {
            displayName = organization
        }
        return Person(
            id: c.identifier,
            name: displayName,
            nickname: nickname,
            phones: c.phoneNumbers.map { $0.value.stringValue },
            emails: c.emailAddresses.map { $0.value as String },
            organization: organization
        )
    }

    func searchRecord(_ c: CNContact) -> SearchRecord {
        let p = person(c)
        let family = c.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let middle = c.middleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let given = c.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        let familyGiven = [family, middle, given].filter { !$0.isEmpty }.joined()
        let givenFamily = [given, middle, family].filter { !$0.isEmpty }.joined()
        let primary = [p.name, familyGiven, givenFamily, family, middle, given, p.nickname]
            .filter { !$0.isEmpty }
        let phoneticFamily = c.phoneticFamilyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneticMiddle = c.phoneticMiddleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneticGiven = c.phoneticGivenName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneticCombined = [phoneticFamily, phoneticMiddle, phoneticGiven].filter { !$0.isEmpty }.joined(separator: " ")
        let secondary = [p.organization, phoneticCombined, phoneticFamily, phoneticMiddle, phoneticGiven]
            .filter { !$0.isEmpty }
        return SearchRecord(person: p, primaryNames: primary, secondaryNames: secondary)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func compact(_ value: String) -> String {
        String(value.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
    }

    static func match(
        query rawQuery: String,
        in records: [SearchRecord],
        predicateMatchedIDs: Set<String> = [],
        limit: Int
    ) -> [Person] {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return [] }
        let normalizedQuery = normalize(trimmed)
        let compactQuery = compact(normalizedQuery)
        let tokens = normalizedQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        let queryDigits = String(trimmed.filter(\.isNumber))

        var ranked: [(rank: Int, person: Person)] = []
        for record in records {
            let primaryNorms = record.primaryNames.map(normalize).filter { !$0.isEmpty }
            let primaryCompacts = primaryNorms.map(compact).filter { !$0.isEmpty }
            let secondaryNorms = record.secondaryNames.map(normalize).filter { !$0.isEmpty }
            let secondaryCompacts = secondaryNorms.map(compact).filter { !$0.isEmpty }

            let rank: Int?
            if primaryNorms.contains(normalizedQuery)
                || (!compactQuery.isEmpty && primaryCompacts.contains(compactQuery)) {
                rank = 0
            } else if primaryNorms.contains(where: { name in
                name.hasPrefix(normalizedQuery)
                    || name.split(whereSeparator: \.isWhitespace).contains(where: { $0.hasPrefix(normalizedQuery) })
            }) || (!compactQuery.isEmpty && primaryCompacts.contains(where: { $0.hasPrefix(compactQuery) }))
                || predicateMatchedIDs.contains(record.person.id) {
                rank = 1
            } else if primaryNorms.contains(where: { $0.contains(normalizedQuery) })
                || (!compactQuery.isEmpty && primaryCompacts.contains(where: { $0.contains(compactQuery) })) {
                rank = 2
            } else if tokens.count > 1 {
                let combined = (primaryNorms + secondaryNorms).joined(separator: " ")
                let combinedCompact = compact(combined)
                if tokens.allSatisfy({ token in
                    combined.contains(token) || (!compact(token).isEmpty && combinedCompact.contains(compact(token)))
                }) {
                    rank = 3
                } else {
                    rank = nil
                }
            } else if secondaryNorms.contains(where: { $0.contains(normalizedQuery) })
                || (!compactQuery.isEmpty && secondaryCompacts.contains(where: { $0.contains(compactQuery) })) {
                rank = 4
            } else if queryDigits.count >= 3,
                      record.person.phones.contains(where: { String($0.filter(\.isNumber)).contains(queryDigits) }) {
                rank = 5
            } else if (normalizedQuery.contains("@") || compactQuery.count >= 3),
                      record.person.emails.contains(where: { normalize($0).contains(normalizedQuery) }) {
                rank = 5
            } else {
                rank = nil
            }

            if let rank {
                ranked.append((rank, record.person))
            }
        }

        ranked.sort { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            if lhs.person.name.count != rhs.person.name.count { return lhs.person.name.count < rhs.person.name.count }
            let order = lhs.person.name.localizedStandardCompare(rhs.person.name)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.person.id < rhs.person.id
        }
        return Array(ranked.prefix(limit).map(\.person))
    }

    public func search(_ name: String, limit: Int) throws -> [Person] {
        guard authorized else { throw ToolError(.permissionDenied, CoreLocalization.text("未获得通讯录访问权限")) }
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, limit > 0 else { return [] }
        // Apple's predicateForContacts(matchingName:) only matches word prefixes, so searching "爸"
        // misses "老爸" or "张爸爸". Combine it with a full unified scan for substring and nickname matches.
        let predicateMatched = (try? store.unifiedContacts(
            matching: CNContact.predicateForContacts(matchingName: query),
            keysToFetch: Self.keys
        )) ?? []
        let predicateIDs = Set(predicateMatched.map(\.identifier))
        var records: [SearchRecord] = []
        var seenIDs: Set<String> = []
        let request = CNContactFetchRequest(keysToFetch: Self.keys)
        try store.enumerateContacts(with: request) { contact, _ in
            guard seenIDs.insert(contact.identifier).inserted else { return }
            records.append(self.searchRecord(contact))
        }
        for contact in predicateMatched where seenIDs.insert(contact.identifier).inserted {
            records.append(self.searchRecord(contact))
        }
        return Self.match(query: query, in: records, predicateMatchedIDs: predicateIDs, limit: limit)
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
        ToolDefinition(name: "contacts_search", summary: CoreLocalization.text("按姓名、昵称或关键词模糊查找联系人（返回全部匹配候选）"),
                       inputSchema: Args.schema(["name": Args.stringProp, "limit": Args.intProp], required: ["name"]),
                       source: .contacts, effect: .read, confirmation: .never, externallyExposable: true)
    }
    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        let r = try contacts.search(try Args.requiredString(a, "name"), limit: Args.int(a["limit"], default: 10, max: 50))
        return AdapterOutput(output: .array(r.map {
            var entry: [String: JSONValue] = [
                "id": .string($0.id),
                "name": .string($0.name),
                "organization": .string($0.organization),
                "phones": .array($0.phones.map { .string($0) }),
                "emails": .array($0.emails.map { .string($0) })
            ]
            if !$0.nickname.isEmpty { entry["nickname"] = .string($0.nickname) }
            return .object(entry)
        }), targets: r.map { TargetRef(kind: "contact", identifier: $0.id) })
    }
}

// MARK: Messages draft hand-off

/// Prepares a Messages draft without sending or reading history.
/// In-app Agent calls prepare the draft card without activating Messages so the AI window stays uncovered
/// until the user clicks "Open in Messages"; external/direct callers hand off to Messages immediately.
public struct MessagesDraftTool: ToolAdapter {
    public typealias Handoff = @Sendable (URL, String) async -> Bool

    let contacts: ContactsBridge
    let handoff: Handoff

    public init(_ c: ContactsBridge, handoff: @escaping Handoff = MessagesDraftTool.defaultHandoff) {
        contacts = c
        self.handoff = handoff
    }

    public static let defaultHandoff: Handoff = { url, body in
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body, forType: .string)
            return NSWorkspace.shared.open(url)
        }
    }

    public var definition: ToolDefinition {
        ToolDefinition(name: "messages_prepare_draft", summary: CoreLocalization.text("准备信息草稿（对话中生成草稿卡片，点击按钮后在 Messages 中打开并由用户手动发送）"),
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
        try await executeDraft(a, openImmediately: true)
    }

    public func execute(_ a: JSONValue, requestID: String, origin: CallerOrigin) async throws -> AdapterOutput {
        switch origin {
        case .agent:
            return try await executeDraft(a, openImmediately: false)
        case .launcher, .mcp:
            return try await executeDraft(a, openImmediately: true)
        }
    }

    private func executeDraft(_ a: JSONValue, openImmediately: Bool) async throws -> AdapterOutput {
        let r = try recipient(a)
        let body = try Args.requiredString(a, "body")
        let url = Self.draftURL(handle: r.handle, body: body)
        if !openImmediately {
            return AdapterOutput(output: ["recipient": .string(r.display), "handle": .string(r.handle),
                                          "body": .string(body), "opened": .bool(false), "copiedToClipboard": .bool(false),
                                          "sent": false,
                                          "note": .string(CoreLocalization.text("草稿已准备好，请点击「在信息中打开」在 Messages 中查看并手动发送"))],
                                 targets: [TargetRef(kind: "messagesDraft", identifier: r.handle)])
        }
        let opened: Bool
        if let url {
            opened = await handoff(url, body)
        } else {
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(body, forType: .string)
            }
            opened = false
        }
        return AdapterOutput(output: ["recipient": .string(r.display), "handle": .string(r.handle),
                                      "body": .string(body), "opened": .bool(opened), "copiedToClipboard": true,
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
