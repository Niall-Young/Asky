import AppKit
import SwiftUI
import Theme
import ToolService

struct ChatBubbleContextActions {
    let copy: () -> Void
    let reply: () -> Void
    let share: () -> Void
}

private struct ChatSelectionColorKey: EnvironmentKey {
    static let defaultValue = AgentAvatarColor.blue.tint
}
private struct ChatQuoteActionKey: EnvironmentKey {
    static var defaultValue: ((String) -> Void)? { nil }
}
private struct ChatBubbleContextActionsKey: EnvironmentKey {
    static var defaultValue: ChatBubbleContextActions? { nil }
}
extension EnvironmentValues {
    var chatSelectionColor: Color {
        get { self[ChatSelectionColorKey.self] }
        set { self[ChatSelectionColorKey.self] = newValue }
    }
    var chatQuoteAction: ((String) -> Void)? {
        get { self[ChatQuoteActionKey.self] }
        set { self[ChatQuoteActionKey.self] = newValue }
    }
    var chatBubbleContextActions: ChatBubbleContextActions? {
        get { self[ChatBubbleContextActionsKey.self] }
        set { self[ChatBubbleContextActionsKey.self] = newValue }
    }
}
extension NSAttributedString.Key {
    static let chatSelectionText = NSAttributedString.Key("AskySelectionText")
}

/// Attachment glyphs retain readable source when copied or quoted.
class ChatSelectableTextView: NSTextView {
    var quoteAction: ((String) -> Void)?
    var contextActions: ChatBubbleContextActions?
    weak var selectionGroup: ChatSelectionGroup?
    private var selectionMenu: ChatSelectionMenu?

    var selectedContent: String { selectionGroup?.selectedText ?? localSelectedContent }

    var localSelectedContent: String {
        guard let storage = textStorage else { return "" }
        let range = selectedRange()
        guard range.location != NSNotFound, range.length > 0, NSMaxRange(range) <= storage.length else { return "" }
        var result = ""
        storage.enumerateAttributes(in: range) { attributes, segment, _ in
            if let source = attributes[.chatSelectionText] as? String { result += source }
            else if attributes[.attachment] == nil { result += (storage.string as NSString).substring(with: segment) }
        }
        return result
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if newSize.width > 0, let container = textContainer, !container.widthTracksTextView {
            container.containerSize = NSSize(width: newSize.width, height: .greatestFiniteMagnitude)
        }
    }

    override func copy(_ sender: Any?) { _ = MessageClipboard.copy(selectedContent) }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard contextActions != nil else { return super.menu(for: event) }
        selectionMenu?.close(clearSelection: false)
        let menu = NSMenu()
        let hasSelection = !selectedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasSelection {
            let copySelection = NSMenuItem(
                title: NSLocalizedString("复制选中内容", comment: ""),
                action: #selector(copy(_:)),
                keyEquivalent: ""
            )
            copySelection.target = self
            menu.addItem(copySelection)
            if quoteAction != nil {
                let quoteSelection = NSMenuItem(
                    title: NSLocalizedString("添加到对话", comment: ""),
                    action: #selector(performQuoteSelection(_:)),
                    keyEquivalent: ""
                )
                quoteSelection.target = self
                menu.addItem(quoteSelection)
            }
            menu.addItem(.separator())
        }
        let copyItem = NSMenuItem(
            title: NSLocalizedString("复制", comment: ""),
            action: #selector(performBubbleCopy(_:)),
            keyEquivalent: ""
        )
        copyItem.target = self
        menu.addItem(copyItem)

        let replyItem = NSMenuItem(
            title: NSLocalizedString("回复消息", comment: ""),
            action: #selector(performBubbleReply(_:)),
            keyEquivalent: ""
        )
        replyItem.target = self
        menu.addItem(replyItem)

        let shareItem = NSMenuItem(
            title: NSLocalizedString("分享回复", comment: ""),
            action: #selector(performBubbleShare(_:)),
            keyEquivalent: ""
        )
        shareItem.target = self
        menu.addItem(shareItem)
        return menu
    }

    @objc private func performQuoteSelection(_ sender: Any?) {
        let content = selectedContent
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        quoteAction?(content)
    }

    @objc private func performBubbleCopy(_ sender: Any?) {
        contextActions?.copy()
    }

    @objc private func performBubbleReply(_ sender: Any?) {
        contextActions?.reply()
    }

    @objc private func performBubbleShare(_ sender: Any?) {
        contextActions?.share()
    }

    override func cursorUpdate(with event: NSEvent) {
        guard !ActionArrowCursor.applyIfCovered(event, in: window) else { return }
        super.cursorUpdate(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        guard !ActionArrowCursor.applyIfCovered(event, in: window) else { return }
        super.mouseMoved(with: event)
    }

    override func selectAll(_ sender: Any?) {
        if let selectionGroup { selectionGroup.selectAll(); showSelectionMenu() }
        else { super.selectAll(sender) }
    }

    override func mouseDown(with event: NSEvent) {
        selectionMenu?.close(clearSelection: false)
        if selectionGroup?.trackDrag(from: self, event: event) == true { return }
        selectionGroup?.clear(except: self)
        super.mouseDown(with: event)
        showSelectionMenu()
    }

    override func keyDown(with event: NSEvent) {
        selectionMenu?.close(clearSelection: event.keyCode == 53)
        if event.keyCode == 53 { selectionGroup?.clear(); return }
        if !event.modifierFlags.contains(.command) { selectionGroup?.clear(except: self) }
        super.keyDown(with: event)
        if event.keyCode != 53 { showSelectionMenu() }
    }

    func showSelectionMenu() {
        selectionMenu?.close(clearSelection: false)
        guard quoteAction != nil, !selectedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let menu = ChatSelectionMenu(textView: self)
        selectionMenu = menu
        menu.show()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { selectionMenu?.close(); selectionMenu = nil }
    }
}

