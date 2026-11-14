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
        selectionMenu?.close(clearSelection: false)
        super.mouseDown(with: event)
        showSelectionMenu()
    }

    override func keyDown(with event: NSEvent) {
        selectionMenu?.close(clearSelection: event.keyCode == 53)
        if event.keyCode == 53 { return }
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
    private let pressSpring = SurfaceSpring()
    private var restingFrame: NSRect?
    private var dismissalTask: Task<Void, Never>?
    private var activated = false
    private var reduceMotion = false
    private var pressLeading = false

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
        let content = ChatSelectionActions(copy: { [weak self] in
            guard let self, !self.activated else { return }
            if MessageClipboard.copy(selection) { self.dismissAfterFeedback() }
        }, quote: { [weak self] in
            guard let self, !self.activated else { return }
            action?(selection)
            self.dismissAfterFeedback()
        }, pressChanged: { [weak self] pressed, reduceMotion, leading in
            self?.setPressed(pressed, reduceMotion: reduceMotion, leading: leading)
        })
        let size = SurfacePanel.fittingSize(of: content, maxWidth: 320)
        let host = FirstMouseHostingView(rootView: content)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        // This compact text menu keeps the glass rim without an extra dark window shadow.
        panel.hasShadow = false
        panel.setContentSize(size)
        panel.contentView = WindowSurface.glassContentView(host, cornerRadius: 16)
        panel.appearance = parent.effectiveAppearance
        let anchor = parent.convertToScreen(textView.convert(rect, to: nil))
        let limits = screen.visibleFrame.intersection(parent.frame).insetBy(dx: 8, dy: 8)
        var y = anchor.maxY + 6
        if y + size.height > limits.maxY { y = anchor.minY - size.height - 6 }
        let x = min(max(anchor.midX - size.width / 2, limits.minX), limits.maxX - size.width)
        panel.setFrameOrigin(NSPoint(x: x, y: max(limits.minY, y)))
        restingFrame = panel.frame
        pressSpring.onStep = { [weak self] progress in
            guard let self, let frame = self.restingFrame else { return }
            let growth = min(0.06, 3 / max(frame.width, frame.height, 1)) * progress
            let expanded = NSRect(x: frame.minX - (self.pressLeading ? frame.width * growth : 0),
                y: frame.minY - frame.height * growth / 2,
                width: frame.width * (1 + growth), height: frame.height * (1 + growth))
            self.panel.setFrame(expanded, display: true)
        }
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

    private func setPressed(_ pressed: Bool, reduceMotion: Bool, leading: Bool) {
        if pressed { pressLeading = leading }
        self.reduceMotion = reduceMotion
        guard panel.isVisible else { return }
        if reduceMotion { pressSpring.set(0) }
        else { pressSpring.animate(to: pressed ? 1 : 0, response: pressed ? 0.18 : 0.34,
                                   damping: pressed ? 1 : 0.42, in: panel) }
    }

    private func dismissAfterFeedback() {
        activated = true
        if reduceMotion { close(); return }
        // Execute immediately, but keep the surface briefly so its release spring is visible.
        dismissalTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
            self?.close()
        }
    }

    func close(clearSelection: Bool = true) {
        if clearSelection, let textView {
            let location = min(textView.selectedRange().location, (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            textView.needsDisplay = true
        }
        dismissalTask?.cancel()
        dismissalTask = nil
        pressSpring.stop()
        restingFrame = nil
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
        panel.remove()
    }
}

private struct ChatSelectionActions: View {
    let copy: () -> Void
    let quote: () -> Void
    let pressChanged: (Bool, Bool, Bool) -> Void
    @State private var copyPressed = false
    @State private var quotePressed = false
    @State private var copyHovered = false
    @State private var quoteHovered = false
    private var pressed: Bool { copyPressed || quotePressed }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var leadingLight: Double { copyPressed ? 1 : pressed ? 0 : copyHovered ? 0.25 : 0 }
    private var trailingLight: Double { quotePressed ? 1 : pressed ? 0 : quoteHovered ? 0.25 : 0 }

    var body: some View {
        HStack(spacing: 2) {
            Button(action: copy) {
                Label { Text("复制") } icon: { Image("ChatCopy").resizable().frame(width: 14, height: 14) }
                    .padding(.horizontal, 10).frame(height: 30).contentShape(.rect)
            }
            .buttonStyle(ChatSelectionActionStyle(pressed: $copyPressed, hovered: $copyHovered))
            Button(action: quote) {
                Label { Text("添加到对话") } icon: { Image(mingCute: "bubble.left", size: 14) }
                    .padding(.horizontal, 10).frame(height: 30).contentShape(.rect)
            }
            .buttonStyle(ChatSelectionActionStyle(pressed: $quotePressed, hovered: $quoteHovered))
        }
        .font(.system(size: 13)).foregroundStyle(ThemeColor.kText)
        .padding(4)
        .windowSurfaceBackground(in: RoundedRectangle(cornerRadius: 16))
        .background {
            // A broad light wash across one continuous surface, matching the supplied recording.
            // It fades through the middle instead of ending at either button's bounds.
            RoundedRectangle(cornerRadius: 16)
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
        .glassPointerFeedback(pressed: pressed, in: RoundedRectangle(cornerRadius: 16), illumination: false)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: leadingLight)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: trailingLight)
        .onAppear { pressChanged(false, reduceMotion, false) }
        .onChange(of: pressed) { _, value in pressChanged(value, reduceMotion, copyPressed) }
        .onChange(of: reduceMotion) { _, value in pressChanged(pressed, value, copyPressed) }
    }
}

/// Track each action independently while the parent owns the continuous glass light.
private struct ChatSelectionActionStyle: ButtonStyle {
    @Binding var pressed: Bool
    @Binding var hovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onHover { hovered = $0 }
            .onChange(of: configuration.isPressed) { _, value in pressed = value }
            .onDisappear { pressed = false; hovered = false }
    }
}
