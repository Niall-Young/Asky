import SwiftUI
import MarkdownUI
import Theme
import ToolService

/// Shared by live replies and reopened history; the stored content remains Markdown source.
struct ChatMarkdownView: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    private static let bodyStyle = TextStyle(size: 14, weight: 400, mode: .default)

    var body: some View {
        Markdown(ChatMath.markdown(text))
            // The default theme is basic; setting it here would override the block styles below.
            .markdownTextStyle {
                FontSize(Self.bodyStyle.size)
                FontWeight(.regular)
                ForegroundColor(ThemeColor("text").color(for: colorScheme))
            }
            .markdownBlockStyle(\.heading1, body: Self.heading)
            .markdownBlockStyle(\.heading2, body: Self.heading)
            .markdownBlockStyle(\.heading3, body: Self.heading)
            .markdownBlockStyle(\.heading4, body: Self.heading)
            .markdownBlockStyle(\.heading5, body: Self.heading)
            .markdownBlockStyle(\.heading6, body: Self.heading)
            .markdownBlockStyle(\.paragraph) { configuration in
                Group {
                    if ChatInlineText.isImageOnly(configuration.content.renderMarkdown()) {
                        configuration.label
                    } else {
                        ChatInlineText(markdown: configuration.content.renderMarkdown())
                    }
                }
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(Self.bodyStyle.lineHeight - Self.bodyStyle.size * 1.2)
                    .markdownMargin(top: 0, bottom: 14)
            }
            .markdownTextStyle(\.link) {
                ForegroundColor(ThemeColor("textPrimary").color(for: colorScheme))
                UnderlineStyle(.single)
            }
            .markdownBlockStyle(\.listItem) { configuration in
                configuration.label
                    // Tight Markdown lists discard bottom margins between items.
                    // A top margin keeps item boundaries distinct from wrapped lines.
                    .markdownMargin(top: 14, bottom: 14)
            }
            .markdownBlockStyle(\.codeBlock) { configuration in
                ChatCodeBlock(configuration: configuration)
                    .markdownMargin(top: 0, bottom: 16)
            }
            .markdownTextStyle(\.code) {
                FontSize(13)
                FontFamilyVariant(.monospaced)
                BackgroundColor(ThemeColor("backgroundNeutral").color(for: colorScheme))
            }
            .markdownBlockStyle(\.blockquote) { configuration in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ThemeColor.kBorderIntense).frame(width: 3)
                    configuration.label
                        .environment(\.chatInlineForeground, ThemeColor("textSubtle"))
                        .markdownTextStyle {
                            ForegroundColor(ThemeColor("textSubtle").color(for: colorScheme))
                        }
                }
                .fixedSize(horizontal: false, vertical: true)
                .markdownMargin(top: 0, bottom: 16)
            }
            .markdownBlockStyle(\.table) { configuration in
                ScrollView(.horizontal) {
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                        .markdownTableBorderStyle(.init(.horizontalBorders, color: ThemeColor("border").color(for: colorScheme), width: 0))
                        .environment(\.chatTableRowCount,
                            max(1, configuration.content.renderMarkdown().split(separator: "\n").count - 1))
                        .markdownTableBackgroundStyle(.alternatingRows(
                            Color.clear, Color.clear,
                            header: ThemeColor("backgroundNeutral").color(for: colorScheme)))
                        .clipShape(.rect(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ThemeColor.kBorder, lineWidth: 1))
                }
                .markdownMargin(top: 0, bottom: 16)
            }
            .markdownBlockStyle(\.tableCell) { configuration in
                ChatTableCell(configuration: configuration)
            }
            .markdownBlockStyle(\.thematicBreak) {
                Rectangle().fill(ThemeColor.kBorder).frame(height: 1)
                    .markdownMargin(top: 16, bottom: 16)
            }
            // Grid spacing is read by TableView before its themed label is built.
            .markdownTableBorderStyle(.init(.horizontalBorders,
                color: ThemeColor("border").color(for: colorScheme), width: 0))
            .markdownImageProvider(ChatImageProvider())
            .markdownInlineImageProvider(ChatInlineImageProvider(color: NSColor(ThemeColor("text").color(for: colorScheme))))
            .textSelection(.enabled)
    }

    // Headings follow ordinary message typography, including reopened history.
    private static func heading(_ configuration: BlockConfiguration) -> some View {
        ChatInlineText(markdown: configuration.content.renderMarkdown().replacingOccurrences(
            of: "^#{1,6} +", with: "", options: .regularExpression))
            .markdownTextStyle {
                FontSize(bodyStyle.size)
                FontWeight(.regular)
            }
            .lineSpacing(bodyStyle.lineHeight - bodyStyle.size * 1.2)
            .markdownMargin(top: 0, bottom: 14)
    }

}

