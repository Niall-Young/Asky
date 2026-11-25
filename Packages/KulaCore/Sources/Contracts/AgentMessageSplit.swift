import Foundation

/// Splits an assistant reply into natural IM-style chat bubbles:
/// Only explicit `<asky-split/>` markers outside fenced code blocks trigger a split
/// (unless the reply contains a top-level `asky-form` fence, which always stays intact).
/// Single-topic structured replies stay in one cohesive bubble rather than being force-split
/// on blank lines.
public enum AgentMessageSplit {
    public static let marker = "<asky-split/>"
    public static let maxBubbles = 4

    public static func split(_ source: String) -> [String] {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { return [] }

        if containsTopLevelFormFence(trimmedSource) {
            return [strippingMarkersOutsideFences(trimmedSource)]
        }

        if let explicit = splitByExplicitMarker(source) {
            return cap(explicit)
        }

        return [trimmedSource]
    }

    /// Removes split markers from narration text shown before tool calls.
    public static func strippingMarkers(_ source: String) -> String {
        source.replacingOccurrences(of: marker, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func strippingMarkersOutsideFences(_ source: String) -> String {
        guard source.contains(marker) else { return source }
        var output: [String] = []
        var fenceMarker: (char: Character, length: Int)? = nil
        for line in source.components(separatedBy: .newlines) {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if let fence = fenceMarker {
                output.append(line)
                if isClosingFence(stripped, char: fence.char, minLength: fence.length) {
                    fenceMarker = nil
                }
                continue
            }
            if let opened = openingFence(stripped) {
                fenceMarker = opened
                output.append(line)
                continue
            }
            if stripped == marker { continue }
            output.append(line.replacingOccurrences(of: marker, with: ""))
        }
        return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cap(_ parts: [String]) -> [String] {
        guard parts.count > maxBubbles else { return parts }
        let head = Array(parts.prefix(maxBubbles - 1))
        let tail = parts.dropFirst(maxBubbles - 1).joined(separator: "\n\n")
        return head + [tail]
    }

    private static func splitByExplicitMarker(_ source: String) -> [String]? {
        guard source.contains(marker) else { return nil }

        var parts: [String] = []
        var currentLines: [String] = []
        var fenceMarker: (char: Character, length: Int)? = nil
        var foundExplicitMarker = false

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
                foundExplicitMarker = true
                flush(&currentLines, into: &parts)
                continue
            }

            if line.contains(marker) {
                foundExplicitMarker = true
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
        guard foundExplicitMarker else { return nil }
        flush(&currentLines, into: &parts)
        return parts.isEmpty ? nil : parts
    }

    private static func containsTopLevelFormFence(_ source: String) -> Bool {
        var fenceMarker: (char: Character, length: Int)? = nil
        for line in source.components(separatedBy: .newlines) {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if let fence = fenceMarker {
                if isClosingFence(stripped, char: fence.char, minLength: fence.length) {
                    fenceMarker = nil
                }
                continue
            }
            if let opened = openingFence(stripped) {
                let info = stripped.dropFirst(opened.length).trimmingCharacters(in: .whitespaces).lowercased()
                if opened.length == 3 && info == "asky-form" {
                    return true
                }
                fenceMarker = opened
            }
        }
        return false
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
