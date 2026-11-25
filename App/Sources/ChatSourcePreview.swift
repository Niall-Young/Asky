import AppKit
import CoreText
import SwiftUI
import ToolService
import Theme

extension NSAttributedString.Key {
    static let chatSources = NSAttributedString.Key("AskySourceGroup")
}

/// Draws the source badge directly in the text view's graphics context so text and pill edges
/// stay aligned to physical pixels across 1x and Retina displays instead of resampling an NSImage.
private final class ChatSourceBadgeAttachmentCell: NSTextAttachmentCell {
    private let line: CTLine
    private let background: NSColor
    private let badgeSize: NSSize
    private let baseline: CGFloat

    init(line: CTLine, background: NSColor, size: NSSize, baseline: CGFloat) {
        self.line = line
        self.background = background
        self.badgeSize = size
        self.baseline = baseline
        super.init(textCell: "")
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func cellSize() -> NSSize { badgeSize }

    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -baseline) }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard let graphics = NSGraphicsContext.current else { return }
        let context = graphics.cgContext
        let deviceUnit = context.convertToDeviceSpace(CGSize(width: 1, height: 1))
        let scaleY = max(1, abs(deviceUnit.height))
        let deviceOrigin = context.convertToDeviceSpace(cellFrame.origin)
        let alignedOrigin = context.convertToUserSpace(CGPoint(x: round(deviceOrigin.x), y: round(deviceOrigin.y)))
        let alignedFrame = NSRect(origin: alignedOrigin, size: badgeSize)
        let alignedBaseline = round(baseline * scaleY) / scaleY

        context.saveGState()
        background.setFill()
        NSBezierPath(roundedRect: alignedFrame, xRadius: 12, yRadius: 12).fill()
        if graphics.isFlipped {
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            context.textPosition = CGPoint(x: alignedFrame.minX + 10, y: alignedFrame.maxY - alignedBaseline)
        } else {
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: alignedFrame.minX + 10, y: alignedFrame.minY + alignedBaseline)
        }
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

/// Clicking a single-source badge opens its URL directly; clicking a multi-source badge toggles its source list card.
/// Non-citation links stay directly clickable in prose.
final class ChatSourceTextView: ChatSelectableTextView, NSTextViewDelegate {
    private var sourceTrackingArea: NSTrackingArea?
    private(set) var preview: ChatSourcePopover?
    var openLinkHandler: (URL) -> Bool = { ToolService.openLauncherURL($0) }
    var hasSourceBadges = false {
        didSet {
            guard hasSourceBadges != oldValue else { return }
            if !hasSourceBadges { preview?.close(); preview = nil }
            if window != nil { updateTrackingAreas() }
        }
    }

    static func isCitation(_ label: String) -> Bool {
        let trimmed = label.trimmingCharacters(in: CharacterSet(charactersIn: "[]【】()（） "))
        guard !trimmed.isEmpty else { return false }
        if Int(trimmed) != nil { return true }
        let lower = trimmed.lowercased()
        if ["来源", "引用", "参考", "出处", "source", "citation", "ref", "reference"].contains(lower) {
            return true
        }
        return lower.range(
            of: #"^(?:来源|引用|参考|出处|source|citation|ref|reference)\s*[:：#-]?\s*\d+$"#,
            options: .regularExpression
        ) != nil
    }

    static func isDirectOpenableLink(_ url: URL) -> Bool {
        ChatImageService.supports(url) || url.scheme?.lowercased() == "mailto"
    }

    static func sources(in content: AttributedString) -> [URL] {
        var result: [URL] = []
        for run in content.runs {
            guard run.imageURL == nil,
                  let url = run.link,
                  ChatImageService.supports(url),
                  isCitation(String(content[run.range].characters)),
                  !result.contains(url) else { continue }
            result.append(url)
        }
        return result
    }

    static func domain(_ url: URL) -> String {
        url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
    }

