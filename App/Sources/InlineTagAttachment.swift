import AppKit
import CoreText
import SwiftUI
import Contracts
import LocalStore
import MarkdownUI
import Theme
import ToolService

enum InlineTagKind: Equatable {
    case image(AttachmentRef, thumbnail: Data?)
    case file(AttachmentRef)
    case pastedText(MessagePastedText)
    case selection(MessageQuote)
    case reply(MessageQuote)

    var segment: MessageSegment {
        switch self {
        case .image(let ref, _), .file(let ref): .attachment(id: ref.id)
        case .pastedText(let snippet): .pastedText(id: snippet.id)
        case .selection(let quote), .reply(let quote): .quote(id: quote.id)
        }
    }

    var tokenID: String {
        switch self {
        case .image(let ref, _), .file(let ref): "attachment:\(ref.id)"
        case .pastedText(let snippet): "pasted:\(snippet.id)"
        case .selection(let quote), .reply(let quote): "quote:\(quote.id)"
        }
    }

    var label: String {
        switch self {
        case .image(let ref, _):
            let name = URL(filePath: ref.path).lastPathComponent
            if name.hasPrefix("pasted-") || name.hasPrefix("clipboard-") || name.hasPrefix("image-") {
                return NSLocalizedString("图片", comment: "")
            }
            return name
        case .file(let ref):
            return URL(filePath: ref.path).lastPathComponent
        case .pastedText(let snippet):
            return String(format: NSLocalizedString("粘贴文本 · %d 字", comment: ""), snippet.text.count)
        case .selection(let quote):
            let clean = Self.singleLinePreview(quote.text)
            return clean.isEmpty ? NSLocalizedString("划词引用", comment: "") : clean
        case .reply(let quote):
            let preview = Self.replyPlainPreview(quote.text)
            return preview.isEmpty ? NSLocalizedString("回复消息", comment: "") : preview
        }
    }

    var symbolName: String {
        switch self {
        case .image: "photo"
        case .file: "doc"
        case .pastedText: "doc.on.clipboard"
        case .selection: "text.bubble"
        case .reply: "share_forward"
        }
    }

    var helpText: String {
        switch self {
        case .image(let ref, _):
            let name = URL(filePath: ref.path).lastPathComponent
            let size = ByteCountFormatter.string(fromByteCount: Int64(ref.byteSize), countStyle: .file)
            return "\(name) (\(size))"
        case .file(let ref):
            let name = URL(filePath: ref.path).lastPathComponent
            let size = ByteCountFormatter.string(fromByteCount: Int64(ref.byteSize), countStyle: .file)
            return "\(name) (\(size))"
        case .pastedText(let snippet):
            let preview = Self.singleLinePreview(snippet.text)
            return String(preview.prefix(120))
        case .selection(let quote):
            return String(Self.singleLinePreview(quote.text).prefix(120))
        case .reply(let quote):
            return String(Self.replyPlainPreview(quote.text).prefix(120))
        }
    }

    var truncatesMiddle: Bool {
        if case .file = self { return true }
        if case .image = self { return true }
        return false
    }

    var supportsBubbleAction: Bool {
        if case .reply = self { return true }
        return false
    }

    static func singleLinePreview(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func replyPlainPreview(_ text: String) -> String {
        let content = ChatFormParser.parse(text, streaming: false).map { part in
            switch part.content {
            case .markdown(let body): body
            case .form(let form): form.title
            }
        }.joined(separator: "\n")
        let plain = MarkdownContent(content).renderPlainText()
        return singleLinePreview(plain)
    }
}

struct InlineTagAppearance: Equatable {
    let colorScheme: ColorScheme
    let inBubble: Bool
    let reduceTransparency: Bool
}

@MainActor
final class InlineTagAttachment: NSTextAttachment {
    let tokenID: String
    var kind: InlineTagKind
    var appearance: InlineTagAppearance
    private(set) var isHovered: Bool = false

