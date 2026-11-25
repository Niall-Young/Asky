import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import MarkdownUI
import Observation
import QuartzCore
import SwiftUI
import Theme
import ToolService

enum ShareCardScope: String, CaseIterable, Identifiable {
    case fullTurn
    case singleBubble

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullTurn: NSLocalizedString("整轮回复", comment: "")
        case .singleBubble: NSLocalizedString("仅此条", comment: "")
        }
    }
}

enum ChatShareTurnText {
    /// Combines multiple assistant reply bubbles from the same response turn into one cohesive shareable text.
    /// Returns `nil` when the turn contains only a single assistant bubble.
    static func merged(from items: [ChatItem]) -> String? {
        let parts = items
            .filter { $0.kind == .assistant }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        return parts.joined(separator: "\n\n")
    }
}

enum ShareCardAppearance: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    init(colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }

    var colorScheme: ColorScheme {
        self == .dark ? .dark : .light
    }

    var assetName: String {
        self == .dark ? "ShareCardBackdropDark" : "ShareCardBackdropLight"
    }

    var title: String {
        switch self {
        case .light: NSLocalizedString("浅色", comment: "")
        case .dark: NSLocalizedString("深色", comment: "")
        }
    }
}

@MainActor
final class ShareCardBackdropCache {
    static let shared = ShareCardBackdropCache()

    struct Pair {
        let sharp: NSImage
        let blurred: NSImage
    }

    private var cache: [ShareCardAppearance: Pair] = [:]
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func backdrop(for appearance: ShareCardAppearance) -> Pair {
        if let cached = cache[appearance] { return cached }
        let sharp = NSImage(named: appearance.assetName) ?? fallbackBackdrop(for: appearance)
        let blurred = blur(sharp, radius: 28, isDark: appearance == .dark) ?? sharp
        let pair = Pair(sharp: sharp, blurred: blurred)
        cache[appearance] = pair
        return pair
    }

    private func blur(_ image: NSImage, radius: Double, isDark: Bool) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cgImage)
        let extent = input.extent

        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = input.clampedToExtent()
        blurFilter.radius = Float(radius)
        guard let blurred = blurFilter.outputImage?.cropped(to: extent) else { return nil }

        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = blurred
        colorControls.saturation = 1.48
        colorControls.brightness = isDark ? 0.04 : 0.03
        colorControls.contrast = 1.06

        let finalImage = (colorControls.outputImage ?? blurred).cropped(to: extent)
        guard let outputCG = ciContext.createCGImage(finalImage, from: extent) else { return nil }
        return NSImage(cgImage: outputCG, size: image.size)
    }

    private func fallbackBackdrop(for appearance: ShareCardAppearance) -> NSImage {
        let size = NSSize(width: 1200, height: 1500)
        return NSImage(size: size, flipped: false) { rect in
            let colors: [NSColor] = appearance == .dark
                ? [
                    NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.22, alpha: 1),
                    NSColor(calibratedRed: 0.12, green: 0.20, blue: 0.34, alpha: 1),
                    NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.16, alpha: 1),
                ]
                : [
                    NSColor(calibratedRed: 0.56, green: 0.74, blue: 0.90, alpha: 1),
                    NSColor(calibratedRed: 0.85, green: 0.82, blue: 0.76, alpha: 1),
                    NSColor(calibratedRed: 0.48, green: 0.64, blue: 0.72, alpha: 1),
                ]
            if let gradient = NSGradient(colors: colors) {
                gradient.draw(in: rect, angle: -90)
            }
            return true
        }
    }
}

struct ChatShareCardContent: View {
    let text: String
    let appearance: ShareCardAppearance
    var images: [URL: CGImage] = [:]
    var isLoadingImages: Bool = false

    private var isDark: Bool { appearance == .dark }

    private var primaryTextColor: Color {
        isDark ? Color(white: 0.95) : Color(white: 0.11)
    }

    private var subtleTextColor: Color {
        isDark ? Color(white: 0.72) : Color(white: 0.38)
    }

    private var brandTextColor: Color {
        isDark ? Color(white: 0.96) : Color(white: 0.12)
    }