    static func badgeLabel(name: String, count: Int) -> String {
        name + (count > 1 ? " +\(count - 1)" : "")
    }

    static func badgeAttachment(name: String, count: Int, foreground: NSColor, background: NSColor) -> NSTextAttachment {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: foreground.withAlphaComponent(0.75)
        ]
        var name = name
        var shortened = false
        while (name as NSString).size(withAttributes: attributes).width > 155, name.count > 1 {
            name.removeLast()
            shortened = true
        }
        if shortened { name += "…" }
        let label = badgeLabel(name: name, count: count)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        // Share the drawn label's baseline with its inline attachment, including fallback fonts.
        let baseline = (24 - ascent - descent) / 2 + descent
        let attachment = NSTextAttachment()
        attachment.attachmentCell = ChatSourceBadgeAttachmentCell(
            line: line,
            background: background,
            size: NSSize(width: ceil(width) + 20, height: 24),
            baseline: baseline
        )
        return attachment
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let sources = textStorage?.attribute(.chatSources, at: charIndex, effectiveRange: nil) as? [URL],
           !sources.isEmpty {
            if sources.count == 1, let single = sources.first {
                ChatSourcePopover.active?.close()
                preview = nil
                openSourceURL(single)
            } else {
                toggleSources(sources, at: charIndex)
            }
            return true
        }
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        if let url, Self.isDirectOpenableLink(url) {
            _ = openLinkHandler(url)
        }
        return true
    }

    func textView(_ textView: NSTextView, willDisplayToolTip tooltip: String, forCharacterAt characterIndex: Int) -> String? {
        guard let storage = textStorage, characterIndex < storage.length else { return tooltip }
        if storage.attribute(.chatSources, at: characterIndex, effectiveRange: nil) != nil { return nil }
        return tooltip
    }

    func openSourceURL(_ url: URL) {
        guard Self.isDirectOpenableLink(url) else { return }
        _ = openLinkHandler(url)
    }

    func clearPreview(_ popover: ChatSourcePopover) {
        if preview === popover { preview = nil }
    }

    private func toggleSources(_ sources: [URL], at index: Int) {
        if let preview, preview.isShown, preview.matches(index: index, sources: sources) {
            preview.close()
            self.preview = nil
            return
        }
        guard sourceAnchor(at: index) != nil else { return }
        preview?.close()
        let popover = ChatSourcePopover(textView: self, index: index, sources: sources)
        self.preview = popover
        popover.show()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let sourceTrackingArea {
            removeTrackingArea(sourceTrackingArea)
            self.sourceTrackingArea = nil
        }
        guard hasSourceBadges else { return }
        let area = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        sourceTrackingArea = area
        addTrackingArea(area)
    }

    /// Convert the actual attachment glyph, never the paragraph's wrapping link range.
    func sourceAnchor(at index: Int) -> NSRect? {
        guard let window, let manager = layoutManager, let container = textContainer,
              let storage = textStorage, index < storage.length,
              storage.attribute(.attachment, at: index, effectiveRange: nil) != nil else { return nil }
        let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        var rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        guard visibleRect.intersects(rect) else { return nil }
        return window.convertToScreen(convert(rect, to: nil))
    }

    func source(at location: NSPoint) -> (index: Int, sources: [URL])? {
        guard let manager = layoutManager, let container = textContainer, let storage = textStorage else { return nil }
        var point = convert(location, from: nil)
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y
        let glyph = manager.glyphIndex(for: point, in: container)
        guard glyph < manager.numberOfGlyphs,
              manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(point) else { return nil }
        let index = manager.characterIndexForGlyph(at: glyph)
        guard index < storage.length,
              storage.attribute(.attachment, at: index, effectiveRange: nil) != nil,
              let sources = storage.attribute(.chatSources, at: index, effectiveRange: nil) as? [URL],
              !sources.isEmpty else { return nil }
        return (index, sources)
    }

    override func cursorUpdate(with event: NSEvent) {
        if hasSourceBadges, source(at: event.locationInWindow) != nil { NSCursor.arrow.set() }
        else { super.cursorUpdate(with: event) }
    }

    override func mouseMoved(with event: NSEvent) {
        // Tracking areas also receive moves while this text sits behind the
        // header or an action. Do not set a text cursor over covered regions.
        if ActionArrowCursor.applyIfCovered(event, in: window) { return }
        super.mouseMoved(with: event)
        guard hasSourceBadges else { return }
        cursorUpdate(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { preview?.close(); preview = nil }
    }
}

