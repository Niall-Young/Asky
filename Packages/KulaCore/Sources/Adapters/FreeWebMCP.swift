import Foundation
import Contracts

/// Calls existing hosted tools. There is deliberately no credential, billing, OAuth,
/// subprocess, browser, package installation, or developer-owned proxy path.
enum FreeWebProvider: String, CaseIterable, Sendable {
    case parallel = "Parallel", exa = "Exa", keenable = "Keenable"
    var endpoint: URL {
        switch self {
        case .parallel: URL(string: "https://search.parallel.ai/mcp")!
        case .exa: URL(string: "https://mcp.exa.ai/mcp")!
        case .keenable: URL(string: "https://api.keenable.ai")!
        }
    }
}

struct FreeWebFailure: Error, Sendable {
    let status: String
    let message: String
    var stage: String? = nil
    var httpStatus: Int? = nil
    var rpcCode: Int? = nil
    var retryAfter: TimeInterval? = nil
    var requestID: String? = nil

    static func classified(_ message: String, stage: String, httpStatus: Int? = nil,
                           rpcCode: Int? = nil, retryAfter: TimeInterval? = nil) -> Self {
        let limited = httpStatus == 429 || message.range(of: "rate.?limit|quota|too many requests|usage limit|slow down",
            options: [.regularExpression, .caseInsensitive]) != nil
        return Self(status: limited ? "rate_limited" : "unavailable", message: String(message.prefix(1500)),
                    stage: stage, httpStatus: httpStatus, rpcCode: rpcCode, retryAfter: retryAfter)
    }
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
        try await performCall(provider, name, arguments, configuration: .ephemeral)
    }

    static func performCall(_ provider: FreeWebProvider, _ name: String, _ arguments: JSONValue,
                            configuration config: URLSessionConfiguration) async throws -> JSONValue {
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForResource = 18
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        if provider == .keenable {
            let request = try keenableRequest(name: name, arguments: arguments)
            return try await send(session, request, id: nil, stage: name, notification: false).0
        }
        let initialized = try await send(session, request(provider: provider, payload: [
            "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
                "protocolVersion": .string(protocolVersion), "capabilities": [:],
                "clientInfo": ["name": "Asky", "version": "1.0"]]]), id: 1, stage: "initialize")
        guard let negotiated = initialized.0["result"]?["protocolVersion"]?.stringValue,
              [protocolVersion, "2025-06-18", "2025-11-25"].contains(negotiated) else {
            throw FreeWebFailure(status: "unavailable", message: "Unsupported MCP protocol", stage: "initialize")
        }
        let sid = initialized.1.value(forHTTPHeaderField: "Mcp-Session-Id")
        func negotiatedRequest(_ payload: JSONValue) -> URLRequest {
            var value = request(provider: provider, payload: payload, sessionID: sid)
            value.setValue(negotiated, forHTTPHeaderField: "MCP-Protocol-Version")
            return value
        }
        _ = try await send(session, negotiatedRequest([
            "jsonrpc": "2.0", "method": "notifications/initialized", "params": [:]]), id: nil,
            stage: "notifications/initialized", notification: true)
        let response = try await send(session, negotiatedRequest([
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": ["name": .string(name), "arguments": arguments]]), id: 2, stage: name)
        guard let result = response.0["result"] else {
            throw FreeWebFailure(status: "unavailable", message: "Missing MCP result", stage: name)
        }
        if result["isError"]?.boolValue == true {
            var failure = FreeWebFailure.classified(text(result), stage: name, httpStatus: response.1.statusCode,
                retryAfter: retryDelay(response.1.value(forHTTPHeaderField: "Retry-After")))
            failure.requestID = response.1.value(forHTTPHeaderField: "x-request-id")
            throw failure
        }
        return result
    }

    static func keenableRequest(name: String, arguments: JSONValue) throws -> URLRequest {
        var url = FreeWebProvider.keenable.endpoint
        var body: JSONValue?
        if name == "search" {
            url.append(path: "v1/search/public")
            body = ["query": arguments["query"] ?? "", "max_results": arguments["numResults"] ?? 5]
        } else {
            guard let page = arguments["urls"]?.arrayValue?.first?.stringValue, publicURL(page) != nil else {
                throw FreeWebFailure(status: "unavailable", message: "Invalid page URL", stage: name)
            }
            var components = URLComponents(url: url.appending(path: "v1/fetch/public"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "url", value: page)]
            url = components.url!
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body?.canonicalData()
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue("Asky", forHTTPHeaderField: "X-Keenable-Title")
        request.setValue("Asky/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func send(_ session: URLSession, _ request: URLRequest, id: Int?, stage: String,
                             notification: Bool = false) async throws -> (JSONValue, HTTPURLResponse) {
        var received: HTTPURLResponse?
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw FreeWebFailure(status: "unavailable", message: "No HTTP response")
            }
            received = http
            var data = Data()
            if !(200..<300).contains(http.statusCode) {
                for try await byte in bytes {
                    data.append(byte)
                    if data.count >= 8192 { break }
                }
                var failure = FreeWebFailure.classified("HTTP \(http.statusCode): \(String(decoding: data, as: UTF8.self))",
                    stage: stage, httpStatus: http.statusCode,
                    retryAfter: retryDelay(http.value(forHTTPHeaderField: "Retry-After")))
                failure.requestID = http.value(forHTTPHeaderField: "x-request-id")
                throw failure
            }
            if notification { return (.null, http) }
            let isSSE = http.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 2_097_152 else {
                    throw FreeWebFailure(status: "unavailable", message: "Response exceeds 2 MiB")
                }
                data.append(byte)
                // Finish as soon as the matching SSE envelope arrives; a server may leave the stream open.
                if isSSE, byte == 10, let id,
                   (data.suffix(2) == Data([10, 10]) || data.suffix(4) == Data([13, 10, 13, 10])) {
                    if let envelope = try envelope(data, id: id) { return (envelope, http) }
                }
            }
            if let id { return (try decode(data, id: id), http) }
            guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
                throw FreeWebFailure(status: "unavailable", message: "Invalid JSON response")
            }
            if value["error"] != nil || value["success"]?.boolValue == false {
                throw FreeWebFailure.classified(value["error"]?.stringValue ?? "Provider returned an error", stage: stage)
            }
            return (value, http)
        } catch var failure as FreeWebFailure {
            failure.stage = stage
            failure.httpStatus = failure.httpStatus ?? received?.statusCode
            failure.requestID = failure.requestID ?? received?.value(forHTTPHeaderField: "x-request-id")
            failure.retryAfter = failure.retryAfter ?? retryDelay(received?.value(forHTTPHeaderField: "Retry-After"))
            throw failure
        } catch {
            try Task.checkCancellation()
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            throw FreeWebFailure(status: "unavailable", message: error.localizedDescription, stage: stage)
        }
    }

    static func retryDelay(_ value: String?, now: Date = Date()) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }

    static func envelope(_ data: Data, id: Int) throws -> JSONValue? {
        var messages: [JSONValue] = []
        func append(_ data: Data) {
            if let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
                messages.append(contentsOf: json.arrayValue ?? [json])
            }
        }
        append(data)
        if messages.isEmpty {
            let input = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
            for event in input.components(separatedBy: "\n\n") {
                let text = event.components(separatedBy: "\n").filter { $0.hasPrefix("data:") }
                    .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
                append(Data(text.utf8))
            }
        }
        let message = messages.first { $0["id"]?.numberValue == Double(id) || $0["id"]?.stringValue == String(id) }
            ?? messages.first { ($0["id"] == nil || $0["id"] == .null) && $0["error"] != nil }
        if let error = message?["error"] {
            throw FreeWebFailure.classified(error["message"]?.stringValue ?? "JSON-RPC error", stage: "decode",
                rpcCode: error["code"]?.numberValue.flatMap { Int(exactly: $0) })
        }
        return message
    }

    static func decode(_ data: Data, id: Int) throws -> JSONValue {
        guard let message = try envelope(data, id: id) else {
            throw FreeWebFailure(status: "unavailable", message: "Missing matching MCP response (id=\(id))", stage: "decode")
        }
        return message
    }

    static func text(_ result: JSONValue) -> String {
        (result["content"]?.arrayValue ?? []).filter { $0["type"]?.stringValue == "text" }
            .compactMap { $0["text"]?.stringValue }.joined(separator: "\n\n")
    }

    static func structured(_ result: JSONValue) throws -> JSONValue {
        if let value = result["structuredContent"], value.objectValue != nil { return value }
        for block in result["content"]?.arrayValue ?? [] where block["type"]?.stringValue == "text" {
            if let text = block["text"]?.stringValue,
               let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), value.objectValue != nil { return value }
        }
        throw FreeWebFailure(status: "unavailable", message: "Invalid structured tool output", stage: "parse")
    }

    static func searchResults(_ result: JSONValue, provider: FreeWebProvider) throws -> [JSONValue] {
        if provider == .keenable {
            guard let rows = result["results"]?.arrayValue else {
                throw FreeWebFailure(status: "unavailable", message: "Missing Keenable search results", stage: "parse")
            }
            return rows.compactMap { row in
                guard let url = row["url"]?.stringValue, publicURL(url) != nil else { return nil }
                let excerpt = row["snippet"]?.stringValue ?? row["description"]?.stringValue ?? ""
                return ["url": .string(url), "title": row["title"] ?? .string(url),
                    "snippet": .string(String(excerpt.prefix(6000))), "truncated": .bool(excerpt.count > 6000),
                    "publishedAt": row["published_at"] ?? .null, "provider": .string(provider.rawValue)]
            }
        }
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
                "error": .string(failure?.message ?? error.localizedDescription),
                "stage": failure?.stage.map(JSONValue.string) ?? .null,
                "httpStatus": failure?.httpStatus.map { .number(Double($0)) } ?? .null,
                "rpcCode": failure?.rpcCode.map { .number(Double($0)) } ?? .null,
                "retryAfterSeconds": failure?.retryAfter.map(JSONValue.number) ?? .null,
                "requestID": failure?.requestID.map(JSONValue.string) ?? .null]
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
