import Foundation
import AppKit
import Contracts
import ToolService
import Search

/// Google Chrome tabs via Apple Events. Incognito windows are never enumerated; no page content or history.
public struct ChromeBridge: Sendable {
    public static let bundleID = "com.google.Chrome"
    let runner: AppleScriptRunner
    public init(runner: AppleScriptRunner = .shared) { self.runner = runner }

    public struct Tab: Sendable, Hashable {
        public var windowID: String
        public var tabID: String
        public var title: String
        public var url: String
        public var ref: TargetRef { TargetRef(kind: "chromeTab", identifier: "\(windowID):\(tabID)") }
    }

    /// Never launches Chrome just to list tabs.
    public var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty }

    public func tabs() async throws -> [Tab] {
        guard isRunning else { return [] }
        let src = """
        \(AppleScript.joinHandler)
        tell application id "\(Self.bundleID)"
          set out to {}
          repeat with w in windows
            if mode of w is not "incognito" then
              set wid to (id of w) as text
              repeat with t in tabs of w
                set end of out to my kjoin({wid, (id of t) as text, title of t, URL of t}, \(AppleScript.us))
              end repeat
            end if
          end repeat
          return my kjoin(out, \(AppleScript.rs))
        end tell
        """
        return AppleScript.parseRecords(try await runner.run(src), fields: 4).map {
            Tab(windowID: $0[0], tabID: $0[1], title: $0[2], url: $0[3])
        }
    }

    /// Re-validates the target (exists, not incognito, same URL if given) right before switching.
    public func activate(windowID: String, tabID: String, expectedURL: String?) async throws -> Tab {
        guard isRunning else { throw ToolError(.unavailable, CoreLocalization.text("Chrome 未运行")) }
        guard let w = Int(windowID), let t = Int(tabID) else { throw ToolError(.invalidArguments, CoreLocalization.text("标签标识无效")) }
        let check = expectedURL.map { "if URL of tb is not \(AppleScript.literal($0)) then error \(AppleScript.literal(CoreLocalization.text("标签页已变化"))) number -1728" } ?? ""
        let src = """
        \(AppleScript.joinHandler)
        tell application id "\(Self.bundleID)"
          set w to window id \(w)
          if mode of w is "incognito" then error \(AppleScript.literal(CoreLocalization.text("无痕窗口不可访问"))) number -1728
          set tb to tab id \(t) of w
          \(check)
          set idx to 0
          repeat with i from 1 to count of tabs of w
            if (id of tab i of w) as text is "\(t)" then
              set idx to i as integer
              exit repeat
            end if
          end repeat
          if idx < 1 then error \(AppleScript.literal(CoreLocalization.text("该标签页已关闭或不可访问，请刷新标签列表"))) number -1728
          if id of tab idx of w is not \(t) then error \(AppleScript.literal(CoreLocalization.text("标签页已变化，请刷新标签列表"))) number -1728
          set active tab index of w to idx
          set index of w to 1
          activate
          return my kjoin({(id of w) as text, (id of tb) as text, title of tb, URL of tb}, \(AppleScript.us))
        end tell
        """
        guard let f = AppleScript.parseRecords(try await runner.run(src), fields: 4).first else {
            throw ToolError(.targetNotFound, CoreLocalization.text("找不到该标签页"))
        }
        return Tab(windowID: f[0], tabID: f[1], title: f[2], url: f[3])
    }


}

/// Launcher provider: cached results are shown first; the cache is refreshed in the background with a bounded lifetime.
public final class ChromeTabsProvider: SearchProvider, @unchecked Sendable {
    public let source = SearchSource.chromeTab
    let bridge: ChromeBridge
    let cache = CacheBox()
    let maxAge: TimeInterval

    final class CacheBox: @unchecked Sendable {
        let lock = NSLock()
        var tabs: [ChromeBridge.Tab] = []
        var at = Date.distantPast
        var refreshing = false
    }

    public init(bridge: ChromeBridge = .init(), maxAge: TimeInterval = 5) {
        self.bridge = bridge
        self.maxAge = maxAge
    }

