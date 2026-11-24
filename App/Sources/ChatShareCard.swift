import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import MarkdownUI
import SwiftUI
import Theme
import ToolService

enum ShareCardAppearance: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    init(colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }

    var colorScheme: ColorScheme {
        self == .dark ? .dark : .light
    }

    var assetName: String {
        self == .dark ? "ShareCardBackdropDark" : "ShareCardBackdropLight"
    }

    var title: String {
        switch self {
        case .light: NSLocalizedString("浅色", comment: "")
        case .dark: NSLocalizedString("深色", comment: "")
        }
    }
}

@MainActor
final class ShareCardBackdropCache {
    static let shared = ShareCardBackdropCache()

    struct Pair {
        let sharp: NSImage
        let blurred: NSImage
    }

    private var cache: [ShareCardAppearance: Pair] = [:]
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    func backdrop(for appearance: ShareCardAppearance) -> Pair {
        if let cached = cache[appearance] { return cached }
        let sharp = NSImage(named: appearance.assetName) ?? fallbackBackdrop(for: appearance)
        let blurred = blur(sharp, radius: 28, isDark: appearance == .dark) ?? sharp
        let pair = Pair(sharp: sharp, blurred: blurred)
        cache[appearance] = pair
        return pair
    }

    private func blur(_ image: NSImage, radius: Double, isDark: Bool) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cgImage)
        let extent = input.extent

        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = input.clampedToExtent()
        blurFilter.radius = Float(radius)
        guard let blurred = blurFilter.outputImage?.cropped(to: extent) else { return nil }

        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = blurred
        colorControls.saturation = 1.48
        colorControls.brightness = isDark ? 0.04 : 0.03
        colorControls.contrast = 1.06

        let finalImage = (colorControls.outputImage ?? blurred).cropped(to: extent)
        guard let outputCG = ciContext.createCGImage(finalImage, from: extent) else { return nil }
        return NSImage(cgImage: outputCG, size: image.size)
    }

    private func fallbackBackdrop(for appearance: ShareCardAppearance) -> NSImage {
        let size = NSSize(width: 1200, height: 1500)
        return NSImage(size: size, flipped: false) { rect in
            let colors: [NSColor] = appearance == .dark
                ? [
                    NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.22, alpha: 1),
                    NSColor(calibratedRed: 0.12, green: 0.20, blue: 0.34, alpha: 1),
                    NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.16, alpha: 1),
                ]
                : [
                    NSColor(calibratedRed: 0.56, green: 0.74, blue: 0.90, alpha: 1),
                    NSColor(calibratedRed: 0.85, green: 0.82, blue: 0.76, alpha: 1),
                    NSColor(calibratedRed: 0.48, green: 0.64, blue: 0.72, alpha: 1),
                ]
            if let gradient = NSGradient(colors: colors) {
                gradient.draw(in: rect, angle: -90)
            }
            return true
        }
    }
}

struct ChatShareCardContent: View {
    let text: String
    let appearance: ShareCardAppearance

    private var isDark: Bool { appearance == .dark }

    private var primaryTextColor: Color {
        isDark ? Color(white: 0.95) : Color(white: 0.11)
    }

    private var subtleTextColor: Color {
        isDark ? Color(white: 0.72) : Color(white: 0.38)
    }

    private var brandTextColor: Color {
        isDark ? Color(white: 0.96) : Color(white: 0.12)
    }

