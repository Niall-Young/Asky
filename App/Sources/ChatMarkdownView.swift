import Observation
import SwiftUI
import MarkdownUI
import Theme
import ToolService

/// Shared by live replies and reopened history; the stored content remains Markdown source.
struct ChatMarkdownView: View {
    let text: String
    @State private var selectionGroup = ChatSelectionGroup()
    @Environment(\.colorScheme) private var colorScheme

    private static let bodyStyle = TextStyle(size: 14, weight: 400, mode: .default)

    var body: some View {
        let parts = ChatImageGalleryContent.parts(MarkdownContent(ChatMath.markdown(text)).renderMarkdown())
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .markdown(let content): markdown(content)
                case .images(let images): ChatImageGallery(images: images)
                }
            }
        }
        .environment(\.chatSelectionGroup, selectionGroup)
    }

    private func markdown(_ content: String) -> some View {
        Markdown(content)
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
            .markdownBlockStyle(\.bulletedListMarker) { configuration in
                // A minimum-width frame can claim half the row; markers need a bounded column.
                ChatInlineText(markdown: "", literal: true, shrinkToFit: true,
                               bullet: .forLevel(configuration.listLevel))
                    .frame(width: 12, alignment: .trailing)
            }
            .markdownBlockStyle(\.numberedListMarker) { configuration in
                let marker = "\(configuration.itemNumber)."
                let width = ceil((marker as NSString).size(withAttributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: Self.bodyStyle.size, weight: .regular)
                ]).width) + 2
                ChatInlineText(markdown: marker, literal: true, monospacedDigits: true, shrinkToFit: true)
                    .frame(width: width, alignment: .trailing)
            }
            .markdownBlockStyle(\.listItem) { configuration in
                configuration.label
                    .labelStyle(ChatListItemLabelStyle())
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
                ChatMarkdownTable {
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
            .environment(\.chatSelectionGroup, selectionGroup)
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

private struct ChatListItemLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 5) {
            configuration.icon
            configuration.title
        }
    }
}

enum ChatListBullet: Hashable {
    case disc, circle, square

    static func forLevel(_ level: Int) -> Self {
        [Self.disc, .circle, .square][min(max(level - 1, 0), 2)]
    }

    var selectionText: String {
        switch self {
        case .disc: "•"
        case .circle: "◦"
        case .square: "▪"
        }
    }

    func attachment(color: NSColor) -> NSTextAttachment {
        let canvas = NSSize(width: 6, height: 6)
        let image = NSImage(size: canvas, flipped: false) { _ in
            switch self {
            case .disc:
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: 0.5, y: 0.5, width: 5, height: 5)).fill()
            case .circle:
                color.setStroke()
                let path = NSBezierPath(ovalIn: NSRect(x: 1.1, y: 1.1, width: 3.8, height: 3.8))
                path.lineWidth = 1.2
                path.stroke()
            case .square:
                color.setFill()
                NSBezierPath(roundedRect: NSRect(x: 0.75, y: 0.75, width: 4.5, height: 4.5), xRadius: 0.6, yRadius: 0.6).fill()
            }
            return true
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        // Center the 6 pt glyph vertically on 14 pt mixed CJK/Latin prose.
        attachment.bounds = NSRect(x: 0, y: 1.0, width: canvas.width, height: canvas.height)
        return attachment
    }
}

struct ChatTableScrollFade: Equatable, Sendable {
    var leading: CGFloat = 0
    var trailing: CGFloat = 0

    static func resolve(visibleMinX: CGFloat, visibleMaxX: CGFloat,
                        contentMinX: CGFloat, contentMaxX: CGFloat) -> Self {
        Self(
            leading: strength(for: max(0, visibleMinX - contentMinX)),
            trailing: strength(for: max(0, contentMaxX - visibleMaxX))
        )
    }

    private static func strength(for overflow: CGFloat) -> CGFloat {
        guard overflow > 0.5 else { return 0 }
        return min(1, (overflow - 0.5) / 8)
    }
}

struct ChatTableScrollAxisLock: Equatable, Sendable {
    enum Axis: Equatable, Sendable { case undecided, horizontal, vertical }
    enum Decision: Equatable, Sendable { case passThrough, lockHorizontal }

