import Foundation

struct ChatGalleryImage: Equatable {
    let url: URL
    let label: String
    var sourceURL: URL?
}

enum ChatGalleryPart: Equatable {
    case markdown(String)
    case images([ChatGalleryImage])
}

/// Consumes canonical Markdown from MarkdownUI, which resolves reference links first.
/// Only standalone photo lines and their immediately adjacent source labels are lifted out.
enum ChatImageGalleryContent {
    static func parts(_ markdown: String) -> [ChatGalleryPart] {
        let lines = markdown.components(separatedBy: "\n")
        var result: [ChatGalleryPart] = []
        var prose: [String] = []
        var images: [ChatGalleryImage] = []
        var fence: (character: Character, count: Int)?
        var index = 0
        func flushProse() {
            let value = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !value.isEmpty { result.append(.markdown(value)) }
            prose = []
        }
        func flushImages() {
            if !images.isEmpty { result.append(.images(images)); images = [] }
        }
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let marker = trimmed.first
            let markerCount = trimmed.prefix { $0 == marker }.count
            if let current = fence {
                prose.append(line)
                if marker == current.character, markerCount >= current.count,
                   trimmed.dropFirst(markerCount).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
            } else if (marker == "`" || marker == "~"), markerCount >= 3 {
                flushImages()
                fence = (marker!, markerCount)
                prose.append(line)
            } else if line == trimmed,
                      var photos = photos(in: line) {
                // A generic photo heading adds no information above the thumbnails.
                while prose.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { prose.removeLast() }
                if let last = prose.last, last.range(
                    of: #"^(?:#{1,6}\s+)?(?:\*\*)?(?:照片|图片|配图|Photos?|Images?)(?:\*\*)?\s*[:：]?\s*$"#,
                    options: [.regularExpression, .caseInsensitive]) != nil { prose.removeLast() }
                flushProse()
                var next = index + 1
                while next < lines.count, lines[next].trimmingCharacters(in: .whitespaces).isEmpty { next += 1 }
                if next < lines.count, let source = source(in: lines[next]) {
                    for i in photos.indices where photos[i].sourceURL == nil { photos[i].sourceURL = source }
                    index = next
                }
                images.append(contentsOf: photos)
            } else if trimmed == "<!-- end list -->" {
                // cmark-gfm inserts this HTML comment when re-rendering adjacent lists; never surface it as prose.
            } else if trimmed.isEmpty, !images.isEmpty {
                // Empty lines between photos do not create separate galleries.
            } else {
                flushImages()
                prose.append(line)
            }
            index += 1
        }
        flushImages()
        flushProse()
        return result
    }

    private static func photos(in line: String) -> [ChatGalleryImage]? {
        guard line.contains("!["), let content = try? AttributedString(markdown: line,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return nil }
        var images: [ChatGalleryImage] = []
        for run in content.runs {
            let label = String(content[run.range].characters)
            if let url = run.imageURL, isWebURL(url) {
                images.append(ChatGalleryImage(url: url, label: label == "\u{fffc}" ? "" : label,
                                               sourceURL: run.link.flatMap { isWebURL($0) ? $0 : nil }))
            } else if !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        }
        return images.isEmpty ? nil : images
    }

    static func source(in line: String) -> URL? {
        guard let content = try? AttributedString(markdown: line,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return nil }
        var links: [URL] = []
        var outside = ""
        var linkedLabel = ""
        for run in content.runs {
            guard run.imageURL == nil else { return nil }
            let text = String(content[run.range].characters)
            if let url = run.link, isWebURL(url) {
                if !links.contains(url) { links.append(url) }
                linkedLabel += text
            } else { outside += text }
        }
        guard links.count == 1 else { return nil }
        let trim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "：:()（）[]【】。."))
        let prefix = outside.trimmingCharacters(in: trim).lowercased()
        let labels = ["来源", "图片来源", "图源", "source", "photo source", "image source", "credit"]
        let linkText = linkedLabel.lowercased()
        let sourceLink = labels.contains(linkText) || labels.contains { label in
            linkText.hasPrefix(label + ":") || linkText.hasPrefix(label + "：")
        }
        let annotation = outside.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceAnnotation = annotation.isEmpty || annotation.range(
            of: #"^(?:（[^）]*）|\([^)]*\))$"#, options: .regularExpression) != nil
        guard labels.contains(prefix) || (sourceLink && sourceAnnotation) else { return nil }
        return links.first
    }

    private static func isWebURL(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
            && url.user == nil && url.password == nil
    }
}