    private var codeBackgroundColor: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    private var borderColor: Color {
        isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)
    }

    private var formattedMarkdown: String {
        let parts = ChatFormParser.parse(text, streaming: false)
        return parts.map { part in
            switch part.content {
            case .markdown(let body):
                return body
            case .form(let form):
                var lines: [String] = []
                if !form.title.isEmpty { lines.append("**\(form.title)**") }
                for field in form.fields {
                    lines.append("- \(field.label)")
                }
                return lines.joined(separator: "\n")
            }
        }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image("AskyLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                Text(verbatim: "Asky")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(brandTextColor)
                Spacer(minLength: 0)
            }

            Markdown(formattedMarkdown)
                .markdownTextStyle {
                    FontSize(14)
                    FontWeight(.regular)
                    ForegroundColor(primaryTextColor)
                }
                .markdownTextStyle(\.strong) {
                    FontWeight(.semibold)
                }
                .markdownTextStyle(\.code) {
                    FontSize(12.5)
                    FontFamilyVariant(.monospaced)
                    BackgroundColor(codeBackgroundColor)
                }
                .markdownTextStyle(\.link) {
                    ForegroundColor(isDark ? Color(red: 0.45, green: 0.72, blue: 1.0) : Color(red: 0.08, green: 0.42, blue: 0.85))
                    UnderlineStyle(.single)
                }
                .markdownBlockStyle(\.heading1) { configuration in
                    configuration.label
                        .markdownTextStyle {
                            FontSize(17.5)
                            FontWeight(.semibold)
                            ForegroundColor(primaryTextColor)
                        }
                        .markdownMargin(top: 4, bottom: 10)
                }
                .markdownBlockStyle(\.heading2) { configuration in
                    configuration.label
                        .markdownTextStyle {
                            FontSize(16)
                            FontWeight(.semibold)
                            ForegroundColor(primaryTextColor)
                        }
                        .markdownMargin(top: 4, bottom: 8)
                }
                .markdownBlockStyle(\.heading3) { configuration in
                    configuration.label
                        .markdownTextStyle {
                            FontSize(15)
                            FontWeight(.semibold)
                            ForegroundColor(primaryTextColor)
                        }
                        .markdownMargin(top: 2, bottom: 8)
                }
                .markdownBlockStyle(\.paragraph) { configuration in
                    configuration.label
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .markdownMargin(top: 0, bottom: 11)
                }
                .markdownBlockStyle(\.listItem) { configuration in
                    configuration.label
                        .markdownMargin(top: 4, bottom: 4)
                }
                .markdownBlockStyle(\.codeBlock) { configuration in
                    configuration.label
                        .markdownTextStyle {
                            FontSize(12)
                            FontFamilyVariant(.monospaced)
                            ForegroundColor(primaryTextColor)
                        }
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .background(codeBackgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(borderColor, lineWidth: 0.5)
                        }
                        .markdownMargin(top: 4, bottom: 12)
                }
                .markdownBlockStyle(\.blockquote) { configuration in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(subtleTextColor.opacity(0.45))
                            .frame(width: 3)
                        configuration.label
                            .markdownTextStyle {
                                ForegroundColor(subtleTextColor)
                            }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownMargin(top: 2, bottom: 11)
                }
                .markdownBlockStyle(\.table) { configuration in
                    configuration.label
                        .markdownTableBorderStyle(.init(.allBorders, color: borderColor, width: 0.5))
                        .markdownTableBackgroundStyle(.alternatingRows(
                            Color.clear,
                            isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.025),
                            header: codeBackgroundColor
                        ))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(borderColor, lineWidth: 0.5)
                        }
                        .markdownMargin(top: 4, bottom: 12)
                }
                .markdownBlockStyle(\.tableCell) { configuration in
                    configuration.label
                        .markdownTextStyle {
                            FontSize(12.5)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                }
                .markdownBlockStyle(\.thematicBreak) {
                    Rectangle()
                        .fill(borderColor)
                        .frame(height: 1)
                        .markdownMargin(top: 10, bottom: 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ChatShareCardView: View {
    static let canvasWidth: CGFloat = 600
    private static let outerHorizontalPadding: CGFloat = 36
    private static let outerVerticalPadding: CGFloat = 40
    private static let cardCornerRadius: CGFloat = 28

    let text: String
    let appearance: ShareCardAppearance

    private var isDark: Bool { appearance == .dark }
    private var backdrop: ShareCardBackdropCache.Pair { ShareCardBackdropCache.shared.backdrop(for: appearance) }

    private var glassTint: Color {
        isDark
            ? Color(red: 0.07, green: 0.09, blue: 0.14).opacity(0.36)
            : Color.white.opacity(0.46)
    }

    private var glassSheen: LinearGradient {
        if isDark {
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.18), location: 0.0),
                    .init(color: Color.white.opacity(0.05), location: 0.18),
                    .init(color: Color.white.opacity(0.01), location: 0.72),
                    .init(color: Color.white.opacity(0.06), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.42), location: 0.0),
                    .init(color: Color.white.opacity(0.12), location: 0.22),
                    .init(color: Color.white.opacity(0.04), location: 0.75),
                    .init(color: Color.white.opacity(0.18), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var glassBorder: LinearGradient {
        if isDark {
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.46), location: 0.0),
                    .init(color: Color.white.opacity(0.12), location: 0.35),
                    .init(color: Color.white.opacity(0.08), location: 0.68),
                    .init(color: Color.white.opacity(0.30), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.95), location: 0.0),
                    .init(color: Color.white.opacity(0.42), location: 0.35),
                    .init(color: Color.white.opacity(0.30), location: 0.68),
                    .init(color: Color.white.opacity(0.76), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        let outerH = Self.outerHorizontalPadding
        let outerV = Self.outerVerticalPadding
        let shape = RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)

        ZStack {
            GeometryReader { canvasProxy in
                Image(nsImage: backdrop.sharp)
                    .resizable()
                    .scaledToFill()
                    .frame(width: canvasProxy.size.width, height: canvasProxy.size.height)
                    .clipped()
            }

            ChatShareCardContent(text: text, appearance: appearance)
                .padding(.horizontal, 28)
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { cardProxy in
                        let canvasWidth = cardProxy.size.width + outerH * 2
                        let canvasHeight = cardProxy.size.height + outerV * 2
                        Image(nsImage: backdrop.blurred)
                            .resizable()
                            .scaledToFill()
                            .frame(width: canvasWidth, height: canvasHeight)
                            .clipped()
                            .offset(x: -outerH, y: -outerV)
                            .frame(width: cardProxy.size.width, height: cardProxy.size.height, alignment: .topLeading)
                    }
                    .overlay(glassTint)
                    .overlay(glassSheen)
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(glassBorder, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(isDark ? 0.42 : 0.18), radius: 26, x: 0, y: 12)
                }
                .padding(.horizontal, outerH)
                .padding(.vertical, outerV)
        }
        .frame(width: Self.canvasWidth)
        .fixedSize(horizontal: false, vertical: true)
        .clipped()
        .environment(\.colorScheme, appearance.colorScheme)
    }
}

