import AppKit
import Foundation
import UniformTypeIdentifiers

/// Explicit user-initiated share card image export (clipboard, save panel, temporary share file).
@MainActor
public enum ShareImageService {
    public static func defaultFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Asky-\(formatter.string(from: date)).png"
    }

    @discardableResult
    public static func copyPNG(_ data: Data) -> Bool {
        guard !data.isEmpty, let image = NSImage(data: data) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        if let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        return pasteboard.writeObjects([item])
    }

    public static func savePNG(_ data: Data, suggestedName: String = defaultFileName(), for window: NSWindow? = nil) async throws -> URL? {
        guard !data.isEmpty else { throw CocoaError(.fileWriteUnknown) }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedName.hasSuffix(".png") ? suggestedName : "\(suggestedName).png"
        if let downloads = try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true) {
            panel.directoryURL = downloads
        }
        let response: NSApplication.ModalResponse
        if let window {
            response = await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: window) { result in
                    continuation.resume(returning: result)
                }
            }
        } else {
            response = panel.runModal()
        }
        guard response == .OK, let destination = panel.url else { return nil }
        try data.write(to: destination, options: .atomic)
        return destination
    }

    public static func writeTemporarySharePNG(_ data: Data, suggestedName: String = defaultFileName()) throws -> URL {
        guard !data.isEmpty else { throw CocoaError(.fileWriteUnknown) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "AskyShare", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cleanupExpiredShareFiles(in: directory)
        let baseName = suggestedName.hasSuffix(".png") ? String(suggestedName.dropLast(4)) : suggestedName
        let uniqueName = "\(baseName)-\(UUID().uuidString.prefix(8)).png"
        let url = directory.appending(path: uniqueName)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func cleanupExpiredShareFiles(in directory: URL) {
        let cutoff = Date().addingTimeInterval(-3600)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles
        ) else { return }
        for url in urls {
            if let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
