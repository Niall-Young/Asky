import AppKit
import Contracts

/// Google Chrome tabs via Apple Events. Incognito windows are never enumerated; no page content or history.
public struct LauncherChromeBridge: Sendable {
    public static let bundleID = "com.google.Chrome"
    let runner: SystemScriptRunner
    public init(runner: SystemScriptRunner = .shared) { self.runner = runner }

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
        \(SystemScript.joinHandler)
        tell application id "\(Self.bundleID)"
          set out to {}
          repeat with w in windows
            if mode of w is not "incognito" then
              set wid to (id of w) as text
              repeat with t in tabs of w
                set end of out to my kjoin({wid, (id of t) as text, title of t, URL of t}, \(SystemScript.us))
              end repeat
            end if
          end repeat
          return my kjoin(out, \(SystemScript.rs))
        end tell
        """
        return SystemScript.parseRecords(try await runner.run(src), fields: 4).map {
            Tab(windowID: $0[0], tabID: $0[1], title: $0[2], url: $0[3])
        }
    }

    /// Re-validates the target (exists, not incognito, same URL if given) right before switching.
    public func activate(windowID: String, tabID: String, expectedURL: String?) async throws -> Tab {
        guard isRunning else { throw ToolError(.unavailable, CoreLocalization.text("Chrome 未运行")) }
        guard let w = Int(windowID), let t = Int(tabID) else { throw ToolError(.invalidArguments, CoreLocalization.text("标签标识无效")) }
        let check = expectedURL.map { "if URL of tb is not \(SystemScript.literal($0)) then error \(SystemScript.literal(CoreLocalization.text("标签页已变化"))) number -1728" } ?? ""
        let src = """
        \(SystemScript.joinHandler)
        tell application id "\(Self.bundleID)"
          set w to window id \(w)
          if mode of w is "incognito" then error \(SystemScript.literal(CoreLocalization.text("无痕窗口不可访问"))) number -1728
          set tb to tab id \(t) of w
          \(check)
          set idx to 0
          repeat with i from 1 to count of tabs of w
            if (id of tab i of w) as text is "\(t)" then
              set idx to i as integer
              exit repeat
            end if
          end repeat
          if idx < 1 then error \(SystemScript.literal(CoreLocalization.text("该标签页已关闭或不可访问，请刷新标签列表"))) number -1728
          if id of tab idx of w is not \(t) then error \(SystemScript.literal(CoreLocalization.text("标签页已变化，请刷新标签列表"))) number -1728
          set active tab index of w to idx
          set index of w to 1
          activate
          return my kjoin({(id of w) as text, (id of tb) as text, title of tb, URL of tb}, \(SystemScript.us))
        end tell
        """
        guard let f = SystemScript.parseRecords(try await runner.run(src), fields: 4).first else {
            throw ToolError(.targetNotFound, CoreLocalization.text("找不到该标签页"))
        }
        return Tab(windowID: f[0], tabID: f[1], title: f[2], url: f[3])
    }


}