@MainActor
enum ChatShareCardRenderer {
    static func renderPNG(text: String, appearance: ShareCardAppearance, scale: CGFloat = 2.0) -> Data? {
        let view = ChatShareCardView(text: text, appearance: appearance)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: ChatShareCardView.canvasWidth, height: nil)
        guard let cgImage = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}

@MainActor
final class ChatShareWindowController: NSWindowController, NSWindowDelegate {
    static let shared = ChatShareWindowController()

    private static let cornerRadius: CGFloat = 24
    private let presentation = WindowPresentation()
    private let outsideClickDismissal = OutsideClickDismissal()
    private var autoDismissSuspensionCount = 0
    private var shareCoordinator: SystemShareCoordinator?

    private init() { super.init(window: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var isAutoDismissSuspended: Bool {
        autoDismissSuspensionCount > 0 || window?.attachedSheet != nil
    }

    func show(text: String, colorScheme: ColorScheme) {
        shareCoordinator?.cancel()
        shareCoordinator = nil
        autoDismissSuspensionCount = 0

        let level = NSApp.keyWindow?.level ?? .normal
        let window = self.window ?? makeWindow()
        window.title = NSLocalizedString("分享回复", comment: "")
        let content = ChatSharePreviewSheet(
            text: text,
            initialAppearance: ShareCardAppearance(colorScheme: colorScheme),
            windowProvider: { [weak window] in window },
            suspendAutoDismiss: { [weak self] in
                self?.suspendAutoDismiss() ?? {}
            },
            presentSystemShare: { [weak self] url, anchor in
                self?.presentSystemShare(url: url, anchor: anchor)
            },
            close: { [weak self] in
                self?.dismiss()
            }
        )
        let host = NSHostingView(rootView: content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .windowSurfaceBackground(in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .circular))
            .ignoresSafeArea())
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: window.contentRect(forFrameRect: window.frame).size)
        window.contentView = WindowSurface.glassContentView(host, cornerRadius: Self.cornerRadius)
        if let surface = window.contentView {
            WindowSurface.updateCorners(of: surface, radius: Self.cornerRadius, circular: true)
        }
        presentation.show(window, level: level)
        updateOutsideClickDismissal()
    }

