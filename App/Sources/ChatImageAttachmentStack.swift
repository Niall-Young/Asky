import AppKit
import SwiftUI
import Contracts

/// Keeps the hover region anchored to the message's trailing edge while opening.
struct ChatImageAttachmentStack: View {
    let attachments: [AttachmentRef]
    @State private var hovering = false
    @State private var keyboardExpanded = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var expanded: Bool { hovering || keyboardExpanded }
    private var contentWidth: CGFloat {
        expanded ? CGFloat(attachments.count) * 90 - 10 : 116
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                ZStack(alignment: .leading) {
                    ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                        ComposerAttachmentCard(attachment: attachment, thumbnail: nil, imageSize: 80)
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.18 : 0.7), lineWidth: 1))
                            .rotationEffect(.degrees(expanded ? 0 : rotation(index)))
                            .offset(x: expanded ? CGFloat(index) * 90 : CGFloat(min(index, 2)) * 18)
                            .opacity(expanded || index < 3 ? 1 : 0)
                            .accessibilityHidden(!expanded && index >= 3)
                            .zIndex(Double(index))
                    }
                }
                .frame(width: contentWidth, height: 100, alignment: .leading)
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(!expanded)
            .defaultScrollAnchor(.trailing)
            .frame(width: min(contentWidth + 16, geometry.size.width), height: 100)
            .overlay(alignment: .bottomTrailing) {
                if !expanded && attachments.count > 3 {
                    Text("\(attachments.count)")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.regularMaterial, in: .capsule)
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(.rect)
            .onHover { hovering = $0 }
            .focusable().focused($focused).focusEffectDisabled()
            .onKeyPress(.return) { keyboardExpanded.toggle(); return .handled }
            .onKeyPress(.space) { keyboardExpanded.toggle(); return .handled }
            .onKeyPress(.escape) { keyboardExpanded = false; focused = false; return .handled }
            .onChange(of: focused) { _, focused in
                if !focused { keyboardExpanded = false }
            }
            .accessibilityAction { keyboardExpanded.toggle() }
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86), value: expanded)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 100)
    }

    private func rotation(_ index: Int) -> Double {
        switch index {
        case 0: -7
        case 1: 0
        default: 7
        }
    }
}

#if DEBUG
@MainActor
enum ChatImageAttachmentPreview {
    private static var window: NSWindow?

    static func run() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--test-image-attachments"),
              args.indices.contains(index + 1) else { return }
        let path = args[index + 1]
        let attachments = (0..<6).map { index in
            AttachmentRef(id: "preview-\(index)", kind: .image, path: path,
                          mimeType: "image/png", byteSize: 0, temporary: false)
        }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 320),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Asky"
        panel.appearance = NSAppearance(named: args.contains("--preview-dark") ? .darkAqua : .aqua)
        panel.contentView = NSHostingView(rootView: VStack(alignment: .trailing, spacing: 20) {
            ChatImageAttachmentStack(attachments: Array(attachments.prefix(3)))
            ChatImageAttachmentStack(attachments: attachments)
        }.padding(32))
        window = panel
        NSApp.setActivationPolicy(.regular)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
#endif
