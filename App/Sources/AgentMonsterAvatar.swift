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

struct AgentMonsterAvatar: View {
    var color: AgentAvatarColor = .blue

    var body: some View {
        Image("AgentAvatar")
            .resizable()
            .scaledToFit()
            .hueRotation(.degrees(color.hue))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The avatar and menu share one native glass container and identity.
struct AgentAvatarPicker: View {
    @Binding var color: AgentAvatarColor
    @State private var showing = false
    @State private var pressed = false
    @State private var focused = AgentAvatarColor.blue
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
                        .frame(width: showing ? 184 : 36, height: showing ? 252 : 36)
                        .glassEffect(showing ? .regular.interactive() : .clear,
                                     in: RoundedRectangle(cornerRadius: 18))
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
                        trigger.nativeGlassBackground(in: Circle(), clear: true)
                            .glassPointerFeedback(pressed: pressed, in: Circle())
                    }
                }
            }
        }
        .frame(width: showing ? 184 : 36, height: showing ? 252 : 36, alignment: .topLeading)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.58), value: showing)
        .onChange(of: showing) { _, value in value ? startMonitoring() : stopMonitoring() }
        .onDisappear { showing = false; stopMonitoring() }
    }

    private var trigger: some View {
        Button {
            focused = color
            showing = true
        } label: {
            AgentMonsterAvatar(color: color)
                .frame(width: 30, height: 30)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(GlassPressObserverStyle(pressed: $pressed))
        .focusable(false)
        .accessibilityLabel(NSLocalizedString("头像颜色", comment: ""))
        .accessibilityValue(NSLocalizedString(color.title, comment: ""))
    }

    private var menu: some View {
        AvatarColorMenu(selected: color, focused: focused) { selected in
            color = selected
            showing = false
        }
        .background(AvatarMenuReader(anchor: menuAnchor).allowsHitTesting(false))
    }

    private func startMonitoring() {
        stopMonitoring()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { event in
            let consumed = MainActor.assumeIsolated {
                if event.type == .keyDown {
                    switch event.keyCode {
                    case 53: showing = false; return true
                    case 125, 126:
                        let colors = AgentAvatarColor.allCases
                        let index = colors.firstIndex(of: focused) ?? 0
                        focused = colors[(index + (event.keyCode == 125 ? 1 : colors.count - 1)) % colors.count]
                        return true
                    case 36, 76: color = focused; showing = false; return true
                    default: showing = false; return false
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

private struct AvatarColorMenu: View {
    let selected: AgentAvatarColor
    let focused: AgentAvatarColor
    let choose: (AgentAvatarColor) -> Void
    @State private var hovered: AgentAvatarColor?

    var body: some View {
        VStack(spacing: 2) {
            ForEach(AgentAvatarColor.allCases, id: \.self) { color in
                AvatarColorRow(color: color, selected: color == selected, focused: color == (hovered ?? focused)) { choose(color) }
                    .onHover { inside in hovered = inside ? color : nil }
            }
        }
        .padding(8)
        .frame(width: 184, height: 252)
    }
}

private struct AvatarColorRow: View {
    let color: AgentAvatarColor
    let selected: Bool
    let focused: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AgentMonsterAvatar(color: color).frame(width: 34, height: 34)
                Text(NSLocalizedString(color.title, comment: "")).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)) }
            }
            .foregroundStyle(ThemeColor.kText.color(for: scheme))
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background {
                if focused {
                    RoundedRectangle(cornerRadius: 11).fill(ThemeColor.kInteractionHover.color(for: scheme))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(NSLocalizedString(color.title, comment: ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
