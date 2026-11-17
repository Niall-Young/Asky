import AppKit
import SwiftUI
import Theme
import ToolService

struct ChatImageGallery: View {
    let images: [ChatGalleryImage]
    @Namespace private var scrollSpace
    @State private var contentOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tileSize: CGFloat = 220
    private let spacing: CGFloat = 8

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, photo in
                            ChatImageTile(photo: photo).frame(width: tileSize, height: tileSize).id(index)
                        }
                    }
                    .background {
                        GeometryReader { content in
                            Color.clear.preference(key: ChatGalleryOffsetKey.self,
                                value: content.frame(in: .named(scrollSpace)).minX)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onPreferenceChange(ChatGalleryOffsetKey.self) {
                    if #unavailable(macOS 15) { contentOffset = $0 }
                }
                .modifier(ChatGalleryScrollOffset(offset: $contentOffset))
                .overlay(alignment: .leading) {
                    if contentOffset < -1 {
                        navigationButton("chevron.left", label: "上一张图片") {
                            move(to: max(0, Int(ceil(-contentOffset / (tileSize + spacing))) - 1), proxy: proxy)
                        }.padding(.leading, 8)
                    }
                }
                .overlay(alignment: .trailing) {
                    let contentWidth = CGFloat(images.count) * (tileSize + spacing) - spacing
                    if contentWidth + contentOffset > viewport.size.width + 1 {
                        navigationButton("chevron.right", label: "下一张图片") {
                            move(to: min(images.count - 1, Int(floor(-contentOffset / (tileSize + spacing))) + 1), proxy: proxy)
                        }.padding(.trailing, 8)
                    }
                }
            }
        }
        .coordinateSpace(name: scrollSpace)
        .frame(height: tileSize)
    }

    private func navigationButton(_ icon: String, label: LocalizedStringKey,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) { ChatImageActionIcon(name: icon) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    private func move(to index: Int, proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            proxy.scrollTo(index, anchor: .leading)
        }
    }
}

private struct ChatGalleryScrollOffset: ViewModifier {
    @Binding var offset: CGFloat
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollGeometryChange(for: CGFloat.self) {
                -($0.contentOffset.x + $0.contentInsets.leading)
            } action: { _, value in offset = value }
        } else { content }
    }
}

private struct ChatGalleryOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ChatImageTile: View {
    let photo: ChatGalleryImage
    @State private var image: NSImage?
    @State private var failed = false
    @State private var retry = 0
    @State private var sourceError = false

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    GeometryReader { geometry in
                        Button {
                            ChatImagePreviewWindow.shared.show(image: image, label: photo.label)
                        } label: {
                            Image(nsImage: image).resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped().contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(photo.label.isEmpty ? NSLocalizedString("预览图片", comment: "") : photo.label)
                        .help("预览图片")
                    }
                } else {
                    VStack(spacing: 8) {
                        if failed {
                            Image(mingCute: "photo", size: 24)
                            Text("图片加载失败").font(.system(size: 12))
                            Button("重试") { retry += 1 }.buttonStyle(.plain).underline()
                        } else { ProgressView().controlSize(.small) }
                    }
                    .foregroundStyle(ThemeColor.kTextSubtle)
                }
            }
            .background(ThemeColor.kBackgroundNeutral)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                if let source = photo.sourceURL {
                    Button {
                        sourceError = !ToolService.openLauncherURL(source)
                    } label: { ChatImageActionIcon(name: "link") }
                        .buttonStyle(.plain)
                        .help("图片来源")
                        .accessibilityLabel("图片来源")
                        .padding(8)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if image != nil { ChatImageDownloadButton(url: photo.url).padding(8) }
            }
            .appDialog(NSLocalizedString("无法打开链接", comment: ""), isPresented: $sourceError,
                       message: NSLocalizedString("无法打开链接，请检查网址或默认浏览器。", comment: ""),
                       buttons: [NSLocalizedString("好", comment: "")])
            .task(id: "\(photo.url.absoluteString)-\(retry)") {
                image = nil
                failed = false
                do {
                    let data = try await ChatImageService.shared.imageData(from: photo.url)
                    try Task.checkCancellation()
                    guard let decoded = NSImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                    image = decoded
                } catch {
                    if !Task.isCancelled { failed = true }
                }
            }
    }
}

private struct ChatImageActionIcon: View {
    var name: String
    var loading = false
    var body: some View {
        Group {
            if loading { ProgressView().controlSize(.small) }
            else { Image(mingCute: name, size: 16) }
        }
        .frame(width: 16, height: 16)
        .foregroundStyle(ThemeColor.kIcon)
        .frame(width: 32, height: 32)
        .nativeGlassBackground(in: Circle(), interactive: true)
    }
}

private struct ChatImageDownloadButton: View {
    let url: URL
    @State private var downloading = false
    @State private var downloaded = false
    @State private var downloadError: String?

    var body: some View {
        Button {
            downloaded = false
            downloading = true
            Task {
                defer { downloading = false }
                do {
                    _ = try await ChatImageService.shared.download(from: url)
                    downloaded = true
                } catch { downloadError = error.localizedDescription }
            }
        } label: {
            ChatImageActionIcon(name: downloaded ? "checkmark" : "arrow.down.to.line", loading: downloading)
        }
        .buttonStyle(.plain)
        .disabled(downloading)
        .help(downloaded ? LocalizedStringKey("已保存到下载文件夹") : LocalizedStringKey("下载图片"))
        .accessibilityLabel(downloaded ? LocalizedStringKey("已保存到下载文件夹") : LocalizedStringKey("下载图片"))
        .appDialog(NSLocalizedString("图片下载失败", comment: ""), isPresented: Binding(
            get: { downloadError != nil }, set: { if !$0 { downloadError = nil } }),
                   message: downloadError ?? "", buttons: [NSLocalizedString("好", comment: "")])
        .task(id: downloaded) {
            guard downloaded else { return }
            do {
                try await Task.sleep(for: .milliseconds(1200))
                downloaded = false
            } catch {}
        }
    }
}

/// One reusable native image window; history and live answers open the same surface.
@MainActor
final class ChatImagePreviewWindow: NSWindowController, NSWindowDelegate {
    static let shared = ChatImagePreviewWindow()
    private let presentation = WindowPresentation()

    private init() { super.init(window: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(image: NSImage, label: String) {
        let window: NSWindow
        if let existing = self.window { window = existing }
        else {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.contentMinSize = NSSize(width: 320, height: 280)
            self.window = window
            window.center()
        }
        window.title = label.isEmpty ? NSLocalizedString("图片预览", comment: "") : label
        let host = NSHostingView(rootView: ChatImagePreview(image: image, label: label))
        host.frame = NSRect(origin: .zero, size: window.contentRect(forFrameRect: window.frame).size)
        window.contentView = WindowSurface.glassContentView(host, cornerRadius: 16)
        presentation.show(window, afterActivation: true)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
    }
}

private struct ChatImagePreview: View {
    let image: NSImage
    let label: String
    var body: some View {
        Image(nsImage: image).resizable().scaledToFit()
            .accessibilityLabel(label)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16).padding(.top, 28)
            .windowSurfaceBackground(in: RoundedRectangle(cornerRadius: 16))
            .ignoresSafeArea()
    }
}
