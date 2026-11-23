import AppKit
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
            return "“\(clean)”"
        case .reply(let quote):
            return Self.replyPlainPreview(quote.text)
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

    var supportsComposerPopover: Bool {
        switch self {
        case .file, .image: false
        case .pastedText, .selection, .reply: true
        }
    }

    var supportsBubbleAction: Bool {
        switch self {
        case .file, .image: false
        case .pastedText, .selection, .reply: true
        }
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

enum InlineTagHoverState: Equatable {
    case none
    case pill
    case closeButton
}

@MainActor
final class InlineTagAttachment: NSTextAttachment {
    let tokenID: String
    var kind: InlineTagKind
    var appearance: InlineTagAppearance
    private(set) var hoverState: InlineTagHoverState = .none

    static let pillHeight: CGFloat = 22
    static let horizontalMargin: CGFloat = 2
    static let horizontalPadding: CGFloat = 7
    static let iconSpacing: CGFloat = 5
    static let iconSize: CGFloat = 13
    static let closeIconSize: CGFloat = 11.5
    static let thumbSize: CGFloat = 16
    static let maxPillWidth: CGFloat = 188
    static let cornerRadius: CGFloat = 6

    private var hasThumbnail: Bool {
        if case .image(_, let data) = kind, data != nil { return true }
        return false
    }

    var closeHitWidth: CGFloat {
        let iconWidth = hasThumbnail ? Self.thumbSize : Self.iconSize
        let leadingPad = hasThumbnail ? 4 : Self.horizontalPadding
        return Self.horizontalMargin + leadingPad + iconWidth + Self.iconSpacing / 2
    }

    init(kind: InlineTagKind, appearance: InlineTagAppearance) {
        self.tokenID = kind.tokenID
        self.kind = kind
        self.appearance = appearance
        super.init(data: nil, ofType: nil)
        rebuildImage()
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
        rebuildImage()
    }

    @discardableResult
    func setHoverState(_ newState: InlineTagHoverState) -> Bool {
        guard hoverState != newState else { return false }
        hoverState = newState
        rebuildImage()
        return true
    }

    private func rebuildImage() {
        let font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        let label = kind.label
        let iconWidth: CGFloat = hasThumbnail ? Self.thumbSize : Self.iconSize
        let leadingPad: CGFloat = hasThumbnail ? 4 : Self.horizontalPadding
        let maxTextWidth = Self.maxPillWidth - leadingPad - iconWidth - Self.iconSpacing - Self.horizontalPadding
        let measuredWidth = ceil((label as NSString).size(withAttributes: [.font: font]).width)
        let textWidth = min(maxTextWidth, max(12, measuredWidth))
        let pillWidth = ceil(leadingPad + iconWidth + Self.iconSpacing + textWidth + Self.horizontalPadding)
        let totalSize = NSSize(width: pillWidth + Self.horizontalMargin * 2, height: Self.pillHeight)

        let isDark = appearance.colorScheme == .dark
        let isHovered = hoverState != .none
        let fillColor: NSColor
        let borderColor: NSColor
        if appearance.reduceTransparency {
            fillColor = NSColor(ThemeColor.kBackground.color(for: appearance.colorScheme))
            borderColor = NSColor(ThemeColor.kBorder.color(for: appearance.colorScheme))
        } else if appearance.inBubble {
            fillColor = isDark
                ? NSColor(white: 1, alpha: 0.12)
                : NSColor(white: 1, alpha: 0.65)
            borderColor = isDark
                ? NSColor(white: 1, alpha: 0.14)
                : NSColor(red: 14 / 255, green: 15 / 255, blue: 17 / 255, alpha: 0.08)
        } else {
            fillColor = isDark
                ? NSColor(white: 1, alpha: isHovered ? 0.15 : 0.10)
                : NSColor(red: 14 / 255, green: 15 / 255, blue: 17 / 255, alpha: isHovered ? 0.10 : 0.065)
            borderColor = isDark
                ? NSColor(white: 1, alpha: isHovered ? 0.18 : 0.12)
                : NSColor(red: 14 / 255, green: 15 / 255, blue: 17 / 255, alpha: isHovered ? 0.12 : 0.08)
        }
        let textColor = isDark
            ? NSColor(white: 1, alpha: 0.86)
            : NSColor(red: 14 / 255, green: 15 / 255, blue: 17 / 255, alpha: 0.80)
        let iconColor = NSColor(ThemeColor.kIconSubtle.color(for: appearance.colorScheme))

        let image = NSImage(size: totalSize, flipped: false) { _ in
            let pillRect = NSRect(x: Self.horizontalMargin, y: 0.5, width: pillWidth, height: Self.pillHeight - 1)
            let path = NSBezierPath(roundedRect: pillRect, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
            fillColor.setFill()
            path.fill()
            borderColor.setStroke()
            path.lineWidth = 0.5
            path.stroke()

            let iconX = pillRect.minX + leadingPad
            if case .image(_, let data) = self.kind, let data, let nsImage = NSImage(data: data) {
                let thumbRect = NSRect(x: iconX, y: (Self.pillHeight - Self.thumbSize) / 2,
                                       width: Self.thumbSize, height: Self.thumbSize)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: thumbRect, xRadius: 3.5, yRadius: 3.5).addClip()
                let src = nsImage.size
                let scale = max(thumbRect.width / max(1, src.width), thumbRect.height / max(1, src.height))
                let drawSize = NSSize(width: src.width * scale, height: src.height * scale)
                let drawRect = NSRect(x: thumbRect.midX - drawSize.width / 2,
                                      y: thumbRect.midY - drawSize.height / 2,
                                      width: drawSize.width, height: drawSize.height)
                nsImage.draw(in: drawRect)
                if self.hoverState != .none {
                    let scrimAlpha: CGFloat = self.hoverState == .closeButton ? 0.65 : 0.48
                    NSColor.black.withAlphaComponent(scrimAlpha).setFill()
                    thumbRect.fill()
                    let glyph = MingCute.image("xmark", size: Self.closeIconSize)
                    let tinted = Self.tintedImage(glyph, color: .white)
                    let closeRect = NSRect(x: thumbRect.midX - Self.closeIconSize / 2,
                                           y: thumbRect.midY - Self.closeIconSize / 2,
                                           width: Self.closeIconSize, height: Self.closeIconSize)
                    tinted.draw(in: closeRect)
                }
                NSGraphicsContext.restoreGraphicsState()
            } else if self.hoverState != .none {
                let iconCenterX = iconX + Self.iconSize / 2
                let iconCenterY = Self.pillHeight / 2
                if self.hoverState == .closeButton {
                    let badgeSize: CGFloat = 16
                    let badgeRect = NSRect(x: iconCenterX - badgeSize / 2, y: iconCenterY - badgeSize / 2,
                                           width: badgeSize, height: badgeSize)
                    let badgeColor = isDark
                        ? NSColor(white: 1, alpha: 0.16)
                        : NSColor(red: 14 / 255, green: 15 / 255, blue: 17 / 255, alpha: 0.11)
                    badgeColor.setFill()
                    NSBezierPath(ovalIn: badgeRect).fill()
                }
                let glyph = MingCute.image("xmark", size: Self.closeIconSize)
                let tint = self.hoverState == .closeButton ? textColor : iconColor
                let tinted = Self.tintedImage(glyph, color: tint)
                let closeRect = NSRect(x: iconCenterX - Self.closeIconSize / 2,
                                       y: iconCenterY - Self.closeIconSize / 2,
                                       width: Self.closeIconSize, height: Self.closeIconSize)
                tinted.draw(in: closeRect)
            } else {
                let symbol: String = switch self.kind {
                case .image: "photo"
                case .file: "doc"
                case .pastedText: "doc.on.clipboard"
                case .selection: "text.document"
                case .reply: "arrow.turn.down.left"
                }
                let glyph = MingCute.image(symbol, size: Self.iconSize)
                let tinted = Self.tintedImage(glyph, color: iconColor)
                let iconRect = NSRect(x: iconX, y: (Self.pillHeight - Self.iconSize) / 2,
                                      width: Self.iconSize, height: Self.iconSize)
                tinted.draw(in: iconRect)
            }

            let style = NSMutableParagraphStyle()
            style.lineBreakMode = self.kind.truncatesMiddle ? .byTruncatingMiddle : .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: style
            ]
            let textHeight = ceil(font.ascender - font.descender)
            let textRect = NSRect(x: iconX + iconWidth + Self.iconSpacing,
                                  y: (Self.pillHeight - textHeight) / 2 + 0.5,
                                  width: textWidth,
                                  height: textHeight)
            (label as NSString).draw(in: textRect, withAttributes: attrs)
            return true
        }
        self.image = image
        let bodyFont = NSFont.systemFont(ofSize: 14)
        let bodyHeight = bodyFont.ascender - bodyFont.descender
        let yOffset = floor(bodyFont.descender + (bodyHeight - Self.pillHeight) / 2)
        self.bounds = NSRect(x: 0, y: yOffset, width: totalSize.width, height: totalSize.height)
    }

    private static func tintedImage(_ image: NSImage, color: NSColor) -> NSImage {
        let size = image.size
        return NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}

/// Lightweight native popover for inspecting or acting on an inline tag.
@MainActor
final class InlineTagPopoverPresenter: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?

    func close() {
        popover?.performClose(nil)
        popover = nil
    }

    func show(kind: InlineTagKind, relativeTo rect: NSRect, of view: NSView,
              onExpandPasted: (() -> Void)? = nil,
              onRevealReply: (() -> Void)? = nil,
              onRemove: (() -> Void)? = nil) {
        close()
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.delegate = self
        let content = InlineTagPopoverContent(
            kind: kind,
            onExpandPasted: onExpandPasted.map { action in { [weak pop] in pop?.performClose(nil); action() } },
            onRevealReply: onRevealReply.map { action in { [weak pop] in pop?.performClose(nil); action() } },
            onRemove: onRemove.map { action in { [weak pop] in pop?.performClose(nil); action() } }
        )
        let hosting = NSHostingController(rootView: content)
        pop.contentViewController = hosting
        popover = pop
        pop.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
    }
}

