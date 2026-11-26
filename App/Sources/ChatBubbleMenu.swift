import AppKit
import SwiftUI
import Theme

enum ChatBubblePopoverTarget: Hashable {
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

struct ChatBubblePopoverPresentation: ViewModifier {
    var controller: ChatBubblePopoverController
    @Binding var showingApprovalMenu: Bool
    var headerHeight: CGFloat
    @State private var monitor: Any?
    @State private var menuView = BubblePopoverWeakViewBox()
    @State private var expandedPanelView = BubblePopoverWeakViewBox()
    @State private var measuredSize: CGSize = .zero
    @State private var emojiPickerExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    AnchoredOverlayLayout {
                        if let target = controller.target,
                           let payload = controller.payload,
                           let trigger = controller.anchorRect {
                            let menuSize = effectiveSize(for: target)
                            let placement = menuPlacement(
                                for: target,
                                trigger: trigger,
                                menuSize: menuSize,
                                container: geometry.size
                            )
                            let anchorPoint = AnchoredPopoverMotion.anchor(
                                for: trigger,
                                menuOrigin: placement.origin,
                                menuSize: menuSize,
                                placedAbove: placement.placedAbove
                            )

                            if case .emojiPicker(let selectedEmoji, let accentColor, let onSelect) = payload,
                               emojiPickerExpanded {
                                let panelLayout = expandedEmojiPanelLayout(
                                    quickBarOrigin: placement.origin,
                                    quickBarSize: menuSize,
                                    container: geometry.size
                                )
                                let panelAnchor = AnchoredPopoverMotion.anchor(
                                    for: CGRect(origin: placement.origin, size: menuSize),
                                    menuOrigin: panelLayout.origin,
                                    menuSize: panelLayout.size,
                                    placedAbove: panelLayout.placedAbove
                                )
                                ChatEmojiFullPickerView(
                                    selectedEmoji: selectedEmoji,
                                    accentColor: accentColor,
                                    panelHeight: panelLayout.size.height,
                                    onSelect: { emoji in
                                        controller.dismiss()
                                        onSelect(emoji)
                                    }
                                )
                                .nativeGlassBackground(in: RoundedRectangle(cornerRadius: 18))
                                .background(BubblePopoverViewReader(box: expandedPanelView).allowsHitTesting(false))
                                .fixedSize()
                                .anchoredOverlayOrigin(panelLayout.origin)
                                .transition(
                                    AnchoredPopoverMotion.transition(
                                        anchor: panelAnchor,
                                        placedAbove: panelLayout.placedAbove,
                                        reduceMotion: reduceMotion
                                    )
                                )
                                .zIndex(1)
                            }

                            popoverContent(for: payload)
                                .background(BubblePopoverViewReader(box: menuView).allowsHitTesting(false))
                                .fixedSize()
                                .onGeometryChange(for: CGSize.self) { $0.size } action: { measuredSize = $0 }
                                .anchoredOverlayOrigin(placement.origin)
                                .transition(
                                    AnchoredPopoverMotion.transition(
                                        anchor: anchorPoint,
                                        placedAbove: placement.placedAbove,
                                        reduceMotion: reduceMotion
                                    )
                                )
                                .id(target)
                                .zIndex(2)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    .animation(
                        AnchoredPopoverMotion.animation(
                            isPresented: controller.target != nil,
                            reduceMotion: reduceMotion
                        ),
                        value: controller.target
                    )
                    .animation(
                        AnchoredPopoverMotion.animation(
                            isPresented: emojiPickerExpanded,
                            reduceMotion: reduceMotion
                        ),
                        value: emojiPickerExpanded
                    )
                }
                .allowsHitTesting(controller.target != nil)
            }
            .onChange(of: controller.target) { _, newTarget in
                measuredSize = .zero
                emojiPickerExpanded = false
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
                isExpanded: emojiPickerExpanded,
                onSelect: { emoji in
                    controller.dismiss()
                    onSelect(emoji)
                },
                onToggleExpand: {
                    if reduceMotion {
                        emojiPickerExpanded.toggle()
                    } else {
                        let opening = !emojiPickerExpanded
                        withAnimation(AnchoredPopoverMotion.animation(isPresented: opening, reduceMotion: false)) {
                            emojiPickerExpanded.toggle()
                        }
                    }
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
                    Image(mingCute: "share_forward", size: 14)
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
            return CGSize(width: 244, height: 40)
        case .assistantMore, .userMore:
            return CGSize(width: 196, height: 110)
        }
    }