private struct ChatTableRowCountKey: EnvironmentKey {
    static let defaultValue = 1
}

private extension EnvironmentValues {
    var chatTableRowCount: Int {
        get { self[ChatTableRowCountKey.self] }
        set { self[ChatTableRowCountKey.self] = newValue }
    }
}

private struct ChatTableCell: View {
    let configuration: TableCellConfiguration
    @Environment(\.chatTableRowCount) private var rowCount

    var body: some View {
        ChatInlineText(markdown: configuration.content.renderMarkdown(), weight: configuration.row == 0 ? .medium : .regular)
            .markdownTextStyle {
                if configuration.row == 0 { FontWeight(.medium) }
                BackgroundColor(nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .overlay(alignment: .bottom) {
                if configuration.row < rowCount - 1 {
                    Rectangle().fill(ThemeColor.kBorder).frame(height: 1)
                }
            }
    }
}

private struct ChatInlineForegroundKey: EnvironmentKey {
    static let defaultValue = ThemeColor("text")
}

private extension EnvironmentValues {
    var chatInlineForeground: ThemeColor {
        get { self[ChatInlineForegroundKey.self] }
        set { self[ChatInlineForegroundKey.self] = newValue }
    }
}

private extension NSAttributedString.Key {
    static let chatInlineCode = NSAttributedString.Key("AskyInlineCode")
}

private final class ChatInlineLayoutManager: NSLayoutManager {
    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int,
        forCharacterRange charRange: NSRange, color: NSColor) {
        guard let view = textContainers.first?.textView as? ChatSelectableTextView,
              view.selectedRange().length > 0,
              NSIntersectionRange(view.selectedRange(), charRange).length > 0,
              let tint = view.selectedTextAttributes[.backgroundColor] as? NSColor else {
            super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
            return
        }
        NSGraphicsContext.saveGraphicsState()
        tint.setFill()
        super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: tint)
        NSGraphicsContext.restoreGraphicsState()
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, !textContainers.isEmpty else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.chatInlineCode, in: characters) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
                ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, container, lineGlyphs, _ in
                let segment = NSIntersectionRange(glyphs, lineGlyphs)
                guard segment.length > 0 else { return }
                let horizontalBounds = self.boundingRect(forGlyphRange: segment, in: container)
                let baseline = fragment.minY + self.location(forGlyphAt: segment.location).y
                // Enclosing selection rects include line spacing and were clipped at the text view edge.
                // Draw against the font baseline so all four corners remain inside the text bounds.
                let pill = NSRect(x: horizontalBounds.minX + origin.x,
                    y: baseline - font.ascender - 2 + origin.y,
                    width: horizontalBounds.width, height: ceil(font.ascender - font.descender) + 4)
                color.setFill()
                NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }
}

