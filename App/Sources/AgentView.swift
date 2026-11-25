import AppKit
import SwiftUI
import Contracts
import Theme
import ToolService

private final class AgentWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AgentWindowController {
    private var window: NSWindow?
    private let presentation: WindowPresentation
    private var restoreAuthenticationWindow = false
    let model: AgentModel

    init(model: AgentModel, presentation: WindowPresentation) {
        self.model = model
        self.presentation = presentation
    }

    func show(prompt: String? = nil) {
        // Restore history before the hosting view's first layout, rather than
        // animating from an empty greeting after the window is already visible.
        model.reloadConversations()
        model.resumeTimeline()
        if window?.isVisible != true {
            model.clearToast()
        }
        if window == nil {
            let w = AgentWindow(contentRect: NSRect(x: 0, y: 0, width: WindowMetrics.agentInitialSize.width,
                                                 height: WindowMetrics.agentInitialSize.height),
                             styleMask: [.borderless, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: true)
            w.title = "Asky AI"
            w.hasShadow = true
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isOpaque = false
            w.backgroundColor = .clear
            w.animationBehavior = .none
            w.isMovableByWindowBackground = false
            w.level = .normal
            w.collectionBehavior = [.moveToActiveSpace, .primary]
            w.minSize = NSSize(width: WindowMetrics.agentMinSize.width, height: WindowMetrics.agentMinSize.height)
            w.maxSize = w.minSize
            w.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: AgentView(model: model, close: { [weak w, weak model] in
                model?.clearToast()
                w?.close()
            },
                setPinned: { [weak w] pinned in w?.level = pinned ? .floating : .normal }))
            host.sizingOptions = []
            host.frame = NSRect(origin: .zero, size: w.contentLayoutRect.size)
            w.contentView = WindowSurface.glassContentView(host, cornerRadius: AgentLayout.radius)
            if let surface = w.contentView {
                WindowSurface.updateCorners(of: surface, radius: AgentLayout.radius, circular: true)
            }
            w.center()
            window = w
        }
        bringToFront()
        if let prompt {
            if model.isRunning {
                model.submitPrompt(prompt)
            } else {
                model.draft = prompt
                model.send()
            }
        }
    }

    var isVisible: Bool { window?.isVisible == true }

    func showNewConversation() {
        show()
        model.resumeTimeline()
    }

    func prepareForAuthentication() {
        restoreAuthenticationWindow = window?.isVisible == true && window?.isMiniaturized == false
        presentation.yieldToAuthentication()
    }

    func restoreAfterAuthentication() {
        defer { restoreAuthenticationWindow = false }
        guard restoreAuthenticationWindow, let window, window.isVisible, !window.isMiniaturized else { return }
        bringToFront()
    }

    private func bringToFront() {
        guard let window else { return }
        presentation.show(window, level: window.level)
    }
}

enum AgentLayout {
    // Figma UI page 22:293, new chat 43:1072, conversation 42:761.
    static let radius: CGFloat = LauncherLayout.shellCornerRadius
    static let message = TextStyle(size: 14, weight: 400, mode: .default)
    static let headerHeight: CGFloat = 64
    static let toastTopInset: CGFloat = 48
    static let messageHorizontalInset: CGFloat = 16
    static let messageVerticalInset: CGFloat = 12
    static let userMessageVerticalInset: CGFloat = 12
    /// Exact half of a single-line text bubble (19 pt optically centered text + 24 pt vertical padding = 43 pt),
    /// so single-line bubbles form a true capsule and multi-line bubbles reuse the same radius.
    static let bubbleCornerRadius: CGFloat = 21.5
    static let linkedBubbleCornerRadius: CGFloat = 4
    static let linkedBubbleSpacing: CGFloat = 4
    static let groupInternalSpacing: CGFloat = 12
    static let turnSpacing: CGFloat = 20
}

enum ChatBubbleSide: Equatable {
    case leading
    case trailing
}

struct ChatBubbleGrouping: Equatable {
    var connectsAbove = false
    var connectsBelow = false

    static let solo = ChatBubbleGrouping()

    func cornerRadii(
        for side: ChatBubbleSide,
        outerRadius: CGFloat = AgentLayout.bubbleCornerRadius,
        linkedRadius: CGFloat = AgentLayout.linkedBubbleCornerRadius
    ) -> RectangleCornerRadii {
        switch side {
        case .leading:
            RectangleCornerRadii(
                topLeading: connectsAbove ? linkedRadius : outerRadius,
                bottomLeading: connectsBelow ? linkedRadius : outerRadius,
                bottomTrailing: outerRadius,
                topTrailing: outerRadius
            )
        case .trailing:
            RectangleCornerRadii(
                topLeading: outerRadius,
                bottomLeading: outerRadius,
                bottomTrailing: connectsBelow ? linkedRadius : outerRadius,
                topTrailing: connectsAbove ? linkedRadius : outerRadius
            )
        }
    }

    func shape(for side: ChatBubbleSide) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: cornerRadii(for: side), style: .circular)
    }
}

struct ChatGroupBubbleLayout: Equatable {
    var topSpacing: CGFloat
    var itemGroupings: [ChatBubbleGrouping]
    var itemTopSpacings: [CGFloat]
    var typingGrouping: ChatBubbleGrouping
    var typingTopSpacing: CGFloat
}

enum ChatTranscriptBubbleLayout {
    private struct Entry {
        let groupIndex: Int
        let itemIndex: Int?
        let side: ChatBubbleSide?
        let canConnectAbove: Bool
        let canConnectBelow: Bool
        let isUser: Bool
    }

    static func resolve(_ groups: [ChatResponseGroup]) -> [ChatGroupBubbleLayout] {
        var layouts = groups.map { group in
            let count = group.content.count
            return ChatGroupBubbleLayout(
                topSpacing: 0,
                itemGroupings: Array(repeating: .solo, count: count),
                itemTopSpacings: Array(repeating: 0, count: count),
                typingGrouping: .solo,
                typingTopSpacing: 0
            )
        }

        var entries: [Entry] = []
        for (groupIndex, group) in groups.enumerated() {
            for (itemIndex, item) in group.content.enumerated() {
                let entry: Entry
                switch item.kind {
                case .user:
                    let hasLegacyAboveCards = (item.segments ?? []).isEmpty
                        && (!item.attachments.isEmpty || !item.quotes.isEmpty)
                    entry = Entry(
                        groupIndex: groupIndex,
                        itemIndex: itemIndex,
                        side: .trailing,
                        canConnectAbove: !hasLegacyAboveCards,
                        canConnectBelow: item.agentReaction == nil,
                        isUser: true
                    )
                case .assistant, .toolNarration:
                    entry = Entry(
                        groupIndex: groupIndex,
                        itemIndex: itemIndex,
                        side: .leading,
                        canConnectAbove: true,
                        canConnectBelow: !item.needsPermissionSettings && item.userReaction == nil,
                        isUser: false
                    )
                case .tool:
                    let hasCard = item.resultCard != nil
                    entry = Entry(
                        groupIndex: groupIndex,
                        itemIndex: itemIndex,
                        side: hasCard ? .leading : nil,
                        canConnectAbove: hasCard,
                        canConnectBelow: hasCard,
                        isUser: false
                    )
                case .notice, .error:
                    entry = Entry(
                        groupIndex: groupIndex,
                        itemIndex: itemIndex,
                        side: nil,
                        canConnectAbove: false,
                        canConnectBelow: false,
                        isUser: false
                    )
                }
                entries.append(entry)
            }
            if group.showsThinkingIndicator {
                entries.append(Entry(
                    groupIndex: groupIndex,
                    itemIndex: nil,
                    side: .leading,
                    canConnectAbove: true,
                    canConnectBelow: true,
                    isUser: false
                ))
            }
        }

        for index in 1..<entries.count {
            let prev = entries[index - 1]
            let curr = entries[index]
            let linked = prev.side != nil
                && prev.side == curr.side
                && prev.canConnectBelow
                && curr.canConnectAbove

            if linked {
                if let prevItem = prev.itemIndex {
                    layouts[prev.groupIndex].itemGroupings[prevItem].connectsBelow = true
                } else {
                    layouts[prev.groupIndex].typingGrouping.connectsBelow = true
                }
                if let currItem = curr.itemIndex {
                    layouts[curr.groupIndex].itemGroupings[currItem].connectsAbove = true
                } else {
                    layouts[curr.groupIndex].typingGrouping.connectsAbove = true
                }
            }

            let spacing: CGFloat
            if linked {
                spacing = AgentLayout.linkedBubbleSpacing
            } else if prev.groupIndex == curr.groupIndex {
                spacing = AgentLayout.groupInternalSpacing
            } else if prev.isUser || curr.isUser {
                spacing = AgentLayout.turnSpacing
            } else {
                spacing = AgentLayout.groupInternalSpacing
            }

            if prev.groupIndex == curr.groupIndex {
                if let currItem = curr.itemIndex {
                    layouts[curr.groupIndex].itemTopSpacings[currItem] = spacing
                } else {
                    layouts[curr.groupIndex].typingTopSpacing = spacing
                }
            } else {
                layouts[curr.groupIndex].topSpacing = spacing
            }
        }

        return layouts
    }
}

