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
            w.isMovableByWindowBackground = true
            w.level = .normal
            w.collectionBehavior = [.moveToActiveSpace, .primary]
            w.minSize = NSSize(width: WindowMetrics.agentMinSize.width, height: WindowMetrics.agentMinSize.height)
            w.maxSize = w.minSize
            w.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: AgentView(model: model, close: { [weak w] in w?.close() },
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
            if model.isRunning { model.draft = prompt } else {
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

private enum AgentLayout {
    // Figma UI page 22:293, new chat 43:1072, conversation 42:761.
    static let radius: CGFloat = LauncherLayout.shellCornerRadius
    static let message = TextStyle(size: 14, weight: 400, mode: .default)
    static let headerHeight: CGFloat = 64
    static let messageHorizontalInset: CGFloat = 18
    static let messageVerticalInset: CGFloat = 14
    static let userMessageVerticalInset: CGFloat = 12
}

struct AgentView: View {
    @Bindable var model: AgentModel
    var close: () -> Void = {}
    var setPinned: (Bool) -> Void = { _ in }
    @State private var composerHeight: CGFloat = 94
    @State private var showingApprovalMenu = false
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

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                if isEmptyConversation {
                    AgentGreeting()
                        .padding(.top, AgentLayout.headerHeight)
                        .padding(.bottom, composerHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(conversationTransition).zIndex(1)
                } else {
                    Transcript(model: model, bottomInset: composerHeight)
                        .id("continuous-transcript")
                        .transition(conversationTransition).zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(navigationAnimation, value: model.conversationID)
            .animation(navigationAnimation, value: isEmptyConversation)
            ProgressiveHeaderBlur(reversed: true)
                .frame(height: composerHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Composer(model: model, showingApprovalMenu: $showingApprovalMenu)
                .padding(.horizontal, 12).padding(.bottom, 12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerHeight = $0 }
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
        .foregroundStyle(ThemeColor.kText.color(for: colorScheme))
        .windowSurfaceBackground(in: shape)
        .modifier(FallbackClipShape(active: !WindowSurface.usesNativeGlass, shape: shape))
        .ignoresSafeArea()
        .background {
            Button("", action: close)
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
        .contentShape(Rectangle())
        .compatibleWindowDrag()
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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AgentModel, bottomInset: CGFloat) {
        self.model = model
        self.bottomInset = bottomInset
        items = model.items
        streaming = model.streaming
        hasOlder = model.hasOlder
        taskID = model.taskID
        taskStartedAt = model.taskStartedAt
        isRunning = model.isRunning
        state = model.state
    }

    var body: some View {
        let allGroups = groups
        let entries = buildEntries(groups: allGroups)
        NativeTranscriptScrollContainer(
            submittedMessageID: items.last(where: { $0.kind == .user })?.id,
            isWaiting: isRunning,
            completedReplyID: items.last(where: { $0.kind == .assistant })?.id,
            viewport: viewport,
            bottomInset: bottomInset,
            replyNavigation: model.replyNavigation,
            hasNewer: model.hasNewer,
            loadLatest: model.loadLatestMessages,
            entries: entries
        )
    }

    private func buildEntries(groups allGroups: [ChatResponseGroup]) -> [TranscriptRowEntry] {
        var result: [TranscriptRowEntry] = []
        result.reserveCapacity(allGroups.count + 2)
        if hasOlder {
            let key = TranscriptRowKey.paging(disabled: isRunning)
            result.append(TranscriptRowEntry(
                id: "__older__",
                groupID: nil,
                itemIDs: [],
                key: key,
                makeView: {
                    AnyView(
                        TranscriptPagingButton(title: NSLocalizedString("加载更早的消息", comment: "")) {
                            viewport.preserveReadingPosition { model.loadOlder() }
                        }
                        .disabled(isRunning)
                        .padding(.bottom, 16)
                    )
                }
            ))
        }
        let avatarColor = model.avatarColor
        for (index, group) in allGroups.enumerated() {
            let topPadding: CGFloat = index == 0 ? 0 : (group.items.first?.kind == .user ? 20 : 12)
            let formStates = group.items.map { item -> TranscriptRowKey.FormState in
                TranscriptRowKey.FormState(
                    id: item.id,
                    answers: model.formAnswers(item.id),
                    active: model.formIsActive(item.id)
                )
            }
            let key = TranscriptRowKey.group(
                group: group,
                topPadding: topPadding,
                avatarColor: avatarColor,
                formStates: formStates,
                colorScheme: colorScheme,
                reduceMotion: reduceMotion
            )
            result.append(TranscriptRowEntry(
                id: "group:\(group.id)",
                groupID: group.id,
                itemIDs: group.items.map(\.id),
                topPadding: topPadding,
                key: key,
                makeView: {
                    AnyView(
                        ResponseGroupView(group: group, model: model)
                            .background { TranscriptGroupPosition(id: group.id) }
                            .padding(.top, topPadding)
                            .foregroundStyle(ThemeColor.kText.color(for: colorScheme))
                    )
                }
            ))
        }
        if model.hasNewer {
            let key = TranscriptRowKey.paging(disabled: isRunning)
            result.append(TranscriptRowEntry(
                id: "__newer__",
                groupID: nil,
                itemIDs: [],
                key: key,
                makeView: {
                    AnyView(
                        TranscriptPagingButton(title: NSLocalizedString("加载更新的消息", comment: "")) {
                            viewport.preserveReadingPosition { model.loadNewer() }
                        }
                        .disabled(isRunning)
                        .padding(.top, 16)
                        .padding(.bottom, 40)
                    )
                }
            ))
        }
        return result
    }

    private var groups: [ChatResponseGroup] {
        var result: [ChatResponseGroup] = []
        for item in items {
            let id = item.responseID ?? item.id
            if result.last?.id == id {
                result[result.count - 1].items.append(item)
            } else {
                result.append(ChatResponseGroup(id: id, items: [item]))
            }
        }
        if isRunning, let id = taskID {
            if result.last?.id != id { result.append(ChatResponseGroup(id: id, items: [])) }
            result[result.count - 1].startedAt = taskStartedAt
            result[result.count - 1].isRunning = true
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

private enum TranscriptRowKey: Equatable {
    struct FormState: Equatable {
        let id: String
        let answers: [String: [String]]
        let active: Bool
    }

    case paging(disabled: Bool)
    case group(
        group: ChatResponseGroup,
        topPadding: CGFloat,
        avatarColor: AgentAvatarColor,
        formStates: [FormState],
        colorScheme: ColorScheme,
        reduceMotion: Bool
    )
}

private struct TranscriptRowEntry {
    let id: String
    let groupID: String?
    let itemIDs: [String]
    var topPadding: CGFloat = 0
    let key: TranscriptRowKey
    let makeView: () -> AnyView
}

@MainActor
private final class TranscriptViewport {
    weak var scroll: NSScrollView?
    var readerMoved = true
    var followsLatestContent = false

    var replyID: String?

    private var readingAnchor: (id: NSUserInterfaceItemIdentifier, offset: CGFloat)?
    private var anchorTask: Task<Void, Never>?
    private var animatingReply = false
    var hasReadingAnchor: Bool { readingAnchor != nil }

    func preserveReadingPosition(_ update: () -> Void) {
        guard let scroll, let document = scroll.documentView else { update(); return }
        followsLatestContent = false
        readerMoved = true
        cancelReadingAnchor()
        func markers(_ view: NSView) -> [NSView] {
            if view.identifier?.rawValue.hasPrefix("transcript-group-") == true { return [view] }
            return view.subviews.flatMap(markers)
        }
        let visible = scroll.contentView.bounds.insetBy(dx: 0, dy: AgentLayout.headerHeight + 12)
        if let marker = markers(document)
            .map({ ($0, scroll.contentView.convert($0.bounds, from: $0)) })
            .filter({ $0.1.intersects(visible) })
            .min(by: { $0.1.minY < $1.1.minY }),
           let id = marker.0.identifier {
            readingAnchor = (id, marker.1.minY - scroll.contentView.bounds.minY)
        }
        update()
        anchorTask = Task { @MainActor [weak self] in
            for _ in 0..<16 {
                do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
                self?.restoreReadingPosition()
            }
            self?.readingAnchor = nil
        }
    }

    func revealReply(_ id: String, reduceMotion: Bool) {
        cancelReadingAnchor()
        followsLatestContent = false
        readerMoved = true
        // The marker is on the text, so subtract the bubble inset as well.
        readingAnchor = (NSUserInterfaceItemIdentifier("transcript-reply-" + id),
                         AgentLayout.headerHeight + 12 + AgentLayout.messageVerticalInset)
        animatingReply = !reduceMotion
        anchorTask = Task { @MainActor [weak self] in
            // Let a newly loaded history page settle before measuring the destination.
            do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            if !reduceMotion {
                await self.animateScroll { self.readingOrigin()?.y }
            }
            guard !Task.isCancelled else { return }
            self.animatingReply = false
            self.restoreReadingPosition()
            for _ in 0..<30 {
                do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
                self.restoreReadingPosition()
            }
            self.readingAnchor = nil
        }
    }

    func cancelReadingAnchor() {
        anchorTask?.cancel()
        readingAnchor = nil
        animatingReply = false
    }

    func restoreReadingPosition() {
        guard !animatingReply, let scroll, let origin = readingOrigin() else { return }
        if abs(scroll.contentView.bounds.minY - origin.y) > 0.5 {
            scroll.contentView.scroll(to: origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    private func readingOrigin() -> NSPoint? {
        guard let readingAnchor, let scroll, let document = scroll.documentView else { return nil }
        let groupPrefix = "transcript-group-"
        if readingAnchor.id.rawValue.hasPrefix(groupPrefix),
           let transcriptDoc = document as? TranscriptDocumentView {
            let gid = String(readingAnchor.id.rawValue.dropFirst(groupPrefix.count))
            if let groupY = transcriptDoc.groupPositionY(groupID: gid) {
                var bounds = scroll.contentView.bounds
                bounds.origin.y = groupY - readingAnchor.offset
                return scroll.contentView.constrainBoundsRect(bounds).origin
            }
        }
        (document as? TranscriptDocumentView)?.ensureMarkerMounted(identifier: readingAnchor.id)
        document.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> NSView? {
            if view.identifier == readingAnchor.id { return view }
            return view.subviews.compactMap(find).first
        }
        guard let marker = find(document) else { return nil }
        var bounds = scroll.contentView.bounds
        bounds.origin.y = scroll.contentView.convert(marker.bounds, from: marker).minY - readingAnchor.offset
        return scroll.contentView.constrainBoundsRect(bounds).origin
    }

    func alignLatestContent() -> Bool {
        guard let scroll, let document = scroll.documentView else { return false }
        if let replyID {
            (document as? TranscriptDocumentView)?.ensureMarkerMounted(
                identifier: NSUserInterfaceItemIdentifier("transcript-reply-" + replyID)
            )
        }
        document.layoutSubtreeIfNeeded()
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

private struct TranscriptGroupPosition: NSViewRepresentable {
    let id: String
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        view.identifier = NSUserInterfaceItemIdentifier("transcript-group-" + id)
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
    return Task { @MainActor in
        // Let native Markdown settle before choosing bottom or reply start.
        for _ in 0..<30 {
            guard !Task.isCancelled, !viewport.readerMoved else { return }
            _ = viewport.alignLatestContent()
            do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
        }
    }
}

@MainActor @Observable
private final class TranscriptBottomState {
    var isAtBottom = true
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

private struct NativeTranscriptScrollContainer: View {
    let submittedMessageID: String?
    let isWaiting: Bool
    let completedReplyID: String?
    let viewport: TranscriptViewport
    let bottomInset: CGFloat
    var replyNavigation: AgentModel.ReplyNavigation?
    var hasNewer = false
    var loadLatest: () -> Void = {}
    let entries: [TranscriptRowEntry]
    @State private var bottomState = TranscriptBottomState()
    @State private var bottomTask: Task<Void, Never>?
    @State private var submissionTask: Task<Void, Never>?
    @State private var replyTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NativeTranscriptScrollView(
            viewport: viewport,
            bottomInset: bottomInset,
            entries: entries,
            onChange: { if bottomState.isAtBottom != $0 { bottomState.isAtBottom = $0 } },
            onUserScroll: cancelAutomatedScroll
        )
        .onDisappear {
            cancelAutomatedScroll()
            viewport.cancelReadingAnchor()
        }
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
            if let newID, newID != oldID, !isWaiting, !viewport.readerMoved {
                bottomTask?.cancel()
                submissionTask?.cancel()
                replyTask?.cancel()
                replyTask = alignTranscriptContent(viewport: viewport, replyID: newID)
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

    private func cancelAutomatedScroll() {
        bottomTask?.cancel()
        submissionTask?.cancel()
        replyTask?.cancel()
        viewport.followsLatestContent = false
        viewport.readerMoved = true
    }
}

private final class TranscriptNSScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?
    var onViewportSizeChanged: (() -> Void)?
    private var lastContentSize: NSSize = .zero
    nonisolated(unsafe) private var nestedScrollMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            if nestedScrollMonitor == nil {
                nestedScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    let handled = MainActor.assumeIsolated {
                        self?.forwardVerticalNestedScrollIfNeeded(event) ?? false
                    }
                    return handled ? nil : event
                }
            }
        } else if let nestedScrollMonitor {
            NSEvent.removeMonitor(nestedScrollMonitor)
            self.nestedScrollMonitor = nil
        }
    }

    private func forwardVerticalNestedScrollIfNeeded(_ event: NSEvent) -> Bool {
        guard let window, event.window === window,
              abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) || abs(event.deltaY) > abs(event.deltaX),
              let hit = window.contentView?.hitTest(event.locationInWindow),
              hit.isDescendant(of: self),
              let inner = hit.enclosingScrollView, inner !== self,
              (inner.documentView?.bounds.height ?? 0) <= inner.documentVisibleRect.height + 0.5,
              !hasTableObserver(inner) else {
            return false
        }
        scrollWheel(with: event)
        return true
    }

    private func hasTableObserver(_ view: NSView) -> Bool {
        view is ChatTableScrollObserver.ObserverView || view.subviews.contains(where: hasTableObserver)
    }

    override func scrollWheel(with event: NSEvent) {
        let phase = event.phase
        if phase.contains(.mayBegin) || phase.contains(.began) || phase.contains(.changed)
            || (phase.isEmpty && event.momentumPhase.isEmpty) {
            onUserScroll?()
        }
        super.scrollWheel(with: event)
    }

    override func layout() {
        super.layout()
        let size = contentView.bounds.size
        if abs(size.width - lastContentSize.width) > 0.5 || abs(size.height - lastContentSize.height) > 0.5 {
            lastContentSize = size
            onViewportSizeChanged?()
        }
    }

    deinit {
        if let nestedScrollMonitor { NSEvent.removeMonitor(nestedScrollMonitor) }
    }
}

private struct TranscriptRowSizedView: View {
    let content: AnyView
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                onHeightChange(height)
            }
    }
}

@MainActor
private final class TranscriptDocumentView: NSView {
    override var isFlipped: Bool { true }

    private struct CachedHeight {
        let width: CGFloat
        let key: TranscriptRowKey
        var height: CGFloat
        var settled: Bool
    }

    private struct HostSlot {
        var key: TranscriptRowKey
        let controller: NSHostingController<TranscriptRowSizedView>
        var lastUsedTick: UInt64
    }

    var onLayoutChanged: (() -> Void)?
    var beforeMountVisibleRows: (() -> Void)?

    private var entries: [TranscriptRowEntry] = []
    private var bottomInset: CGFloat = 0
    private var viewportWidth: CGFloat = 0
    private var viewportHeight: CGFloat = 0
    private var frames: [String: NSRect] = [:]
    private var heightCache: [String: CachedHeight] = [:]
    private var hostCache: [String: HostSlot] = [:]
    private var mountedIDs: Set<String> = []
    private var pinnedRowIDs: Set<String> = []
    private var prewarmControllers: [(id: String, width: CGFloat, key: TranscriptRowKey, controller: NSHostingController<TranscriptRowSizedView>)] = []
    private var prewarmScheduled = false
    private var useTick: UInt64 = 0
    private let buffer: CGFloat = 320
    private let maxCachedHosts = 28

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) { nil }

    func apply(entries: [TranscriptRowEntry], bottomInset: CGFloat, viewportWidth: CGFloat, viewportHeight: CGFloat) {
        let sameSignature = entries.count == self.entries.count
            && abs(bottomInset - self.bottomInset) <= 0.5
            && abs(viewportWidth - self.viewportWidth) <= 0.5
            && abs(viewportHeight - self.viewportHeight) <= 0.5
            && zip(entries, self.entries).allSatisfy { $0.id == $1.id && $0.key == $1.key }
        if sameSignature { return }

        let oldIDs = Set(self.entries.map(\.id))
        let newIDs = Set(entries.map(\.id))
        for removed in oldIDs.subtracting(newIDs) {
            if let slot = hostCache.removeValue(forKey: removed) {
                slot.controller.view.removeFromSuperview()
            }
            mountedIDs.remove(removed)
            pinnedRowIDs.remove(removed)
            heightCache.removeValue(forKey: removed)
        }

        self.entries = entries
        self.bottomInset = bottomInset
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight

        relayoutRows()
        beforeMountVisibleRows?()
        updateVisibleRows()
        schedulePrewarm()
    }

    func groupPositionY(groupID: String) -> CGFloat? {
        guard let entry = entries.first(where: { $0.groupID == groupID }),
              let rect = frames[entry.id] else { return nil }
        return rect.minY + entry.topPadding
    }

    func ensureMarkerMounted(identifier: NSUserInterfaceItemIdentifier) {
        let raw = identifier.rawValue
        let targetID: String?
        if raw.hasPrefix("transcript-group-") {
            let gid = String(raw.dropFirst("transcript-group-".count))
            targetID = entries.first(where: { $0.groupID == gid })?.id
        } else if raw.hasPrefix("transcript-reply-") {
            let rid = String(raw.dropFirst("transcript-reply-".count))
            targetID = entries.first(where: { $0.itemIDs.contains(rid) })?.id
        } else {
            targetID = nil
        }
        guard let targetID, !mountedIDs.contains(targetID) else { return }
        pinnedRowIDs.insert(targetID)
        updateVisibleRows()
    }

    private func relayoutRows() {
        guard viewportWidth > 0 else { return }
        let contentWidth = max(1, viewportWidth - 24)
        var y = AgentLayout.headerHeight + 12
        frames.removeAll(keepingCapacity: true)

        for entry in entries {
            let height: CGFloat
            if let cached = heightCache[entry.id],
               abs(cached.width - contentWidth) <= 0.5,
               cached.key == entry.key {
                height = cached.height
            } else {
                let measurer = NSHostingController(rootView: AnyView(entry.makeView().id(entry.id)))
                measurer.sizingOptions = []
                measurer.view.frame = NSRect(x: -10_000, y: 0, width: contentWidth, height: 100)
                addSubview(measurer.view)
                measurer.view.layoutSubtreeIfNeeded()
                let measured = ceil(measurer.sizeThatFits(in: CGSize(width: contentWidth, height: .greatestFiniteMagnitude)).height)
                measurer.view.removeFromSuperview()
                height = max(1, measured)
                heightCache[entry.id] = CachedHeight(width: contentWidth, key: entry.key, height: height, settled: false)
            }
            frames[entry.id] = NSRect(x: 12, y: y, width: contentWidth, height: height)
            y += height
        }

        let totalHeight = max(viewportHeight, y + bottomInset + 13)
        let targetSize = NSSize(width: viewportWidth, height: totalHeight)
        if abs(frame.width - targetSize.width) > 0.5 || abs(frame.height - targetSize.height) > 0.5 {
            frame = NSRect(origin: .zero, size: targetSize)
        }
        for id in mountedIDs {
            if let rowFrame = frames[id], let slot = hostCache[id] {
                if slot.controller.view.frame != rowFrame {
                    slot.controller.view.frame = rowFrame
                }
            }
        }
    }

    func updateVisibleRows() {
        guard let scroll = enclosingScrollView, viewportWidth > 0 else { return }
        let visible = scroll.documentVisibleRect.insetBy(dx: 0, dy: -buffer)
        var keep: Set<String> = pinnedRowIDs

        for entry in entries {
            guard let rowFrame = frames[entry.id] else { continue }
            if rowFrame.intersects(visible) {
                keep.insert(entry.id)
            } else if mountedIDs.contains(entry.id), let view = hostCache[entry.id]?.controller.view, hasActiveSelectionOrFocus(in: view) {
                keep.insert(entry.id)
            }
        }
        pinnedRowIDs.removeAll()

        for id in mountedIDs.subtracting(keep) {
            if let slot = hostCache[id] {
                slot.controller.view.removeFromSuperview()
            }
            mountedIDs.remove(id)
        }

        for entry in entries where keep.contains(entry.id) {
            guard let rowFrame = frames[entry.id] else { continue }
            useTick &+= 1
            if var slot = hostCache[entry.id] {
                slot.lastUsedTick = useTick
                if slot.key != entry.key {
                    slot.key = entry.key
                    let rowID = entry.id
                    slot.controller.rootView = TranscriptRowSizedView(content: entry.makeView()) { [weak self] h in
                        self?.handleRowHeightChange(rowID: rowID, newHeight: h)
                    }
                }
                hostCache[entry.id] = slot
                let view = slot.controller.view
                if view.frame != rowFrame { view.frame = rowFrame }
                if view.superview !== self { addSubview(view) }
            } else {
                let rowID = entry.id
                let controller = NSHostingController(rootView: TranscriptRowSizedView(content: entry.makeView()) { [weak self] h in
                    self?.handleRowHeightChange(rowID: rowID, newHeight: h)
                })
                controller.sizingOptions = []
                controller.view.translatesAutoresizingMaskIntoConstraints = true
                controller.view.frame = rowFrame
                addSubview(controller.view)
                hostCache[entry.id] = HostSlot(key: entry.key, controller: controller, lastUsedTick: useTick)
            }
            mountedIDs.insert(entry.id)
        }

        if hostCache.count > maxCachedHosts {
            let evictable = hostCache.filter { !mountedIDs.contains($0.key) }
                .sorted { $0.value.lastUsedTick < $1.value.lastUsedTick }
            let excess = hostCache.count - maxCachedHosts
            for (id, _) in evictable.prefix(excess) {
                hostCache.removeValue(forKey: id)
            }
        }
    }

    private func handleRowHeightChange(rowID: String, newHeight: CGFloat) {
        let ceiled = max(1, ceil(newHeight))
        guard var cached = heightCache[rowID] else { return }
        cached.settled = true
        if abs(cached.height - ceiled) <= 0.5 {
            heightCache[rowID] = cached
            return
        }
        cached.height = ceiled
        heightCache[rowID] = cached
        relayoutRows()
        beforeMountVisibleRows?()
        updateVisibleRows()
        onLayoutChanged?()
    }

    private func schedulePrewarm() {
        guard !prewarmScheduled, window != nil, viewportWidth > 0 else { return }
        let contentWidth = max(1, viewportWidth - 24)
        let hasUnsettled = entries.contains { entry in
            !mountedIDs.contains(entry.id)
                && (heightCache[entry.id].map { !$0.settled && abs($0.width - contentWidth) <= 0.5 } ?? false)
        }
        guard hasUnsettled else { return }
        prewarmScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.runPrewarmBatch()
        }
    }

    private func runPrewarmBatch() {
        prewarmScheduled = false
        guard window != nil, viewportWidth > 0 else { return }
        let contentWidth = max(1, viewportWidth - 24)
        if !prewarmControllers.isEmpty {
            var changed = false
            for item in prewarmControllers {
                item.controller.view.layoutSubtreeIfNeeded()
                let settledHeight = max(1, ceil(item.controller.sizeThatFits(in: CGSize(width: item.width, height: .greatestFiniteMagnitude)).height))
                item.controller.view.removeFromSuperview()
                if var cached = heightCache[item.id], abs(cached.width - item.width) <= 0.5, cached.key == item.key {
                    if abs(cached.height - settledHeight) > 0.5 {
                        cached.height = settledHeight
                        changed = true
                    }
                    cached.settled = true
                    heightCache[item.id] = cached
                }
            }
            prewarmControllers.removeAll()
            if changed {
                relayoutRows()
                beforeMountVisibleRows?()
                updateVisibleRows()
                onLayoutChanged?()
            }
        }

        let batch = entries.filter { entry in
            !mountedIDs.contains(entry.id)
                && (heightCache[entry.id].map { !$0.settled && abs($0.width - contentWidth) <= 0.5 && $0.key == entry.key } ?? false)
        }.prefix(24)

        guard !batch.isEmpty else { return }
        for entry in batch {
            let estimated = heightCache[entry.id]?.height ?? 100
            let controller = NSHostingController(rootView: TranscriptRowSizedView(content: entry.makeView()) { _ in })
            controller.sizingOptions = []
            controller.view.translatesAutoresizingMaskIntoConstraints = true
            controller.view.frame = NSRect(x: -10_000, y: 0, width: contentWidth, height: estimated)
            addSubview(controller.view)
            controller.view.layoutSubtreeIfNeeded()
            prewarmControllers.append((entry.id, contentWidth, entry.key, controller))
        }
        prewarmScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.runPrewarmBatch()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            schedulePrewarm()
        } else {
            for item in prewarmControllers { item.controller.view.removeFromSuperview() }
            prewarmControllers.removeAll()
            prewarmScheduled = false
        }
    }

    private func hasActiveSelectionOrFocus(in view: NSView) -> Bool {
        if let responder = view.window?.firstResponder as? NSView, responder.isDescendant(of: view) {
            if let text = responder as? NSTextView, text.selectedRange().length > 0 { return true }
        }
        func hasSelection(_ node: NSView) -> Bool {
            if let text = node as? NSTextView, text.selectedRange().length > 0 { return true }
            return node.subviews.contains(where: hasSelection)
        }
        return hasSelection(view)
    }
}

private struct NativeTranscriptScrollView: NSViewRepresentable {
    let viewport: TranscriptViewport
    let bottomInset: CGFloat
    let entries: [TranscriptRowEntry]
    var onChange: (Bool) -> Void
    var onUserScroll: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(viewport: viewport, onChange: onChange, onUserScroll: onUserScroll)
    }

    func makeNSView(context: Context) -> TranscriptNSScrollView {
        context.coordinator.scroll
    }

    func updateNSView(_ scroll: TranscriptNSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onUserScroll = onUserScroll
        context.coordinator.viewport = viewport
        context.coordinator.update(entries: entries, bottomInset: bottomInset)
    }

    @MainActor
    final class Coordinator: NSObject {
        let scroll = TranscriptNSScrollView()
        let document = TranscriptDocumentView()
        var viewport: TranscriptViewport
        var onChange: (Bool) -> Void
        var onUserScroll: () -> Void
        private var lastEntries: [TranscriptRowEntry] = []
        private var lastBottomInset: CGFloat = 0
        private var syncScheduled = false
        private var positionScheduled = false
        private var lastIsAtBottom: Bool?

        init(viewport: TranscriptViewport, onChange: @escaping (Bool) -> Void, onUserScroll: @escaping () -> Void) {
            self.viewport = viewport
            self.onChange = onChange
            self.onUserScroll = onUserScroll
            super.init()

            document.translatesAutoresizingMaskIntoConstraints = true
            scroll.drawsBackground = false
            scroll.borderType = .noBorder
            scroll.hasVerticalScroller = false
            scroll.hasHorizontalScroller = false
            scroll.automaticallyAdjustsContentInsets = false
            scroll.contentInsets = NSEdgeInsetsZero
            scroll.contentView.drawsBackground = false
            scroll.documentView = document

            viewport.scroll = scroll

            scroll.onUserScroll = { [weak self] in
                self?.viewport.cancelReadingAnchor()
                self?.onUserScroll()
            }
            scroll.onViewportSizeChanged = { [weak self] in
                self?.applyEntries()
            }
            document.onLayoutChanged = { [weak self] in
                self?.schedulePositionUpdate()
            }
            document.beforeMountVisibleRows = { [weak self] in
                self?.viewport.restoreReadingPosition()
            }

            scroll.contentView.postsBoundsChangedNotifications = true
            document.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(userScrolled(_:)),
                name: NSScrollView.willStartLiveScrollNotification, object: scroll)
            NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged(_:)),
                name: NSView.boundsDidChangeNotification, object: scroll.contentView)
            NotificationCenter.default.addObserver(self, selector: #selector(frameChanged(_:)),
                name: NSView.frameDidChangeNotification, object: document)
        }

        func update(entries: [TranscriptRowEntry], bottomInset: CGFloat) {
            lastEntries = entries
            lastBottomInset = bottomInset
            applyEntries()
            scheduleSync()
        }

        private func scheduleSync() {
            guard !syncScheduled else { return }
            syncScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.syncScheduled = false
                self.applyEntries()
            }
        }

        private func applyEntries() {
            let size = scroll.contentView.bounds.size
            guard size.width > 0 else { return }
            document.apply(entries: lastEntries, bottomInset: lastBottomInset, viewportWidth: size.width, viewportHeight: size.height)
            schedulePositionUpdate()
        }

        @objc private func userScrolled(_ notification: Notification) {
            viewport.cancelReadingAnchor()
            onUserScroll()
        }

        @objc private func boundsChanged(_ notification: Notification) {
            document.updateVisibleRows()
            schedulePositionUpdate()
        }

        @objc private func frameChanged(_ notification: Notification) {
            schedulePositionUpdate()
        }

        func schedulePositionUpdate() {
            guard !positionScheduled else { return }
            positionScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.positionScheduled = false
                self.updatePosition()
            }
        }

        private func updatePosition() {
            viewport.scroll = scroll
            if viewport.followsLatestContent, !viewport.readerMoved {
                _ = viewport.alignLatestContent()
            }
            viewport.restoreReadingPosition()
            let atBottom = viewport.isAtBottom
            if lastIsAtBottom != atBottom {
                lastIsAtBottom = atBottom
                onChange(atBottom)
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
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

    var tools: [ChatItem] { items.filter { if case .tool = $0.kind { true } else { false } } }
    var steps: [ChatItem] {
        items.filter { if case .tool = $0.kind { return true }; return $0.kind == .toolNarration }
    }
    var content: [ChatItem] {
        items.filter {
            switch $0.kind {
            case .tool, .toolNarration: false
            case .assistant: !isRunning
            default: true
            }
        }
    }
    var workSeconds: Int? { items.compactMap(\.workSeconds).last }
    var showsThinkingIndicator: Bool { isRunning }
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

private struct ResponseGroupView: View {
    let group: ChatResponseGroup
    let model: AgentModel
    @Namespace private var bubbleMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(group.content) { item in
                message(item)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 5)))
            }
            if group.showsThinkingIndicator {
                ChatTypingBubble(bubbleMotion: bubbleMotion)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.9),
                   value: group.isRunning)
    }

    private func message(_ item: ChatItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ChatBubble(item: item, model: model, bubbleMotion: bubbleMotion,
                showsReplyActions: !group.isRunning && group.content.last(where: { $0.kind == .assistant })?.id == item.id)
            if item.needsPermissionSettings {
                Button(NSLocalizedString("管理权限…", comment: "")) { model.openSettings(permissions: true) }
                    .buttonStyle(.link)
            }
        }
    }
}

