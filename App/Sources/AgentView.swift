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
        if window == nil {
            let w = AgentWindow(contentRect: NSRect(x: 0, y: 0, width: WindowMetrics.agentInitialSize.width,
                                                 height: WindowMetrics.agentInitialSize.height),
                             styleMask: [.borderless, .resizable, .miniaturizable, .fullSizeContentView],
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
            w.maxSize = NSSize(width: WindowMetrics.agentWidth, height: .greatestFiniteMagnitude)
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
        model.reloadConversations()
        if let prompt {
            if model.isRunning { model.draft = prompt } else {
                model.open(nil)
                model.draft = prompt
                model.send()
            }
        }
    }

    var isVisible: Bool { window?.isVisible == true }

    func showNewConversation() {
        show()
        Task { await model.startNewConversation() }
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
    // Figma UI page 22:293, new chat 43:1072, conversation 42:761 and history 38:654.
    static let radius: CGFloat = LauncherLayout.shellCornerRadius
    static let message = TextStyle(size: 14, weight: 400, mode: .default)
    static let title = TextStyle(size: 13, weight: 500, mode: .default)
}

struct AgentView: View {
    @Bindable var model: AgentModel
    var close: () -> Void = {}
    var setPinned: (Bool) -> Void = { _ in }
    @State private var pinned = false
    @State private var showingHistory = false
    @State private var historyQuery = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: AgentLayout.radius, style: .circular) }
    private var navigationAnimation: Animation { .easeInOut(duration: reduceMotion ? 0.15 : 0.24) }
    private var historyTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(x: -16))
    }
    private var conversationTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8))
    }
    private var isEmptyConversation: Bool { model.items.isEmpty && !model.isRunning }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                if showingHistory {
                    history.transition(historyTransition).zIndex(1)
                } else {
                    VStack(spacing: 0) {
                        ZStack {
                            if isEmptyConversation {
                                AgentGreeting()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .transition(conversationTransition).zIndex(1)
                            } else {
                                Transcript(model: model)
                                    .id(model.conversationID)
                                    .transition(conversationTransition).zIndex(1)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Animate navigation and the empty-state boundary, never token updates.
                        .animation(navigationAnimation, value: model.conversationID)
                        .animation(navigationAnimation, value: isEmptyConversation)
                        Composer(model: model)
                            .padding(.horizontal, 12).padding(.bottom, 12)
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 16)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(navigationAnimation, value: showingHistory)
        }
        .foregroundStyle(ThemeColor.kText.color(for: colorScheme))
        .windowSurfaceBackground(in: shape)
        .clipShape(shape)
        .ignoresSafeArea()
        .onChange(of: model.newConversationRevision) { showingHistory = false; historyQuery = "" }
        .background {
            Button("") { if showingHistory { showingHistory = false } else { close() } }
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
        HStack(spacing: 8) {
            if showingHistory {
                Button { showingHistory = false } label: { headerIcon("chevron.left") }
                    .accessibilityLabel(NSLocalizedString("返回对话", comment: ""))
                    .help(NSLocalizedString("返回对话", comment: ""))
                HStack(spacing: 8) {
                    Image(mingCute: "magnifyingglass", size: 14)
                        .foregroundStyle(ThemeColor.kIconSubtle.color(for: colorScheme))
                    ConversationSearchField(text: $historyQuery,
                        textColor: NSColor(ThemeColor.kText.color(for: colorScheme)),
                        placeholderColor: NSColor(ThemeColor.kTextSubtlest.color(for: colorScheme)))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 6) {
                    Text(model.conversations.first { $0.id == model.conversationID }?.title ?? NSLocalizedString("新对话", comment: ""))
                        .textStyle(AgentLayout.title)
                        .foregroundStyle(ThemeColor.kTextSubtle.color(for: colorScheme))
                        .lineLimit(1).truncationMode(.tail)
                    if pinned {
                        Image(mingCute: "pin.fill", size: 12)
                            .foregroundStyle(ThemeColor.kIconSubtle.color(for: colorScheme))
                            .accessibilityLabel(NSLocalizedString("已置顶", comment: ""))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
            }
            Button { model.open(nil); showingHistory = false } label: { headerIcon("pencil") }
                .disabled(model.isRunning)
                .accessibilityLabel(NSLocalizedString("新对话", comment: ""))
                .help(NSLocalizedString("新对话", comment: ""))
                .keyboardShortcut(model.shortcutPreferences.shortcut(.newChat).keyEquivalent,
                                  modifiers: model.shortcutPreferences.shortcut(.newChat).eventModifiers)
            Menu {
                Button {
                    showingHistory.toggle()
                    model.reloadConversations()
                } label: {
                    Label { Text(NSLocalizedString(showingHistory ? "返回对话" : "历史对话", comment: "")) }
                        icon: { Image(mingCute: showingHistory ? "chevron.left" : "list.bullet") }
                }
                .keyboardShortcut(model.shortcutPreferences.shortcut(.history).keyEquivalent,
                                  modifiers: model.shortcutPreferences.shortcut(.history).eventModifiers)
                Toggle(isOn: Binding(get: { pinned }, set: { pinned = $0; setPinned($0) })) {
                    Label { Text(NSLocalizedString("置顶窗口", comment: "")) } icon: { Image(mingCute: "pin") }
                }
                Divider()
                Button { model.openSettings() } label: {
                    Label { Text(NSLocalizedString("设置…", comment: "")) } icon: { Image(mingCute: "gearshape") }
                }
                Button(action: close) {
                    Label { Text(NSLocalizedString("关闭对话窗口", comment: "")) } icon: { Image(mingCute: "xmark") }
                }
                .keyboardShortcut(model.shortcutPreferences.shortcut(.closeChat).keyEquivalent,
                                  modifiers: model.shortcutPreferences.shortcut(.closeChat).eventModifiers)
            } label: { headerIcon("ellipsis.vertical") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(NSLocalizedString("更多操作", comment: ""))
            .accessibilityLabel(NSLocalizedString("更多操作", comment: ""))
        }
        .buttonStyle(AgentToolbarButtonStyle(colorScheme: colorScheme))
        .padding(.horizontal, 16)
        .frame(height: 48)
        .contentShape(Rectangle())
        .compatibleWindowDrag()
    }

    private func headerIcon(_ symbol: String) -> some View {
        Image(mingCute: symbol, size: 16)
            .frame(width: 28, height: 28)
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 7))
    }

    private var history: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.conversations.filter { historyQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(historyQuery) }) { c in
                    Button { model.open(c.id); showingHistory = false } label: {
                        HStack(spacing: 12) {
                            Text(c.title).lineLimit(1).truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(c.updatedAt, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                                .foregroundStyle(ThemeColor.kTextSubtlest).fixedSize()
                        }
                    }
                    .buttonStyle(AgentHistoryRowStyle(selected: model.conversationID == c.id))
                    .disabled(model.isRunning)
                    .contextMenu {
                        Button(NSLocalizedString("删除对话", comment: ""), role: .destructive) { model.delete(c.id) }.disabled(model.isRunning)
                    }
                }
            }
            .textStyle(AgentLayout.message).padding(.horizontal, 12).padding(.vertical, 12)
        }
        .frame(maxHeight: .infinity)
    }
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