struct AgentView: View {
    @Bindable var model: AgentModel
    var close: () -> Void = {}
    var setPinned: (Bool) -> Void = { _ in }
    @State private var composerHeight: CGFloat = 94
    @State private var emptyComposerHeight: CGFloat = 94
    @State private var showingApprovalMenu = false
    @State private var bubblePopover = ChatBubblePopoverController()
    @State private var pinned = false
    @State private var toolbarPressed: Int?
    @State private var toolbarHovered: Int?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: AgentLayout.radius, style: .circular) }
    private var navigationAnimation: Animation { .easeInOut(duration: reduceMotion ? 0.15 : 0.24) }
    private var conversationTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8))
    }
    private var isEmptyConversation: Bool { model.items.isEmpty && !model.isRunning }
    private var isComposerEmpty: Bool { model.isComposerEmpty }
    private var effectiveComposerHeight: CGFloat { isComposerEmpty ? emptyComposerHeight : composerHeight }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                if isEmptyConversation {
                    AgentGreeting()
                        .padding(.top, AgentLayout.headerHeight)
                        .padding(.bottom, effectiveComposerHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(WindowDragArea())
                        .transition(conversationTransition).zIndex(1)
                } else {
                    Transcript(model: model, bottomInset: effectiveComposerHeight, bubblePopover: bubblePopover)
                        .id("continuous-transcript")
                        .transition(conversationTransition).zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(navigationAnimation, value: isEmptyConversation)
            ProgressiveHeaderBlur(reversed: true)
                .frame(height: effectiveComposerHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Composer(model: model, showingApprovalMenu: $showingApprovalMenu)
                .padding(.horizontal, 12).padding(.bottom, 12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    composerHeight = height
                    if isComposerEmpty { emptyComposerHeight = height }
                }
        }
        .overlay(alignment: .top) {
            ProgressiveHeaderBlur()
                .frame(height: AgentLayout.headerHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .top) { header }
        .overlay(alignment: .topLeading) {
            AgentAvatarPicker(color: Binding(get: { model.avatarColor }, set: { model.avatarColor = $0 }),
                              shape: Binding(get: { model.avatarShape }, set: { model.avatarShape = $0 }),
                              expression: Binding(get: { model.avatarExpression }, set: { model.avatarExpression = $0 }))
                .padding(.leading, 16).padding(.top, 14)
        }
        .modifier(ApprovalMenuPresentation(showing: $showingApprovalMenu) {
            ApprovalModeMenu(model: model, showing: $showingApprovalMenu)
        })
        .modifier(ChatBubblePopoverPresentation(
            controller: bubblePopover,
            showingApprovalMenu: $showingApprovalMenu,
            headerHeight: AgentLayout.headerHeight
        ))
        .modifier(ChatDeleteConfirmPresentation(
            isPresented: model.pendingDeleteMessage != nil,
            confirmDisabled: model.isRunning || model.isCleaningHistory,
            onCancel: { model.cancelPendingDeleteMessage() },
            onConfirm: { model.commitPendingDeleteMessage() }
        ))
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                if let toast = model.toast {
                    ClipboardStatusToast(message: toast)
                        .background(AgentToastFrameProbe().allowsHitTesting(false))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.36 : 0.12), radius: 12, x: 0, y: 4)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("agent-status-toast")
                        .padding(.top, AgentLayout.toastTopInset)
                        .padding(.horizontal, 24)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .offset(y: -6)).combined(with: .scale(scale: 0.96, anchor: .top))
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .allowsHitTesting(false)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.86),
                value: model.toast
            )
        }
        .onChange(of: model.pendingDeleteMessage != nil) { _, presented in
            if presented {
                showingApprovalMenu = false
                bubblePopover.dismiss()
            }
        }
        .foregroundStyle(ThemeColor.kText.color(for: colorScheme))
        .windowSurfaceBackground(in: shape)
        .modifier(FallbackClipShape(active: !WindowSurface.usesNativeGlass, shape: shape))
        .ignoresSafeArea()
        .background {
            Button("") {
                if model.pendingDeleteMessage != nil {
                    model.cancelPendingDeleteMessage()
                } else {
                    close()
                }
            }
            .keyboardShortcut(model.shortcutPreferences.shortcut(.agentEscape).keyEquivalent,
                              modifiers: model.shortcutPreferences.shortcut(.agentEscape).eventModifiers)
            .hidden().accessibilityHidden(true)
        }
        .background {
            Button("") { model.openSettings() }
                .keyboardShortcut(model.shortcutPreferences.shortcut(.settings).keyEquivalent,
                                  modifiers: model.shortcutPreferences.shortcut(.settings).eventModifiers).hidden().accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 36, height: 36).allowsHitTesting(false)
            Spacer(minLength: 0)
            AgentToolbarControls(
                pinned: pinned,
                onPin: togglePin, onClose: close,
                onPressChanged: { toolbarPressed = $0 },
                onHoverChanged: { toolbarHovered = $0 })
                .fixedSize()
                .nativeGlassBackground(in: Capsule())
                .overlay {
                    GlassCapsuleIllumination(pressedIndex: toolbarPressed, hoveredIndex: toolbarHovered)
                }
                .glassPointerFeedback(pressed: toolbarPressed != nil, in: Capsule(), illumination: false)
        }
        .padding(.horizontal, 16)
        .frame(height: AgentLayout.headerHeight)
        .background(WindowDragArea())
        .actionArrowCursor()
        .background {
            Group {
                Button("", action: close)
                    .keyboardShortcut(model.shortcutPreferences.shortcut(.closeChat).keyEquivalent,
                                      modifiers: model.shortcutPreferences.shortcut(.closeChat).eventModifiers)
            }
            .hidden().accessibilityHidden(true)
        }
    }

    private func togglePin() { pinned.toggle(); setPinned(pinned) }
}

private struct AgentGreeting: View {
    private let greeting = "Hey，what’s up?"
    @State private var visibleCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var revealedText: AttributedString {
        var text = AttributedString(greeting)
        let boundary = text.characters.index(text.startIndex, offsetBy: visibleCount)
        text[boundary..<text.endIndex].foregroundColor = .clear
        return text
    }

    var body: some View {
        // Transparent unrevealed characters reserve the final line's width.
        Text(revealedText)
            .textStyle(TextStyle(size: 24, weight: 500, mode: .default))
            .accessibilityLabel(greeting)
            .task(id: reduceMotion) {
                visibleCount = reduceMotion ? greeting.count : 0
                guard !reduceMotion else { return }
                for count in 1...greeting.count {
                    do { try await Task.sleep(for: .milliseconds(38)) }
                    catch { return }
                    visibleCount = count
                }
            }
    }
}

/// Native image buttons share the composer's subdued glass surface.
private struct AgentToolbarControls: NSViewRepresentable {
    var pinned: Bool
    var onPin: () -> Void
    var onClose: () -> Void
    var onPressChanged: (Int?) -> Void
    var onHoverChanged: (Int?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 0
        stack.alignment = .centerY
        stack.detachesHiddenViews = false
        for index in 0..<2 {
            let button = GlassPointerButton(title: "", target: context.coordinator, action: #selector(Coordinator.activate(_:)))
            button.setButtonType(.momentaryPushIn)
            button.bezelStyle = .accessoryBarAction
            button.tag = index
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 48),
                button.heightAnchor.constraint(equalToConstant: 36)
            ])
            stack.addArrangedSubview(button)
        }
        updateNSView(stack, context: context)
        return stack
    }

    func updateNSView(_ stack: NSStackView, context: Context) {
        context.coordinator.parent = self
        let symbols = [pinned ? "pin.fill" : "pin", "power"]
        let titles = [pinned ? "取消置顶" : "置顶窗口", "关闭对话窗口"]
        for (index, view) in stack.arrangedSubviews.enumerated() {
            guard let button = view as? NSButton else { continue }
            let title = NSLocalizedString(titles[index], comment: "")
            (button as? GlassPointerButton)?.onPressChanged = { onPressChanged($0 ? index : nil) }
            (button as? GlassPointerButton)?.onHoverChanged = { onHoverChanged($0 ? index : nil) }
            button.image = MingCute.image(symbols[index], size: 18)
            button.image?.accessibilityDescription = title
            button.toolTip = title
            button.setAccessibilityLabel(title)
            button.isEnabled = true
        }

    }

    @MainActor final class Coordinator: NSObject {
        var parent: AgentToolbarControls
        init(_ parent: AgentToolbarControls) { self.parent = parent }
        @objc func activate(_ sender: NSButton) {
            if sender.tag == 0 { parent.onPin() }
            else if sender.tag == 1 { parent.onClose() }
        }
    }
}

private struct AgentHeaderButtonStyle: ButtonStyle {
    let colorScheme: ColorScheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14)).foregroundStyle(ThemeColor.kTextSubtle.color(for: colorScheme))
            .nativeGlassBackground(in: Circle())
            .contentShape(.interaction, Circle())
            .glassPointerFeedback(pressed: configuration.isPressed, in: Circle())
    }
}

struct AgentIconButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect(cornerRadius: cornerRadius))
            .background {
                if isEnabled && (hovering || configuration.isPressed) {
                    RoundedRectangle(cornerRadius: cornerRadius).fill(ThemeColor.kInteractionHover)
                }
            }
            .onHover { hovering = $0 }
            .glassPointerFeedback(pressed: configuration.isPressed, in: RoundedRectangle(cornerRadius: cornerRadius), illumination: false)
    }
}

private struct TranscriptPagingButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ThemeColor.kTextSubtle)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(ThemeColor.kBackgroundNeutral, in: Capsule())
        }
        .buttonStyle(AgentIconButtonStyle(cornerRadius: 14))
        .opacity(isEnabled ? 1 : 0.3)
        .frame(maxWidth: .infinity)
    }
}

private struct Transcript: View {
    let model: AgentModel
    let bottomInset: CGFloat
    let bubblePopover: ChatBubblePopoverController
    // Value snapshots let an outgoing transcript finish fading after model.open
    // clears/replaces the active conversation. The live model still owns actions.
    private let items: [ChatItem]
    private let streaming: String
    private let hasOlder: Bool
    private let taskID: String?
    private let taskStartedAt: Date?
    private let isRunning: Bool
    private let state: AgentTaskState?

    @State private var viewport = TranscriptViewport()
    @State private var pacer = TranscriptPrependPacer()

    init(model: AgentModel, bottomInset: CGFloat, bubblePopover: ChatBubblePopoverController) {
        self.model = model
        self.bottomInset = bottomInset
        self.bubblePopover = bubblePopover
        items = model.items
        streaming = model.streaming
        hasOlder = model.hasOlder
        taskID = model.taskID
        taskStartedAt = model.taskStartedAt
        isRunning = model.isRunning
        state = model.state
    }

    var body: some View {
        GeometryReader { geometry in
            let displayedItems = pacer.visibleItems(from: items)
            let allGroups = makeGroups(from: displayedItems)
            let latestCompletedReplyID = allGroups.last(where: { $0.content.contains { $0.kind == .assistant } })?
                .content.first(where: { $0.kind == .assistant })?.id
            CompatibleTranscriptScroll(submittedMessageID: items.last(where: { $0.kind == .user })?.id, isWaiting: isRunning, completedReplyID: latestCompletedReplyID, viewport: viewport, bottomInset: bottomInset, replyNavigation: model.replyNavigation, hasNewer: model.hasNewer, loadLatest: {
                pacer.cancel(viewport: viewport)
                model.loadLatestMessages()
            }) {
                // The model already bounds this window to 120 records. Measure it eagerly:
                // lazy height estimates changed during scrolling and moved native text offscreen.
                VStack(alignment: .leading, spacing: 0) {
                    if hasOlder {
                        TranscriptPagingButton(title: NSLocalizedString("加载更早的消息", comment: "")) {
                            guard !pacer.isStaging else { return }
                            let previousFirstID = model.items.first?.id
                            viewport.preserveReadingPosition {
                                model.loadOlder()
                                pacer.beginPrepend(previousFirstID: previousFirstID, updatedItems: model.items, viewport: viewport)
                            }
                        }
                        .disabled(isRunning || pacer.isStaging)
                        .padding(.bottom, 16)
                    }
                    let latestIndex = allGroups.count - 1
                    let navigationTarget = model.replyNavigation?.messageID
                    let groupLayouts = ChatTranscriptBubbleLayout.resolve(allGroups)
                    let avatarColor = model.avatarColor
                    let canDelete = !isRunning && !model.isCleaningHistory
                    ForEach(Array(allGroups.enumerated()), id: \.element.id) { index, group in
                        let layout = groupLayouts[index]
                        let formStates = group.items.compactMap { item -> ResponseGroupView.FormSnapshot? in
                            guard item.kind == .assistant, item.text.contains("```asky-form") else { return nil }
                            return ResponseGroupView.FormSnapshot(
                                id: item.id,
                                answers: model.formAnswers(item.id),
                                active: model.formIsActive(item.id)
                            )
                        }
                        TranscriptGroupWindow(pinned: index >= latestIndex - 1
                            || (navigationTarget != nil && group.items.contains { $0.id == navigationTarget })) {
                            ResponseGroupView(
                                group: group,
                                layout: layout,
                                model: model,
                                bubblePopover: bubblePopover,
                                isLatest: index == latestIndex,
                                avatarColor: avatarColor,
                                canDelete: canDelete,
                                formStates: formStates
                            ).equatable()
                        }
                            .background { TranscriptGroupPosition(id: group.id) }
                            .padding(.top, layout.topSpacing)
                    }
                    if model.hasNewer {
                        TranscriptPagingButton(title: NSLocalizedString("加载更新的消息", comment: "")) {
                            pacer.cancel(viewport: viewport)
                            viewport.preserveReadingPosition { model.loadNewer() }
                        }
                        .disabled(isRunning)
                        .padding(.top, 16)
                        .padding(.bottom, 40)
                    }
                    // Scroll content continues behind the floating composer; its tail remains readable.
                    Color.clear.frame(height: bottomInset + 13)
                }
                .padding(.horizontal, 12).padding(.top, 12)
                .padding(.top, AgentLayout.headerHeight)
                // Keep an initially short conversation at the top without padding individual turns.
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .onChange(of: model.replyNavigation) { _, request in
                if request != nil { pacer.cancel(viewport: viewport) }
            }
            .onDisappear { pacer.cancel(viewport: viewport) }
        }
    }

    private func makeGroups(from sourceItems: [ChatItem]) -> [ChatResponseGroup] {
        var result: [ChatResponseGroup] = []
        var segmentCounts: [String: Int] = [:]
        var lastBaseID: String?
        for item in sourceItems {
            let baseID = item.responseID ?? item.id
            if lastBaseID == baseID, !result.isEmpty {
                result[result.count - 1].items.append(item)
            } else {
                let occurrence = segmentCounts[baseID, default: 0]
                segmentCounts[baseID] = occurrence + 1
                let groupID = occurrence == 0 ? baseID : "\(baseID)#\(occurrence)"
                result.append(ChatResponseGroup(id: groupID, items: [item]))
                lastBaseID = baseID
            }
        }
        if isRunning, let id = taskID {
            for index in result.indices where result[index].items.first?.responseID == id {
                result[index].isRunning = true
                result[index].suppressThinkingIndicator = true
            }
            if lastBaseID != id {
                let occurrence = segmentCounts[id, default: 0]
                segmentCounts[id] = occurrence + 1
                let groupID = occurrence == 0 ? id : "\(id)#\(occurrence)"
                result.append(ChatResponseGroup(id: groupID, items: []))
            }
            result[result.count - 1].startedAt = taskStartedAt
            result[result.count - 1].isRunning = true
            result[result.count - 1].suppressThinkingIndicator = false
            result[result.count - 1].streaming = streaming
            result[result.count - 1].state = state
        }
        return result.filter { $0.showsThinkingIndicator || !$0.content.isEmpty }
    }

    static func label(_ s: AgentTaskState) -> String {
        switch s {
        case .starting: NSLocalizedString("正在启动…", comment: "")
        case .running: NSLocalizedString("思考中…", comment: "")
        case .compacting: NSLocalizedString("正在压缩上下文…", comment: "")
        case .awaitingInput: NSLocalizedString("等待你的回答", comment: "")
        case .awaitingConfirmation: NSLocalizedString("等待确认", comment: "")
        case .completed: NSLocalizedString("已完成", comment: "")
        case .cancelled: NSLocalizedString("已停止", comment: "")
        case .failed: NSLocalizedString("失败", comment: "")
        case .pendingVerification: NSLocalizedString("待核实", comment: "")
        }
    }
}

private struct CompatibleTranscriptScroll<Content: View>: View {
    let submittedMessageID: String?
    let isWaiting: Bool
    let completedReplyID: String?
    let viewport: TranscriptViewport
    let bottomInset: CGFloat
    var replyNavigation: AgentModel.ReplyNavigation?
    var hasNewer = false
    var loadLatest: () -> Void = {}
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 15, *), !SurfaceCompatibility.useMacOS14Compatibility {
            ModernTranscriptScroll(submittedMessageID: submittedMessageID, isWaiting: isWaiting, completedReplyID: completedReplyID, viewport: viewport, bottomInset: bottomInset, replyNavigation: replyNavigation, hasNewer: hasNewer, loadLatest: loadLatest, content: content)
        } else {
            LegacyTranscriptScroll(submittedMessageID: submittedMessageID, isWaiting: isWaiting, completedReplyID: completedReplyID, viewport: viewport, bottomInset: bottomInset, replyNavigation: replyNavigation, hasNewer: hasNewer, loadLatest: loadLatest, content: content)
        }
    }
}

