import AppKit
import Contracts
import Foundation

extension ToolService {
    /// Opens the corresponding macOS native application or file for a `ToolResultCard` action.
    /// Kept inside `ToolService` so `App` never bypasses the system boundary.
    @MainActor @discardableResult
    public static func performCardAction(_ action: ToolResultCard.Action, memoryRoot: URL) -> Bool {
        switch action.kind {
        case .openCalendar:
            return openApplication(bundleID: "com.apple.iCal")
        case .openReminders:
            if let url = URL(string: "x-apple-reminderkit://"), NSWorkspace.shared.open(url) {
                return true
            }
            return openApplication(bundleID: "com.apple.reminders")
        case .openNotes:
            if let noteID = action.target, !noteID.isEmpty, openAppleNote(id: noteID) {
                return true
            }
            return openApplication(bundleID: "com.apple.Notes")
        case .openMessagesDraft:
            if let handle = action.target, !handle.isEmpty {
                let body = action.detail ?? ""
                if !body.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(body, forType: .string)
                }
                if let url = messagesDraftURL(handle: handle, body: body), NSWorkspace.shared.open(url) {
                    return true
                }
            }
            return openApplication(bundleID: "com.apple.MobileSMS")
        case .openMaps:
            if let url = appleMapsURL(target: action.target, name: action.detail),
               NSWorkspace.shared.open(url) {
                return true
            }
            return openApplication(bundleID: "com.apple.Maps")
        case .openMemoryFile:
            let fileName = (try? MarkdownMemoryFolder.fileName(action.target)) ?? MarkdownMemoryFolder.indexName
            let url = memoryRoot.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                return NSWorkspace.shared.open(url)
            }
            return NSWorkspace.shared.open(memoryRoot)
        case .openShortcuts:
            return openApplication(bundleID: "com.apple.shortcuts")
        }
    }

    @MainActor
    private static func openApplication(bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    @MainActor
    private static func openAppleNote(id: String) -> Bool {
        let escaped = id.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Notes"
            activate
            try
                show note id "\(escaped)"
            end try
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        return error == nil
    }

    private static func messagesDraftURL(handle: String, body: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        guard let encodedHandle = handle.filter({ !" ()-".contains($0) }).addingPercentEncoding(withAllowedCharacters: allowed),
              let encodedBody = body.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: "sms:\(encodedHandle)&body=\(encodedBody)")
    }

    private static func appleMapsURL(target: String?, name: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "maps"
        var items: [URLQueryItem] = []
        if let target, !target.isEmpty {
            items.append(URLQueryItem(name: "ll", value: target))
        }
        if let name, !name.isEmpty {
            items.append(URLQueryItem(name: "q", value: name))
        }
        guard !items.isEmpty else { return nil }
        components.queryItems = items
        return components.url
    }
}
