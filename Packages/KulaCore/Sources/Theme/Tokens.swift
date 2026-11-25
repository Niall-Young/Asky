import Foundation

/// Design data snapshot from Figma (docs/design-system.md appendix, colors checked 2026-10-10).
/// Source names are preserved verbatim; native code maps them to normalized names.
public struct RGBA: Sendable, Hashable {
    public var red: Double, green: Double, blue: Double, alpha: Double
    public init(hex: UInt32, alpha: Double) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }
}

public enum Appearance: String, Sendable, CaseIterable {
    case light, dark
}

public enum Palette {
    static let blackHex: UInt32 = 0x0E0F11
    static let whiteHex: UInt32 = 0xFFFFFF
    static let steps = [100, 90, 80, 70, 60, 50, 40, 30, 20, 10, 8, 6, 4, 2, 0]

    public static let values: [String: RGBA] = {
        var v: [String: RGBA] = [:]
        for s in steps {
            v["black\(s)"] = RGBA(hex: blackHex, alpha: Double(s) / 100)
            v["white\(s)"] = RGBA(hex: whiteHex, alpha: Double(s) / 100)
        }
        v["red"] = RGBA(hex: 0xFF0730, alpha: 1)
        v["warningLight"] = RGBA(hex: 0xAD690B, alpha: 1)
        v["warningDark"] = RGBA(hex: 0xE8AD52, alpha: 1)
        v["negativeLight"] = RGBA(hex: 0xB84542, alpha: 1)
        v["negativeDark"] = RGBA(hex: 0xDC726E, alpha: 1)
        v["negativeFillDark"] = RGBA(hex: 0xB54B48, alpha: 1)
        v["green"] = RGBA(hex: 0x28EEA5, alpha: 1)
        return v
    }()
}

/// Semantic colors: values are "Palette/x" or "Colors/y" aliases per mode.
public enum SemanticColors {
    public static let sourceTable: [String: (light: String, dark: String)] = [
        "text": ("Palette/black90", "Palette/white90"),
        "textSubtle": ("Palette/black70", "Palette/white70"),
        "textSubtlest": ("Palette/black50", "Palette/white50"),
        "textDisabled": ("Palette/black30", "Palette/white30"),
        "textInverted": ("Palette/white100", "Palette/black100"),
        "textPrimary": ("Palette/black90", "Palette/white90"),
        "textWarning": ("Palette/warningLight", "Palette/warningDark"),
        "textNegative": ("Palette/negativeLight", "Palette/negativeDark"),
        "textPositive": ("Palette/green", "Palette/green"),
        "textSelected": ("Colors/textPrimary", "Colors/textPrimary"),
        "icon": ("Palette/black80", "Palette/white80"),
        "iconSubtle": ("Palette/black60", "Palette/white60"),
        "iconSubtlest": ("Palette/black50", "Palette/white50"),
        "iconDisabled": ("Palette/black30", "Palette/white30"),
        "iconInverted": ("Palette/white100", "Palette/black100"),
        "iconPrimary": ("Palette/black80", "Palette/white80"),
        "iconNegative": ("Palette/negativeLight", "Palette/negativeDark"),
        "iconPositive": ("Palette/green", "Palette/green"),
        "iconSelected": ("Colors/iconPrimary", "Colors/iconPrimary"),
        "border": ("Palette/black8", "Palette/white8"),
        "borderIntense": ("Palette/black10", "Palette/white10"),
        "borderPrimary": ("Palette/black20", "Palette/white20"),
        "borderNegative": ("Palette/negativeLight", "Palette/negativeDark"),
        "borderPositive": ("Palette/green", "Palette/green"),
        "borderSelected": ("Colors/borderPrimary", "Colors/borderPrimary"),
        "borderFocused": ("Colors/borderPrimary", "Colors/borderPrimary"),
        "background": ("Palette/white60", "Palette/black60"),
        "backgroundDisbled": ("Palette/black2", "Palette/white2"),
        "backgroundPrimary": ("Palette/black100", "Palette/white100"),
        "backgroundPrimaryHover": ("Palette/black80", "Palette/white80"),
        "backgroundPrimarySubtle": ("Palette/black6", "Palette/white6"),
        "backgroundNegative": ("Palette/negativeLight", "Palette/negativeFillDark"),
        "backgroundPositive": ("Palette/green", "Palette/green"),
        "backgroundNeutral": ("Palette/black6", "Palette/white6"),
        "backgroundNeutralHover": ("Palette/black8", "Palette/white8"),
        "backgroundNeutralIntense": ("Palette/black20", "Palette/white20"),
        "backgroundSelected": ("Colors/backgroundPrimarySubtle", "Colors/backgroundPrimarySubtle"),
        "backgroundSelectedIntense": ("Colors/backgroundPrimary", "Colors/backgroundPrimary"),
        "Overlay": ("Palette/black20", "Palette/black60"),
        "Input": ("Palette/black8", "Palette/white8"),
        "InteractionHover": ("Palette/black6", "Palette/white8"),
    ]