/// Progressively reveals a prepended history page from bottom to top on actual display frames
/// so building native Markdown views never blocks the main thread for hundreds of milliseconds.
@MainActor @Observable
private final class TranscriptPrependPacer {
    private(set) var hiddenLeadingCount = 0
    @ObservationIgnored private var trackedAnchorID: String?
    @ObservationIgnored private var trackedExpectedFirstID: String?
    @ObservationIgnored private var trackedItems: [ChatItem] = []
    @ObservationIgnored private var stageTask: Task<Void, Never>?

    var isStaging: Bool { hiddenLeadingCount > 0 }

    func visibleItems(from items: [ChatItem]) -> [ChatItem] {
        guard hiddenLeadingCount > 0 else { return items }
        guard hiddenLeadingCount < items.count,
              items.first?.id == trackedExpectedFirstID,
              trackedAnchorID == nil || items[hiddenLeadingCount...].contains(where: { $0.id == trackedAnchorID }) else {
            return items
        }
        return Array(items[hiddenLeadingCount...])
    }

    func beginPrepend(previousFirstID: String?, updatedItems: [ChatItem], viewport: TranscriptViewport) {
        stageTask?.cancel()
        stageTask = nil
        guard let previousFirstID,
              let anchorIndex = updatedItems.firstIndex(where: { $0.id == previousFirstID }),
              anchorIndex > 0 else {
            reset(viewport: viewport)
            return
        }
        let initialStart = Self.nextBatchStart(before: anchorIndex, totalPrepended: anchorIndex, in: updatedItems)
        guard initialStart > 0 else {
            reset(viewport: viewport)
            return
        }
        trackedAnchorID = previousFirstID
        trackedExpectedFirstID = updatedItems.first?.id
        trackedItems = updatedItems
        hiddenLeadingCount = initialStart
        viewport.setStagingPrepend(true)
        stageTask = Task { @MainActor [weak self, weak viewport] in
            // Yield until the current run-loop turn's layout/commit finishes plus one display interval,
            // so batches never coalesce into one stall and never stall on inactive windows.
            guard await Self.waitForNextCommit(), !Task.isCancelled else { return }
            while !Task.isCancelled, let self, self.hiddenLeadingCount > 0 {
                viewport?.prepareForStagedBatch()
                let nextStart = Self.nextBatchStart(before: self.hiddenLeadingCount, totalPrepended: anchorIndex, in: self.trackedItems)
                self.hiddenLeadingCount = nextStart
                if nextStart == 0 { break }
                guard await Self.waitForNextCommit() else { return }
            }
            guard !Task.isCancelled, let self else { return }
            self.trackedAnchorID = nil
            self.trackedExpectedFirstID = nil
            self.trackedItems = []
            self.stageTask = nil
            viewport?.setStagingPrepend(false)
        }
    }

    func cancel(viewport: TranscriptViewport? = nil) {
        stageTask?.cancel()
        stageTask = nil
        reset(viewport: viewport)
    }

    private func reset(viewport: TranscriptViewport?) {
        hiddenLeadingCount = 0
        trackedAnchorID = nil
        trackedExpectedFirstID = nil
        trackedItems = []
        viewport?.setStagingPrepend(false)
    }

    private static func estimatedRenderCost(of item: ChatItem) -> Int {
        guard item.kind == .assistant || item.kind == .toolNarration else { return 1 }
        let text = item.text
        var cost = 1 + min(3, text.count / 500)
        if text.contains("```") { cost += 5 }
        if text.contains("\n|") || text.hasPrefix("|") { cost += 6 }
        if text.contains("\n- ") || text.contains("\n1. ") { cost += 3 }
        return cost
    }

    private static func nextBatchStart(before endIndex: Int, totalPrepended: Int, in items: [ChatItem]) -> Int {
        guard endIndex > 6 else { return 0 }
        // Plain prose pages settle in 2–3 fast frames; heavy Markdown (code/tables) splits into ~5–6 frames
        // so neither freezes the main thread nor triggers O(K²) relayouts.
        let minItems = max(3, min(8, (totalPrepended + 5) / 6))
        let budget = 30
        var index = endIndex
        var spent = 0
        var count = 0
        while index > 0 && count < 16 {
            let cost = estimatedRenderCost(of: items[index - 1])
            if count >= minItems && spent + cost > budget { break }
            index -= 1
            spent += cost
            count += 1
        }
        return index <= 3 ? 0 : index
    }

    private static func waitForNextCommit() async -> Bool {
        // First hop onto the next main-queue turn (after SwiftUI/AppKit finishes laying out and
        // committing the current batch), then pause one frame interval so presentation & events run.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        guard !Task.isCancelled else { return false }
        do { try await Task.sleep(for: .milliseconds(16)) } catch { return false }
        return !Task.isCancelled
    }
}

@MainActor
private final class TranscriptViewport {
    private enum AnchorMode {
        case preservePosition
        case revealReply
    }

    weak var scroll: NSScrollView?
    var readerMoved = true
    var followsLatestContent = false
    var isLiveScrolling = false

    var replyID: String?

    private struct WeakAnchor {
        let id: NSUserInterfaceItemIdentifier
        let offset: CGFloat
        weak var view: NSView?
    }

    private var anchorMode: AnchorMode = .preservePosition
    private var readingAnchors: [WeakAnchor] = []
    private var anchorTask: Task<Void, Never>?
    private var animatingReply = false
    private var initialized = false
    private var isAligning = false
    private var isRestoringPosition = false
    private var isStagingPrepend = false
    private var hasUserScrolledDuringPreserve = false
    private var preUpdateDocumentHeight: CGFloat?

    var shouldSyncPreserveOnBoundsChange: Bool {
        !animatingReply && anchorMode == .preservePosition && !readingAnchors.isEmpty
    }

    func setStagingPrepend(_ active: Bool) {
        isStagingPrepend = active
    }

    func prepareInitialAlignmentIfNeeded(replyID: String?) {
        guard !initialized else { return }
        initialized = true
        readerMoved = false
        followsLatestContent = true
        self.replyID = replyID
    }

    private func captureVisibleAnchors(in scroll: NSScrollView, document: NSView) -> [WeakAnchor] {
        func collect(_ view: NSView, prefixes: [String]) -> [NSView] {
            if let raw = view.identifier?.rawValue, prefixes.contains(where: { raw.hasPrefix($0) }) {
                return [view]
            }
            return view.subviews.flatMap { collect($0, prefixes: prefixes) }
        }
        var markers = collect(document, prefixes: ["transcript-reply-", "transcript-item-"])
        if markers.isEmpty {
            markers = collect(document, prefixes: ["transcript-group-"])
        }
        let clipBounds = scroll.contentView.bounds
        // Clamp against top/bottom rubber-band overscroll so the saved screen offset never absorbs bounce.
        let baselineY = scroll.contentView.constrainBoundsRect(clipBounds).minY
        let visibleTop = baselineY + AgentLayout.headerHeight + 12
        let visibleBottom = baselineY + clipBounds.height
        let sorted: [(id: NSUserInterfaceItemIdentifier, view: NSView, rect: NSRect)] = markers.compactMap { view in
            guard let id = view.identifier else { return nil }
            let rect = scroll.contentView.convert(view.bounds, from: view)
            guard rect.height > 0.5 else { return nil }
            return (id, view, rect)
        }.sorted { lhs, rhs in
            if abs(lhs.rect.minY - rhs.rect.minY) > 0.5 { return lhs.rect.minY < rhs.rect.minY }
            return lhs.rect.maxY < rhs.rect.maxY
        }
        var candidates = sorted.filter { $0.rect.maxY > visibleTop && $0.rect.minY < visibleBottom }
        if candidates.isEmpty {
            candidates = sorted.filter { $0.rect.intersects(clipBounds) }
        }
        if candidates.isEmpty, let first = sorted.first {
            candidates = [first]
        }
        return candidates.prefix(4).map { WeakAnchor(id: $0.id, offset: $0.rect.minY - baselineY, view: $0.view) }
    }

