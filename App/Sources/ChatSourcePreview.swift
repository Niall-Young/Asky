import AppKit
import CoreText
import SwiftUI
import ToolService
import Theme

extension NSAttributedString.Key {
    static let chatSources = NSAttributedString.Key("AskySourceGroup")
}

/// Source attachments are the only hover targets, regardless of the original Markdown label.
final class ChatSourceTextView: ChatSelectableTextView, NSTextViewDelegate {
    private var hoverTask: Task<Void, Never>?
    private var sourceURL: URL?
    private var sourceTrackingArea: NSTrackingArea?
    private(set) var preview: ChatSourcePopover?

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

    static func badge(name: String, count: Int, foreground: NSColor, background: NSColor) -> (image: NSImage, baseline: CGFloat) {
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
        let image = NSImage(size: NSSize(width: ceil(width) + 20, height: 24), flipped: false) { rect in
            background.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: 10, y: baseline)
            CTLineDraw(line, context)
            context.restoreGState()
            return true
        }
        return (image, baseline)
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
        if let sourceTrackingArea { removeTrackingArea(sourceTrackingArea) }
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
        if source(at: event.locationInWindow) != nil { NSCursor.arrow.set() }
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
        cursorUpdate(with: event)
        guard let (index, sources) = source(at: event.locationInWindow), let url = sources.first else {
            cancelPendingHover(); return
        }
        if sourceURL == url, hoverTask != nil || preview?.isShown == true { return }
        hoverTask?.cancel()
        preview?.close()
        sourceURL = url
        hoverTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, self.sourceAnchor(at: index) != nil else { return }
            self.openSources(sources, at: index)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        cancelPendingHover()
    }

    private func cancelPendingHover() {
        hoverTask?.cancel()
        hoverTask = nil
        if preview?.isShown != true { sourceURL = nil }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { cancelPendingHover(); preview?.close(); preview = nil; sourceURL = nil }
    }
}

/// A window-sized glass card stays attached to the source even in a scrolled transcript.
@MainActor
final class ChatSourcePopover {
    private static weak var active: ChatSourcePopover?
    let panel = SurfacePanel()
    private weak var textView: ChatSourceTextView?
    private let index: Int
    private let sources: [URL]
    private var metadata: [URL: ChatLinkService.Preview] = [:]
    private var host: FirstMouseHostingView<AnyView>?
    private var metadataTask: Task<Void, Never>?
    private var trackingTask: Task<Void, Never>?
    var isShown: Bool { panel.isVisible }
    var contentView: NSView? { panel.contentView }

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
        panel.appearance = parent.effectiveAppearance
        update()
        parent.addChildWindow(panel, ordered: .above)
        panel.matchesActiveAppearance = parent.isKeyWindow
        panel.orderFront(nil)
        metadataTask = Task { @MainActor [weak self, sources] in
            await withTaskGroup(of: (URL, ChatLinkService.Preview?).self) { group in
                var pending = sources.makeIterator()
                for _ in 0..<min(4, sources.count) {
                    if let url = pending.next() { group.addTask { (url, try? await ChatLinkService.shared.preview(for: url)) } }
                }
                for await (url, metadata) in group {
                    guard !Task.isCancelled else { group.cancelAll(); return }
                    if let metadata { self?.metadata[url] = metadata; self?.update() }
                    if let next = pending.next() { group.addTask { (next, try? await ChatLinkService.shared.preview(for: next)) } }
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

    private func update() {
        let rows = ChatSourcePreview(sources: sources, metadata: metadata)
        let measured = SurfacePanel.fittingSize(of: rows, maxWidth: ChatSourcePreview.width)
        let available = textView?.window?.screen?.visibleFrame.height ?? 700
        let size = NSSize(width: ChatSourcePreview.width, height: min(measured.height, min(460, available - 32)))
        let view = ScrollView { rows }.frame(width: size.width, height: size.height)
            .windowSurfaceBackground(in: RoundedRectangle(cornerRadius: 12))
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
            panel.contentView = WindowSurface.glassContentView(host, cornerRadius: 12)
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
        metadataTask?.cancel()
        trackingTask?.cancel()
        panel.remove()
        host = nil
    }
}
struct ChatSourcePreview: View {
    static let width: CGFloat = 300
    let sources: [URL]
    var metadata: [URL: ChatLinkService.Preview] = [:]

    private static func date(_ source: String?) -> String? {
        guard let source else { return nil }
        let day = String(source.prefix(10))
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return nil }
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
                        Text(metadata[url]?.siteName ?? ChatSourceTextView.domain(url))
                            .font(.system(size: 13)).foregroundStyle(ThemeColor.kTextSubtle)
                        Text(metadata[url]?.title ?? url.absoluteString)
                            .font(.system(size: 15)).foregroundStyle(ThemeColor.kText)
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        if let date = Self.date(metadata[url]?.publishedAt) {
                            Text(date).font(.system(size: 13)).foregroundStyle(ThemeColor.kTextSubtle)
                        }
                    }.multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                }.buttonStyle(AgentIconButtonStyle(cornerRadius: 8))
            }
        }.padding(4)
            .frame(width: Self.width, alignment: .leading)
    }
}
