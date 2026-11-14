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
        presentation.show(window)
    }
}

private enum AgentLayout {
    // Figma UI page 22:293, new chat 43:1072, conversation 42:761.
    static let radius: CGFloat = LauncherLayout.shellCornerRadius
    static let message = TextStyle(size: 14, weight: 400, mode: .default)
    static let headerHeight: CGFloat = 64
    static let messageHorizontalInset: CGFloat = 18
    static let messageVerticalInset: CGFloat = 14
}

struct AgentView: View {
    @Bindable var model: AgentModel
    var close: () -> Void = {}
    var setPinned: (Bool) -> Void = { _ in }
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
        VStack(spacing: 0) {
            ZStack {
                if isEmptyConversation {
                    AgentGreeting()
                        .padding(.top, AgentLayout.headerHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(conversationTransition).zIndex(1)
                } else {
                    Transcript(model: model)
                        .id("continuous-transcript")
                        .transition(conversationTransition).zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(navigationAnimation, value: model.conversationID)
            .animation(navigationAnimation, value: isEmptyConversation)
            Composer(model: model)
                .padding(.horizontal, 12).padding(.bottom, 12)
        }
        .overlay(alignment: .top) {
            ProgressiveHeaderBlur()
                .frame(height: AgentLayout.headerHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .top) { header }
        .overlay(alignment: .topLeading) {
            AgentAvatarPicker(color: Binding(get: { model.avatarColor }, set: { model.avatarColor = $0 }))
                .padding(.leading, 16).padding(.top, 14)
        }
        .foregroundStyle(ThemeColor.kText.color(for: colorScheme))
        .windowSurfaceBackground(in: shape)
        .clipShape(shape)
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
                .nativeGlassBackground(in: Capsule(), clear: true, glassOpacity: 0.85)
                .overlay {
                    HStack(spacing: 0) {
                        ForEach(0..<2) { index in
                            Rectangle().fill(.white.opacity(toolbarPressed == index ? 0.16
                                : toolbarPressed == nil && toolbarHovered == index ? 0.055 : 0))
                        }
                    }
                    .clipShape(Capsule())
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: toolbarPressed)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: toolbarHovered)
                }
                .glassPointerFeedback(pressed: toolbarPressed != nil, in: Capsule(), illumination: false)
        }
        .padding(.horizontal, 16)
        .frame(height: AgentLayout.headerHeight)
        .contentShape(Rectangle())
        .compatibleWindowDrag()
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

private struct Transcript: View {
    let model: AgentModel
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

    init(model: AgentModel) {
        self.model = model
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
            let allGroups = groups
            let currentTurn = allGroups.lastIndex { $0.items.first?.kind == .user } ?? allGroups.count
            CompatibleTranscriptScroll(submittedMessageID: items.last(where: { $0.kind == .user })?.id, isWaiting: isRunning, completedReplyID: items.last(where: { $0.kind == .assistant })?.id, viewport: viewport) {
                VStack(spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if hasOlder {
                            Button(NSLocalizedString("加载更早的消息", comment: "")) { model.loadOlder() }.buttonStyle(.link).frame(maxWidth: .infinity)
                        }
                        ForEach(Array(allGroups.prefix(currentTurn).enumerated()), id: \.element.id) { index, group in
                            ResponseGroupView(group: group, model: model)
                                .padding(.top, index == 0 ? 0 : (group.items.first?.kind == .user ? 20 : 12))
                        }
                    }
                    // Keep the current turn measured even when its full reply exceeds the viewport.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(allGroups.suffix(from: currentTurn).enumerated()), id: \.element.id) { index, group in
                            ResponseGroupView(group: group, model: model)
                                .padding(.top, index == 0 ? (currentTurn == 0 ? 0 : 20) : 12)
                        }
                    }
                    // Keep the destination outside lazy row height estimation.
                    Color.clear.frame(height: 13).id("bottom")
                }
                .padding(.horizontal, 12).padding(.top, 12)
                .padding(.top, AgentLayout.headerHeight)
                // Short conversations rest above the composer. Each new row pushes older rows up.
                .frame(minHeight: geometry.size.height, alignment: .bottom)
            }
        }
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