    static let pillHeight: CGFloat = 22
    static let pillYOffset: CGFloat = {
        let bodyFont = NSFont.systemFont(ofSize: 14)
        let bodyHeight = bodyFont.ascender - bodyFont.descender
        return floor(bodyFont.descender + (bodyHeight - pillHeight) / 2)
    }()
    static let horizontalMargin: CGFloat = 4
    static let trailingPadding: CGFloat = 9
    static let iconLeadingPadding: CGFloat = 7.5
    static let thumbLeadingPadding: CGFloat = 2.5
    static let iconSpacing: CGFloat = 4.5
    static let thumbSpacing: CGFloat = 5
    static let iconSize: CGFloat = 13
    static let closeIconSize: CGFloat = 12
    static let thumbCloseIconSize: CGFloat = 11
    static let thumbSize: CGFloat = 16
    static let thumbCornerRadius: CGFloat = thumbSize / 2
    static let maxPillWidth: CGFloat = 176
    static let cornerRadius: CGFloat = (pillHeight - 1) / 2
    private static let labelFont = NSFont.systemFont(ofSize: 12.5, weight: .regular)

    private struct MarginKey: Hashable {
        let leading: Int
        let trailing: Int
    }

    private var pillWidth: CGFloat = 0
    private var maxTextWidth: CGFloat = 0
    private var imageCache: [MarginKey: NSImage] = [:]

    private var hasThumbnail: Bool {
        if case .image(_, let data) = kind, data != nil { return true }
        return false
    }

    private var leadingPadding: CGFloat {
        hasThumbnail ? Self.thumbLeadingPadding : Self.iconLeadingPadding
    }

    private var leadingVisualWidth: CGFloat {
        hasThumbnail ? Self.thumbSize : Self.iconSize
    }

    private var leadingVisualSpacing: CGFloat {
        hasThumbnail ? Self.thumbSpacing : Self.iconSpacing
    }

    func closeHitWidth(atLineStart: Bool) -> CGFloat {
        let leadingMargin: CGFloat = atLineStart ? 0 : Self.horizontalMargin
        return leadingMargin + leadingPadding + leadingVisualWidth + leadingVisualSpacing / 2
    }

    init(kind: InlineTagKind, appearance: InlineTagAppearance) {
        self.tokenID = kind.tokenID
        self.kind = kind
        self.appearance = appearance
        super.init(data: nil, ofType: nil)
        rebuildMetrics()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(kind: InlineTagKind? = nil, appearance: InlineTagAppearance) {
        let newKind = kind ?? self.kind
        guard newKind != self.kind || appearance != self.appearance else { return }
        self.kind = newKind
        self.appearance = appearance
        rebuildMetrics()
    }

    @discardableResult
    func setHovered(_ newValue: Bool) -> Bool {
        guard isHovered != newValue else { return false }
        isHovered = newValue
        rebuildMetrics()
        return true
    }

    private nonisolated static func isAtParagraphEnd(in textContainer: NSTextContainer?, at charIndex: Int) -> Bool {
        guard let storage = textContainer?.layoutManager?.textStorage else { return false }
        let nextIndex = charIndex + 1
        guard nextIndex < storage.length else { return true }
        let nextChar = (storage.string as NSString).character(at: nextIndex)
        return nextChar == 0x0A || nextChar == 0x0D
    }

    private func trailingMargin(atParagraphEnd: Bool) -> CGFloat {
        (appearance.inBubble && atParagraphEnd) ? 0 : Self.horizontalMargin
    }

    nonisolated override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect,
                                               glyphPosition position: CGPoint, characterIndex charIndex: Int) -> NSRect {
        let atParagraphEnd = Self.isAtParagraphEnd(in: textContainer, at: charIndex)
        nonisolated(unsafe) let attachment = self
        return MainActor.assumeIsolated {
            let leading: CGFloat = position.x <= lineFrag.minX + 0.5 ? 0 : Self.horizontalMargin
            let trailing = attachment.trailingMargin(atParagraphEnd: atParagraphEnd)
            return NSRect(x: 0, y: Self.pillYOffset, width: attachment.pillWidth + leading + trailing, height: Self.pillHeight)
        }
    }