    func dismiss() {
        outsideClickDismissal.hide()
        shareCoordinator?.cancel()
        shareCoordinator = nil
        autoDismissSuspensionCount = 0
        guard let window else { return }
        let shouldClose = window.isVisible || window.contentView != nil
        window.orderOut(nil)
        if shouldClose {
            window.close()
        }
        window.contentView = nil
    }

    func suspendAutoDismiss() -> () -> Void {
        autoDismissSuspensionCount += 1
        updateOutsideClickDismissal()
        var active = true
        return { [weak self] in
            guard active else { return }
            active = false
            guard let self else { return }
            self.autoDismissSuspensionCount = max(0, self.autoDismissSuspensionCount - 1)
            self.updateOutsideClickDismissal()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window, window.isVisible, !isAutoDismissSuspended else { return }
        dismiss()
    }

    func windowWillClose(_ notification: Notification) {
        outsideClickDismissal.hide()
        shareCoordinator?.cancel()
        shareCoordinator = nil
        autoDismissSuspensionCount = 0
        window?.contentView = nil
    }

    private func updateOutsideClickDismissal() {
        guard let window, window.isVisible, !isAutoDismissSuspended else {
            outsideClickDismissal.hide()
            return
        }
        outsideClickDismissal.show(contains: { [weak self] point in
            guard let self, let window = self.window else { return false }
            if self.isAutoDismissSuspended { return true }
            return window.isVisible && window.frame.contains(point)
        }, dismiss: { [weak self] in
            self?.dismiss()
        })
    }

    private func presentSystemShare(url: URL, anchor: NSView) {
        shareCoordinator?.cancel()
        let resume = suspendAutoDismiss()
        var coordinator: SystemShareCoordinator?
        let created = SystemShareCoordinator(
            sourceWindow: window,
            onFinish: { [weak self] cancelled in
                resume()
                guard let self else { return }
                if self.shareCoordinator === coordinator {
                    self.shareCoordinator = nil
                }
                if cancelled {
                    Task { @MainActor [weak self] in
                        guard let self, let window = self.window,
                              window.isVisible, !window.isKeyWindow, !self.isAutoDismissSuspended else { return }
                        self.dismiss()
                    }
                }
            }
        )
        coordinator = created
        shareCoordinator = created
        created.present(items: [url], relativeTo: anchor.bounds, of: anchor)
    }

    private func makeWindow() -> NSWindow {
        let window = ChatShareWindow(
            contentRect: NSRect(x: 0, y: 0, width: 448, height: 516),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.center()
        self.window = window
        return window
    }
}

@MainActor
private final class SystemShareCoordinator: NSObject, @MainActor NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    private weak var sourceWindow: NSWindow?
    private var onFinish: ((_ cancelled: Bool) -> Void)?
    private var fallbackTask: Task<Void, Never>?
    private var isPresentingService = false

    init(sourceWindow: NSWindow?, onFinish: @escaping (_ cancelled: Bool) -> Void) {
        self.sourceWindow = sourceWindow
        self.onFinish = onFinish
    }

    func present(items: [Any], relativeTo rect: NSRect, of view: NSView) {
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = self
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    func cancel() {
        complete(cancelled: false)
    }

    private func complete(cancelled: Bool) {
        fallbackTask?.cancel()
        fallbackTask = nil
        isPresentingService = false
        let finish = onFinish
        onFinish = nil
        finish?(cancelled)
    }

    nonisolated func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                                          delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? {
        MainActor.assumeIsolated { self }
    }

    nonisolated func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                                          didChoose service: NSSharingService?) {
        let choseService = service != nil
        MainActor.assumeIsolated {
            guard choseService else {
                complete(cancelled: true)
                return
            }
            fallbackTask?.cancel()
            fallbackTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                guard let self, !Task.isCancelled, !self.isPresentingService else { return }
                self.complete(cancelled: false)
            }
        }
    }

    func sharingService(_ sharingService: NSSharingService,
                        sourceWindowForShareItems items: [Any],
                        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        sourceWindow
    }

    func sharingService(_ sharingService: NSSharingService, willShareItems items: [Any]) {
        isPresentingService = true
        fallbackTask?.cancel()
        fallbackTask = nil
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        complete(cancelled: false)
    }

