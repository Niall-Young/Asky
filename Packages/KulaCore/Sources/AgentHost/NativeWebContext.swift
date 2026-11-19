import Foundation
import Contracts

/// A request-only view of web evidence. Original tool results remain in the session snapshot.
/// Keep source URLs, image candidates, errors, and tool-call pairing intact; only excerpt prose is cut.
enum NativeWebContext {
    static let proseBudget = 48_000
    static let perResultBudget = 12_000

    static func allSourcesCoolingDown(_ result: JSONValue) -> Bool {
        guard let output = result["output"],
              ["rate_limited", "unavailable"].contains(output["status"]?.stringValue ?? ""),
              let attempts = output["attempts"]?.arrayValue, !attempts.isEmpty else { return false }
        return attempts.allSatisfy { $0["skipped"] == true && $0["stage"] == "cooldown" }
    }

    static func messages(_ messages: [JSONValue]) -> [JSONValue] {
        var webIDs = Set<String>(), webIndices = Set<Int>()
        for (index, message) in messages.enumerated() {
            if message["role"] == "assistant" {
                webIDs = Set((message["tool_calls"]?.arrayValue ?? []).compactMap { call -> String? in
                    guard ["web_search", "web_read_page"].contains(call["function"]?["name"]?.stringValue ?? "") else { return nil }
                    return call["id"]?.stringValue
                })
            } else if message["role"] == "tool", webIDs.contains(message["tool_call_id"]?.stringValue ?? "") {
                webIndices.insert(index)
            }
        }
        guard !webIndices.isEmpty else { return messages }
        // Allocate prose budget sequentially so earlier web tool results never mutate
        // when subsequent web calls arrive in the same turn, preserving prompt prefix cache.
        var remainingBudget = proseBudget
        return messages.enumerated().map { index, message in
            guard webIndices.contains(index),
                  let content = message["content"]?.stringValue,
                  var result = (try? JSONDecoder().decode(JSONValue.self, from: Data(content.utf8)))?.objectValue,
                  var output = result["output"]?.objectValue,
                  var projected = message.objectValue else { return message }
            var changed = false
            var resultAllowance = min(perResultBudget, remainingBudget)
            if let text = output["text"]?.stringValue {
                if text.utf8.count > resultAllowance {
                    let kept = prefix(text, bytes: resultAllowance)
                    output["text"] = .string(kept)
                    output["truncated"] = true
                    changed = true
                    remainingBudget = max(0, remainingBudget - kept.utf8.count)
                    resultAllowance = max(0, resultAllowance - kept.utf8.count)
                } else {
                    remainingBudget = max(0, remainingBudget - text.utf8.count)
                    resultAllowance = max(0, resultAllowance - text.utf8.count)
                }
            }
            if let rows = output["results"]?.arrayValue, !rows.isEmpty {
                let perRow = resultAllowance / rows.count
                var keptSnippetsBytes = 0
                output["results"] = .array(rows.map { row in
                    guard var fields = row.objectValue, let text = fields["snippet"]?.stringValue else { return row }
                    if text.utf8.count > perRow {
                        let kept = prefix(text, bytes: perRow)
                        fields["snippet"] = .string(kept)
                        fields["truncated"] = true
                        changed = true
                        keptSnippetsBytes += kept.utf8.count
                        return .object(fields)
                    } else {
                        keptSnippetsBytes += text.utf8.count
                        return row
                    }
                })
                remainingBudget = max(0, remainingBudget - keptSnippetsBytes)
            }
            guard changed else { return message }
            output["contextTruncated"] = true
            output["contextNotice"] = "网页正文摘录已按本轮上下文预算截取；仅依据保留片段作答，不声称读过省略内容。"
            result["output"] = .object(output)
            projected["content"] = .string(String(decoding: JSONValue.object(result).canonicalData(), as: UTF8.self))
            return .object(projected)
        }
    }

    private static func prefix(_ text: String, bytes: Int) -> String {
        var end = text.utf8.index(text.utf8.startIndex, offsetBy: min(bytes, text.utf8.count))
        while end > text.utf8.startIndex && String.Index(end, within: text) == nil {
            end = text.utf8.index(before: end)
        }
        return String(text[..<String.Index(end, within: text)!])
    }
}
