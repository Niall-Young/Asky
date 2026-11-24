import SwiftUI

enum ChatReactionBadgeLayout {
    static let emojiSize: CGFloat = 18
    static let slotSize: CGFloat = 24
    static let verticalOverhang: CGFloat = 12
    static let horizontalOverhang: CGFloat = 4
}

/// Container-less emoji reaction hanging directly on a chat bubble corner,
/// with a dedicated choreographed swap animation when changing emojis.
struct ChatReactionBadge: View {
    let emoji: String?
    let side: ChatBubbleSide
    let accentColor: Color
    var accessibilityLabelFormat: String
    var helpText: String? = nil
    var accessibilityID: String? = nil
    var onTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var displayedEmoji: String?
    @State private var arrival: Arrival
    @State private var outgoing: OutgoingReaction?
    @State private var burstID: Int?
    @State private var generation = 0
    @State private var hovered = false
    @State private var cleanupTask: Task<Void, Never>?

    private enum ArrivalKind: Equatable {
        case initial
        case appear
        case swap
    }

    private struct Arrival: Equatable {
        let id: Int
        let kind: ArrivalKind
    }

    private enum OutgoingKind: Equatable {
        case swap
        case remove
    }

    private struct OutgoingReaction: Equatable {
        let id: Int
        let emoji: String
        let kind: OutgoingKind
    }

    init(
        emoji: String?,
        side: ChatBubbleSide,
        accentColor: Color,
        accessibilityLabelFormat: String,
        helpText: String? = nil,
        accessibilityID: String? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.emoji = emoji
        self.side = side
        self.accentColor = accentColor
        self.accessibilityLabelFormat = accessibilityLabelFormat
        self.helpText = helpText
        self.accessibilityID = accessibilityID
        self.onTap = onTap
        _displayedEmoji = State(initialValue: emoji)
        _arrival = State(initialValue: Arrival(id: 0, kind: .initial))
    }

    private var hasVisibleContent: Bool {
        displayedEmoji != nil || outgoing != nil || burstID != nil
    }

    private var horizontalOffset: CGFloat {
        side == .trailing ? ChatReactionBadgeLayout.horizontalOverhang : -ChatReactionBadgeLayout.horizontalOverhang
    }

    var body: some View {
        ZStack {
            if let burstID, !reduceMotion {
                ReactionSwapBurstView(accentColor: accentColor)
                    .id(burstID)
                    .allowsHitTesting(false)
            }

            if let outgoing {
                OutgoingReactionView(
                    emoji: outgoing.emoji,
                    kind: outgoing.kind,
                    side: side,
                    scheme: scheme,
                    reduceMotion: reduceMotion
                )
                .id(outgoing.id)
                .allowsHitTesting(false)
            }

            if let current = displayedEmoji {
                currentEmojiView(current)
            }
        }
        .frame(
            width: hasVisibleContent ? ChatReactionBadgeLayout.slotSize : 0,
            height: hasVisibleContent ? ChatReactionBadgeLayout.slotSize : 0
        )
        .offset(x: horizontalOffset, y: ChatReactionBadgeLayout.verticalOverhang)
        .allowsHitTesting(onTap != nil && displayedEmoji != nil)
        .onChange(of: emoji) { oldValue, newValue in
            handleEmojiChange(from: oldValue, to: newValue)
        }
        .onDisappear {
            cleanupTask?.cancel()
            cleanupTask = nil
        }
    }

    @ViewBuilder
    private func currentEmojiView(_ current: String) -> some View {
        let glyph = IncomingReactionView(
            emoji: current,
            kind: arrival.kind,
            side: side,
            scheme: scheme,
            reduceMotion: reduceMotion
        )
        .id(arrival.id)

        if let onTap {
            Button(action: onTap) {
                glyph
                    .frame(width: ChatReactionBadgeLayout.slotSize, height: ChatReactionBadgeLayout.slotSize)
                    .scaleEffect(!reduceMotion && hovered ? 1.12 : 1)
                    .contentShape(Circle())
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            }
            .buttonStyle(ReactionBadgePressStyle())
            .onHover { hovered = $0 }
            .actionArrowCursor()
            .modifier(OptionalHelpModifier(text: helpText))
            .accessibilityLabel(String(format: accessibilityLabelFormat, current))
            .modifier(OptionalAccessibilityIDModifier(id: accessibilityID))
        } else {
            glyph
                .frame(width: ChatReactionBadgeLayout.slotSize, height: ChatReactionBadgeLayout.slotSize)
                .accessibilityLabel(String(format: accessibilityLabelFormat, current))
                .modifier(OptionalAccessibilityIDModifier(id: accessibilityID))
        }
    }