    private(set) var liveAxis: Axis = .undecided
    private(set) var momentumAxis: Axis = .undecided
    private var accumX: CGFloat = 0
    private var accumY: CGFloat = 0

    var isTrackingHorizontal: Bool { liveAxis == .horizontal || momentumAxis == .horizontal }

    mutating func reset() {
        liveAxis = .undecided
        momentumAxis = .undecided
        accumX = 0
        accumY = 0
    }

    mutating func evaluate(dx: CGFloat, dy: CGFloat, phase: NSEvent.Phase, momentumPhase: NSEvent.Phase) -> Decision {
        if !momentumPhase.isEmpty {
            let decision: Decision
            switch momentumAxis {
            case .horizontal: decision = .lockHorizontal
            case .vertical: decision = .passThrough
            case .undecided: decision = abs(dx) > 0 && abs(dx) >= abs(dy) ? .lockHorizontal : .passThrough
            }
            if momentumPhase.contains(.ended) || momentumPhase.contains(.cancelled) {
                momentumAxis = .undecided
            }
            return decision
        }

        if phase.isEmpty {
            reset()
            return abs(dx) > 0 && abs(dx) >= abs(dy) ? .lockHorizontal : .passThrough
        }

        if phase.contains(.mayBegin) {
            reset()
            return .passThrough
        }

        if phase.contains(.began) {
            reset()
            accumX = abs(dx)
            accumY = abs(dy)
            if max(accumX, accumY) >= 2 {
                liveAxis = accumX >= accumY ? .horizontal : .vertical
            }
            return liveAxis == .horizontal || (liveAxis == .undecided && abs(dx) > 0 && abs(dx) >= abs(dy))
                ? .lockHorizontal : .passThrough
        }

        if phase.contains(.ended) || phase.contains(.cancelled) {
            let lockedHorizontal = liveAxis == .horizontal
            momentumAxis = liveAxis
            liveAxis = .undecided
            accumX = 0
            accumY = 0
            return lockedHorizontal ? .lockHorizontal : .passThrough
        }

        if liveAxis == .undecided {
            accumX += abs(dx)
            accumY += abs(dy)
            if max(accumX, accumY) >= 2 {
                liveAxis = accumX >= accumY ? .horizontal : .vertical
            }
        }
        if liveAxis == .horizontal { return .lockHorizontal }
        if liveAxis == .undecided && abs(dx) > 0 && abs(dx) >= abs(dy) { return .lockHorizontal }
        return .passThrough
    }
}

@MainActor @Observable
private final class ChatTableScrollFadeState {
    var fade = ChatTableScrollFade()

    func update(_ updated: ChatTableScrollFade) {
        if abs(fade.leading - updated.leading) > 0.005
            || abs(fade.trailing - updated.trailing) > 0.005 {
            fade = updated
        }
    }
}

private struct ChatTableScrollFadeMask: View {
    let state: ChatTableScrollFadeState

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let fadeFraction = min(36, width * 0.2) / width
            let fade = state.fade
            LinearGradient(stops: [
                .init(color: .black.opacity(1 - fade.leading), location: 0),
                .init(color: .black.opacity(1 - fade.leading * 0.45), location: fadeFraction * 0.45),
                .init(color: .black, location: fadeFraction),
                .init(color: .black, location: 1 - fadeFraction),
                .init(color: .black.opacity(1 - fade.trailing * 0.45), location: 1 - fadeFraction * 0.45),
                .init(color: .black.opacity(1 - fade.trailing), location: 1)
            ], startPoint: .leading, endPoint: .trailing)
        }
    }
}

private struct ChatMarkdownTable<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var fadeState = ChatTableScrollFadeState()

    var body: some View {
        ScrollView(.horizontal) {
            content()
                .background {
                    ChatTableScrollObserver { updated in
                        fadeState.update(updated)
                    }
                }
        }
        .mask {
            ChatTableScrollFadeMask(state: fadeState)
        }
    }
}