    /// Explicit native-name → source-name mapping (keeps source spelling such as `backgroundDisbled`).
    public static let nativeToSource: [String: String] = {
        var m: [String: String] = [:]
        for k in sourceTable.keys { m[k] = k }
        m["backgroundDisabled"] = "backgroundDisbled"
        m["overlay"] = "Overlay"
        m["input"] = "Input"
        m["interactionHover"] = "InteractionHover"
        m.removeValue(forKey: "backgroundDisbled")
        m.removeValue(forKey: "Overlay")
        m.removeValue(forKey: "Input")
        m.removeValue(forKey: "InteractionHover")
        return m
    }()

    /// Recursively resolves aliases for the given mode.
    public static func resolve(_ sourceName: String, _ appearance: Appearance, depth: Int = 0) -> RGBA? {
        guard depth < 8, let entry = sourceTable[sourceName] else { return nil }
        let ref = appearance == .light ? entry.light : entry.dark
        let parts = ref.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "Palette": return Palette.values[parts[1]]
        case "Colors": return resolve(parts[1], appearance, depth: depth + 1)
        default: return nil
        }
    }

    public static func color(native: String, _ appearance: Appearance) -> RGBA? {
        guard let src = nativeToSource[native] else { return nil }
        return resolve(src, appearance)
    }
}

public enum Radius {
    public static let values: [String: Double] = [
        "radius0": 0, "radius4": 4, "radius8": 8, "radius12": 12, "radius16": 16,
        "radius24": 24, "radius32": 32, "radius40": 40, "radius48": 48, "radius99999": 99999,
    ]
    /// radius99999 maps to a capsule rather than a huge corner radius.
    public static func isCapsule(_ name: String) -> Bool { name == "radius99999" }
}

public enum BorderWidth {
    public static let values: [String: Double] = ["borderWidth0": 0, "borderWidth1": 1, "borderWidth2": 2]
}

public enum OpacityToken {
    /// Figma `disabled = 30` (percent) normalized.
    public static let disabled: Double = 0.30
}

public enum TypeLanguage: String, Sendable {
    case english, chinese
    public var fontFamily: String { self == .english ? "SF Pro" : "PingFang SC" }
}

public enum LineHeightMode: String, Sendable {
    case `default` = "Default"
    case paragraph = "Paragraph"
}

public struct TextStyle: Sendable, Hashable {
    public var size: Double
    public var weight: Int
    public var mode: LineHeightMode
    public var sourceName: String { "\(Int(size))/\(weight)/\(mode.rawValue)" }
    public var lineHeight: Double { TextStyle.lineHeights[Int(size)].map { mode == .default ? $0.0 : $0.1 } ?? size * 1.4 }

    static let lineHeights: [Int: (Double, Double)] = [
        12: (20, 24), 14: (22, 28), 16: (24, 32), 18: (26, 36), 20: (28, 40), 24: (32, 48),
    ]

    public init(size: Double, weight: Int, mode: LineHeightMode) {
        self.size = size
        self.weight = weight
        self.mode = mode
    }

    /// All 24 Styles from the Figma file.
    public static let all: [TextStyle] = [12, 14, 16, 18, 20, 24].flatMap { s in
        [400, 500].flatMap { w in [LineHeightMode.default, .paragraph].map { TextStyle(size: Double(s), weight: w, mode: $0) } }
    }

    // Role mapping (design-system.md, prototype defaults).
    public static let input = TextStyle(size: 16, weight: 400, mode: .default)
    public static let resultPrimary = TextStyle(size: 14, weight: 400, mode: .default)
    public static let secondary = TextStyle(size: 12, weight: 400, mode: .default)
    public static let button = TextStyle(size: 14, weight: 500, mode: .default)
    public static let body = TextStyle(size: 16, weight: 400, mode: .paragraph)
}

public enum WindowMetrics {
    public static let launcherWidth: Double = 640
    public static let launcherMaxHeight: Double = 640
    public static let agentWidth: Double = 560
    public static let agentInitialSize = (width: agentWidth, height: 680.0)
    public static let agentMinSize = agentInitialSize
}
