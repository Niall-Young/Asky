import AppKit
import SwiftUI
import Theme
import ToolService

/// One in-app reminder card. Unlike UserNotifications, Asky draws the whole surface itself.
struct ReminderBannerItem: Identifiable {
    struct Action {
        var title: String
        var prominent = false
        var dismissesCard = true
        var handler: @MainActor () -> Void = {}
    }

    let id = UUID()
    var source: String
    var timeLabel: String
    var title: String
    var body: String
    var symbol = "calendar"
    /// Supporting context retained with the reminder; not displayed on the card.
    var reasons: [String] = []
    var actions: [Action] = []
    /// Auto-dismiss delay; hovering pauses it. nil keeps the card until the user acts.
    var lifetime: TimeInterval? = 8
}

/// One floating stack in the top-right corner that never takes focus from the frontmost app.
/// New cards slide in from the right with 8 pt gaps; after a few seconds the stack folds so only the
/// first card stays readable and the rest peek out underneath, to be handled one at a time.
@MainActor
final class ReminderBannerCenter {
    static let shared = ReminderBannerCenter()

    static let width: CGFloat = 360
    static let gap: CGFloat = 8
    /// How much each folded card shows under the one in front of it.
    static let peek: CGFloat = 8
    static let maxPeeking = 2
    /// Transparent canvas around the stack so the panel does not clip card shadows.
    static let shadowInset: CGFloat = 24
    private static let margin: CGFloat = 12
    private static let foldDelay: TimeInterval = 4
    private static let maxCards = 5

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var slide: Animation { reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.4) }
    static var reflow: Animation { reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.45, bounce: 0.12) }

    let stack = ReminderBannerStack()
    private var panel: ReminderBannerPanel?
    private var screenID: CGDirectDisplayID?
    private var screenObserver: NSObjectProtocol?
    private var waiting: [ReminderBannerItem] = []
    private var timers: [UUID: Timer] = [:]
    private var remaining: [UUID: TimeInterval] = [:]
    private var deadlines: [UUID: Date] = [:]
    private var foldTimer: Timer?
    private var shrinkWork: DispatchWorkItem?

    private init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible else { return }
                self.setPanelHeight(panel.frame.height, panel)
            }
        }
    }

    func show(_ item: ReminderBannerItem) {
        guard stack.cards.filter({ !$0.leaving }).count < Self.maxCards else { waiting.append(item); return }
        let panel = preparePanel()
        remaining[item.id] = item.lifetime
        stack.cards.append(.init(item: item))
        panel.orderFrontRegardless()
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: "\(item.title)，\(item.body)", .priority: NSAccessibilityPriorityLevel.high.rawValue])
        // The slide starts once the card has reported its height (see measured), so it never animates layout.
    }

    func dismiss(_ id: UUID) {
        waiting.removeAll { $0.id == id }
        guard let index = stack.cards.firstIndex(where: { $0.id == id && !$0.leaving }) else { return }
        stopTimer(id)
        remaining[id] = nil
        stack.cards[index].frozenY = stack.y(of: id)
        stack.cards[index].leaving = true
        stack.cards[index].settled = false
        withAnimation(Self.reduceMotion ? .easeOut(duration: 0.15) : .easeIn(duration: 0.25)) { stack.cards[index].presented = false }
        // The rest close the gap (or the next folded card comes forward) while this one slides out.
        withAnimation(Self.reflow) { stack.layoutVersion += 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + (Self.reduceMotion ? 0.15 : 0.3)) { [weak self] in
            guard let self else { return }
            stack.cards.removeAll { $0.id == id }
            if !waiting.isEmpty { show(waiting.removeFirst()) }
            if stack.cards.isEmpty { panel?.orderOut(nil); stack.expanded = true }
            afterChange()
        }
        afterChange()
    }

    func dismissAll() {
        waiting.removeAll()
        stack.cards.map(\.id).forEach(dismiss)
    }

    /// Called by the card view once SwiftUI knows its natural height.
    func measured(_ id: UUID, height: CGFloat) {
        guard let index = stack.cards.firstIndex(where: { $0.id == id }), stack.cards[index].height != height else { return }
        let first = stack.cards[index].height == 0
        stack.cards[index].height = height
        afterChange()
        guard first else { return }
        // A newcomer unfolds the stack so it is seen, then everything folds again after a pause.
        if !stack.expanded { withAnimation(Self.reflow) { stack.expanded = true } }
        DispatchQueue.main.async { [weak self] in
            guard let self, let i = stack.cards.firstIndex(where: { $0.id == id }) else { return }
            withAnimation(Self.slide) { self.stack.cards[i].presented = true } completion: { [weak self] in
                guard let self, let i = stack.cards.firstIndex(where: { $0.id == id }) else { return }
                withAnimation(.easeOut(duration: 0.15)) { self.stack.cards[i].settled = true }
            }
            scheduleFold()
            afterChange()
        }
    }

    func setHovering(_ hovering: Bool) {
        stack.hovering = hovering
        if hovering { foldTimer?.invalidate() } else { scheduleFold() }
        refreshTimers()
    }

    func expand() {
        guard !stack.expanded else { return }
        withAnimation(Self.reflow) { stack.expanded = true }
        scheduleFold()
        afterChange()
    }

    // MARK: Folding, timers, window size

    private func scheduleFold() {
        foldTimer?.invalidate()
        guard stack.expanded, !stack.hovering else { return }
        foldTimer = Timer.scheduledTimer(withTimeInterval: Self.foldDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.stack.hovering, self.stack.cards.filter({ !$0.leaving }).count > 1 else { return }
                withAnimation(Self.reflow) { self.stack.expanded = false }
                self.afterChange()
            }
        }
    }

    private func afterChange() {
        refreshTimers()
        resizePanel()
    }

    /// Auto-dismiss only counts down while a card is actually readable and the pointer is elsewhere.
    private func refreshTimers() {
        let active = stack.active
        for card in stack.cards {
            let readable = card.presented && !card.leaving && (stack.expanded || active.first?.id == card.id)
            if readable && !stack.hovering { startTimer(card.id) } else { stopTimer(card.id) }
        }
    }

    private func startTimer(_ id: UUID) {
        guard timers[id] == nil, let left = remaining[id] else { return }
        deadlines[id] = Date().addingTimeInterval(left)
        timers[id] = Timer.scheduledTimer(withTimeInterval: left, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(id) }
        }
    }

    private func stopTimer(_ id: UUID) {
        guard let timer = timers.removeValue(forKey: id) else { return }
        timer.invalidate()
        if let deadline = deadlines.removeValue(forKey: id) { remaining[id] = max(1.5, deadline.timeIntervalSinceNow) }
    }

    private func preparePanel() -> ReminderBannerPanel {
        shrinkWork?.cancel()
        if let panel, panel.isVisible {
            setPanelHeight(panel.frame.height, panel)
            return panel
        }
        // A new stack follows the pointer; an existing stack stays on its original display.
        screenID = nil
        let panel = self.panel ?? {
            let p = ReminderBannerPanel()
            let host = NSHostingView(rootView: ReminderBannerStackView(stack: stack, center: self))
            host.sizingOptions = []
            p.contentView = host
            self.panel = p
            return p
        }()
        setPanelHeight(Self.shadowInset * 2, panel)
        return panel
    }

    /// The window is top-anchored and only as tall as the stack, so the desktop under it stays clickable.
    /// It grows at once and shrinks after the reflow, so cards never get clipped mid-animation.
    private func resizePanel() {
        guard let panel else { return }
        let target = stack.contentHeight + Self.shadowInset * 2
        shrinkWork?.cancel()
        if target >= panel.frame.height {
            setPanelHeight(target, panel)
        } else {
            let work = DispatchWorkItem { [weak self] in self?.setPanelHeight(target, panel) }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    private func setPanelHeight(_ height: CGFloat, _ panel: NSPanel) {
        guard let screen = targetScreen() else { return }
        let visibleFrame = screen.visibleFrame
        let width = Self.width + Self.shadowInset * 2
        panel.setFrame(NSRect(x: visibleFrame.maxX - Self.margin + Self.shadowInset - width,
                              y: visibleFrame.maxY - Self.margin + Self.shadowInset - height,
                              width: width, height: height), display: true)
    }

    private func targetScreen() -> NSScreen? {
        // NSScreen instances and their frames can become stale after display reconfiguration.
        // Resolve the stable display ID against the current screen list on every placement.
        let screens = NSScreen.screens
        let displayKey = NSDeviceDescriptionKey("NSScreenNumber")
        let screen = screens.first { ($0.deviceDescription[displayKey] as? NSNumber)?.uint32Value == screenID }
            ?? screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main ?? screens.first
        screenID = (screen?.deviceDescription[displayKey] as? NSNumber)?.uint32Value
        return screen
    }

    #if DEBUG
    /// Developer preview: two sample cards, no calendar or scheduler records.
    func showPreview() {
        show(ReminderBannerItem(source: NSLocalizedString("Asky · 情境提醒", comment: "Reminder preview"), timeLabel: NSLocalizedString("15 分钟后", comment: "Reminder preview"),
                                title: NSLocalizedString("产品讨论会", comment: "Reminder preview"), body: NSLocalizedString("14:30 – 15:30 · 3 号会议室\n上次会议约定要带上新版原型，记得提前准备。", comment: "Reminder preview"),
                                symbol: "calendar",
                                reasons: [NSLocalizedString("日程：产品讨论会 14:30", comment: "Reminder preview"), NSLocalizedString("记忆：上次会议约定带新版原型", comment: "Reminder preview")],
                                actions: [.init(title: NSLocalizedString("稍后提醒", comment: "Reminder preview")),
                                          .init(title: NSLocalizedString("打开日程", comment: "Reminder preview"), prominent: true) { Self.openApp("com.apple.iCal") }],
                                lifetime: nil))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.show(ReminderBannerItem(source: NSLocalizedString("Asky · 出行提醒", comment: "Reminder preview"), timeLabel: NSLocalizedString("现在", comment: "Reminder preview"),
                                          title: NSLocalizedString("该出发了", comment: "Reminder preview"), body: NSLocalizedString("去往望京 SOHO 预计 28 分钟，路况较平时拥堵。", comment: "Reminder preview"),
                                          symbol: "car.fill",
                                          reasons: [NSLocalizedString("日程：望京 SOHO 拜访 10:30", comment: "Reminder preview"), NSLocalizedString("路况：较平时拥堵", comment: "Reminder preview")],
                                          actions: [.init(title: NSLocalizedString("已处理", comment: "Reminder preview")),
                                                    .init(title: NSLocalizedString("查看路线", comment: "Reminder preview"), prominent: true) { Self.openApp("com.apple.Maps") }]))
        }
        // Deterministic preview of the folded → expanded path; keep it open for inspection.
        if CommandLine.arguments.contains("--test-banner-reflow") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                self?.setHovering(true)
                self?.expand()
            }
        }
    }

    private static func openApp(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        Task { try? await ToolService.openLauncherApplication(url) }
    }
    #endif
}

