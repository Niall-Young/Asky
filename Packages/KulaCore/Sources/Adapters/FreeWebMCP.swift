import Foundation
import Contracts

/// Calls existing hosted tools. There is deliberately no credential, billing, OAuth,
/// subprocess, browser, package installation, or developer-owned proxy path.
enum FreeWebProvider: String, CaseIterable, Sendable {
    case parallel = "Parallel", exa = "Exa"
    var endpoint: URL {
        URL(string: self == .parallel ? "https://search.parallel.ai/mcp" : "https://mcp.exa.ai/mcp")!
    }
}

struct FreeWebFailure: Error, Sendable {
    let status: String
    let message: String
}

enum FreeWebMCP {
    typealias Call = @Sendable (FreeWebProvider, String, JSONValue) async throws -> JSONValue
    static let protocolVersion = "2025-03-26"
    // Stable for this app process; never rotate IDs to avoid a provider's limits.
    static let sessionID = UUID().uuidString

    static func request(provider: FreeWebProvider, payload: JSONValue, sessionID: String? = nil) -> URLRequest {
        var request = URLRequest(url: provider.endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = payload.canonicalData()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Asky/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        return request
    }

    static func call(_ provider: FreeWebProvider, _ name: String, _ arguments: JSONValue) async throws -> JSONValue {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForResource = 18
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let initialized = try await send(session, request(provider: provider, payload: [
            "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
                "protocolVersion": .string(protocolVersion), "capabilities": [:],
                "clientInfo": ["name": "Asky", "version": "1.0"]]]), id: 1)
        guard initialized.0["result"]?["protocolVersion"]?.stringValue == protocolVersion else {
            throw FreeWebFailure(status: "unavailable", message: "Unsupported MCP protocol")
        }
        let sid = initialized.1.value(forHTTPHeaderField: "Mcp-Session-Id")
        _ = try await send(session, request(provider: provider, payload: [
            "jsonrpc": "2.0", "method": "notifications/initialized", "params": [:]], sessionID: sid), id: nil)
        let response = try await send(session, request(provider: provider, payload: [
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": ["name": .string(name), "arguments": arguments]], sessionID: sid), id: 2)
        guard let result = response.0["result"] else { throw FreeWebFailure(status: "unavailable", message: "Missing MCP result") }
        if result["isError"]?.boolValue == true {
            let message = text(result)
            let limited = message.range(of: "rate.?limit|quota|too many|usage limit", options: [.regularExpression, .caseInsensitive]) != nil
            throw FreeWebFailure(status: limited ? "rate_limited" : "unavailable", message: String(message.prefix(1500)))
        }
        return result
    }

    private static func send(_ session: URLSession, _ request: URLRequest, id: Int?) async throws -> (JSONValue, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw FreeWebFailure(status: "unavailable", message: "No HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            throw FreeWebFailure(status: http.statusCode == 429 ? "rate_limited" : "unavailable", message: "HTTP \(http.statusCode)")
        }
        // A notification has no JSON-RPC response; do not wait on an optional event stream.
        guard let id else { return (.null, http) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 2_097_152 else { throw FreeWebFailure(status: "unavailable", message: "MCP response exceeds 2 MiB") }
            data.append(byte)
        }
        return (try decode(data, id: id), http)
    }

    static func decode(_ data: Data, id: Int) throws -> JSONValue {
        var messages: [JSONValue] = []
        if let json = try? JSONDecoder().decode(JSONValue.self, from: data) { messages.append(json) }
        else {
            let input = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
            for event in input.components(separatedBy: "\n\n") {
                let text = event.components(separatedBy: "\n").filter { $0.hasPrefix("data:") }
                    .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
                if let json = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) { messages.append(json) }
            }
        }
        guard let message = messages.first(where: { $0["id"]?.numberValue == Double(id) }), message["error"] == nil else {
            throw FreeWebFailure(status: "unavailable", message: "Invalid or failed MCP response")
        }
        return message
    }

    static func text(_ result: JSONValue) -> String {
        (result["content"]?.arrayValue ?? []).filter { $0["type"]?.stringValue == "text" }
            .compactMap { $0["text"]?.stringValue }.joined(separator: "\n\n")
    }

    static func structured(_ result: JSONValue) throws -> JSONValue {
        if let value = result["structuredContent"], value.objectValue != nil { return value }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text(result).utf8)) else {
            throw FreeWebFailure(status: "unavailable", message: "Invalid structured tool output")
        }
        return value
    }

    static func searchResults(_ result: JSONValue, provider: FreeWebProvider) throws -> [JSONValue] {
        if provider == .parallel {
            let value = try structured(result)
            guard let rows = value["results"]?.arrayValue else { throw FreeWebFailure(status: "unavailable", message: "Missing search results") }
            return rows.compactMap { row in
                guard let url = row["url"]?.stringValue, publicURL(url) != nil else { return nil }
                let excerpt = (row["excerpts"]?.arrayValue ?? []).compactMap(\.stringValue).joined(separator: "\n\n")
                return ["url": .string(url), "title": row["title"] ?? .string(url), "snippet": .string(String(excerpt.prefix(6000))),
                        "truncated": .bool(excerpt.count > 6000), "publishedAt": row["publish_date"] ?? .null, "provider": .string(provider.rawValue)]
            }
        }
        // Exa's official MCP search returns labelled text blocks, not HTML.
        let value = text(result)
        let regex = try NSRegularExpression(pattern: #"(?ms)^Title: ([^\n]*)\nURL: (https?://[^\s]+)\n(.*?)(?=^Title: |\z)"#)
        let ns = value as NSString
        let rows: [JSONValue] = regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let url = ns.substring(with: match.range(at: 2))
            guard publicURL(url) != nil else { return nil }
            let body = ns.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
            return ["url": .string(url), "title": .string(ns.substring(with: match.range(at: 1))),
                    "snippet": .string(String(body.prefix(6000))), "truncated": .bool(body.count > 6000), "provider": .string(provider.rawValue)]
        }
        if rows.isEmpty && value.range(of: "no results|no search results", options: [.caseInsensitive, .regularExpression]) == nil {
            throw FreeWebFailure(status: "unavailable", message: "Unrecognized Exa search output")
        }
        return rows
    }

    static func publicURL(_ value: String) -> URL? {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, let host = url.host?.lowercased(), host.contains("."),
              !host.contains(":"), !host.allSatisfy({ $0.isNumber || $0 == "." }),
              !["localhost", "local", "internal", "test", "invalid"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
        return url
    }

    static func failure(_ error: Error, provider: FreeWebProvider) throws -> JSONValue {
        try Task.checkCancellation()
        if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
        let failure = error as? FreeWebFailure
        return ["provider": .string(provider.rawValue), "status": .string(failure?.status ?? "unavailable"),
                "error": .string(failure?.message ?? error.localizedDescription)]
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