    private struct ExpandedEmojiPanelLayout {
        let origin: CGPoint
        let size: CGSize
        let placedAbove: Bool
    }

    private func expandedEmojiPanelLayout(
        quickBarOrigin: CGPoint,
        quickBarSize: CGSize,
        container: CGSize
    ) -> ExpandedEmojiPanelLayout {
        let edgeMargin: CGFloat = 12
        let topLimit = headerHeight + 4
        let bottomLimit = container.height - edgeMargin
        let gap: CGFloat = 8
        let width = min(ChatEmojiFullPickerLayout.width, max(240, container.width - edgeMargin * 2))
        let preferredHeight = ChatEmojiFullPickerLayout.preferredHeight

        let spaceAbove = max(0, quickBarOrigin.y - gap - topLimit)
        let spaceBelow = max(0, bottomLimit - (quickBarOrigin.y + quickBarSize.height + gap))

        let placedAbove: Bool
        let height: CGFloat
        let y: CGFloat
        if spaceAbove >= preferredHeight {
            placedAbove = true
            height = preferredHeight
            y = quickBarOrigin.y - gap - height
        } else if spaceBelow >= preferredHeight {
            placedAbove = false
            height = preferredHeight
            y = quickBarOrigin.y + quickBarSize.height + gap
        } else if spaceAbove >= spaceBelow {
            placedAbove = true
            height = max(180, spaceAbove)
            y = max(topLimit, quickBarOrigin.y - gap - height)
        } else {
            placedAbove = false
            height = max(180, spaceBelow)
            y = min(quickBarOrigin.y + quickBarSize.height + gap, max(topLimit, bottomLimit - height))
        }

        let preferredX = quickBarOrigin.x + quickBarSize.width / 2 - width / 2
        let x = min(max(edgeMargin, preferredX), max(edgeMargin, container.width - edgeMargin - width))
        return ExpandedEmojiPanelLayout(
            origin: CGPoint(x: x, y: y),
            size: CGSize(width: width, height: height),
            placedAbove: placedAbove
        )
    }

    private struct BubbleMenuPlacement {
        let origin: CGPoint
        let placedAbove: Bool
    }

    private func menuPlacement(for target: ChatBubblePopoverTarget, trigger: CGRect, menuSize: CGSize, container: CGSize) -> BubbleMenuPlacement {
        let edgeMargin: CGFloat = 12
        let topLimit = headerHeight + 4
        let bottomLimit = container.height - edgeMargin
        let gap: CGFloat = 6

        let x: CGFloat
        let y: CGFloat
        let placedAbove: Bool
        switch target {
        case .emojiPicker:
            let preferredX = trigger.midX - menuSize.width / 2
            x = min(max(edgeMargin, preferredX), max(edgeMargin, container.width - edgeMargin - menuSize.width))
            let aboveY = trigger.minY - gap - menuSize.height
            let belowY = trigger.maxY + gap
            if aboveY >= topLimit {
                y = aboveY
                placedAbove = true
            } else if belowY + menuSize.height <= bottomLimit {
                y = belowY
                placedAbove = false
            } else {
                y = min(max(topLimit, aboveY), max(topLimit, bottomLimit - menuSize.height))
                placedAbove = true
            }
        case .assistantMore:
            let preferredX = trigger.maxX - menuSize.width
            x = min(max(edgeMargin, preferredX), max(edgeMargin, container.width - edgeMargin - menuSize.width))
            let belowY = trigger.maxY + gap
            let aboveY = trigger.minY - gap - menuSize.height
            if belowY + menuSize.height <= bottomLimit {
                y = belowY
                placedAbove = false
            } else if aboveY >= topLimit {
                y = aboveY
                placedAbove = true
            } else {
                y = min(max(topLimit, belowY), max(topLimit, bottomLimit - menuSize.height))
                placedAbove = false
            }
        case .userMore:
            let preferredX = trigger.minX
            x = min(max(edgeMargin, preferredX), max(edgeMargin, container.width - edgeMargin - menuSize.width))
            let belowY = trigger.maxY + gap
            let aboveY = trigger.minY - gap - menuSize.height
            if belowY + menuSize.height <= bottomLimit {
                y = belowY
                placedAbove = false
            } else if aboveY >= topLimit {
                y = aboveY
                placedAbove = true
            } else {
                y = min(max(topLimit, belowY), max(topLimit, bottomLimit - menuSize.height))
                placedAbove = false
            }
        }
        return BubbleMenuPlacement(origin: CGPoint(x: x, y: y), placedAbove: placedAbove)
    }

