import AppKit
import SwiftUI
import Theme

enum ChatBubblePopoverTarget: Equatable {
    case emojiPicker(messageID: String)
    case assistantMore(messageID: String)
    case userMore(messageID: String)

    var messageID: String {
        switch self {
        case .emojiPicker(let id), .assistantMore(let id), .userMore(let id): id
        }
    }
}

enum ChatBubblePopoverPayload {
    case emojiPicker(selectedEmoji: String?, accentColor: Color, onSelect: (String) -> Void)
    case assistantMore(timestamp: Date?, onCopy: () -> Void, onShare: () -> Void)
    case userMore(timestamp: Date?, canDelete: Bool, onReply: () -> Void, onDelete: () -> Void)
}

@MainActor @Observable
final class ChatBubblePopoverController {
    private(set) var target: ChatBubblePopoverTarget?
    private(set) var anchorRect: CGRect?
    @ObservationIgnored private(set) var payload: ChatBubblePopoverPayload?

    func toggle(_ target: ChatBubblePopoverTarget, anchor: CGRect, payload: ChatBubblePopoverPayload) {
        if self.target == target {
            dismiss()
        } else {
            self.payload = payload
            self.anchorRect = anchor
            self.target = target
        }
    }

    func dismiss() {
        target = nil
        anchorRect = nil
        payload = nil
    }

    func isActive(_ target: ChatBubblePopoverTarget) -> Bool {
        self.target == target
    }

    func isActive(for messageID: String) -> Bool {
        target?.messageID == messageID
    }
}

/// Captures a trigger button's AppKit view so its exact window-space frame can be resolved
/// at click time without relying on SwiftUI preferences crossing an NSScrollView boundary.
@MainActor
final class ChatBubbleAnchorBox {
    weak var view: NSView?