/// Cards in display order: the first one is on top when unfolded and in front when folded.
@MainActor @Observable
final class ReminderBannerStack {
    struct Card: Identifiable {
        let item: ReminderBannerItem
        var height: CGFloat = 0
        var presented = false
        /// The outer shadow appears after the slide so it never trails the glass.
        var settled = false
        var leaving = false
        var frozenY: CGFloat = 0
        var id: UUID { item.id }
    }

    var cards: [Card] = []
    var expanded = true
    var hovering = false
    /// Bumped inside withAnimation so a dismissal reflows the remaining cards in the same transaction.
    var layoutVersion = 0

    var active: [Card] { cards.filter { !$0.leaving && $0.height > 0 } }

    /// Position among the cards that still take part in the layout.
    func rank(of id: UUID) -> Int? { active.firstIndex { $0.id == id } }

    func y(of id: UUID) -> CGFloat {
        if let card = cards.first(where: { $0.id == id }), card.leaving { return card.frozenY }
        guard let rank = rank(of: id) else { return 0 }
        if expanded {
            return active.prefix(rank).reduce(0) { $0 + $1.height + ReminderBannerCenter.gap }
        }
        return CGFloat(min(rank, ReminderBannerCenter.maxPeeking)) * ReminderBannerCenter.peek
    }

