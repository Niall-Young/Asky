import Foundation

/// Splits an assistant reply into multiple natural chat bubbles when the model
/// intentionally places `<asky-split/>` between segments, ignoring occurrences
/// inside fenced code blocks (such as `asky-form` or code examples).
public enum AgentMessageSplit {
    public static let marker = "<asky-split/>"
    public static let maxBubbles = 4

    public static func split(_ source: String) -> [String] {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { return [] }
        guard trimmedSource.contains(marker) else { return [trimmedSource] }

        var parts: [String] = []
        var currentLines: [String] = []
        var fenceMarker: (char: Character, length: Int)? = nil

        let lines = source.components(separatedBy: .newlines)
        for line in lines {
            let stripped = line.trimmingCharacters(in: .whitespaces)

            if let fence = fenceMarker {
                currentLines.append(line)
                if isClosingFence(stripped, char: fence.char, minLength: fence.length) {
                    fenceMarker = nil
                }
                continue
            }

            if let opened = openingFence(stripped) {
                fenceMarker = opened
                currentLines.append(line)
                continue
            }

            if stripped == marker {
                flush(&currentLines, into: &parts)
                continue
            }

            if line.contains(marker) {
                let inlineSegments = line.components(separatedBy: marker)
                for (index, segment) in inlineSegments.enumerated() {
                    if index > 0 {
                        flush(&currentLines, into: &parts)
                    }
                    if !segment.trimmingCharacters(in: .whitespaces).isEmpty {
                        currentLines.append(segment)
                    }
                }
                continue
            }

            currentLines.append(line)
        }
        flush(&currentLines, into: &parts)

        guard !parts.isEmpty else { return [] }
        if parts.count > maxBubbles {
            let head = Array(parts.prefix(maxBubbles - 1))
            let tail = parts.dropFirst(maxBubbles - 1).joined(separator: "\n\n")
            return head + [tail]
        }
        return parts
    }

    /// Removes split markers from narration text shown before tool calls.
    public static func strippingMarkers(_ source: String) -> String {
        source.replacingOccurrences(of: marker, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func flush(_ lines: inout [String], into parts: inout [String]) {
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        lines.removeAll(keepingCapacity: true)
        if !text.isEmpty {
            parts.append(text)
        }
    }

    private static func openingFence(_ trimmedLine: String) -> (char: Character, length: Int)? {
        guard let first = trimmedLine.first, first == "`" || first == "~" else { return nil }
        let count = trimmedLine.prefix(while: { $0 == first }).count
        guard count >= 3 else { return nil }
        let rest = trimmedLine.dropFirst(count)
        if first == "`" && rest.contains("`") { return nil }
        return (first, count)
    }

    private static func isClosingFence(_ trimmedLine: String, char: Character, minLength: Int) -> Bool {
        let count = trimmedLine.prefix(while: { $0 == char }).count
        guard count >= minLength else { return false }
        return trimmedLine.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty
    }
}