    private func startMonitoring() {
        stopMonitoring()
        let box = menuView
        let panelBox = expandedPanelView
        let controller = self.controller
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { event in
            let point = event.locationInWindow
            let window = event.window
            if event.type == .scrollWheel {
                MainActor.assumeIsolated {
                    let insidePanel = Self.contains(point: point, in: window, box: panelBox)
                    let insideMenu = Self.contains(point: point, in: window, box: box)
                    if !insidePanel && !insideMenu {
                        controller.dismiss()
                    }
                }
                return event
            }
            let isEscape = event.type == .keyDown && event.keyCode == 53
            if event.type == .keyDown && !isEscape { return event }
            let consumed = MainActor.assumeIsolated {
                if !isEscape,
                   Self.contains(point: point, in: window, box: box)
                    || Self.contains(point: point, in: window, box: panelBox) {
                    return false
                }
                let sameWindow = window != nil && (window === box.view?.window || window === panelBox.view?.window)
                controller.dismiss()
                return sameWindow
            }
            return consumed ? nil : event
        }
    }

    @MainActor
    private static func contains(point: NSPoint, in window: NSWindow?, box: BubblePopoverWeakViewBox) -> Bool {
        guard let view = box.view, window === view.window else { return false }
        return view.bounds.contains(view.convert(point, from: nil))
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct ChatEmojiReactionPickerView: View {
    let selectedEmoji: String?
    let accentColor: Color
    let isExpanded: Bool
    let onSelect: (String) -> Void
    let onToggleExpand: () -> Void

    private var hasCustomSelectedEmoji: Bool {
        guard let selectedEmoji else { return false }
        return !ChatUserReactionCatalog.quickEmojis.contains(selectedEmoji)
    }

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

            ChatEmojiExpandButton(
                isExpanded: isExpanded,
                hasCustomSelection: hasCustomSelectedEmoji,
                accentColor: accentColor,
                action: onToggleExpand
            )
        }
        .padding(4)
        .actionArrowCursor()
        .onAppear {
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            ChatEmojiGlyphCache.shared.prewarmCatalog(scale: scale)
        }
        .accessibilityIdentifier("bubble-emoji-picker")
    }
}

private struct ChatEmojiExpandButton: View {
    let isExpanded: Bool
    let hasCustomSelection: Bool
    let accentColor: Color
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stateTint: Color {
        if hasCustomSelection && !isExpanded {
            return accentColor.opacity(hovered ? 0.24 : 0.18)
        }
        if isExpanded {
            return scheme == .dark
                ? .white.opacity(hovered ? 0.16 : 0.10)
                : .black.opacity(hovered ? 0.08 : 0.05)
        }
        return .clear
    }

