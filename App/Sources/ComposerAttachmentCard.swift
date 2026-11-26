import AppKit
import SwiftUI
import Contracts
import LocalStore
import MarkdownUI
import Theme
import ToolService

struct ComposerAttachmentCard: View {
    let attachment: AttachmentRef?
    let thumbnail: Data?
    private var quoteNumber: Int? = nil
    private var replyPreview: String? = nil
    var remove: (() -> Void)? = nil
    var imageSize: CGFloat = 52
    @State private var loadedThumbnail: Data?
    @State private var hovering = false
    @FocusState private var deleteFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(attachment: AttachmentRef, thumbnail: Data?, remove: (() -> Void)? = nil, imageSize: CGFloat = 52) {
        self.attachment = attachment
        self.thumbnail = thumbnail
        self.remove = remove
        self.imageSize = imageSize
    }

    /// Whole-message replies preview the answer; selected excerpts retain their numbered label.
    init(quote: MessageQuote, quoteNumber: Int, remove: (() -> Void)? = nil) {
        attachment = nil
        thumbnail = nil
        self.quoteNumber = quoteNumber
        self.remove = remove
        if quote.kind == .reply {
            let content = ChatFormParser.parse(quote.text, streaming: false).compactMap { part -> String? in
                switch part.content {
                case .markdown(let text): text
                case .form(let form): form.title ?? form.fields.map(\.label).joined(separator: "、")
                }
            }.joined(separator: "\n")
            let plain = MarkdownContent(content).renderPlainText()
            replyPreview = plain.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }

    private var name: String {
        if let attachment { return URL(filePath: attachment.path).lastPathComponent }
        if let replyPreview { return replyPreview }
        return String(format: NSLocalizedString("引用的文本 %d", comment: ""), quoteNumber ?? 1)
    }
    private var active: Bool { hovering || deleteFocused }
    private var iconFill: Color {
        reduceTransparency
            ? ThemeColor.kBackground.color(for: colorScheme)
            : ThemeColor.kBackgroundNeutral.color(for: colorScheme)
    }
    var body: some View {
        Group {
            if attachment?.kind == .image {
                ZStack {
                    if let data = thumbnail ?? loadedThumbnail, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        Image(mingCute: "photo", size: 28)
                    }
                }
                .frame(width: imageSize, height: imageSize).clipped()
            } else {
                HStack(spacing: 12) {
                    Image(mingCute: replyPreview == nil ? "text.document" : "text.bubble", size: 24)
                        .foregroundStyle(ThemeColor.kIconSubtle.color(for: colorScheme))
                        .frame(width: 44, height: 44)
                        .background(iconFill, in: .rect(cornerRadius: 8))
                    if let replyPreview {
                        Text(replyPreview).textStyle(.button)
                            .foregroundStyle(ThemeColor.kText.color(for: colorScheme))
                            .lineLimit(2).truncationMode(.tail)
                            .frame(width: 224, height: 44, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(name).textStyle(.button)
                                .foregroundStyle(ThemeColor.kText.color(for: colorScheme))
                                .lineLimit(1).truncationMode(.tail)
                                .frame(height: 22, alignment: .leading)
                            if let attachment {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteSize), countStyle: .file))
                                    .textStyle(.secondary).foregroundStyle(ThemeColor.kTextSubtlest.color(for: colorScheme))
                                    .lineLimit(1).frame(height: 20, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: 128, alignment: .leading)
                    }
                }
                .padding(.leading, 4).padding(.trailing, 20).padding(.vertical, 4).frame(height: 52)
            }
        }
        .background(ThemeColor(active ? "backgroundNeutralHover" : "backgroundNeutral").color(for: colorScheme))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if let remove {
                Button(action: remove) {
                    Image(mingCute: "xmark", size: 14)
                        .foregroundStyle(ThemeColor("iconInverted").color(for: colorScheme))
                        .frame(width: 20, height: 20)
                        .background(ThemeColor.kBackgroundPrimary, in: .circle)
                }
                .buttonStyle(.plain).focused($deleteFocused)
                .actionArrowCursor(enabled: active)
                .accessibilityLabel(attachment == nil ? NSLocalizedString("移除引用", comment: "") : String(format: NSLocalizedString("删除附件：%@", comment: ""), name))
                .opacity(active ? 1 : 0)
                .offset(x: attachment?.kind == .image ? 6 : 8, y: -6)
            }
        }
        // Reserve vertical overhang here; the row reserves trailing space once.
        .padding(.top, remove == nil ? 0 : 6)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .task(id: attachment) {
            guard let attachment, thumbnail == nil, attachment.kind == .image else { return }
            let reference = attachment
            loadedThumbnail = await Task.detached(priority: .utility) {
                ComposerAttachmentService.preview(reference).thumbnail
            }.value
        }
        .help(name)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
    }
}