    private var codeBackgroundColor: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    private var borderColor: Color {
        isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)
    }

    private var formattedMarkdown: String {
        Self.formattedMarkdown(from: text)
    }

    static func formattedMarkdown(from text: String) -> String {
        let parts = ChatFormParser.parse(text, streaming: false)
        return parts.map { part in
            switch part.content {
            case .markdown(let body):
                return stripCitations(from: body)
            case .form(let form):
                var lines: [String] = []
                if !form.title.isEmpty { lines.append("**\(form.title)**") }
                for field in form.fields {
                    lines.append("- \(field.label)")
                }
                return lines.joined(separator: "\n")
            }
        }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n\n")
    }

    private enum InlineToken {
        case plain(String)
        case protected(String)
        case citation
    }

    private static let citationSeparators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "、,，;；/"))
    private static let trailingPunctuation: Set<Character> = Set("。，、；：！？.,;:!?）)】]}》」』”’|")
    private static let wrapperPairs: [(open: String, close: String)] = [
        ("（", "）"), ("(", ")"), ("【", "】"), ("[", "]"),
        ("**", "**"), ("__", "__"), ("*", "*"), ("_", "_")
    ]

    /// Removes non-clickable source/citation links from share-card Markdown while preserving
    /// normal descriptive links, images, inline code, fenced code blocks, and surrounding punctuation.
    static func stripCitations(from markdown: String) -> String {
        let canonical = MarkdownContent(markdown).renderMarkdown()
        let lines = canonical.components(separatedBy: "\n")
        var output: [String] = []
        var fence: (character: Character, count: Int)?
        var droppedAnyLine = false

        for line in lines {
            if let current = fence {
                output.append(line)
                if let marker = fenceMarker(in: line),
                   marker.character == current.character,
                   marker.count >= current.count,
                   marker.rest.trimmingCharacters(in: .whitespaces).isEmpty {
                    fence = nil
                }
                continue
            }

            if let marker = fenceMarker(in: line),
               !(marker.character == "`" && marker.rest.contains("`")) {
                fence = (marker.character, marker.count)
                output.append(line)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "<!-- end list -->" {
                droppedAnyLine = true
                continue
            }

            if !trimmed.isEmpty, ChatImageGalleryContent.source(in: trimmed) != nil {
                droppedAnyLine = true
                continue
            }

            let (cleaned, removedAny) = stripInlineCitations(from: line)
            if removedAny && isEmptyAfterCitationRemoval(cleaned) {
                droppedAnyLine = true
                continue
            }
            output.append(cleaned)
        }

        guard droppedAnyLine else {
            return output.joined(separator: "\n")
        }

        // Collapse duplicate blank lines introduced by dropping standalone source lines.
        var collapsed: [String] = []
        var inFence: (character: Character, count: Int)?
        for line in output {
            if let current = inFence {
                collapsed.append(line)
                if let marker = fenceMarker(in: line),
                   marker.character == current.character,
                   marker.count >= current.count,
                   marker.rest.trimmingCharacters(in: .whitespaces).isEmpty {
                    inFence = nil
                }
                continue
            }
            if let marker = fenceMarker(in: line),
               !(marker.character == "`" && marker.rest.contains("`")) {
                inFence = (marker.character, marker.count)
                collapsed.append(line)
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if collapsed.isEmpty || collapsed.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
                    continue
                }
                collapsed.append("")
            } else {
                collapsed.append(line)
            }
        }
        while collapsed.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            collapsed.removeLast()
        }
        return collapsed.joined(separator: "\n")
    }

    private static func fenceMarker(in line: String) -> (character: Character, count: Int, rest: Substring)? {
        var rest = line[...]
        while true {
            var spaces = 0
            while spaces < 3, rest.first == " " {
                rest = rest.dropFirst()
                spaces += 1
            }
            if rest.first == ">" {
                rest = rest.dropFirst()
                if rest.first == " " { rest = rest.dropFirst() }
            } else {
                break
            }
        }
        guard let first = rest.first, first == "`" || first == "~" else { return nil }
        let count = rest.prefix { $0 == first }.count
        guard count >= 3 else { return nil }
        return (first, count, rest.dropFirst(count))
    }

    private static func isEmptyAfterCitationRemoval(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        if stripped.isEmpty { return true }
        return stripped.allSatisfy { $0 == ">" || $0 == " " || $0 == "\t" }
    }

    private static func stripInlineCitations(from line: String) -> (String, Bool) {
        let rawTokens = tokenizeLine(line)
        guard rawTokens.contains(where: { if case .citation = $0 { return true }; return false }) else {
            return (line, false)
        }

        // 1 & 2. Merge adjacent citations (and citation-only separators) and strip empty enclosing wrappers
        //        (e.g. （[来源](url)）, ([1](url), [2](url)), **[来源](url)**) until fixed point.
        var tokens = rawTokens
        var changed = true
        while changed {
            changed = false

            var merged: [InlineToken] = []
            var idx = 0
            while idx < tokens.count {
                if case .citation = tokens[idx] {
                    if case .citation = merged.last {
                        changed = true
                        idx += 1
                        continue
                    }
                    merged.append(.citation)
                    idx += 1
                    continue
                }
                if case .plain(let text) = tokens[idx],
                   case .citation = merged.last,
                   idx + 1 < tokens.count,
                   case .citation = tokens[idx + 1],
                   text.trimmingCharacters(in: citationSeparators).isEmpty {
                    changed = true
                    idx += 1
                    continue
                }
                appendToken(tokens[idx], to: &merged)
                idx += 1
            }
            tokens = merged

            for i in tokens.indices {
                guard case .citation = tokens[i],
                      i > 0, i + 1 < tokens.count,
                      case .plain(let before) = tokens[i - 1],
                      case .plain(let after) = tokens[i + 1] else { continue }
                let trimmedBefore = trimTrailingHorizontalSpace(before)
                let trimmedAfter = trimLeadingHorizontalSpace(after)
                for pair in wrapperPairs where trimmedBefore.hasSuffix(pair.open) && trimmedAfter.hasPrefix(pair.close) {
                    tokens[i - 1] = .plain(String(trimmedBefore.dropLast(pair.open.count)))
                    tokens[i + 1] = .plain(String(trimmedAfter.dropFirst(pair.close.count)))
                    changed = true
                    break
                }
            }
            if changed {
                tokens.removeAll { token in
                    if case .plain(let text) = token { return text.isEmpty }
                    return false
                }
            }
        }

        // 3. Rejoin tokens while cleaning boundary whitespace around each removed citation.
        var result = ""
        var i = 0
        while i < tokens.count {
            switch tokens[i] {
            case .plain(let text), .protected(let text):
                result.append(text)
                i += 1
            case .citation:
                var nextPlainIndex: Int?
                if i + 1 < tokens.count, case .plain = tokens[i + 1] {
                    nextPlainIndex = i + 1
                }
                let nextChar = nextNonEmptyCharacter(in: tokens, startingAt: i + 1)
                let isAtLineEnd = nextChar == nil
                let isAtLineStart = result.trimmingCharacters(in: .whitespaces).isEmpty

                if isAtLineEnd {
                    result = trimTrailingHorizontalSpace(result)
                    if let nextIdx = nextPlainIndex {
                        tokens[nextIdx] = .plain("")
                    }
                } else if let nextChar, trailingPunctuation.contains(nextChar) {
                    result = trimTrailingHorizontalSpace(result)
                } else if isAtLineStart {
                    if let nextIdx = nextPlainIndex, case .plain(let nextText) = tokens[nextIdx] {
                        tokens[nextIdx] = .plain(trimLeadingHorizontalSpace(nextText))
                    }
                } else if endsWithHorizontalSpace(result),
                          let nextIdx = nextPlainIndex,
                          case .plain(let nextText) = tokens[nextIdx],
                          startsWithHorizontalSpace(nextText) {
                    tokens[nextIdx] = .plain(trimLeadingHorizontalSpace(nextText))
                }
                i += 1
            }
        }

        return (result, true)
    }

    private static func appendToken(_ token: InlineToken, to tokens: inout [InlineToken]) {
        if case .plain(let text) = token, case .plain(let previous) = tokens.last {
            tokens[tokens.count - 1] = .plain(previous + text)
        } else {
            tokens.append(token)
        }
    }

    private static func nextNonEmptyCharacter(in tokens: [InlineToken], startingAt start: Int) -> Character? {
        for idx in start..<tokens.count {
            switch tokens[idx] {
            case .plain(let text), .protected(let text):
                if let first = text.first { return first }
            case .citation:
                continue
            }
        }
        return nil
    }

    private static func endsWithHorizontalSpace(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return last == " " || last == "\t"
    }

    private static func startsWithHorizontalSpace(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        return first == " " || first == "\t"
    }

    private static func trimTrailingHorizontalSpace(_ text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex {
            let prev = text.index(before: end)
            if text[prev] == " " || text[prev] == "\t" {
                end = prev
            } else {
                break
            }
        }
        return String(text[..<end])
    }

    private static func trimLeadingHorizontalSpace(_ text: String) -> String {
        var start = text.startIndex
        while start < text.endIndex, text[start] == " " || text[start] == "\t" {
            start = text.index(after: start)
        }
        return String(text[start...])
    }

    private static func tokenizeLine(_ line: String) -> [InlineToken] {
        var tokens: [InlineToken] = []
        var plainBuffer = ""
        var idx = line.startIndex

        func flushPlain() {
            guard !plainBuffer.isEmpty else { return }
            appendToken(.plain(plainBuffer), to: &tokens)
            plainBuffer.removeAll(keepingCapacity: true)
        }

        while idx < line.endIndex {
            let ch = line[idx]

            // Backslash escape: keep escaped characters verbatim.
            if ch == "\\" {
                let next = line.index(after: idx)
                if next < line.endIndex {
                    let after = line.index(after: next)
                    flushPlain()
                    tokens.append(.protected(String(line[idx..<after])))
                    idx = after
                    continue
                }
            }

            // Inline code span: preserve verbatim.
            if ch == "`" {
                var endTicks = idx
                while endTicks < line.endIndex, line[endTicks] == "`" {
                    endTicks = line.index(after: endTicks)
                }
                let tickCount = line.distance(from: idx, to: endTicks)
                if let closingEnd = findClosingBackticks(in: line, from: endTicks, count: tickCount) {
                    flushPlain()
                    tokens.append(.protected(String(line[idx..<closingEnd])))
                    idx = closingEnd
                    continue
                }
                plainBuffer.append(contentsOf: line[idx..<endTicks])
                idx = endTicks
                continue
            }

            // Image syntax `![alt](dest)`: never treat as a citation link.
            if ch == "!" {
                let next = line.index(after: idx)
                if next < line.endIndex, line[next] == "[" {
                    if let parsed = parseInlineLink(in: line, from: next) {
                        flushPlain()
                        tokens.append(.protected(String(line[idx..<parsed.end])))
                        idx = parsed.end
                        continue
                    }
                    plainBuffer.append("![")
                    idx = line.index(after: next)
                    continue
                }
            }

            // Inline Markdown link `[label](destination)`.
            if ch == "[", let parsed = parseInlineLink(in: line, from: idx) {
                flushPlain()
                if isCitationLink(label: parsed.label, destination: parsed.destination) {
                    tokens.append(.citation)
                } else {
                    tokens.append(.protected(String(line[idx..<parsed.end])))
                }
                idx = parsed.end
                continue
            }

            plainBuffer.append(ch)
            idx = line.index(after: idx)
        }

        flushPlain()
        return tokens
    }

    private static func findClosingBackticks(in line: String, from start: String.Index, count: Int) -> String.Index? {
        var idx = start
        while idx < line.endIndex {
            if line[idx] == "`" {
                var end = idx
                while end < line.endIndex, line[end] == "`" {
                    end = line.index(after: end)
                }
                if line.distance(from: idx, to: end) == count {
                    return end
                }
                idx = end
            } else {
                idx = line.index(after: idx)
            }
        }
        return nil
    }

    private static func parseInlineLink(in line: String, from start: String.Index)
        -> (label: String, destination: String, end: String.Index)? {
        guard start < line.endIndex, line[start] == "[" else { return nil }
        var idx = line.index(after: start)
        var bracketDepth = 1
        var labelEnd: String.Index?

        while idx < line.endIndex {
            let ch = line[idx]
            if ch == "\\" {
                let next = line.index(after: idx)
                idx = next < line.endIndex ? line.index(after: next) : next
                continue
            }
            if ch == "[" {
                bracketDepth += 1
            } else if ch == "]" {
                bracketDepth -= 1
                if bracketDepth == 0 {
                    labelEnd = idx
                    break
                }
            }
            idx = line.index(after: idx)
        }

        guard let labelEnd else { return nil }
        let openParen = line.index(after: labelEnd)
        guard openParen < line.endIndex, line[openParen] == "(" else { return nil }

        var j = line.index(after: openParen)
        while j < line.endIndex, line[j] == " " || line[j] == "\t" {
            j = line.index(after: j)
        }

        let destination: String
        if j < line.endIndex, line[j] == "<" {
            let destStart = line.index(after: j)
            var scan = destStart
            var foundClose = false
            while scan < line.endIndex {
                if line[scan] == "\\" {
                    let next = line.index(after: scan)
                    scan = next < line.endIndex ? line.index(after: next) : next
                    continue
                }
                if line[scan] == ">" {
                    foundClose = true
                    break
                }
                scan = line.index(after: scan)
            }
            guard foundClose else { return nil }
            destination = String(line[destStart..<scan])
            j = line.index(after: scan)
        } else {
            let destStart = j
            var parenDepth = 0
            while j < line.endIndex {
                let ch = line[j]
                if ch == "\\" {
                    let next = line.index(after: j)
                    j = next < line.endIndex ? line.index(after: next) : next
                    continue
                }
                if ch == "(" {
                    parenDepth += 1
                } else if ch == ")" {
                    if parenDepth == 0 { break }
                    parenDepth -= 1
                } else if ch == " " || ch == "\t" {
                    break
                }
                j = line.index(after: j)
            }
            destination = String(line[destStart..<j])
        }

        while j < line.endIndex, line[j] == " " || line[j] == "\t" {
            j = line.index(after: j)
        }

        if j < line.endIndex, line[j] == "\"" || line[j] == "'" || line[j] == "(" {
            let closing: Character = line[j] == "(" ? ")" : line[j]
            j = line.index(after: j)
            var closedTitle = false
            while j < line.endIndex {
                if line[j] == "\\" {
                    let next = line.index(after: j)
                    j = next < line.endIndex ? line.index(after: next) : next
                    continue
                }
                if line[j] == closing {
                    closedTitle = true
                    j = line.index(after: j)
                    break
                }
                j = line.index(after: j)
            }
            guard closedTitle else { return nil }
            while j < line.endIndex, line[j] == " " || line[j] == "\t" {
                j = line.index(after: j)
            }
        }

        guard j < line.endIndex, line[j] == ")" else { return nil }
        let label = String(line[line.index(after: start)..<labelEnd])
        return (label, destination, line.index(after: j))
    }

    private static func isCitationLink(label: String, destination: String) -> Bool {
        let trimmedDest = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedDest), ChatImageService.supports(url) else { return false }
        let parsed = ChatInlineText.parsed(label)
        guard !parsed.runs.contains(where: { $0.imageURL != nil }) else { return false }
        let plain = String(parsed.characters)
        if ChatSourceTextView.isCitation(plain) { return true }
        let trimmed = plain.trimmingCharacters(in: CharacterSet(charactersIn: "[]【】()（） "))
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        let exactLabels = ["图片来源", "图源", "photo source", "image source", "credit"]
        if exactLabels.contains(lower) { return true }
        let prefixLabels = [
            "来源", "图片来源", "图源", "引用", "参考", "出处",
            "source", "photo source", "image source", "citation", "ref", "reference"
        ]
        return prefixLabels.contains { prefix in
            lower.hasPrefix(prefix + ":") || lower.hasPrefix(prefix + "：")
        }
    }

    /// Extracts all supported remote image URLs from share-card Markdown, ignoring fenced/inline code.
    static func imageURLs(in text: String) -> [URL] {
        imageURLs(inFormattedMarkdown: formattedMarkdown(from: text))
    }

    static func imageURLs(inFormattedMarkdown markdown: String) -> [URL] {
        let lines = markdown.components(separatedBy: "\n")
        var urls: [URL] = []
        var seen: Set<URL> = []
        var fence: (character: Character, count: Int)?

        for line in lines {
            if let current = fence {
                if let marker = fenceMarker(in: line),
                   marker.character == current.character,
                   marker.count >= current.count,
                   marker.rest.trimmingCharacters(in: .whitespaces).isEmpty {
                    fence = nil
                }
                continue
            }
            if let marker = fenceMarker(in: line),
               !(marker.character == "`" && marker.rest.contains("`")) {
                fence = (marker.character, marker.count)
                continue
            }
            guard line.contains("![") else { continue }
            let parsed = ChatInlineText.parsed(line)
            for run in parsed.runs {
                guard let url = run.imageURL,
                      ChatImageService.supports(url),
                      ChatMath.formula(url) == nil,
                      seen.insert(url).inserted else { continue }
                urls.append(url)
            }
        }
        return urls
    }

    private func visibleParts(from markdown: String) -> [ChatGalleryPart] {
        ChatImageGalleryContent.parts(markdown).compactMap { part in
            switch part {
            case .markdown(let body):
                return .markdown(body)
            case .images(let photos):
                if isLoadingImages {
                    return .images(photos)
                }
                let loaded = photos.filter { images[$0.url] != nil }
                return loaded.isEmpty ? nil : .images(loaded)
            }
        }
    }

    var body: some View {
        let parts = visibleParts(from: formattedMarkdown)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image("AskyLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                Text(verbatim: "Asky")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(brandTextColor)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    switch part {
                    case .markdown(let body):
                        markdownBlock(body)
                    case .images(let photos):
                        ShareCardImageGrid(
                            photos: photos,
                            images: images,
                            isLoading: isLoadingImages,
                            borderColor: borderColor,
                            placeholderColor: codeBackgroundColor
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func markdownBlock(_ content: String) -> some View {
        Markdown(content)
            .markdownTextStyle {
                FontSize(14)
                FontWeight(.regular)
                ForegroundColor(primaryTextColor)
            }
            .markdownTextStyle(\.strong) {
                FontWeight(.semibold)
            }
            .markdownTextStyle(\.code) {
                FontSize(12.5)
                FontFamilyVariant(.monospaced)
                BackgroundColor(codeBackgroundColor)
            }
            .markdownTextStyle(\.link) {
                ForegroundColor(isDark ? Color(red: 0.45, green: 0.72, blue: 1.0) : Color(red: 0.08, green: 0.42, blue: 0.85))
                UnderlineStyle(.single)
            }
            .markdownBlockStyle(\.heading1) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(15.5)
                        FontWeight(.semibold)
                        ForegroundColor(primaryTextColor)
                    }
                    .markdownMargin(top: 14, bottom: 6)
            }
            .markdownBlockStyle(\.heading2, body: sectionHeading)
            .markdownBlockStyle(\.heading3, body: sectionHeading)
            .markdownBlockStyle(\.heading4, body: sectionHeading)
            .markdownBlockStyle(\.heading5, body: sectionHeading)
            .markdownBlockStyle(\.heading6, body: sectionHeading)
            .markdownBlockStyle(\.paragraph) { configuration in
                configuration.label
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownMargin(top: 0, bottom: 10)
            }
            .markdownBlockStyle(\.listItem) { configuration in
                configuration.label
                    .markdownMargin(top: 6, bottom: 6)
            }
            .markdownBlockStyle(\.codeBlock) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(12)
                        FontFamilyVariant(.monospaced)
                        ForegroundColor(primaryTextColor)
                    }
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(codeBackgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 0.5)
                    }
                    .markdownMargin(top: 4, bottom: 12)
            }
            .markdownBlockStyle(\.blockquote) { configuration in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(subtleTextColor.opacity(0.45))
                        .frame(width: 3)
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(subtleTextColor)
                        }
                }
                .fixedSize(horizontal: false, vertical: true)
                .markdownMargin(top: 2, bottom: 11)
            }
            .markdownBlockStyle(\.table) { configuration in
                configuration.label
                    .markdownTableBorderStyle(.init(.allBorders, color: borderColor, width: 0.5))
                    .markdownTableBackgroundStyle(.alternatingRows(
                        Color.clear,
                        isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.025),
                        header: codeBackgroundColor
                    ))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 0.5)
                    }
                    .markdownMargin(top: 4, bottom: 12)
            }
            .markdownBlockStyle(\.tableCell) { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(12.5)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
            }
            .markdownBlockStyle(\.thematicBreak) {
                Rectangle()
                    .fill(borderColor)
                    .frame(height: 1)
                    .markdownMargin(top: 10, bottom: 10)
            }
            .markdownImageProvider(
                ShareCardMarkdownImageProvider(
                    images: images,
                    isLoading: isLoadingImages,
                    borderColor: borderColor,
                    placeholderColor: codeBackgroundColor
                )
            )
            .markdownInlineImageProvider(
                ShareCardInlineImageProvider(images: images)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeading(_ configuration: BlockConfiguration) -> some View {
        configuration.label
            .markdownTextStyle {
                FontSize(14)
                FontWeight(.semibold)
                ForegroundColor(primaryTextColor)
            }
            .markdownMargin(top: 14, bottom: 6)
    }
}

