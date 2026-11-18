import Foundation
import Contracts

extension ToolService {
    /// Packages (including .app bundles) keep their normal open behavior.
    public static func launcherFolder(at path: String) -> URL? {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
              values.isDirectory == true, values.isPackage != true else { return nil }
        return url
    }

    /// Empty input browses immediate children. Spotlight adds indexed descendants for a name search.
    /// Directory reads run off the UI thread; no private index or document-content scan is created.
    public static func searchLauncherFolder(_ folder: URL, query: String, excluded: [String],
                                            limit: Int = 40) async throws -> [SearchResult] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let children = try await Task.detached(priority: .userInitiated) {
            try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles])
        }.value
        try Task.checkCancellation()
        var urls = children.filter { text.isEmpty || $0.lastPathComponent.localizedStandardContains(text) }
        if !text.isEmpty {
            let paths = await LauncherFileMetadataSearch().run(text: text, scopes: [folder], timeout: .milliseconds(450), limit: limit * 4)
            urls += paths.map { URL(fileURLWithPath: $0) }
        }
        try Task.checkCancellation()
        let exclusions = LauncherFileExclusions(excluded)
        let root = folder.standardizedFileURL.path
        var seen = Set<String>()
        return urls.filter { url in
            let path = url.standardizedFileURL.path
            return path.hasPrefix(root == "/" ? "/" : root + "/") &&
                !path.dropFirst(root.count).split(separator: "/").contains(where: { $0.hasPrefix(".") }) &&
                !exclusions.contains(path) &&
                seen.insert(path).inserted
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(max(0, limit)).map { url in
                SearchResult(source: .file, target: TargetRef(kind: "file", identifier: url.path),
                             title: url.lastPathComponent,
                             subtitle: (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath,
                             actions: [.open, .revealInFinder])
            }
    }
}
