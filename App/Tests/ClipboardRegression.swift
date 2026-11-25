import AppKit
import SwiftUI
import LocalStore
import ToolService
import AVKit
import Search

@main @MainActor
enum ClipboardRegression {
    static var receiverWindow: NSWindow?
    static var receiverTimer: Timer?

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        if let index = CommandLine.arguments.firstIndex(of: "--paste-receiver") {
            startPasteReceiver(at: URL(filePath: CommandLine.arguments[index + 1]))
            application.run()
            return
        }
        Task { @MainActor in
            do {
                if CommandLine.arguments.contains("--pagination") {
                    try await verifyPagination()
                    exit(0)
                }
                if CommandLine.arguments.contains("--availability") {
                    try await verifyAvailability()
                    exit(0)
                }
                if CommandLine.arguments.contains("--delete-shortcut") {
                    try await verifyDeleteShortcut()
                    exit(0)
                }
                if CommandLine.arguments.contains("--clear-all") {
                    try await verifyClearAll()
                    exit(0)
                }
                if CommandLine.arguments.contains("--local-paste-target") {
                    try await verifyLocalPasteTarget()
                    exit(0)
                }
                if CommandLine.arguments.contains("--paste-target") {
                    try await verifyPasteTarget()
                    exit(0)
                }
                if CommandLine.arguments.contains("--drag-paste-target") {
                    try await verifyDragPasteTarget()
                    exit(0)
                }
                if CommandLine.arguments.contains("--external-drag") {
                    try await verifyExternalDrag()
                    exit(0)
                }
                if CommandLine.arguments.contains("--external-paste") {
                    try await verifyExternalPaste()
                    exit(0)
                }
                if CommandLine.arguments.contains("--toast-surfaces") {
                    try await verifyToastSurfaces()
                    exit(0)
                }
                let root = FileManager.default.temporaryDirectory.appending(path: "Asky-clipboard-\(UUID())")
                let app = try AppModel(root: root)
                let store = ClipboardStore(app.store)
                let text = ClipboardItem(kind: .text, text: "Paste anywhere, this is one example text", byteSize: 42,
                                         sourceApp: "Safari", contentHash: "short", createdAt: Date().addingTimeInterval(4))
                let image = NSImage(size: NSSize(width: 640, height: 360))
                image.lockFocus()
                NSGradient(starting: .systemBlue, ending: .systemTeal)?.draw(in: NSRect(x: 0, y: 0, width: 640, height: 360), angle: 35)
                NSColor.white.setFill()
                NSBezierPath(ovalIn: NSRect(x: 220, y: 80, width: 200, height: 200)).fill()
                image.unlockFocus()
                let path = root.appending(path: "fixture.tiff")
                try image.tiffRepresentation!.write(to: path)
                if CommandLine.arguments.contains("--chat-images") {
                    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
                    let monitor = ClipboardMonitor(app: app)
                    monitor.start()
                    for fileOnly in [false, true] {
                        let original = root.appending(path: "img_v3_02167_827d327e.jpg")
                        try bitmap.representation(using: .jpeg, properties: [:])!.write(to: original)
                        NSPasteboard.general.clearContents()
                        if fileOnly {
                            NSPasteboard.general.writeObjects([original as NSURL])
                        } else {
                            NSPasteboard.general.setData(image.tiffRepresentation!, forType: .tiff)
                        }
                        NSPasteboard.general.setString(original.lastPathComponent, forType: .string)
                        let expectedCount = fileOnly ? 2 : 1
                        for _ in 0..<50 {
                            if store.recent(limit: 10).count == expectedCount { break }
                            try await Task.sleep(for: .milliseconds(100))
                        }
                        let items = store.recent(limit: 10)
                        precondition(items.count == expectedCount && items.allSatisfy { $0.kind == .image },
                                     "chat image plus filename must record an image")
                        let recorded = items.first!
                        try FileManager.default.removeItem(at: original)
                        precondition(recorded.thumbPath.flatMap(NSImage.init(contentsOfFile:)) != nil,
                                     "chat image must have a usable thumbnail")
                        precondition(ClipboardAccess.copy(recorded), "image must copy after source file removal")
                        let restored = NSBitmapImageRep(data: ClipboardAccess.snapshot().image!)!
                        precondition(restored.pixelsWide == bitmap.pixelsWide && restored.pixelsHigh == bitmap.pixelsHigh,
                                     "copy must restore image pixels instead of filename")
                        try await Task.sleep(for: .milliseconds(1200))
                        precondition(store.recent(limit: 10).count == expectedCount, "restore must not add a text row")
                    }
                    monitor.stop()
                    let controller = ClipboardController(app: app)
                    controller.pinned = true
                    controller.show()
                    try await waitForSearch(controller)
                    try await Task.sleep(for: .milliseconds(500))
                    let view = application.windows.first { $0.title == "剪贴板历史" }!.contentView!
                    view.layoutSubtreeIfNeeded()
                    let capture = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                    view.cacheDisplay(in: view.bounds, to: capture)
                    try capture.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/clipboard-chat-images.png"))
                    print("Chat image monitoring, thumbnails, temporary-file survival and image copy passed")
                    application.terminate(nil)
                    return
                }
                let picture = ClipboardItem(kind: .image, filePath: path.path, byteSize: 1000, sourceApp: "Safari",
                                            contentHash: "picture", createdAt: Date().addingTimeInterval(3))
                try store.insert(text)
                try store.insert(picture)
                try store.insert(ClipboardItem(kind: .text, text: String(repeating: "完整文字可以滚动查看。\n", count: 60), byteSize: 2000,
                                               contentHash: "long", createdAt: Date().addingTimeInterval(2)))
                try store.insert(ClipboardItem(kind: .text, text: "Another clipboard card", byteSize: 22, contentHash: "fourth"))
                if CommandLine.arguments.contains("--colors") {
                    for (input, expected) in [("#f80", "#FF8800"), (" #aBcD\n", "#AABBCCDD"),
                                              ("#123456", "#123456"), ("#12345678", "#12345678"),
                                              ("rgb(255, 147, 23)", "#FF9317"), ("RGB(100% 0% 0% / 50%)", "#FF000080"),
                                              ("rgba(255, 0, 0, .5)", "#FF000080"), ("rgb(1e2 0 0)", "#640000"),
                                              ("hsl(120, 100%, 50%)", "#00FF00"), ("hsla(240 100% 50% / .5)", "#0000FF80"),
                                              ("hsl(-.5turn 100% 50%)", "#00FFFF"), ("hsl(200grad 100% 50%)", "#00FFFF"),
                                              ("oklch(62.7955% 0.257683 29.2338)", "#FF0000"),
                                              ("oklch(62.7955% 64.42075% 29.2338 / 50%)", "#FF000080")] {
                        let original = ClipboardItem(kind: .text, text: input, byteSize: input.utf8.count, contentHash: input)
                        let parsed = ClipboardColor(item: original)
                        precondition(parsed?.hex == expected, "Wrong color for \(input): \(parsed?.hex ?? "nil")")
                        precondition(parsed?.text == input && original.text == input, "Preview must preserve original notation")
                    }
                    for input in ["hello #ff8800", "#12345", "#gg8800", "FF9317", "34C467", "123456", "12345678",
                                  "f80", "abcd", "#１２３", "rgb(nan 0 0)", "rgb(inf 0 0)", "rgb(0xFF 0 0)",
                                  "rgb(255,,0,0)", "rgb(255 0 / .5)", "rgb(255 0 0 .5)", "rgb(1,2,3 / .5)",
                                  "hsl(120 100 50)", "hsl(120% 100% 50%)", "oklch(50%, .1, 20)",
                                  "rgb(255 0 0) extra", "red", String(repeating: " ", count: 2049) + "#fff"] {
                        precondition(ClipboardColor(item: ClipboardItem(kind: .text, text: input, byteSize: input.utf8.count, contentHash: input)) == nil,
                                     "Must stay plain text: \(input.prefix(100))")
                    }
                    precondition(ClipboardColor(item: ClipboardItem(kind: .file, text: "#FF8800", byteSize: 7, contentHash: "file-color")) == nil)
                    _ = try store.delete(ids: store.recent(limit: 20).map(\.id))
                    for value in ["rgb(255, 147, 23)", "hsl(120 100% 50%)", "oklch(62.7955% .257683 29.2338)", "FF9317", "#FFFFFF", "#000000", "#48A0FF80", "ordinary text"] {
                        try store.insert(ClipboardItem(kind: .text, text: value, byteSize: value.utf8.count, sourceApp: "Asky", contentHash: value))
                    }
                }
                let fileTest = CommandLine.arguments.contains("--files")
                let fileURLs = [root.appending(path: "复制文件.txt"), root.appending(path: "second.pdf")]
                if fileTest {
                    _ = try store.delete(ids: store.recent(limit: 20).map(\.id))
                    for url in fileURLs { try Data("real file: \(url.lastPathComponent)".utf8).write(to: url) }
                    let monitor = ClipboardMonitor(app: app)
                    monitor.start()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects(fileURLs.map { $0 as NSURL })
                    NSPasteboard.general.setString("复制文件.txt\nsecond.pdf", forType: .string)
                    for _ in 0..<30 {
                        if store.recent(limit: 1).first?.kind == .file { break }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    monitor.stop()
                    let recorded = store.recent(limit: 1).first!
                    precondition(recorded.kind == .file && recorded.filePaths == fileURLs.map(\.path), "monitor must prioritize complete file selection")
                    monitor.start()
                    precondition(ClipboardAccess.copy(recorded), "file selection must copy")
                    precondition(ClipboardAccess.snapshot().fileURLs == fileURLs, "copy must restore all URLs")
                    try await Task.sleep(for: .milliseconds(1200))
                    monitor.stop()
                    let afterRestore = store.recent(limit: 1).first!
                    precondition(afterRestore.id == recorded.id && afterRestore.createdAt == recorded.createdAt &&
                        afterRestore.sourceApp == recorded.sourceApp && afterRestore.sourceBundleID == recorded.sourceBundleID,
                        "restoring history must not overwrite source metadata or reorder the card")
                }
                let controller = ClipboardController(app: app, pasteTargetProvider: { .unavailable })
                let dragPreview = CommandLine.arguments.contains("--drag-preview")
                let dragTest = CommandLine.arguments.contains("--drag") || fileTest
                if CommandLine.arguments.contains("--preview") || CommandLine.arguments.contains("--layouts") || dragPreview || dragTest { controller.pinned = true }
                controller.show()
                try await waitForSearch(controller)
                if !CommandLine.arguments.contains("--preview"), !dragPreview { controller.pinned = true }
                try await Task.sleep(for: .milliseconds(400))
                @MainActor func panel() -> NSWindow { application.windows.first { $0.title == "剪贴板历史" }! }
                @MainActor func shellFrame() -> NSRect { panel().frame }
                @MainActor func snapshot(_ window: NSWindow, _ name: String) throws {
                    if CommandLine.arguments.contains("--video-preview") || name.hasPrefix("layout-actions-") {
                        // AVPlayer renders in a composited layer, absent from cacheDisplay bitmaps.
                        let capture = Process()
                        capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
                        capture.arguments = ["-x", "-l", String(window.windowNumber), "build/clipboard-\(name).png"]
                        try capture.run()
                        capture.waitUntilExit()
                        precondition(capture.terminationStatus == 0)
                        return
                    }
                    let view = window.contentView!
                    view.layoutSubtreeIfNeeded()
                    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/clipboard-\(name).png"))
                }
                if CommandLine.arguments.contains("--search-only") {
                    controller.updateLayout()
                    for word in ["img", "text", "video", "file"] {
                        let literal = ClipboardItem(kind: .text, text: "\(word) literal sample", byteSize: 20,
                                                    contentHash: "literal-\(word)-list")
                        try store.insert(literal)
                        controller.query = word + " literal"
                        try await waitForSearch(controller)
                        precondition(controller.query == word + " literal")
                        precondition(controller.items.contains { $0.id == literal.id }, "former commands search as literal text")
                        controller.query = word
                        try await waitForSearch(controller)
                        precondition(controller.items.contains { $0.id == literal.id }, "bare keywords show history results")
                    }
                    for query in [String(picture.imageTitle.prefix(4)), String(picture.imageTitle.prefix(10)),
                                  picture.imageTitle, "\(picture.imageTitle) Safari"] {
                        controller.query = query
                        try await waitForSearch(controller)
                        precondition(controller.items.contains { $0.id == picture.id },
                                     "image names must be searchable by year, partial/full timestamp and source")
                    }
                    try await Task.sleep(for: .milliseconds(250))
                    try snapshot(panel(), "image-name-search-list")
                    controller.query = ""
                    try await waitForSearch(controller)
                    try await Task.sleep(for: .milliseconds(250))
                    try snapshot(panel(), "search-only-list")
                    controller.query = "img literal"
                    try await waitForSearch(controller)
                    controller.escape()
                    precondition(!controller.isVisible, "Escape closes clipboard without a type scope")
                    controller.show()
                    try await waitForSearch(controller)
                    precondition(controller.query.isEmpty && !controller.items.isEmpty)
                    controller.hide()
                    print("Clipboard search-only passed: list layout, literal keywords, Escape and reopen")
                    application.terminate(nil)
                    return
                }
                if CommandLine.arguments.contains("--colors") {
                    for appearance in ["light", "dark"] {
                        app.preferences.appearance = appearance
                        controller.updateLayout()
                        controller.query = "rgb(255, 147, 23)"
                        try await waitForSearch(controller)
                        try await Task.sleep(for: .milliseconds(350))
                        try snapshot(panel(), "color-\(appearance)-list")
                    }
                    print("Color parsing, non-color rejection, list previews passed")
                    application.terminate(nil)
                    return
                }
                if CommandLine.arguments.contains("--video-preview") {
                    let url = URL(filePath: ProcessInfo.processInfo.environment["ASKY_CLIPBOARD_VIDEO_FIXTURE"]!)
                    let movie = ClipboardItem(kind: .file, text: url.lastPathComponent, filePath: url.path,
                        filePaths: [url.path], byteSize: 220, sourceApp: "微信", contentHash: "movie")
                    try store.insert(movie)
                    controller.query = url.lastPathComponent
                    try await waitForSearch(controller)
                    precondition(controller.selectedItem?.id == movie.id)
                    func previews(in view: NSView) -> [AVPlayerView] {
                        (view as? AVPlayerView).map { [$0] } ?? view.subviews.flatMap { previews(in: $0) }
                    }
                    @MainActor func verifyControlInsets(_ preview: AVPlayerView) async throws {
                        @MainActor func glass(in view: NSView) -> NSView? {
                            if view is NSGlassEffectView, view.bounds.width > 100, view.bounds.height >= 40 { return view }
                            return view.subviews.lazy.compactMap { glass(in: $0) }.first
                        }
                        let center = preview.window!.convertPoint(toScreen: preview.convert(
                            NSPoint(x: preview.bounds.midX, y: preview.bounds.midY), to: nil))
                        CGWarpMouseCursorPosition(CGPoint(x: center.x, y: NSScreen.screens[0].frame.maxY - center.y))
                        preview.mouseEntered(with: NSEvent.mouseEvent(with: .mouseMoved, location: .zero,
                            modifierFlags: [], timestamp: 0, windowNumber: preview.window!.windowNumber,
                            context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
                        let windowFrame = preview.window!.frame
                        let playerFrame = preview.convert(preview.bounds, to: nil)
                        @MainActor final class Frames {
                            var firstControlsFrame: NSRect?
                            var count = 0
                        }
                        let frames = Frames()
                        // Sample after the player's pre-display layout observer,
                        // rather than midway through AVKit's asynchronous updates.
                        let observer = CFRunLoopObserverCreateWithHandler(nil,
                            CFRunLoopActivity.beforeWaiting.rawValue, true, 1000) { _, _ in
                            MainActor.assumeIsolated {
                                precondition(preview.window!.frame == windowFrame &&
                                    preview.convert(preview.bounds, to: nil) == playerFrame,
                                    "hover window and video must not move when controls appear")
                                if let surface = glass(in: preview) {
                                    let frame = preview.convert(surface.bounds, from: surface)
                                    if let first = frames.firstControlsFrame {
                                        precondition(abs(frame.minY - first.minY) < 0.5,
                                            "controls must not jump between displayed frames")
                                    } else { frames.firstControlsFrame = frame }
                                    frames.count += 1
                                }
                            }
                        }
                        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
                        try await Task.sleep(for: .milliseconds(400))
                        CFRunLoopObserverInvalidate(observer)
                        precondition(frames.count > 0, "must sample displayed playback controls")
                        preview.layoutSubtreeIfNeeded()
                        guard let surface = glass(in: preview) else {
                            preconditionFailure("native floating controls must have a glass surface")
                        }
                        let frame = preview.convert(surface.bounds, from: surface)
                        let left = frame.minX - preview.bounds.minX
                        let right = preview.bounds.maxX - frame.maxX
                        let bottom = preview.isFlipped ? preview.bounds.maxY - frame.maxY : frame.minY - preview.bounds.minY
                        precondition(abs(left - right) < 1 && abs(left - bottom) < 1,
                            "floating controls must have equal left/right/bottom gaps: \(left), \(right), \(bottom)")
                        print("Video control gaps: \(left), \(right), \(bottom) pt")
                    }
                    controller.updateLayout()
                    try await Task.sleep(for: .seconds(3))
                    let listPreview = previews(in: panel().contentView!)
                    precondition(listPreview.count == 1 && (listPreview[0].player?.currentItem?.asset as? AVURLAsset)?.url == url)
                    let player = listPreview[0].player!
                    precondition(player.currentItem?.status == .readyToPlay && player.rate == 0)
                    player.play()
                    try await Task.sleep(for: .milliseconds(600))
                    precondition(player.currentTime().seconds > 0.1, "video playback must advance")
                    player.pause()
                    precondition(listPreview[0].bounds.height > 100)
                    let listSize = listPreview[0].bounds.size
                    precondition(listSize.height > 200, "list video must fill the preview height before controls appear")
                    try await verifyControlInsets(listPreview[0])
                    try await Task.sleep(for: .seconds(2))
                    precondition(listPreview[0].bounds.size == listSize,
                        "floating controls must not change the list video size")
                    print("Stable list video size: \(listSize)")
                    try snapshot(panel(), "video-list")
                    controller.query = "Another"
                    try await waitForSearch(controller)
                    try await Task.sleep(for: .milliseconds(300))
                    precondition(previews(in: panel().contentView!).isEmpty && player.currentItem == nil,
                        "switching selection removes movie preview and releases its asset")
                    controller.query = url.lastPathComponent
                    try await waitForSearch(controller)
                    controller.copySelection()
                    try await waitForSearch(controller)
                    precondition(ClipboardAccess.snapshot().fileURLs == [url], "video copies as original file")
                    controller.hide()
                    print("Video list previews, selection switching, dismissal and original-file copy passed")
                    application.terminate(nil)
                    return
                }

                if CommandLine.arguments.contains("--floating-actions") {
                    for index in 0..<24 {
                        try store.insert(ClipboardItem(kind: .text, text: "Floating actions row \(index + 1)",
                            byteSize: 24, contentHash: "floating-\(index)",
                            createdAt: Date().addingTimeInterval(Double(100 - index))))
                    }
                    controller.refresh()
                    try await waitForSearch(controller)
                    controller.updateLayout()
                    controller.pinned = true
                    panel().makeFirstResponder(nil)
                    panel().ignoresMouseEvents = true
                    for appearance in ["light", "dark"] {
                        app.preferences.appearance = appearance
                        controller.selection = 0
                        try await Task.sleep(for: .milliseconds(400))
                        for position in ["top", "last"] {
                            if position == "last" {
                                controller.moveSelection(controller.items.count - 1)
                                try await Task.sleep(for: .milliseconds(400))
                            }
                            let capture = Process()
                            capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
                            capture.arguments = ["-x", "-l", String(panel().windowNumber),
                                "build/clipboard-floating-\(appearance)-\(position).png"]
                            try capture.run()
                            capture.waitUntilExit()
                            precondition(capture.terminationStatus == 0)
                        }
                    }
                    print("Floating clipboard actions captured in light/dark at the top and final selection")
                    controller.hide()
                    application.terminate(nil)
                    return
                }
                if CommandLine.arguments.contains("--layouts") {
                    let legacy = try JSONDecoder().decode(SettingsPreferences.self, from: Data("{}".utf8))
                    let savedCards = try JSONDecoder().decode(SettingsPreferences.self,
                        from: Data(#"{"clipboardLayout":"cards","appearance":"dark"}"#.utf8))
                    precondition(savedCards.appearance == "dark", "retired layout must not discard other preferences")
                    let encoded = try JSONEncoder().encode(savedCards)
                    precondition(!String(decoding: encoded, as: UTF8.self).contains("clipboardLayout"))
                    precondition(legacy.appearance == "system")
                    precondition(panel().frame.height == 560)
                    // Layout callbacks run directly; isolate them from concurrent desktop input.
                    panel().makeFirstResponder(nil)
                    panel().resignKey()
                    panel().ignoresMouseEvents = true
                    controller.query = ""
                    try await waitForSearch(controller)
                    controller.selection = 1
                    let selectedID = controller.selectedItem!.id
                    controller.updateLayout()
                    try await Task.sleep(for: .milliseconds(400))
                    precondition(controller.selectedItem?.id == selectedID && panel().frame.height == 560)
                    guard let glass = panel().contentView as? GlassSurfaceView else {
                        preconditionFailure("clipboard list must use the search shell's AppKit glass")
                    }
                    precondition(glass.style == .regular && glass.tintColor == nil && panel().hasShadow)
                    try snapshot(panel(), "layout-list-image")
                    controller.selection = 2
                    try await Task.sleep(for: .milliseconds(200))
                    try snapshot(panel(), "layout-list-text")
                    // Exercise the rendered row mouse surface and the search field's Return delegate.
                    @MainActor func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
                        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, of: type) }
                    }
                    controller.selection = controller.items.firstIndex { $0.contentHash == "long" }!
                    try await Task.sleep(for: .milliseconds(300))
                    let detailScroll = descendants(panel().contentView!, of: NSScrollView.self)
                        .first { $0.bounds.width > 300 }!
                    let viewport = detailScroll.convert(detailScroll.bounds, to: panel().contentView!)
                    precondition(abs(viewport.maxX - panel().contentView!.bounds.maxX) < 1,
                                 "text scroll viewport must reach the right pane edge")
                    let document = detailScroll.documentView!
                    precondition(document.bounds.height > detailScroll.contentSize.height,
                                 "long text must remain scrollable")
                    detailScroll.flashScrollers()
                    try await Task.sleep(for: .milliseconds(120))
                    try snapshot(panel(), "layout-list-long-text-scroller")
                    let scrollerCapture = Process()
                    scrollerCapture.executableURL = URL(filePath: "/usr/sbin/screencapture")
                    scrollerCapture.arguments = ["-x", "-l", String(panel().windowNumber),
                                                "build/clipboard-layout-list-long-text-native.png"]
                    try scrollerCapture.run()
                    scrollerCapture.waitUntilExit()
                    precondition(scrollerCapture.terminationStatus == 0)
                    detailScroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
                    detailScroll.reflectScrolledClipView(detailScroll.contentView)
                    precondition(detailScroll.contentView.bounds.minY > 0, "long text must scroll")
                    let rows = descendants(panel().contentView!, of: ClipboardCardMouseView.self)
                    precondition(!rows.isEmpty)
                    controller.status = nil
                    let down = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                        timestamp: 0, windowNumber: panel().windowNumber, context: nil, eventNumber: 0,
                        clickCount: 1, pressure: 1)!
                    let up = NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [],
                        timestamp: 0, windowNumber: panel().windowNumber, context: nil, eventNumber: 0,
                        clickCount: 1, pressure: 0)!
                    let beforeClick = NSPasteboard.general.changeCount
                    rows[0].mouseDown(with: down)
                    rows[0].mouseUp(with: up)
                    precondition(controller.selectedItem?.id == controller.items[0].id)
                    precondition(NSPasteboard.general.changeCount == beforeClick && controller.status == nil,
                                 "single click must only select the row")
                    let doubleUp = NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [],
                        timestamp: 0, windowNumber: panel().windowNumber, context: nil, eventNumber: 0,
                        clickCount: 2, pressure: 0)!
                    rows[0].mouseDown(with: down)
                    rows[0].mouseUp(with: doubleUp)
                    precondition(NSPasteboard.general.string(forType: .string) == controller.items[0].text,
                                 "double click must copy the selected row")
                    precondition(controller.status == NSLocalizedString("已复制", comment: "") && controller.isVisible)
                    @MainActor func key(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags = []) {
                        panel().sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                            timestamp: 0, windowNumber: panel().windowNumber, context: nil,
                            characters: code == 40 ? "k" : "", charactersIgnoringModifiers: code == 40 ? "k" : "",
                            isARepeat: false, keyCode: code)!)
                    }
                    let targetID = controller.selectedItem!.id
                    key(35, [.option, .command])
                    precondition(controller.selectedItem?.id == targetID && controller.selectedItem?.pinned == false,
                                 "removed pin shortcut must not change the record")
                    precondition(controller.actionKinds == [.copy, .delete, .clearAll], "More always offers Copy, Delete and Clear All")
                    key(40, .command)
                    try await Task.sleep(for: .milliseconds(200))
                    precondition(controller.isActionsMenuPresented)
                    let shellFrame = panel().frame
                    let editor = panel().firstResponder
                    precondition(!(panel().childWindows ?? []).contains { $0.isVisible && abs($0.frame.width - LauncherLayout.actionsMenuWidth) < 1 },
                                 "More must share the main window instead of opening a child window")
                    precondition(panel().contentView!.bounds.contains(controller.actionsMenuFrame), "menu must fit inside the shell")
                    try snapshot(panel(), "layout-actions-menu")
                    for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                        panel().appearance = NSAppearance(named: appearance)
                        try await Task.sleep(for: .milliseconds(220))
                        try snapshot(panel(), "layout-actions-menu-\(name)")
                        key(53)
                        try await Task.sleep(for: .milliseconds(220))
                        precondition(!controller.isActionsMenuPresented && panel().frame == shellFrame)
                        precondition(panel().firstResponder === editor, "closing More must preserve search focus")
                        try snapshot(panel(), "layout-actions-footer-\(name)")
                        key(40, .command)
                        try await Task.sleep(for: .milliseconds(220))
                    }
                    panel().appearance = nil
                    if CommandLine.arguments.contains("--more-motion") {
                        let recording = Process()
                        recording.executableURL = URL(filePath: "/usr/sbin/screencapture")
                        let path = "build/clipboard-more-morph-\(UUID()).mov"
                        recording.arguments = ["-x", "-v", "-V", "4", "-l", String(panel().windowNumber), path]
                        try recording.run()
                        try await Task.sleep(for: .milliseconds(700))
                        key(53)
                        try await Task.sleep(for: .milliseconds(900))
                        key(40, .command)
                        try await Task.sleep(for: .milliseconds(900))
                        key(53)
                        try await Task.sleep(for: .milliseconds(900))
                        key(40, .command)
                        while recording.isRunning { try await Task.sleep(for: .milliseconds(100)) }
                        precondition(recording.terminationStatus == 0)
                        print("Clipboard More morph recording: \(path)")
                    }
                    // Appearance snapshots may let pointer hover choose a menu row.
                    controller.actionSelection = 0
                    key(125)
                    precondition(controller.actionSelection == 1, "menu must select Delete after moving down")
                    key(53)
                    precondition(!controller.isActionsMenuPresented && controller.isVisible, "Escape only closes the menu")
                    key(40, .command)
                    key(40, .command)
                    precondition(!controller.isActionsMenuPresented, "Cmd K toggles the menu")
                    key(40, .command)
                    controller.query = "Another"
                    try await waitForSearch(controller)
                    precondition(!controller.isActionsMenuPresented)
                    key(40, .command)
                    key(125)
                    key(36)
                    precondition(controller.items.isEmpty && !controller.isActionsMenuPresented)
                    key(40, .command)
                    precondition(!controller.isActionsMenuPresented, "empty results have no actions")
                    try store.insert(ClipboardItem(kind: .text, text: "Another clipboard card", byteSize: 22, contentHash: "replacement"))
                    controller.refresh()
                    try await waitForSearch(controller)
                    controller.query = "Another"
                    try await waitForSearch(controller)
                    try await Task.sleep(for: .milliseconds(200))
                    controller.status = nil
                    NSPasteboard.general.clearContents()
                    // Exercise Return through the panel's actual event routing.
                    key(36)
                    precondition(NSPasteboard.general.string(forType: .string) == nil,
                                 "Return without an input must leave the clipboard untouched")
                    precondition(controller.status == nil && controller.isVisible && !controller.hasPasteTarget,
                                 "Return without a target must leave the list open without pasting")
                    key(36, .command)
                    precondition(controller.status == NSLocalizedString("已复制", comment: "") && controller.isVisible,
                                 "Cmd Return must only copy and keep the list open")
                    try await Task.sleep(for: .milliseconds(200))
                    let toast = panel().childWindows!.first { $0.isVisible && $0.frame.minY > panel().frame.maxY }
                    precondition(toast != nil, "copy toast must be visible above the list")
                    try snapshot(toast!, "layout-list-copy-toast")
                    try snapshot(panel(), "layout-list-copy")
                    try await Task.sleep(for: .milliseconds(1000))
                    controller.copySelection()
                    try await waitForSearch(controller)
                    try await Task.sleep(for: .milliseconds(1000))
                    precondition(controller.status != nil && toast!.isVisible,
                                 "repeated copies must restart the toast lifetime")
                    try await Task.sleep(for: .milliseconds(1200))
                    precondition(controller.status == nil && !toast!.isVisible && controller.isVisible,
                                 "toast must disappear automatically without closing the list")
                    precondition(controller.items.count == 1)
                    controller.copySelection()
                    try await waitForSearch(controller)
                    precondition(NSPasteboard.general.string(forType: .string) == "Another clipboard card")
                    try snapshot(panel(), "layout-list")
                    print("Clipboard list selection, filtering, copy and More passed")
                    if CommandLine.arguments.contains("--layout-preview") {
                        try await Task.sleep(for: .seconds(300))
                    }
                    controller.hide()
                    app.settingsTab = SettingsPage.clipboard.rawValue
                    let settingsWindow = SettingsWindow.make(app: app)
                    settingsWindow.makeKeyAndOrderFront(nil)
                    try await Task.sleep(for: .milliseconds(500))
                    func scrollToClipboard(_ view: NSView) {
                        if let scroll = view as? NSScrollView, scroll.frame.width > 300,
                           let document = scroll.documentView {
                            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentSize.height)))
                            scroll.reflectScrolledClipView(scroll.contentView)
                        }
                        for child in view.subviews { scrollToClipboard(child) }
                    }
                    scrollToClipboard(settingsWindow.contentView!)
                    try await Task.sleep(for: .milliseconds(200))
                    try snapshot(settingsWindow, "layout-settings")
                    settingsWindow.orderOut(nil)
                    application.terminate(nil)
                    return
                }
                if dragPreview || dragTest {
                    // Keep the initial launch stable, then enable the real unpinned outside-click observer.
                    panel().makeKey()
                    controller.pinned = false
                }
                if dragTest {
                    let externalPoint = ProcessInfo.processInfo.environment["ASKY_CLIPBOARD_DROP_POINT"]?
                        .split(separator: ",").compactMap { Double($0) }
                    let draggingImage = ProcessInfo.processInfo.environment["ASKY_CLIPBOARD_DRAG_IMAGE"] == "1"
                    let screen = panel().screen!.visibleFrame
                    let destination = NSWindow(contentRect: NSRect(x: screen.minX + 24, y: screen.minY + 24,
                        width: 240, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
                    destination.title = "Clipboard drag destination"
                    let fileReceiver = ClipboardFileDropReceiver(frame: NSRect(x: 0, y: 0, width: 240, height: 160))
                    let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 160))
                    editor.isRichText = false
                    destination.contentView = fileTest ? fileReceiver : editor
                    if externalPoint == nil { destination.orderFrontRegardless() }
                    controller.pinned = false
                    panel().level = .popUpMenu
                    panel().makeKeyAndOrderFront(nil)
                    try await Task.sleep(for: .milliseconds(200))
                    func mouse(_ type: CGEventType, _ point: NSPoint) {
                        let location = CGPoint(x: point.x, y: NSScreen.screens[0].frame.maxY - point.y)
                        CGWarpMouseCursorPosition(location)
                        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location,
                            mouseButton: .left)
                        event?.flags = []
                        event?.post(tap: .cghidEventTap)
                    }
                    func dragCards(_ view: NSView) -> [ClipboardCardMouseView] {
                        if let card = view as? ClipboardCardMouseView { return [card] }
                        return view.subviews.flatMap(dragCards)
                    }
                    let sourceCards = dragCards(panel().contentView!).sorted {
                        $0.convert(.zero, to: nil).x < $1.convert(.zero, to: nil).x
                    }
                    let sourceCard = sourceCards[draggingImage ? 1 : 0]
                    let sourceRect = panel().convertToScreen(sourceCard.convert(sourceCard.bounds, to: nil))
                    let start = NSPoint(x: sourceRect.midX, y: sourceRect.midY)
                    let end: NSPoint
                    if let externalPoint {
                        precondition(externalPoint.count == 2, "ASKY_CLIPBOARD_DROP_POINT must be screen x,y")
                        end = NSPoint(x: externalPoint[0], y: NSScreen.screens[0].frame.maxY - externalPoint[1])
                    } else {
                        end = destination.convertToScreen(NSRect(x: 40, y: 80, width: 1, height: 1)).origin
                    }
                    let clipboardChangeBeforeDrag = ClipboardAccess.changeCount
                    mouse(.leftMouseDown, start)
                    try await Task.sleep(for: .milliseconds(150))
                    for step in 1...30 {
                        let progress = CGFloat(step) / 30
                        mouse(.leftMouseDragged, NSPoint(x: start.x + (end.x - start.x) * progress,
                            y: start.y + (end.y - start.y) * progress))
                        try await Task.sleep(for: .milliseconds(30))
                    }
                    try await Task.sleep(for: .milliseconds(150))
                    mouse(.leftMouseUp, end)
                    for _ in 0..<150 {
                        if !controller.isDragging { break }
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    try await Task.sleep(for: .milliseconds(500))
                    if externalPoint != nil {
                        print("External drop clipboard matches fixture:", NSPasteboard.general.string(forType: .string) == text.text)
                        try await Task.sleep(for: .seconds(3))
                    }
                    if externalPoint == nil {
                        precondition(ClipboardAccess.changeCount == clipboardChangeBeforeDrag,
                            "dragging must leave the system clipboard unchanged")
                        if fileTest {
                            precondition(fileReceiver.urls == fileURLs, "native destination must receive every original URL")
                            for url in fileReceiver.urls {
                                let received = try Data(contentsOf: url)
                                precondition(received == Data("real file: \(url.lastPathComponent)".utf8))
                            }
                        } else {
                            precondition(editor.string == text.text, "native text destination must receive the card contents")
                        }
                    }
                    if panel().isVisible {
                        fputs("Drag not accepted: source=\(start), destination=\(end), status=\(controller.status ?? "none")\n", stderr)
                    }
                    precondition(!panel().isVisible, "accepted unpinned drag must close the source panel")
                    destination.orderOut(nil)
                    try? FileManager.default.removeItem(at: root)
                    if fileTest { print("File monitor, history copy, real mouse multi-file drag and destination byte readback passed") }
                    print(externalPoint == nil ? "Clipboard real mouse drag, destination text and unpinned panel dismissal passed"
                        : "External destination accepted the clipboard drag; verify destination contents separately")
                    exit(0)
                }


                // Direct-callback regressions must not consume concurrent desktop keyboard/pointer input.
                panel().makeFirstResponder(nil)
                panel().resignKey()
                panel().ignoresMouseEvents = true
                controller.query = ""
                try await waitForSearch(controller)
                var settingsOpened = 0
                app.onOpenSettings = { settingsOpened += 1 }
                let comma = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                            timestamp: 0, windowNumber: panel().windowNumber,
                                            context: nil, characters: ",", charactersIgnoringModifiers: ",",
                                            isARepeat: false, keyCode: 43)!
                panel().sendEvent(comma)
                precondition(settingsOpened == 1, "clipboard Cmd-comma must reach Settings")
                let launcher = LauncherPanel()
                launcher.onOpenSettings = { settingsOpened += 1 }
                launcher.sendEvent(comma)
                precondition(settingsOpened == 2, "launcher Cmd-comma must reach Settings")
                let modifiedComma = NSEvent.keyEvent(with: .keyDown, location: .zero,
                    modifierFlags: [.command, .shift], timestamp: 0, windowNumber: 0, context: nil,
                    characters: "<", charactersIgnoringModifiers: ",", isARepeat: false, keyCode: 43)!
                precondition(!SettingsShortcut.matches(modifiedComma), "extra modifiers must not open Settings")
                if CommandLine.arguments.contains("--settings-shortcut") {
                    controller.hide()
                    try? FileManager.default.removeItem(at: root)
                    print("Launcher and clipboard Cmd-comma event routing passed")
                    exit(0)
                }
                precondition(controller.items.count == 4)
                precondition(panel().frame.height == 560 && panel().hasShadow, "panel is exactly the shadowed glass shell")
                precondition(controller.selection == 0, "first row is selected by default")
                controller.moveSelection(1)
                precondition(controller.selection == 1)
                controller.moveSelection(-5)
                precondition(controller.selection == 0)
                let notes = ClipboardAccess.sourceIcon(bundleID: "com.apple.Notes", name: "备忘录")
                precondition(notes != nil, "bundle ID resolves icons for apps that are not running")
                panel().makeFirstResponder(nil)
                for appearance in ["light", "dark"] {
                    controller.query = ""
                    try await waitForSearch(controller)
                    app.preferences.appearance = appearance
                    try await Task.sleep(for: .milliseconds(250))
                    try snapshot(panel(), appearance)
                }
                controller.query = "example"
                try await waitForSearch(controller)
                precondition(controller.items.count == 1 && controller.items.first?.id == text.id)
                controller.query = ""
                try await waitForSearch(controller)
                controller.pinned = false
                controller.togglePinned()
                precondition(panel().level == .floating)
                controller.togglePinned()
                precondition(panel().level == .normal)
                controller.hide()
                print("Clipboard list selection, search, pinning and appearance passed")
                application.terminate(nil)
            } catch { fputs("Clipboard regression failed: \(error)\n", stderr); exit(1) }
        }
        application.run()
    }

    private static func waitForSearch(_ controller: ClipboardController) async throws {
        let deadline = Date().addingTimeInterval(10)
        while controller.isLoading, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        precondition(!controller.isLoading, "Background clipboard search timed out")
    }

    private static func verifyPagination() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-pages-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let store = ClipboardStore(app.store)
        for index in 0..<165 {
            try store.insert(ClipboardItem(kind: .text, text: "fixture \(index)", byteSize: 1,
                contentHash: "page-\(index)", createdAt: Date().addingTimeInterval(Double(-index))))
        }
        let controller = ClipboardController(app: app, pasteTargetProvider: { .unavailable })
        // No visible list: exercise exactly one page request at a time.
        controller.refresh()
        try await waitForSearch(controller)
        precondition(controller.items.count == 40 && controller.hasMore)
        let selected = controller.selectedItem?.id
        while controller.hasMore {
            controller.loadMore()
            try await waitForSearch(controller)
        }
        precondition(controller.items.count == 165 && Set(controller.items.map(\.id)).count == 165)
        precondition(controller.selectedItem?.id == selected)
        controller.query = "no match"
        controller.query = "fixture 164"
        try await waitForSearch(controller)
        precondition(controller.items.count == 1 && controller.items[0].text == "fixture 164")
        controller.query = "obsolete"
        controller.hide()
        try await Task.sleep(for: .milliseconds(200))
        precondition(controller.items.isEmpty && !controller.isLoading)
        precondition(!LocalShortcutAction.allCases.contains { $0.rawValue == "history" })
        print("Clipboard pagination passed: 165 records, stable selection, latest query wins, hide cancels search")
    }

    private static func verifyAvailability() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-availability-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let store = ClipboardStore(app.store)
        let file = root.appending(path: "fixture.txt")
        let item = ClipboardItem(kind: .file, text: "fixture.txt", filePaths: [file.path], byteSize: 1, contentHash: "file")
        let text = ClipboardItem(kind: .text, text: "fixture text", byteSize: 1, contentHash: "text",
                                 createdAt: Date().addingTimeInterval(-1))
        try store.insert(item)
        try store.insert(text)
        let controller = ClipboardController(app: app, pasteTargetProvider: { .unavailable })
        controller.pinned = true
        controller.show()
        try await waitForSearch(controller)
        precondition(controller.items.map(\.id) == [text.id])
        try await Task.sleep(for: .milliseconds(150))
        let panel = NSApp.windows.first { $0.title == "剪贴板历史" }!
        let view = panel.contentView!
        view.layoutSubtreeIfNeeded()
        let capture = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: capture)
        try capture.representation(using: .png, properties: [:])!.write(
            to: URL(filePath: "build/clipboard-availability-list.png"))
        try Data("restored".utf8).write(to: file)
        controller.refresh()
        try await waitForSearch(controller)
        precondition(controller.items.count == 2 && controller.selectedItem?.id == text.id,
                     "returning file must not change the selected text")
        controller.selection = controller.items.firstIndex { $0.id == item.id }!
        // Disappear after display but before copy: remove stale row and preserve pasteboard.
        try FileManager.default.removeItem(at: file)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("keep", forType: .string)
        controller.copySelection()
        try await waitForSearch(controller)
        precondition(controller.items.map(\.id) == [text.id])
        precondition(NSPasteboard.general.string(forType: .string) == "keep")
        controller.query = "fixture.txt"
        try await waitForSearch(controller)
        controller.refresh()
        try await waitForSearch(controller)
        precondition(controller.items.isEmpty)
        precondition(store.recent(limit: 10).count == 2, "hidden rows must remain recoverable")
        controller.hide()
        let results = await ClipboardProvider(store: store).search("fixture", limit: 1)
        precondition(results.map { $0.target.identifier } == [text.id], "launcher filters before limiting")
        let monitor = ClipboardMonitor(app: app)
        monitor.start()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([file as NSURL])
        try await Task.sleep(for: .milliseconds(1500))
        monitor.stop()
        precondition(store.recent(limit: 10).count == 2, "monitor must not record missing file references")
        print("PASS: unavailable originals hidden in list and search; recovery, selection, copy race and monitor verified")
    }

    private static func verifyDeleteShortcut() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-delete-shortcut-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let store = ClipboardStore(app.store)
        let controller = ClipboardController(app: app, pasteTargetProvider: { .unavailable })
        controller.pinned = true
        for i in 0..<3 {
            try store.insert(ClipboardItem(kind: .text, text: "delete fixture \(i)", byteSize: 1,
                contentHash: "list-\(i)"))
        }
        controller.show()
        try await waitForSearch(controller)
        controller.query = "delete fixture"
        try await waitForSearch(controller)
        let panel = NSApp.windows.first { $0.title == "剪贴板历史" }!
        @MainActor func key(_ modifiers: NSEvent.ModifierFlags, repeatKey: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}",
                isARepeat: repeatKey, keyCode: 51)!
        }
        precondition(!controller.handleActionKey(key([])), "plain Backspace remains available for search")
        precondition(!controller.handleActionKey(key([.command, .shift])), "extra modifiers must not delete")
        let firstID = controller.selectedItem!.id
        panel.sendEvent(key(.command))
        precondition(!store.recent(limit: 10).contains { $0.id == firstID }, "Cmd Backspace deletes selected record")
        precondition(controller.items.count == 2 && controller.query == "delete fixture" && controller.isVisible)
        panel.sendEvent(key(.command, repeatKey: true))
        precondition(controller.items.count == 2, "holding shortcut must not delete additional records")
        controller.toggleActionsMenu()
        let nextID = controller.selectedItem!.id
        panel.sendEvent(key(.command))
        precondition(!controller.isActionsMenuPresented && controller.items.count == 1)
        precondition(!store.recent(limit: 10).contains { $0.id == nextID })
        panel.sendEvent(key(.command))
        panel.sendEvent(key(.command))
        precondition(controller.items.isEmpty, "shortcut is safe without a selection")
        controller.hide()
        print("PASS: Cmd Backspace deletes selection in list, closes More, ignores repeat and preserves query")
    }

    private static func verifyClearAll() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-clear-all-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        let store = ClipboardStore(app.store)
        let original = root.appending(path: "original.txt")
        try Data("keep".utf8).write(to: original)
        let controller = ClipboardController(app: app)
        for i in 0..<125 {
            try store.insert(ClipboardItem(kind: .text, text: "history \(i)", byteSize: 1,
                pinned: i == 0, contentHash: "text-\(i)"))
        }
        let image = root.appending(path: "owned.png")
        let thumb = root.appending(path: "thumb.png")
        try Data([1]).write(to: image)
        try Data([2]).write(to: thumb)
        try store.insert(ClipboardItem(kind: .image, filePath: image.path, thumbPath: thumb.path,
            byteSize: 1, contentHash: "image"))
        try store.insert(ClipboardItem(kind: .file, filePath: original.path, byteSize: 4, contentHash: "file"))
        controller.show()
        try await waitForSearch(controller)
        controller.query = "history 124"
        try await waitForSearch(controller)
        let panel = NSApp.windows.first { $0.title == "剪贴板历史" }!
        for approved in [false, true] {
            let task = Task { await controller.clearAll() }
            var overlay: AppDialogOverlay?
            for _ in 0..<50 {
                if let found = AppDialogPresenter.shared.activeOverlay(in: panel),
                   found.button(at: 0) != nil, found.button(at: 1) != nil {
                    overlay = found
                    break
                }
                try await Task.sleep(for: .milliseconds(25))
            }
            guard let overlay else { preconditionFailure("Clear All must present an in-window Liquid Glass dialog") }
            try await Task.sleep(for: .milliseconds(350))
            precondition(store.recent(limit: 1000).count == 127, "Opening confirmation must preserve history")
            if !approved {
                let url = URL(filePath: FileManager.default.currentDirectoryPath)
                    .appending(path: "build/clipboard-clear-all-list.png")
                let capture = Process()
                capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-o", "-l", String(panel.windowNumber), url.path]
                try capture.run()
                capture.waitUntilExit()
                precondition(capture.terminationStatus == 0)
            }
            overlay.button(at: approved ? 0 : 1)!.performClick(nil)
            await task.value
            if approved {
                precondition(store.recent(limit: 1000).isEmpty && store.search("history").isEmpty)
                precondition(controller.items.isEmpty)
                precondition(!FileManager.default.fileExists(atPath: image.path))
                precondition(!FileManager.default.fileExists(atPath: thumb.path))
            } else {
                precondition(store.recent(limit: 1000).count == 127)
                precondition(FileManager.default.fileExists(atPath: image.path))
            }
            precondition(FileManager.default.fileExists(atPath: original.path))
            precondition(panel.isVisible)
        }
        controller.hide()
        print("Clipboard Clear All: list confirmation, cancel, filtered >100 history, pinned items, assets and original files passed")
    }

    private static func startPasteReceiver(at root: URL) {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        EditMenu.install()
        let window = NSWindow(contentRect: NSRect(x: 120, y: 160, width: 440, height: 220),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Asky paste receiver"
        let rejectsDrag = CommandLine.arguments.contains("--reject-drag")
        if rejectsDrag { window.level = .statusBar }
        let text = rejectsDrag ? ClipboardPasteOnlyTextView(frame: NSRect(x: 20, y: 60, width: 400, height: 140))
            : NSTextView(frame: NSRect(x: 20, y: 60, width: 400, height: 140))
        text.string = rejectsDrag ? "" : "LeftRight"
        text.setSelectedRange(NSRange(location: rejectsDrag ? 0 : 4, length: 0))
        window.contentView!.addSubview(text)
        let button = NSButton(title: "Non-input focus", target: nil, action: nil)
        button.frame = NSRect(x: 20, y: 10, width: 160, height: 32)
        window.contentView!.addSubview(button)
        window.makeFirstResponder(text)
        window.makeKeyAndOrderFront(nil)
        application.activate()
        receiverWindow = window
        let drop = window.convertToScreen(text.frame)
        try? "\(drop.midX),\(drop.midY)".write(to: root.appending(path: "drop-point"), atomically: true, encoding: .utf8)
        let nonInput = window.convertToScreen(button.frame)
        try? "\(nonInput.midX),\(nonInput.midY)".write(to: root.appending(path: "noninput-point"), atomically: true, encoding: .utf8)
        var previous = ""
        receiverTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
            MainActor.assumeIsolated {
                let control = (try? String(contentsOf: root.appending(path: "control"), encoding: .utf8)) ?? ""
                if control != previous {
                    previous = control
                    if control == "blur" { window.makeFirstResponder(button) }
                    if control == "focus" { window.makeFirstResponder(text) }
                    if control == "quit" { exit(0) }
                }
                try? text.string.write(to: root.appending(path: "text"), atomically: true, encoding: .utf8)
                try? control.write(to: root.appending(path: "ack"), atomically: true, encoding: .utf8)
            }
        }
        try? "ready".write(to: root.appending(path: "ready"), atomically: true, encoding: .utf8)
    }

    private static func verifyPasteTarget() async throws {
        func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, of: type) }
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-paste-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let receiver = Process()
        receiver.executableURL = URL(filePath: ProcessInfo.processInfo.environment["ASKY_CLIPBOARD_RECEIVER"]!)
        receiver.arguments = ["--paste-receiver", root.path]
        try receiver.run()
        defer {
            receiver.terminate()
            try? FileManager.default.removeItem(at: root)
        }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: root.appending(path: "ready").path) { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        let targetApp = NSRunningApplication(processIdentifier: receiver.processIdentifier)!
        targetApp.activate(options: [.activateIgnoringOtherApps])
        for _ in 0..<100 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == receiver.processIdentifier { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        precondition(NSWorkspace.shared.frontmostApplication?.processIdentifier == receiver.processIdentifier,
                     "receiver must be the frontmost app")
        let target = ClipboardPasteTarget.capture()
        precondition(target.canPaste, "must detect the receiver's native text input (requires Accessibility)")
        let app = try AppModel(root: root.appending(path: "model"))
        let item = ClipboardItem(kind: .text, text: "PASTE", byteSize: 5, contentHash: "paste")
        try ClipboardStore(app.store).insert(item)
        let controller = ClipboardController(app: app)
        controller.show()
        try await waitForSearch(controller)
        controller.pinned = true
        try await Task.sleep(for: .milliseconds(150))
        precondition(controller.hasPasteTarget && controller.actionKinds.first == .copy)
        controller.toggleActionsMenu()
        precondition(controller.isActionsMenuPresented)
        try await Task.sleep(for: .milliseconds(250))
        let panel = NSApp.windows.first { $0.title == "剪贴板历史" }!
        if let bitmap = panel.contentView!.bitmapImageRepForCachingDisplay(in: panel.contentView!.bounds) {
            panel.contentView!.cacheDisplay(in: panel.contentView!.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(filePath: "build/clipboard-focused-footer.png"))
        }
        let menuCapture = Process()
        menuCapture.executableURL = URL(filePath: "/usr/sbin/screencapture")
        menuCapture.arguments = ["-x", "-l", String(panel.windowNumber), "build/clipboard-keep-open-menu.png"]
        try menuCapture.run()
        menuCapture.waitUntilExit()
        precondition(menuCapture.terminationStatus == 0)
        controller.performSelectedAction(0)
        try await Task.sleep(for: .milliseconds(120))
        let afterCopy = try String(contentsOf: root.appending(path: "text"), encoding: .utf8)
        precondition(afterCopy == "LeftRight",
                     "copy in More must not insert text")
        // Use the menu with an unpinned panel: releasing key focus must not destroy it.
        controller.pinned = false
        controller.query = "PASTE"
        try await waitForSearch(controller)
        let keptFrame = panel.frame
        let keptItem = controller.selectedItem?.id
        controller.toggleActionsMenu()
        controller.performSelectedAction(controller.actionKinds.firstIndex(of: .pasteKeepingOpen)!)
        try await Task.sleep(for: .milliseconds(650))
        let afterKeepOpen = try String(contentsOf: root.appending(path: "text"), encoding: .utf8)
        precondition(afterKeepOpen == "LeftPASTERight",
                     "keep-open menu action must insert at the external cursor")
        precondition(controller.isVisible && panel.contentView != nil && panel.frame == keptFrame,
                     "unpinned panel must remain available at the same position")
        precondition(controller.query == "PASTE" && controller.selectedItem?.id == keptItem && !controller.pinned,
                     "keep-open paste must preserve query, selection and pin state")
        precondition(!controller.isActionsMenuPresented && !panel.isKeyWindow,
                     "close only More and leave keyboard focus with the destination")
        panel.makeKey()
        controller.toggleActionsMenu()
        controller.actionSelection = 2
        let keepOpenKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .option,
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        precondition(controller.handleActionKey(keepOpenKey))
        try await Task.sleep(for: .milliseconds(650))
        let afterKeepOpenKey = try String(contentsOf: root.appending(path: "text"), encoding: .utf8)
        precondition(afterKeepOpenKey == "LeftPASTEPASTERight",
                     "Option Return must paste and keep window open even when Delete is highlighted in More")
        precondition(controller.isVisible && panel.contentView != nil && panel.frame == keptFrame,
                     "Option Return keep-open paste must leave the unpinned panel open at the same position")
        precondition(controller.query == "PASTE" && controller.selectedItem?.id == keptItem && !controller.pinned,
                     "Option Return keep-open paste must preserve query, selection and pin state")
        precondition(!controller.isActionsMenuPresented && !panel.isKeyWindow,
                     "Option Return keep-open paste must close More and leave keyboard focus with the destination")
        panel.makeKey()
        controller.toggleActionsMenu()
        controller.actionSelection = 2
        let copyKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        precondition(controller.handleActionKey(copyKey))
        precondition(controller.items.count == 1 && !controller.isActionsMenuPresented,
                     "Cmd Return must copy even when Delete is highlighted in More")
        // Deliver a real Return event: the delegate consults NSApp.currentEvent, so calling
        // it directly can accidentally reuse an earlier activation or Command Return event.
        let returnKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        NSApp.postEvent(returnKey, atStart: false)
        for _ in 0..<100 {
            if (try? String(contentsOf: root.appending(path: "text"), encoding: .utf8)) == "LeftPASTEPASTEPASTERight" { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        let afterPaste = try String(contentsOf: root.appending(path: "text"), encoding: .utf8)
        precondition(afterPaste == "LeftPASTEPASTEPASTERight",
                     "Return must insert at the original cursor in another process")
        precondition(!controller.isVisible)
        // A clipboard change between copy and dispatch must prevent an unrelated paste.
        let stale = ClipboardAccess.changeCount
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("OTHER", forType: .string)
        let staleResult = await target.paste(expectedChangeCount: stale)
        precondition(staleResult == .unavailable)
        try "blur".write(to: root.appending(path: "control"), atomically: true, encoding: .utf8)
        for _ in 0..<100 {
            if (try? String(contentsOf: root.appending(path: "ack"), encoding: .utf8)) == "blur" { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        controller.show()
        try await waitForSearch(controller)
        precondition(!controller.hasPasteTarget && controller.actionKinds == [.copy, .delete, .clearAll],
                     "no input must retain Copy and omit automatic paste in More")
        let before = ClipboardAccess.changeCount
        controller.submitSelection(copyOnly: false)
        precondition(ClipboardAccess.changeCount == before && controller.isVisible)
        controller.submitSelection(copyOnly: true)
        precondition(NSPasteboard.general.string(forType: .string) == "PASTE" && controller.isVisible)
        controller.hide()
        print("Clipboard paste passed: external cursor insertion, keep-open menu paste, preserved panel state, copy-only, no input, clipboard race")
    }

    private static func verifyLocalPasteTarget() async throws {
        NSApp.setActivationPolicy(.regular)
        func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, of: type) }
        }
        let original = NSPasteboard.general.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        defer {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(original.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            })
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-local-paste-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        try ClipboardStore(app.store).insert(ClipboardItem(kind: .text, text: "PASTE", byteSize: 5,
                                                         contentHash: "local-paste"))
        var draft = "LeftRight"
        var attachmentPastes = 0
        let host = NSHostingView(rootView: ComposerTextEditor(
            height: .constant(80), isFocused: .constant(true), resetRevision: 0,
            pendingInsertions: [], consumeInsertions: { _ in },
            onSegmentsChanged: { segments in
                draft = segments.compactMap { if case .text(let s) = $0 { return s } else { return nil } }.joined()
            }, pasteAttachment: {
                if NSPasteboard.general.data(forType: .png) != nil { attachmentPastes += 1; return true }
                return false
            }, pasteLongText: { _ in nil },
            submit: { preconditionFailure("paste must never submit the message") }))
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 500, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        let editor = descendants(host, of: NSTextView.self).first!
        editor.string = draft
        NSApp.activate(ignoringOtherApps: true)
        for _ in 0..<30 {
            window.makeKeyAndOrderFront(nil)
            if NSApp.keyWindow === window { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(window.makeFirstResponder(editor) && NSApp.keyWindow === window,
                     "the composer window must own keyboard focus before capture")
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        let controller = ClipboardController(app: app)
        controller.show()
        try await waitForSearch(controller)
        try await Task.sleep(for: .milliseconds(100))
        precondition(controller.hasPasteTarget, "our own composer must be a paste target")
        controller.submitSelection(copyOnly: false)
        try await Task.sleep(for: .milliseconds(500))
        precondition(!controller.isVisible && editor.string == "LeftPASTERight" && draft == editor.string,
                     "Return must insert at the composer cursor and update its draft binding")
        editor.setSelectedRange(NSRange(location: 4, length: 5))
        controller.show()
        try await waitForSearch(controller)
        controller.pasteSelection(keepingOpen: true)
        try await Task.sleep(for: .milliseconds(350))
        precondition(controller.isVisible && editor.string == "LeftPASTERight",
                     "keep-open paste must replace the selection once")
        controller.hide()
        window.makeKeyAndOrderFront(nil)
        precondition(window.makeFirstResponder(editor))
        let target = ClipboardPasteTarget.capture()
        precondition(target.canPaste && target.prepare() == .posted)
        let stale = ClipboardAccess.changeCount
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(Data([1]), forType: .png)
        let staleResult = await target.paste(expectedChangeCount: stale)
        precondition(staleResult == .unavailable && attachmentPastes == 0)
        let imageResult = await target.paste(expectedChangeCount: ClipboardAccess.changeCount)
        precondition(imageResult == .posted && attachmentPastes == 1 && draft == "LeftPASTERight",
                     "local paste must invoke the composer's existing image attachment handler")
        editor.isEditable = false
        precondition(!ClipboardPasteTarget.capture().canPaste, "read-only text is not an input")
        editor.isEditable = true
        window.orderOut(nil)
        let closedResult = await target.paste(expectedChangeCount: ClipboardAccess.changeCount)
        precondition(closedResult == .unavailable && attachmentPastes == 1,
                     "a hidden target must not be reopened by a stale paste")
        print("PASS: local composer cursor insertion, binding, selection replacement, keep-open, attachment dispatch, clipboard race, read-only and hidden target")
    }

    private static func verifyDragPasteTarget() async throws {
        let originalClipboard = NSPasteboard.general.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        defer {
            let writers = originalClipboard.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(writers)
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-drag-paste-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let receiver = Process()
        receiver.executableURL = URL(filePath: ProcessInfo.processInfo.environment["ASKY_CLIPBOARD_RECEIVER"]!)
        receiver.arguments = ["--paste-receiver", root.path, "--reject-drag"]
        try receiver.run()
        defer { receiver.terminate(); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: root.appending(path: "ready").path) { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        let coordinates = try String(contentsOf: root.appending(path: "drop-point"), encoding: .utf8)
            .split(separator: ",").map { Double($0)! }
        let inputPoint = NSPoint(x: coordinates[0], y: coordinates[1])
        let buttonCoordinates = try String(contentsOf: root.appending(path: "noninput-point"), encoding: .utf8)
            .split(separator: ",").map { Double($0)! }
        let buttonPoint = NSPoint(x: buttonCoordinates[0], y: buttonCoordinates[1])
        let app = try AppModel(root: root.appending(path: "model"))
        let item = ClipboardItem(kind: .text, text: "DROP", byteSize: 4, contentHash: "drop")
        try ClipboardStore(app.store).insert(item)
        let controller = ClipboardController(app: app)
        let oldPointer = CGEvent(source: nil)!.location
        defer { CGWarpMouseCursorPosition(oldPointer) }
        func mouse(_ type: CGEventType, _ point: NSPoint) {
            let location = CGPoint(x: point.x, y: NSScreen.screens[0].frame.maxY - point.y)
            CGWarpMouseCursorPosition(location)
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        for scenario in ["cancel", "button", "paste"] {
            let cancel = scenario == "cancel"
            let end = scenario == "button" ? buttonPoint : inputPoint
            controller.pinned = true
            controller.show()
            try await waitForSearch(controller)
            try await Task.sleep(for: .milliseconds(300))
            let panel = NSApp.windows.first { $0.title == "剪贴板历史" }!
            panel.makeKeyAndOrderFront(nil)
            controller.pinned = CommandLine.arguments.contains("--pinned-drag")
            // Becoming key applies the production floating level; raise the fixture after it.
            panel.level = .popUpMenu
            func surfaces(_ view: NSView) -> [ClipboardCardMouseView] {
                (view as? ClipboardCardMouseView).map { [$0] } ?? view.subviews.flatMap(surfaces)
            }
            let surface = surfaces(panel.contentView!).first!
            let rect = panel.convertToScreen(surface.convert(surface.bounds, to: nil))
            let start = NSPoint(x: rect.midX, y: rect.midY)
            NSLog("Drag test: visible=%d key=%d card=%@ destination=%@", panel.isVisible, panel.isKeyWindow,
                  NSStringFromRect(rect), NSStringFromPoint(end))
            let before = ClipboardAccess.changeCount
            mouse(.leftMouseDown, start)
            try await Task.sleep(for: .milliseconds(100))
            for step in 1...25 {
                let fraction = CGFloat(step) / 25
                mouse(.leftMouseDragged, NSPoint(x: start.x + (end.x - start.x) * fraction,
                                                y: start.y + (end.y - start.y) * fraction))
                try await Task.sleep(for: .milliseconds(25))
            }
            if cancel {
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)
                    event?.flags = []
                    event?.post(tap: .cghidEventTap)
                }
                try await Task.sleep(for: .milliseconds(200))
            }
            mouse(.leftMouseUp, end)
            for _ in 0..<100 {
                if !controller.isDragging { break }
                try await Task.sleep(for: .milliseconds(30))
            }
            precondition(!controller.isDragging, "the native drag must finish before checking side effects")
            if scenario != "paste" {
                try await Task.sleep(for: .milliseconds(300))
                let value = try String(contentsOf: root.appending(path: "text"), encoding: .utf8)
                precondition(value.isEmpty && ClipboardAccess.changeCount == before,
                             "cancelled drops and drops on buttons must not paste or rewrite the clipboard")
            } else {
                let pinned = CommandLine.arguments.contains("--pinned-drag")
                for _ in 0..<100 {
                    if (try? String(contentsOf: root.appending(path: "text"), encoding: .utf8)) == "DROP",
                       controller.isVisible == pinned { break }
                    try await Task.sleep(for: .milliseconds(30))
                }
                let value = try String(contentsOf: root.appending(path: "text"), encoding: .utf8)
                precondition(value == "DROP", "a rejected native drop must paste once into the editor under the release point")
                precondition(controller.isVisible == pinned && NSPasteboard.general.string(forType: .string) == "DROP")
                if pinned { precondition(!panel.isKeyWindow, "a retained panel must release keyboard focus to the receiver") }
            }
            controller.hide()
        }
        print("Clipboard drag paste passed: native rejection, external editor insertion, Escape cancellation, non-input rejection, no duplicate insertion")
    }

    /// Opt-in native drag into a live app; verify the resulting draft separately, never send it.
    private static func verifyExternalDrag() async throws {
        let bundle = ProcessInfo.processInfo.environment["ASKY_CLIPBOARD_TARGET_BUNDLE"]!
        let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first {
            bundle != "com.stablyai.orca" || $0.bundleURL?.path == "/Applications/Orca.app"
        }!
        target.activate()
        for _ in 0..<100 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        precondition(NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier)
        let coordinates = ProcessInfo.processInfo.environment["ASKY_CLIPBOARD_DROP_POINT"]!
            .split(separator: ",").map { Double($0)! }
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-live-drag-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        try ClipboardStore(app.store).insert(ClipboardItem(kind: .text, text: "AskyDragProbe", byteSize: 13, contentHash: "live-drag"))
        let controller = ClipboardController(app: app)
        controller.pinned = true
        controller.show()
        try await waitForSearch(controller)
        try await Task.sleep(for: .milliseconds(300))
        let panel = NSApp.windows.first { $0.title == "剪贴板历史" }!
        controller.pinned = false
        panel.level = .popUpMenu
        panel.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(200))
        func cards(_ view: NSView) -> [ClipboardCardMouseView] {
            if let card = view as? ClipboardCardMouseView { return [card] }
            return view.subviews.flatMap(cards)
        }
        target.activate(options: [.activateAllWindows])
        let targetAX = AXUIElementCreateApplication(target.processIdentifier)
        var targetWindow: CFTypeRef?
        if AXUIElementCopyAttributeValue(targetAX, kAXMainWindowAttribute as CFString, &targetWindow) == .success,
           let targetWindow, CFGetTypeID(targetWindow) == AXUIElementGetTypeID() {
            AXUIElementPerformAction(targetWindow as! AXUIElement, kAXRaiseAction as CFString)
        }
        try await Task.sleep(for: .milliseconds(300))
        panel.makeKeyAndOrderFront(nil)
        print("Live drag frontmost before mouse:", NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")
        let card = cards(panel.contentView!).first!
        let rect = panel.convertToScreen(card.convert(card.bounds, to: nil))
        let start = CGPoint(x: rect.midX, y: NSScreen.screens[0].frame.maxY - rect.midY)
        let end = CGPoint(x: coordinates[0], y: coordinates[1])
        func mouse(_ type: CGEventType, _ point: CGPoint) {
            CGWarpMouseCursorPosition(point)
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
        mouse(.leftMouseDown, start)
        try await Task.sleep(for: .milliseconds(150))
        for step in 1...30 {
            let progress = CGFloat(step) / 30
            mouse(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress))
            try await Task.sleep(for: .milliseconds(30))
        }
        var hit: AXUIElement?
        AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(end.x), Float(end.y), &hit)
        var hitPID: pid_t = 0
        if let hit { AXUIElementGetPid(hit, &hitPID) }
        print("Live drag actual destination:", NSRunningApplication(processIdentifier: hitPID)?.bundleIdentifier ?? "none")
        mouse(.leftMouseUp, end)
        for _ in 0..<150 {
            if !controller.isDragging { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .seconds(3))
        print("Live drag finished; fixture on clipboard:", NSPasteboard.general.string(forType: .string) == "AskyDragProbe")
        var focused: CFTypeRef?
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(targetAX, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXValueAttribute as CFString, &value)
        }
        print("Live drag focused value contains fixture:", (value as? String)?.contains("AskyDragProbe") == true)
        controller.hide()
    }

    /// Opt-in live app check: only inserts a unique draft string; never sends Return to the receiver.
    private static func verifyExternalPaste() async throws {
        guard let bundle = ProcessInfo.processInfo.environment["ASKY_CLIPBOARD_TARGET_BUNDLE"],
              let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
            throw NSError(domain: "ClipboardExternalPaste", code: 1)
        }
        let original = NSPasteboard.general.pasteboardItems?.map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        } ?? []
        defer {
            let items = original.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(items)
        }
        target.activate(options: [.activateIgnoringOtherApps])
        for _ in 0..<100 {
            if target.isActive { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        precondition(target.isActive, "live app must be active before capture")
        let captured = ClipboardPasteTarget.capture()
        print("External paste target:", bundle, "focus:", captured.focusState, "canPaste:", captured.canPaste)
        precondition(captured.canPaste)
        let root = FileManager.default.temporaryDirectory.appending(path: "Asky-live-paste-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppModel(root: root)
        try ClipboardStore(app.store).insert(ClipboardItem(kind: .text, text: "AskyPasteProbe", byteSize: 14, contentHash: "live-paste"))
        let controller = ClipboardController(app: app)
        controller.show()
        try await waitForSearch(controller)
        controller.pinned = true
        try await Task.sleep(for: .milliseconds(250))
        precondition(controller.hasPasteTarget)
        controller.submitSelection(copyOnly: false)
        try await Task.sleep(for: .seconds(10))
        precondition(!controller.isVisible && controller.status == nil, "paste dispatch must finish without fallback")
        print("External paste dispatched. Verify AskyPasteProbe in the receiver before claiming insertion success.")
    }

    private static func verifyToastSurfaces() async throws {
        let panel = SurfacePanel()
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            panel.appearance = NSAppearance(named: appearance)
            for (kind, message) in [("copied", "已复制"), ("error", "无法复制：原始内容已不可用")] {
                let view = ClipboardStatusToast(message: message)
                let size = SurfacePanel.fittingSize(of: view, maxWidth: 672)
                panel.setSurface(view, size: size, cornerRadius: ClipboardStatusToast.cornerRadius, glass: false)
                panel.center()
                panel.orderFrontRegardless()
                try await Task.sleep(for: .milliseconds(200))
                let host = panel.contentView!
                host.layoutSubtreeIfNeeded()
                precondition(panel.frame.size == size, "hosting must preserve the measured surface size")
                precondition(size.height <= 40, "short feedback must fit on one line")
                let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: bitmap)
                precondition(bitmap.colorAt(x: 0, y: 0)!.alphaComponent < 0.1,
                             "toast corner must remain transparent rather than overflow as a rectangle")
                precondition(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.alphaComponent > 0.99,
                             "toast must retain its opaque background")
                try bitmap.representation(using: .png, properties: [:])!.write(
                    to: URL(filePath: "build/clipboard-toast-\(name)-\(kind).png"))
                print("PASS: toast \(name) \(kind) \(size)")
                panel.remove()
            }
        }
    }
}


@MainActor
final class ClipboardFileDropReceiver: NSView {
    var urls: [URL] = []
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        return !urls.isEmpty
    }
}

@MainActor
final class ClipboardPasteOnlyTextView: NSTextView {
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { [] }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { [] }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { false }
}