/// A window-sized glass card stays attached to the source even in a scrolled transcript.
@MainActor
final class ChatSourcePopover {
    private(set) static weak var active: ChatSourcePopover?
    let panel = SurfacePanel()
    private weak var textView: ChatSourceTextView?
    private let index: Int
    private let sources: [URL]
    private var metadata: [URL: ChatLinkService.Preview] = [:]
    private var host: FirstMouseHostingView<AnyView>?
    private var metadataTask: Task<Void, Never>?
    nonisolated(unsafe) private var localMonitor: Any?
    nonisolated(unsafe) private var globalMonitor: Any?
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    private var initialScrollOrigin: NSPoint?
    private(set) var isScrollable = false
    var isShown: Bool { panel.isVisible }
    var contentView: NSView? { panel.contentView }
    var parentWindow: NSWindow? { textView?.window }
    var enclosingScrollView: NSScrollView? { textView?.enclosingScrollView }

    init(textView: ChatSourceTextView, index: Int, sources: [URL]) {
        self.textView = textView
        self.index = index
        self.sources = sources
    }

    deinit {
        removeMonitorsAndObservers()
    }

    func matches(index: Int, sources: [URL]) -> Bool {
        self.index == index && self.sources == sources
    }

    /// Prefer below the icon within the conversation; flip above before crossing its bottom edge.
    static func frame(size: NSSize, anchor: NSRect, screen: NSRect, viewport: NSRect) -> NSRect {
        let limits = screen.insetBy(dx: 8, dy: 8)
        let bottom = max(limits.minY, viewport.minY + 8)
        var y = anchor.minY - 8 - size.height
        if y < bottom { y = anchor.maxY + 8 }
        y = min(max(y, limits.minY), limits.maxY - size.height)
        let x = min(max(anchor.midX - size.width / 2, limits.minX), limits.maxX - size.width)
        return NSRect(x: round(x), y: round(y), width: size.width, height: size.height)
    }

    static func isActiveScroll(_ event: NSEvent) -> Bool {
        let hasDelta = event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 || event.deltaX != 0 || event.deltaY != 0
        if !event.momentumPhase.isEmpty { return true }
        if !event.phase.isEmpty {
            return !(event.phase == .mayBegin && !hasDelta)
        }
        return hasDelta
    }

    func show() {
        guard let parent = textView?.window else { return }
        Self.active?.close()
        Self.active = self
        for url in sources {
            if let cached = ChatLinkService.shared.cachedPreview(for: url) {
                metadata[url] = cached
            }
        }
        panel.appearance = parent.effectiveAppearance
        update()
        parent.addChildWindow(panel, ordered: .above)
        panel.matchesActiveAppearance = parent.isKeyWindow
        panel.orderFront(nil)
        let pendingSources = sources.filter { !ChatLinkService.shared.hasCompletedLookup(for: $0) }
        if !pendingSources.isEmpty {
            metadataTask = Task { @MainActor [weak self, pendingSources] in
                await withTaskGroup(of: (URL, ChatLinkService.Preview?).self) { group in
                    var pending = pendingSources.makeIterator()
                    func enqueue(_ url: URL) {
                        let apply: @MainActor @Sendable (ChatLinkService.Preview) -> Void = { [weak self] partial in
                            guard let self, self.isShown else { return }
                            self.applyPreview(partial, for: url)
                        }
                        group.addTask {
                            let preview = try? await ChatLinkService.shared.preview(for: url) { partial in
                                Task { @MainActor in apply(partial) }
                            }
                            return (url, preview)
                        }
                    }
                    for _ in 0..<min(6, pendingSources.count) {
                        if let url = pending.next() { enqueue(url) }
                    }
                    for await (url, metadata) in group {
                        guard !Task.isCancelled else { group.cancelAll(); return }
                        if let metadata { self?.applyPreview(metadata, for: url) }
                        if let next = pending.next() { enqueue(next) }
                    }
                }
            }
        }
        installDismissalMonitors(for: parent)
    }

