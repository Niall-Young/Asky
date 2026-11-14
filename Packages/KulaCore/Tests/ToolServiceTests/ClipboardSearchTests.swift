import AppKit
import Testing
import LocalStore
@testable import ToolService

@Suite @MainActor struct ClipboardSearchTests {
    @Test(arguments: ClipboardRetention.allCases)
    func expiredRowsAreHiddenBeforeCleanup(retention: ClipboardRetention) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClipboardStore(try LocalStore(inMemoryWithRoot: root), retention: retention)
        let cutoff = Date().addingTimeInterval(-retention.interval)
        for (hash, date) in [("expired", cutoff.addingTimeInterval(-1)), ("recent", cutoff.addingTimeInterval(60))] {
            try store.insert(ClipboardItem(kind: .text, text: "retention \(hash)", byteSize: 1,
                pinned: true, contentHash: hash, createdAt: date))
        }
        #expect(store.recent(limit: 10).count == 2)
        for query in ["", "retention"] {
            #expect(ClipboardAccess.search(in: store, query: query).map(\.contentHash) == ["recent"])
        }
    }
    @Test func sourceAndTypeCanBeCombinedWithoutSearchingDimensions() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClipboardStore(try LocalStore(inMemoryWithRoot: root))
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 36,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let path = root.appending(path: "fixture.tiff")
        try #require(bitmap.tiffRepresentation).write(to: path)
        let image = ClipboardItem(kind: .image, filePath: path.path, byteSize: 1,
            sourceApp: "微信", contentHash: "picture", createdAt: Date().addingTimeInterval(-200))
        try store.insert(image)
        for i in 0..<105 {
            try store.insert(ClipboardItem(kind: .text, text: "unrelated \(i)", byteSize: 1,
                                          contentHash: "text-\(i)"))
        }
        for query in ["图片", "微信", "TIFF", "tiff", "微信 TIFF", "图片 微信", "微信 TIFF 图片", image.imageTitle, String(image.imageTitle.prefix(4)), "\(image.imageTitle) 微信 TIFF"] {
            #expect(ClipboardAccess.search(in: store, query: query).map(\.id) == [image.id])
        }
        #expect(ClipboardAccess.search(in: store, query: "64 × 36").isEmpty)
        #expect(ClipboardAccess.search(in: store, query: "Safari TIFF").isEmpty)
        #expect(ClipboardAccess.search(in: store, query: "微信", limit: 0).isEmpty)
        let text = ClipboardItem(kind: .text, text: "微信 TIFF notes", byteSize: 1, contentHash: "literal")
        try store.insert(text)
        #expect(ClipboardAccess.search(in: store, query: "微信 TIFF").map(\.id) == [text.id, image.id])
        #expect(ClipboardAccess.search(in: store, query: "微信 TIFF", limit: 1).map(\.id) == [text.id])
    }
    @Test func unavailableOriginalsAreHiddenBeforeLimitingAndRecoverWithoutDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClipboardStore(try LocalStore(inMemoryWithRoot: root))
        let file = root.appending(path: "recover.txt")
        let valid = ClipboardItem(kind: .text, text: "fixture valid", byteSize: 1,
                                  contentHash: "valid", createdAt: Date().addingTimeInterval(-200))
        try store.insert(valid)
        for i in 0..<260 {
            try store.insert(ClipboardItem(kind: .file, text: "fixture missing", filePaths: [file.path],
                byteSize: 1, sourceApp: "Finder", contentHash: "missing-\(i)"))
        }
        for query in ["", "fixture", "Finder", "文件"] {
            let results = ClipboardAccess.search(in: store, query: query, limit: 1)
            #expect(results.map(\.id) == (query.isEmpty || query == "fixture" ? [valid.id] : []))
        }
        #expect(ClipboardAccess.search(in: store, query: "", limit: 0).isEmpty)
        #expect(store.recent(limit: 300).count == 261)
        try Data("recovered".utf8).write(to: file)
        #expect(ClipboardAccess.search(in: store, query: "Finder", limit: 1).count == 1)
        let group = ClipboardItem(kind: .file, filePaths: [file.path, root.appending(path: "missing").path],
                                  byteSize: 1, contentHash: "group")
        #expect(!ClipboardAccess.isAvailable(group))
        #expect(!ClipboardAccess.isAvailable(ClipboardItem(kind: .text, text: "  ", byteSize: 1, contentHash: "empty")))
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let original = root.appending(path: "original.img")
        let thumb = root.appending(path: "thumb.png")
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: original)
        try png.write(to: thumb)
        let image = ClipboardItem(kind: .image, filePath: original.path, thumbPath: thumb.path,
                                  byteSize: png.count, contentHash: "image")
        try store.insert(image)
        #expect(ClipboardAccess.isAvailable(image))
        try Data("corrupt".utf8).write(to: original)
        #expect(!ClipboardAccess.isAvailable(image))
        #expect(ClipboardAccess.search(in: store, query: "图片").isEmpty)
        try FileManager.default.removeItem(at: original)
        #expect(!ClipboardAccess.isAvailable(image))
        #expect(FileManager.default.fileExists(atPath: thumb.path))
    }

    @Test func pagesPassOneHundredWithoutDuplicatesOrInsertionDrift() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClipboardStore(try LocalStore(inMemoryWithRoot: root))
        let time = Date()
        for index in 0..<165 {
            try store.insert(ClipboardItem(id: String(format: "%04d", index), kind: .text,
                text: "page fixture \(index)", byteSize: 1, contentHash: "page-\(index)", createdAt: time))
        }
        var page = ClipboardAccess.searchPage(in: store, query: "fixture", limit: 40)
        #expect(page.items.count == 40)
        var ids = page.items.map(\.id)
        try store.insert(ClipboardItem(kind: .text, text: "fixture newly captured", byteSize: 1,
            contentHash: "new", createdAt: time.addingTimeInterval(1)))
        while page.hasMore {
            page = ClipboardAccess.searchPage(in: store, query: "fixture", limit: 40, before: page.cursor)
            ids += page.items.map(\.id)
        }
        #expect(ids.count == 165)
        #expect(Set(ids).count == 165)
        #expect(ids == (0..<165).reversed().map { String(format: "%04d", $0) })
    }

    @Test func cancelledSearchReturnsNoStalePage() async throws {
        let store = ClipboardStore(try LocalStore(inMemoryWithRoot: FileManager.default.temporaryDirectory))
        try store.insert(ClipboardItem(kind: .text, text: "cancel fixture", byteSize: 1, contentHash: "cancel"))
        let worker = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return ClipboardAccess.searchPage(in: store, query: "fixture")
        }
        let page = await worker.value
        #expect(page.items.isEmpty)
        #expect(!page.hasMore)
    }

}