    func swiftUIFrameInWindow() -> CGRect? {
        guard let view, let window = view.window, let content = window.contentView else { return nil }
        let rect = view.convert(view.bounds, to: nil)
        let height = content.bounds.height
        return CGRect(
            x: rect.minX,
            y: height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

struct ChatBubbleAnchorReader: NSViewRepresentable {
    let box: ChatBubbleAnchorBox
    func makeNSView(context: Context) -> NSView {
        let view = PassiveAnchorView()
        box.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }

    private final class PassiveAnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

enum ChatUserReactionCatalog {
    static let quickEmojis = ["👍", "❤️", "😂", "🎉", "😮", "🙏"]
}

struct ChatBubblePopoverPresentation: ViewModifier {
    var controller: ChatBubblePopoverController
    @Binding var showingApprovalMenu: Bool
    var headerHeight: CGFloat
    @State private var monitor: Any?
    @State private var menuView = BubblePopoverWeakViewBox()
    @State private var measuredSize: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if let target = controller.target, let payload = controller.payload, let trigger = controller.anchorRect {
                    GeometryReader { geometry in
                        let menuSize = effectiveSize(for: target)
                        let origin = menuOrigin(for: target, trigger: trigger, menuSize: menuSize, container: geometry.size)
                        popoverContent(for: payload)
                            .background(BubblePopoverViewReader(box: menuView).allowsHitTesting(false))
                            .fixedSize()
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { measuredSize = $0 }
                            .position(x: origin.x + menuSize.width / 2, y: origin.y + menuSize.height / 2)
                    }
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: controller.target)
            .onChange(of: controller.target) { _, newTarget in
                measuredSize = .zero
                if newTarget != nil {
                    if showingApprovalMenu { showingApprovalMenu = false }
                    startMonitoring()
                } else {
                    stopMonitoring()
                }
            }
            .onChange(of: showingApprovalMenu) { _, shown in
                if shown, controller.target != nil {
                    controller.dismiss()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { event in
                if let owner = menuView.view?.window, event.object as? NSWindow === owner {
                    controller.dismiss()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { event in
                if let owner = menuView.view?.window, event.object as? NSWindow === owner {
                    controller.dismiss()
                }
            }
            .onDisappear {
                controller.dismiss()
                stopMonitoring()
            }
    }

    @ViewBuilder
    private func popoverContent(for payload: ChatBubblePopoverPayload) -> some View {
        switch payload {
        case .emojiPicker(let selectedEmoji, let accentColor, let onSelect):
            ChatEmojiReactionPickerView(
                selectedEmoji: selectedEmoji,
                accentColor: accentColor,
                onSelect: { emoji in
                    controller.dismiss()
                    onSelect(emoji)
                }
            )
            .nativeGlassBackground(in: Capsule())
        case .assistantMore(let timestamp, let onCopy, let onShare):
            ChatBubbleMoreMenuView(timestamp: timestamp) {
                ChatBubbleMoreRow(title: NSLocalizedString("复制", comment: "")) {
                    controller.dismiss()
                    onCopy()
                } icon: {
                    Image("ChatCopy").resizable().scaledToFit().frame(width: 14, height: 14)
                }
                .accessibilityIdentifier("bubble-more-copy")

                ChatBubbleMoreRow(title: NSLocalizedString("分享", comment: "")) {
                    controller.dismiss()
                    onShare()
                } icon: {
                    Image("ChatShare").resizable().scaledToFit().frame(width: 14, height: 14)
                }
                .accessibilityIdentifier("bubble-more-share")
            }
            .nativeGlassBackground(in: RoundedRectangle(cornerRadius: 14))
        case .userMore(let timestamp, let canDelete, let onReply, let onDelete):
            ChatBubbleMoreMenuView(timestamp: timestamp) {
                ChatBubbleMoreRow(title: NSLocalizedString("回复", comment: "")) {
                    controller.dismiss()
                    onReply()
                } icon: {
                    Image(mingCute: "arrow.turn.down.left", size: 14)
                }
                .accessibilityIdentifier("bubble-more-reply")

                ChatBubbleMoreRow(title: NSLocalizedString("删除", comment: ""), destructive: true, disabled: !canDelete) {
                    controller.dismiss()
                    onDelete()
                } icon: {
                    Image(mingCute: "trash", size: 14)
                }
                .accessibilityIdentifier("bubble-more-delete")
            }
            .nativeGlassBackground(in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func effectiveSize(for target: ChatBubblePopoverTarget) -> CGSize {
        if measuredSize.width > 0, measuredSize.height > 0 { return measuredSize }
        switch target {
        case .emojiPicker:
            return CGSize(width: 214, height: 40)
        case .assistantMore, .userMore:
            return CGSize(width: 196, height: 110)
        }
    }

    private func menuOrigin(for target: ChatBubblePopoverTarget, trigger: CGRect, menuSize: CGSize, container: CGSize) -> CGPoint {
        let edgeMargin: CGFloat = 12
        let topLimit = headerHeight + 4
        let bottomLimit = container.height - edgeMargin
        let gap: CGFloat = 6

        let x: CGFloat
        let y: CGFloat
        switch target {
        case .emojiPicker:
            let preferredX = trigger.midX - menuSize.width / 2
            x = min(max(edgeMargin, preferredX), max(edgeMargin, container.width - edgeMargin - menuSize.width))
            let aboveY = trigger.minY - gap - menuSize.height
            let belowY = trigger.maxY + gap
            if aboveY >= topLimit {
                y = aboveY
            } else if belowY + menuSize.height <= bottomLimit {
                y = belowY
            } else {
                y = min(max(topLimit, aboveY), max(topLimit, bottomLimit - menuSize.height))
            }
        case .assistantMore:
            let preferredX = trigger.maxX - menuSize.width
            x = min(max(edgeMargin, preferredX), max(edgeMargin, container.width - edgeMargin - menuSize.width))
            let belowY = trigger.maxY + gap
            let aboveY = trigger.minY - gap - menuSize.height
            if belowY + menuSize.height <= bottomLimit {
                y = belowY
            } else if aboveY >= topLimit {
                y = aboveY
            } else {
                y = min(max(topLimit, belowY), max(topLimit, bottomLimit - menuSize.height))
            }
        case .userMore:
            let preferredX = trigger.minX
            x = min(max(edgeMargin, preferredX), max(edgeMargin, container.width - edgeMargin - menuSize.width))
            let belowY = trigger.maxY + gap
            let aboveY = trigger.minY - gap - menuSize.height
            if belowY + menuSize.height <= bottomLimit {
                y = belowY
            } else if aboveY >= topLimit {
                y = aboveY
            } else {
                y = min(max(topLimit, belowY), max(topLimit, bottomLimit - menuSize.height))
            }
        }
        return CGPoint(x: x, y: y)
    }

    private func startMonitoring() {
        stopMonitoring()
        let box = menuView
        let controller = self.controller
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { event in
            if event.type == .scrollWheel {
                MainActor.assumeIsolated { controller.dismiss() }
                return event
            }
            let isEscape = event.type == .keyDown && event.keyCode == 53
            if event.type == .keyDown && !isEscape { return event }
            let point = event.locationInWindow
            let window = event.window
            let consumed = MainActor.assumeIsolated {
                if !isEscape, let view = box.view, window === view.window,
                   view.bounds.contains(view.convert(point, from: nil)) {
                    return false
                }
                let sameWindow = window != nil && window === box.view?.window
                controller.dismiss()
                return sameWindow
            }
            return consumed ? nil : event
        }
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct ChatEmojiReactionPickerView: View {
    let selectedEmoji: String?
    let accentColor: Color
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ChatUserReactionCatalog.quickEmojis, id: \.self) { emoji in
                ChatEmojiOptionButton(
                    emoji: emoji,
                    selected: selectedEmoji == emoji,
                    accentColor: accentColor
                ) {
                    onSelect(emoji)
                }
            }
        }
        .padding(4)
        .accessibilityIdentifier("bubble-emoji-picker")
    }
}

private struct ChatEmojiOptionButton: View {
    let emoji: String
    let selected: Bool
    let accentColor: Color
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: 18))
                .frame(width: 32, height: 32)
                .scaleEffect(!reduceMotion && hovered ? 1.16 : 1)
                .background {
                    if selected {
                        Circle()
                            .fill(accentColor.opacity(0.22))
                            .overlay(Circle().strokeBorder(accentColor.opacity(0.45), lineWidth: 1))
                    }
                }
                .overlay {
                    Circle()
                        .fill(.white.opacity(hovered ? 0.12 : 0))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
                .contentShape(Circle())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(ChatEmojiPressStyle())
        .onHover { hovered = $0 }
        .actionArrowCursor()
        .accessibilityLabel(emoji)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("bubble-emoji-option-" + emoji)
    }
}

private struct ChatEmojiPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct BubbleTimestampSchedule: TimelineSchedule {
    let timestamp: Date

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(timestamp: timestamp, cursor: startDate, emittedStart: false)
    }

    struct Entries: Sequence, IteratorProtocol {
        let timestamp: Date
        var cursor: Date
        var emittedStart: Bool

        mutating func next() -> Date? {
            if !emittedStart {
                emittedStart = true
                return cursor
            }
            let elapsed = Swift.max(0, cursor.timeIntervalSince(timestamp))
            let nextOffset: TimeInterval
            if elapsed < 60 {
                nextOffset = 60
            } else if elapsed < 3600 {
                nextOffset = floor(elapsed / 60 + 1) * 60
            } else if elapsed < 86400 {
                nextOffset = floor(elapsed / 3600 + 1) * 3600
            } else if elapsed < 3 * 86400 {
                nextOffset = floor(elapsed / 86400 + 1) * 86400
            } else {
                return nil
            }
            let nextDate = timestamp.addingTimeInterval(nextOffset)
            cursor = nextDate
            return nextDate
        }
    }
}

private struct ChatBubbleMoreMenuView<Actions: View>: View {
    let timestamp: Date?
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let timestamp {
                TimelineView(BubbleTimestampSchedule(timestamp: timestamp)) { context in
                    Text(ChatCompletionTime.label(timestamp, now: context.date))
                        .font(.system(size: 12, weight: .regular))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(ThemeColor.kTextSubtle)
                        .accessibilityIdentifier("bubble-more-timestamp")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .help(ChatCompletionTime.exact(timestamp))

                Rectangle()
                    .fill(ThemeColor.kBorder)
                    .frame(height: 1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }
            actions()
        }
        .padding(6)
        .frame(width: 196)
        .accessibilityIdentifier("bubble-more-menu")
    }
}

private struct ChatBubbleMoreRow<Icon: View>: View {
    let title: String
    var destructive = false
    var disabled = false
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon()
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 8)
            }
            .foregroundStyle(destructive ? ThemeColor.kTextNegative : ThemeColor.kText)
            .padding(.horizontal, 10)
            .frame(height: 32)
        }
        .buttonStyle(GlassRowButtonStyle(cornerRadius: 8))
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }
}

@MainActor
private final class BubblePopoverWeakViewBox {
    weak var view: NSView?
}

private struct BubblePopoverViewReader: NSViewRepresentable {
    let box: BubblePopoverWeakViewBox
    func makeNSView(context: Context) -> NSView { let view = NSView(); box.view = view; return view }
    func updateNSView(_ view: NSView, context: Context) { box.view = view }
}