private struct CompatibleTranscriptScroll<Content: View>: View {
    let submittedMessageID: String?
    let isWaiting: Bool
    let completedReplyID: String?
    let viewport: TranscriptViewport
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 15, *), !SurfaceCompatibility.useMacOS14Compatibility {
            ModernTranscriptScroll(submittedMessageID: submittedMessageID, isWaiting: isWaiting, completedReplyID: completedReplyID, viewport: viewport, content: content)
        } else {
            LegacyTranscriptScroll(submittedMessageID: submittedMessageID, isWaiting: isWaiting, completedReplyID: completedReplyID, viewport: viewport, content: content)
        }
    }
}

/// Lazy rows can refine their heights over several layout passes after a jump.
/// Keep this correction scoped to opening, one submission or an explicit click; replies never start it.
@MainActor
private func alignTranscriptBottom(_ proxy: ScrollViewProxy, viewport: TranscriptViewport,
                                   reduceMotion: Bool) -> Task<Void, Never> {
    Task { @MainActor in
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
        do {
            try await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 220))
            var settledPasses = 0
            for _ in 0..<12 {
                try Task.checkCancellation()
                viewport.alignBottom()
                try await Task.sleep(for: .milliseconds(30))
                settledPasses = viewport.isAtBottom ? settledPasses + 1 : 0
                if settledPasses >= 3 { return }
            }
        } catch { /* The window closed or the reader took over. */ }
    }
}

/// Resolve the actual clip/document bounds after SwiftUI's animated estimate.
@MainActor
private final class TranscriptViewport {
    weak var scroll: NSScrollView?
    var readerMoved = true
    var followsInitialBottom = false

    func revealReplyStart(id: String) -> Bool {
        guard !readerMoved, let scroll, let document = scroll.documentView else { return false }
        document.layoutSubtreeIfNeeded()
        func findReply(_ view: NSView) -> NSView? {
            if view.identifier?.rawValue == "transcript-reply-" + id { return view }
            return view.subviews.compactMap(findReply).first
        }
        guard let reply = findReply(document) else { return false }
        let rect = scroll.contentView.convert(reply.bounds, from: reply)
        let previewHeight = CGFloat(AgentLayout.message.lineHeight * 4)
        if rect.height <= previewHeight {
            alignBottom()
        } else {
            var bounds = scroll.contentView.bounds
            bounds.origin.y = document.isFlipped
                ? rect.minY + previewHeight - bounds.height
                : rect.maxY - previewHeight
            scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(bounds).origin)
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

    func alignBottom() {
        guard let scroll else { return }
        scroll.layoutSubtreeIfNeeded()
        scroll.documentView?.layoutSubtreeIfNeeded()
        guard let bottomY else { return }
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: bottomY))
        scroll.reflectScrolledClipView(scroll.contentView)
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
private func revealCompletedReply(viewport: TranscriptViewport, id: String) -> Task<Void, Never> {
    Task { @MainActor in
        // The placeholder transition can defer creation of the final reply's native marker.
        // Follow only this initial layout, never the reply's bottom.
        for _ in 0..<30 {
            guard !Task.isCancelled, !viewport.readerMoved else { return }
            _ = viewport.revealReplyStart(id: id)
            do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
        }
        viewport.readerMoved = true
    }
}

@available(macOS 15, *)
private struct ModernTranscriptScroll<Content: View>: View {
    let submittedMessageID: String?
    let isWaiting: Bool
    let completedReplyID: String?
    let viewport: TranscriptViewport
    var content: Content
    @State private var isAtBottom = true
    @State private var bottomTask: Task<Void, Never>?
    @State private var submissionTask: Task<Void, Never>?
    @State private var replyTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content.background {
                    TranscriptPosition(viewport: viewport, onChange: { isAtBottom = $0 },
                                       onUserScroll: { bottomTask?.cancel(); submissionTask?.cancel(); replyTask?.cancel(); viewport.followsInitialBottom = false; viewport.readerMoved = true })
                }
            }
            .scrollIndicators(.hidden)
            .onDisappear { bottomTask?.cancel(); submissionTask?.cancel(); replyTask?.cancel(); viewport.followsInitialBottom = false }
            .onChange(of: isWaiting) { _, waiting in
                if !waiting { submissionTask?.cancel() }
            }
            .onChange(of: completedReplyID) { oldID, newID in
                viewport.followsInitialBottom = false
                if let newID, newID != oldID, !isWaiting, !viewport.readerMoved {
                    bottomTask?.cancel()
                    submissionTask?.cancel()
                    replyTask?.cancel()
                    replyTask = revealCompletedReply(viewport: viewport, id: newID)
                }
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.top, for: .sizeChanges)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .tracking {
                    viewport.followsInitialBottom = false
                    bottomTask?.cancel()
                    submissionTask?.cancel()
                    replyTask?.cancel()
                    viewport.readerMoved = true
                }
            }
            .onAppear {
                viewport.readerMoved = !isWaiting
                viewport.followsInitialBottom = !isWaiting
                bottomTask?.cancel()
                bottomTask = alignTranscriptBottom(proxy, viewport: viewport, reduceMotion: true)
            }
            .overlay(alignment: .bottom) {
                if !isAtBottom {
                    Button {
                        bottomTask?.cancel()
                        submissionTask?.cancel()
                        viewport.readerMoved = true
                        bottomTask = alignTranscriptBottom(proxy, viewport: viewport, reduceMotion: reduceMotion)
                    } label: {
                        Image(mingCute: "arrow.up", size: 20)
                            .rotationEffect(.degrees(180))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(AgentHeaderButtonStyle(colorScheme: colorScheme))
                    .accessibilityLabel(NSLocalizedString("回到底部", comment: ""))
                    .help(NSLocalizedString("回到底部", comment: ""))
                    .padding(.bottom, 8)
                }
            }
            .onChange(of: submittedMessageID) { oldID, newID in
                // Only a new outgoing message moves the viewport; replies keep the reading position.
                viewport.followsInitialBottom = false
                if let newID, newID != oldID, isWaiting {
                    bottomTask?.cancel()
                    submissionTask?.cancel()
                    replyTask?.cancel()
                    viewport.readerMoved = false
                    submissionTask = alignTranscriptBottom(proxy, viewport: viewport, reduceMotion: true)
                }
            }
        }
    }
}

