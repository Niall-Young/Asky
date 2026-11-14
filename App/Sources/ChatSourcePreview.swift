import AppKit
import SwiftUI
import ToolService
import Theme

/// Source attachments are the only hover targets, regardless of the original Markdown label.
final class ChatSourceTextView: NSTextView {
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

    static func badge(icon: NSImage?, foreground: NSColor, background: NSColor) -> NSImage {
        let image = icon ?? MingCute.image("globe")
        return NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            background.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).fill()
            let target = NSRect(x: 3, y: 3, width: 12, height: 12)
            if icon == nil {
                let tinted = image.copy() as! NSImage
                tinted.lockFocus()
                foreground.setFill()
                NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
                tinted.unlockFocus()
                tinted.draw(in: target)
            } else { image.draw(in: target) }
            return true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let sourceTrackingArea { removeTrackingArea(sourceTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
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

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard let manager = layoutManager, let container = textContainer, let storage = textStorage else { return }
        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y
        let glyph = manager.glyphIndex(for: point, in: container)
        guard glyph < manager.numberOfGlyphs,
              manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).insetBy(dx: -2, dy: -2).contains(point) else {
            cancelPendingHover(); return
        }
        let index = manager.characterIndexForGlyph(at: glyph)
        guard index < storage.length,
              storage.attribute(.attachment, at: index, effectiveRange: nil) != nil,
              let url = storage.attribute(.link, at: index, effectiveRange: nil) as? URL,
              ChatImageService.supports(url) else { cancelPendingHover(); return }
        if sourceURL == url, hoverTask != nil || preview?.isShown == true { return }
        hoverTask?.cancel()
        preview?.close()
        sourceURL = url
        hoverTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, self.sourceAnchor(at: index) != nil else { return }
            self.hoverTask = nil
            let preview = ChatSourcePopover(textView: self, index: index, url: url)
            self.preview = preview
            preview.show()
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
    private let url: URL
    private var metadataTask: Task<Void, Never>?
    private var trackingTask: Task<Void, Never>?
    var isShown: Bool { panel.isVisible }
    var contentView: NSView? { panel.contentView }

    init(textView: ChatSourceTextView, index: Int, url: URL) {
        self.textView = textView
        self.index = index
        self.url = url
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
        update(metadata: nil)
        parent.addChildWindow(panel, ordered: .above)
        panel.matchesActiveAppearance = parent.isKeyWindow
        panel.orderFront(nil)
        metadataTask = Task { @MainActor [weak self, url] in
            let metadata = try? await ChatLinkService.shared.preview(for: url)
            guard !Task.isCancelled else { return }
            self?.update(metadata: metadata)
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

    private func update(metadata: ChatLinkService.Preview?) {
        let view = ChatSourcePreview(url: url, label: "", metadata: metadata)
        let size = SurfacePanel.fittingSize(of: view, maxWidth: 300)
        panel.setSurface(view, size: size, cornerRadius: 16)
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
    }
}
struct ChatSourcePreview: View {
    let url: URL
    let label: String
    var metadata: ChatLinkService.Preview? = nil

    private var domain: String { url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString }
    private var title: String {
        metadata?.title.flatMap { $0.isEmpty ? nil : $0 }
            ?? (label.isEmpty || ChatSourceTextView.isCitation(label) ? domain : label)
    }

    var body: some View {
        Link(destination: url) {
            VStack(alignment: .leading, spacing: 0) {
                if let data = metadata?.image, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: 300, height: 170).clipped()
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium)).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(ThemeColor.kText)
                    if title != domain {
                        Text(domain).font(.system(size: 12))
                            .foregroundStyle(ThemeColor.kTextSubtle).lineLimit(1)
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(width: 300)
        }
        .buttonStyle(.plain)
        .windowSurfaceBackground(in: RoundedRectangle(cornerRadius: 16))
    }
}
