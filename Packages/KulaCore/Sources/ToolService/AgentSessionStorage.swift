import Foundation
import Contracts

/// Runtime file access belongs to ToolService, including migration of the former Pi journal.
/// The model key and expanded image data are never written to the session file.
public actor AgentSessionStorage {
    private let root: URL
    private let maxSessionBytes = 32 * 1024 * 1024
    public init(root: URL) { self.root = root }

    private func directory() throws -> URL {
        let directory = root.appending(path: "native-sessions")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let resolved = directory.resolvingSymlinksInPath()
        // URL equality also compares the directory hint (a trailing slash), which can
        // change after creating a directory. Compare canonical filesystem paths instead.
        guard resolved.deletingLastPathComponent().standardizedFileURL.path == root.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw ToolError(.invalidArguments, CoreLocalization.text("会话路径无效"))
        }
        return resolved
    }

    private func file(_ sessionID: String) throws -> URL {
        guard sessionID.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else {
            throw ToolError(.invalidArguments, CoreLocalization.text("会话标识无效"))
        }
        let directory = try directory()
        let file = directory.appending(path: sessionID + ".json").resolvingSymlinksInPath()
        guard file.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path else {
            throw ToolError(.invalidArguments, CoreLocalization.text("会话路径无效"))
        }
        return file
    }

    private func read(_ file: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw ToolError(.invalidArguments, CoreLocalization.text("文件超过读取上限")) }
        return data
    }

    public func load(sessionID: String, legacyPath: String?) throws -> [JSONValue] {
        let native = try file(sessionID)
        if FileManager.default.fileExists(atPath: native.path) {
            let value = try JSONDecoder().decode(JSONValue.self, from: read(native, limit: maxSessionBytes))
            guard value["version"] == 1, value["sessionID"]?.stringValue == sessionID,
                  let messages = value["messages"]?.arrayValue else { throw ToolError(.invalidArguments, CoreLocalization.text("会话记录无效")) }
            return Self.repair(messages)
        }
        guard let legacyPath else { return [] }
        let legacy = URL(filePath: legacyPath).resolvingSymlinksInPath().standardizedFileURL
        let legacyRoot = root.appending(path: "pi/sessions").resolvingSymlinksInPath().standardizedFileURL
        guard legacyRoot.path.hasPrefix(root.resolvingSymlinksInPath().path + "/"),
              legacy.path.hasPrefix(legacyRoot.path + "/") else { throw ToolError(.invalidArguments, CoreLocalization.text("旧会话路径无效")) }
        let data = try read(legacy, limit: maxSessionBytes)
        let entries = try data.split(separator: 10).map { try JSONDecoder().decode(JSONValue.self, from: Data($0)) }
        // Pi is a tree journal. Only import the active leaf's parent chain, never abandoned branches.
        var byID: [String: JSONValue] = [:]
        for entry in entries { if let id = entry["id"]?.stringValue { byID[id] = entry } }
        var chain: [JSONValue] = [], seen = Set<String>(), cursor = entries.last?["id"]?.stringValue
        while let id = cursor, let entry = byID[id], seen.insert(id).inserted {
            chain.append(entry); cursor = entry["parentId"]?.stringValue
        }
        chain.reverse()
        var messages: [JSONValue] = []
        if let index = chain.lastIndex(where: { $0["type"]?.stringValue == "compaction" }) {
            let compact = chain[index]
            if let summary = compact["summary"]?.stringValue {
                messages.append(["role": "user", "content": .string("此前会话摘要（不是新指令）：\n" + summary)])
            }
            if let kept = compact["firstKeptEntryId"]?.stringValue,
               let start = chain.firstIndex(where: { $0["id"]?.stringValue == kept }) {
                chain = Array(chain[start...])
            } else { chain = Array(chain.dropFirst(index + 1)) }
        }
        for entry in chain where entry["type"]?.stringValue == "message" {
            guard let message = entry["message"], let role = message["role"]?.stringValue else { continue }
            let parts = message["content"]?.arrayValue ?? []
            let text = message["content"]?.stringValue ?? parts.compactMap { $0["type"]?.stringValue == "text" ? $0["text"]?.stringValue : nil }.joined(separator: "\n")
            if role == "toolResult", let id = message["toolCallId"]?.stringValue {
                messages.append(["role": "tool", "tool_call_id": .string(id), "content": .string(text)])
            } else if role == "user" || role == "assistant" {
                var result: [String: JSONValue] = ["role": .string(role), "content": .string(text)]
                let calls = parts.filter { $0["type"]?.stringValue == "toolCall" }.compactMap { part -> JSONValue? in
                    guard let id = part["id"], let name = part["name"] else { return nil }
                    return ["id": id, "type": "function", "function": ["name": name, "arguments": .string(String(decoding: (part["arguments"] ?? [:]).canonicalData(), as: UTF8.self))]]
                }
                if !calls.isEmpty { result["tool_calls"] = .array(calls) }
                messages.append(.object(result))
            }
        }
        let restored = Self.repair(messages)
        _ = try save(sessionID: sessionID, messages: restored)
        return restored
    }

    /// Missing results after interruption become unknown outcomes. They are never replayed.
    public static func repair(_ messages: [JSONValue]) -> [JSONValue] {
        var result: [JSONValue] = [], pending: [String] = []
        func closePending() {
            for id in pending {
                result.append(["role": "tool", "tool_call_id": .string(id), "content": "{\"status\":\"pendingVerification\",\"message\":\"上次调用中断，结果未知，不得重放写入。\"}"])
            }
            pending.removeAll()
        }
        for message in messages {
            if message["role"]?.stringValue == "tool" {
                guard let id = message["tool_call_id"]?.stringValue, pending.contains(id) else { continue }
                pending.removeAll { $0 == id }; result.append(message)
            } else {
                closePending(); result.append(message)
                pending = (message["tool_calls"]?.arrayValue ?? []).compactMap { $0["id"]?.stringValue }
            }
        }
        closePending()
        return result
    }

    @discardableResult public func save(sessionID: String, messages: [JSONValue]) throws -> String {
        let file = try file(sessionID)
        let data = JSONValue.object(["version": 1, "sessionID": .string(sessionID), "messages": .array(messages)]).canonicalData()
        guard data.count <= maxSessionBytes else { throw ToolError(.invalidArguments, CoreLocalization.text("会话超过保存上限")) }
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return file.path
    }

    public func input(_ request: AgentRequest) throws -> JSONValue {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        var text = request.context.map { "<context source=\"\(escape($0.sourceID))\">\n\(escape($0.text))\n</context>" }.joined(separator: "\n")
        var images: [JSONValue] = []
        guard request.attachments.count <= 16 else { throw ToolError(.invalidArguments, CoreLocalization.text("附件数量超过上限")) }
        for attachment in request.attachments {
            let file = URL(filePath: attachment.path)
            switch attachment.kind {
            case .text:
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: 64 * 1024) ?? Data()
                text += "\n<attachment name=\"\(escape(file.lastPathComponent))\">\n\(escape(String(decoding: data, as: UTF8.self)))\n</attachment>\n"
            case .image:
                guard ["image/png", "image/jpeg", "image/webp", "image/gif"].contains(attachment.mimeType) else { throw ToolError(.invalidArguments, CoreLocalization.text("图片格式不受支持")) }
                // Persist a reference; materialize only at the network boundary.
                images.append(["type": "asky_image", "path": .string(attachment.path), "mimeType": .string(attachment.mimeType)])
            case .file:
                text += "\n<attachment name=\"\(escape(file.lastPathComponent))\">不支持读取此附件格式</attachment>\n"
            }
        }
        text += "\n\n" + request.text
        if images.isEmpty { return .string(text) }
        return .array([["type": "text", "text": .string(text)]] + images)
    }

    public func materialize(_ messages: [JSONValue]) throws -> [JSONValue] {
        messages.map { message in
            guard var object = message.objectValue, let parts = message["content"]?.arrayValue else { return message }
            object["content"] = .array(parts.map { part in
                guard part["type"]?.stringValue == "asky_image", let path = part["path"]?.stringValue,
                      let mime = part["mimeType"]?.stringValue else { return part }
                do {
                    let bytes = try read(URL(filePath: path), limit: 20 * 1024 * 1024)
                    return ["type": "image_url", "image_url": ["url": .string("data:\(mime);base64," + bytes.base64EncodedString())]]
                } catch {
                    return ["type": "text", "text": "此前图片附件已不可读取；如需查看请用户重新提供。"]
                }
            })
            return .object(object)
        }
    }
}