private struct ShareCardSingleImage: View {
    let cgImage: CGImage
    let maxHeight: CGFloat
    let cornerRadius: CGFloat
    let borderColor: Color

    var body: some View {
        let width = CGFloat(max(1, cgImage.width))
        let height = CGFloat(max(1, cgImage.height))
        let aspect = width / height
        let maxWidth = min(width, maxHeight * aspect)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        Image(decorative: cgImage, scale: 1.0)
            .resizable()
            .aspectRatio(aspect, contentMode: .fit)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: 0.5)
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
    }
}

private struct ShareCardImageGrid: View {
    let photos: [ChatGalleryImage]
    let images: [URL: CGImage]
    let isLoading: Bool
    let borderColor: Color
    let placeholderColor: Color

    var body: some View {
        if photos.count == 1, let photo = photos.first {
            if let cgImage = images[photo.url] {
                ShareCardSingleImage(
                    cgImage: cgImage,
                    maxHeight: 360,
                    cornerRadius: 12,
                    borderColor: borderColor
                )
            } else if isLoading {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                shape
                    .fill(placeholderColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 168)
                    .overlay {
                        ProgressView().controlSize(.small)
                    }
                    .overlay {
                        shape.strokeBorder(borderColor, lineWidth: 0.5)
                    }
            }
        } else if photos.count >= 2 {
            let columns = (photos.count == 2 || photos.count == 4) ? 2 : 3
            let rows = stride(from: 0, to: photos.count, by: columns).map {
                Array(photos[$0..<min($0 + columns, photos.count)])
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, photo in
                            tile(for: photo)
                        }
                        if row.count < columns {
                            ForEach(0..<(columns - row.count), id: \.self) { _ in
                                Color.clear.aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func tile(for photo: ChatGalleryImage) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let cgImage = images[photo.url] {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .scaledToFill()
                } else if isLoading {
                    shape
                        .fill(placeholderColor)
                        .overlay { ProgressView().controlSize(.small) }
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: 0.5)
            }
    }
}

private struct ShareCardMarkdownImageProvider: ImageProvider {
    let images: [URL: CGImage]
    let isLoading: Bool
    let borderColor: Color
    let placeholderColor: Color

    @ViewBuilder
    func makeImage(url: URL?) -> some View {
        if let url, let cgImage = images[url] {
            ShareCardSingleImage(
                cgImage: cgImage,
                maxHeight: 320,
                cornerRadius: 10,
                borderColor: borderColor
            )
        } else if isLoading {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            shape
                .fill(placeholderColor)
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .overlay { ProgressView().controlSize(.small) }
                .overlay { shape.strokeBorder(borderColor, lineWidth: 0.5) }
        } else {
            EmptyView()
        }
    }
}

private struct ShareCardInlineImageProvider: InlineImageProvider {
    let images: [URL: CGImage]

    func image(with url: URL, label: String) async throws -> Image {
        if let cgImage = images[url] {
            return await MainActor.run {
                let width = CGFloat(max(1, cgImage.width))
                let height = CGFloat(max(1, cgImage.height))
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 14 * width / height, height: 14))
                return Image(nsImage: nsImage)
            }
        }
        let data = try await ChatImageService.shared.imageData(from: url)
        guard let cgImage = ChatShareCardRenderer.decodeCGImage(from: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        return await MainActor.run {
            let width = CGFloat(max(1, cgImage.width))
            let height = CGFloat(max(1, cgImage.height))
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 14 * width / height, height: 14))
            return Image(nsImage: nsImage)
        }
    }
}