/// AppKit bounds notifications cover wheel events and programmatic scrolling on all supported systems.
private struct TranscriptPosition: NSViewRepresentable {
    let viewport: TranscriptViewport
    var onChange: (Bool) -> Void
    var onUserScroll: () -> Void
    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
        view.onUserScroll = onUserScroll
        view.viewport = viewport
        view.scheduleUpdate()
    }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        var onUserScroll: (() -> Void)?
        var viewport: TranscriptViewport?
        private weak var observedScroll: NSScrollView?

        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleUpdate() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); scheduleUpdate() }

        func scheduleUpdate() {
            DispatchQueue.main.async { [weak self] in self?.updatePosition() }
        }

        @objc private func boundsChanged(_ notification: Notification) { scheduleUpdate() }
        @objc private func userScrolled(_ notification: Notification) { onUserScroll?() }

        private func updatePosition() {
            guard let scroll = enclosingScrollView, let document = scroll.documentView else { return }
            viewport?.scroll = scroll
            if observedScroll !== scroll {
                NotificationCenter.default.removeObserver(self)
                observedScroll = scroll
                NotificationCenter.default.addObserver(self, selector: #selector(userScrolled(_:)),
                    name: NSScrollView.willStartLiveScrollNotification, object: scroll)
                scroll.contentView.postsBoundsChangedNotifications = true
                document.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged(_:)),
                    name: NSView.boundsDidChangeNotification, object: scroll.contentView)
                NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged(_:)),
                    name: NSView.frameDidChangeNotification, object: document)
            }
            // Native Markdown/form views can finish measuring after the first scroll task.
            // Follow those layout changes only while opening untouched history.
            if let viewport, viewport.followsInitialBottom, !viewport.isAtBottom {
                viewport.alignBottom()
            }
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
    var content: Content
    @State private var isAtBottom = true
    @State private var bottomTask: Task<Void, Never>?
    @State private var submissionTask: Task<Void, Never>?
    @State private var replyTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            ScrollViewReader { proxy in
                ScrollView {
                    content.background {
                        TranscriptPosition(viewport: viewport, onChange: { isAtBottom = $0 },
                                           onUserScroll: { bottomTask?.cancel(); submissionTask?.cancel(); replyTask?.cancel(); viewport.followsInitialBottom = false; viewport.readerMoved = true })
                    }
                }
                .scrollIndicators(.hidden)
                .onDisappear { bottomTask?.cancel(); submissionTask?.cancel(); replyTask?.cancel(); viewport.followsInitialBottom = false }
                .onChange(of: isWaiting) { _, waiting in
                    if !waiting { submissionTask?.cancel() }
                }
                .onChange(of: completedReplyID) { oldID, newID in
                    viewport.followsInitialBottom = false
                    if let newID, newID != oldID, !isWaiting, !viewport.readerMoved {
                        bottomTask?.cancel()
                        submissionTask?.cancel()
                        replyTask?.cancel()
                        replyTask = revealCompletedReply(viewport: viewport, id: newID)
                    }
                }
                .defaultScrollAnchor(.top)
                .onAppear {
                    viewport.readerMoved = !isWaiting
                    viewport.followsInitialBottom = !isWaiting
                    bottomTask?.cancel()
                    bottomTask = alignTranscriptBottom(proxy, viewport: viewport, reduceMotion: true)
                }
                .overlay(alignment: .bottom) {
                    if !isAtBottom {
                        Button {
                            bottomTask?.cancel()
                            submissionTask?.cancel()
                            viewport.readerMoved = true
                            bottomTask = alignTranscriptBottom(proxy, viewport: viewport, reduceMotion: reduceMotion)
                        } label: {
                            Image(mingCute: "arrow.up", size: 20)
                                .rotationEffect(.degrees(180))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(AgentHeaderButtonStyle(colorScheme: colorScheme))
                        .accessibilityLabel(NSLocalizedString("回到底部", comment: ""))
                        .help(NSLocalizedString("回到底部", comment: ""))
                        .padding(.bottom, 8)
                    }
                }
                .onChange(of: submittedMessageID) { oldID, newID in
                    viewport.followsInitialBottom = false
                    if let newID, newID != oldID, isWaiting {
                        bottomTask?.cancel()
                        submissionTask?.cancel()
                        replyTask?.cancel()
                        viewport.readerMoved = false
                        submissionTask = alignTranscriptBottom(proxy, viewport: viewport, reduceMotion: true)
                    }
                }
            }
        }
    }
}

