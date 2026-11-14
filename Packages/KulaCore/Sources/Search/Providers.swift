import Foundation
import Contracts
import os
import LocalStore
import ToolService

/// Installed applications from standard folders (plus one level of vendor subfolders such as
/// "/Applications/Adobe …"), ranked by fuzzy match + recent launches. The index is rebuilt when
/// any scanned folder changes; rebuilds reuse unchanged bundles, so an install costs one parse.
/// With a `cacheURL`, the index survives relaunches: a new process only re-checks each bundle's
/// Info.plist date instead of parsing every bundle again.
public final class AppsProvider: SearchProvider {
    public let source = SearchSource.app
    private let roots: [URL]
    private let extraApps: [URL]
    private let preferredLanguages: [String]
    private let cacheURL: URL?
    private struct IndexedApp: Codable, Equatable {
        let name: String
        let path: String
        let searchNames: Set<String>
        let stamp: Date?
    }
    private struct Index: Codable, Equatable {
        var apps: [IndexedApp]
        var stamps: [String: Date]
    }
    /// Cached names depend on the parser, the scanned locations and the user's languages.
    private struct CacheFile: Codable {
        var version: Int
        var sources: [String]
        var languages: [String]
        var index: Index
    }
    private static let cacheVersion = 1
    private let index = OSAllocatedUnfairLock<Index?>(initialState: nil)
    /// Serializes rebuilds so a background prewarm and a first search never parse twice.
    private let buildLock = NSLock()
    private let usage = OSAllocatedUnfairLock<[String: Date]>(initialState: [:])

    public init(roots: [URL] = AppsProvider.defaultRoots,
                extraApps: [URL] = AppsProvider.defaultExtraApps,
                preferredLanguages: [String] = Locale.preferredLanguages,
                cacheURL: URL? = nil) {
        self.roots = roots
        self.extraApps = extraApps
        self.preferredLanguages = preferredLanguages
        self.cacheURL = cacheURL
    }

    public static var defaultRoots: [URL] {
        ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities",
         "/System/Library/CoreServices/Applications", NSHomeDirectory() + "/Applications"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Single launchable apps living in folders that are otherwise full of system internals.
    public static var defaultExtraApps: [URL] {
        [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true)]
    }

    public func invalidate() { index.withLock { $0 = nil } }

    /// Builds the index off the main thread so the first launcher query does not wait for it.
    /// Same priority as searches: a first query waits on this build through `buildLock`,
    /// which cannot boost a lower-priority holder.
    public func prewarm() {
        Task.detached(priority: .userInitiated) { [self] in _ = loadIndex() }
    }

    /// Paths of indexed applications, building the index if needed. Blocks; call off the main thread.
    public func applicationPaths() -> [String] { loadIndex().map(\.path) }

    public func recordLaunch(path: String, at date: Date = Date()) { usage.withLock { $0[path] = date } }

