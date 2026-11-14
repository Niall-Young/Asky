import Foundation

// Compile before publishing the plugin repository:
// xcrun swiftc -O main.swift -o native-echo
// No model credentials or Node runtime are involved in this executable.
func emit(_ object: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data([10]))
}

do {
    guard let line = readLine(), let data = line.data(using: .utf8),
          let frame = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          frame["tool"] as? String == "echo", let args = frame["arguments"] as? [String: Any],
          let text = args["text"] as? String else {
        throw NSError(domain: "NativeEcho", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid request"])
    }
    try emit(["type": "result", "value": ["text": text]])
} catch {
    try? emit(["type": "result", "error": error.localizedDescription, "errorCode": "invalidArguments"])
}