private struct AgentToolbarButtonStyle: ButtonStyle {
    let colorScheme: ColorScheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(ThemeColor.kTextSubtle.color(for: colorScheme))
            .background {
                if isEnabled && (hovering || configuration.isPressed) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(ThemeColor.kInteractionHover.color(for: colorScheme))
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .onHover { hovering = $0 }
    }
}

private struct AgentHeaderButtonStyle: ButtonStyle {
    let colorScheme: ColorScheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14)).foregroundStyle(ThemeColor.kTextSubtle.color(for: colorScheme))
            .nativeGlassBackground(in: Circle())
            .overlay {
                if isEnabled && (hovering || configuration.isPressed) {
                    Circle().fill(ThemeColor.kInteractionHover.color(for: colorScheme))
                }
            }
            .contentShape(.interaction, Circle())
            .opacity(isEnabled && configuration.isPressed ? 0.7 : 1)
            .onHover { hovering = $0 }
    }
}

private struct AgentHistoryRowStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 16).frame(height: 48)
            .contentShape(.rect(cornerRadius: 12))
            .background {
                if isEnabled && (hovering || configuration.isPressed) {
                    RoundedRectangle(cornerRadius: 12).fill(ThemeColor.kInteractionHover)
                } else if selected {
                    RoundedRectangle(cornerRadius: 12).fill(ThemeColor.kBackgroundNeutral)
                }
            }
            .onHover { hovering = $0 }
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
    }
}