struct ChatShareCardView: View {
    static let canvasWidth: CGFloat = 600
    private static let outerHorizontalPadding: CGFloat = 36
    private static let outerVerticalPadding: CGFloat = 40
    private static let cardCornerRadius: CGFloat = 28

    let text: String
    let appearance: ShareCardAppearance
    var images: [URL: CGImage] = [:]

    private var isDark: Bool { appearance == .dark }
    private var backdrop: ShareCardBackdropCache.Pair { ShareCardBackdropCache.shared.backdrop(for: appearance) }

    private var glassTint: Color {
        isDark
            ? Color(red: 0.07, green: 0.09, blue: 0.14).opacity(0.36)
            : Color.white.opacity(0.46)
    }

    private var glassSheen: LinearGradient {
        if isDark {
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.18), location: 0.0),
                    .init(color: Color.white.opacity(0.05), location: 0.18),
                    .init(color: Color.white.opacity(0.01), location: 0.72),
                    .init(color: Color.white.opacity(0.06), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.42), location: 0.0),
                    .init(color: Color.white.opacity(0.12), location: 0.22),
                    .init(color: Color.white.opacity(0.04), location: 0.75),
                    .init(color: Color.white.opacity(0.18), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var glassBorder: LinearGradient {
        if isDark {
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.46), location: 0.0),
                    .init(color: Color.white.opacity(0.12), location: 0.35),
                    .init(color: Color.white.opacity(0.08), location: 0.68),
                    .init(color: Color.white.opacity(0.30), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.95), location: 0.0),
                    .init(color: Color.white.opacity(0.42), location: 0.35),
                    .init(color: Color.white.opacity(0.30), location: 0.68),
                    .init(color: Color.white.opacity(0.76), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var cardShadowColor: Color {
        isDark
            ? Color.black.opacity(0.24)
            : Color(red: 0.08, green: 0.14, blue: 0.24).opacity(0.08)
    }

    private var cardShadowRadius: CGFloat {
        isDark ? 18 : 16
    }

    private var cardShadowOffsetY: CGFloat {
        isDark ? 8 : 6
    }

    var body: some View {
        let outerH = Self.outerHorizontalPadding
        let outerV = Self.outerVerticalPadding
        let shape = RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)

        ZStack {
            GeometryReader { canvasProxy in
                Image(nsImage: backdrop.sharp)
                    .resizable()
                    .scaledToFill()
                    .frame(width: canvasProxy.size.width, height: canvasProxy.size.height)
                    .clipped()
            }

            ChatShareCardContent(text: text, appearance: appearance, images: images)
                .padding(.horizontal, 28)
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { cardProxy in
                        let canvasWidth = cardProxy.size.width + outerH * 2
                        let canvasHeight = cardProxy.size.height + outerV * 2
                        Image(nsImage: backdrop.blurred)
                            .resizable()
                            .scaledToFill()
                            .frame(width: canvasWidth, height: canvasHeight)
                            .clipped()
                            .offset(x: -outerH, y: -outerV)
                            .frame(width: cardProxy.size.width, height: cardProxy.size.height, alignment: .topLeading)
                    }
                    .overlay(glassTint)
                    .overlay(glassSheen)
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(glassBorder, lineWidth: 1)
                    }
                    .compositingGroup()
                    .shadow(color: cardShadowColor, radius: cardShadowRadius, x: 0, y: cardShadowOffsetY)
                }
                .padding(.horizontal, outerH)
                .padding(.vertical, outerV)
        }
        .frame(width: Self.canvasWidth)
        .fixedSize(horizontal: false, vertical: true)
        .clipped()
        .environment(\.colorScheme, appearance.colorScheme)
    }
}