    func preserveReadingPosition(_ update: () -> Void) {
        guard let scroll, let document = scroll.documentView else { update(); return }
        followsLatestContent = false
        readerMoved = true
        isLiveScrolling = false
        cancelReadingAnchor()
        anchorMode = .preservePosition
        hasUserScrolledDuringPreserve = false
        preUpdateDocumentHeight = document.bounds.height
        readingAnchors = captureVisibleAnchors(in: scroll, document: document)
        update()
        anchorTask = Task { @MainActor [weak self] in
            var lastHeight = self?.scroll?.documentView?.bounds.height ?? 0
            var lastScrollY = self?.scroll?.contentView.bounds.minY ?? 0
            var heightChanged = false
            var settledPasses = 0
            for _ in 0..<120 {
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
                guard let self, !Task.isCancelled else { return }
                if self.readingAnchors.isEmpty { return }
                if self.isStagingPrepend {
                    // Staged batches synchronize on frame/bounds/layout callbacks; avoid forcing
                    // extra synchronous layoutSubtreeIfNeeded() passes mid-staging.
                    settledPasses = 0
                    continue
                }
                if !self.isLiveScrolling {
                    self.restoreReadingPosition(layoutIfNeeded: true)
                }
                let currentHeight = self.scroll?.documentView?.bounds.height ?? lastHeight
                let currentScrollY = self.scroll?.contentView.bounds.minY ?? lastScrollY
                if let pre = self.preUpdateDocumentHeight, abs(currentHeight - pre) > 0.5 {
                    heightChanged = true
                }
                if abs(currentHeight - lastHeight) <= 0.5 && abs(currentScrollY - lastScrollY) <= 0.5 {
                    settledPasses += 1
                    if settledPasses >= (heightChanged ? 6 : 12) { break }
                } else {
                    settledPasses = 0
                }
                lastHeight = currentHeight
                lastScrollY = currentScrollY
            }
            if let self, !self.isStagingPrepend {
                self.readingAnchors = []
                self.preUpdateDocumentHeight = nil
            }
        }
    }

    /// Re-locks to the reader's current visible item right before inserting the next staged batch,
    /// so even if the reader started scrolling up during staging, their live viewport stays steady.
    func prepareForStagedBatch() {
        guard let scroll, let document = scroll.documentView else { return }
        if hasUserScrolledDuringPreserve || readingAnchors.isEmpty {
            anchorMode = .preservePosition
            readingAnchors = captureVisibleAnchors(in: scroll, document: document)
        }
    }

    func revealReply(_ id: String, reduceMotion: Bool) {
        cancelReadingAnchor()
        followsLatestContent = false
        readerMoved = true
        isLiveScrolling = false
        anchorMode = .revealReply
        // The marker is on the text, so subtract the bubble inset as well.
        readingAnchors = [WeakAnchor(
            id: NSUserInterfaceItemIdentifier("transcript-reply-" + id),
            offset: AgentLayout.headerHeight + 12 + AgentLayout.messageVerticalInset,
            view: nil
        )]
        animatingReply = !reduceMotion
        anchorTask = Task { @MainActor [weak self] in
            // Let a newly loaded history page settle before measuring the destination.
            do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            if !reduceMotion {
                await self.animateScroll { self.readingOrigin(layoutIfNeeded: true)?.y }
            }
            guard !Task.isCancelled else { return }
            self.animatingReply = false
            self.restoreReadingPosition(layoutIfNeeded: true)
            for _ in 0..<30 {
                do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
                self.restoreReadingPosition(layoutIfNeeded: true)
            }
            self.readingAnchors = []
        }
    }

    func cancelReadingAnchor() {
        anchorTask?.cancel()
        anchorTask = nil
        readingAnchors = []
        animatingReply = false
        hasUserScrolledDuringPreserve = false
        preUpdateDocumentHeight = nil
    }

    /// Cancels reveal animations immediately; during passive touch (.tracking) preserves a pending
    /// history-load anchor so resting fingers on a trackpad cannot drop the reading offset.
    func handleScrollPhaseChange(isTrackingOnly: Bool) {
        if anchorMode == .revealReply {
            cancelReadingAnchor()
            return
        }
        if isTrackingOnly {
            return
        }
        hasUserScrolledDuringPreserve = true
        if !isStagingPrepend {
            cancelReadingAnchor()
        } else {
            readingAnchors = []
        }
    }

    func handleUserLiveScrollBegan() {
        isLiveScrolling = true
        if anchorMode == .revealReply {
            cancelReadingAnchor()
            return
        }
        hasUserScrolledDuringPreserve = true
        if !isStagingPrepend {
            cancelReadingAnchor()
        } else {
            readingAnchors = []
        }
    }

    func handleUserLiveScrollEnded() {
        isLiveScrolling = false
    }

    func restoreReadingPosition(layoutIfNeeded: Bool = true) {
        guard !animatingReply, !isRestoringPosition, !readingAnchors.isEmpty, let scroll else { return }
        isRestoringPosition = true
        defer { isRestoringPosition = false }
        guard let origin = readingOrigin(layoutIfNeeded: layoutIfNeeded) else { return }
        if abs(scroll.contentView.bounds.minY - origin.y) > 0.5 {
            scroll.contentView.scroll(to: origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    private func readingOrigin(layoutIfNeeded: Bool) -> NSPoint? {
        guard !readingAnchors.isEmpty, let scroll, let document = scroll.documentView else { return nil }
        if layoutIfNeeded { document.layoutSubtreeIfNeeded() }
        // Fast path: reuse the still-mounted weak reference to the anchor marker view in O(1).
        for anchor in readingAnchors {
            if let marker = anchor.view, marker.identifier == anchor.id, marker.isDescendant(of: document) {
                var bounds = scroll.contentView.bounds
                bounds.origin.y = scroll.contentView.convert(marker.bounds, from: marker).minY - anchor.offset
                return scroll.contentView.constrainBoundsRect(bounds).origin
            }
        }
        let targetIDs = Set(readingAnchors.map(\.id))
        var found: [NSUserInterfaceItemIdentifier: NSView] = [:]
        func collect(_ view: NSView) {
            if let id = view.identifier, targetIDs.contains(id) {
                found[id] = view
                if found.count == targetIDs.count { return }
            }
            for child in view.subviews {
                collect(child)
                if found.count == targetIDs.count { return }
            }
        }
        collect(document)
        guard let index = readingAnchors.firstIndex(where: { found[$0.id] != nil }),
              let marker = found[readingAnchors[index].id] else { return nil }
        readingAnchors[index].view = marker
        var bounds = scroll.contentView.bounds
        bounds.origin.y = scroll.contentView.convert(marker.bounds, from: marker).minY - readingAnchors[index].offset
        return scroll.contentView.constrainBoundsRect(bounds).origin
    }

    func alignLatestContent(layoutIfNeeded: Bool = true) -> Bool {
        guard !isAligning else { return true }
        guard let scroll, let document = scroll.documentView else { return false }
        isAligning = true
        defer { isAligning = false }
        if layoutIfNeeded { document.layoutSubtreeIfNeeded() }
        guard let bottomY else { return false }
        var bounds = scroll.contentView.bounds
        bounds.origin.y = bottomY
        if let replyID {
            func findReply(_ view: NSView) -> NSView? {
                if view.identifier?.rawValue == "transcript-reply-" + replyID { return view }
                return view.subviews.compactMap(findReply).first
            }
            // Wait for the completed bubble to replace the typing indicator before moving.
            guard let reply = findReply(document) else { return false }
            let rect = scroll.contentView.convert(reply.bounds, from: reply)
            let topInset = AgentLayout.headerHeight + 12 + AgentLayout.messageVerticalInset
            let replyStart = document.isFlipped
                ? rect.minY - topInset
                : rect.maxY + topInset - bounds.height
            // Follow ordinary messages to the bottom, but never scroll past an unread reply's start.
            bounds.origin.y = document.isFlipped ? min(bottomY, replyStart) : max(bottomY, replyStart)
        }
        let origin = scroll.contentView.constrainBoundsRect(bounds).origin
        if abs(scroll.contentView.bounds.minY - origin.y) > 0.5 {
            scroll.contentView.scroll(to: origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        return true
    }

    private var bottomY: CGFloat? {
        guard let scroll, let document = scroll.documentView else { return nil }
        let bounds = scroll.contentView.convert(document.bounds, from: document)
        return document.isFlipped
            ? max(bounds.minY, bounds.maxY - scroll.contentView.bounds.height)
            : bounds.minY
    }

    var isAtBottom: Bool {
        guard let scroll, let bottomY else { return false }
        return abs(scroll.contentView.bounds.minY - bottomY) <= 1
    }

    func returnToBottom(reduceMotion: Bool) -> Task<Void, Never> {
        cancelReadingAnchor()
        readerMoved = true
        isLiveScrolling = false
        followsLatestContent = false
        return Task { @MainActor in
            guard !Task.isCancelled, let scroll else { return }
            scroll.layoutSubtreeIfNeeded()
            scroll.documentView?.layoutSubtreeIfNeeded()
            if !reduceMotion {
                await animateScroll { self.bottomY }
            }
            // A newly loaded page can finish measuring its rich text after the animation.
            var settledPasses = 0
            for _ in 0..<12 {
                guard !Task.isCancelled, let bottomY else { return }
                if !isAtBottom {
                    scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: bottomY))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
                do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
                settledPasses = isAtBottom ? settledPasses + 1 : 0
                if settledPasses >= 3 { return }
            }
        }
    }

    private func animateScroll(to destinationY: () -> CGFloat?) async {
        guard let scroll else { return }
        let start = scroll.contentView.bounds.origin
        let startedAt = ProcessInfo.processInfo.systemUptime
        while !Task.isCancelled, let targetY = destinationY() {
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - startedAt) / 0.22)
            let eased = 1 - pow(1 - progress, 3)
            let origin = NSPoint(x: start.x, y: start.y + (targetY - start.y) * eased)
            scroll.contentView.scroll(to: origin)
            scroll.reflectScrolledClipView(scroll.contentView)
            if progress >= 1 { return }
            do { try await Task.sleep(for: .milliseconds(8)) } catch { return }
        }
    }
}

/// Keeps the transcript one SwiftUI tree (so insertions, typing-bubble morphs and height
/// changes animate) while groups far outside the viewport collapse to a spacer of their
/// last measured height. Their native text views, tracking areas and geometry effects
/// then stop participating in every scroll frame. Group position markers stay outside.
private struct TranscriptGroupWindow<Content: View>: View {
    struct Placement: Equatable {
        /// 0: within one viewport of the visible area, 1: within three, 2: farther away.
        var zone: Int
        var width: CGFloat
    }

    let pinned: Bool
    @ViewBuilder let content: Content
    @State private var placement = Placement(zone: 0, width: 0)
    @State private var near = true
    @State private var measured: CGSize?
    /// Native Markdown settles its height asynchronously; never freeze a provisional height.
    @State private var settled = false

    var body: some View {
        Group {
            if !pinned, !near, settled, let measured, abs(measured.width - placement.width) <= 0.5 {
                Color.clear.frame(maxWidth: .infinity).frame(height: measured.height)
            } else {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { measured = $0; settled = false }
                    .task(id: measured) {
                        do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
                        settled = true
                    }
            }
        }
        .onGeometryChange(for: Placement.self) { proxy in
            let frame = proxy.frame(in: .local)
            guard let viewport = proxy.bounds(of: .scrollView) else {
                return Placement(zone: 0, width: frame.width)
            }
            // Render a viewport ahead in both directions; keep rendered groups until three away,
            // so scrolling back and forth does not rebuild the same native text.
            let margin = max(600, viewport.height)
            let zone = frame.intersects(viewport.insetBy(dx: 0, dy: -margin)) ? 0
                : frame.intersects(viewport.insetBy(dx: 0, dy: -margin * 3)) ? 1 : 2
            return Placement(zone: zone, width: frame.width)
        } action: { value in
            placement = value
            if value.zone == 0 { near = true }
        }
        // Collapse only after staying far away briefly: flings and history restores pass through
        // transient positions and must not rebuild the native text they return to.
        .task(id: placement.zone == 2) {
            guard placement.zone == 2, near else { return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            if placement.zone == 2 { near = false }
        }
    }
}

private struct TranscriptGroupPosition: NSViewRepresentable {
    let id: String
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier("transcript-group-" + id)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        view.identifier = NSUserInterfaceItemIdentifier("transcript-group-" + id)
    }
}

private struct TranscriptItemPosition: NSViewRepresentable {
    let id: String
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier("transcript-item-" + id)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        view.identifier = NSUserInterfaceItemIdentifier("transcript-item-" + id)
    }
}

private struct TranscriptReplyPosition: NSViewRepresentable {
    let id: String
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier("transcript-reply-" + id)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        view.identifier = NSUserInterfaceItemIdentifier("transcript-reply-" + id)
    }
}

