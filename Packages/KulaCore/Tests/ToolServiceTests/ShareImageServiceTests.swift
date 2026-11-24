import AppKit
import Foundation
import Testing
@testable import ToolService

@Suite("ShareImageService")
struct ShareImageServiceTests {
    private func samplePNGData() -> Data {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        let tiff = image.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        return rep.representation(using: .png, properties: [:])!
    }

    @Test("Default file name uses Asky prefix and png extension")
    @MainActor
    func defaultFileNameFormat() {
        let name = ShareImageService.defaultFileName(date: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(name.hasPrefix("Asky-"))
        #expect(name.hasSuffix(".png"))
    }

    @Test("Write temporary share PNG creates readable PNG file")
    @MainActor
    func writeTemporarySharePNG() throws {
        let png = samplePNGData()
        let url = try ShareImageService.writeTemporarySharePNG(png, suggestedName: "Asky-test.png")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(FileManager.default.fileExists(atPath: url.path))
        let readBack = try Data(contentsOf: url)
        #expect(readBack == png)
    }

    @Test("Copy PNG rejects empty data")
    @MainActor
    func copyRejectsEmptyData() {
        #expect(ShareImageService.copyPNG(Data()) == false)
    }
}