    func sharingService(_ sharingService: NSSharingService,
                        didFailToShareItems items: [Any],
                        error: any Error) {
        complete(cancelled: false)
    }
}

private final class ChatShareWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

private struct ChatSharePreviewSheet: View {
    private static let modalWidth: CGFloat = 448
    private static let modalHeight: CGFloat = 516
    private static let cardHorizontalInset: CGFloat = 24
    private static let maxCardHeight: CGFloat = 310
    private static let bottomFadeHeight: CGFloat = 78

    let text: String
    let windowProvider: () -> NSWindow?
    let suspendAutoDismiss: () -> () -> Void
    let presentSystemShareAction: (URL, NSView) -> Void
    let close: () -> Void

    @State private var appearance: ShareCardAppearance
    @State private var cardHeight: CGFloat = 0
    @State private var copied = false
    @State private var saved = false
    @State private var errorMessage: String?
    @State private var resumeErrorSuspension: (() -> Void)?
    @State private var shareAnchor = ShareAnchorBox()

    init(
        text: String,
        initialAppearance: ShareCardAppearance,
        windowProvider: @escaping () -> NSWindow?,
        suspendAutoDismiss: @escaping () -> () -> Void,
        presentSystemShare: @escaping (URL, NSView) -> Void,
        close: @escaping () -> Void
    ) {
        self.text = text
        self.windowProvider = windowProvider
        self.suspendAutoDismiss = suspendAutoDismiss
        self.presentSystemShareAction = presentSystemShare
        self.close = close
        _appearance = State(initialValue: initialAppearance)
    }

    private var isDark: Bool { appearance == .dark }
    private var backdrop: ShareCardBackdropCache.Pair { ShareCardBackdropCache.shared.backdrop(for: appearance) }
    private var isOverflowing: Bool { cardHeight > Self.maxCardHeight }
    private var visibleCardHeight: CGFloat {
        cardHeight > 0 ? min(cardHeight, Self.maxCardHeight) : Self.maxCardHeight
    }