@MainActor
private func alignTranscriptContent(viewport: TranscriptViewport, replyID: String?) -> Task<Void, Never> {
    viewport.cancelReadingAnchor()
    viewport.replyID = replyID
    viewport.followsLatestContent = true
    _ = viewport.alignLatestContent()
    return Task { @MainActor in
        // Let native Markdown settle before choosing bottom or reply start.
        for _ in 0..<30 {
            guard !Task.isCancelled, !viewport.readerMoved else { return }
            _ = viewport.alignLatestContent()
            do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
        }
    }
}

/// Scroll position changes on every wheel tick; keep it out of the transcript view's state so
/// only the return-to-bottom button re-renders, not the scroll content.
@MainActor @Observable
private final class TranscriptBottomState {
    var isAtBottom = true
    func update(_ value: Bool) { if isAtBottom != value { isAtBottom = value } }
}

private struct TranscriptReturnToBottomOverlay: View {
    let bottomState: TranscriptBottomState
    let hasNewer: Bool
    let bottomInset: CGFloat
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if !bottomState.isAtBottom || hasNewer {
            Button(action: action) {
                Image(mingCute: "arrow.up", size: 20)
                    .rotationEffect(.degrees(180))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(AgentHeaderButtonStyle(colorScheme: colorScheme))
            .accessibilityLabel(NSLocalizedString("回到底部", comment: ""))
            .help(NSLocalizedString("回到底部", comment: ""))
            .padding(.bottom, bottomInset + 8)
        }
    }
}

@available(macOS 15, *)
private struct ModernTranscriptScroll<Content: View>: View {
    let submittedMessageID: String?
    let isWaiting: Bool
    let completedReplyID: String?
    let viewport: TranscriptViewport
    let bottomInset: CGFloat
    var replyNavigation: AgentModel.ReplyNavigation?
    var hasNewer = false
    var loadLatest: () -> Void = {}
    var content: Content
    @State private var bottomState = TranscriptBottomState()
    @State private var bottomTask: Task<Void, Never>?
    @State private var submissionTask: Task<Void, Never>?
    @State private var replyTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            content.background {
                TranscriptPosition(viewport: viewport, initialReplyID: isWaiting ? nil : completedReplyID,
                                   onChange: { [bottomState] in bottomState.update($0) },
                                   onUserScroll: { bottomTask?.cancel(); submissionTask?.cancel(); replyTask?.cancel(); viewport.followsLatestContent = false; viewport.readerMoved = true })
            }
        }
        .coordinateSpace(name: "transcriptScroll")
        .environment(\.transcriptVisibleInsets, EdgeInsets(top: AgentLayout.headerHeight + 8, leading: 0, bottom: bottomInset + 8, trailing: 0))
        .scrollIndicators(.hidden)
        .onDisappear { bottomTask?.cancel(); submissionTask?.cancel(); replyTask?.cancel(); viewport.followsLatestContent = false; viewport.cancelReadingAnchor() }
        .onChange(of: replyNavigation) { _, request in
            guard let request else { return }
            bottomTask?.cancel()
            submissionTask?.cancel()
            replyTask?.cancel()
            viewport.revealReply(request.messageID, reduceMotion: reduceMotion)
        }
        .onChange(of: isWaiting) { _, waiting in
            if !waiting { submissionTask?.cancel() }
        }
        .onChange(of: completedReplyID) { oldID, newID in
            viewport.followsLatestContent = false
            if let newID, newID != oldID, !viewport.readerMoved {
                bottomTask?.cancel()
                submissionTask?.cancel()
                replyTask?.cancel()
                replyTask = alignTranscriptContent(viewport: viewport, replyID: newID)
            }
        }
        // Open at the latest message; starting at the top made the first frame jump down.
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.top, for: .sizeChanges)
        .onScrollPhaseChange { _, phase in
            if phase == .interacting || phase == .tracking {
                viewport.handleScrollPhaseChange(isTrackingOnly: phase == .tracking)
                viewport.followsLatestContent = false
                bottomTask?.cancel()
                submissionTask?.cancel()
                replyTask?.cancel()
                viewport.readerMoved = true
            }
        }
        .onAppear {
            viewport.readerMoved = false
            viewport.followsLatestContent = true
            bottomTask?.cancel()
            bottomTask = alignTranscriptContent(viewport: viewport, replyID: isWaiting ? nil : completedReplyID)
        }
        .overlay(alignment: .bottom) {
            TranscriptReturnToBottomOverlay(bottomState: bottomState, hasNewer: hasNewer, bottomInset: bottomInset) {
                bottomTask?.cancel()
                submissionTask?.cancel()
                replyTask?.cancel()
                loadLatest()
                bottomTask = viewport.returnToBottom(reduceMotion: reduceMotion)
            }
        }
        .onChange(of: submittedMessageID) { oldID, newID in
            // A new outgoing message resumes normal bottom-following, even after manual reading.
            viewport.followsLatestContent = false
            if let newID, newID != oldID, isWaiting {
                bottomTask?.cancel()
                submissionTask?.cancel()
                replyTask?.cancel()
                viewport.readerMoved = false
                submissionTask = alignTranscriptContent(viewport: viewport, replyID: nil)
            }
        }
    }
}

/// AppKit bounds notifications cover wheel events and programmatic scrolling on all supported systems.
private struct TranscriptPosition: NSViewRepresentable {
    let viewport: TranscriptViewport
    let initialReplyID: String?
    var onChange: (Bool) -> Void
    var onUserScroll: () -> Void
    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
        view.onUserScroll = onUserScroll
        view.viewport = viewport
        view.initialReplyID = initialReplyID
        view.attachAndSync(layoutIfNeeded: false)
        view.scheduleUpdate()
    }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        var onUserScroll: (() -> Void)?
        var viewport: TranscriptViewport?
        var initialReplyID: String?
        private weak var observedScroll: NSScrollView?
        private var updateScheduled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachAndSync(layoutIfNeeded: false)
            scheduleUpdate()
        }
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            attachAndSync(layoutIfNeeded: false)
            scheduleUpdate()
        }
        override func layout() {
            super.layout()
            attachAndSync(layoutIfNeeded: false)
            viewport?.restoreReadingPosition(layoutIfNeeded: false)
        }

        /// Coalesces the per-frame bounds notifications of a scroll into one update per run loop turn.
        func scheduleUpdate() {
            guard !updateScheduled else { return }
            updateScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.updateScheduled = false
                self?.updatePosition()
            }
        }

        @objc private func boundsChanged(_ notification: Notification) {
            syncAlignmentIfFollowing(layoutIfNeeded: false)
            if viewport?.shouldSyncPreserveOnBoundsChange == true {
                viewport?.restoreReadingPosition(layoutIfNeeded: false)
            }
            scheduleUpdate()
        }
        @objc private func documentFrameChanged(_ notification: Notification) {
            syncAlignmentIfFollowing(layoutIfNeeded: false)
            viewport?.restoreReadingPosition(layoutIfNeeded: false)
            scheduleUpdate()
        }
        @objc private func userScrolled(_ notification: Notification) {
            viewport?.handleUserLiveScrollBegan()
            onUserScroll?()
        }
        @objc private func userScrollEnded(_ notification: Notification) {
            viewport?.handleUserLiveScrollEnded()
        }

        func attachAndSync(layoutIfNeeded: Bool) {
            guard let scroll = enclosingScrollView, let document = scroll.documentView else { return }
            viewport?.scroll = scroll
            viewport?.prepareInitialAlignmentIfNeeded(replyID: initialReplyID)
            if observedScroll !== scroll {
                NotificationCenter.default.removeObserver(self)
                observedScroll = scroll
                NotificationCenter.default.addObserver(self, selector: #selector(userScrolled(_:)),
                    name: NSScrollView.willStartLiveScrollNotification, object: scroll)
                NotificationCenter.default.addObserver(self, selector: #selector(userScrollEnded(_:)),
                    name: NSScrollView.didEndLiveScrollNotification, object: scroll)
                scroll.contentView.postsBoundsChangedNotifications = true
                document.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged(_:)),
                    name: NSView.boundsDidChangeNotification, object: scroll.contentView)
                NotificationCenter.default.addObserver(self, selector: #selector(documentFrameChanged(_:)),
                    name: NSView.frameDidChangeNotification, object: document)
            }
            syncAlignmentIfFollowing(layoutIfNeeded: layoutIfNeeded)
        }

        private func syncAlignmentIfFollowing(layoutIfNeeded: Bool) {
            if let viewport, viewport.followsLatestContent, !viewport.readerMoved {
                _ = viewport.alignLatestContent(layoutIfNeeded: layoutIfNeeded)
            }
        }

        private func updatePosition() {
            attachAndSync(layoutIfNeeded: true)
            viewport?.restoreReadingPosition(layoutIfNeeded: true)
            onChange?(viewport?.isAtBottom ?? false)
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

private struct LegacyTranscriptScroll<Content: View>: View {
    let submittedMessageID: String?
    let isWaiting: Bool
    let completedReplyID: String?
    let viewport: TranscriptViewport
    let bottomInset: CGFloat
    var replyNavigation: AgentModel.ReplyNavigation?
    var hasNewer = false
    var loadLatest: () -> Void = {}
    var content: Content
    @State private var bottomState = TranscriptBottomState()
    @State private var bottomTask: Task<Void, Never>?
    @State private var submissionTask: Task<Void, Never>?
    @State private var replyTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            content.background {
                TranscriptPosition(viewport: viewport, initialReplyID: isWaiting ? nil : completedReplyID,
                                   onChange: { [bottomState] in bottomState.update($0) },
                                   onUserScroll: { bottomTask?.cancel(); submissionTask?.cancel(); replyTask?.cancel(); viewport.followsLatestContent = false; viewport.readerMoved = true })
            }
        }
        .coordinateSpace(name: "transcriptScroll")
        .environment(\.transcriptVisibleInsets, EdgeInsets(top: AgentLayout.headerHeight + 8, leading: 0, bottom: bottomInset + 8, trailing: 0))
        .scrollIndicators(.hidden)
        .onDisappear { bottomTask?.cancel(); submissionTask?.cancel(); replyTask?.cancel(); viewport.followsLatestContent = false; viewport.cancelReadingAnchor() }
        .onChange(of: replyNavigation) { _, request in
            guard let request else { return }
            bottomTask?.cancel()
            submissionTask?.cancel()
            replyTask?.cancel()
            viewport.revealReply(request.messageID, reduceMotion: reduceMotion)
        }
        .onChange(of: isWaiting) { _, waiting in
            if !waiting { submissionTask?.cancel() }
        }
        .onChange(of: completedReplyID) { oldID, newID in
            viewport.followsLatestContent = false
            if let newID, newID != oldID, !viewport.readerMoved {
                bottomTask?.cancel()
                submissionTask?.cancel()
                replyTask?.cancel()
                replyTask = alignTranscriptContent(viewport: viewport, replyID: newID)
            }
        }
        .defaultScrollAnchor(.top)
        .onAppear {
            viewport.readerMoved = false
            viewport.followsLatestContent = true
            bottomTask?.cancel()
            bottomTask = alignTranscriptContent(viewport: viewport, replyID: isWaiting ? nil : completedReplyID)
        }
        .overlay(alignment: .bottom) {
            TranscriptReturnToBottomOverlay(bottomState: bottomState, hasNewer: hasNewer, bottomInset: bottomInset) {
                bottomTask?.cancel()
                submissionTask?.cancel()
                replyTask?.cancel()
                loadLatest()
                bottomTask = viewport.returnToBottom(reduceMotion: reduceMotion)
            }
        }
        .onChange(of: submittedMessageID) { oldID, newID in
            viewport.followsLatestContent = false
            if let newID, newID != oldID, isWaiting {
                bottomTask?.cancel()
                submissionTask?.cancel()
                replyTask?.cancel()
                viewport.readerMoved = false
                submissionTask = alignTranscriptContent(viewport: viewport, replyID: nil)
            }
        }
    }
}