@MainActor
enum ChatShareCardRenderer {
    nonisolated static func decodeCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary),
              image.width > 0, image.height > 0 else {
            return nil
        }
        return image
    }

    static func loadImages(
        for text: String,
        existing: [URL: CGImage] = [:],
        timeout: Duration = .seconds(8),
        fetchData: @escaping @Sendable (URL) async throws -> Data = { try await ChatImageService.shared.imageData(from: $0) }
    ) async -> [URL: CGImage] {
        let urls = ChatShareCardContent.imageURLs(in: text)
        guard !urls.isEmpty else { return existing }
        let missing = urls.filter { existing[$0] == nil }
        guard !missing.isEmpty else { return existing }

        let fetched: [URL: CGImage] = await withTaskGroup(of: (URL?, CGImage?).self) { group in
            group.addTask {
                try? await Task.sleep(for: timeout)
                return (nil, nil)
            }
            for url in missing {
                group.addTask {
                    guard let data = try? await fetchData(url),
                          let image = decodeCGImage(from: data) else {
                        return (url, nil)
                    }
                    return (url, image)
                }
            }

            var loaded: [URL: CGImage] = [:]
            var completed = 0
            for await (url, image) in group {
                guard let url else {
                    group.cancelAll()
                    break
                }
                completed += 1
                if let image {
                    loaded[url] = image
                }
                if completed == missing.count {
                    group.cancelAll()
                    break
                }
            }
            return loaded
        }

        guard !fetched.isEmpty else { return existing }
        var merged = existing
        for (url, image) in fetched {
            merged[url] = image
        }
        return merged
    }

    static func renderPNG(
        text: String,
        appearance: ShareCardAppearance,
        images: [URL: CGImage] = [:],
        scale: CGFloat = 2.0
    ) -> Data? {
        let view = ChatShareCardView(text: text, appearance: appearance, images: images)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: ChatShareCardView.canvasWidth, height: nil)
        guard let cgImage = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    static func renderPNGLoadingImages(
        text: String,
        appearance: ShareCardAppearance,
        existingImages: [URL: CGImage] = [:],
        timeout: Duration = .seconds(8),
        scale: CGFloat = 2.0,
        fetchData: @escaping @Sendable (URL) async throws -> Data = { try await ChatImageService.shared.imageData(from: $0) }
    ) async -> Data? {
        let images = await loadImages(for: text, existing: existingImages, timeout: timeout, fetchData: fetchData)
        return renderPNG(text: text, appearance: appearance, images: images, scale: scale)
    }
}

@MainActor @Observable
private final class ChatShareEntranceState {
    var isPresented: Bool

    init(isPresented: Bool = false) {
        self.isPresented = isPresented
    }
}

/// Display-link driven window entrance: combines a fast ease-out alpha reveal
/// with a gentle upward spring while keeping the Spotlight window size fixed.
@MainActor
private final class ShareWindowEntranceAnimator: NSObject {
    private static let riseDistance: CGFloat = 16
    private static let fadeDuration: Double = 0.16
    private static let reduceMotionFadeDuration: Double = 0.15
    private static let springResponse: Double = 0.30
    private static let springDamping: Double = 0.88

    private weak var window: NSWindow?
    private var link: CADisplayLink?
    private var startTime: CFTimeInterval?
    private var targetOrigin: NSPoint = .zero
    private var targetAlpha: CGFloat = 1
    private var startOffsetY: CGFloat = 0
    private var reduceMotion = false
    private var allowPositionUpdates = true
    private(set) var isUpdatingFrame = false

    func start(window: NSWindow, targetOrigin: NSPoint, targetAlpha: CGFloat, reduceMotion: Bool) {
        stop()
        self.window = window
        self.targetOrigin = targetOrigin
        self.targetAlpha = targetAlpha
        self.reduceMotion = reduceMotion
        self.allowPositionUpdates = !reduceMotion
        self.startOffsetY = reduceMotion ? 0 : -Self.riseDistance

        window.alphaValue = 0
        if allowPositionUpdates {
            setOrigin(NSPoint(x: targetOrigin.x, y: targetOrigin.y + startOffsetY), on: window)
        } else {
            setOrigin(targetOrigin, on: window)
        }

        let link = window.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func cancelPositionMotion() {
        allowPositionUpdates = false
    }

    func stop() {
        link?.invalidate()
        link = nil
        startTime = nil
        window = nil
        allowPositionUpdates = true
    }

    private func setOrigin(_ origin: NSPoint, on window: NSWindow) {
        isUpdatingFrame = true
        window.setFrameOrigin(origin)
        isUpdatingFrame = false
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let window, window.isVisible else {
            stop()
            return
        }
        let start = startTime ?? link.timestamp
        startTime = start
        let t = max(0, link.targetTimestamp - start)

        if reduceMotion {
            let u = min(1.0, t / Self.reduceMotionFadeDuration)
            let eased = 1.0 - pow(1.0 - u, 2)
            window.alphaValue = targetAlpha * CGFloat(eased)
            if u >= 1.0 {
                window.alphaValue = targetAlpha
                stop()
            }
            return
        }

        let fadeProgress = min(1.0, t / Self.fadeDuration)
        let alphaEased = 1.0 - pow(1.0 - fadeProgress, 3)
        window.alphaValue = targetAlpha * CGFloat(alphaEased)

        let omega = 2.0 * Double.pi / Self.springResponse
        let decay = Self.springDamping * omega
        let wd = omega * (1.0 - Self.springDamping * Self.springDamping).squareRoot()
        let springProgress = 1.0 - exp(-decay * t) * (cos(wd * t) + (decay / wd) * sin(wd * t))
        let remaining = abs(1.0 - springProgress) * abs(Double(startOffsetY))
        let settled = t > 1.2 || (fadeProgress >= 1.0 && t > Self.springResponse && remaining < 0.01)

        if allowPositionUpdates {
            if settled {
                setOrigin(targetOrigin, on: window)
            } else {
                let scale = max(1.0, Double(window.backingScaleFactor))
                let rawY = Double(targetOrigin.y) + Double(startOffsetY) * (1.0 - springProgress)
                let alignedY = (rawY * scale).rounded() / scale
                setOrigin(NSPoint(x: targetOrigin.x, y: CGFloat(alignedY)), on: window)
            }
        }

        if settled {
            window.alphaValue = targetAlpha
            stop()
        }
    }
}

@MainActor
final class ChatShareWindowController: NSWindowController, NSWindowDelegate {
    static let shared = ChatShareWindowController()

