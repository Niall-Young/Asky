import Foundation

// Authors compile this executable before publishing; users need no compiler or Node.
func result(_ frame: [String: Any]) throws -> [String: Any] {
    guard frame["readback"] as? Bool != true else { return ["type": "result", "value": NSNull()] }
    switch frame["tool"] as? String {
    case "uuid":
        return ["type": "result", "value": ["text": UUID().uuidString.lowercased()]]
    case "transform":
        guard let args = frame["arguments"] as? [String: Any], let text = args["text"] as? String else {
            return ["type": "result", "error": "text must be a string", "errorCode": "invalidArguments"]
        }
        if text.isEmpty { return ["type": "result", "value": ["items": []]] }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
        let base64 = Data(text.utf8).base64EncodedString()
        var items = [
            ["id": "url-encode", "title": encoded, "subtitle": "URL Encode", "copy": encoded],
            ["id": "base64", "title": base64, "subtitle": "Base64 Encode", "copy": base64],
        ]
        if let decoded = text.removingPercentEncoding, decoded != text, !decoded.isEmpty {
            items.append(["id": "url-decode", "title": decoded, "subtitle": "URL Decode", "copy": decoded])
        }
        return ["type": "result", "value": ["items": items]]
    default:
        return ["type": "result", "error": "Unknown tool", "errorCode": "invalidArguments"]
    }
}

do {
    guard let line = readLine(), let data = line.data(using: .utf8),
          let frame = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw NSError(domain: "TextTools", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid request"])
    }
    let response = try JSONSerialization.data(withJSONObject: result(frame), options: [.sortedKeys])
    FileHandle.standardOutput.write(response + Data([10]))
} catch {
    let data = try JSONSerialization.data(withJSONObject: ["type": "result", "error": error.localizedDescription])
    FileHandle.standardOutput.write(data + Data([10]))
}