/// Only this placeholder is visible until the complete answer is committed.
private struct ChatTypingBubble: View {
    let bubbleMotion: Namespace.ID
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
            .padding(.horizontal, 16).padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 16).fill(ThemeColor.kBackgroundNeutral)
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

private struct CompletionTimeSchedule: TimelineSchedule {
    let completedAt: Date

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(completedAt: completedAt, cursor: startDate, emittedStart: false)
    }

    struct Entries: Sequence, IteratorProtocol {
        let completedAt: Date
        var cursor: Date
        var emittedStart: Bool

        mutating func next() -> Date? {
            if !emittedStart {
                emittedStart = true
                return cursor
            }
            let elapsed = cursor.timeIntervalSince(completedAt)
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
            let nextDate = completedAt.addingTimeInterval(nextOffset)
            cursor = nextDate
            return nextDate
        }
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

private struct AssistantCopyButton: View {
    let text: String
    @State private var copyFeedbackID: UUID?

    var body: some View {
        ChatCopyButton(text: text, copyFeedbackID: $copyFeedbackID)
    }
}

private struct UserCopyActionRow: View {
    let text: String
    let hoverState: UserMessageHoverState
    @State private var copyHovering = false
    @State private var copyFeedbackID: UUID?
    @FocusState private var copyFocused: Bool

    var body: some View {
        ChatCopyButton(text: text, copyFeedbackID: $copyFeedbackID)
            .focused($copyFocused)
            .onHover { copyHovering = $0 }
            .opacity(hoverState.bubbleHovered || copyHovering || copyFocused || copyFeedbackID != nil ? 1 : 0)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct ChatBubble: View {
    @Environment(\.colorScheme) private var scheme
    let item: ChatItem
    let model: AgentModel
    let bubbleMotion: Namespace.ID
    var showsReplyActions = true
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
            VStack(alignment: .trailing, spacing: 8) {
                if !item.attachments.isEmpty || !item.quotes.isEmpty {
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
                VStack(alignment: .trailing, spacing: 4) {
                    HStack { Spacer(minLength: 40); bubble.padding(.horizontal, AgentLayout.messageHorizontalInset).padding(.vertical, AgentLayout.userMessageVerticalInset)
                        .background {
                            RoundedRectangle(cornerRadius: 16).fill(ThemeColor.kBackgroundNeutral)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16).fill(model.avatarColor.userBubbleTint(for: scheme))
                                }
                        }
                        .overlay(alignment: .bottomLeading) {
                            if let emoji = item.agentReaction {
                                Text(emoji)
                                    .font(.system(size: 15))
                                    .padding(.horizontal, 7)
                                    .frame(height: 26)
                                    .background {
                                        Capsule().fill(ThemeColor.kBackgroundNeutral)
                                            .overlay {
                                                Capsule().fill(model.avatarColor.userBubbleTint(for: scheme))
                                            }
                                    }
                                    .overlay(Capsule().strokeBorder(scheme == .dark ? ThemeColor.kBorder.color(for: scheme) : .white, lineWidth: 1))
                                    // Keep the overlapping badge within the bottom text inset.
                                    .offset(x: -8, y: 26 - AgentLayout.userMessageVerticalInset)
                                    .allowsHitTesting(false)
                                    .accessibilityLabel(String(format: NSLocalizedString("Asky 回应了 %@", comment: ""), emoji))
                            }
                        }
                    }
                    UserCopyActionRow(text: item.text, hoverState: hoverState)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            // Include the empty action row and the gap below the bubble in
            // hover tracking, so moving to Copy never hides it mid-gesture.
            .contentShape(.rect)
            .onHover { hoverState.bubbleHovered = $0 }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                ChatReplyView(text: item.text, isStreaming: item.id == "streaming",
                    values: Binding(get: { model.formAnswers(item.id) },
                                    set: { model.setFormAnswers($0, for: item.id) }),
                    active: model.formIsActive(item.id), submit: { model.submitForm(item.id) })
                    .environment(\.chatSelectionColor, model.avatarColor.tint)
                    .environment(\.chatQuoteAction, { model.addQuote($0, sourceMessageID: item.id) })
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        TranscriptReplyPosition(id: item.id)
                    }
                    .padding(.horizontal, AgentLayout.messageHorizontalInset).padding(.vertical, AgentLayout.messageVerticalInset)
                    .background {
                        RoundedRectangle(cornerRadius: 16).fill(ThemeColor.kBackgroundNeutral)
                            .matchedGeometryEffect(id: showsReplyActions ? "reply-surface" : item.id,
                                                   in: bubbleMotion, properties: reduceMotion ? [] : .frame, anchor: .topLeading)
                    }
                if showsReplyActions {
                    HStack(spacing: 16) {
                        HStack(spacing: 0) {
                            AssistantCopyButton(text: item.text)
                            replyButton
                        }
                        if let completed = item.completedAt {
                            TimelineView(CompletionTimeSchedule(completedAt: completed)) { context in
                                Text(ChatCompletionTime.label(completed, now: context.date))
                                    .textStyle(.secondary)
                                    .foregroundStyle(ThemeColor.kTextSubtlest)
                            }
                            .help(ChatCompletionTime.exact(completed))
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 40)
        case .tool, .toolNarration:
            EmptyView()
        case .notice:
            Text(item.text).textStyle(.secondary).foregroundStyle(ThemeColor.kTextSubtle)
                .padding(12).background(ThemeColor.kBackgroundNeutral, in: .rect(cornerRadius: 16))
        case .error:
            Label { Text(item.text) } icon: { Image(mingCute: "warning", size: 16) }.textStyle(.secondary).foregroundStyle(ThemeColor.kTextNegative)
                .padding(12).background(ThemeColor.kBackgroundNeutral, in: .rect(cornerRadius: 16))
        }
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
        .alert(NSLocalizedString("原回复已不可用", comment: ""), isPresented: $replyUnavailable) {
            Button(NSLocalizedString("确定", comment: ""), role: .cancel) {}
        }
    }

    private var replyButton: some View {
        Button {
            model.addQuote(item.text, sourceMessageID: item.id, kind: .reply)
        } label: {
            Image(mingCute: "arrow.turn.down.left", size: 14)
                .frame(width: 16, height: 16).padding(6)
        }
        .buttonStyle(AgentIconButtonStyle())
        .foregroundStyle(ThemeColor("iconSubtlest"))
        .accessibilityLabel(NSLocalizedString("回复消息", comment: ""))
        .help(NSLocalizedString("回复消息", comment: ""))
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChatInlineText(markdown: item.text, literal: true, shrinkToFit: true)
                .environment(\.chatSelectionColor, model.avatarColor.tint)
                .environment(\.chatQuoteAction, { model.addQuote($0, sourceMessageID: item.id) })
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Composer: View {
    @Bindable var model: AgentModel
    @Binding var showingApprovalMenu: Bool
    @State private var importing = false
    @State private var editorHeight: CGFloat = 28
    @State private var editorFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.attachments.isEmpty || !model.quotes.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.quotes.enumerated()), id: \.element.id) { index, quote in
                            ComposerAttachmentCard(quote: quote, quoteNumber: index + 1, remove: {
                                model.quotes.removeAll { $0.id == quote.id }
                            })
                        }
                        ForEach(model.attachments) { attachment in
                            ComposerAttachmentCard(attachment: attachment,
                                thumbnail: model.attachmentThumbnails[attachment.id]) {
                                model.removeAttachment(attachment)
                            }
                        }
                    }
                    // Keep the last delete button inside the scroll content without widening each gap.
                    .padding(.trailing, 8)
                    .padding(.horizontal, 12)
                }
                .scrollIndicators(.hidden).frame(height: 58)
            }
            ComposerTextEditor(text: $model.draft, height: $editorHeight,
                isFocused: $editorFocused,
                pasteAttachment: { model.pasteAttachments() }, submit: { model.send() }, shortcuts: model.shortcutPreferences)
                .environment(\.chatSelectionColor, model.avatarColor.tint)
                .frame(height: editorHeight)
                .padding(.horizontal, 4)
            HStack {
                Button { importing = true } label: {
                    Image(mingCute: "plus", size: 14).frame(width: 28, height: 28)
                }
                .buttonStyle(AgentIconButtonStyle(cornerRadius: 14))
                .accessibilityLabel(NSLocalizedString("选择文件或图片", comment: ""))
                Spacer()
                ApprovalModePicker(model: model, showing: $showingApprovalMenu)
                Button { if model.isRunning { model.stop() } else { model.send() } } label: {
                    Image(mingCute: model.isRunning ? "stop.fill" : "arrow.up", size: 14).frame(width: 28, height: 28)
                }
                .buttonStyle(ComposerSubmitButtonStyle(color: model.avatarColor.tint))
                .disabled(!model.isRunning && !model.canSend)
                .accessibilityLabel(model.isRunning ? NSLocalizedString("停止生成", comment: "") : NSLocalizedString("发送消息", comment: ""))
            }
            .padding(.horizontal, 8)
        }
        // Attachment cards reserve 6 pt above their visible edge for the delete button.
        // Keep the visible top inset aligned with the compact text editor.
        .padding(.top, model.attachments.isEmpty && model.quotes.isEmpty ? 10 : 4).padding(.bottom, 8)
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
}

private struct ApprovalModePicker: View {
    @Bindable var model: AgentModel
    @Binding var showing: Bool
    @State private var pressed = false

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
        .buttonStyle(GlassPressObserverStyle(pressed: $pressed))
        .accessibilityLabel(NSLocalizedString("审批模式", comment: ""))
        .accessibilityValue(Self.title(mode))
        .glassPointerFeedback(pressed: pressed, in: RoundedRectangle(cornerRadius: 14), illumination: false)
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
        .buttonStyle(ApprovalModeRowButtonStyle())
        .accessibilityLabel(ApprovalModePicker.title(option))
        .accessibilityIdentifier(option == .fullAccess ? "approval-mode-full" : "approval-mode-auto")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ApprovalModeRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .contentShape(.rect(cornerRadius: 8))
            .glassPointerFeedback(pressed: configuration.isPressed, in: RoundedRectangle(cornerRadius: 8))
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
                            .nativeGlassBackground(in: RoundedRectangle(cornerRadius: 14), interactive: true)
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