/// Native selectable text supplies inline padding, rounded backgrounds and attachment baselines.
struct ChatInlineText: View {
    let markdown: String
    var literal = false
    var monospaced = false
    var shrinkToFit = false
    var weight: NSFont.Weight = .regular
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.chatInlineForeground) private var foreground
    @State private var images: [URL: Data] = [:]
    @State private var sourceNames: [URL: String] = [:]

    static func parsed(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(markdown)
    }

    static func isImageOnly(_ markdown: String) -> Bool {
        let content = parsed(markdown)
        return content.runs.contains { $0.imageURL != nil } && !content.runs.contains {
            $0.imageURL == nil && !String(content[$0.range].characters)
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        ChatInlineNativeText(content: literal ? AttributedString(markdown) : Self.parsed(markdown), monospaced: monospaced, shrinkToFit: shrinkToFit, weight: weight, images: images, sourceName: ChatSourceTextView.sources(in: Self.parsed(markdown)).first.flatMap { sourceNames[$0] },
            foreground: NSColor(foreground.color(for: colorScheme)),
            background: NSColor(ThemeColor("backgroundNeutral").color(for: colorScheme)),
            linkColor: NSColor(ThemeColor("textPrimary").color(for: colorScheme)))
            .task(id: markdown) {
                guard !literal else { return }
                var loaded: [URL: Data] = [:]
                for url in Set(Self.parsed(markdown).runs.compactMap(\.imageURL)) {
                    guard !Task.isCancelled else { return }
                    if ChatMath.formula(url) != nil { continue }
                    if let data = try? await ChatImageService.shared.imageData(from: url) { loaded[url] = data }
                }
                guard !Task.isCancelled else { return }
                images = loaded
                if let first = ChatSourceTextView.sources(in: Self.parsed(markdown)).first {
                    let metadata = try? await ChatLinkService.shared.preview(for: first)
                    guard !Task.isCancelled else { return }
                    sourceNames[first] = metadata?.siteName
                }
            }
    }
}

private struct ChatInlineNativeText: NSViewRepresentable {
    let content: AttributedString
    var monospaced = false
    var shrinkToFit = false
    var weight: NSFont.Weight = .regular
    @Environment(\.chatSelectionColor) private var selectionColor
    @Environment(\.chatQuoteAction) private var quoteAction
    let images: [URL: Data]
    let sourceName: String?
    let foreground: NSColor
    let background: NSColor
    let linkColor: NSColor