    private static let cornerRadius: CGFloat = 24
    private let presentation = WindowPresentation()
    private let outsideClickDismissal = OutsideClickDismissal()
    private let entranceAnimator = ShareWindowEntranceAnimator()
    private var entranceState: ChatShareEntranceState?
    private var autoDismissSuspensionCount = 0
    private var shareCoordinator: SystemShareCoordinator?

    private init() { super.init(window: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var isAutoDismissSuspended: Bool {
        autoDismissSuspensionCount > 0 || window?.attachedSheet != nil
            || AppDialogPresenter.shared.isPresenting(in: window)
    }

    func show(text: String, fullTurnText: String? = nil, colorScheme: ColorScheme) {
        shareCoordinator?.cancel()
        shareCoordinator = nil
        autoDismissSuspensionCount = 0
        entranceAnimator.stop()

        let level = NSApp.keyWindow?.level ?? .normal
        let window = self.window ?? makeWindow()
        let wasVisible = window.isVisible
        if !wasVisible {
            window.alphaValue = 1
            window.center()
        }
        let targetOrigin = window.frame.origin
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let entrance = ChatShareEntranceState(isPresented: wasVisible || reduceMotion)
        entranceState = entrance

        let normalizedFullTurn: String? = fullTurnText.flatMap { candidate in
            let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedSingle = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedCandidate.isEmpty, trimmedCandidate != trimmedSingle else { return nil }
            return trimmedCandidate
        }

        window.title = NSLocalizedString("分享回复", comment: "")
        let content = ChatSharePreviewSheet(
            text: text,
            fullTurnText: normalizedFullTurn,
            initialAppearance: ShareCardAppearance(colorScheme: colorScheme),
            entrance: entrance,
            windowProvider: { [weak window] in window },
            suspendAutoDismiss: { [weak self] in
                self?.suspendAutoDismiss() ?? {}
            },
            presentSystemShare: { [weak self] url, anchor in
                self?.presentSystemShare(url: url, anchor: anchor)
            },
            close: { [weak self] in
                self?.dismiss()
            }
        )
        let host = NSHostingView(rootView: content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .windowSurfaceBackground(in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .circular))
            .ignoresSafeArea())
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: window.contentRect(forFrameRect: window.frame).size)
        window.contentView = WindowSurface.glassContentView(host, cornerRadius: Self.cornerRadius)
        if let surface = window.contentView {
            WindowSurface.updateCorners(of: surface, radius: Self.cornerRadius, circular: true)
        }
        if !wasVisible {
            presentation.show(window, level: level) { [weak self] revealedWindow, targetAlpha in
                self?.beginEntrance(
                    window: revealedWindow,
                    targetOrigin: targetOrigin,
                    targetAlpha: targetAlpha,
                    entrance: entrance
                )
            }
        } else {
            window.alphaValue = 1
            presentation.show(window, level: level)
        }
        updateOutsideClickDismissal()
    }

    private func beginEntrance(
        window: NSWindow,
        targetOrigin: NSPoint,
        targetAlpha: CGFloat,
        entrance: ChatShareEntranceState
    ) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        entranceAnimator.start(
            window: window,
            targetOrigin: targetOrigin,
            targetAlpha: targetAlpha,
            reduceMotion: reduceMotion
        )
        guard !reduceMotion else {
            entrance.isPresented = true
            return
        }
        DispatchQueue.main.async { [weak self, weak entrance] in
            guard let self, let entrance, self.entranceState === entrance else { return }
            entrance.isPresented = true
        }
    }

    func dismiss() {
        entranceAnimator.stop()
        entranceState = nil
        outsideClickDismissal.hide()
        shareCoordinator?.cancel()
        shareCoordinator = nil
        autoDismissSuspensionCount = 0
        guard let window else { return }
        let shouldClose = window.isVisible || window.contentView != nil
        window.orderOut(nil)
        window.alphaValue = 1
        if shouldClose {
            window.close()
        }
        window.contentView = nil
    }

    func suspendAutoDismiss() -> () -> Void {
        autoDismissSuspensionCount += 1
        updateOutsideClickDismissal()
        var active = true
        return { [weak self] in
            guard active else { return }
            active = false
            guard let self else { return }
            self.autoDismissSuspensionCount = max(0, self.autoDismissSuspensionCount - 1)
            self.updateOutsideClickDismissal()
        }
    }

    func windowWillMove(_ notification: Notification) {
        if !entranceAnimator.isUpdatingFrame {
            entranceAnimator.cancelPositionMotion()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window, window.isVisible, !isAutoDismissSuspended else { return }
        dismiss()
    }

    func windowWillClose(_ notification: Notification) {
        entranceAnimator.stop()
        entranceState = nil
        outsideClickDismissal.hide()
        shareCoordinator?.cancel()
        shareCoordinator = nil
        autoDismissSuspensionCount = 0
        window?.alphaValue = 1
        window?.contentView = nil
    }

    private func updateOutsideClickDismissal() {
        guard let window, window.isVisible, !isAutoDismissSuspended else {
            outsideClickDismissal.hide()
            return
        }
        outsideClickDismissal.show(contains: { [weak self] point in
            guard let self, let window = self.window else { return false }
            if self.isAutoDismissSuspended { return true }
            return window.isVisible && window.frame.contains(point)
        }, dismiss: { [weak self] in
            self?.dismiss()
        })
    }

    private func presentSystemShare(url: URL, anchor: NSView) {
        shareCoordinator?.cancel()
        let resume = suspendAutoDismiss()
        var coordinator: SystemShareCoordinator?
        let created = SystemShareCoordinator(
            sourceWindow: window,
            onFinish: { [weak self] cancelled in
                resume()
                guard let self else { return }
                if self.shareCoordinator === coordinator {
                    self.shareCoordinator = nil
                }
                if cancelled {
                    Task { @MainActor [weak self] in
                        guard let self, let window = self.window,
                              window.isVisible, !window.isKeyWindow, !self.isAutoDismissSuspended else { return }
                        self.dismiss()
                    }
                }
            }
        )
        coordinator = created
        shareCoordinator = created
        created.present(items: [url], relativeTo: anchor.bounds, of: anchor)
    }

    private func makeWindow() -> NSWindow {
        let window = ChatShareWindow(
            contentRect: NSRect(x: 0, y: 0, width: 448, height: 516),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.center()
        self.window = window
        return window
    }
}

@MainActor
private final class SystemShareCoordinator: NSObject, @MainActor NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    private weak var sourceWindow: NSWindow?
    private var onFinish: ((_ cancelled: Bool) -> Void)?
    private var fallbackTask: Task<Void, Never>?
    private var isPresentingService = false

    init(sourceWindow: NSWindow?, onFinish: @escaping (_ cancelled: Bool) -> Void) {
        self.sourceWindow = sourceWindow
        self.onFinish = onFinish
    }

    func present(items: [Any], relativeTo rect: NSRect, of view: NSView) {
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = self
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    func cancel() {
        complete(cancelled: false)
    }

    private func complete(cancelled: Bool) {
        fallbackTask?.cancel()
        fallbackTask = nil
        isPresentingService = false
        let finish = onFinish
        onFinish = nil
        finish?(cancelled)
    }

    nonisolated func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                                          delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? {
        MainActor.assumeIsolated { self }
    }

    nonisolated func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                                          didChoose service: NSSharingService?) {
        let choseService = service != nil
        MainActor.assumeIsolated {
            guard choseService else {
                complete(cancelled: true)
                return
            }
            fallbackTask?.cancel()
            fallbackTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                guard let self, !Task.isCancelled, !self.isPresentingService else { return }
                self.complete(cancelled: false)
            }
        }
    }

