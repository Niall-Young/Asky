import Foundation

/// Splits an assistant reply into natural IM-style chat bubbles:
/// 1. Explicit `<asky-split/>` markers outside fenced code blocks are always honored.
/// 2. Otherwise, multi-block Markdown replies are automatically segmented by top-level
///    paragraphs/sections while keeping semantically paired blocks together (headings,
///    colon lead-ins before lists/code/tables/quotes/images, loose list items, image
///    galleries with their source citations, and `asky-form` replies).
public enum AgentMessageSplit {
    public static let marker = "<asky-split/>"
    public static let maxBubbles = 4

    public static func split(_ source: String) -> [String] {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { return [] }

        if let explicit = splitByExplicitMarker(source) {
            return cap(explicit)
        }

        if containsTopLevelFormFence(trimmedSource) {
            return [trimmedSource]
        }

        let blocks = parseBlocks(trimmedSource)
        guard blocks.count > 1 else { return [trimmedSource] }
        let grouped = groupBlocks(blocks)
        guard grouped.count > 1 else { return [trimmedSource] }
        return cap(grouped)
    }

    /// Removes split markers from narration text shown before tool calls.
    public static func strippingMarkers(_ source: String) -> String {
        source.replacingOccurrences(of: marker, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private enum BlockKind: Equatable {
        case paragraph
        case list
        case codeFence
        case table
        case blockquote
        case heading
        case image
        case citationOnly
        case mathBlock
        case thematicBreak
    }

    private struct Block {
        var kind: BlockKind
        var text: String
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

    private static func parseBlocks(_ source: String) -> [Block] {
        let lines = source.components(separatedBy: .newlines)
        var blocks: [Block] = []
        var current: [String] = []
        var fenceMarker: (char: Character, length: Int)? = nil
        var mathFence: String? = nil

        func flushCurrent() {
            let text = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            current.removeAll(keepingCapacity: true)
            guard !text.isEmpty else { return }
            blocks.append(Block(kind: classify(text), text: text))
        }

        for line in lines {
            let stripped = line.trimmingCharacters(in: .whitespaces)

            if let fence = fenceMarker {
                current.append(line)
                if isClosingFence(stripped, char: fence.char, minLength: fence.length) {
                    fenceMarker = nil
                    let text = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    current.removeAll(keepingCapacity: true)
                    if !text.isEmpty { blocks.append(Block(kind: .codeFence, text: text)) }
                }
                continue
            }

            if let closing = mathFence {
                current.append(line)
                if stripped == closing || stripped.hasSuffix(closing) {
                    mathFence = nil
                    let text = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    current.removeAll(keepingCapacity: true)
                    if !text.isEmpty { blocks.append(Block(kind: .mathBlock, text: text)) }
                }
                continue
            }

            if stripped.isEmpty {
                flushCurrent()
                continue
            }

            if let opened = openingFence(stripped) {
                flushCurrent()
                fenceMarker = opened
                current.append(line)
                continue
            }

            if stripped == "$$" || (stripped.hasPrefix("$$") && !stripped.dropFirst(2).contains("$$")) {
                flushCurrent()
                mathFence = "$$"
                current.append(line)
                continue
            }
            if stripped == "\\[" || (stripped.hasPrefix("\\[") && !stripped.contains("\\]")) {
                flushCurrent()
                mathFence = "\\]"
                current.append(line)
                continue
            }

            if isThematicBreak(stripped) {
                flushCurrent()
                blocks.append(Block(kind: .thematicBreak, text: stripped))
                continue
            }

            if isHeading(stripped) {
                flushCurrent()
                blocks.append(Block(kind: .heading, text: line))
                continue
            }

            current.append(line)
        }
        flushCurrent()
        return blocks
    }

    private static func groupBlocks(_ raw: [Block]) -> [String] {
        // Pass 1: merge consecutive loose list blocks and consecutive standalone image blocks.
        var merged: [Block] = []
        for block in raw {
            if let last = merged.last {
                if last.kind == .list && block.kind == .list {
                    merged[merged.count - 1].text += "\n\n" + block.text
                    continue
                }
                if last.kind == .image && block.kind == .image {
                    merged[merged.count - 1].text += "\n\n" + block.text
                    continue
                }
                if block.kind == .citationOnly && last.kind != .thematicBreak {
                    merged[merged.count - 1].text += "\n\n" + block.text
                    continue
                }
            }
            merged.append(block)
        }

        // Pass 2: bind headings and colon lead-ins forward onto their following structured block,
        // and use standalone thematic breaks as bubble separators.
        var bubbles: [String] = []
        var index = 0
        while index < merged.count {
            let current = merged[index]
            if current.kind == .thematicBreak {
                index += 1
                continue
            }

            var combined = current.text
            var tailKind = current.kind
            while index + 1 < merged.count {
                let next = merged[index + 1]
                if next.kind == .thematicBreak { break }
                let shouldBindForward = tailKind == .heading
                    || (tailKind == .paragraph && endsWithColonLeadIn(combined) && isStructuredFollowUp(next.kind))
                guard shouldBindForward else { break }
                combined += "\n\n" + next.text
                tailKind = next.kind
                index += 1
            }

            bubbles.append(combined)
            index += 1
        }
        return bubbles
    }

    private static func isStructuredFollowUp(_ kind: BlockKind) -> Bool {
        switch kind {
        case .list, .codeFence, .table, .blockquote, .image, .mathBlock:
            true
        case .paragraph, .heading, .citationOnly, .thematicBreak:
            false
        }
    }

    private static func endsWithColonLeadIn(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        return last == ":" || last == "："
    }

    private static func classify(_ text: String) -> BlockKind {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return .paragraph }

        if lines.count == 1 && isThematicBreak(first) { return .thematicBreak }
        if lines.count == 1 && isHeading(first) { return .heading }
        if openingFence(first) != nil { return .codeFence }
        if (first.hasPrefix("$$") && lines.last?.hasSuffix("$$") == true)
            || (first.hasPrefix("\\[") && lines.last?.hasSuffix("\\]") == true) {
            return .mathBlock
        }
        if lines.allSatisfy({ $0.hasPrefix(">") }) { return .blockquote }
        if isTable(lines) { return .table }
        if lines.allSatisfy(isStandaloneImageLine) { return .image }
        if lines.allSatisfy(isCitationOnlyLine) { return .citationOnly }
        if isListLine(first) { return .list }
        return .paragraph
    }

    private static func isHeading(_ trimmedLine: String) -> Bool {
        let hashes = trimmedLine.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return false }
        let rest = trimmedLine.dropFirst(hashes)
        return rest.first == " " || rest.first == "\t"
    }

    private static func isThematicBreak(_ trimmedLine: String) -> Bool {
        let compact = trimmedLine.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, first == "-" || first == "*" || first == "_" else {
            return false
        }
        return compact.allSatisfy { $0 == first }
    }

    private static func isListLine(_ trimmedLine: String) -> Bool {
        if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") || trimmedLine.hasPrefix("+ ") {
            return true
        }
        let digits = trimmedLine.prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty else { return false }
        let rest = trimmedLine.dropFirst(digits.count)
        return rest.hasPrefix(". ") || rest.hasPrefix(") ")
    }

    private static func isTable(_ lines: [String]) -> Bool {
        guard lines.count >= 2 else { return false }
        let separator = lines[1]
        let allowed = CharacterSet(charactersIn: "|-: ")
        let hasPipe = lines[0].contains("|") && separator.contains("|")
        let hasDash = separator.contains("-")
        let isSep = separator.unicodeScalars.allSatisfy { allowed.contains($0) }
        return hasPipe && hasDash && isSep
    }

    private static func isStandaloneImageLine(_ trimmedLine: String) -> Bool {
        guard trimmedLine.hasPrefix("![") else { return false }
        guard let closeBracket = trimmedLine.range(of: "](") else { return false }
        return trimmedLine[closeBracket.upperBound...].hasSuffix(")")
    }

    private static func isCitationOnlyLine(_ trimmedLine: String) -> Bool {
        // Matches one or more Markdown links like `[来源](https://...)` separated only by spaces or punctuation.
        let pattern = #"^(?:\[[^\]\n]+\]\(https?://[^\s\)]+\)[\s、,，;；/]*)+$"#
        return trimmedLine.range(of: pattern, options: .regularExpression) != nil
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
