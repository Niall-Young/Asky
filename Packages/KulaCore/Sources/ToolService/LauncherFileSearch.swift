import Foundation
import Contracts

extension ToolService {
    /// Query only Spotlight metadata. Filter and rank the gathered snapshot before applying
    /// the result limit, so recent cache files cannot crowd out an exact filename or folder.
    public static func searchLauncherFiles(query: String, scopes: [URL], excluded: [String],
                                           limit: Int = 8, timeout: Duration = .milliseconds(450)) async -> [SearchResult] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, limit > 0, !scopes.isEmpty, !Task.isCancelled else { return [] }
        let paths = await LauncherFileMetadataSearch().run(text: text, scopes: scopes, timeout: timeout)
        guard !Task.isCancelled else { return [] }
        return await Task.detached(priority: .userInitiated) {
            LauncherFileRanking.results(paths: paths, query: text, excluded: excluded, limit: limit)
        }.value
    }
}

/// Pure snapshot processing; paths arrive newest first, which breaks equal-name-score ties.
enum LauncherFileRanking {
    static func results(paths: [String], query: String, excluded: [String], limit: Int) -> [SearchResult] {
        guard limit > 0 else { return [] }
        let normalize: (String) -> String = {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        }
        let text = normalize(query)
        guard !text.isEmpty else { return [] }
        let exclusions = LauncherFileExclusions(excluded)
        var seen = Set<String>()
        var best: [SearchResult] = []
        for path in paths {
            let components = path.split(separator: "/").map(String.init)
            guard !components.contains(where: { $0.hasPrefix(".") || $0 == "Library" }),
                  !exclusions.contains(path),
                  seen.insert(path).inserted else { continue }
            let url = URL(fileURLWithPath: path)
            let name = normalize(url.lastPathComponent)
            guard name.contains(text) else { continue }
            let words = name.split(whereSeparator: { " -_.".contains($0) })
            let score = name == text ? 1.0 : name.hasPrefix(text) ? 0.9 :
                words.contains(where: { $0.hasPrefix(text) }) ? 0.8 : 0.6
            let result = SearchResult(source: .file, target: TargetRef(kind: "file", identifier: path),
                                      title: url.lastPathComponent,
                                      subtitle: (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath,
                                      actions: [.open, .revealInFinder], score: score)
            // Keep only the best bounded batch while considering every gathered match.
            let index = best.firstIndex(where: { $0.score < score }) ?? best.endIndex
            if index < limit {
                best.insert(result, at: index)
                if best.count > limit { best.removeLast() }
            }
        }
        return best
    }
}

struct LauncherFileExclusions {
    let absoluteExclusions: [String]
    let excludedNames: Set<String>

    init(_ excluded: [String]) {
        absoluteExclusions = excluded.filter { $0.hasPrefix("/") || $0.hasPrefix("~") }
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL.path }
        excludedNames = Set(excluded.filter { !$0.contains("/") && !$0.hasPrefix("~") })
    }

    func contains(_ path: String) -> Bool {
        path.split(separator: "/").contains { excludedNames.contains(String($0)) }
            || absoluteExclusions.contains { $0 == "/" || path == $0 || path.hasPrefix($0 + "/") }
    }
}

@MainActor
final class LauncherFileMetadataSearch {
    private var observer: NSObjectProtocol?
    private var deadline: Task<Void, Never>?
    private var finishQuery: (() -> Void)?
    nonisolated init() {}

    func run(text: String, scopes: [URL], timeout: Duration, limit: Int = .max) async -> [String] {
        guard !Task.isCancelled else { return [] }
        let query = NSMetadataQuery()
        query.searchScopes = scopes
        query.predicate = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, text)
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        return await withTaskCancellationHandler {
            await collect(query, timeout: timeout, limit: limit)
        } onCancel: { Task { @MainActor in self.finishQuery?() } }
    }

    private func collect(_ query: NSMetadataQuery, timeout: Duration, limit: Int) async -> [String] {
        guard !Task.isCancelled else { return [] }
        return await withCheckedContinuation { continuation in
            var finished = false
            let finish: @MainActor () -> Void = {
                guard !finished else { return }
                finished = true
                query.disableUpdates()
                let paths = (0..<min(limit, query.resultCount)).compactMap {
                    (query.result(at: $0) as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String
                }
                query.stop()
                if let observer = self.observer { NotificationCenter.default.removeObserver(observer) }
                self.observer = nil
                self.deadline?.cancel()
                self.deadline = nil
                self.finishQuery = nil
                continuation.resume(returning: paths)
            }
            self.finishQuery = finish
            self.observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering,
                                                               object: query, queue: .main) { _ in
                MainActor.assumeIsolated { finish() }
            }
            guard query.start() else { finish(); return }
            self.deadline = Task { @MainActor in
                do { try await Task.sleep(for: timeout) } catch { return }
                finish()
            }
        }
    }
}