    func sharingService(_ sharingService: NSSharingService,
                        sourceWindowForShareItems items: [Any],
                        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        sourceWindow
    }

    func sharingService(_ sharingService: NSSharingService, willShareItems items: [Any]) {
        isPresentingService = true
        fallbackTask?.cancel()
        fallbackTask = nil
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        complete(cancelled: false)
    }

    func sharingService(_ sharingService: NSSharingService,
                        didFailToShareItems items: [Any],
                        error: any Error) {
        complete(cancelled: false)
    }
}

private final class ChatShareWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

private struct ChatSharePreviewSheet: View {
    private static let modalWidth: CGFloat = 448
    private static let modalHeight: CGFloat = 516
    private static let cardHorizontalInset: CGFloat = 24
    private static let maxCardHeight: CGFloat = 310
    private static let bottomFadeHeight: CGFloat = 78

    let text: String
    let fullTurnText: String?
    let entrance: ChatShareEntranceState
    let windowProvider: () -> NSWindow?
    let suspendAutoDismiss: () -> () -> Void
    let presentSystemShareAction: (URL, NSView) -> Void
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appearance: ShareCardAppearance
    @State private var scope: ShareCardScope
    @State private var cardHeight: CGFloat = 0
    @State private var copied = false
    @State private var saved = false
    @State private var errorMessage: String?
    @State private var resumeErrorSuspension: (() -> Void)?
    @State private var shareAnchor = ShareAnchorBox()
    @State private var resolvedImages: [URL: CGImage] = [:]
    @State private var completedImageLoadTexts: Set<String> = []
    @State private var isLoadingImages = false
    @State private var isExporting = false
    @State private var exportTask: Task<Void, Never>?

    init(
        text: String,
        fullTurnText: String? = nil,
        initialAppearance: ShareCardAppearance,
        entrance: ChatShareEntranceState,
        windowProvider: @escaping () -> NSWindow?,
        suspendAutoDismiss: @escaping () -> () -> Void,
        presentSystemShare: @escaping (URL, NSView) -> Void,
        close: @escaping () -> Void
    ) {
        self.text = text
        self.fullTurnText = fullTurnText
        self.entrance = entrance
        self.windowProvider = windowProvider
        self.suspendAutoDismiss = suspendAutoDismiss
        self.presentSystemShareAction = presentSystemShare
        self.close = close
        _appearance = State(initialValue: initialAppearance)
        _scope = State(initialValue: fullTurnText != nil ? .fullTurn : .singleBubble)
    }

    private var activeText: String {
        scope == .fullTurn ? (fullTurnText ?? text) : text
    }

    private var isDark: Bool { appearance == .dark }
    private var revealed: Bool { entrance.isPresented || reduceMotion }
    private var backdrop: ShareCardBackdropCache.Pair { ShareCardBackdropCache.shared.backdrop(for: appearance) }
    private var isOverflowing: Bool { cardHeight > Self.maxCardHeight }
    private var visibleCardHeight: CGFloat {
        cardHeight > 0 ? min(cardHeight, Self.maxCardHeight) : Self.maxCardHeight
    }

    private var chromeTextColor: Color {
        isDark ? Color.white.opacity(0.94) : Color(white: 0.12)
    }

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        ZStack {
            // Full-bleed scenic landscape as the modal's own backdrop.
            Image(nsImage: backdrop.sharp)
                .resizable()
                .scaledToFill()
                .frame(width: Self.modalWidth, height: Self.modalHeight)
                .scaleEffect(revealed ? 1.0 : 1.055)
                .clipped()
                .animation(reduceMotion ? nil : .easeOut(duration: 0.34), value: revealed)

            // Subtle top & bottom scrim so floating title and labels stay legible in both appearances.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        (isDark ? Color.black : Color.white).opacity(isDark ? 0.30 : 0.22),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [
                        .clear,
                        (isDark ? Color.black : Color.white).opacity(isDark ? 0.38 : 0.32)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 124)
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    HStack(spacing: 0) {
                        Text(NSLocalizedString("分享回复", comment: ""))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(chromeTextColor)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .contentShape(.rect)
                    .background(WindowDragArea())

                    if fullTurnText != nil {
                        ShareScopeToggle(selection: $scope, isDark: isDark, reduceMotion: reduceMotion)
                    }

                    Button(action: close) {
                        Image(mingCute: "xmark", size: 12.5)
                            .foregroundStyle(chromeTextColor.opacity(0.92))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(ShareGlassCircleButtonStyle())
                    .accessibilityLabel(NSLocalizedString("关闭", comment: ""))
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 6)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: revealed)

                Spacer(minLength: 0)