private struct Transcript: View {
    let model: AgentModel
    // Value snapshots let an outgoing transcript finish fading after model.open
    // clears/replaces the active conversation. The live model still owns actions.
    private let items: [ChatItem]
    private let hasOlder: Bool
    private let taskID: String?
    private let taskStartedAt: Date?
    private let isRunning: Bool
    private let state: AgentTaskState?

    init(model: AgentModel) {
        self.model = model
        items = model.items
        hasOlder = model.hasOlder
        taskID = model.taskID
        taskStartedAt = model.taskStartedAt
        isRunning = model.isRunning
        state = model.state
    }

    var body: some View {
        CompatibleTranscriptScroll(itemCount: items.count, activity: groups.last?.activityLabel ?? "") {
            LazyVStack(alignment: .leading, spacing: 0) {
                if hasOlder {
                    Button(NSLocalizedString("加载更早的消息", comment: "")) { model.loadOlder() }.buttonStyle(.link).frame(maxWidth: .infinity)
                }
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    ResponseGroupView(group: group, model: model)
                        .padding(.top, index == 0 ? 0 : (group.items.first?.kind == .user ? 20 : 12))
                }
                Color.clear.frame(height: 1).id("bottom")
            }
            .padding(.horizontal, 32).padding(.vertical, 12)
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
            result[result.count - 1].state = state
        }
        return result
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
    let itemCount: Int
    let activity: String
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 15, *), !SurfaceCompatibility.useMacOS14Compatibility {
            ModernTranscriptScroll(itemCount: itemCount, activity: activity, content: content)
        } else {
            LegacyTranscriptScroll(itemCount: itemCount, activity: activity, content: content)
        }
    }
}

@available(macOS 15, *)
private struct ModernTranscriptScroll<Content: View>: View {
    let itemCount: Int
    let activity: String
    var content: Content
    @State private var isAtBottom = true
    @State private var scrollPosition = ScrollPosition()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            ScrollView {
                content
            }
            .scrollPosition($scrollPosition)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height
                    >= geometry.contentSize.height + geometry.contentInsets.bottom - 1
            } action: { _, atBottom in
                isAtBottom = atBottom
            }
            .overlay(alignment: .bottom) {
                if !isAtBottom {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            scrollPosition.scrollTo(edge: .bottom)
                        }
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
            .onChange(of: itemCount) {
                if isAtBottom { scrollPosition.scrollTo(edge: .bottom) }
            }
            .onChange(of: activity) {
                if isAtBottom { scrollPosition.scrollTo(edge: .bottom) }
            }
        }
    }
}

/// AppKit bounds notifications also cover wheel events and programmatic scrolling on 14.
private struct LegacyTranscriptPosition: NSViewRepresentable {
    var onChange: (Bool) -> Void
    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
        view.scheduleUpdate()
    }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        private weak var observedScroll: NSScrollView?

        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleUpdate() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); scheduleUpdate() }

        func scheduleUpdate() {
            DispatchQueue.main.async { [weak self] in self?.updatePosition() }
        }

        @objc private func boundsChanged(_ notification: Notification) { scheduleUpdate() }

        private func updatePosition() {
            guard let scroll = enclosingScrollView, let document = scroll.documentView else { return }
            if observedScroll !== scroll {
                NotificationCenter.default.removeObserver(self)
                observedScroll = scroll
                scroll.contentView.postsBoundsChangedNotifications = true
                document.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged(_:)),
                    name: NSView.boundsDidChangeNotification, object: scroll.contentView)
                NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged(_:)),
                    name: NSView.frameDidChangeNotification, object: document)
            }
            onChange?(scroll.documentVisibleRect.maxY >= document.bounds.maxY - 1)
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