    public func search(_ query: String, limit: Int) async -> [SearchResult] {
        let apps = loadIndex()
        let recent = usage.withLock { $0 }
        let now = Date()
        var scored: [(SearchResult, Double)] = []
        for app in apps {
            if Task.isCancelled { return [] }
            guard var s = app.searchNames.compactMap({ FuzzyMatch.score(query, in: $0) }).max() else { continue }
            if let last = recent[app.path] { s += max(0, 0.1 - now.timeIntervalSince(last) / (86400 * 70)) }
            let r = SearchResult(source: .app, target: TargetRef(kind: "app", identifier: app.path), title: app.name,
                                 subtitle: CoreLocalization.text("应用"), actions: [.open, .revealInFinder], score: s)
            scored.append((r, s))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    private static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    // Safari's public .app symlink can carry Finder's hidden flag. Keep such
    // launchable applications while excluding dot-prefixed internal entries.
    private static func visibleEntries(of directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Modification dates of every scanned folder. Installing or removing an app changes the
    /// date of the folder that contains it, so equal stamps mean an unchanged app list.
    private func folderStamps(subfolders: [URL]) -> [String: Date] {
        var stamps: [String: Date] = [:]
        for folder in roots + subfolders { stamps[folder.path] = Self.modificationDate(folder.path) }
        return stamps
    }

    private func subfolders() -> [URL] {
        roots.flatMap { root in
            Self.visibleEntries(of: root).filter { $0.pathExtension != "app" && Self.isDirectory($0) }
        }
    }

    private func loadIndex() -> [IndexedApp] {
        if let cached = index.withLock({ $0 }), cached.stamps == folderStamps(subfolders: subfolders()) {
            return cached.apps
        }
        buildLock.lock()
        defer { buildLock.unlock() }
        let folders = subfolders()
        let stamps = folderStamps(subfolders: folders)
        let memory = index.withLock { $0 }
        if let memory, memory.stamps == stamps { return memory.apps }
        // A disk index never short-circuits on folder stamps: apps updated in place while
        // Asky was not running leave their folder date unchanged, so every bundle is re-checked.
        let stored = memory == nil ? readCache() : nil
        let previous = memory ?? stored
        let reusable = Dictionary((previous?.apps ?? []).map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        var candidates = (roots + folders).flatMap { Self.visibleEntries(of: $0).filter { $0.pathExtension == "app" } }
        candidates += extraApps.filter { FileManager.default.fileExists(atPath: $0.path) }
        var out: [IndexedApp] = []
        var seen = Set<String>()
        for url in candidates where seen.insert(url.path).inserted {
            // Updates replace Info.plist, so its date identifies the installed version.
            let stamp = Self.modificationDate(url.appendingPathComponent("Contents/Info.plist").path)
                ?? Self.modificationDate(url.path)
            if let cached = reusable[url.path], cached.stamp == stamp {
                out.append(cached)
            } else {
                out.append(indexedApp(at: url, stamp: stamp))
            }
        }
        let built = Index(apps: out, stamps: stamps)
        index.withLock { $0 = built }
        if built != previous { writeCache(built) }
        return out
    }

    private var cacheSources: [String] { (roots + extraApps).map(\.path) }

    private func readCache() -> Index? {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL),
              let file = try? JSONDecoder().decode(CacheFile.self, from: data),
              file.version == Self.cacheVersion, file.sources == cacheSources, file.languages == preferredLanguages
        else { return nil }
        return file.index
    }

    private func writeCache(_ index: Index) {
        guard let cacheURL else { return }
        let file = CacheFile(version: Self.cacheVersion, sources: cacheSources, languages: preferredLanguages, index: index)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func indexedApp(at url: URL, stamp: Date?) -> IndexedApp {
        let fileName = url.deletingPathExtension().lastPathComponent
        let keys = ["CFBundleDisplayName", "CFBundleName"]
        // Read Info.plist directly: Bundle(url:) caches per path for the process lifetime,
        // so an app updated in place would keep its old name.
        let info = (try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        var localizedNames: [String] = []
        let bundleNames = keys.compactMap { info?[$0] as? String }
            .filter { !$0.isEmpty }
        var names = Set([fileName] + localizedNames + bundleNames)
        // Index the app's own translations, even when macOS uses a different language.
        // InfoPlist.strings may be XML/binary plists or OpenStep strings in UTF-16.
        let resources = url.appendingPathComponent("Contents/Resources", isDirectory: true)
        // Match the user's language explicitly: Bundle's implicit selection can be
        // limited by the host app's own development language. Platform variants
        // must never let iPhone/Apple TV names leak into macOS search results.
        var translations: [String: [String: Any]] = [:]
        if let data = try? Data(contentsOf: resources.appendingPathComponent("InfoPlist.loctable")),
           let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for (language, value) in table where !language.contains("~") {
                if let dictionary = value as? [String: Any], keys.contains(where: { dictionary[$0] is String }) {
                    translations[language] = dictionary
                }
            }
            for (language, value) in table where language.hasSuffix("~mac") {
                guard let dictionary = value as? [String: Any] else { continue }
                let base = String(language.dropLast(4))
                translations[base, default: [:]].merge(dictionary) { _, macValue in macValue }
            }
        }
        let localizations = (try? FileManager.default.contentsOfDirectory(
            at: resources, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for localization in localizations where localization.pathExtension == "lproj" {
            guard let data = try? Data(contentsOf: localization.appendingPathComponent("InfoPlist.strings")),
                  let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }
            let language = localization.deletingPathExtension().lastPathComponent
            translations[language, default: [:]].merge(dictionary) { _, stringsValue in stringsValue }
        }
        // Index only the user's language families plus English: fuzzy matching against
        // every translation (e.g. Turkish "Etkinlik Monitörü") yields unrelated hits.
        let searchable = Set(preferredLanguages.map(Self.languageFamily) + ["en", "english", "base"])
        for (language, dictionary) in translations where searchable.contains(Self.languageFamily(language)) {
            for key in keys {
                if let name = dictionary[key] as? String, !name.isEmpty { names.insert(name) }
            }
        }
        let languages = translations.keys.filter { language in
            keys.contains { (translations[language]?[$0] as? String).map { !$0.isEmpty } ?? false }
        }.sorted()
        if let language = Bundle.preferredLocalizations(from: languages, forPreferences: preferredLanguages).first,
           let dictionary = translations[language] {
            let preferredNames = keys.compactMap { dictionary[$0] as? String }.filter { !$0.isEmpty }
            if !preferredNames.isEmpty { localizedNames = preferredNames }
        }
        return IndexedApp(name: localizedNames.first ?? bundleNames.first ?? fileName,
                          path: url.path, searchNames: names, stamp: stamp)
    }

    private static func languageFamily(_ identifier: String) -> String {
        String(identifier.lowercased().prefix { $0 != "_" && $0 != "-" })
    }

}

/// File-name search through Spotlight (NSMetadataQuery), restricted to configured scopes and
/// excluding configured directories. Never builds its own full-disk index.
public final class SpotlightProvider: SearchProvider {
    public let source = SearchSource.file
    private let settings: @Sendable () -> (scopes: [URL], excluded: [String])
    public let timeout: Duration

    public init(timeout: Duration = .milliseconds(450),
                settings: @escaping @Sendable () -> (scopes: [URL], excluded: [String]) = {
                    ([FileManager.default.homeDirectoryForCurrentUser], [])
                }) {
        self.settings = settings
        self.timeout = timeout
    }

    /// Runs one throwaway query so the first real search does not pay Spotlight's per-process setup.
    public func prewarm() {
        Task.detached(priority: .utility) { [self] in _ = await search("asky-prewarm", limit: 1) }
    }

    public func search(_ query: String, limit: Int) async -> [SearchResult] {
        let (scopes, excluded) = settings()
        return await ToolService.searchLauncherFiles(query: query, scopes: scopes,
                                                     excluded: excluded, limit: limit, timeout: timeout)
    }
}

/// Clipboard history search; read-only, bounded.
public struct ClipboardProvider: SearchProvider {
    public let source = SearchSource.clipboard
    let store: ClipboardStore
    public init(store: ClipboardStore) { self.store = store }

    public func search(_ query: String, limit: Int) async -> [SearchResult] {
        guard limit > 0 else { return [] }
        return ClipboardAccess.search(in: store, query: query, limit: limit).map { item in
            let title: String
            switch item.kind {
            case .text: title = String((item.text ?? "").prefix(120)).replacingOccurrences(of: "\n", with: " ")
            case .image: title = item.imageTitle
            case .file: title = item.text ?? URL(fileURLWithPath: item.filePath ?? "").lastPathComponent
            }
            return SearchResult(source: .clipboard, target: TargetRef(kind: "clipboard", identifier: item.id), title: title,
                                subtitle: CoreLocalization.format("剪贴板 · %@", String(describing: item.sourceApp ?? "")),
                                actions: item.kind == .text ? (item.text.map { [.copy($0)] } ?? [.open]) : [.open], score: 0.35)
        }
    }
}