                ChatShareCardContent(
                    text: activeText,
                    appearance: appearance,
                    images: resolvedImages,
                    isLoadingImages: isLoadingImages
                )
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
                    .frame(width: Self.modalWidth - Self.cardHorizontalInset * 2, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                    .frame(width: Self.modalWidth - Self.cardHorizontalInset * 2, height: visibleCardHeight, alignment: .top)
                    .clipped()
                    .nativeGlassBackground(in: cardShape)
                    .mask {
                        VStack(spacing: 0) {
                            Color.black
                            if isOverflowing {
                                LinearGradient(
                                    stops: [
                                        .init(color: .black, location: 0.0),
                                        .init(color: .black.opacity(0.62), location: 0.38),
                                        .init(color: .black.opacity(0.18), location: 0.74),
                                        .init(color: .clear, location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: Self.bottomFadeHeight)
                            }
                        }
                    }
                    .scaleEffect(revealed ? 1 : 0.94, anchor: .center)
                    .offset(y: revealed ? 0 : 12)
                    .opacity(revealed ? 1 : 0)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84).delay(0.02),
                        value: revealed
                    )

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    ShareCircleActionButton(
                        title: copied ? NSLocalizedString("已复制", comment: "") : NSLocalizedString("复制图片", comment: ""),
                        mingCute: copied ? "checkmark" : "doc.on.clipboard",
                        isDark: isDark,
                        action: copyImage
                    )
                    .shareActionEntrance(revealed: revealed, index: 0, reduceMotion: reduceMotion)

                    ShareCircleActionButton(
                        title: saved ? NSLocalizedString("已保存图片", comment: "") : NSLocalizedString("保存图片", comment: ""),
                        mingCute: saved ? "checkmark" : "arrow.down.to.line",
                        isDark: isDark,
                        action: saveImage
                    )
                    .shareActionEntrance(revealed: revealed, index: 1, reduceMotion: reduceMotion)

                    ShareCircleActionButton(
                        title: NSLocalizedString("系统分享", comment: ""),
                        assetImage: "ChatShare",
                        isDark: isDark,
                        action: presentSystemShare
                    )
                    .background(ShareAnchorReader(box: shareAnchor).allowsHitTesting(false))
                    .shareActionEntrance(revealed: revealed, index: 2, reduceMotion: reduceMotion)

                    ShareCircleActionButton(
                        title: appearance.title,
                        assetImage: "ChatThemeToggle",
                        isDark: isDark,
                        action: {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                                appearance = appearance == .dark ? .light : .dark
                            }
                        }
                    )
                    .shareActionEntrance(revealed: revealed, index: 3, reduceMotion: reduceMotion)
                }
                .padding(.top, 14)
                .padding(.bottom, 22)
            }
        }
        .frame(width: Self.modalWidth, height: Self.modalHeight)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(isDark ? 0.16 : 0.45), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, appearance.colorScheme)
        .appDialog(
            NSLocalizedString("分享失败", comment: ""),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { presented in
                    if !presented {
                        errorMessage = nil
                        resumeErrorSuspension?()
                        resumeErrorSuspension = nil
                    }
                }
            ),
            message: errorMessage ?? "",
            buttons: [NSLocalizedString("好", comment: "")]
        )
        .onChange(of: activeText) { _, _ in
            exportTask?.cancel()
            exportTask = nil
            isExporting = false
        }
        .onDisappear {
            exportTask?.cancel()
            exportTask = nil
            isExporting = false
            resumeErrorSuspension?()
            resumeErrorSuspension = nil
        }
        .task(id: activeText) {
            let targetText = activeText
            let urls = ChatShareCardContent.imageURLs(in: targetText)
            guard !urls.isEmpty else {
                isLoadingImages = false
                completedImageLoadTexts.insert(targetText)
                return
            }
            let missing = urls.filter { resolvedImages[$0] == nil }
            guard !missing.isEmpty else {
                isLoadingImages = false
                completedImageLoadTexts.insert(targetText)
                return
            }
            isLoadingImages = true
            let loaded = await ChatShareCardRenderer.loadImages(for: targetText, existing: resolvedImages)
            guard !Task.isCancelled else { return }
            resolvedImages = loaded
            completedImageLoadTexts.insert(targetText)
            isLoadingImages = false
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .milliseconds(1400))
            copied = false
        }
        .task(id: saved) {
            guard saved else { return }
            try? await Task.sleep(for: .milliseconds(1600))
            saved = false
        }
    }

    private func showError(_ message: String) {
        if resumeErrorSuspension == nil {
            resumeErrorSuspension = suspendAutoDismiss()
        }
        errorMessage = message
    }

    private func withRenderedPNG(_ perform: @escaping @MainActor (Data) -> Void) {
        guard !isExporting else { return }
        let targetText = activeText
        let targetAppearance = appearance
        let urls = ChatShareCardContent.imageURLs(in: targetText)
        let needsImageLoad = !urls.isEmpty
            && !completedImageLoadTexts.contains(targetText)
            && urls.contains { resolvedImages[$0] == nil }

        if !needsImageLoad {
            guard let png = ChatShareCardRenderer.renderPNG(
                text: targetText,
                appearance: targetAppearance,
                images: resolvedImages
            ) else {
                showError(NSLocalizedString("生成分享图片失败", comment: ""))
                return
            }
            perform(png)
            return
        }

        isExporting = true
        exportTask?.cancel()
        exportTask = Task { @MainActor in
            defer {
                isExporting = false
                exportTask = nil
            }
            let loaded = await ChatShareCardRenderer.loadImages(for: targetText, existing: resolvedImages)
            guard !Task.isCancelled, activeText == targetText else { return }
            resolvedImages = loaded
            completedImageLoadTexts.insert(targetText)
            isLoadingImages = false
            guard let png = ChatShareCardRenderer.renderPNG(
                text: targetText,
                appearance: appearance,
                images: loaded
            ) else {
                showError(NSLocalizedString("生成分享图片失败", comment: ""))
                return
            }
            perform(png)
        }
    }

    private func presentSystemShare() {
        withRenderedPNG { png in
            guard let anchor = shareAnchor.view,
                  let url = try? ShareImageService.writeTemporarySharePNG(png) else {
                showError(NSLocalizedString("生成分享图片失败", comment: ""))
                return
            }
            presentSystemShareAction(url, anchor)
        }
    }

    private func copyImage() {
        withRenderedPNG { png in
            guard ShareImageService.copyPNG(png) else {
                showError(NSLocalizedString("生成分享图片失败", comment: ""))
                return
            }
            copied = true
        }
    }

    private func saveImage() {
        withRenderedPNG { png in
            let resume = suspendAutoDismiss()
            Task {
                defer { resume() }
                do {
                    if try await ShareImageService.savePNG(png, for: windowProvider()) != nil {
                        saved = true
                    }
                } catch {
                    showError(error.localizedDescription)
                }
            }
        }
    }
}

private extension View {
    func shareActionEntrance(revealed: Bool, index: Int, reduceMotion: Bool) -> some View {
        self
            .scaleEffect(revealed ? 1 : 0.88)
            .offset(y: revealed ? 0 : 10)
            .opacity(revealed ? 1 : 0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.80).delay(0.03 + Double(index) * 0.03),
                value: revealed
            )
    }
}

private struct ShareScopeToggle: View {
    @Binding var selection: ShareCardScope
    let isDark: Bool
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ShareCardScope.allCases) { option in
                let isSelected = selection == option
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                        selection = option
                    }
                } label: {
                    Text(option.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(
                            isSelected
                                ? (isDark ? Color.white.opacity(0.96) : Color(white: 0.10))
                                : (isDark ? Color.white.opacity(0.68) : Color(white: 0.24))
                        )
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(isDark ? Color.white.opacity(0.18) : Color.white.opacity(0.68))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("share-scope-\(option.rawValue)")
            }
        }
        .padding(3)
        .frame(height: 28)
        .nativeGlassBackground(in: Capsule())
    }
}

private struct ShareGlassCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .nativeGlassBackground(in: Circle(), interactive: true)
            .contentShape(.interaction, Circle())
            .glassPointerFeedback(pressed: configuration.isPressed, in: Circle())
    }
}

private struct ShareCircleActionButton: View {
    static let slotWidth: CGFloat = 76

    let title: String
    var mingCute: String? = nil
    var assetImage: String? = nil
    let isDark: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Group {
                    if let mingCute {
                        Image(mingCute: mingCute, size: 19)
                    } else if let assetImage {
                        Image(assetImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 19, height: 19)
                    }
                }
                .foregroundStyle(isDark ? Color.white.opacity(0.95) : Color(white: 0.12))
                .frame(width: 46, height: 46)
            }
            .buttonStyle(ShareGlassCircleButtonStyle())
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isDark ? Color.white.opacity(0.90) : Color(white: 0.14))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(width: Self.slotWidth)
    }
}

@MainActor
private final class ShareAnchorBox {
    weak var view: NSView?
}

private struct ShareAnchorReader: NSViewRepresentable {
    let box: ShareAnchorBox
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }
}
