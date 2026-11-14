import Foundation

/// Optional presentation metadata at the start of a completed assistant reply.
/// Ordinary emoji in prose and quoted/code examples remain ordinary message text.
public struct AgentReactionReply: Equatable, Sendable {
    public let emoji: String?
    public let text: String

    public init(_ source: String) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let opening = "<asky-reaction>"
        let closing = "</asky-reaction>"
        guard trimmed.hasPrefix(opening), let end = trimmed.range(of: closing) else {
            emoji = nil; text = source; return
        }
        let candidate = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: opening.count)..<end.lowerBound])
        let remainder = trimmed[end.upperBound...]
        guard Self.isEmoji(candidate), remainder.isEmpty || remainder.first?.isNewline == true else {
            emoji = nil; text = source; return
        }
        emoji = candidate
        text = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isEmoji(_ value: String) -> Bool {
        guard value.count == 1, value.utf8.count <= 64 else { return false }
        let scalars = value.unicodeScalars
        return scalars.contains { $0.properties.isEmojiPresentation }
            || (scalars.contains { $0.value == 0xFE0F || $0.value == 0x20E3 }
                && scalars.contains { $0.properties.isEmoji })
    }
}