    func makeNSView(context: Context) -> NSTextView {
        let storage = NSTextStorage()
        let manager = ChatInlineLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        // SwiftUI supplies the paragraph width in sizeThatFits; avoid stale AppKit widths on resize.
        container.widthTracksTextView = false
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        let view = ChatSourceTextView(frame: .zero, textContainer: container)
        view.delegate = view
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = TextStyle(size: 14, weight: 400, mode: .default).lineHeight - 14 * 1.2
        for run in content.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = monospaced ? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular) : NSFont.systemFont(ofSize: 14, weight: weight)
            if intent.contains(.stronglyEmphasized) { font = NSFont.systemFont(ofSize: 14, weight: .bold) }
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: foreground, .paragraphStyle: paragraph
            ]
            if let link = run.link, !ChatImageService.supports(link) {
                attributes[.link] = link
                attributes[.foregroundColor] = linkColor
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            // Source labels remain plain text; the source action belongs at the end of this paragraph.
            if let url = run.link, ChatImageService.supports(url), run.imageURL == nil,
               ChatSourceTextView.isCitation(String(content[run.range].characters)) { continue }
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let url = run.imageURL {
                if let formula = ChatMath.formula(url) {
                    if let rendered = ChatMathRenderer.render(formula, color: foreground) {
                        let attachment = NSTextAttachment()
                        attachment.image = rendered.image
                        attachment.bounds = NSRect(x: 0, y: -rendered.descent,
                            width: rendered.image.size.width, height: rendered.image.size.height)
                        let fragment = NSMutableAttributedString(attachment: attachment)
                        fragment.addAttribute(.chatSelectionText, value: formula.source, range: NSRange(location: 0, length: fragment.length))
                        result.append(fragment)
                    } else {
                        result.append(NSAttributedString(string: formula.source, attributes: attributes))
                    }
                    continue
                }
                let image = images[url].flatMap(NSImage.init(data:)) ?? MingCute.image("photo")
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = NSRect(x: 0, y: -2, width: min(120, 14 * image.size.width / max(1, image.size.height)), height: 14)
                let fragment = NSMutableAttributedString(attachment: attachment)
                attributes[.chatSelectionText] = String(content[run.range].characters)
                fragment.addAttributes(attributes, range: NSRange(location: 0, length: fragment.length))
                result.append(fragment)
            } else {
                var text = String(content[run.range].characters)
                if intent.contains(.code) {
                    text = " " + text + " "
                    attributes[.font] = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                    attributes[.chatInlineCode] = background
                }
                result.append(NSAttributedString(string: text, attributes: attributes))
            }
        }
        let sources = ChatSourceTextView.sources(in: content)
        if let first = sources.first {
            result.append(NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: 14)]))
            let attachment = NSTextAttachment()
            let name = sourceName?.trimmingCharacters(in: .whitespacesAndNewlines)
            attachment.image = ChatSourceTextView.badge(name: name.flatMap { $0.isEmpty ? nil : $0 } ?? ChatSourceTextView.domain(first),
                count: sources.count, foreground: foreground, background: background)
            attachment.bounds = NSRect(x: 0, y: -5, width: attachment.image!.size.width, height: 24)
            let fragment = NSMutableAttributedString(attachment: attachment)
            fragment.addAttributes([.link: first, .chatSources: sources], range: NSRange(location: 0, length: fragment.length))
            result.append(fragment)
        }
        if let selectable = view as? ChatSelectableTextView {
            selectable.quoteAction = quoteAction
            selectable.selectedTextAttributes = [.backgroundColor: NSColor(selectionColor).withAlphaComponent(0.45)]
        }
        view.linkTextAttributes = [.foregroundColor: linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        if view.textStorage?.isEqual(to: result) != true { view.textStorage?.setAttributedString(result) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context) -> CGSize? {
        // SwiftUI probes minimum and maximum widths before choosing the actual paragraph width.
        // Falling back to NSTextView for the zero-width probe makes its current width a hard minimum.
        if proposal.width == 0 { return .zero }
        if let width = proposal.width, !width.isFinite { return CGSize(width: 100_000, height: 0) }
        let proposedWidth: CGFloat?
        if monospaced {
            proposedWidth = max(200, (view.string.components(separatedBy: "\n").map {
                ($0 as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]).width
            }.max() ?? 200) + 2)
        } else if shrinkToFit, let width = proposal.width {
            let natural = view.string.components(separatedBy: "\n").map {
                ($0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: weight)]).width
            }.max() ?? width
            proposedWidth = min(width, ceil(natural) + 2)
        } else { proposedWidth = proposal.width }
        guard let width = proposedWidth, width > 0, let container = view.textContainer,
              let manager = view.layoutManager else { return nil }
        view.setFrameSize(NSSize(width: width, height: view.frame.height))
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(manager.usedRect(for: container).height) + 4)
    }
}

private struct ChatCodeBlock: View {
    let configuration: CodeBlockConfiguration
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(configuration.language.flatMap { $0.isEmpty ? nil : $0 } ?? NSLocalizedString("代码", comment: "Code block language fallback"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ThemeColor.kTextSubtle)
                Spacer()
                Button {
                    copied = MessageClipboard.copy(configuration.content)
                } label: {
                    Group {
                        if copied { Image(mingCute: "checkmark", size: 14) }
                        else { Image("ChatCopy").resizable().scaledToFit().frame(width: 14, height: 14) }
                    }
                    .frame(width: 16, height: 16).padding(6)
                }
                .buttonStyle(AgentIconButtonStyle())
                .foregroundStyle(ThemeColor("iconSubtlest"))
                .help(copied ? LocalizedStringKey("已复制代码") : LocalizedStringKey("复制代码"))
                .accessibilityLabel("复制代码")
            }
            .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 4)
            Rectangle().fill(ThemeColor.kBorder).frame(height: 1)
            ScrollView(.horizontal) {
                ChatInlineText(markdown: configuration.content, literal: true, monospaced: true)
                    .frame(minWidth: 200)
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(14)
                    }
                    .padding(12)
            }
        }
        .background(ThemeColor.kBackgroundNeutral)
        .clipShape(.rect(cornerRadius: 8))
        .task(id: copied) {
            guard copied else { return }
            do {
                try await Task.sleep(for: .milliseconds(800))
                copied = false
            } catch {}
        }
    }
}

