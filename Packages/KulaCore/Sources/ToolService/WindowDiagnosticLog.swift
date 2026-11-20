import CoreGraphics
import Foundation

/// Privacy-preserving snapshot of an on-screen window near the launcher.
/// Never captures window titles, input text, or file paths.
public struct WindowDiagnosticScreenSample: Sendable, Equatable {
    public let ownerName: String
    public let isSelfProcess: Bool
    public let layer: Int
    public let alpha: Double
    public let bounds: CGRect

    public init(ownerName: String, isSelfProcess: Bool, layer: Int, alpha: Double, bounds: CGRect) {
        self.ownerName = ownerName
        self.isSelfProcess = isSelfProcess
        self.layer = layer
        self.alpha = alpha
        self.bounds = bounds
    }

    public var summary: String {
        let who = isSelfProcess ? "self(\(ownerName))" : ownerName
        let x = Int(bounds.origin.x.rounded())
        let y = Int(bounds.origin.y.rounded())
        let w = Int(bounds.size.width.rounded())
        let h = Int(bounds.size.height.rounded())
        return "\(who)[L=\(layer),a=\(String(format: "%.2f", alpha)),(\(x),\(y),\(w)x\(h))]"
    }
}

/// Local-only, size-bounded diagnostic log for window lifecycle anomalies.
/// Never transmits data off-device and never records user content or window titles.
public final class WindowDiagnosticLog: @unchecked Sendable {
    public let fileURL: URL
    public let backupURL: URL
    private let maxBytes: Int
    private let queue = DispatchQueue(label: "app.kulahere.window-diagnostic-log", qos: .utility)
    private let pid = ProcessInfo.processInfo.processIdentifier
    private let versionLabel: String

    public init(directory: URL, maxBytes: Int = 512 * 1024) {
        self.fileURL = directory.appending(path: "window-lifecycle.log")
        self.backupURL = directory.appending(path: "window-lifecycle.1.log")
        self.maxBytes = max(4096, maxBytes)
        let version = ToolService.currentAppVersion
        let build = ToolService.currentAppBuild
        self.versionLabel = build.isEmpty ? version : "\(version)(\(build))"
    }

    public func record(_ event: String, fields: [(String, String)] = []) {
        let timestamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current,
                                                    formatOptions: [.withInternetDateTime, .withFractionalSeconds])
        let sanitizedEvent = Self.sanitize(event)
        var parts = ["\(timestamp)", "pid=\(pid)", "v=\(versionLabel)", "event=\(sanitizedEvent)"]
        for (key, value) in fields where !key.isEmpty {
            parts.append("\(Self.sanitize(key))=\(Self.sanitize(value))")
        }
        let line = parts.joined(separator: " ") + "\n"
        let fileURL = self.fileURL
        let backupURL = self.backupURL
        let maxBytes = self.maxBytes
        queue.async {
            Self.append(line, to: fileURL, backup: backupURL, maxBytes: maxBytes)
        }
    }

    /// Waits for all queued local writes to complete (used by tests).
    public func flush() {
        queue.sync {}
    }

    private static func sanitize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func append(_ line: String, to fileURL: URL, backup backupURL: URL, maxBytes: Int) {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = line.data(using: .utf8) else { return }
        if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue + data.count > maxBytes {
            try? fm.removeItem(at: backupURL)
            try? fm.moveItem(at: fileURL, to: backupURL)
        }
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: data)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {}
    }
}

extension ToolService {
    /// Captures on-screen windows belonging to Asky or overlapping `quartzRect`.
    /// Only records process name, layer, alpha, and bounds — never window titles.
    public static func sampleOnScreenWindows(near quartzRect: CGRect) -> [WindowDiagnosticScreenSample] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return filterDiagnosticWindowSamples(info, near: quartzRect,
                                             selfPID: ProcessInfo.processInfo.processIdentifier)
    }

    static func filterDiagnosticWindowSamples(_ entries: [[String: Any]], near quartzRect: CGRect,
                                              selfPID: Int32) -> [WindowDiagnosticScreenSample] {
        var result: [WindowDiagnosticScreenSample] = []
        for entry in entries {
            guard let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 0, bounds.height > 0 else { continue }
            let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1
            let isSelf = pid == selfPID
            guard isSelf || bounds.intersects(quartzRect) else { continue }
            let owner = (entry[kCGWindowOwnerName as String] as? String) ?? "unknown"
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            result.append(WindowDiagnosticScreenSample(ownerName: owner, isSelfProcess: isSelf,
                                                       layer: layer, alpha: alpha, bounds: bounds))
        }
        return result
    }
}