private struct InlineTagPopoverContent: View {
    let kind: InlineTagKind
    let onExpandPasted: (() -> Void)?
    let onRevealReply: (() -> Void)?
    let onRemove: (() -> Void)?
    @State private var loadedImage: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(mingCute: iconName, size: 14)
                    .foregroundStyle(ThemeColor.kIconSubtle)
                Text(headerTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ThemeColor.kText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let subtitle = headerSubtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(ThemeColor.kTextSubtlest)
                }
            }

            switch kind {
            case .image(let ref, let data):
                Group {
                    if let img = (data.flatMap(NSImage.init(data:)) ?? loadedImage) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260, maxHeight: 200)
                            .clipShape(.rect(cornerRadius: 8))
                    } else {
                        ProgressView()
                            .frame(width: 120, height: 80)
                    }
                }
                .task(id: ref.id) {
                    if data == nil {
                        let loaded = await Task.detached(priority: .utility) {
                            ComposerAttachmentService.preview(ref).thumbnail
                        }.value
                        loadedImage = loaded.flatMap(NSImage.init(data:))
                    }
                }
            case .file(let ref):
                Text(URL(filePath: ref.path).lastPathComponent)
                    .font(.system(size: 13))
                    .foregroundStyle(ThemeColor.kTextSubtle)
                    .textSelection(.enabled)
            case .pastedText(let snippet):
                ScrollView {
                    Text(snippet.text)
                        .font(.system(size: 13))
                        .foregroundStyle(ThemeColor.kText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(width: 320, height: min(220, max(60, CGFloat(snippet.text.count / 24 + 2) * 18)))
            case .selection(let quote), .reply(let quote):
                ScrollView {
                    Text(quote.text)
                        .font(.system(size: 13))
                        .foregroundStyle(ThemeColor.kText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(width: 320, height: min(220, max(56, CGFloat(quote.text.count / 24 + 2) * 18)))
            }

            HStack(spacing: 8) {
                if let copyText {
                    Button(NSLocalizedString("复制", comment: "")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(copyText, forType: .string)
                    }
                    .controlSize(.small)
                }
                if let onExpandPasted {
                    Button(NSLocalizedString("展开到输入框", comment: ""), action: onExpandPasted)
                        .controlSize(.small)
                }
                if let onRevealReply {
                    Button(NSLocalizedString("查看原回复", comment: ""), action: onRevealReply)
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
                if let onRemove {
                    Button(NSLocalizedString("移除", comment: ""), role: .destructive, action: onRemove)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 220, maxWidth: 344)
    }

    private var iconName: String {
        switch kind {
        case .image: "photo"
        case .file: "doc"
        case .pastedText: "doc.on.clipboard"
        case .selection: "text.document"
        case .reply: "arrow.turn.down.left"
        }
    }

    private var headerTitle: String {
        switch kind {
        case .image: NSLocalizedString("图片附件", comment: "")
        case .file: NSLocalizedString("文件附件", comment: "")
        case .pastedText: NSLocalizedString("粘贴的文本", comment: "")
        case .selection: NSLocalizedString("划词引用", comment: "")
        case .reply: NSLocalizedString("回复消息", comment: "")
        }
    }

    private var headerSubtitle: String? {
        switch kind {
        case .image(let ref, _), .file(let ref):
            return ByteCountFormatter.string(fromByteCount: Int64(ref.byteSize), countStyle: .file)
        case .pastedText(let snippet):
            return String(format: NSLocalizedString("%d 字", comment: ""), snippet.text.count)
        case .selection, .reply:
            return nil
        }
    }

    private var copyText: String? {
        switch kind {
        case .pastedText(let snippet): snippet.text
        case .selection(let quote), .reply(let quote): quote.text
        case .image, .file: nil
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
        let popover = InlineTagPopoverPresenter()
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
            let h = max(22, ceil(manager.usedRect(for: container).height) + 2)
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
            tagView.onTagClick = { [weak tagView] attachment, rect in
                guard let tagView else { return }
                if case .reply(let quote) = attachment.kind {
                    onRevealReply(quote.sourceMessageID)
                } else {
                    context.coordinator.popover.show(kind: attachment.kind, relativeTo: rect, of: tagView)
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