    private func handleEmojiChange(from oldValue: String?, to newValue: String?) {
        guard oldValue != newValue else { return }
        cleanupTask?.cancel()
        generation += 1
        let currentGen = generation

        switch (oldValue, newValue) {
        case let (old?, new?):
            // Dedicated swap animation: peel old emoji away, pop new emoji in with accent burst.
            outgoing = OutgoingReaction(id: currentGen, emoji: old, kind: .swap)
            displayedEmoji = new
            arrival = Arrival(id: currentGen, kind: .swap)
            burstID = reduceMotion ? nil : currentGen
            scheduleCleanup(for: currentGen, delayMilliseconds: 420)

        case (nil, let new?):
            // First sticker landing.
            outgoing = nil
            burstID = nil
            displayedEmoji = new
            arrival = Arrival(id: currentGen, kind: .appear)

        case (let old?, nil):
            // Crisp sticker peel-out on removal.
            hovered = false
            burstID = nil
            outgoing = OutgoingReaction(id: currentGen, emoji: old, kind: .remove)
            displayedEmoji = nil
            scheduleCleanup(for: currentGen, delayMilliseconds: 220)

        case (nil, nil):
            break
        }
    }

    private func scheduleCleanup(for targetGen: Int, delayMilliseconds: Int) {
        cleanupTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(delayMilliseconds))
            } catch {
                return
            }
            guard !Task.isCancelled, generation == targetGen else { return }
            outgoing = nil
            burstID = nil
        }
    }

    private struct IncomingReactionView: View {
        let emoji: String
        let kind: ArrivalKind
        let side: ChatBubbleSide
        let scheme: ColorScheme
        let reduceMotion: Bool

        @State private var landed: Bool
        @State private var revealed: Bool

        init(emoji: String, kind: ArrivalKind, side: ChatBubbleSide, scheme: ColorScheme, reduceMotion: Bool) {
            self.emoji = emoji
            self.kind = kind
            self.side = side
            self.scheme = scheme
            self.reduceMotion = reduceMotion
            let startsAtRest = kind == .initial
            _landed = State(initialValue: startsAtRest)
            _revealed = State(initialValue: startsAtRest)
        }

        private var initialScale: CGFloat {
            switch kind {
            case .initial: 1
            case .appear: 0.68
            case .swap: 0.46
            }
        }

        private var initialOffsetY: CGFloat {
            switch kind {
            case .initial: 0
            case .appear: -4
            case .swap: 11
            }
        }

        private var initialRotation: Double {
            let sign: Double = side == .trailing ? 1 : -1
            switch kind {
            case .initial: return 0
            case .appear: return -10 * sign
            case .swap: return 24 * sign
            }
        }

        private var initialBlur: CGFloat {
            kind == .swap ? 1.8 : 0
        }

        var body: some View {
            Text(emoji)
                .font(.system(size: ChatReactionBadgeLayout.emojiSize))
                .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.14), radius: 2, x: 0, y: 1)
                .scaleEffect(!reduceMotion && !landed ? initialScale : 1)
                .offset(y: !reduceMotion && !landed ? initialOffsetY : 0)
                .rotationEffect(.degrees(!reduceMotion && !landed ? initialRotation : 0))
                .blur(radius: !reduceMotion && !revealed ? initialBlur : 0)
                .opacity(revealed ? 1 : 0)
                .task {
                    guard kind != .initial else { return }
                    let beatMs = kind == .swap ? 24 : 16
                    do {
                        try await Task.sleep(for: .milliseconds(beatMs))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    if reduceMotion {
                        withAnimation(.easeOut(duration: 0.15)) {
                            revealed = true
                            landed = true
                        }
                    } else if kind == .swap {
                        withAnimation(.easeOut(duration: 0.13)) {
                            revealed = true
                        }
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.46)) {
                            landed = true
                        }
                    } else {
                        withAnimation(.easeOut(duration: 0.12)) {
                            revealed = true
                        }
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.58)) {
                            landed = true
                        }
                    }
                }
        }
    }

    private struct OutgoingReactionView: View {
        let emoji: String
        let kind: OutgoingKind
        let side: ChatBubbleSide
        let scheme: ColorScheme
        let reduceMotion: Bool

        @State private var dismissed = false

        private var exitOffsetX: CGFloat {
            guard kind == .swap else { return 0 }
            return side == .trailing ? 7 : -7
        }

        private var exitOffsetY: CGFloat {
            kind == .swap ? -14 : 4
        }

        private var exitScale: CGFloat {
            kind == .swap ? 0.45 : 0.62
        }

        private var exitRotation: Double {
            guard kind == .swap else { return 0 }
            return side == .trailing ? -26 : 26
        }

        private var exitBlur: CGFloat {
            kind == .swap ? 2.0 : 0
        }

        var body: some View {
            Text(emoji)
                .font(.system(size: ChatReactionBadgeLayout.emojiSize))
                .shadow(color: .black.opacity(scheme == .dark ? 0.30 : 0.14), radius: 2, x: 0, y: 1)
                .scaleEffect(!reduceMotion && dismissed ? exitScale : 1)
                .offset(
                    x: !reduceMotion && dismissed ? exitOffsetX : 0,
                    y: !reduceMotion && dismissed ? exitOffsetY : 0
                )
                .rotationEffect(.degrees(!reduceMotion && dismissed ? exitRotation : 0))
                .blur(radius: !reduceMotion && dismissed ? exitBlur : 0)
                .opacity(dismissed ? 0 : 1)
                .task {
                    do {
                        try await Task.sleep(for: .milliseconds(16))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    let duration = reduceMotion ? 0.14 : (kind == .swap ? 0.18 : 0.15)
                    withAnimation(.easeOut(duration: duration)) {
                        dismissed = true
                    }
                }
        }
    }
}

