import AppKit
import SwiftUI
import Theme

enum AgentAvatarColor: String, CaseIterable {
    case blue, yellow, purple, green, pink

    var title: String {
        switch self {
        case .blue: "蓝色"
        case .yellow: "黄色"
        case .purple: "紫色"
        case .green: "绿色"
        case .pink: "粉色"
        }
    }

    var hue: Double {
        switch self {
        case .blue: 0
        case .yellow: -170
        case .purple: 55
        case .green: -100
        case .pink: 115
        }
    }

    var tint: Color {
        let rgb: UInt32 = switch self {
        case .blue: 0x73BFFF
        case .yellow: 0xF1CB62
        case .purple: 0xB69AF8
        case .green: 0x87CC8A
        case .pink: 0xECA4C4
        }
        return Color(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255,
                     green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255, opacity: 1)
    }

    /// A hint of the pet hue sits over the neutral user-message surface.
    func userBubbleTint(for scheme: ColorScheme) -> Color {
        tint.opacity(scheme == .dark ? 0.12 : 0.08)
    }
}

enum AgentAvatarShape: String, CaseIterable {
    case monster, round
    case gear = "square" // Retain the saved selection from the replaced square shape.
    case triangle, ghost

    var title: String {
        switch self {
        case .monster: "小怪物"
        case .round: "正圆"
        case .gear: "圆齿"
        case .triangle: "软糖"
        case .ghost: "幽灵"
        }
    }

    var bodyAsset: String {
        switch self {
        case .monster: "AgentAvatarBody"
        case .round: "AgentAvatarRound"
        case .gear: "AgentAvatarGear"
        case .triangle: "AgentAvatarTriangle"
        case .ghost: "AgentAvatarGhost"
        }
    }

    /// Match visible body sizes, accounting for each sprite's transparent margins.
    var bodyScale: CGFloat {
        switch self {
        case .monster: 1
        case .round: 1.06
        case .gear: 0.96
        case .triangle: 0.98
        case .ghost: 1.06
        }
    }

}

enum AgentAvatarExpression: String, CaseIterable {
    case smile, sunglasses, wink, sleepy

    var title: String {
        switch self {
        case .smile: "微笑"
        case .sunglasses: "墨镜"
        case .wink: "眨眼"
        case .sleepy: "困困"
        }
    }
}

/// Every silhouette shares the original soft material; expressions remain a separate overlay.
struct AgentMonsterAvatar: View {
    var color: AgentAvatarColor = .blue
    var shape: AgentAvatarShape = .monster
    var expression: AgentAvatarExpression = .smile