    private var chromeTextColor: Color {
        isDark ? Color.white.opacity(0.94) : Color(white: 0.12)
    }

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        ZStack {
            // Full-bleed scenic landscape as the modal's own backdrop.
            Image(nsImage: backdrop.sharp)
                .resizable()
                .scaledToFill()
                .frame(width: Self.modalWidth, height: Self.modalHeight)
                .clipped()

            // Subtle top & bottom scrim so floating title and labels stay legible in both appearances.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        (isDark ? Color.black : Color.white).opacity(isDark ? 0.30 : 0.22),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [
                        .clear,
                        (isDark ? Color.black : Color.white).opacity(isDark ? 0.38 : 0.32)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 124)
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    HStack(spacing: 0) {
                        Text(NSLocalizedString("分享回复", comment: ""))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(chromeTextColor)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .contentShape(.rect)
                    .background(WindowDragArea())

                    Button(action: close) {
                        Image(mingCute: "xmark", size: 12.5)
                            .foregroundStyle(chromeTextColor.opacity(0.92))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(ShareGlassCircleButtonStyle())
                    .accessibilityLabel(NSLocalizedString("关闭", comment: ""))
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)

                Spacer(minLength: 0)

                ChatShareCardContent(text: text, appearance: appearance)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
                    .frame(width: Self.modalWidth - Self.cardHorizontalInset * 2, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                    .frame(width: Self.modalWidth - Self.cardHorizontalInset * 2, height: visibleCardHeight, alignment: .top)
                    .clipped()
                    .nativeGlassBackground(in: cardShape)
                    .mask {
                        VStack(spacing: 0) {
                            Color.black
                            if isOverflowing {
                                LinearGradient(
                                    stops: [
                                        .init(color: .black, location: 0.0),
                                        .init(color: .black.opacity(0.62), location: 0.38),
                                        .init(color: .black.opacity(0.18), location: 0.74),
                                        .init(color: .clear, location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: Self.bottomFadeHeight)
                            }
                        }
                    }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    ShareCircleActionButton(
                        title: copied ? NSLocalizedString("已复制", comment: "") : NSLocalizedString("复制图片", comment: ""),
                        mingCute: copied ? "checkmark" : "doc.on.clipboard",
                        isDark: isDark,
                        action: copyImage
                    )
                    ShareCircleActionButton(
                        title: saved ? NSLocalizedString("已保存图片", comment: "") : NSLocalizedString("保存图片", comment: ""),
                        mingCute: saved ? "checkmark" : "arrow.down.to.line",
                        isDark: isDark,
                        action: saveImage
                    )
                    ShareCircleActionButton(
                        title: NSLocalizedString("系统分享", comment: ""),
                        assetImage: "ChatShare",
                        isDark: isDark,
                        action: presentSystemShare
                    )
                    .background(ShareAnchorReader(box: shareAnchor).allowsHitTesting(false))
                    ShareCircleActionButton(
                        title: appearance.title,
                        assetImage: "ChatThemeToggle",
                        isDark: isDark,
                        action: {
                            appearance = appearance == .dark ? .light : .dark
                        }
                    )
                }
                .padding(.top, 14)
                .padding(.bottom, 22)
            }
        }
        .frame(width: Self.modalWidth, height: Self.modalHeight)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(isDark ? 0.16 : 0.45), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, appearance.colorScheme)
        .appDialog(
            NSLocalizedString("分享失败", comment: ""),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { presented in
                    if !presented {
                        errorMessage = nil
                        resumeErrorSuspension?()
                        resumeErrorSuspension = nil
                    }
                }
            ),
            message: errorMessage ?? "",
            buttons: [NSLocalizedString("好", comment: "")]
        )
        .onDisappear {
            resumeErrorSuspension?()
            resumeErrorSuspension = nil
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .milliseconds(1400))
            copied = false
        }
        .task(id: saved) {
            guard saved else { return }
            try? await Task.sleep(for: .milliseconds(1600))
            saved = false
        }
    }

    private func showError(_ message: String) {
        if resumeErrorSuspension == nil {
            resumeErrorSuspension = suspendAutoDismiss()
        }
        errorMessage = message
    }

    private func presentSystemShare() {
        guard let anchor = shareAnchor.view,
              let png = ChatShareCardRenderer.renderPNG(text: text, appearance: appearance),
              let url = try? ShareImageService.writeTemporarySharePNG(png) else {
            showError(NSLocalizedString("生成分享图片失败", comment: ""))
            return
        }
        presentSystemShareAction(url, anchor)
    }

    private func copyImage() {
        guard let png = ChatShareCardRenderer.renderPNG(text: text, appearance: appearance),
              ShareImageService.copyPNG(png) else {
            showError(NSLocalizedString("生成分享图片失败", comment: ""))
            return
        }
        copied = true
    }

    private func saveImage() {
        guard let png = ChatShareCardRenderer.renderPNG(text: text, appearance: appearance) else {
            showError(NSLocalizedString("生成分享图片失败", comment: ""))
            return
        }
        let resume = suspendAutoDismiss()
        Task {
            defer { resume() }
            do {
                if try await ShareImageService.savePNG(png, for: windowProvider()) != nil {
                    saved = true
                }
            } catch {
                showError(error.localizedDescription)
            }
        }
    }
}

private struct ShareGlassCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .nativeGlassBackground(in: Circle(), interactive: true)
            .contentShape(.interaction, Circle())
            .glassPointerFeedback(pressed: configuration.isPressed, in: Circle())
    }
}

private struct ShareCircleActionButton: View {
    static let slotWidth: CGFloat = 76

    let title: String
    var mingCute: String? = nil
    var assetImage: String? = nil
    let isDark: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Group {
                    if let mingCute {
                        Image(mingCute: mingCute, size: 19)
                    } else if let assetImage {
                        Image(assetImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 19, height: 19)
                    }
                }
                .foregroundStyle(isDark ? Color.white.opacity(0.95) : Color(white: 0.12))
                .frame(width: 46, height: 46)
            }
            .buttonStyle(ShareGlassCircleButtonStyle())
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isDark ? Color.white.opacity(0.90) : Color(white: 0.14))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(width: Self.slotWidth)
    }
}

@MainActor
private final class ShareAnchorBox {
    weak var view: NSView?
}

private struct ShareAnchorReader: NSViewRepresentable {
    let box: ShareAnchorBox
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }
}