private struct ReactionSwapBurstView: View {
    let accentColor: Color
    @State private var startDate: Date?

    private static let duration: TimeInterval = 0.34
    private static let beatDelay: TimeInterval = 0.024

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: startDate == nil)) { context in
            let progress = burstProgress(at: context.date)
            ReactionSwapBurstCanvas(progress: progress, accentColor: accentColor)
        }
        .frame(width: 52, height: 52)
        .onAppear {
            startDate = Date()
        }
    }

    private func burstProgress(at now: Date) -> CGFloat {
        guard let startDate else { return 0 }
        let elapsed = now.timeIntervalSince(startDate) - Self.beatDelay
        guard elapsed > 0 else { return 0 }
        return CGFloat(min(1, elapsed / Self.duration))
    }
}

private struct ReactionSwapBurstCanvas: View {
    let progress: CGFloat
    let accentColor: Color

    var body: some View {
        let t = max(0, min(1, progress))
        let eased = 1 - pow(1 - t, 3)

        let ringFadeIn = min(1, t / 0.18)
        let ringFadeOut = max(0, 1 - max(0, t - 0.18) / 0.82)
        let ringOpacity = (t <= 0.005 || t >= 0.995) ? 0 : Double(ringFadeIn * ringFadeOut) * 0.58

        let sparkFadeIn = min(1, t / 0.14)
        let sparkFadeOut = max(0, 1 - max(0, t - 0.14) / 0.86)
        let sparkOpacity = (t <= 0.005 || t >= 0.995) ? 0 : Double(sparkFadeIn * sparkFadeOut) * 0.92

        let ringDiameter = 14 + 22 * eased
        let ringWidth = max(0.5, 2.2 * (1 - eased * 0.76))

        ZStack {
            Circle()
                .strokeBorder(accentColor.opacity(ringOpacity), lineWidth: ringWidth)
                .frame(width: ringDiameter, height: ringDiameter)

            ForEach(0..<6, id: \.self) { index in
                let angle = (Double(index) * 60 + 18) * .pi / 180
                let reach: CGFloat = (index.isMultiple(of: 2) ? 14.5 : 11.5) * eased + 7.0
                let dotDiameter: CGFloat = (index.isMultiple(of: 2) ? 3.4 : 2.5) * max(0.22, 1 - t * 0.78)
                Circle()
                    .fill(index.isMultiple(of: 2) ? accentColor : accentColor.opacity(0.82))
                    .frame(width: dotDiameter, height: dotDiameter)
                    .opacity(sparkOpacity)
                    .offset(
                        x: CGFloat(cos(angle)) * reach,
                        y: CGFloat(sin(angle)) * reach
                    )
            }
        }
    }
}

private struct ReactionBadgePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct OptionalHelpModifier: ViewModifier {
    let text: String?
    func body(content: Content) -> some View {
        if let text { content.help(text) } else { content }
    }
}

private struct OptionalAccessibilityIDModifier: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id { content.accessibilityIdentifier(id) } else { content }
    }
}