    nonisolated override func image(forBounds imageBounds: NSRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> NSImage? {
        let atParagraphEnd = Self.isAtParagraphEnd(in: textContainer, at: charIndex)
        nonisolated(unsafe) let attachment = self
        return MainActor.assumeIsolated {
            let trailing = attachment.trailingMargin(atParagraphEnd: atParagraphEnd)
            let leading = max(0, round(imageBounds.width - attachment.pillWidth - trailing))
            return attachment.renderedImage(leadingMargin: leading, trailingMargin: trailing)
        }
    }

    private static func makeLabelLine(
        text: String,
        color: NSColor,
        maxWidth: CGFloat,
        truncatesMiddle: Bool
    ) -> (line: CTLine, width: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: color
        ]
        let rawLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let rawWidth = CGFloat(CTLineGetTypographicBounds(rawLine, nil, nil, nil))
        guard rawWidth > maxWidth else {
            return (rawLine, rawWidth)
        }
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attrs))
        let truncated = CTLineCreateTruncatedLine(
            rawLine,
            Double(maxWidth),
            truncatesMiddle ? .middle : .end,
            ellipsis
        ) ?? rawLine
        let finalWidth = CGFloat(CTLineGetTypographicBounds(truncated, nil, nil, nil))
        return (truncated, min(maxWidth, finalWidth))
    }

    private func rebuildMetrics() {
        let availableTextWidth = Self.maxPillWidth - leadingPadding - leadingVisualWidth - leadingVisualSpacing - Self.trailingPadding
        maxTextWidth = max(12, availableTextWidth)
        let measuredWidth = ceil(Self.makeLabelLine(
            text: kind.label,
            color: .labelColor,
            maxWidth: maxTextWidth,
            truncatesMiddle: kind.truncatesMiddle
        ).width)
        let textWidth = min(maxTextWidth, max(12, measuredWidth))
        pillWidth = ceil(leadingPadding + leadingVisualWidth + leadingVisualSpacing + textWidth + Self.trailingPadding)

        imageCache.removeAll()
        let fallback = renderedImage(leadingMargin: Self.horizontalMargin, trailingMargin: Self.horizontalMargin)
        self.image = fallback
        self.bounds = NSRect(x: 0, y: Self.pillYOffset, width: fallback.size.width, height: fallback.size.height)
    }

    private func renderedImage(leadingMargin: CGFloat, trailingMargin: CGFloat) -> NSImage {
        let key = MarginKey(leading: Int(round(leadingMargin)), trailing: Int(round(trailingMargin)))
        if let cached = imageCache[key] { return cached }

        let totalSize = NSSize(width: pillWidth + leadingMargin + trailingMargin, height: Self.pillHeight)
        let isDark = appearance.colorScheme == .dark
        let fillColor: NSColor
        let borderColor: NSColor?
        if appearance.reduceTransparency {
            fillColor = NSColor(ThemeColor.kBackground.color(for: appearance.colorScheme))
            borderColor = NSColor(ThemeColor.kBorder.color(for: appearance.colorScheme))
        } else if appearance.inBubble {
            fillColor = isDark
                ? NSColor(white: 1, alpha: 0.12)
                : NSColor(white: 1, alpha: 0.62)
            borderColor = nil
        } else {
            fillColor = isDark
                ? NSColor(white: 1, alpha: 0.10)
                : NSColor(red: 14 / 255, green: 15 / 255, blue: 17 / 255, alpha: 0.06)
            borderColor = nil
        }
        let textColor = isDark
            ? NSColor(white: 1, alpha: 0.86)
            : NSColor(red: 14 / 255, green: 15 / 255, blue: 17 / 255, alpha: 0.84)
        let iconColor = NSColor(ThemeColor.kIconSubtle.color(for: appearance.colorScheme))
        let labelLine = Self.makeLabelLine(
            text: kind.label,
            color: textColor,
            maxWidth: maxTextWidth,
            truncatesMiddle: kind.truncatesMiddle
        ).line

        let image = NSImage(size: totalSize, flipped: false) { _ in
            let pillRect = NSRect(x: leadingMargin, y: 0.5, width: self.pillWidth, height: Self.pillHeight - 1)
            let path = NSBezierPath(roundedRect: pillRect, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
            fillColor.setFill()
            path.fill()
            if let borderColor {
                borderColor.setStroke()
                path.lineWidth = 0.5
                path.stroke()
            }

            let visualX = pillRect.minX + self.leadingPadding
            if case .image(_, let data) = self.kind, let data, let nsImage = NSImage(data: data) {
                let thumbRect = NSRect(x: visualX, y: (Self.pillHeight - Self.thumbSize) / 2,
                                       width: Self.thumbSize, height: Self.thumbSize)
                let thumbPath = NSBezierPath(roundedRect: thumbRect, xRadius: Self.thumbCornerRadius, yRadius: Self.thumbCornerRadius)
                NSGraphicsContext.saveGraphicsState()
                thumbPath.addClip()
                let src = nsImage.size
                let scale = max(thumbRect.width / max(1, src.width), thumbRect.height / max(1, src.height))
                let drawSize = NSSize(width: src.width * scale, height: src.height * scale)
                let drawRect = NSRect(x: thumbRect.midX - drawSize.width / 2,
                                      y: thumbRect.midY - drawSize.height / 2,
                                      width: drawSize.width, height: drawSize.height)
                nsImage.draw(in: drawRect)
                if self.isHovered {
                    NSColor.black.withAlphaComponent(0.45).setFill()
                    thumbRect.fill()
                    let glyph = MingCute.image("xmark", size: Self.thumbCloseIconSize)
                    let tinted = Self.tintedImage(glyph, color: .white)
                    let closeRect = NSRect(x: thumbRect.midX - Self.thumbCloseIconSize / 2,
                                           y: thumbRect.midY - Self.thumbCloseIconSize / 2,
                                           width: Self.thumbCloseIconSize, height: Self.thumbCloseIconSize)
                    tinted.draw(in: closeRect)
                }
                NSGraphicsContext.restoreGraphicsState()

                let thumbBorder = isDark
                    ? NSColor(white: 1, alpha: 0.12)
                    : NSColor(red: 14 / 255, green: 15 / 255, blue: 17 / 255, alpha: 0.08)
                thumbBorder.setStroke()
                let insetThumb = NSBezierPath(
                    roundedRect: thumbRect.insetBy(dx: 0.25, dy: 0.25),
                    xRadius: max(0, Self.thumbCornerRadius - 0.25),
                    yRadius: max(0, Self.thumbCornerRadius - 0.25)
                )
                insetThumb.lineWidth = 0.5
                insetThumb.stroke()
            } else if self.isHovered {
                let iconCenterX = visualX + Self.iconSize / 2
                let iconCenterY = Self.pillHeight / 2
                let glyph = MingCute.image("xmark", size: Self.closeIconSize)
                let tinted = Self.tintedImage(glyph, color: iconColor)
                let closeRect = NSRect(x: iconCenterX - Self.closeIconSize / 2,
                                       y: iconCenterY - Self.closeIconSize / 2,
                                       width: Self.closeIconSize, height: Self.closeIconSize)
                tinted.draw(in: closeRect)
            } else {
                let glyph = MingCute.image(self.kind.symbolName, size: Self.iconSize)
                let tinted = Self.tintedImage(glyph, color: iconColor)
                let iconRect = NSRect(x: visualX, y: (Self.pillHeight - Self.iconSize) / 2,
                                      width: Self.iconSize, height: Self.iconSize)
                tinted.draw(in: iconRect)
            }

            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                let textX = visualX + self.leadingVisualWidth + self.leadingVisualSpacing
                let baselineY = round((Self.pillHeight - Self.labelFont.capHeight) * 0.5 * 2) / 2
                context.textMatrix = .identity
                context.textPosition = CGPoint(x: textX, y: baselineY)
                CTLineDraw(labelLine, context)
                context.restoreGState()
            }
            return true
        }
        imageCache[key] = image
        return image
    }

    private static func tintedImage(_ image: NSImage, color: NSColor) -> NSImage {
        let size = image.size
        return NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceIn)
            return true
        }
    }
}

