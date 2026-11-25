import AppKit
import SwiftUI
import ToolService

/// The chat and keyboard previews share the same glass and content views.
@MainActor
final class ContentPreviewWindow: NSWindowController, NSWindowDelegate {
    static let shared = ContentPreviewWindow()
    static let quick = ContentPreviewWindow()

    private static let cornerRadius: CGFloat = 16
    private let presentation = WindowPresentation()
    private weak var originPanel: NSPanel?
    private var onBlur: (() -> Void)?
    private weak var shortcutWindow: NSPanel?
    private var shouldRouteShortcut: ((NSEvent) -> Bool)?
    private var shortcutCapture: PreviewShortcutCapture?

    private init() { super.init(window: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isVisible: Bool { isWindowLoaded && window?.isVisible == true }

    func show(image: NSImage, label: String) {
        let level = NSApp.keyWindow?.level ?? .normal
        let window = self.window ?? makeWindow()
        window.title = label.isEmpty ? NSLocalizedString("图片预览", comment: "") : label
        install(PreviewImage(image: image, label: label), in: window)
        presentation.show(window, level: level)
    }

    func show(file: PreviewFile, label: String, from owner: NSPanel, shortcut: LauncherActionShortcut,
              onBlur: @escaping () -> Void) {
        if let previous = originPanel { dismiss(from: previous) }
        let panel = (window as? PreviewPanel) ?? makePanel()
        originPanel = owner
        self.onBlur = onBlur
        panel.shortcut = shortcut
        panel.title = label
        panel.level = owner.level
        if let screen = owner.screen {
            let area = screen.visibleFrame.insetBy(dx: 16, dy: 16)
            var frame = panel.frame
            frame.size.width = min(frame.width, area.width)
            frame.size.height = min(frame.height, area.height)
            frame.origin = NSPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2)
            panel.setFrame(frame.integral, display: false)
        }
        install(PreviewFileView(file: file, label: label), in: panel)
        owner.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func isShowing(from owner: NSPanel) -> Bool { originPanel === owner }

    func contains(_ point: NSPoint, from owner: NSPanel) -> Bool {
        isShowing(from: owner) && window?.isVisible == true && window?.frame.contains(point) == true
    }

    func captureShortcut(in panel: NSPanel, when shouldRoute: @escaping (NSEvent) -> Bool) {
        shortcutWindow = panel
        shouldRouteShortcut = shouldRoute
        if shortcutCapture == nil {
            shortcutCapture = PreviewShortcutCapture { [weak self] event in
                guard let self, let panel = self.shortcutWindow, panel.isVisible, panel.isKeyWindow,
                      self.shouldRouteShortcut?(event) == true else { return false }
                // Decode files and change key windows after the event tap returns.
                Task { @MainActor [weak panel] in
                    guard let panel, panel.isKeyWindow else { return }
                    panel.sendEvent(event)
                }
                return true
            }
        }
        shortcutCapture?.setEnabled(true)
    }

    func releaseShortcut(in panel: NSPanel) {
        guard shortcutWindow === panel else { return }
        shortcutCapture?.invalidate()
        shortcutCapture = nil
        shortcutWindow = nil
        shouldRouteShortcut = nil
    }

    func dismiss(from owner: NSPanel) {
        guard isShowing(from: owner) else { return }
        clearOwner()
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if let panel = window as? PreviewPanel { releaseShortcut(in: panel) }
        let previousOwner = originPanel
        clearOwner()
        window?.contentView = nil
        if let previousOwner {
            // Restore the existing field editor after AppKit has finished closing the preview.
            Task { @MainActor [weak previousOwner] in
                guard let previousOwner, previousOwner.isVisible, self.originPanel == nil else { return }
                previousOwner.makeKey()
            }
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let panel = window as? PreviewPanel, originPanel != nil else { return }
        captureShortcut(in: panel) { [weak panel] event in panel?.shortcut.matches(event) == true }
    }

    func windowDidResignKey(_ notification: Notification) {
        if let panel = window as? PreviewPanel { releaseShortcut(in: panel) }
        guard let owner = originPanel else { return }
        Task { @MainActor [weak self, weak owner] in
            guard let self, let owner, self.isShowing(from: owner), self.window?.isKeyWindow == false else { return }
            let onBlur = self.onBlur
            self.dismiss(from: owner)
            if !owner.isKeyWindow { onBlur?() }
        }
    }

    private func clearOwner() {
        if let window { originPanel?.removeChildWindow(window) }
        originPanel = nil
        onBlur = nil
    }

    private static let frame = NSRect(x: 0, y: 0, width: 680, height: 560)
    private static let style: NSWindow.StyleMask = [.titled, .closable, .resizable, .fullSizeContentView]

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: Self.frame, styleMask: Self.style.union(.miniaturizable),
                              backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        configure(window)
        return window
    }

    private func makePanel() -> PreviewPanel {
        let panel = PreviewPanel(contentRect: Self.frame, styleMask: Self.style.union(.nonactivatingPanel),
                                 backing: .buffered, defer: false)
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        configure(panel)
        return panel
    }

    private func configure(_ window: NSWindow) {
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.contentMinSize = NSSize(width: 320, height: 280)
        self.window = window
        window.center()
    }

    private func install(_ content: some View, in window: NSWindow) {
        let host = NSHostingView(rootView: content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .windowSurfaceBackground(in: RoundedRectangle(cornerRadius: Self.cornerRadius))
            .ignoresSafeArea())
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: window.contentRect(forFrameRect: window.frame).size)
        window.contentView = WindowSurface.glassContentView(host, cornerRadius: Self.cornerRadius)
    }
}

private struct PreviewFileView: View {
    let file: PreviewFile
    let label: String
    @State private var result: Result<PreviewFile.Content, Error>?