    var body: some View {
        Group {
            if shape == .monster {
                if expression == .smile {
                    Image("AgentAvatar").resizable().scaledToFit()
                        .hueRotation(.degrees(color.hue))
                } else {
                    Image("AgentAvatarBody").resizable().scaledToFit()
                        .mask { Image("AgentAvatar").resizable().scaledToFit() }
                        .hueRotation(.degrees(color.hue))
                        .overlay { AvatarFace(expression: expression, mouthY: 58) }
                }
            } else {
                Image(shape.bodyAsset).resizable().scaledToFit()
                    .scaleEffect(shape.bodyScale)
                    .hueRotation(.degrees(color.hue))
                    .overlay { AvatarFace(expression: expression, mouthY: 58) }

            }
        }
        .aspectRatio(1, contentMode: .fit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct AvatarFace: View {
    let expression: AgentAvatarExpression
    var mouthY: CGFloat = 64

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 100, y: size.height / 100)
            let ink = Color(red: 0.08, green: 0.16, blue: 0.29)
            func stroke(_ points: [CGPoint], width: CGFloat = 3.4) {
                var path = Path()
                path.addLines(points)
                context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            func eye(_ x: CGFloat) {
                context.fill(Path(ellipseIn: CGRect(x: x - 4, y: 44, width: 8, height: 12)),
                             with: .linearGradient(Gradient(colors: [Color(red: 0.15, green: 0.24, blue: 0.39), ink]),
                                                   startPoint: CGPoint(x: x - 4, y: 44), endPoint: CGPoint(x: x + 4, y: 56)))
            }
            switch expression {
            case .smile:
                eye(35); eye(65)
            case .wink:
                eye(35)
                stroke([CGPoint(x: 67, y: 47), CGPoint(x: 60, y: 51), CGPoint(x: 67, y: 54)])
            case .sleepy:
                for x: CGFloat in [35, 65] {
                    var lid = Path()
                    lid.move(to: CGPoint(x: x - 6, y: 48))
                    lid.addQuadCurve(to: CGPoint(x: x + 6, y: 48), control: CGPoint(x: x, y: 55))
                    context.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
                }
            case .sunglasses:
                for x: CGFloat in [22, 54] {
                    context.fill(Path(roundedRect: CGRect(x: x, y: 40, width: 24, height: 20), cornerRadius: 7), with: .color(ink))
                    var shine = Path()
                    shine.move(to: CGPoint(x: x + 6, y: 44))
                    shine.addLine(to: CGPoint(x: x + 15, y: 44))
                    context.stroke(shine, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                stroke([CGPoint(x: 18, y: 42), CGPoint(x: 24, y: 44)])
                stroke([CGPoint(x: 46, y: 46), CGPoint(x: 54, y: 46)])
                stroke([CGPoint(x: 76, y: 44), CGPoint(x: 82, y: 42)])
            }
            if expression == .sleepy {
                context.fill(Path(ellipseIn: CGRect(x: 47, y: mouthY, width: 6, height: 8)), with: .color(ink))
            } else {
                var smile = Path()
                smile.move(to: CGPoint(x: 41, y: mouthY))
                smile.addQuadCurve(to: CGPoint(x: 59, y: mouthY), control: CGPoint(x: 50, y: mouthY + 10))
                context.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
            }
        }
    }
}

/// The avatar and menu share one native glass container and identity.
struct AgentAvatarPicker: View {
    @Binding var color: AgentAvatarColor
    @Binding var shape: AgentAvatarShape
    @Binding var expression: AgentAvatarExpression
    @State private var showing = false
    @State private var pressed = false
    @State private var focusedRow = 0
    @State private var focusedIndex = 0
    @State private var keyboardFocus = false
    @State private var monitor: Any?
    @State private var globalMonitor: Any?
    @State private var menuAnchor = AvatarMenuAnchor()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial,
               !reduceTransparency, contrast != .increased {
                GlassEffectContainer {
                    // Keep the same glass surface alive as its frame contracts.
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.clear)
                        .frame(width: showing ? 260 : 36, height: showing ? 340 : 36)
                        .glassEffect(showing ? .regular.interactive() : .clear,
                                     in: RoundedRectangle(cornerRadius: 18))
                        .opacity(showing ? 1 : 0.85)
                        .overlay(alignment: .topLeading) {
                            if showing { menu } else { trigger }
                        }
                        // Mark the overlay as foreground content so the native
                        // glass does not refract the avatar and menu themselves.
                        .glassEffect(.identity)
                        .glassPointerFeedback(pressed: pressed, in: RoundedRectangle(cornerRadius: 18))
                }
            } else {
                ZStack(alignment: .topLeading) {
                    if showing {
                        menu.nativeGlassBackground(in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        trigger.nativeGlassBackground(in: Circle(), clear: true, glassOpacity: 0.85)
                            .glassPointerFeedback(pressed: pressed, in: Circle())
                    }
                }
            }
        }
        .frame(width: showing ? 260 : 36, height: showing ? 340 : 36, alignment: .topLeading)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.58), value: showing)
        .onChange(of: showing) { _, value in value ? startMonitoring() : stopMonitoring() }
        .onDisappear { showing = false; stopMonitoring() }
    }

    private var trigger: some View {
        Button {
            focusedRow = 0
            focusedIndex = AgentAvatarShape.allCases.firstIndex(of: shape) ?? 0
            keyboardFocus = false
            showing = true
        } label: {
            AgentMonsterAvatar(color: color, shape: shape, expression: expression)
                .frame(width: 30, height: 30)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(GlassPressObserverStyle(pressed: $pressed))
        .focusable(false)
        .accessibilityLabel(NSLocalizedString("自定义头像", comment: ""))
        .accessibilityValue([shape.title, expression.title, color.title].map { NSLocalizedString($0, comment: "") }.joined(separator: "，"))
    }

    private var menu: some View {
        AvatarCustomizationMenu(color: $color, shape: $shape, expression: $expression,
                                focusedRow: focusedRow, focusedIndex: focusedIndex, keyboardFocus: keyboardFocus) { row, index in
            focusedRow = row
            focusedIndex = index
            keyboardFocus = false
        }
        .background(AvatarMenuReader(anchor: menuAnchor).allowsHitTesting(false))
    }

    private func startMonitoring() {
        stopMonitoring()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { event in
            let consumed = MainActor.assumeIsolated {
                if event.type == .keyDown {
                    guard let view = menuAnchor.view, event.window === view.window else {
                        showing = false
                        return false
                    }
                    if event.modifierFlags.contains(.command) {
                        showing = false
                        return false
                    }
                    switch event.keyCode {
                    case 53: showing = false; return true
                    case 125, 126, 48:
                        let backwards = event.keyCode == 126 || (event.keyCode == 48 && event.modifierFlags.contains(.shift))
                        focusedRow = (focusedRow + (backwards ? 2 : 1)) % 3
                        focusedIndex = selectedIndex(in: focusedRow)
                        keyboardFocus = true
                        return true
                    case 123, 124:
                        let count = focusedRow == 0 ? AgentAvatarShape.allCases.count
                            : focusedRow == 1 ? AgentAvatarExpression.allCases.count : AgentAvatarColor.allCases.count
                        focusedIndex = (focusedIndex + (event.keyCode == 124 ? 1 : count - 1)) % count
                        keyboardFocus = true
                        return true
                    case 36, 76, 49:
                        switch focusedRow {
                        case 0: shape = AgentAvatarShape.allCases[focusedIndex]
                        case 1: expression = AgentAvatarExpression.allCases[focusedIndex]
                        default: color = AgentAvatarColor.allCases[focusedIndex]
                        }
                        return true
                    default: return true
                    }
                }
                if let view = menuAnchor.view, event.window === view.window,
                   view.bounds.contains(view.convert(event.locationInWindow, from: nil)) { return false }
                showing = false
                return true
            }
            return consumed ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in showing = false }
        }
    }

    private func selectedIndex(in row: Int) -> Int {
        switch row {
        case 0: AgentAvatarShape.allCases.firstIndex(of: shape) ?? 0
        case 1: AgentAvatarExpression.allCases.firstIndex(of: expression) ?? 0
        default: AgentAvatarColor.allCases.firstIndex(of: color) ?? 0
        }
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        monitor = nil
        globalMonitor = nil
    }
}

