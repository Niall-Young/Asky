import Foundation
import Contracts

/// Locate image syntax without rewriting surrounding prose, reference definitions or code examples.
enum NativeReplyImages {
    struct Image {
        let url: URL
        let range: Range<String.Index>
    }

    static func images(in text: String) -> [Image] {
        let definitions = text.components(separatedBy: "\n").filter {
            $0.range(of: #"^ {0,3}\[[^\]]+\]:\s*\S+"#, options: .regularExpression) != nil
        }.joined(separator: "\n")
        var result: [Image] = []
        var index = text.startIndex
        func closing(_ start: String.Index, open: Character, close: Character) -> String.Index? {
            var depth = 0, cursor = start
            while cursor < text.endIndex {
                let ch = text[cursor]
                if ch == "\\" {
                    cursor = text.index(after: cursor)
                    if cursor < text.endIndex { cursor = text.index(after: cursor) }
                    continue
                }
                if ch == open { depth += 1 }
                if ch == close { depth -= 1; if depth == 0 { return cursor } }
                cursor = text.index(after: cursor)
            }
            return nil
        }
        while index < text.endIndex {
            let ch = text[index]
            if ch == "\\" {
                index = text.index(after: index)
                if index < text.endIndex { index = text.index(after: index) }
                continue
            }
            // Skip inline code and fenced blocks, including longer outer fences.
            if ch == "`" || ch == "~" {
                let end = text[index...].firstIndex(where: { $0 != ch }) ?? text.endIndex
                let marker = String(text[index..<end])
                if ch == "`" || marker.count >= 3,
                   let close = text.range(of: marker, range: end..<text.endIndex) {
                    index = close.upperBound; continue
                }
            }
            let next = text.index(after: index)
            guard ch == "!", next < text.endIndex, text[next] == "[",
                  let labelEnd = closing(next, open: "[", close: "]") else {
                index = next; continue
            }
            var end = text.index(after: labelEnd)
            if end < text.endIndex, text[end] == "(", let close = closing(end, open: "(", close: ")") {
                end = text.index(after: close)
            } else if end < text.endIndex, text[end] == "[", let close = closing(end, open: "[", close: "]") {
                end = text.index(after: close)
            }
            let fragment = String(text[index..<end]) + "\n\n" + definitions
            if let parsed = try? AttributedString(markdown: fragment),
               let url = parsed.runs.compactMap(\.imageURL).first {
                result.append(Image(url: url, range: index..<end))
            }
            index = end
        }
        return result
    }

    static func removing(_ rejected: Set<URL>, from text: String) -> String {
        var output = text
        var ranges: [Range<String.Index>] = []
        for image in images(in: text) where rejected.contains(image.url) {
            ranges.append(image.range)
            let lineStart = text[..<image.range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
            let lineEnd = text[image.range.upperBound...].firstIndex(of: "\n") ?? text.endIndex
            guard text[lineStart..<image.range.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty,
                  text[image.range.upperBound..<lineEnd].trimmingCharacters(in: .whitespaces).isEmpty,
                  let sourceStart = text[lineEnd...].firstIndex(where: { !$0.isWhitespace }) else { continue }
            let sourceEnd = text[sourceStart...].firstIndex(of: "\n") ?? text.endIndex
            if text[sourceStart..<sourceEnd].range(of: #"^(?:(?:图片来源|来源|图源|Source)\s*[:：]?\s*)?\[(?:图片来源|来源|图源|Source|Photo source|Image source)\]\([^\n]+\)\s*$"#,
                options: [.regularExpression, .caseInsensitive]) != nil {
                ranges.append(sourceStart..<sourceEnd)
            }
        }
        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            output.removeSubrange(range)
        }
        return output
    }

    static func allowedURLs(messages: [JSONValue], userText: String) -> Set<URL> {
        var allowed = Set<URL>()
        // Only successful tool outputs establish provenance. Assistant prose and history do not.
        func collect(_ value: JSONValue) {
            if let rows = value["images"]?.arrayValue {
                for row in rows {
                    if let raw = row["url"]?.stringValue, let url = URL(string: raw) { allowed.insert(url) }
                }
            }
            if let body = value["text"]?.stringValue {
                allowed.formUnion(images(in: body).map(\.url))
            }
        }
        for message in messages where message["role"] == "tool" {
            guard let raw = message["content"]?.stringValue,
                  let result = try? JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)),
                  result["status"] == "completed", let output = result["output"] else { continue }
            collect(output)
        }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: userText, range: NSRange(userText.startIndex..., in: userText)) {
                if let url = match.url { allowed.insert(url) }
            }
        }
        allowed.formUnion(images(in: userText).map(\.url))
        return allowed
    }
}