    var body: some View {
        Group {
            switch result {
            case .success(.image(let image)):
                PreviewImage(image: NSImage(cgImage: image, size: .zero), label: label)
            case .success(.markdown(let text, let directory)):
                PreviewMarkdown(text: text, directory: directory)
            case .success(.plainText(let text, let highlights)):
                PreviewPlainText(text: text, highlights: highlights)
                    .padding(.top, 34)
            case .failure:
                Text(NSLocalizedString("无法预览此文件", comment: ""))
            case nil:
                ProgressView().controlSize(.small)
            }
        }
        .task {
            do {
                let content = try await file.load()
                if !Task.isCancelled { result = .success(content) }
            } catch {
                if !Task.isCancelled { result = .failure(error) }
            }
        }
    }
}

private final class PreviewPanel: NSPanel {
    var shortcut = LocalShortcutAction.launcherPreview.defaultShortcut
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if shortcut.matches(event) || LocalShortcutAction.launcherEscape.defaultShortcut.matches(event) {
            if !event.isARepeat { close() }
            return
        }
        super.sendEvent(event)
    }
}

private struct PreviewImage: View {
    let image: NSImage
    let label: String

    var body: some View {
        Image(nsImage: image).resizable().scaledToFit()
            .accessibilityLabel(label)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16).padding(.top, 28)
    }
}

private struct PreviewPlainText: NSViewRepresentable {
    let text: String
    let highlights: [SyntaxHighlight]

    private static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private static let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        let view = scroll.documentView as! NSTextView
        view.drawsBackground = false
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.font = Self.font
        view.textColor = .labelColor
        view.textContainerInset = NSSize(width: 19, height: 12)
        view.isHorizontallyResizable = true
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = view.maxSize
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView,
              view.string != text || context.coordinator.highlights != highlights else { return }
        context.coordinator.highlights = highlights
        let styled = NSMutableAttributedString(string: text, attributes: [.font: Self.font, .foregroundColor: NSColor.labelColor])
        let length = styled.length
        styled.beginEditing()
        for highlight in highlights where highlight.location + highlight.length <= length {
            styled.addAttribute(.foregroundColor, value: Self.color(for: highlight.kind), range: highlight.range)
            if highlight.kind == .keyword { styled.addAttribute(.font, value: Self.boldFont, range: highlight.range) }
        }
        styled.endEditing()
        view.textStorage?.setAttributedString(styled)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var highlights: [SyntaxHighlight] = []
    }

    /// Xcode-inspired source colors, resolved per appearance so the preview follows light and dark mode live.
    private static let palette: [SyntaxHighlight.Kind: NSColor] = [
        .comment: dynamic(0x5D6C79, 0x7F8C98),
        .string: dynamic(0xC41A16, 0xFC6A5D),
        .number: dynamic(0x1C00CF, 0xD0BF69),
        .keyword: dynamic(0x9B2393, 0xFC5FA3),
        .literal: dynamic(0x9B2393, 0xFC5FA3),
        .type: dynamic(0x0B4F79, 0x5DD8FF),
        .function: dynamic(0x326D74, 0x67B7A4),
        .attribute: dynamic(0x815F03, 0xFD8F3F),
        .property: dynamic(0x0F68A0, 0x41A1C0),
        .tag: dynamic(0x9B2393, 0xFC5FA3),
        .inserted: dynamic(0x1F7A35, 0x67D17E),
        .deleted: dynamic(0xB3261E, 0xFF7B72),
        .meta: dynamic(0x6C36A9, 0xB281EB)
    ]

    private static func color(for kind: SyntaxHighlight.Kind) -> NSColor { palette[kind] ?? .labelColor }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}

private struct PreviewMarkdown: View {
    let text: String
    let directory: URL

    var body: some View {
        // Same Markdown styling as AI chat replies; the directory scopes relative images.
        ScrollView {
            ChatMarkdownView(text: text, fileDirectory: directory)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
        }
        .padding(.top, 34)
        .environment(\.openURL, OpenURLAction { url in
            guard ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
            return ToolService.openLauncherURL(url) ? .handled : .discarded
        })
    }
}

/// Block image inside a previewed Markdown file; reads stay inside the file's directory.
struct PreviewMarkdownBlockImage: View {
    let url: URL?
    let directory: URL
    @State private var image: CGImage?

    nonisolated init(url: URL?, directory: URL) {
        self.url = url
        self.directory = directory
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .frame(maxWidth: CGFloat(image.width))
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = await PreviewFile.loadMarkdownImage(at: url, in: directory, maxPixelSize: 1600)
        }
    }
}