/// Observes the enclosing horizontal ScrollView so edge fades track overflow and horizontal gestures stay vertically steady.
struct ChatTableScrollObserver: NSViewRepresentable {
    var onChange: (ChatTableScrollFade) -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView() }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
        view.scheduleUpdate()
    }

    final class ObserverView: NSView {
        var onChange: ((ChatTableScrollFade) -> Void)?
        private weak var observedScroll: NSScrollView?
        private weak var observedDocument: NSView?
        private var updateScheduled = false
        private var axisLock = ChatTableScrollAxisLock()
        nonisolated(unsafe) private var scrollMonitor: Any?

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { stopScrollMonitor() }
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { startScrollMonitor() } else { stopScrollMonitor() }
            scheduleUpdate()
        }

        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); scheduleUpdate() }
        override func layout() { super.layout(); scheduleUpdate() }

        private func startScrollMonitor() {
            guard scrollMonitor == nil else { return }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    self?.consumeScrollEvent(event) ?? false
                }
                return consumed ? nil : event
            }
        }

        private func stopScrollMonitor() {
            if let scrollMonitor {
                NSEvent.removeMonitor(scrollMonitor)
                self.scrollMonitor = nil
            }
            axisLock.reset()
        }

        /// Strips unintentional vertical wobble during locked horizontal table scrolling so the outer transcript stays still.
        func consumeScrollEvent(_ event: NSEvent, hitView overrideHitView: NSView? = nil) -> Bool {
            guard let scroll = enclosingScrollView,
                  let document = scroll.documentView,
                  document.bounds.width > scroll.documentVisibleRect.width + 0.5 else {
                axisLock.reset()
                return false
            }
            if overrideHitView == nil {
                guard let window, event.window === window else { return false }
            }
            let startsNewGesture = event.phase.contains(.mayBegin)
                || event.phase.contains(.began)
                || (event.phase.isEmpty && event.momentumPhase.isEmpty)
            if startsNewGesture || !axisLock.isTrackingHorizontal {
                let target = overrideHitView ?? window?.contentView?.hitTest(event.locationInWindow)
                guard let target, target.isDescendant(of: scroll) else {
                    if startsNewGesture { axisLock.reset() }
                    return false
                }
            }
            let decision = axisLock.evaluate(
                dx: event.scrollingDeltaX,
                dy: event.scrollingDeltaY,
                phase: event.phase,
                momentumPhase: event.momentumPhase
            )
            guard decision == .lockHorizontal else { return false }
            guard event.scrollingDeltaY != 0 || event.deltaY != 0 else { return false }
            guard let horizontalOnly = Self.horizontalOnlyEvent(from: event) else { return false }
            scroll.scrollWheel(with: horizontalOnly)
            return true
        }

        static func horizontalOnlyEvent(from event: NSEvent) -> NSEvent? {
            guard let cgCopy = event.cgEvent?.copy() else { return nil }
            cgCopy.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
            cgCopy.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
            cgCopy.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
            return NSEvent(cgEvent: cgCopy)
        }

        func scheduleUpdate() {
            guard !updateScheduled else { return }
            updateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateScheduled = false
                self.updateFade()
            }
        }

        @objc private func scrollChanged(_ notification: Notification) { scheduleUpdate() }

        private func updateFade() {
            guard let scroll = enclosingScrollView, let document = scroll.documentView else { return }
            if observedScroll !== scroll || observedDocument !== document {
                NotificationCenter.default.removeObserver(self)
                observedScroll = scroll
                observedDocument = document
                scroll.contentView.postsBoundsChangedNotifications = true
                scroll.contentView.postsFrameChangedNotifications = true
                document.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(scrollChanged(_:)),
                    name: NSView.boundsDidChangeNotification, object: scroll.contentView)
                NotificationCenter.default.addObserver(self, selector: #selector(scrollChanged(_:)),
                    name: NSView.frameDidChangeNotification, object: scroll.contentView)
                NotificationCenter.default.addObserver(self, selector: #selector(scrollChanged(_:)),
                    name: NSView.frameDidChangeNotification, object: document)
            }
            let visible = scroll.documentVisibleRect
            let content = document.bounds
            onChange?(ChatTableScrollFade.resolve(
                visibleMinX: visible.minX,
                visibleMaxX: visible.maxX,
                contentMinX: content.minX,
                contentMaxX: content.maxX
            ))
        }

        deinit {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            NotificationCenter.default.removeObserver(self)
        }
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
    var monospacedDigits = false
    var shrinkToFit = true
    var weight: NSFont.Weight = .regular
    var bullet: ChatListBullet? = nil
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
        let content = literal ? AttributedString(markdown) : Self.parsed(markdown)
        let sources = literal ? [] : ChatSourceTextView.sources(in: content)
        let imageURLs = literal ? [] : Array(Set(content.runs.compactMap(\.imageURL).filter { ChatMath.formula($0) == nil })).sorted { $0.absoluteString < $1.absoluteString }
        let resolvedSourceName = sources.first.flatMap { sourceNames[$0] ?? ChatLinkService.shared.cachedPreview(for: $0)?.siteName }
        ChatInlineNativeText(content: content, monospaced: monospaced, monospacedDigits: monospacedDigits, shrinkToFit: shrinkToFit, weight: weight, bullet: bullet, images: images, sourceName: resolvedSourceName,
            foreground: NSColor(foreground.color(for: colorScheme)),
            background: NSColor(ThemeColor("backgroundNeutral").color(for: colorScheme)),
            linkColor: NSColor(ThemeColor("textPrimary").color(for: colorScheme)))
            .task(id: imageURLs) {
                guard !imageURLs.isEmpty else { return }
                var loaded: [URL: Data] = [:]
                for url in imageURLs {
                    guard !Task.isCancelled else { return }
                    if let data = try? await ChatImageService.shared.imageData(from: url) { loaded[url] = data }
                }
                guard !Task.isCancelled else { return }
                images = loaded
            }
            .task(id: sources) {
                guard let first = sources.first else { return }
                await withTaskGroup(of: (URL, ChatLinkService.Preview?).self) { group in
                    var pending = sources.makeIterator()
                    func enqueue(_ url: URL) {
                        group.addTask {
                            let preview = try? await ChatLinkService.shared.preview(for: url) { partial in
                                guard url == first, let site = partial.siteName, !site.isEmpty else { return }
                                Task { @MainActor in
                                    if sourceNames[first] != site { sourceNames[first] = site }
                                }
                            }
                            return (url, preview)
                        }
                    }
                    for _ in 0..<min(4, sources.count) {
                        if let url = pending.next() { enqueue(url) }
                    }
                    for await (url, metadata) in group {
                        guard !Task.isCancelled else { group.cancelAll(); return }
                        if url == first, let site = metadata?.siteName, !site.isEmpty, sourceNames[first] != site {
                            sourceNames[first] = site
                        }
                        if let next = pending.next() { enqueue(next) }
                    }
                }
            }
    }
}