private struct ChatImageProvider: ImageProvider {
    @ViewBuilder func makeImage(url: URL?) -> some View {
        if let formula = ChatMath.formula(url) { ChatMathBlock(formula: formula) }
        else { ChatRemoteImage(url: url) }
    }
}

private struct ChatRemoteImage: View {
    let url: URL?
    @State private var image: NSImage?
    @State private var failed = false
    @State private var downloading = false
    @State private var downloaded = false
    @State private var downloadError: String?

    nonisolated init(url: URL?) { self.url = url }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 420, alignment: .leading)
                    .overlay(alignment: .bottomTrailing) {
                        Button {
                            guard let url else { return }
                            downloading = true
                            Task {
                                defer { downloading = false }
                                do {
                                    _ = try await ChatImageService.shared.download(from: url)
                                    downloaded = true
                                } catch { downloadError = error.localizedDescription }
                            }
                        } label: {
                            Group {
                                if downloading { ProgressView().controlSize(.small) }
                                else { Image(mingCute: downloaded ? "checkmark" : "arrow.down.to.line", size: 14) }
                            }
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(ThemeColor.kIcon)
                            .background(ThemeColor.kBackground, in: .circle)
                            .overlay(Circle().stroke(ThemeColor.kBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(downloading)
                        .help(downloaded ? LocalizedStringKey("已保存到下载文件夹") : LocalizedStringKey("下载图片"))
                        .accessibilityLabel("下载图片")
                        .padding(12)
                    }
            } else {
                HStack(spacing: 8) {
                    if failed { Image(mingCute: "photo") } else { ProgressView().controlSize(.small) }
                    Text(failed ? LocalizedStringKey("图片加载失败") : LocalizedStringKey("正在加载图片…")).font(.system(size: 14))
                    if failed {
                        Button("重试") { failed = false }
                            .buttonStyle(.plain).underline()
                    }
                }
                .foregroundStyle(ThemeColor.kTextSubtle)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(ThemeColor.kBackgroundNeutral)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ThemeColor.kBorder, lineWidth: 1))
        .appDialog(NSLocalizedString("图片下载失败", comment: ""), isPresented: Binding(
            get: { downloadError != nil }, set: { if !$0 { downloadError = nil } }),
                   message: downloadError ?? "", buttons: [NSLocalizedString("好", comment: "")])
        .task(id: "\(url?.absoluteString ?? "")-\(failed)") {
            guard !failed else { return }
            image = nil
            do {
                guard let url else { throw URLError(.badURL) }
                let data = try await ChatImageService.shared.imageData(from: url)
                try Task.checkCancellation()
                guard let decoded = NSImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                image = decoded
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}

private struct ChatInlineImageProvider: InlineImageProvider {
    let color: NSColor
    func image(with url: URL, label: String) async throws -> Image {
        if let formula = ChatMath.formula(url) {
            return await MainActor.run {
                if let rendered = ChatMathRenderer.render(formula, color: color) { return Image(nsImage: rendered.image) }
                return Image(nsImage: ChatMathRenderer.sourceImage(formula.source, color: color))
            }
        }
        do {
            let data = try await ChatImageService.shared.imageData(from: url)
            guard let image = NSImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            // Inline images stay within the text line; standalone images use the full block.
            image.size = NSSize(width: 14 * image.size.width / max(1, image.size.height), height: 14)
            return Image(nsImage: image)
        } catch {
            if Task.isCancelled { throw error }
            return Image(mingCute: "photo")
        }
    }
}

#Preview(NSLocalizedString("Markdown 回复", comment: "")) {
    ChatMarkdownView(text: """
    你好！我是 **Asky**，你的 macOS 个人助理。

    比如：
    - 查看或新建日程、提醒事项
    - 查找联系人、准备短信草稿
    - 搜索或新建备忘录
    - 运行快捷指令

    ## 更多格式
    1. **粗体**、*斜体*、`行内代码`
    2. [链接](https://example.com)
       - 嵌套列表

    > 引用内容

    ```swift
    let greeting = "你好"
    ```

    | 功能 | 状态 |
    | --- | --- |
    | Markdown | 支持 |
    """)
    .padding(24)
    .frame(width: 640)
}