    /// Returns `true` when the event is consumed by the popover (e.g. Escape or forwarded scroll).
    @discardableResult
    func handleLocalEvent(_ event: NSEvent) -> Bool {
        guard isShown else { return false }
        switch event.type {
        case .keyDown:
            if event.keyCode == 53 {
                close()
                return true
            }
            return false
        case .scrollWheel:
            if event.window === panel {
                if isScrollable { return false }
                guard Self.isActiveScroll(event) else { return false }
                let scroll = enclosingScrollView
                close()
                if let scroll {
                    scroll.scrollWheel(with: event)
                    return true
                }
                return false
            }
            if event.window === parentWindow, Self.isActiveScroll(event) {
                close()
            }
            return false
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if event.window === panel { return false }
            if event.type == .leftMouseDown,
               event.window === parentWindow,
               textView?.source(at: event.locationInWindow)?.index == index {
                // Forward clicks on the same badge so `clickedOnLink` toggles this card closed cleanly.
                return false
            }
            close()
            return false
        default:
            return false
        }
    }

    private func installDismissalMonitors(for parent: NSWindow) {
        removeMonitorsAndObservers()
        let localMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: localMask) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                self?.handleLocalEvent(event) ?? false
            }
            return consumed ? nil : event
        }
        let globalMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: globalMask) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.close()
            }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSWindow.didResignKeyNotification, object: parent, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
        observers.append(center.addObserver(
            forName: NSWindow.willCloseNotification, object: parent, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isShown else { return }
                    if self.reposition() == nil { self.close() }
                }
            })
        }
        if let clip = textView?.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            initialScrollOrigin = clip.bounds.origin
            observers.append(center.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self, weak clip] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isShown, let clip, let initial = self.initialScrollOrigin else { return }
                    if abs(clip.bounds.origin.x - initial.x) > 0.5 || abs(clip.bounds.origin.y - initial.y) > 0.5 {
                        self.close()
                    }
                }
            })
        }
    }

    private nonisolated func removeMonitorsAndObservers() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if !observers.isEmpty {
            let center = NotificationCenter.default
            for observer in observers { center.removeObserver(observer) }
            observers.removeAll()
        }
    }

    private func applyPreview(_ preview: ChatLinkService.Preview, for url: URL) {
        var changed = false
        if metadata[url] != preview {
            metadata[url] = preview
            changed = true
        }
        // Propagate newly resolved origin favicons to sibling URLs on the same host immediately.
        for source in sources where source != url {
            if let cached = ChatLinkService.shared.cachedPreview(for: source), metadata[source] != cached {
                metadata[source] = cached
                changed = true
            }
        }
        if changed { update() }
    }

    private func update() {
        let rows = ChatSourcePreview(sources: sources, metadata: metadata) { [weak self] url in
            guard let self else { return }
            let owner = self.textView
            self.close()
            owner?.openSourceURL(url)
        }
        let measured = SurfacePanel.fittingSize(of: rows, maxWidth: ChatSourcePreview.width)
        let available = textView?.window?.screen?.visibleFrame.height ?? 700
        let maxHeight = min(460, available - 32)
        let size = NSSize(width: ChatSourcePreview.width, height: min(measured.height, maxHeight))
        isScrollable = measured.height > maxHeight + 1
        let view = ScrollView { rows }.frame(width: size.width, height: size.height)
            .windowSurfaceBackground(in: RoundedRectangle(cornerRadius: ChatSourcePreview.cornerRadius))
        if let host {
            // Preserve ScrollView identity and its offset as individual source metadata arrives.
            host.rootView = AnyView(view)
            panel.setContentSize(size)
            host.frame = NSRect(origin: .zero, size: size)
        } else {
            let host = FirstMouseHostingView(rootView: AnyView(view))
            host.sizingOptions = []
            host.frame = NSRect(origin: .zero, size: size)
            panel.setContentSize(size)
            panel.contentView = WindowSurface.glassContentView(host, cornerRadius: ChatSourcePreview.cornerRadius)
            self.host = host
        }
        panel.invalidateShadow()
        _ = reposition()
    }

    @discardableResult private func reposition() -> NSRect? {
        guard let textView, let parent = textView.window, parent.isVisible,
              let anchor = textView.sourceAnchor(at: index), let screen = parent.screen else { return nil }
        let viewport: NSRect
        if let clip = textView.enclosingScrollView?.contentView {
            viewport = parent.convertToScreen(clip.convert(clip.bounds, to: nil))
        } else { viewport = parent.convertToScreen(parent.contentLayoutRect) }
        let frame = Self.frame(size: panel.frame.size, anchor: anchor, screen: screen.visibleFrame, viewport: viewport)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        return anchor
    }

    func close() {
        if Self.active === self { Self.active = nil }
        metadataTask?.cancel()
        metadataTask = nil
        removeMonitorsAndObservers()
        initialScrollOrigin = nil
        panel.remove()
        host = nil
        textView?.clearPreview(self)
    }
}
struct ChatSourcePreview: View {
    static let width: CGFloat = 300
    static let cornerRadius: CGFloat = 18
    static let outerPadding: CGFloat = 6
    static let rowCornerRadius: CGFloat = cornerRadius - outerPadding
    static let titleFontSize: CGFloat = 14
    static let metaFontSize: CGFloat = 12
    static let faviconSize: CGFloat = 13
    let sources: [URL]
    var metadata: [URL: ChatLinkService.Preview] = [:]
    var onOpen: ((URL) -> Void)? = nil

