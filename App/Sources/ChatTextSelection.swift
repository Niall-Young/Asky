import AppKit
import SwiftUI
import Theme
import ToolService

private struct ChatSelectionColorKey: EnvironmentKey {
    static let defaultValue = AgentAvatarColor.blue.tint
}
private struct ChatQuoteActionKey: EnvironmentKey {
    static var defaultValue: ((String) -> Void)? { nil }
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
}
extension NSAttributedString.Key {
    static let chatSelectionText = NSAttributedString.Key("AskySelectionText")
}

/// Attachment glyphs retain readable source when copied or quoted.
class ChatSelectableTextView: NSTextView {
    var quoteAction: ((String) -> Void)?
    private var selectionMenu: ChatSelectionMenu?

    var selectedContent: String {
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

    override func copy(_ sender: Any?) { _ = MessageClipboard.copy(selectedContent) }

    override func mouseDown(with event: NSEvent) {
        selectionMenu?.close()
        super.mouseDown(with: event)
        showSelectionMenu()
    }

    override func keyDown(with event: NSEvent) {
        selectionMenu?.close()
        super.keyDown(with: event)
        if event.keyCode != 53 { showSelectionMenu() }
    }

    func showSelectionMenu() {
        selectionMenu?.close()
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
        Self.active?.close()
        Self.active = self
        let selection = textView.selectedContent
        let action = textView.quoteAction
        let content = HStack(spacing: 2) {
            Button { [weak self] in
                if MessageClipboard.copy(selection) { self?.close() }
            } label: {
                Label { Text("复制") } icon: { Image("ChatCopy").resizable().frame(width: 14, height: 14) }
                    .padding(.horizontal, 10).frame(height: 30)
            }
            Button { [weak self] in
                self?.close()
                action?(selection)
            } label: {
                Label { Text("添加到对话") } icon: { Image(mingCute: "plus", size: 14) }
                    .padding(.horizontal, 10).frame(height: 30)
            }
        }
        .font(.system(size: 13)).foregroundStyle(ThemeColor.kText)
        .buttonStyle(AgentIconButtonStyle(cornerRadius: 12))
        .padding(4)
        .windowSurfaceBackground(in: RoundedRectangle(cornerRadius: 16))
        let size = SurfacePanel.fittingSize(of: content, maxWidth: 320)
        let host = FirstMouseHostingView(rootView: content)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
        panel.contentView = WindowSurface.glassContentView(host, cornerRadius: 16)
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
            if event.window !== self.panel { self.close() }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
            object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
        panel.remove()
    }
}
