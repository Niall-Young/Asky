import AppKit
import SwiftUI
import ToolService
import Theme

/// Keep source inspection in the selectable text flow, including lists and quoted paragraphs.
final class ChatSourceTextView: NSTextView {
    private var hoverTask: Task<Void, Never>?
    private var sourceURL: URL?
    private var sourceTrackingArea: NSTrackingArea?
    private(set) var preview: NSPopover?

    static func isCitation(_ label: String) -> Bool {
        let label = label.trimmingCharacters(in: CharacterSet(charactersIn: "[]【】 "))
        return Int(label) != nil || ["来源", "引用", "source", "citation"].contains(label.lowercased())
    }

    static func badge(_ label: String, foreground: NSColor, background: NSColor) -> NSImage {
        let number = label.trimmingCharacters(in: CharacterSet(charactersIn: "[]【】 "))
        let text = Int(number) == nil ? "↗" : number
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: foreground]
        let size = (text as NSString).size(withAttributes: attributes)
        return NSImage(size: NSSize(width: max(18, size.width + 10), height: 18), flipped: false) { rect in
            background.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
            (text as NSString).draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2), withAttributes: attributes)
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

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard let manager = layoutManager, let container = textContainer, let storage = textStorage else { return }
        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y
        let glyph = manager.glyphIndex(for: point, in: container)
        guard glyph < manager.numberOfGlyphs,
              manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).insetBy(dx: -2, dy: -2).contains(point) else {
            scheduleDismissal(); return
        }
        let index = manager.characterIndexForGlyph(at: glyph)
        var range = NSRange()
        guard index < storage.length,
              let url = storage.attribute(.link, at: index, effectiveRange: &range) as? URL,
              ChatImageService.supports(url) else { scheduleDismissal(); return }
        guard sourceURL != url else { return }
        hoverTask?.cancel()
        preview?.close()
        sourceURL = url
        let title = storage.attributedSubstring(from: range).string.replacingOccurrences(of: "\u{fffc}", with: "")
        var rect = manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        hoverTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, self.window != nil else { return }
            let popover = NSPopover()
            popover.behavior = .semitransient
            popover.animates = false
            popover.contentViewController = NSHostingController(rootView: ChatSourcePreview(url: url, label: title))
            self.preview = popover
            popover.show(relativeTo: rect, of: self, preferredEdge: .maxY)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        scheduleDismissal()
    }

    private func scheduleDismissal() {
        hoverTask?.cancel()
        sourceURL = nil
        hoverTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self else { return }
            if let frame = self.preview?.contentViewController?.view.window?.frame,
               frame.contains(NSEvent.mouseLocation) { return }
            self.preview?.close()
            self.preview = nil
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { hoverTask?.cancel(); preview?.close(); preview = nil; sourceURL = nil }
    }
}

struct ChatSourcePreview: View {
    let url: URL
    let label: String
    @State private var metadata: ChatLinkService.Preview?

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
        .task(id: url) { metadata = try? await ChatLinkService.shared.preview(for: url) }
    }
}