struct ChatResponseGroup: Identifiable, Equatable {
    let id: String
    var items: [ChatItem]
    var startedAt: Date?
    var isRunning = false
    var state: AgentTaskState?
    var streaming = ""
    var suppressThinkingIndicator = false

    var tools: [ChatItem] { items.filter { if case .tool = $0.kind { true } else { false } } }
    var steps: [ChatItem] {
        items.filter { if case .tool = $0.kind { return true }; return $0.kind == .toolNarration }
    }
    var content: [ChatItem] {
        var primary: [ChatItem] = []
        var cards: [ChatItem] = []
        for item in items {
            switch item.kind {
            case .tool:
                if !isRunning, item.resultCard != nil {
                    cards.append(item)
                }
            case .toolNarration:
                if !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    primary.append(item)
                }
            case .assistant:
                if !isRunning {
                    primary.append(item)
                }
            default:
                primary.append(item)
            }
        }
        return primary + cards
    }
    var workSeconds: Int? { items.compactMap(\.workSeconds).last }
    var showsThinkingIndicator: Bool { isRunning && !suppressThinkingIndicator }
    var activityLabel: String {
        if state == .running || state == .starting || state == nil {
            if let tool = tools.last(where: { $0.kind == .tool(nil) }) {
                return tool.text
            }
            return NSLocalizedString("思考中…", comment: "")
        }
        if let state { return Transcript.label(state) }
        return NSLocalizedString("思考中…", comment: "")
    }
}

/// The exact timestamp remains available while the visible label ages with the clock.
enum ChatCompletionTime {
    static func label(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return NSLocalizedString("刚刚", comment: "") }
        if seconds < 3600 { return String(format: NSLocalizedString("%d 分钟前", comment: ""), seconds / 60) }
        if seconds < 86400 { return String(format: NSLocalizedString("%d 小时前", comment: ""), seconds / 3600) }
        if seconds < 3 * 86400 { return String(format: NSLocalizedString("%d 天前", comment: ""), seconds / 86400) }
        return exact(date)
    }

    static func exact(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

private struct ResponseGroupView: View, Equatable {
    struct FormSnapshot: Equatable {
        let id: String
        let answers: [String: [String]]
        let active: Bool
    }

    let group: ChatResponseGroup
    let layout: ChatGroupBubbleLayout
    let model: AgentModel
    let bubblePopover: ChatBubblePopoverController
    /// Only the newest turn can morph from the typing bubble. Older replies skip
    /// matched geometry, whose global anchors would otherwise update on every scroll frame.
    var isLatest = true
    var avatarColor: AgentAvatarColor
    var canDelete: Bool
    var formStates: [FormSnapshot]
    @Namespace private var bubbleMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.group == rhs.group
            && lhs.layout == rhs.layout
            && lhs.isLatest == rhs.isLatest
            && lhs.avatarColor == rhs.avatarColor
            && lhs.canDelete == rhs.canDelete
            && lhs.formStates == rhs.formStates
    }

    var body: some View {
        let content = group.content
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(content.enumerated()), id: \.element.id) { index, item in
                let grouping = index < layout.itemGroupings.count ? layout.itemGroupings[index] : .solo
                let topSpacing = index < layout.itemTopSpacings.count ? layout.itemTopSpacings[index] : 0
                message(item, grouping: grouping)
                    .padding(.top, topSpacing)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 5)))
            }
            if group.showsThinkingIndicator {
                ChatTypingBubble(bubbleMotion: bubbleMotion, grouping: layout.typingGrouping)
                    .padding(.top, layout.typingTopSpacing)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.9),
                   value: group.isRunning)
    }

    private func message(_ item: ChatItem, grouping: ChatBubbleGrouping) -> some View {
        let fullTurnShareText = ChatShareTurnText.merged(from: group.content)
        return VStack(alignment: .leading, spacing: 6) {
            ChatBubble(item: item, model: model, bubblePopover: bubblePopover, bubbleMotion: isLatest ? bubbleMotion : nil,
                morphsFromTyping: !group.isRunning && group.content.first(where: { $0.kind == .assistant })?.id == item.id,
                grouping: grouping, fullTurnShareText: fullTurnShareText)
            if item.needsPermissionSettings {
                Button(NSLocalizedString("管理权限…", comment: "")) { model.openSettings(permissions: true) }
                    .buttonStyle(.link)
            }
        }
        .background {
            if item.kind != .user && item.kind != .assistant {
                TranscriptItemPosition(id: item.id)
            }
        }
    }
}

/// Only this placeholder is visible until the complete answer is committed.
private struct ChatTypingBubble: View {
    let bubbleMotion: Namespace.ID
    var grouping: ChatBubbleGrouping = .solo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    let wave = reduceMotion ? 0.5 : (sin(elapsed * 2 * .pi / 1.15 - Double(index) * 0.85) + 1) / 2
                    Circle().fill(ThemeColor.kTextSubtlest)
                        .frame(width: 5, height: 5)
                        .scaleEffect(0.8 + wave * 0.5)
                        .offset(y: reduceMotion ? 0 : -wave * 2)
                        .opacity(0.35 + wave * 0.65)
                }
            }
            .padding(.horizontal, AgentLayout.messageHorizontalInset).padding(.vertical, 19)
            .background {
                grouping.shape(for: .leading).fill(ThemeColor.kBackgroundNeutral)
                    .matchedGeometryEffect(id: "reply-surface", in: bubbleMotion, properties: reduceMotion ? [] : .frame, anchor: .topLeading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("思考中…", comment: ""))
    }
}

private struct FallbackClipShape<S: Shape>: ViewModifier {
    let active: Bool
    let shape: S
    @ViewBuilder
    func body(content: Content) -> some View {
        if active { content.clipShape(shape) } else { content }
    }
}

private struct AgentToastFrameProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = PassiveProbeView()
        view.setAccessibilityIdentifier("agent-status-toast-surface")
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class PassiveProbeView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

@MainActor @Observable
private final class UserMessageHoverState {
    var bubbleHovered = false
}

private struct ChatCopyButton: View {
    let text: String
    @Binding var copyFeedbackID: UUID?

    var body: some View {
        Button {
            if MessageClipboard.copy(text) {
                copyFeedbackID = UUID()
            }
        } label: {
            Group {
                if copyFeedbackID != nil {
                    Image(mingCute: "checkmark", size: 14)
                } else {
                    Image("ChatCopy").resizable().scaledToFit().frame(width: 14, height: 14)
                }
            }
            .frame(width: 16, height: 16).padding(6)
        }
        .buttonStyle(AgentIconButtonStyle()).foregroundStyle(ThemeColor("iconSubtlest"))
        .accessibilityLabel(copyFeedbackID != nil ? NSLocalizedString("已复制", comment: "") : NSLocalizedString("复制消息", comment: ""))
        .task(id: copyFeedbackID) {
            guard let feedbackID = copyFeedbackID else { return }
            do {
                try await Task.sleep(for: .milliseconds(800))
            } catch {
                return
            }
            if copyFeedbackID == feedbackID {
                copyFeedbackID = nil
            }
        }
    }
}

private struct ChatReplyButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(mingCute: "share_forward", size: 14)
                .frame(width: 16, height: 16).padding(6)
        }
        .buttonStyle(AgentIconButtonStyle())
        .foregroundStyle(ThemeColor("iconSubtlest"))
        .accessibilityLabel(NSLocalizedString("回复消息", comment: ""))
        .help(NSLocalizedString("回复消息", comment: ""))
    }
}

private struct ChatEmojiButton: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("ChatEmoji").resizable().scaledToFit().frame(width: 14, height: 14)
                .frame(width: 16, height: 16).padding(6)
        }
        .buttonStyle(AgentIconButtonStyle())
        .foregroundStyle(isActive ? ThemeColor.kText : ThemeColor("iconSubtlest"))
        .accessibilityLabel(NSLocalizedString("贴表情", comment: ""))
        .help(NSLocalizedString("贴表情", comment: ""))
    }
}

private struct ChatMoreButton: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(mingCute: "ellipsis.vertical", size: 14)
                .rotationEffect(.degrees(90))
                .frame(width: 16, height: 16).padding(6)
        }
        .buttonStyle(AgentIconButtonStyle())
        .foregroundStyle(isActive ? ThemeColor.kText : ThemeColor("iconSubtlest"))
        .accessibilityLabel(NSLocalizedString("更多操作", comment: ""))
        .help(NSLocalizedString("更多操作", comment: ""))
    }
}

private struct TranscriptVisibleInsetsKey: EnvironmentKey {
    static let defaultValue = EdgeInsets(top: AgentLayout.headerHeight + 8, leading: 0, bottom: 102, trailing: 0)
}

private extension EnvironmentValues {
    var transcriptVisibleInsets: EdgeInsets {
        get { self[TranscriptVisibleInsetsKey.self] }
        set { self[TranscriptVisibleInsetsKey.self] = newValue }
    }
}

private func bubbleSideActionCenterY(in proxy: GeometryProxy, barHeight: CGFloat, visibleInsets: EdgeInsets) -> CGFloat {
    let totalHeight = proxy.size.height
    guard totalHeight > barHeight else { return totalHeight / 2 }
    let edgePadding: CGFloat = 12
    let minCenter = min(totalHeight / 2, barHeight / 2 + edgePadding)
    let maxCenter = max(totalHeight / 2, totalHeight - barHeight / 2 - edgePadding)
    guard let viewport = proxy.bounds(of: .named("transcriptScroll")) else {
        return totalHeight / 2
    }
    let visibleTop = max(0, viewport.minY + visibleInsets.top)
    let visibleBottom = min(totalHeight, viewport.maxY - visibleInsets.bottom)
    guard visibleBottom > visibleTop else {
        return totalHeight / 2
    }
    let target = (visibleTop + visibleBottom) / 2
    return min(max(target, minCenter), maxCenter)
}

private struct AssistantSideActionBar: View {
    static let width: CGFloat = 86
    static let height: CGFloat = 28

