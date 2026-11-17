import Foundation
import AppKit
import SwiftUI
import MarkdownUI

@main
@MainActor
struct ChatImageGalleryRegression {
    static func main() {
        let image = "![人像](https://example.com/portrait.jpg)"
        let image2 = "![合照](https://example.com/group.jpg)"
        let source = "来源：[人物页](https://example.com/person)"
        let input = "介绍\n\n\(image)\n\n\(source)\n\n\(image2)\n来源：[报道](https://example.com/story)\n\n后续正文"
        let parts = ChatImageGalleryContent.parts(input)
        precondition(parts.count == 3)
        guard case .images(let photos) = parts[1] else { fatalError("Missing gallery") }
        precondition(photos.count == 2)
        precondition(photos[0].sourceURL?.path == "/person")
        precondition(photos[1].sourceURL?.path == "/story")
        precondition(photos[0].label == "人像")
        precondition(parts[0] == .markdown("介绍"))
        precondition(parts[2] == .markdown("后续正文"))

        for sourceLine in ["**图片来源：**[网页](https://example.com/source)",
                           "[来源](https://example.com/source)",
                           "Source: [Site](https://example.com/source)",
                           "[来源：人物页](https://example.com/source)",
                           "[来源：新闻报道](https://example.com/source)（照片说明）"] {
            guard case .images(let photos) = ChatImageGalleryContent.parts(image + "\n" + sourceLine).first else { fatalError() }
            precondition(photos.first?.sourceURL?.path == "/source")
        }
        // A nearby ordinary link, mixed prose or citation must never disappear.
        for text in ["[继续阅读](https://example.com/story)",
                     "来源：[资料](https://example.com)；这是正文解释。",
                     "来源：[一](https://example.com/1)、[二](https://example.com/2)"] {
            precondition(ChatImageGalleryContent.parts(image + "\n" + text).last == .markdown(text))
        }
        for code in ["```md\n\(image)\n\(source)\n```", "~~~~md\n\(image)\n\(source)\n~~~~", "    \(image)", "- 列表项\n  \(image)"] {
            precondition(ChatImageGalleryContent.parts(code) == [.markdown(code)])
        }
        for text in ["正文 \(image)", "`\(image)`", "![公式](asky-math://formula)", "![文件](file:///tmp/image.png)"] {
            precondition(ChatImageGalleryContent.parts(text) == [.markdown(text)])
        }
        guard case .images(let multiple) = ChatImageGalleryContent.parts(image + " " + image2).first else { fatalError() }
        precondition(multiple.count == 2)
        guard case .images(let emptyAlt) = ChatImageGalleryContent.parts("![](https://example.com/a.png)").first else { fatalError() }
        precondition(emptyAlt.first?.label == "")
        precondition(ChatImageGalleryContent.parts(image + "\n\n正文\n\n" + image2).count == 3)
        for heading in ["### 照片", "照片", "**图片**", "## Photos"] {
            let result = ChatImageGalleryContent.parts("介绍\n\n" + heading + "\n\n" + image)
            precondition(result.count == 2)
            precondition(result.first == .markdown("介绍"))
        }
        for heading in ["### 拍摄地点", "正文提到了照片"] {
            precondition(ChatImageGalleryContent.parts(heading + "\n\n" + image).first == .markdown(heading))
        }
        let references = MarkdownContent("![照片][photo]\n\n[来源：网页][source]\n\n[photo]: https://example.com/a.jpg\n[source]: https://example.com/source").renderMarkdown()
        guard case .images(let resolved) = ChatImageGalleryContent.parts(references).first else { fatalError() }
        precondition(resolved.first?.sourceURL?.path == "/source")
        print("Chat image gallery parsing passed")
        if CommandLine.arguments.contains("--preview") { preview() }
    }

    private static func preview() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let portrait = "https://fareastfilms.com/wp-content/uploads/2026/10/Christy-Chung-768x1152.jpg"
        let landscape = "https://dam.mediacorp.sg/image/upload/s--UY9oQ9E_--/c_crop,h_910,w_1619,x_1,y_84/c_fill,g_auto,h_780,w_1390/f_auto,q_auto/v1/8world/images/2026/09/24/20260924_ent_christy-chung.jpg?itok=_IkwwEaB"
        let content = "### 照片\n\n" + [portrait, landscape, portrait, landscape].enumerated().map {
            "![照片 \($0.offset + 1)](\($0.element))\n\n[来源：人物页](https://fareastfilms.com/person/christy-chung)"
        }.joined(separator: "\n\n")
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 300),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "图片"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentMinSize = NSSize(width: 280, height: 280)
        let host = NSHostingView(rootView: ChatMarkdownView(text: content).padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .windowSurfaceBackground(in: RoundedRectangle(cornerRadius: 16)))
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
        window.contentView = WindowSurface.glassContentView(host, cornerRadius: 16)
        let presentation = WindowPresentation()
        presentation.show(window, afterActivation: true)
        withExtendedLifetime((window, presentation)) { app.run() }
    }

}