@MainActor private final class AvatarMenuAnchor {
    weak var view: NSView?
}

private struct AvatarMenuReader: NSViewRepresentable {
    let anchor: AvatarMenuAnchor
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}

private struct AvatarCustomizationMenu: View {
    @Binding var color: AgentAvatarColor
    @Binding var shape: AgentAvatarShape
    @Binding var expression: AgentAvatarExpression
    let focusedRow: Int
    let focusedIndex: Int
    let keyboardFocus: Bool
    let didChoose: (Int, Int) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 14) {
            AgentMonsterAvatar(color: color, shape: shape, expression: expression)
                .frame(width: 80, height: 80)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            section("造型") {
                ForEach(Array(AgentAvatarShape.allCases.enumerated()), id: \.element) { index, item in
                    option(title: item.title, selected: shape == item, row: 0, index: index) {
                        shape = item
                    } content: {
                        AgentMonsterAvatar(color: color, shape: item, expression: expression).frame(width: 36, height: 36)
                    }
                }
            }
            section("表情") {
                ForEach(Array(AgentAvatarExpression.allCases.enumerated()), id: \.element) { index, item in
                    option(title: item.title, selected: expression == item, row: 1, index: index) {
                        expression = item
                    } content: {
                        AgentMonsterAvatar(color: color, shape: shape, expression: item)
                            .frame(width: 36, height: 36)
                    }
                }
            }
            section("颜色") {
                ForEach(Array(AgentAvatarColor.allCases.enumerated()), id: \.element) { index, item in
                    option(title: item.title, selected: color == item, row: 2, index: index) {
                        color = item
                    } content: {
                        Circle().fill(item.tint).frame(width: 24, height: 24)
                            .overlay {
                                if color == item {
                                    Image(mingCute: "checkmark", size: 13).foregroundStyle(Color(white: 0.15))
                                }
                            }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 260, height: 340, alignment: .top)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString(title, comment: ""))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ThemeColor.kTextSubtle.color(for: scheme))
            HStack(spacing: 6, content: content)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func option<Content: View>(title: String, selected: Bool, row: Int, index: Int,
                                       action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button {
            action()
            didChoose(row, index)
        } label: {
            content()
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 11).fill(selected ? ThemeColor.kInteractionHover.color(for: scheme) : .clear))
                .overlay {
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(ThemeColor.kText.color(for: scheme).opacity(selected ? 0.65 : 0), lineWidth: 1.5)
                    if keyboardFocus && focusedRow == row && focusedIndex == index {
                        RoundedRectangle(cornerRadius: 13).strokeBorder(color.tint, lineWidth: 2).padding(-3)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(NSLocalizedString(title, comment: ""))
        .accessibilityLabel(NSLocalizedString(title, comment: ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
