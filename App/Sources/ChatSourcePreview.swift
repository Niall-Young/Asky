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

/// Source attachments are the only hover targets, regardless of the original Markdown label.
final class ChatSourceTextView: ChatSelectableTextView, NSTextViewDelegate {
    private var hoverTask: Task<Void, Never>?
    private var sourceURL: URL?
    private var sourceTrackingArea: NSTrackingArea?
    private(set) var preview: ChatSourcePopover?
    var hasSourceBadges = false {
        didSet {
            guard hasSourceBadges != oldValue else { return }
            if !hasSourceBadges { cancelPendingHover() }
            syncScrollGuard()
            if window != nil { updateTrackingAreas() }
        }
    }

    static func isCitation(_ label: String) -> Bool {
        let label = label.trimmingCharacters(in: CharacterSet(charactersIn: "[]【】 "))
        return Int(label) != nil || ["来源", "引用", "source", "citation"].contains(label.lowercased())
    }

    static func sources(in content: AttributedString) -> [URL] {
        var result: [URL] = []
        for run in content.runs {
            if run.imageURL == nil, let url = run.link, ChatImageService.supports(url), !result.contains(url) { result.append(url) }
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
        guard let sources = textStorage?.attribute(.chatSources, at: charIndex, effectiveRange: nil) as? [URL],
              !sources.isEmpty else {
            if let url = link as? URL, url.scheme?.lowercased() == "mailto" { _ = ToolService.openLauncherURL(url) }
            return true
        }
        openSources(sources, at: charIndex)
        return true
    }

    func textView(_ textView: NSTextView, willDisplayToolTip tooltip: String, forCharacterAt characterIndex: Int) -> String? {
        guard let storage = textStorage, characterIndex < storage.length else { return tooltip }
        if storage.attribute(.chatSources, at: characterIndex, effectiveRange: nil) != nil { return nil }
        return tooltip
    }

    private func openSources(_ sources: [URL], at index: Int) {
        guard sourceAnchor(at: index) != nil else { return }
        hoverTask?.cancel()
        hoverTask = nil
        preview?.close()
        sourceURL = sources.first
        let preview = ChatSourcePopover(textView: self, index: index, sources: sources)
        self.preview = preview
        preview.show()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let sourceTrackingArea {
            removeTrackingArea(sourceTrackingArea)
            self.sourceTrackingArea = nil
        }
        guard hasSourceBadges else { return }
        let area = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
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

    private func source(at location: NSPoint) -> (index: Int, sources: [URL])? {
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
        // header or an action. Do not set a text cursor or open covered sources.
        if ActionArrowCursor.applyIfCovered(event, in: window) {
            cancelPendingHover()
            return
        }
        super.mouseMoved(with: event)
        guard hasSourceBadges else { return }
        cursorUpdate(with: event)
        guard let window, !ChatSourceScrollGuard.shared.isSuppressed(for: window) else {
            cancelPendingHover(); return
        }
        guard let (index, sources) = source(at: event.locationInWindow), let url = sources.first else {
            cancelPendingHover(); return
        }
        if sourceURL == url, hoverTask != nil || preview?.isShown == true { return }
        guard let initialAnchor = sourceAnchor(at: index) else {
            cancelPendingHover(); return
        }
        hoverTask?.cancel()
        preview?.close()
        sourceURL = url
        hoverTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, let window = self.window,
                  !ChatSourceScrollGuard.shared.isSuppressed(for: window),
                  let currentAnchor = self.sourceAnchor(at: index),
                  abs(currentAnchor.origin.x - initialAnchor.origin.x) < 1,
                  abs(currentAnchor.origin.y - initialAnchor.origin.y) < 1 else {
                self?.cancelPendingHover()
                return
            }
            self.openSources(sources, at: index)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        cancelPendingHover()
    }

    func cancelPendingHover() {
        hoverTask?.cancel()
        hoverTask = nil
        if preview?.isShown != true { sourceURL = nil }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncScrollGuard()
        if window == nil { cancelPendingHover(); preview?.close(); preview = nil; sourceURL = nil }
    }

    private func syncScrollGuard() {
        if window != nil && hasSourceBadges {
            ChatSourceScrollGuard.shared.register(self)
        } else {
            ChatSourceScrollGuard.shared.unregister(self)
        }
    }

    deinit {
        MainActor.assumeIsolated { ChatSourceScrollGuard.shared.unregister(self) }
    }
}

/// Suppresses citation hover popovers during conversation scrolling and dismisses open cards
/// so accidental pointer hovers over badges never interrupt scrolling.
@MainActor
final class ChatSourceScrollGuard {
    static let shared = ChatSourceScrollGuard()

    struct WindowScrollState {
        var activeGesture = false
        var activeMomentum = false
        var lastEventTime: TimeInterval = 0
        var suppressedUntil: TimeInterval = 0

        mutating func record(
            phase: NSEvent.Phase,
            momentumPhase: NSEvent.Phase,
            hasDelta: Bool,
            at now: TimeInterval
        ) -> Bool {
            if !momentumPhase.isEmpty {
                lastEventTime = now
                if momentumPhase.contains(.ended) || momentumPhase.contains(.cancelled) {
                    activeMomentum = false
                    suppressedUntil = max(suppressedUntil, now + 0.25)
                } else {
                    activeMomentum = true
                    suppressedUntil = max(suppressedUntil, now + 0.35)
                }
                return true
            }

            if !phase.isEmpty {
                if phase == .mayBegin && !hasDelta { return false }
                lastEventTime = now
                if phase.contains(.ended) || phase.contains(.cancelled) {
                    activeGesture = false
                    suppressedUntil = max(suppressedUntil, now + 0.3)
                } else {
                    activeGesture = true
                    activeMomentum = false
                    suppressedUntil = max(suppressedUntil, now + 0.35)
                }
                return true
            }

            guard hasDelta else { return false }
            activeGesture = false
            activeMomentum = false
            lastEventTime = now
            suppressedUntil = max(suppressedUntil, now + 0.35)
            return true
        }

        func isSuppressed(at now: TimeInterval) -> Bool {
            if now < suppressedUntil { return true }
            // Safety cap in case AppKit drops an ended/cancelled phase event.
            if (activeGesture || activeMomentum), now - lastEventTime < 0.6 { return true }
            return false
        }
    }

    private struct Entry { weak var textView: ChatSourceTextView? }
    private var entries: [Entry] = []
    private var states: [ObjectIdentifier: WindowScrollState] = [:]
    nonisolated(unsafe) private var monitor: Any?

    func register(_ textView: ChatSourceTextView) {
        entries.removeAll { $0.textView == nil || $0.textView === textView }
        entries.append(Entry(textView: textView))
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    self?.handle(event) ?? false
                }
                return consumed ? nil : event
            }
        }
    }

    func unregister(_ textView: ChatSourceTextView) {
        entries.removeAll { $0.textView == nil || $0.textView === textView }
        if entries.isEmpty, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            states.removeAll()
        }
    }

    func isSuppressed(for window: NSWindow, at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        states[ObjectIdentifier(window)]?.isSuppressed(at: now) ?? false
    }

    @discardableResult
    func recordScroll(
        in window: NSWindow,
        phase: NSEvent.Phase,
        momentumPhase: NSEvent.Phase,
        hasDelta: Bool,
        at now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        var state = states[ObjectIdentifier(window)] ?? WindowScrollState()
        guard state.record(phase: phase, momentumPhase: momentumPhase, hasDelta: hasDelta, at: now) else {
            return false
        }
        states[ObjectIdentifier(window)] = state
        if let active = ChatSourcePopover.active, active.isShown, active.parentWindow === window {
            active.close()
        }
        for entry in entries where entry.textView?.window === window {
            entry.textView?.cancelPendingHover()
        }
        return true
    }

    @discardableResult
    func handle(_ event: NSEvent, at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        entries.removeAll { $0.textView == nil }
        let hasDelta = event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 || event.deltaX != 0 || event.deltaY != 0

        if let active = ChatSourcePopover.active, active.isShown, event.window === active.panel {
            if active.isScrollable { return false }
            guard let parent = active.parentWindow else { return false }
            let scroll = active.enclosingScrollView
            guard recordScroll(in: parent, phase: event.phase, momentumPhase: event.momentumPhase, hasDelta: hasDelta, at: now) else {
                return false
            }
            if let scroll {
                scroll.scrollWheel(with: event)
                return true
            }
            return false
        }

        guard let window = event.window else { return false }
        let hasTarget = entries.contains { $0.textView?.window === window }
            || (ChatSourcePopover.active?.isShown == true && ChatSourcePopover.active?.parentWindow === window)
        guard hasTarget else { return false }

        _ = recordScroll(in: window, phase: event.phase, momentumPhase: event.momentumPhase, hasDelta: hasDelta, at: now)
        return false
    }

    func resetForTesting(window: NSWindow? = nil) {
        if let window { states.removeValue(forKey: ObjectIdentifier(window)) }
        else { states.removeAll() }
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
    private var trackingTask: Task<Void, Never>?
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
        trackingTask = Task { @MainActor [weak self] in
            var outside = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, self.isShown else { return }
                guard let anchor = self.reposition() else { self.close(); return }
                let pointer = NSEvent.mouseLocation
                if self.panel.frame.insetBy(dx: -8, dy: -8).contains(pointer) || anchor.insetBy(dx: -10, dy: -10).contains(pointer) {
                    outside = 0
                } else { outside += 1 }
                if outside >= 4 { self.close(); return }
            }
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
        let rows = ChatSourcePreview(sources: sources, metadata: metadata)
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
        trackingTask?.cancel()
        panel.remove()
        host = nil
    }
}
struct ChatSourcePreview: View {
    static let width: CGFloat = 300
    static let cornerRadius: CGFloat = 18
    static let outerPadding: CGFloat = 6
    static let rowCornerRadius: CGFloat = cornerRadius - outerPadding
    let sources: [URL]
    var metadata: [URL: ChatLinkService.Preview] = [:]

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
                Link(destination: url) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            ChatSourceFavicon(data: metadata[url]?.favicon)
                            Text(metadata[url]?.siteName ?? ChatSourceTextView.domain(url))
                                .font(.system(size: 13))
                                .foregroundStyle(ThemeColor.kTextSubtle)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Text(metadata[url]?.title ?? url.absoluteString)
                            .font(.system(size: 15)).foregroundStyle(ThemeColor.kText)
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        if let date = Self.date(metadata[url]?.publishedAt) {
                            Text(date).font(.system(size: 13)).foregroundStyle(ThemeColor.kTextSubtle)
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
                Image(mingCute: "globe", size: 13)
                    .foregroundStyle(ThemeColor.kTextSubtle)
            }
        }
        .frame(width: 14, height: 14)
    }
}