@MainActor
final class ChatSelectionMenu {
    private static weak var active: ChatSelectionMenu?
    let panel = SurfacePanel()
    private weak var textView: ChatSelectableTextView?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var activated = false

    init(textView: ChatSelectableTextView) { self.textView = textView }

    func show() {
        guard let textView, let parent = textView.window, let manager = textView.layoutManager,
              let container = textView.textContainer, let screen = parent.screen else { return }
        let range = textView.selectedRange()
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        rect = rect.intersection(textView.visibleRect)
        guard !rect.isEmpty else { return }
        if let active = Self.active {
            let sameGroup = textView.selectionGroup != nil && active.textView?.selectionGroup === textView.selectionGroup
            active.close(clearSelection: !sameGroup)
        }
        Self.active = self
        let selection = textView.selectedContent
        let action = textView.quoteAction
        let content = ChatSelectionActions(copy: { [weak self] in
            guard let self, !self.activated else { return }
            if MessageClipboard.copy(selection) {
                self.activated = true
                self.close()
            }
        }, quote: { [weak self] in
            guard let self, !self.activated else { return }
            self.activated = true
            self.close()
            action?(selection)
        })
        let size = SurfacePanel.fittingSize(of: content, maxWidth: 320)
        let host = FirstMouseHostingView(rootView: content)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        // This compact text menu keeps the glass rim without an extra dark window shadow.
        panel.hasShadow = false
        panel.setContentSize(size)
        panel.contentView = WindowSurface.glassContentView(host, cornerRadius: size.height / 2)
        if let surface = panel.contentView { WindowSurface.updateCorners(of: surface, radius: size.height / 2, circular: true) }
        panel.appearance = parent.effectiveAppearance
        let anchor = parent.convertToScreen(textView.convert(rect, to: nil))
        let limits = screen.visibleFrame.intersection(parent.frame).insetBy(dx: 8, dy: 8)
        var y = anchor.maxY + 6
        if y + size.height > limits.maxY { y = anchor.minY - size.height - 6 }
        let x = min(max(anchor.midX - size.width / 2, limits.minX), limits.maxX - size.width)
        panel.setFrameOrigin(NSPoint(x: x, y: max(limits.minY, y)))
        parent.addChildWindow(panel, ordered: .above)
        panel.matchesActiveAppearance = parent.isKeyWindow
        panel.orderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.close(); return nil }
                // Let the text responder process shortcuts/Shift-arrows before changing its range.
                return event
            }
            if event.window !== self.panel {
                let insideText = event.type != .scrollWheel && event.window === self.textView?.window
                    && self.textView.map { $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) } == true
                self.close(clearSelection: !insideText)
            }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
            object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
    }

    func close(clearSelection: Bool = true) {
        if Self.active === self { Self.active = nil }
        if clearSelection, let textView {
            textView.selectionGroup?.clear()
            let location = min(textView.selectedRange().location, (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            textView.needsDisplay = true
        }
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
        panel.remove()
    }
}

private struct ChatSelectionActions: View {
    let copy: () -> Void
    let quote: () -> Void
    @State private var copyHovered = false
    @State private var quoteHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var leadingLight: Double { copyHovered ? 0.25 : 0 }
    private var trailingLight: Double { quoteHovered ? 0.25 : 0 }

    var body: some View {
        HStack(spacing: 2) {
            Button(action: copy) {
                Label { Text("复制") } icon: { Image("ChatCopy").resizable().frame(width: 14, height: 14) }
                    .padding(.horizontal, 10).frame(height: 30).contentShape(.rect)
            }
            .buttonStyle(ChatSelectionActionStyle(hovered: $copyHovered))
            Button(action: quote) {
                Label { Text("添加到对话") } icon: { Image(mingCute: "bubble.left", size: 14) }
                    .padding(.horizontal, 10).frame(height: 30).contentShape(.rect)
            }
            .buttonStyle(ChatSelectionActionStyle(hovered: $quoteHovered))
        }
        .font(.system(size: 13)).foregroundStyle(ThemeColor.kText)
        .padding(4)
        .windowSurfaceBackground(in: Capsule())
        .background {
            // A broad light wash across one continuous surface, matching the supplied recording.
            // It fades through the middle instead of ending at either button's bounds.
            Capsule()
                .fill(LinearGradient(stops: [
                    .init(color: .white.opacity(leadingLight * 0.16), location: 0),
                    .init(color: .white.opacity(leadingLight * 0.07 + trailingLight * 0.01), location: 0.4),
                    .init(color: .white.opacity(trailingLight * 0.07 + leadingLight * 0.01), location: 0.6),
                    .init(color: .white.opacity(trailingLight * 0.16), location: 1)
                ], startPoint: .leading, endPoint: .trailing))
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .glassPointerFeedback(pressed: false, in: Capsule(), illumination: false)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: leadingLight)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: trailingLight)
    }
}

/// Track each action independently while the parent owns the continuous glass light.
private struct ChatSelectionActionStyle: ButtonStyle {
    @Binding var hovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onHover { hovered = $0 }
            .onDisappear { hovered = false }
    }
}