private struct ChatInlineNativeText: NSViewRepresentable {
    let content: AttributedString
    var monospaced = false
    var monospacedDigits = false
    var shrinkToFit = false
    var weight: NSFont.Weight = .regular
    var bullet: ChatListBullet? = nil
    @Environment(\.chatSelectionColor) private var selectionColor
    @Environment(\.chatQuoteAction) private var quoteAction
    @Environment(\.chatSelectionGroup) private var selectionGroup
    let images: [URL: Data]
    let sourceName: String?
    let foreground: NSColor
    let background: NSColor
    let linkColor: NSColor

    @MainActor
    final class Measurement {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: .zero)
        private(set) var naturalWidth: CGFloat = 2
        private var cachedBullet: ChatListBullet?
        private var cachedBulletColor: NSColor?
        private var cachedBulletAttachment: NSTextAttachment?

        init() {
            container.lineFragmentPadding = 0
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
        }

        func bulletAttachment(for bullet: ChatListBullet, color: NSColor) -> NSTextAttachment {
            if cachedBullet == bullet, cachedBulletColor == color, let cached = cachedBulletAttachment {
                return cached
            }
            let attachment = bullet.attachment(color: color)
            cachedBullet = bullet
            cachedBulletColor = color
            cachedBulletAttachment = attachment
            return attachment
        }

        func update(_ content: NSAttributedString) {
            guard !storage.isEqual(to: content) else { return }
            storage.setAttributedString(content)
            container.containerSize = NSSize(width: 100_000, height: CGFloat.greatestFiniteMagnitude)
            manager.ensureLayout(for: container)
            naturalWidth = ceil(manager.usedRect(for: container).width) + 2
        }