    var body: some View {
        Button(action: action) {
            Image(mingCute: "plus", size: 14)
                .foregroundStyle(ThemeColor.kText.color(for: scheme).opacity(isExpanded || hovered ? 0.95 : 0.78))
                .frame(width: 28, height: 28)
                .background {
                    Circle().fill(stateTint)
                }
                .overlay {
                    if hasCustomSelection && !isExpanded {
                        Circle()
                            .strokeBorder(accentColor.opacity(0.45), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    Circle()
                        .fill(.white.opacity(hovered ? 0.12 : 0))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
                .nativeGlassBackground(in: Circle(), clear: true)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isExpanded)
        }
        .buttonStyle(ChatEmojiPressStyle())
        .onHover { hovered = $0 }
        .help(isExpanded ? NSLocalizedString("收起全部表情", comment: "") : NSLocalizedString("展开全部表情", comment: ""))
        .accessibilityLabel(isExpanded ? NSLocalizedString("收起全部表情", comment: "") : NSLocalizedString("展开全部表情", comment: ""))
        .accessibilityAddTraits(isExpanded ? .isSelected : [])
        .accessibilityIdentifier("bubble-emoji-expand")
    }
}

private struct ChatEmojiFullPickerView: View {
    let selectedEmoji: String?
    let accentColor: Color
    let panelHeight: CGFloat
    let onSelect: (String) -> Void

    private let initialCategoryID: String
    @State private var scrollState: ChatEmojiPickerScrollState
    @Environment(\.colorScheme) private var scheme

    init(
        selectedEmoji: String?,
        accentColor: Color,
        panelHeight: CGFloat,
        onSelect: @escaping (String) -> Void
    ) {
        self.selectedEmoji = selectedEmoji
        self.accentColor = accentColor
        self.panelHeight = panelHeight
        self.onSelect = onSelect
        let shouldJumpToSelected = selectedEmoji.map { !ChatUserReactionCatalog.quickEmojis.contains($0) } ?? false
        let initialCategory = (shouldJumpToSelected ? selectedEmoji.flatMap(ChatUserReactionCatalog.categoryID(containing:)) : nil)
            ?? ChatUserReactionCatalog.categories.first?.id
            ?? "smileys"
        self.initialCategoryID = initialCategory
        _scrollState = State(initialValue: ChatEmojiPickerScrollState(initialCategoryID: initialCategory))
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatEmojiCategoryTabBar(scrollState: scrollState)

            Rectangle()
                .fill(ThemeColor.kBorder.color(for: scheme))
                .frame(height: 1)

            ChatEmojiGridScrollView(
                selectedEmoji: selectedEmoji,
                accentColor: accentColor,
                initialCategoryID: initialCategoryID,
                scrollState: scrollState,
                onSelect: onSelect
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: ChatEmojiFullPickerLayout.width, height: panelHeight)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .actionArrowCursor()
        .accessibilityIdentifier("bubble-emoji-full-picker")
    }
}

private struct ChatEmojiCategoryTabBar: View {
    let scrollState: ChatEmojiPickerScrollState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: ChatEmojiFullPickerLayout.columnSpacing) {
            ForEach(ChatUserReactionCatalog.categories) { category in
                ChatEmojiCategoryTabButton(
                    category: category,
                    selected: scrollState.activeCategoryID == category.id
                ) {
                    scrollState.selectCategory(category.id, animated: !reduceMotion)
                }
            }
        }
        .padding(.horizontal, ChatEmojiFullPickerLayout.horizontalPadding)
        .frame(height: 44)
    }
}

private struct ChatEmojiCategoryTabButton: View {
    let category: ChatEmojiCategory
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pillFill: Color {
        if scheme == .dark {
            if selected { return .white.opacity(0.18) }
            if hovered { return .white.opacity(0.09) }
            return .clear
        } else {
            if selected { return .black.opacity(0.09) }
            if hovered { return .black.opacity(0.05) }
            return .clear
        }
    }

    var body: some View {
        Button(action: action) {
            Text(category.icon)
                .font(.system(size: 16))
                .frame(width: 30, height: 30)
                .background(Circle().fill(pillFill))
                .frame(width: ChatEmojiFullPickerLayout.cellSize, height: 32)
                .contentShape(Circle())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selected)
        }
        .buttonStyle(ChatEmojiPressStyle())
        .onHover { hovered = $0 }
        .help(category.title)
        .accessibilityLabel(category.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("bubble-emoji-category-" + category.id)
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