    public func search(_ query: String, limit: Int) async -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty, bridge.isRunning else { return [] }
        let (snapshot, stale) = cache.lock.withLock { (cache.tabs, Date().timeIntervalSince(cache.at) > maxAge) }
        var tabs = snapshot
        if stale {
            if snapshot.isEmpty {
                tabs = (try? await bridge.tabs()) ?? []
                cache.lock.withLock { cache.tabs = tabs; cache.at = Date() }
            } else {
                refreshInBackground()
            }
        }
        return tabs.compactMap { t -> SearchResult? in
            let title = t.title.lowercased(), url = t.url.lowercased()
            let score: Double = title.hasPrefix(q) ? 0.9 : title.contains(q) ? 0.7 : url.contains(q) ? 0.5 : 0
            guard score > 0 else { return nil }
            return SearchResult(source: .chromeTab, target: t.ref, title: t.title.isEmpty ? t.url : t.title,
                                subtitle: t.url, actions: [.switchTo, .copy(t.url)], score: score)
        }.sorted { $0.score > $1.score }.prefix(limit).map { $0 }
    }

    /// URLs from the last tab snapshot; never queries Chrome.
    public var cachedURLs: [URL] { cache.lock.withLock { cache.tabs.compactMap { URL(string: $0.url) } } }

    public func invalidate() { cache.lock.withLock { cache.tabs = []; cache.at = .distantPast } }

    func refreshInBackground() {
        let start = cache.lock.withLock { () -> Bool in
            if cache.refreshing { return false }
            cache.refreshing = true
            return true
        }
        guard start else { return }
        Task { [bridge, cache] in
            let tabs = (try? await bridge.tabs())
            cache.lock.withLock {
                if let tabs { cache.tabs = tabs; cache.at = Date() }
                cache.refreshing = false
            }
        }
    }
}

public struct ChromeListTabsTool: ToolAdapter {
    let bridge: ChromeBridge
    public init(_ bridge: ChromeBridge = .init()) { self.bridge = bridge }

    public var definition: ToolDefinition {
        ToolDefinition(name: "chrome_list_tabs", summary: CoreLocalization.text("列出 Chrome 普通窗口中的标签页（标题、URL）"),
                       inputSchema: Args.schema(["query": Args.stringProp, "limit": Args.intProp], required: []),
                       source: .chrome, effect: .read, confirmation: .never, externallyExposable: true)
    }

    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        let q = try Args.string(a["query"], "query", required: false)?.lowercased()
        let limit = Args.int(a["limit"], default: 50, max: 200)
        let tabs = try await bridge.tabs()
            .filter { q == nil || $0.title.lowercased().contains(q!) || $0.url.lowercased().contains(q!) }
            .prefix(limit)
        return AdapterOutput(output: .array(tabs.map { ["windowID": .string($0.windowID), "tabID": .string($0.tabID),
                                                         "title": .string($0.title), "url": .string($0.url)] }),
                             targets: tabs.map(\.ref))
    }
}

public struct ChromeActivateTabTool: ToolAdapter {
    let bridge: ChromeBridge
    public init(_ bridge: ChromeBridge = .init()) { self.bridge = bridge }

    public var definition: ToolDefinition {
        ToolDefinition(name: "chrome_activate_tab", summary: CoreLocalization.text("切换到指定的 Chrome 标签页"),
                       inputSchema: Args.schema(["windowID": Args.stringProp, "tabID": Args.stringProp, "url": Args.stringProp],
                                                required: ["windowID", "tabID"]),
                       source: .chrome, effect: .write, writeKind: .create, confirmation: .createDirectOtherwiseConfirm,
                       externallyExposable: true)
    }

    public func preview(_ a: JSONValue) async throws -> ConfirmationPreview {
        let w = try Args.requiredString(a, "windowID"), t = try Args.requiredString(a, "tabID")
        guard let tab = try await bridge.tabs().first(where: { $0.windowID == w && $0.tabID == t }) else {
            throw ToolError(.targetNotFound, CoreLocalization.text("该标签页已关闭或不可访问"))
        }
        return ConfirmationPreview(target: "Chrome 标签页", changes: ["切换到「\(tab.title)」", tab.url])
    }

    public func execute(_ a: JSONValue) async throws -> AdapterOutput {
        let tab = try await bridge.activate(windowID: try Args.requiredString(a, "windowID"),
                                            tabID: try Args.requiredString(a, "tabID"),
                                            expectedURL: try Args.string(a["url"], "url", required: false))
        return AdapterOutput(output: ["title": .string(tab.title), "url": .string(tab.url)], targets: [tab.ref])
    }
}