/// Read-only native text view for sent user messages that contain inline tags.
struct UserInlineMessageView: View {
    let segments: [MessageSegment]
    let quotes: [MessageQuote]
    let attachments: [AttachmentRef]
    let pastedTexts: [MessagePastedText]
    let onRevealReply: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.chatSelectionColor) private var selectionColor
    @Environment(\.chatQuoteAction) private var quoteAction
    @State private var thumbnails: [String: Data] = [:]

    private var imageAttachmentIDs: [String] {
        attachments.filter { $0.kind == .image }.map(\.id)
    }

    var body: some View {
        UserInlineNativeText(
            segments: segments,
            quotes: quotes,
            attachments: attachments,
            pastedTexts: pastedTexts,
            thumbnails: thumbnails,
            appearance: InlineTagAppearance(colorScheme: colorScheme, inBubble: true, reduceTransparency: reduceTransparency),
            foreground: NSColor(ThemeColor.kText.color(for: colorScheme)),
            selectionColor: NSColor(selectionColor).withAlphaComponent(0.45),
            quoteAction: quoteAction,
            onRevealReply: onRevealReply
        )
        .task(id: imageAttachmentIDs) {
            let imageRefs = attachments.filter { $0.kind == .image }
            guard !imageRefs.isEmpty else { return }
            var loaded: [String: Data] = [:]
            for ref in imageRefs {
                guard !Task.isCancelled else { return }
                let data = await Task.detached(priority: .utility) {
                    ComposerAttachmentService.preview(ref).thumbnail
                }.value
                if let data { loaded[ref.id] = data }
            }
            guard !Task.isCancelled else { return }
            thumbnails = loaded
        }
    }
}