    private static let dayParser: DateFormatter = {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        return parser
    }()

    private static func date(_ source: String?) -> String? {
        guard let source else { return nil }
        let day = String(source.prefix(10))
        guard let date = dayParser.date(from: day) else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sources.enumerated()), id: \.element) { index, url in
                if index > 0 {
                    Rectangle().fill(ThemeColor.kBorder).frame(height: 1)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                }
                Button {
                    if let onOpen {
                        onOpen(url)
                    } else {
                        _ = ToolService.openLauncherURL(url)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            ChatSourceFavicon(data: metadata[url]?.favicon)
                            Text(metadata[url]?.siteName ?? ChatSourceTextView.domain(url))
                                .font(.system(size: Self.metaFontSize))
                                .foregroundStyle(ThemeColor.kTextSubtle)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Text(metadata[url]?.title ?? url.absoluteString)
                            .font(.system(size: Self.titleFontSize)).foregroundStyle(ThemeColor.kText)
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        if let date = Self.date(metadata[url]?.publishedAt) {
                            Text(date).font(.system(size: Self.metaFontSize)).foregroundStyle(ThemeColor.kTextSubtle)
                        }
                    }.multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                }.buttonStyle(GlassRowButtonStyle(cornerRadius: Self.rowCornerRadius))
            }
        }.padding(Self.outerPadding)
            .frame(width: Self.width, alignment: .leading)
    }
}

private struct ChatSourceFavicon: View {
    let data: Data?

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(mingCute: "globe", size: 12)
                    .foregroundStyle(ThemeColor.kTextSubtle)
            }
        }
        .frame(width: ChatSourcePreview.faviconSize, height: ChatSourcePreview.faviconSize)
    }
}
