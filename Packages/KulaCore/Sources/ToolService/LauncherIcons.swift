import AppKit
import Contracts
import UniformTypeIdentifiers

extension ToolService {
    @MainActor public static func pluginApplicationIcon(repository: String) -> NSImage? {
        let bundleID: String
        switch repository.lowercased() {
        case "https://github.com/niall-young/asky-plugin-orca": bundleID = "com.stablyai.orca"
        case "https://github.com/niall-young/asky-plugin-lark": bundleID = "com.bytedance.macos.feishu"
        default: return nil
        }
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return launcherIcon(filePath: application.path)
    }

    @MainActor private static let launcherIcons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 128
        return cache
    }()

    @MainActor private static var browserApplication: URL?
    @MainActor private static var browserScheme: String?
    @MainActor private static var browserCheckedAt = Date.distantPast
    @MainActor public static func openLauncherURL(_ url: URL) -> Bool {
        return NSWorkspace.shared.open(url)
    }
    @MainActor public static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Presentation-only system reads stay in the native service boundary.
    @MainActor public static func launcherIcon(filePath: String) -> NSImage {
        if let cached = launcherIcons.object(forKey: filePath as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: filePath)
        launcherIcons.setObject(icon, forKey: filePath as NSString)
        return icon
    }

    /// File metadata is read here, alongside the launcher's system icon lookup.
    @MainActor public static func launcherFileType(filePath: String) -> String? {
        let url = URL(fileURLWithPath: filePath)
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
        let type = values?.contentType
        if values?.isDirectory == true {
            return (type ?? .folder).localizedDescription
        }
        let ext = url.pathExtension
        if !ext.isEmpty { return ext.uppercased() }
        return type?.localizedDescription
    }

    /// Seed the same small, decoded artwork cache used by visible result rows.
    public static func prewarmLauncherIcons(filePaths: [String]) {
        Task.detached(priority: .utility) {
            for path in filePaths {
                guard !Task.isCancelled else { return }
                _ = await loadLauncherPresentation(for: .file(path: path))
            }
        }
    }

    /// Resolve the actual app artwork for each configurable data source.
    @MainActor public static func dataSourceApplicationIcon(_ source: DataSourceID) -> NSImage? {
        let bundleID: String
        switch source {
        case .calendar: bundleID = "com.apple.iCal"
        case .reminders: bundleID = "com.apple.reminders"
        case .notes: bundleID = "com.apple.Notes"
        case .contacts: bundleID = "com.apple.AddressBook"
        case .chrome: bundleID = "com.google.Chrome"
        case .shortcuts: bundleID = "com.apple.shortcuts"
        case .messages: bundleID = "com.apple.MobileSMS"
        case .maps: bundleID = "com.apple.Maps"
        case .terminal: bundleID = "com.apple.Terminal"
        case .clipboard, .plugins, .web: return nil
        case .memory: return launcherIcon(filePath: Bundle.main.bundlePath)
        }
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return launcherIcon(filePath: application.path)
    }

    @MainActor public static func launcherBrowserIcon(for url: URL) -> NSImage? {
        // Launcher commands use web URLs. Reuse the handler during rapid result updates.
        if browserScheme != url.scheme || Date().timeIntervalSince(browserCheckedAt) > 5 {
            browserScheme = url.scheme
            browserApplication = NSWorkspace.shared.urlForApplication(toOpen: url)
            browserCheckedAt = Date()
        }
        guard let application = browserApplication else { return nil }
        return launcherIcon(filePath: application.path)
    }
}