private final class UserInlineTagTextView: NSTextView {
    var onTagClick: ((InlineTagAttachment, NSRect) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    private func tagAt(windowPoint: NSPoint) -> (InlineTagAttachment, NSRect)? {
        guard let storage = textStorage, let layout = layoutManager, let container = textContainer else { return nil }
        let pt = convert(windowPoint, from: nil)
        let containerPt = NSPoint(x: pt.x - textContainerOrigin.x, y: pt.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let index = layout.characterIndex(for: containerPt, in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
        guard index < storage.length,
              let attachment = storage.attribute(.attachment, at: index, effectiveRange: nil) as? InlineTagAttachment else {
            return nil
        }
        let glyphRange = layout.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        var rect = layout.boundingRect(forGlyphRange: glyphRange, in: container)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        guard rect.insetBy(dx: -2, dy: -2).contains(pt) else { return nil }
        return (attachment, rect)
    }

    override func mouseMoved(with event: NSEvent) {
        if let (tag, _) = tagAt(windowPoint: event.locationInWindow) {
            toolTip = tag.kind.helpText
            if tag.kind.supportsBubbleAction {
                NSCursor.pointingHand.set()
            } else {
                super.mouseMoved(with: event)
            }
        } else {
            toolTip = nil
            super.mouseMoved(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let (tag, rect) = tagAt(windowPoint: event.locationInWindow), tag.kind.supportsBubbleAction {
            onTagClick?(tag, rect)
            return
        }
        super.mouseDown(with: event)
    }
}

private struct UserInlineNativeText: NSViewRepresentable {
    let segments: [MessageSegment]
    let quotes: [MessageQuote]
    let attachments: [AttachmentRef]
    let pastedTexts: [MessagePastedText]
    let thumbnails: [String: Data]
    let appearance: InlineTagAppearance
    let foreground: NSColor
    let selectionColor: NSColor
    let quoteAction: ((String) -> Void)?
    let onRevealReply: (String) -> Void

    @MainActor
    final class Coordinator {
        struct RenderKey: Equatable {
            let segments: [MessageSegment]
            let quotes: [MessageQuote]
            let attachments: [AttachmentRef]
            let pastedTexts: [MessagePastedText]
            let thumbnails: [String: Data]
            let appearance: InlineTagAppearance
            let foreground: NSColor
        }
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: .zero)
        var lastKey: RenderKey?
        private(set) var naturalWidth: CGFloat = 2
        private var cachedWidth: CGFloat?
        private var cachedHeight: CGFloat = 22

        init() {
            container.lineFragmentPadding = 0
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
        }

        func update(_ attributed: NSAttributedString) {
            storage.setAttributedString(attributed)
            cachedWidth = nil
            container.containerSize = NSSize(width: 100_000, height: CGFloat.greatestFiniteMagnitude)
            manager.ensureLayout(for: container)
            naturalWidth = ceil(manager.usedRect(for: container).width) + 2
        }

        func height(for width: CGFloat) -> CGFloat {
            if let cachedWidth, abs(cachedWidth - width) < 0.01 { return cachedHeight }
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            manager.ensureLayout(for: container)
            let usedHeight = manager.usedRect(for: container).height
            var opticalBottom: CGFloat = 1.5
            if manager.numberOfGlyphs > 0 {
                let lastLine = manager.lineFragmentRect(forGlyphAt: manager.numberOfGlyphs - 1, effectiveRange: nil)
                if lastLine.height >= 21.5 { opticalBottom = 0 }
            }
            let h = usedHeight > 0 ? max(ceil(usedHeight), round(usedHeight + opticalBottom)) : 0
            cachedWidth = width
            cachedHeight = h
            return h
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSTextView {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        let view = UserInlineTagTextView(frame: .zero, textContainer: container)
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
        view.selectedTextAttributes = [.backgroundColor: selectionColor]
        if let tagView = view as? UserInlineTagTextView {
            tagView.onTagClick = { attachment, _ in
                if case .reply(let quote) = attachment.kind {
                    onRevealReply(quote.sourceMessageID)
                }
            }
        }
        let key = Coordinator.RenderKey(
            segments: segments, quotes: quotes, attachments: attachments,
            pastedTexts: pastedTexts, thumbnails: thumbnails,
            appearance: appearance, foreground: foreground
        )
        guard context.coordinator.lastKey != key else { return }
        context.coordinator.lastKey = key

        let attributed = buildAttributedString()
        view.textStorage?.setAttributedString(attributed)
        context.coordinator.update(attributed)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        let proposed = proposal.width ?? context.coordinator.naturalWidth
        let width = min(proposed, context.coordinator.naturalWidth)
        if let container = nsView.textContainer, abs(container.containerSize.width - width) > 0.5 {
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        }
        let height = context.coordinator.height(for: width)
        return CGSize(width: max(2, width), height: height)
    }

    private func buildAttributedString() -> NSAttributedString {
        let quotesByID = Dictionary(uniqueKeysWithValues: quotes.map { ($0.id, $0) })
        let attachmentsByID = Dictionary(uniqueKeysWithValues: attachments.map { ($0.id, $0) })
        let pastedByID = Dictionary(uniqueKeysWithValues: pastedTexts.map { ($0.id, $0) })
        let font = NSFont.systemFont(ofSize: 14, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = max(0, TextStyle(size: 14, weight: 400, mode: .default).lineHeight - 14 * 1.2)
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foreground,
            .paragraphStyle: paragraph
        ]
        let result = NSMutableAttributedString()
        for segment in segments {
            switch segment {
            case .text(let value):
                result.append(NSAttributedString(string: value, attributes: baseAttrs))
            case .quote(let id):
                guard let quote = quotesByID[id] else { continue }
                let kind: InlineTagKind = quote.kind == .reply ? .reply(quote) : .selection(quote)
                let att = InlineTagAttachment(kind: kind, appearance: appearance)
                let frag = NSMutableAttributedString(attachment: att)
                frag.addAttributes(baseAttrs, range: NSRange(location: 0, length: frag.length))
                result.append(frag)
            case .attachment(let id):
                guard let ref = attachmentsByID[id] else { continue }
                let kind: InlineTagKind = ref.kind == .image ? .image(ref, thumbnail: thumbnails[ref.id]) : .file(ref)
                let att = InlineTagAttachment(kind: kind, appearance: appearance)
                let frag = NSMutableAttributedString(attachment: att)
                frag.addAttributes(baseAttrs, range: NSRange(location: 0, length: frag.length))
                result.append(frag)
            case .pastedText(let id):
                guard let snippet = pastedByID[id] else { continue }
                let att = InlineTagAttachment(kind: .pastedText(snippet), appearance: appearance)
                let frag = NSMutableAttributedString(attachment: att)
                frag.addAttributes(baseAttrs, range: NSRange(location: 0, length: frag.length))
                result.append(frag)
            }
        }
        return result
    }
}
