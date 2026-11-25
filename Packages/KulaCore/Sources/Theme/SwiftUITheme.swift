import SwiftUI

extension RGBA {
    public var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

/// Persistent full-access status shares the unified warning/alert tint (`#AD690B` light, `#E8AD52` dark).
public struct FullAccessTint: ShapeStyle {
    public init() {}

    public func resolve(in environment: EnvironmentValues) -> Color {
        ThemeColor.kWarning.resolve(in: environment)
    }
}

/// Theme bridge for SwiftUI: resolves semantic tokens against the current color scheme.
public struct ThemeColor: ShapeStyle {
    public let native: String
    public init(_ native: String) { self.native = native }

    public func resolve(in environment: EnvironmentValues) -> Color {
        color(for: environment.colorScheme)
    }

    /// Color-valued APIs such as native glass tint use the same semantic mapping as ShapeStyle.
    public func color(for colorScheme: ColorScheme, opaque: Bool = false) -> Color {
        let appearance: Appearance = colorScheme == .dark ? .dark : .light
        guard var value = SemanticColors.color(native: native, appearance) else { return .primary }
        if opaque { value.alpha = 1 }
        return value.color
    }
}

extension ShapeStyle where Self == ThemeColor {
    public static var kText: ThemeColor { ThemeColor("text") }
    public static var kTextSubtle: ThemeColor { ThemeColor("textSubtle") }
    public static var kTextSubtlest: ThemeColor { ThemeColor("textSubtlest") }
    public static var kWarning: ThemeColor { ThemeColor("textWarning") }
    public static var kTextNegative: ThemeColor { ThemeColor("textNegative") }
    public static var kTextPositive: ThemeColor { ThemeColor("textPositive") }
    public static var kIcon: ThemeColor { ThemeColor("icon") }
    public static var kIconSubtle: ThemeColor { ThemeColor("iconSubtle") }
    public static var kBorder: ThemeColor { ThemeColor("border") }
    public static var kBorderIntense: ThemeColor { ThemeColor("borderIntense") }
    public static var kBorderFocused: ThemeColor { ThemeColor("borderFocused") }
    public static var kBackground: ThemeColor { ThemeColor("background") }
    public static var kBackgroundSelected: ThemeColor { ThemeColor("backgroundSelected") }
    public static var kBackgroundNeutral: ThemeColor { ThemeColor("backgroundNeutral") }
    public static var kBackgroundPrimary: ThemeColor { ThemeColor("backgroundPrimary") }
    public static var kBackgroundNegative: ThemeColor { ThemeColor("backgroundNegative") }
    public static var kBackgroundWarningSubtle: ThemeColor { ThemeColor("backgroundWarningSubtle") }
    public static var kInput: ThemeColor { ThemeColor("input") }
    public static var kInteractionHover: ThemeColor { ThemeColor("interactionHover") }
}

extension TextStyle {
    public var font: Font {
        Font.system(size: size, weight: weight >= 500 ? .medium : .regular)
    }
}

public struct ThemedText: ViewModifier {
    let style: TextStyle
    public func body(content: Content) -> some View {
        // lineSpacing adds to the font's natural line height; approximate the design target without clipping.
        content
            .font(style.font)
            .lineSpacing(max(0, style.lineHeight - style.size * 1.2))
    }
}

extension View {
    public func textStyle(_ style: TextStyle) -> some View { modifier(ThemedText(style: style)) }
}
