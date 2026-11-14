import Foundation
import LocalStore
import UniformTypeIdentifiers

extension ClipboardAccess {
    public struct SearchPage: Sendable {
        public let items: [ClipboardItem]
        public let cursor: ClipboardItem?
        public let hasMore: Bool
    }

    /// Scan bounded database batches on the caller's executor, checking cancellation between rows.
    /// The cursor tracks scanned rows, including unavailable and unmatched records.
    nonisolated public static func searchPage(in store: ClipboardStore, query: String,
        limit: Int = 40, before: ClipboardItem? = nil) -> SearchPage {
        guard limit > 0 else { return SearchPage(items: [], cursor: before, hasMore: false) }
        let tokens = FTSQuery.tokens(query)
        var result: [ClipboardItem] = []
        var cursor = before
        while !Task.isCancelled {
            let batch = store.page(limit: 128, before: cursor)
            for item in batch {
                guard !Task.isCancelled else { return SearchPage(items: [], cursor: before, hasMore: false) }
                cursor = item
                guard isAvailable(item), matches(item, tokens: tokens) else { continue }
                result.append(item)
                if result.count == limit { return SearchPage(items: result, cursor: cursor, hasMore: true) }
            }
            if batch.count < 128 { break }
        }
        return SearchPage(items: result, cursor: cursor, hasMore: false)
    }

    nonisolated public static func search(in store: ClipboardStore, query: String, limit: Int = 100) -> [ClipboardItem] {
        searchPage(in: store, query: query, limit: limit).items
    }

    nonisolated private static func matches(_ item: ClipboardItem, tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return true }
        let kindNames: String
        switch item.kind {
        case .text: kindNames = "文本 Text"
        case .image: kindNames = "图片 Image Images"
        case .file: kindNames = "文件 File Files"
        }
        let basic = [item.text, item.kind == .image ? item.imageTitle : nil, item.sourceApp, kindNames]
            .compactMap { $0 }.joined(separator: " ")
        let unmatched = tokens.filter { !basic.localizedCaseInsensitiveContains($0) }
        if unmatched.isEmpty { return true }
        guard item.kind != .text else { return false }
        let paths = item.kind == .file ? item.filePaths : [item.filePath].compactMap { $0 }
        guard paths.count == 1, let path = paths.first else { return false }
        let extensionName = URL(filePath: path).pathExtension
        let type = UTType(filenameExtension: extensionName)
        let names = [information(for: item).typeName, type?.localizedDescription, extensionName,
                     type?.conforms(to: .movie) == true ? "视频 Video" : nil]
            .compactMap { $0 }.joined(separator: " ")
        return unmatched.allSatisfy { names.localizedCaseInsensitiveContains($0) }
    }
}