struct ChatResponseGroup: Identifiable {
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

private struct ChatBubble: View {
    @Environment(\.colorScheme) private var scheme
    let item: ChatItem
    let model: AgentModel
    let bubbleMotion: Namespace.ID
    var showsReplyActions = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var copyHovering = false
    @State private var copyFeedbackID: UUID?
    @FocusState private var copyFocused: Bool

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
                    HStack { Spacer(minLength: 40); bubble.padding(.horizontal, AgentLayout.messageHorizontalInset).padding(.vertical, AgentLayout.messageVerticalInset)
                        .background {
                            RoundedRectangle(cornerRadius: 16).fill(ThemeColor.kBackgroundNeutral)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16).fill(model.avatarColor.userBubbleTint(for: scheme))
                                }
                        } }
                    copyButton
                        .onHover { copyHovering = $0 }
                        .opacity(hovering || copyHovering || copyFocused || copyFeedbackID != nil ? 1 : 0)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            // Include the empty action row and the gap below the bubble in
            // hover tracking, so moving to Copy never hides it mid-gesture.
            .contentShape(.rect)
            .onHover { hovering = $0 }
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
                        if item.id == model.items.last(where: { $0.kind == .assistant })?.id {
                            TranscriptReplyPosition(id: item.id)
                        }
                    }
                    .padding(.horizontal, AgentLayout.messageHorizontalInset).padding(.vertical, AgentLayout.messageVerticalInset)
                    .background {
                        RoundedRectangle(cornerRadius: 16).fill(ThemeColor.kBackgroundNeutral)
                            .matchedGeometryEffect(id: showsReplyActions ? "reply-surface" : item.id,
                                                   in: bubbleMotion, properties: reduceMotion ? [] : .frame, anchor: .topLeading)
                    }
                if showsReplyActions {
                    HStack(spacing: 16) {
                        copyButton
                            // Align the glyph with the message text inset.
                            .padding(.leading, 10)
                        if let completed = item.completedAt {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
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
            ForEach(item.quotes) { _ in ComposerAttachmentCard(quoteWithRemoval: nil) }
            ForEach(inlineAttachments) { attachment in
                ComposerAttachmentCard(attachment: attachment, thumbnail: nil)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var copyButton: some View {
        Button {
            if MessageClipboard.copy(item.text) {
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
        .buttonStyle(AgentIconButtonStyle()).focused($copyFocused).foregroundStyle(ThemeColor("iconSubtlest"))
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

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChatInlineText(markdown: item.text, literal: true, shrinkToFit: true)
                .environment(\.chatSelectionColor, model.avatarColor.tint)
                .environment(\.chatQuoteAction, { model.addQuote($0, sourceMessageID: item.id) })
        }
    }
}

private struct Composer: View {
    @Bindable var model: AgentModel
    @State private var importing = false
    @State private var editorHeight: CGFloat = 28
    @State private var editorFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.attachments.isEmpty || !model.quotes.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.quotes) { quote in
                            ComposerAttachmentCard(quoteWithRemoval: {
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
            .padding(.horizontal, 12)
            HStack {
                Button { importing = true } label: {
                    Image(mingCute: "plus", size: 14).frame(width: 28, height: 28)
                }
                .buttonStyle(AgentIconButtonStyle(cornerRadius: 14))
                .accessibilityLabel(NSLocalizedString("选择文件或图片", comment: ""))
                Spacer()
                ApprovalModePicker(model: model)
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
        .nativeGlassBackground(in: RoundedRectangle(cornerRadius: 16, style: .circular), clear: true, glassOpacity: 0.85)
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
    @State private var showing = false

    static let iconSize: CGFloat = 16

    var body: some View {
        let mode = model.approvalMode
        Button { showing.toggle() } label: {
            HStack(alignment: .center, spacing: 4) {
                Image(mingCute: Self.icon(mode), size: Self.iconSize)
                    .frame(width: Self.iconSize, height: Self.iconSize)
                Text(Self.shortTitle(mode)).font(.system(size: 13))
            }
            .foregroundStyle(mode == .fullAccess ? AnyShapeStyle(ThemeColor.kTextNegative) : AnyShapeStyle(ThemeColor.kTextSubtle))
            .padding(.horizontal, 10).frame(height: 28)
        }
        .buttonStyle(AgentIconButtonStyle(cornerRadius: 16))
        .accessibilityLabel(NSLocalizedString("审批模式", comment: ""))
        .accessibilityValue(Self.title(mode))
        .modifier(ApprovalMenuPresentation(showing: $showing) { menu(mode) })
    }

    private func menu(_ mode: ApprovalMode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ApprovalMode.allCases, id: \.self) { option in
                ApprovalModeRow(option: option, selected: option == mode) {
                    model.approvalMode = option
                    showing = false
                }
            }
        }
        .padding(6).frame(width: 340)
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

    static func detail(_ mode: ApprovalMode) -> String {
        mode == .fullAccess
            ? NSLocalizedString("AI 执行任何操作都不再询问，包括删除、发送和修改", comment: "")
            : NSLocalizedString("仅对检测到的风险操作请求批准", comment: "")
    }
}

private struct ApprovalModeRow: View {
    let option: ApprovalMode
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let tint = option == .fullAccess ? AnyShapeStyle(ThemeColor.kTextNegative) : AnyShapeStyle(ThemeColor.kText)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Image(mingCute: ApprovalModePicker.icon(option), size: ApprovalModePicker.iconSize)
                        .frame(width: 20, height: ApprovalModePicker.iconSize)
                    Text(ApprovalModePicker.title(option)).font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 8)
                    if selected { Image(mingCute: "checkmark", size: 12) }
                }
                Text(ApprovalModePicker.detail(option)).font(.system(size: 12)).opacity(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 30)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(.rect(cornerRadius: 8))
            .background {
                if hovering { RoundedRectangle(cornerRadius: 8).fill(ThemeColor.kInteractionHover) }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
            .overlay(alignment: .bottomTrailing) {
                if showing {
                    menu()
                        .nativeGlassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .background(ViewReader(box: menuView).allowsHitTesting(false))
                        .fixedSize()
                        // Sit 8 pt above the 32 pt picker, extending over the send button and its spacing.
                        .offset(x: 40, y: -40)
                        .transition(reduceMotion ? .opacity
                                    : .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
                }
            }
            .animation(.easeOut(duration: 0.15), value: showing)
            .onChange(of: showing) { _, shown in shown ? startMonitoring() : stopMonitoring() }
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
                dismiss.wrappedValue = false
                return true
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