    var contentHeight: CGFloat {
        let cards = active
        guard let front = cards.first else { return 0 }
        if expanded { return cards.reduce(0) { $0 + $1.height } + CGFloat(cards.count - 1) * ReminderBannerCenter.gap }
        return front.height + CGFloat(min(cards.count - 1, ReminderBannerCenter.maxPeeking)) * ReminderBannerCenter.peek
    }
}

private struct ReminderBannerStackView: View {
    let stack: ReminderBannerStack
    let center: ReminderBannerCenter

    var body: some View {
        let _ = stack.layoutVersion
        let front = stack.active.first
        ZStack(alignment: .top) {
            // All shadows sit below all glass surfaces and are excluded from every card,
            // so a neighbour's shadow cannot darken translucent content during reflow.
            shadowLayer
            ForEach(stack.cards) { card in
                let rank = stack.rank(of: card.id)
                let behind = !stack.expanded && (rank ?? 0) > 0
                let depth = CGFloat(min(rank ?? 0, ReminderBannerCenter.maxPeeking))
                ReminderBannerCard(item: card.item, contentVisible: !behind,
                                   // Folded cards take the front card's size so only an even sliver shows below it.
                                   foldedHeight: behind ? front?.height : nil,
                                   onDismiss: { center.dismiss(card.id) },
                                   onHeight: { center.measured(card.id, height: $0) })
                    .overlay {
                        // A folded card is just a sliver: clicking it unfolds the stack instead of hitting hidden buttons.
                        if behind {
                            Color.clear.contentShape(Rectangle())
                                .onTapGesture { center.expand() }
                                .accessibilityHidden(true)
                        }
                    }
                    .scaleEffect(behind ? 1 - depth * 0.05 : 1, anchor: .bottom)
                    .offset(x: card.presented || ReminderBannerCenter.reduceMotion ? 0
                            : ReminderBannerCenter.width + ReminderBannerCenter.shadowInset * 2,
                            y: stack.y(of: card.id))
                    .opacity(visible(card, rank: rank) ? 1 : 0)
                    .zIndex(card.leaving ? 1000 : -Double(rank ?? 0))
                    .allowsHitTesting(!card.leaving)
                    .accessibilityHidden(behind)
            }
        }
        .frame(width: ReminderBannerCenter.width)
        .onHover { center.setHovering($0) }
        .padding(ReminderBannerCenter.shadowInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var shadowLayer: some View {
        ZStack(alignment: .top) {
            ForEach(stack.cards) { card in
                surface(for: card, castsShadow: true)
            }
        }
        .frame(width: ReminderBannerCenter.width, height: stack.contentHeight, alignment: .top)
        .mask {
            Rectangle().padding(-ReminderBannerCenter.shadowInset)
                .overlay(alignment: .top) {
                    ZStack(alignment: .top) {
                        ForEach(stack.cards) { card in
                            surface(for: card, castsShadow: false)
                        }
                    }
                    .frame(width: ReminderBannerCenter.width, height: stack.contentHeight, alignment: .top)
                    .blendMode(.destinationOut)
                }
                .compositingGroup()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func surface(for card: ReminderBannerStack.Card, castsShadow: Bool) -> some View {
        let rank = stack.rank(of: card.id)
        let behind = !stack.expanded && (rank ?? 0) > 0
        let depth = CGFloat(min(rank ?? 0, ReminderBannerCenter.maxPeeking))
        let height = behind ? stack.active.first?.height ?? card.height : card.height
        return RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.black)
            .frame(width: ReminderBannerCenter.width, height: height)
            .shadow(color: .black.opacity(behind ? 0.12 : 0.28),
                    radius: castsShadow ? (behind ? 6 : 14) : 0,
                    x: 0, y: castsShadow ? (behind ? 2 : 6) : 0)
            .opacity(castsShadow && !card.settled ? 0 : 1)
            .scaleEffect(behind ? 1 - depth * 0.05 : 1, anchor: .bottom)
            .offset(x: card.presented || ReminderBannerCenter.reduceMotion ? 0
                    : ReminderBannerCenter.width + ReminderBannerCenter.shadowInset * 2,
                    y: stack.y(of: card.id))
            .opacity(visible(card, rank: rank) ? 1 : 0)
    }

    private func visible(_ card: ReminderBannerStack.Card, rank: Int?) -> Bool {
        if ReminderBannerCenter.reduceMotion && !card.presented { return false }
        if card.leaving || stack.expanded { return true }
        return (rank ?? 0) <= ReminderBannerCenter.maxPeeking
    }
}

private final class ReminderBannerPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Placement already anchors the visible card inside the target screen. The transparent
    // shadow inset may extend above visibleFrame; AppKit must not shift that entire canvas.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private struct ReminderBannerCard: View {
    let item: ReminderBannerItem
    let contentVisible: Bool
    let foldedHeight: CGFloat?
    let onDismiss: () -> Void
    let onHeight: (CGFloat) -> Void
    @State private var hovering = false
    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    private var sourceLabel: String {
        if item.source == "Asky" { return "" }
        let prefix = "Asky · "
        return item.source.hasPrefix(prefix) ? String(item.source.dropFirst(prefix.count)) : item.source
    }

    /// Keep punctuation inside sentences, but omit Chinese full stops at the end of card copy.
    private func displayText(_ text: String) -> String {
        text.replacingOccurrences(of: #"。+(?=\s*$)"#, with: "", options: .regularExpression)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                if !sourceLabel.isEmpty {
                    Text(displayText(sourceLabel))
                        .textStyle(.secondary)
                        .foregroundStyle(ThemeColor.kTextSubtle)
                }
                Spacer(minLength: 8)
                Text(displayText(item.timeLabel))
                    .textStyle(.secondary)
                    .foregroundStyle(ThemeColor.kTextSubtle)
                    .opacity(hovering ? 0 : 1)
            }

            HStack(alignment: .top, spacing: 12) {
                Image(mingCute: item.symbol, size: 16)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayText(item.title))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ThemeColor.kText)
                    Text(displayText(item.body))
                        .textStyle(.resultPrimary)
                        .foregroundStyle(ThemeColor.kTextSubtle)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(4)
                }
                Spacer(minLength: 0)
            }

            if !item.actions.isEmpty {
                HStack(spacing: 8) {
                    Spacer()
                    ForEach(Array(item.actions.enumerated()), id: \.offset) { _, action in
                        Button {
                            action.handler()
                            if action.dismissesCard { onDismiss() }
                        } label: {
                            Text(displayText(action.title)).frame(minWidth: 56)
                        }
                        .buttonStyle(BannerButtonStyle(prominent: action.prominent))
                    }
                }
            }
        }
        .padding(16)
        .frame(width: ReminderBannerCenter.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
        .opacity(contentVisible ? 1 : 0)
        .frame(height: foldedHeight, alignment: .top)
        .clipped()
        .nativeGlassBackground(in: shape)
        .overlay(alignment: .topTrailing) {
            if hovering && contentVisible {
                Button(action: onDismiss) {
                    Image(mingCute: "xmark", size: 10)
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(ThemeColor.kTextSubtle)
                .background(ThemeColor.kBackgroundNeutral, in: Circle())
                .padding(10)
                .accessibilityLabel(Text("关闭"))
                .transition(.opacity)
            }
        }
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .accessibilityElement(children: .contain)
    }
}

/// System bordered buttons dim in non-key windows; the banner never becomes key, so it draws its own.
private struct BannerButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(ThemeColor.kText))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(ThemeColor.kBackgroundNeutral),
                        in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
