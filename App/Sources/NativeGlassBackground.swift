import AppKit
import SwiftUI
import Theme

/// Debug previews exercise the pre-26 appearance without changing the host OS.
@MainActor
enum SurfaceCompatibility {
    @MainActor @Observable final class State {
        var liquidGlassEnabled = true
    }
    static let state = State()

    static var useMacOS14Compatibility: Bool {
        #if DEBUG
        if CommandLine.arguments.contains("--preview-macos14") { return true }
        #endif
        if #available(macOS 15, *) { return false }
        return true
    }

    static var supportsLiquidGlass: Bool {
        if useMacOS14Compatibility { return false }
        #if DEBUG
        if CommandLine.arguments.contains("--preview-legacy-material") { return false }
        #endif
        if #available(macOS 26, *) { return true }
        return false
    }

    /// Pre-26 systems, or Liquid Glass turned off in settings, use blur plus a border.
    static var useLegacyMaterial: Bool {
        !supportsLiquidGlass || !state.liquidGlassEnabled
    }
}

/// One system-managed frosted surface, with an opaque accessibility fallback.
private struct NativeGlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    var interactive: Bool
    var clear: Bool
    var glassOpacity: Double
    var forceOpaque: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    private var opaque: Bool { forceOpaque || reduceTransparency || contrast == .increased }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial {
            let glass: Glass = clear ? .clear : .regular
            content
                .background {
                    if opaque {
                        shape.fill(ThemeColor.kBackground.color(for: scheme, opaque: true))
                    } else if glassOpacity < 1 {
                        shape.fill(.clear)
                            .glassEffect(interactive ? glass.interactive() : glass, in: shape)
                            .opacity(glassOpacity)
                    }
                }
                .glassEffect(opaque || glassOpacity < 1 ? .identity : interactive ? glass.interactive() : glass, in: shape)
                .overlay {
                    if opaque {
                        shape.strokeBorder(ThemeColor.kText.color(for: scheme).opacity(0.55), lineWidth: 1)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        } else {
            content
                .background {
                    ZStack {
                        if !opaque { LegacyBackdropBlur() }
                        shape.fill(ThemeColor.kBackground.color(for: scheme, opaque: opaque))
                    }
                    .clipShape(shape)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .overlay {
                    shape.strokeBorder(opaque ? ThemeColor.kText.color(for: scheme).opacity(0.55)
                                       : ThemeColor.kBorder.color(for: scheme), lineWidth: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
    }
}

extension View {
    func nativeGlassBackground<S: InsettableShape>(in shape: S, interactive: Bool = false,
                                                   clear: Bool = false, glassOpacity: Double = 1, forceOpaque: Bool = false) -> some View {
        modifier(NativeGlassBackground(shape: shape, interactive: interactive, clear: clear, glassOpacity: glassOpacity, forceOpaque: forceOpaque))
    }
}

/// AppKit blurs the live content behind the window; its public API owns the radius.
private struct LegacyBackdropBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct CompatibleGlassButtonStyle: ViewModifier {
    var prominent: Bool
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let tint = SettingsPalette.monochromeTint(scheme)
        if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial {
            if prominent { content.buttonStyle(.glassProminent).tint(tint) }
            else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent).tint(tint) }
            else { content.buttonStyle(.bordered) }
        }
    }
}

extension View {
    func compatibleGlassButtonStyle(prominent: Bool = false) -> some View {
        modifier(CompatibleGlassButtonStyle(prominent: prominent))
    }
}

private struct SettingsVersionBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial {
            content
        } else {
            content
                .scrollContentBackground(.hidden)
                .nativeGlassBackground(in: Rectangle())
        }
    }
}

extension View {
    func settingsVersionBackground() -> some View {
        modifier(SettingsVersionBackground())
    }
}

/// Keeps title-bar gaps draggable on systems before WindowDragGesture.
extension View {
    @ViewBuilder
    func compatibleWindowDrag() -> some View {
        if #available(macOS 15, *), !SurfaceCompatibility.useMacOS14Compatibility {
            self.gesture(WindowDragGesture()).allowsWindowActivationEvents()
        } else {
            self.background(WindowDragArea())
        }
    }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
