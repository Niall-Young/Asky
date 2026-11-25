import Foundation
import Contracts
import ToolService

/// Preserve image references from provider Markdown, including reference-style images.
/// Candidates are source metadata, not proof that an image depicts the requested subject.
enum WebPageImages {
    static func candidates(in markdown: String, sourceURL: String) -> [JSONValue] {
        guard let base = FreeWebMCP.publicURL(sourceURL),
              let content = try? AttributedString(markdown: markdown,
                options: .init(interpretedSyntax: .full), baseURL: base) else { return [] }
        var seen = Set<String>()
        var images: [JSONValue] = []
        for run in content.runs {
            guard let image = run.imageURL,
                  let url = URL(string: image.relativeString, relativeTo: base)?.absoluteURL,
                  url.absoluteString.count <= 4096,
                  FreeWebMCP.publicURL(url.absoluteString) != nil,
                  !["svg", "ico"].contains(url.pathExtension.lowercased()),
                  !WebPageImageService.isLikelyTrackerOrNoise(url),
                  seen.insert(url.absoluteString).inserted else { continue }
            images.append(["url": .string(url.absoluteString),
                "alt": .string(String(String(content[run.range].characters).prefix(300))),
                "sourceURL": .string(sourceURL)])
            if images.count == 8 { break }
        }
        return images
    }
}