    let messageID: String
    let timestamp: Date?
    let currentReaction: String?
    let accentColor: Color
    let hoverState: UserMessageHoverState
    let bubblePopover: ChatBubblePopoverController
    let onSelectReaction: (String) -> Void
    let onReply: () -> Void
    let onCopy: () -> Void
    let onShare: () -> Void
    @State private var rowHovering = false
    @State private var emojiAnchor = ChatBubbleAnchorBox()
    @State private var moreAnchor = ChatBubbleAnchorBox()
    @FocusState private var actionFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.transcriptVisibleInsets) private var visibleInsets

    private var emojiTarget: ChatBubblePopoverTarget { .emojiPicker(messageID: messageID) }
    private var moreTarget: ChatBubblePopoverTarget { .assistantMore(messageID: messageID) }
    private var isEmojiOpen: Bool { bubblePopover.isActive(emojiTarget) }
    private var isMoreOpen: Bool { bubblePopover.isActive(moreTarget) }

    private var isVisible: Bool {
        hoverState.bubbleHovered || rowHovering || actionFocused || isEmojiOpen || isMoreOpen
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ChatEmojiButton(isActive: isEmojiOpen) {
                    guard let anchor = emojiAnchor.swiftUIFrameInWindow() else { return }
                    bubblePopover.toggle(
                        emojiTarget,
                        anchor: anchor,
                        payload: .emojiPicker(
                            selectedEmoji: currentReaction,
                            accentColor: accentColor,
                            onSelect: onSelectReaction
                        )
                    )
                }
                .background {
                    if isVisible {
                        ChatBubbleAnchorReader(box: emojiAnchor).allowsHitTesting(false)
                    }
                }
                .focused($actionFocused)
                .accessibilityIdentifier("assistant-emoji-trigger-" + messageID)

                ChatReplyButton(action: onReply)
                    .focused($actionFocused)

                ChatMoreButton(isActive: isMoreOpen) {
                    guard let anchor = moreAnchor.swiftUIFrameInWindow() else { return }
                    bubblePopover.toggle(
                        moreTarget,
                        anchor: anchor,
                        payload: .assistantMore(
                            timestamp: timestamp,
                            onCopy: onCopy,
                            onShare: onShare
                        )
                    )
                }
                .background {
                    if isVisible {
                        ChatBubbleAnchorReader(box: moreAnchor).allowsHitTesting(false)
                    }
                }
                .focused($actionFocused)
                .accessibilityIdentifier("assistant-more-trigger-" + messageID)
            }
            .frame(width: Self.width, height: Self.height)
            .onHover { rowHovering = $0 }
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isVisible)
            .position(
                x: Self.width / 2,
                y: isVisible
                    ? bubbleSideActionCenterY(in: proxy, barHeight: Self.height, visibleInsets: visibleInsets)
                    : proxy.size.height / 2
            )
        }
        .frame(width: Self.width)
    }
}

private struct UserSideActionBar: View {
    static let width: CGFloat = 58
    static let height: CGFloat = 28

    let messageID: String
    let text: String
    let timestamp: Date?
    let canDelete: Bool
    let hoverState: UserMessageHoverState
    let bubblePopover: ChatBubblePopoverController
    let onReply: () -> Void
    let onDelete: () -> Void
    @State private var rowHovering = false
    @State private var copyFeedbackID: UUID?
    @State private var moreAnchor = ChatBubbleAnchorBox()
    @FocusState private var actionFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.transcriptVisibleInsets) private var visibleInsets

    private var moreTarget: ChatBubblePopoverTarget { .userMore(messageID: messageID) }
    private var isMoreOpen: Bool { bubblePopover.isActive(moreTarget) }

    private var isVisible: Bool {
        hoverState.bubbleHovered || rowHovering || actionFocused || copyFeedbackID != nil || isMoreOpen
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ChatMoreButton(isActive: isMoreOpen) {
                    guard let anchor = moreAnchor.swiftUIFrameInWindow() else { return }
                    bubblePopover.toggle(
                        moreTarget,
                        anchor: anchor,
                        payload: .userMore(
                            timestamp: timestamp,
                            canDelete: canDelete,
                            onReply: onReply,
                            onDelete: onDelete
                        )
                    )
                }
                .background {
                    if isVisible {
                        ChatBubbleAnchorReader(box: moreAnchor).allowsHitTesting(false)
                    }
                }
                .focused($actionFocused)
                .accessibilityIdentifier("user-more-trigger-" + messageID)

                ChatCopyButton(text: text, copyFeedbackID: $copyFeedbackID)
                    .focused($actionFocused)
            }
            .frame(width: Self.width, height: Self.height)
            .onHover { rowHovering = $0 }
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isVisible)
            .position(
                x: Self.width / 2,
                y: isVisible
                    ? bubbleSideActionCenterY(in: proxy, barHeight: Self.height, visibleInsets: visibleInsets)
                    : proxy.size.height / 2
            )
        }
        .frame(width: Self.width)
    }
}

private extension View {
    /// The typing bubble morphs into the newest reply surface; other surfaces stay static.
    @ViewBuilder func replySurfaceMotion(_ namespace: Namespace.ID?, reduceMotion: Bool) -> some View {
        if let namespace {
            matchedGeometryEffect(id: "reply-surface", in: namespace, properties: reduceMotion ? [] : .frame, anchor: .topLeading)
        } else {
            self
        }
    }
}

private struct ChatBubble: View {
    @Environment(\.colorScheme) private var scheme
    let item: ChatItem
    let model: AgentModel
    let bubblePopover: ChatBubblePopoverController
    let bubbleMotion: Namespace.ID?
    var morphsFromTyping = true
    var grouping: ChatBubbleGrouping = .solo
    var fullTurnShareText: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoverState = UserMessageHoverState()
    @State private var replyUnavailable = false

    private var imageAttachments: [AttachmentRef] { item.attachments.filter { $0.kind == .image } }
    private var inlineAttachments: [AttachmentRef] {
        item.attachments.filter { $0.kind != .image || imageAttachments.count < 2 }
    }

    var body: some View {
        switch item.kind {
        case .user:
            let hasInlineSegments = !(item.segments ?? []).isEmpty
            let bubbleShape = grouping.shape(for: .trailing)
            VStack(alignment: .trailing, spacing: 8) {
                if !hasInlineSegments, (!item.attachments.isEmpty || !item.quotes.isEmpty) {
                    if imageAttachments.count > 1 {
                        ChatImageAttachmentStack(attachments: imageAttachments)
                    }
                    if !inlineAttachments.isEmpty || !item.quotes.isEmpty {
                        ViewThatFits(in: .horizontal) {
                            attachmentCards
                            ScrollView(.horizontal) { attachmentCards }
                                .scrollIndicators(.hidden)
                                .defaultScrollAnchor(.trailing)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                HStack(alignment: .center, spacing: 8) {
                    Color.clear
                        .frame(width: UserSideActionBar.width, height: UserSideActionBar.height)
                        .layoutPriority(1)
                    bubble
                        .background {
                            TranscriptReplyPosition(id: item.id)
                        }
                        .padding(.horizontal, AgentLayout.messageHorizontalInset).padding(.vertical, AgentLayout.userMessageVerticalInset)
                        .background {
                            bubbleShape.fill(ThemeColor.kBackgroundNeutral)
                                .overlay {
                                    bubbleShape.fill(model.avatarColor.userBubbleTint(for: scheme))
                                }
                        }
                        .overlay(alignment: .bottomLeading) {
                            ChatReactionBadge(
                                emoji: item.agentReaction,
                                side: .leading,
                                accentColor: model.avatarColor.tint,
                                accessibilityLabelFormat: NSLocalizedString("Asky 回应了 %@", comment: "")
                            )
                        }
                }
                .overlay(alignment: .leading) {
                    UserSideActionBar(
                        messageID: item.id,
                        text: item.copyableText,
                        timestamp: item.createdAt,
                        canDelete: !model.isRunning && !model.isCleaningHistory,
                        hoverState: hoverState,
                        bubblePopover: bubblePopover,
                        onReply: { model.addQuote(item.copyableText, sourceMessageID: item.id, kind: .reply) },
                        onDelete: { model.confirmAndDeleteUserMessage(item) }
                    )
                }
                .padding(.bottom, item.agentReaction == nil ? 0 : ChatReactionBadgeLayout.verticalOverhang)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            // Include the leading side action bar and the gap next to the bubble in
            // hover tracking, so moving to Copy never hides it mid-gesture.
            .contentShape(.rect)
            .onHover { hoverState.bubbleHovered = $0 }
            .appDialog(NSLocalizedString("原回复已不可用", comment: ""), isPresented: $replyUnavailable,
                       message: "", buttons: [NSLocalizedString("确定", comment: "")])
        case .assistant:
            let contextActions = item.id == "streaming" ? nil : assistantContextActions
            let bubbleShape = grouping.shape(for: .leading)
            let hasForm = item.text.contains("```asky-form")
            HStack(alignment: .center, spacing: 8) {
                ChatReplyView(text: item.text, isStreaming: item.id == "streaming",
                    values: hasForm ? Binding(get: { model.formAnswers(item.id) },
                                              set: { model.setFormAnswers($0, for: item.id) }) : .constant([:]),
                    active: hasForm && model.formIsActive(item.id), submit: { model.submitForm(item.id) })
                    .environment(\.chatSelectionColor, model.avatarColor.tint)
                    .environment(\.chatQuoteAction, { model.addQuote($0, sourceMessageID: item.id) })
                    .environment(\.chatBubbleContextActions, contextActions)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        TranscriptReplyPosition(id: item.id)
                    }
                    .padding(.horizontal, AgentLayout.messageHorizontalInset).padding(.vertical, AgentLayout.messageVerticalInset)
                    .background {
                        bubbleShape.fill(ThemeColor.kBackgroundNeutral)
                            .replySurfaceMotion(morphsFromTyping ? bubbleMotion : nil, reduceMotion: reduceMotion)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        userReactionBadge
                    }
                    .contextMenu {
                        if let actions = contextActions {
                            assistantContextMenuItems(actions)
                        }
                    }
                if contextActions != nil {
                    Color.clear
                        .frame(width: AssistantSideActionBar.width, height: AssistantSideActionBar.height)
                        .layoutPriority(1)
                }
            }
            .overlay(alignment: .trailing) {
                if let actions = contextActions {
                    AssistantSideActionBar(
                        messageID: item.id,
                        timestamp: item.completedAt ?? item.createdAt,
                        currentReaction: item.userReaction,
                        accentColor: model.avatarColor.tint,
                        hoverState: hoverState,
                        bubblePopover: bubblePopover,
                        onSelectReaction: { model.toggleUserReaction($0, for: item.id) },
                        onReply: actions.reply,
                        onCopy: actions.copy,
                        onShare: actions.share
                    )
                }
            }
            .padding(.bottom, item.userReaction == nil ? 0 : ChatReactionBadgeLayout.verticalOverhang)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85), value: item.userReaction != nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onHover { hoverState.bubbleHovered = $0 }
        case .toolNarration:
            let contextActions = assistantContextActions
            let bubbleShape = grouping.shape(for: .leading)
            HStack(alignment: .center, spacing: 8) {
                ChatMarkdownView(text: item.text).equatable()
                    .environment(\.chatSelectionColor, model.avatarColor.tint)
                    .environment(\.chatQuoteAction, { model.addQuote($0, sourceMessageID: item.id) })
                    .environment(\.chatBubbleContextActions, contextActions)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AgentLayout.messageHorizontalInset)
                    .padding(.vertical, AgentLayout.messageVerticalInset)
                    .background {
                        bubbleShape.fill(ThemeColor.kBackgroundNeutral)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        userReactionBadge
                    }
                    .contextMenu {
                        assistantContextMenuItems(contextActions)
                    }
                Color.clear
                    .frame(width: AssistantSideActionBar.width, height: AssistantSideActionBar.height)
                    .layoutPriority(1)
            }
            .overlay(alignment: .trailing) {
                AssistantSideActionBar(
                    messageID: item.id,
                    timestamp: item.completedAt ?? item.createdAt,
                    currentReaction: item.userReaction,
                    accentColor: model.avatarColor.tint,
                    hoverState: hoverState,
                    bubblePopover: bubblePopover,
                    onSelectReaction: { model.toggleUserReaction($0, for: item.id) },
                    onReply: contextActions.reply,
                    onCopy: contextActions.copy,
                    onShare: contextActions.share
                )
            }
            .padding(.bottom, item.userReaction == nil ? 0 : ChatReactionBadgeLayout.verticalOverhang)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85), value: item.userReaction != nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onHover { hoverState.bubbleHovered = $0 }
        case .tool:
            if let card = item.resultCard {
                ToolResultCardView(card: card, grouping: grouping) { action in
                    model.performCardAction(action)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 40)
            } else {
                EmptyView()
            }
        case .notice:
            Text(item.text).textStyle(.secondary).foregroundStyle(ThemeColor.kTextSubtle)
                .padding(.horizontal, AgentLayout.messageHorizontalInset).padding(.vertical, AgentLayout.messageVerticalInset)
                .background(ThemeColor.kBackgroundNeutral, in: .rect(cornerRadius: AgentLayout.bubbleCornerRadius))
        case .error:
            Label { Text(item.text) } icon: { Image(mingCute: "warning", size: 16) }.textStyle(.secondary).foregroundStyle(ThemeColor.kTextNegative)
                .padding(.horizontal, AgentLayout.messageHorizontalInset).padding(.vertical, AgentLayout.messageVerticalInset)
                .background(ThemeColor.kBackgroundNeutral, in: .rect(cornerRadius: AgentLayout.bubbleCornerRadius))
        }
    }

