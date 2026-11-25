import Foundation

/// Shared display strings for the native app and the independently launched MCP Bridge.
/// Error codes, arguments, identifiers and user content never pass through this lookup.
public enum CoreLocalization {
    private static let launchLanguage: String = {
        let main = Bundle.main
        let preferences: [String]
        if main.localizations.contains("en") || main.localizations.contains("zh-Hans") {
            preferences = main.preferredLocalizations
        } else {
            // Command-line executables have no native main-bundle localization.
            preferences = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        }
        return Bundle.preferredLocalizations(from: Bundle.module.localizations, forPreferences: preferences).first ?? "zh-Hans"
    }()

    public static var currentLanguage: String { launchLanguage }

    public static func isEnglish(_ language: String? = nil) -> Bool {
        (language ?? launchLanguage).lowercased().hasPrefix("en")
    }

    public static func text(_ key: String, language: String? = nil) -> String {
        let bundle: Bundle
        if let path = Bundle.module.path(forResource: language ?? launchLanguage, ofType: "lproj"),
           let localized = Bundle(path: path) {
            bundle = localized
        } else {
            bundle = .module
        }
        return bundle.localizedString(forKey: key, value: nil, table: "Core")
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }

    public static func format(_ key: String, language: String?, _ arguments: CVarArg...) -> String {
        String(format: text(key, language: language), arguments: arguments)
    }
}