private struct LegacyTranscriptScroll<Content: View>: View {
    let itemCount: Int
    let activity: String
    var content: Content
    @State private var isAtBottom = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            ScrollViewReader { proxy in
                ScrollView {
                    content.background {
                        LegacyTranscriptPosition { isAtBottom = $0 }
                    }
                }
                .defaultScrollAnchor(.bottom)
                .overlay(alignment: .bottom) {
                    if !isAtBottom {
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
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
                .onChange(of: itemCount) {
                    if isAtBottom { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: activity) {
                    if isAtBottom { proxy.scrollTo("bottom", anchor: .bottom) }
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

    var tools: [ChatItem] { items.filter { if case .tool = $0.kind { true } else { false } } }
    var content: [ChatItem] { items.filter { if case .tool = $0.kind { false } else { true } } }
    var workSeconds: Int? { items.compactMap(\.workSeconds).last }
    var activityLabel: String {
        if state == .running || state == .starting || state == nil {
            if let tool = tools.last(where: { $0.kind == .tool(nil) }) {
                return String(format: NSLocalizedString("正在使用 %@…", comment: ""), tool.activityToolName)
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
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if group.isRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                    Text(group.activityLabel)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: group.activityLabel)
                    Spacer(minLength: 8)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = group.startedAt.map { max(0, Int(context.date.timeIntervalSince($0))) } ?? 0
                        Text(String(format: NSLocalizedString("Work for %ds", comment: "Tool execution duration"), seconds))
                    }
                }
                .textStyle(AgentLayout.message)
                .foregroundStyle(ThemeColor.kTextSubtlest)
            }
            if !group.isRunning && (group.workSeconds != nil || !group.tools.isEmpty) {
                VStack(alignment: .leading, spacing: 0) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = group.startedAt.map { max(0, Int(context.date.timeIntervalSince($0))) } ?? group.workSeconds ?? 0
                        if group.tools.isEmpty {
                            Text(String(format: NSLocalizedString("Work for %ds", comment: "Tool execution duration"), seconds))
                                .textStyle(AgentLayout.message)
                                .foregroundStyle(ThemeColor.kTextSubtlest)
                        } else {
                            Button {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(String(format: NSLocalizedString("Work for %ds", comment: "Tool execution duration"), seconds))
                                    Image(mingCute: "chevron.right", size: 12)
                                        .rotationEffect(.degrees(expanded ? 90 : 0))
                                        .accessibilityHidden(true)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(ToolErrorDisclosureButtonStyle())
                            .textStyle(AgentLayout.message)
                            .foregroundStyle(ThemeColor.kTextSubtlest)
                            .accessibilityLabel(String(format: NSLocalizedString("Work for %ds", comment: "Tool execution duration"), seconds))
                            .accessibilityValue(expanded ? "expanded" : "collapsed")
                            .accessibilityHint(NSLocalizedString(expanded ? "收起工具调用" : "展开工具调用", comment: ""))
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(group.tools) { item in message(item) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .frame(height: expanded ? nil : 0, alignment: .top)
                    .opacity(expanded ? 1 : 0)
                    .clipped()
                    .allowsHitTesting(expanded)
                    .accessibilityHidden(!expanded)
                }
            }
            ForEach(visibleContent) { item in message(item) }
        }
        .onChange(of: group.isRunning) { _, running in
            if !running { expanded = false }
        }
    }

    private var visibleContent: [ChatItem] {
        group.content.filter { !group.isRunning || $0.kind != .assistant }
    }

    private func message(_ item: ChatItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ChatBubble(item: item, model: model,
                showsReplyActions: !group.isRunning && group.content.last(where: { $0.kind == .assistant })?.id == item.id)
            if item.needsPermissionSettings {
                Button(NSLocalizedString("管理权限…", comment: "")) { model.openSettings(permissions: true) }
                    .buttonStyle(.link)
            }
        }
    }
}

private struct ChatBubble: View {
    let item: ChatItem
    let model: AgentModel
    var showsReplyActions = true
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
                if !item.attachments.isEmpty {
                    if imageAttachments.count > 1 {
                        ChatImageAttachmentStack(attachments: imageAttachments)
                    }
                    if !inlineAttachments.isEmpty {
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
                    HStack { Spacer(minLength: 40); bubble.padding(.horizontal, 12).padding(.vertical, 10)
                        .background(ThemeColor.kBackgroundNeutral, in: .rect(cornerRadius: 16)) }
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
            VStack(alignment: .leading, spacing: 16) {
                ChatReplyView(text: item.text,
                    values: Binding(get: { model.formValues[item.id] ?? [:] },
                                    set: { model.formValues[item.id] = $0 }),
                    active: model.formIsActive(item.id), submit: { model.submitForm(item.id) })
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsReplyActions {
                    HStack(spacing: 16) {
                        copyButton
                            // Align the visible glyph with the text, keeping its padded hit area.
                            .padding(.leading, -8)
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
        case .tool(let status):
            ToolCallRow(item: item, status: status)
        case .notice:
            Text(item.text).textStyle(.secondary).foregroundStyle(ThemeColor.kTextSubtle)
        case .error:
            Label { Text(item.text) } icon: { Image(mingCute: "warning", size: 16) }.textStyle(.secondary).foregroundStyle(ThemeColor.kTextNegative)
        }
    }

    private var attachmentCards: some View {
        HStack(spacing: 8) {
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
        Text(LocalizedStringKey(item.text)).textStyle(AgentLayout.message).textSelection(.enabled)
    }
}

private struct Composer: View {
    @Bindable var model: AgentModel
    @State private var importing = false
    @State private var editorHeight: CGFloat = 28
    @State private var editorFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
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
                .buttonStyle(ComposerSubmitButtonStyle())
                .disabled(!model.isRunning && !model.canSend)
                .accessibilityLabel(model.isRunning ? NSLocalizedString("停止生成", comment: "") : NSLocalizedString("发送消息", comment: ""))
            }
            .padding(.horizontal, 8)
        }
        // Attachment cards reserve 6 pt above their visible edge for the delete button.
        // Keep the visible top inset aligned with the compact text editor.
        .padding(.top, model.attachments.isEmpty ? 10 : 4).padding(.bottom, 8)
        .nativeGlassBackground(in: RoundedRectangle(cornerRadius: 16, style: .circular), clear: true, glassOpacity: 0.35)
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
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(ThemeColor("iconInverted"))
            // Fade only the fill so the arrow keeps its contrast when disabled.
            .background(ThemeColor.kBackgroundPrimary.opacity(isEnabled ? 1 : 0.3), in: .circle)
    }
}

private struct ToolErrorDisclosureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(ThemeColor.kTextSubtlest)
    }
}

private struct ToolCallRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: ChatItem
    let status: ExecutionStatus?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Group {
                    if status == nil {
                        ProgressView().controlSize(.small)
                    } else if status == .failed {
                        Image(mingCute: "warning", size: 16)
                            .accessibilityLabel(AgentModel.statusLabel(.failed))
                    } else if item.pluginID != nil {
                        Image(mingCute: "tool", size: 16)
                    } else if let source = item.toolSource, source != .web, source != .memory {
                        DataSourceIcon(source: source)
                    } else {
                        Image(mingCute: item.toolSymbol)
                    }
                }
                .frame(width: 16, height: 16)
                if item.toolError != nil {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            expanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(item.text)
                            Image(mingCute: "chevron.right", size: 12)
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ToolErrorDisclosureButtonStyle())
                    .accessibilityHint(NSLocalizedString(expanded ? "收起错误详情" : "展开错误详情", comment: ""))
                    .accessibilityValue(expanded ? "expanded" : "collapsed")
                } else {
                    Text(item.text).textSelection(.enabled)
                }
                if let status, status != .completed, status != .failed {
                    Text(AgentModel.statusLabel(status))
                }
                Spacer(minLength: 0)
            }
            if let error = item.toolError {
                Text(error).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 24)
                    .padding(.top, 8)
                    .frame(height: expanded ? nil : 0, alignment: .top)
                    .opacity(expanded ? 1 : 0)
                    .clipped()
                    .accessibilityHidden(!expanded)
            }
        }
        .textStyle(AgentLayout.message)
        .foregroundStyle(ThemeColor.kTextSubtlest)

    }
}
