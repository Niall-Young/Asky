import CoreGraphics
import Foundation
import Testing
@testable import ToolService

@Suite("WindowDiagnosticLog")
struct WindowDiagnosticLogTests {
    @Test("writes sanitized local entries and rotates when exceeding maxBytes")
    func writesAndRotatesLocally() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "asky-window-diag-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dir) }

        let log = WindowDiagnosticLog(directory: dir, maxBytes: 4096)
        log.record("app-launch", fields: [("note", "line1\nline2\ttab")])
        log.flush()

        let initial = try String(contentsOf: log.fileURL, encoding: .utf8)
        #expect(initial.contains("event=app-launch"))
        #expect(initial.contains("note=line1 line2 tab"))
        #expect(!FileManager.default.fileExists(atPath: log.backupURL.path))

        // Exceed maxBytes to trigger rotation to window-lifecycle.1.log.
        let payload = String(repeating: "a", count: 500)
        for i in 0..<12 {
            log.record("burst-\(i)", fields: [("pad", payload)])
        }
        log.flush()

        #expect(FileManager.default.fileExists(atPath: log.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: log.backupURL.path))
        let currentSize = (try FileManager.default.attributesOfItem(atPath: log.fileURL.path)[.size] as? NSNumber)?.intValue ?? 0
        #expect(currentSize <= 4096)
    }

    @Test("filters screen window samples by bounds or self PID without reading window titles")
    func filtersScreenSamplesWithoutTitles() {
        let region = CGRect(x: 400, y: 200, width: 680, height: 500)
        let entries: [[String: Any]] = [
            // Self window outside region: still included
            [
                kCGWindowOwnerPID as String: NSNumber(value: 100),
                kCGWindowOwnerName as String: "Asky",
                kCGWindowName as String: "Secret Title",
                kCGWindowLayer as String: NSNumber(value: 3),
                kCGWindowAlpha as String: NSNumber(value: 1.0),
                kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 100, height: 50).dictionaryRepresentation as Any,
            ],
            // Other app window intersecting region: included, title ignored
            [
                kCGWindowOwnerPID as String: NSNumber(value: 200),
                kCGWindowOwnerName as String: "SCIM",
                kCGWindowName as String: "Private Candidate",
                kCGWindowLayer as String: NSNumber(value: 20),
                kCGWindowAlpha as String: NSNumber(value: 0.95),
                kCGWindowBounds as String: CGRect(x: 420, y: 260, width: 220, height: 300).dictionaryRepresentation as Any,
            ],
            // Unrelated window outside region: excluded
            [
                kCGWindowOwnerPID as String: NSNumber(value: 300),
                kCGWindowOwnerName as String: "Finder",
                kCGWindowLayer as String: NSNumber(value: 0),
                kCGWindowAlpha as String: NSNumber(value: 1.0),
                kCGWindowBounds as String: CGRect(x: 10, y: 10, width: 100, height: 100).dictionaryRepresentation as Any,
            ],
        ]

        let samples = ToolService.filterDiagnosticWindowSamples(entries, near: region, selfPID: 100)
        #expect(samples.count == 2)
        #expect(samples[0].isSelfProcess)
        #expect(samples[0].ownerName == "Asky")
        #expect(!samples[0].summary.contains("Secret"))
        #expect(!samples[1].isSelfProcess)
        #expect(samples[1].ownerName == "SCIM")
        #expect(!samples[1].summary.contains("Private"))
    }
}