        func height(for width: CGFloat) -> CGFloat {
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            manager.ensureLayout(for: container)
            return ceil(manager.usedRect(for: container).height) + 4
        }
    }

    func makeCoordinator() -> Measurement { Measurement() }

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
        if let bullet {
            let attachment = context.coordinator.bulletAttachment(for: bullet, color: foreground)
            let fragment = NSMutableAttributedString(attachment: attachment)
            fragment.addAttributes([
                .font: NSFont.systemFont(ofSize: 14, weight: weight),
                .paragraphStyle: paragraph,
                .chatSelectionText: bullet.selectionText
            ], range: NSRange(location: 0, length: fragment.length))
            result.append(fragment)
        } else {
        let runs = Array(content.runs)
        let skippedCitations = runs.map { run -> Bool in
            guard let url = run.link, ChatImageService.supports(url), run.imageURL == nil else { return false }
            return ChatSourceTextView.isCitation(String(content[run.range].characters))
        }
        let citationSeparators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "、,，;；/"))
        for (runIndex, run) in runs.enumerated() {
            let intent = run.inlinePresentationIntent ?? []
            var font = monospaced ? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
                : monospacedDigits ? NSFont.monospacedDigitSystemFont(ofSize: 14, weight: weight)
                : NSFont.systemFont(ofSize: 14, weight: weight)
            if intent.contains(.stronglyEmphasized) { font = NSFont.systemFont(ofSize: 14, weight: .bold) }
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: foreground, .paragraphStyle: paragraph
            ]
            if let link = run.link, link.scheme?.lowercased() == "mailto" {
                attributes[.link] = link
                attributes[.foregroundColor] = linkColor
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            // Source labels remain plain text; the source action belongs at the end of this paragraph.
            if skippedCitations[runIndex] { continue }
            if run.link == nil, run.imageURL == nil,
               runIndex > 0, runIndex + 1 < runs.count,
               skippedCitations[runIndex - 1], skippedCitations[runIndex + 1],
               String(content[run.range].characters).trimmingCharacters(in: citationSeparators).isEmpty { continue }
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
            let name = sourceName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let attachment = ChatSourceTextView.badgeAttachment(
                name: name.flatMap { $0.isEmpty ? nil : $0 } ?? ChatSourceTextView.domain(first),
                count: sources.count, foreground: foreground, background: background)
            let fragment = NSMutableAttributedString(attachment: attachment)
            fragment.addAttributes([.link: first, .chatSources: sources], range: NSRange(location: 0, length: fragment.length))
            result.append(fragment)
        }
        }
        if let selectable = view as? ChatSelectableTextView {
            selectable.quoteAction = quoteAction
            selectable.selectionGroup = selectionGroup
            selectionGroup?.register(selectable)
            selectable.selectedTextAttributes = [.backgroundColor: NSColor(selectionColor).withAlphaComponent(0.45)]
        }
        view.linkTextAttributes = [.foregroundColor: linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        context.coordinator.update(result)
        if view.textStorage?.isEqual(to: result) != true { view.textStorage?.setAttributedString(result) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context) -> CGSize? {
        // SwiftUI probes minimum and maximum widths before choosing the actual paragraph width.
        // Falling back to NSTextView for the zero-width probe makes its current width a hard minimum.
        if proposal.width == 0 { return .zero }
        if !shrinkToFit, let width = proposal.width, !width.isFinite {
            return CGSize(width: 100_000, height: 0)
        }
        let proposedWidth: CGFloat?
        if monospaced {
            proposedWidth = max(200, (view.string.components(separatedBy: "\n").map {
                ($0 as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]).width
            }.max() ?? 200) + 2)
        } else if shrinkToFit {
            // Never measure natural width with the live NSTextView's layout manager:
            // AppKit can retain its rendered line width and add the 2 pt inset again
            // on every hover update. Measure immutable content in an independent stack.
            let natural = context.coordinator.naturalWidth
            proposedWidth = min(proposal.width ?? natural, natural)
        } else { proposedWidth = proposal.width }
        guard let width = proposedWidth, width > 0 else { return nil }
        return CGSize(width: width, height: context.coordinator.height(for: width))
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
        else if let url { ChatImageGallery(images: [ChatGalleryImage(url: url, label: "")]) }
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
