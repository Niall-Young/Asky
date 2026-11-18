import AppKit
import CryptoKit
import LocalStore
import Resources
import ToolService

/// Watches `NSPasteboard.changeCount` (cheap integer poll) and records text, images and original file references.
/// Skips concealed or transient content, password managers and user-excluded apps.
@MainActor
final class ClipboardMonitor {
    static let maxImageBytes = 20 * 1024 * 1024

    private let app: AppModel
    private var timer: Timer?
    private var lastCleanup = Date.distantPast
    private var lastChange = ClipboardAccess.changeCount

    init(app: AppModel) { self.app = app }

    func start() {
        guard timer == nil else { return }
        lastChange = ClipboardAccess.changeCount
        let t = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let now = Date()
        if now.timeIntervalSince(lastCleanup) >= 60 {
            Self.cleanup(app.clipboardStore)
            ClipboardAccess.cleanExpiredDragFiles(now: now)
            lastCleanup = now
        }
        guard ClipboardAccess.changeCount != lastChange else { return }
        let snapshot = ClipboardAccess.snapshot()
        lastChange = snapshot.changeCount
        let settings = app.settings
        guard settings.clipboardEnabled, !snapshot.concealed, !snapshot.restoredFromHistory else { return }
        if let bid = snapshot.sourceBundleID, settings.clipboardExcludedApps.contains(bid) { return }
        let sourceApp = snapshot.sourceName
        let sourceBundleID = snapshot.sourceBundleID
        let store = app.clipboardStore
        let dir = app.store.clipboardDirectory

        if !snapshot.fileURLs.isEmpty {
            let paths = snapshot.fileURLs.map(\.path)
            let data = Data(JSONText.encode(paths).utf8)
            let names = snapshot.fileURLs.map(\.lastPathComponent).joined(separator: "\n")
            let item = ClipboardItem(kind: .file, text: names, filePath: paths.first, filePaths: paths,
                                            byteSize: data.count, sourceApp: sourceApp, sourceBundleID: sourceBundleID,
                                            contentHash: "files:" + Self.hash(data))
            guard ClipboardAccess.isAvailable(item) else { return }
            try? store.insert(item)
        } else if snapshot.image == nil, let text = snapshot.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let data = Data(text.utf8)
            try? store.insert(ClipboardItem(kind: .text, text: text, byteSize: data.count, sourceApp: sourceApp,
                                            sourceBundleID: sourceBundleID, contentHash: Self.hash(data)))
        } else if let data = snapshot.image, data.count <= Self.maxImageBytes {
            // Disk I/O and thumbnailing off the main thread.
            Task.detached(priority: .utility) {
                ClipboardAccess.storeImage(data, in: dir, store: store, sourceApp: sourceApp,
                    sourceBundleID: sourceBundleID, contentHash: Self.hash(data))
            }
        }
    }

    nonisolated static func hash(_ d: Data) -> String {
        SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    /// Configured retention for all rows; 200 MiB budget for unpinned rows. Removes only owned image assets.
    static func cleanup(_ store: ClipboardStore) {
        removeFiles((try? store.cleanup()) ?? [])
    }

    static func removeFiles(_ paths: [String]) {
        ClipboardAccess.removeFiles(paths)
    }
}