    private var userReactionBadge: some View {
        ChatReactionBadge(
            emoji: item.userReaction,
            side: .trailing,
            accentColor: model.avatarColor.tint,
            accessibilityLabelFormat: NSLocalizedString("已贴表情 %@", comment: ""),
            helpText: NSLocalizedString("移除表情", comment: ""),
            accessibilityID: "user-reaction-badge-" + item.id,
            onTap: { model.setUserReaction(nil, for: item.id) }
        )
    }

    private var assistantContextActions: ChatBubbleContextActions {
        ChatBubbleContextActions(
            copy: {
                if MessageClipboard.copy(item.text) {
                    model.showToast(NSLocalizedString("已复制", comment: ""))
                }
            },
            reply: { model.addQuote(item.text, sourceMessageID: item.id, kind: .reply) },
            share: { ChatShareWindowController.shared.show(text: item.text, fullTurnText: fullTurnShareText, colorScheme: scheme) }
        )
    }

    @ViewBuilder
    private func assistantContextMenuItems(_ actions: ChatBubbleContextActions) -> some View {
        Button(NSLocalizedString("复制", comment: ""), action: actions.copy)
        Button(NSLocalizedString("回复消息", comment: ""), action: actions.reply)
        Button(NSLocalizedString("分享回复", comment: ""), action: actions.share)
    }

    private var attachmentCards: some View {
        HStack(spacing: 8) {
            ForEach(Array(item.quotes.enumerated()), id: \.element.id) { index, quote in
                if quote.kind == .reply {
                    Button {
                        replyUnavailable = !model.revealReply(quote.sourceMessageID)
                    } label: {
                        ComposerAttachmentCard(quote: quote, quoteNumber: index + 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRunning && !model.items.contains { $0.id == quote.sourceMessageID })
                    .accessibilityLabel(NSLocalizedString("查看原回复", comment: ""))
                    .accessibilityIdentifier("reply-reference-" + quote.id)
                } else {
                    ComposerAttachmentCard(quote: quote, quoteNumber: index + 1)
                }
            }
            ForEach(inlineAttachments) { attachment in
                ComposerAttachmentCard(attachment: attachment, thumbnail: nil)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let segments = item.segments, !segments.isEmpty {
                UserInlineMessageView(
                    segments: segments,
                    quotes: item.quotes,
                    attachments: item.attachments,
                    pastedTexts: item.pastedTexts,
                    onRevealReply: { sourceID in
                        replyUnavailable = !model.revealReply(sourceID)
                    }
                )
                .environment(\.chatSelectionColor, model.avatarColor.tint)
                .environment(\.chatQuoteAction, { model.addQuote($0, sourceMessageID: item.id) })
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ChatInlineText(markdown: item.text, literal: true, shrinkToFit: true)
                    .environment(\.chatSelectionColor, model.avatarColor.tint)
                    .environment(\.chatQuoteAction, { model.addQuote($0, sourceMessageID: item.id) })
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct Composer: View {
    @Bindable var model: AgentModel
    @Binding var showingApprovalMenu: Bool
    @State private var importing = false
    @State private var editorHeight: CGFloat = 28
    @State private var editorFocused = false
    @State private var hasMarkedText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ComposerTextEditor(
                height: $editorHeight,
                isFocused: $editorFocused,
                resetRevision: model.composerResetRevision,
                pendingInsertions: model.pendingTagInsertions,
                consumeInsertions: { model.consumeTagInsertions($0) },
                onSegmentsChanged: { model.syncDraft(segments: $0) },
                onMarkedTextChanged: { hasMarkedText = $0 },
                pasteAttachment: { model.pasteAttachments() },
                pasteLongText: { model.collapsePastedTextIfNeeded($0) },
                onRevealReply: { _ = model.revealReply($0) },
                submit: submitDraft,
                shortcuts: model.shortcutPreferences
            )
            .environment(\.chatSelectionColor, model.avatarColor.tint)
            .frame(height: (model.isComposerEmpty && !hasMarkedText) ? 28 : editorHeight)
            .padding(.horizontal, 4)
            HStack {
                Button { importing = true } label: {
                    Image(mingCute: "plus", size: 14).frame(width: 28, height: 28)
                }
                .buttonStyle(AgentIconButtonStyle(cornerRadius: 14))
                .accessibilityLabel(NSLocalizedString("选择文件或图片", comment: ""))
                Spacer()
                ApprovalModePicker(model: model, showing: $showingApprovalMenu)
                let primaryAction = model.composerPrimaryAction
                let showsStop = primaryAction == .stop
                Button { if showsStop { model.stop() } else { submitDraft() } } label: {
                    Image(mingCute: showsStop ? "stop.fill" : "arrow.up", size: 14).frame(width: 28, height: 28)
                }
                .buttonStyle(ComposerSubmitButtonStyle(color: model.avatarColor.tint))
                .disabled(primaryAction == .send(enabled: false))
                .accessibilityLabel(showsStop ? NSLocalizedString("停止生成", comment: "") : NSLocalizedString("发送消息", comment: ""))
            }
            .padding(.horizontal, 8)
        }
        .padding(.top, 10).padding(.bottom, 8)
        .nativeGlassBackground(in: RoundedRectangle(cornerRadius: 16, style: .circular))
        .onChange(of: model.quoteFocusRevision) { _, _ in editorFocused = true }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .image, .text], allowsMultipleSelection: true) { r in
            switch r {
            case .success(let urls): urls.forEach { model.attach(fileURL: $0) }
            case .failure(let error): model.reportAttachmentError(error)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            urls.forEach { model.attach(fileURL: $0) }
            return !urls.isEmpty
        }
    }

    private func submitDraft() {
        model.send()
        if model.isComposerEmpty { editorHeight = 28 }
    }
}

private struct ApprovalModePicker: View {
    @Bindable var model: AgentModel
    @Binding var showing: Bool

    static let iconSize: CGFloat = 16

    var body: some View {
        let mode = model.approvalMode
        Button { showing.toggle() } label: {
            HStack(alignment: .center, spacing: 4) {
                Image(mingCute: Self.icon(mode), size: Self.iconSize)
                    .frame(width: Self.iconSize, height: Self.iconSize)
                Text(Self.shortTitle(mode)).font(.system(size: 13))
            }
            .foregroundStyle(mode == .fullAccess ? AnyShapeStyle(FullAccessTint()) : AnyShapeStyle(ThemeColor.kTextSubtle))
            .padding(.horizontal, 10).frame(height: 28)
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .actionArrowCursor()
        .accessibilityLabel(NSLocalizedString("审批模式", comment: ""))
        .accessibilityValue(Self.title(mode))
        .anchorPreference(key: ApprovalMenuAnchorKey.self, value: .bounds) { $0 }
        .accessibilityIdentifier("approval-mode-trigger")
    }

    static func icon(_ mode: ApprovalMode) -> String {
        mode == .fullAccess ? "exclamationmark.shield" : "checkmark.shield"
    }

    static func shortTitle(_ mode: ApprovalMode) -> String {
        mode == .fullAccess ? NSLocalizedString("完全访问", comment: "") : NSLocalizedString("自动审批", comment: "")
    }

    static func title(_ mode: ApprovalMode) -> String {
        mode == .fullAccess ? NSLocalizedString("完全访问权限", comment: "") : NSLocalizedString("自动审批", comment: "")
    }
}

private struct ApprovalMenuAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct ApprovalModeMenu: View {
    @Bindable var model: AgentModel
    @Binding var showing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ApprovalMode.allCases, id: \.self) { option in
                ApprovalModeRow(option: option, selected: option == model.approvalMode) {
                    model.approvalMode = option
                    showing = false
                }
            }
        }
        .padding(6).frame(width: 220)
        .accessibilityIdentifier("approval-mode-menu")
    }
}

private struct ApprovalModeRow: View {
    let option: ApprovalMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let tint = option == .fullAccess ? AnyShapeStyle(FullAccessTint()) : AnyShapeStyle(ThemeColor.kText)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(mingCute: ApprovalModePicker.icon(option), size: ApprovalModePicker.iconSize)
                    .frame(width: 20, height: ApprovalModePicker.iconSize)
                Text(ApprovalModePicker.title(option)).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 8)
                if selected { Image(mingCute: "checkmark", size: 12) }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10).frame(height: 36)
        }
        .buttonStyle(GlassRowButtonStyle())
        .accessibilityLabel(ApprovalModePicker.title(option))
        .accessibilityIdentifier(option == .fullAccess ? "approval-mode-full" : "approval-mode-auto")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// An in-window menu instead of NSPopover, whose chrome is always system Liquid Glass on macOS 26
/// and so ignores the Liquid Glass setting.
private struct ApprovalMenuPresentation<Menu: View>: ViewModifier {
    @Binding var showing: Bool
    @ViewBuilder let menu: () -> Menu
    @State private var monitor: Any?
    @State private var menuView = WeakViewBox()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(ApprovalMenuAnchorKey.self) { anchor in
                if showing, let anchor {
                    GeometryReader { geometry in
                        let trigger = geometry[anchor]
                        menu()
                            .nativeGlassBackground(in: RoundedRectangle(cornerRadius: 14))
                            .background(ViewReader(box: menuView).allowsHitTesting(false))
                            .fixedSize()
                            // Present in the full window, outside the composer's glass/hover bounds.
                            .position(x: min(geometry.size.width - 122, trigger.maxX + 40 - 110),
                                      y: trigger.minY - 8 - 43)
                    }
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: showing)
            .onChange(of: showing) { _, shown in shown ? startMonitoring() : stopMonitoring() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { event in
                if let owner = menuView.view?.window, event.object as? NSWindow === owner { showing = false; stopMonitoring() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { event in
                if let owner = menuView.view?.window, event.object as? NSWindow === owner { showing = false; stopMonitoring() }
            }
            .onDisappear { showing = false; stopMonitoring() }
    }

    private func startMonitoring() {
        stopMonitoring()
        let box = menuView
        let dismiss = $showing
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { event in
            let isEscape = event.type == .keyDown && event.keyCode == 53
            if event.type == .keyDown && !isEscape { return event }
            let point = event.locationInWindow
            let window = event.window
            let consumed = MainActor.assumeIsolated {
                if !isEscape, let view = box.view, window === view.window,
                   view.bounds.contains(view.convert(point, from: nil)) {
                    return false
                }
                // Like a transient popover, the dismissing click does nothing else.
                let sameWindow = window != nil && window === box.view?.window
                dismiss.wrappedValue = false
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

@MainActor private final class WeakViewBox {
    weak var view: NSView?
}

private struct ViewReader: NSViewRepresentable {
    let box: WeakViewBox
    func makeNSView(context: Context) -> NSView { let view = NSView(); box.view = view; return view }
    func updateNSView(_ view: NSView, context: Context) { box.view = view }
}

private struct ComposerSubmitButtonStyle: ButtonStyle {
    var color: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.black.opacity(0.8))
            // Fade only the fill so the arrow keeps its contrast when disabled.
            .background(color.opacity(isEnabled ? 1 : 0.3), in: .circle)
            .glassPointerFeedback(pressed: configuration.isPressed, in: Circle())
    }
}
