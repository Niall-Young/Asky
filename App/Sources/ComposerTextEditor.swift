import AppKit
import SwiftUI
import LocalStore
import Theme

struct ComposerTagInsertion: Identifiable, Equatable {
    let id = UUID()
    let kind: InlineTagKind
    let atStart: Bool
}

private final class ComposerTextView: NSTextView {
    var pasteAttachment: () -> Bool = { false }
    var pasteLongText: (String) -> InlineTagKind? = { _ in nil }
    var onRevealReply: ((String) -> Void)?
    var shortcuts = SettingsPreferences()
    var submit: () -> Void = {}
    var focusChanged: (Bool) -> Void = { _ in }
    var tagAppearance = InlineTagAppearance(colorScheme: .light, inBubble: false, reduceTransparency: false)
    var placeholderColor: NSColor = .placeholderTextColor {
        didSet { needsDisplay = true }
    }
    var baseTextColor: NSColor = .labelColor {
        didSet {
            textColor = baseTextColor
            updateTypingAttributes()
        }
    }

    private let popoverPresenter = InlineTagPopoverPresenter()
    private var tracking: NSTrackingArea?

    static let bodyFont = NSFont.systemFont(ofSize: 14, weight: .regular)
    static var bodyParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = max(0, TextStyle(size: 14, weight: 400, mode: .default).lineHeight - 14 * 1.2)
        return style
    }

    func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: Self.bodyFont,
            .foregroundColor: baseTextColor,
            .paragraphStyle: Self.bodyParagraphStyle
        ]
    }

    func updateTypingAttributes() {
        typingAttributes = baseAttributes()
    }

    func insertInlineTag(_ kind: InlineTagKind, atStart: Bool) {
        guard let storage = textStorage else { return }
        let attachment = InlineTagAttachment(kind: kind, appearance: tagAppearance)
        let fragment = NSMutableAttributedString(attachment: attachment)
        fragment.addAttributes(baseAttributes(), range: NSRange(location: 0, length: fragment.length))

        let targetRange: NSRange
        if atStart {
            targetRange = NSRange(location: 0, length: 0)
            // Add a trailing space when inserting a leading reply tag before existing text.
            if storage.length > 0 {
                let firstChar = (storage.string as NSString).substring(to: 1)
                if firstChar != " " {
                    fragment.append(NSAttributedString(string: " ", attributes: baseAttributes()))
                }
            }
        } else {
            targetRange = selectedRange()
        }

        if shouldChangeText(in: targetRange, replacementString: fragment.string) {
            storage.replaceCharacters(in: targetRange, with: fragment)
            didChangeText()
            let newCursor = targetRange.location + fragment.length
            setSelectedRange(NSRange(location: newCursor, length: 0))
            updateTypingAttributes()
        }
    }

    func refreshTagAppearances() {
        guard let storage = textStorage, storage.length > 0 else { return }
        var changed = false
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let tag = value as? InlineTagAttachment else { return }
            if tag.appearance != tagAppearance {
                tag.update(appearance: tagAppearance)
                layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                layoutManager?.invalidateDisplay(forCharacterRange: range)
                changed = true
            }
        }
        if changed { needsDisplay = true }
    }

    func extractSegments() -> [MessageSegment] {
        guard let storage = textStorage, storage.length > 0 else { return [] }
        var segments: [MessageSegment] = []
        var buffer = ""
        let full = storage.string as NSString

        func flushBuffer() {
            if !buffer.isEmpty {
                segments.append(.text(buffer))
                buffer = ""
            }
        }

        var index = 0
        while index < storage.length {
            var effective = NSRange()
            if let tag = storage.attribute(.attachment, at: index, effectiveRange: &effective) as? InlineTagAttachment {
                flushBuffer()
                segments.append(tag.kind.segment)
                index += 1
            } else {
                let nextRange = NSRange(location: index, length: min(effective.length, storage.length - index))
                let chunk = full.substring(with: nextRange).replacingOccurrences(of: "\u{FFFC}", with: "")
                buffer.append(chunk)
                index = nextRange.location + nextRange.length
            }
        }
        flushBuffer()
        return segments
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    private func tagAt(windowPoint: NSPoint) -> (InlineTagAttachment, Int, NSRect)? {
        guard let storage = textStorage, let layout = layoutManager, let container = textContainer else { return nil }
        let pt = convert(windowPoint, from: nil)
        let containerPt = NSPoint(x: pt.x - textContainerOrigin.x, y: pt.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let index = layout.characterIndex(for: containerPt, in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
        guard index < storage.length,
              let attachment = storage.attribute(.attachment, at: index, effectiveRange: nil) as? InlineTagAttachment else {
            return nil
        }
        let glyphRange = layout.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        var rect = layout.boundingRect(forGlyphRange: glyphRange, in: container)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        guard rect.insetBy(dx: -2, dy: -2).contains(pt) else { return nil }
        return (attachment, index, rect)
    }

    override func mouseMoved(with event: NSEvent) {
        if let (tag, _, _) = tagAt(windowPoint: event.locationInWindow) {
            toolTip = tag.kind.helpText
            NSCursor.pointingHand.set()
        } else {
            toolTip = nil
            super.mouseMoved(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let (tag, index, rect) = tagAt(windowPoint: event.locationInWindow) {
            let expand: (() -> Void)? = {
                if case .pastedText(let snippet) = tag.kind {
                    return { [weak self] in self?.replaceTag(at: index, with: snippet.text) }
                }
                return nil
            }()
            let reveal: (() -> Void)? = {
                if case .reply(let quote) = tag.kind {
                    return { [weak self] in self?.onRevealReply?(quote.sourceMessageID) }
                }
                return nil
            }()
            popoverPresenter.show(
                kind: tag.kind,
                relativeTo: rect,
                of: self,
                onExpandPasted: expand,
                onRevealReply: reveal,
                onRemove: { [weak self] in self?.replaceTag(at: index, with: "") }
            )
            return
        }
        super.mouseDown(with: event)
    }

    private func replaceTag(at index: Int, with replacement: String) {
        guard let storage = textStorage, index < storage.length,
              storage.attribute(.attachment, at: index, effectiveRange: nil) is InlineTagAttachment else { return }
        let range = NSRange(location: index, length: 1)
        if shouldChangeText(in: range, replacementString: replacement) {
            storage.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: baseAttributes()))
            didChangeText()
            setSelectedRange(NSRange(location: index + (replacement as NSString).length, length: 0))
            updateTypingAttributes()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard (textStorage?.length ?? 0) == 0, !hasMarkedText(), let textContainer else { return }
        // Use TextKit for both the hint and input so their first glyph and
        // baseline agree, including the insertion point in an empty editor.
        let storage = NSTextStorage(string: NSLocalizedString("输入你的任务", comment: ""), attributes: [
            .font: Self.bodyFont, .foregroundColor: placeholderColor, .paragraphStyle: Self.bodyParagraphStyle
        ])
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: textContainer.containerSize)
        container.lineFragmentPadding = textContainer.lineFragmentPadding
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let glyphs = layout.glyphRange(for: container)
        layout.drawGlyphs(forGlyphRange: glyphs, at: textContainerOrigin)
    }

    override func didChangeText() {
        super.didChangeText()
        normalizeTextAttributes()
        updateTypingAttributes()
        needsDisplay = true
    }

    private func normalizeTextAttributes() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.addAttributes(baseAttributes(), range: fullRange)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            updateTypingAttributes()
            focusChanged(true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { focusChanged(false) }
        return accepted
    }

    // This accessory app has no standard Edit menu. Handle the responder's
    // paste shortcut directly, including image-only pasteboards that plain
    // NSTextView would otherwise mark as unavailable.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if !hasMarkedText(), shortcuts.shortcut(.send).matches(event) {
            submit(); return true
        }
        if !hasMarkedText(), shortcuts.shortcut(.newline).matches(event) {
            insertNewlineIgnoringFieldEditor(nil); return true
        }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return true
        }
        if mods == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "v" {
            pasteAsPlainText(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if !hasMarkedText(), shortcuts.shortcut(.send).matches(event) { submit(); return }
        if !hasMarkedText(), shortcuts.shortcut(.newline).matches(event) {
            insertNewlineIgnoringFieldEditor(nil); return
        }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
        } else if mods == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "v" {
            pasteAsPlainText(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)) || item.action == #selector(pasteAsPlainText(_:)) { return true }
        return super.validateUserInterfaceItem(item)
    }

    override func paste(_ sender: Any?) {
        if pasteAttachment() { return }
        guard let string = NSPasteboard.general.string(forType: .string), !string.isEmpty else { return }
        if let collapsed = pasteLongText(string) {
            insertInlineTag(collapsed, atStart: false)
            return
        }
        insertPlainString(string)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        guard let string = NSPasteboard.general.string(forType: .string), !string.isEmpty else { return }
        insertPlainString(string)
    }

    private func insertPlainString(_ string: String) {
        let range = selectedRange()
        if shouldChangeText(in: range, replacementString: string) {
            textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: string, attributes: baseAttributes()))
            didChangeText()
            setSelectedRange(NSRange(location: range.location + (string as NSString).length, length: 0))
        }
    }
}

struct ComposerTextEditor: NSViewRepresentable {
    @Binding var height: CGFloat
    @Binding var isFocused: Bool
    var resetRevision: Int
    var pendingInsertions: [ComposerTagInsertion]
    var consumeInsertions: ([UUID]) -> Void
    var onSegmentsChanged: ([MessageSegment]) -> Void
    var pasteAttachment: () -> Bool
    var pasteLongText: (String) -> InlineTagKind?
    var onRevealReply: (String) -> Void
    var submit: () -> Void
    var shortcuts = SettingsPreferences()
    @Environment(\.chatSelectionColor) private var selectionColor
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let editor = ComposerTextView()
        editor.isRichText = true
        editor.allowsUndo = true
        editor.importsGraphics = false
        editor.drawsBackground = false
        editor.font = ComposerTextView.bodyFont
        editor.updateTypingAttributes()
        // Keep text 12 pt from the glass while the scroll view sits only 4 pt in.
        editor.textContainerInset = NSSize(width: 8, height: 4)
        editor.textContainer?.lineFragmentPadding = 0
        editor.minSize = NSSize(width: 0, height: 28)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.focusChanged = { [weak coordinator = context.coordinator] focused in
            DispatchQueue.main.async { coordinator?.parent.isFocused = focused }
        }
        editor.setAccessibilityLabel(NSLocalizedString("消息输入", comment: ""))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = editor
        context.coordinator.editor = editor
        DispatchQueue.main.async { [weak editor] in
            guard let editor else { return }
            editor.window?.makeFirstResponder(editor)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? ComposerTextView else { return }
        context.coordinator.parent = self
        editor.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(28, editor.frame.height)))
        editor.pasteAttachment = pasteAttachment
        editor.pasteLongText = pasteLongText
        editor.onRevealReply = onRevealReply
        editor.shortcuts = shortcuts
        editor.submit = submit
        editor.baseTextColor = NSColor(ThemeColor.kText.color(for: colorScheme))
        editor.placeholderColor = NSColor(ThemeColor.kTextSubtlest.color(for: colorScheme))
        editor.selectedTextAttributes = [.backgroundColor: NSColor(selectionColor).withAlphaComponent(0.45)]
        editor.insertionPointColor = editor.baseTextColor

        let appearance = InlineTagAppearance(colorScheme: colorScheme, inBubble: false, reduceTransparency: reduceTransparency)
        if editor.tagAppearance != appearance {
            editor.tagAppearance = appearance
            editor.refreshTagAppearances()
        }

        if context.coordinator.lastResetRevision != resetRevision {
            context.coordinator.lastResetRevision = resetRevision
            editor.textStorage?.setAttributedString(NSAttributedString())
            editor.updateTypingAttributes()
            editor.needsDisplay = true
        }

        if !pendingInsertions.isEmpty {
            let unseen = pendingInsertions.filter { !context.coordinator.appliedInsertionIDs.contains($0.id) }
            if !unseen.isEmpty {
                for insertion in unseen {
                    context.coordinator.appliedInsertionIDs.insert(insertion.id)
                    editor.insertInlineTag(insertion.kind, atStart: insertion.atStart)
                }
                let ids = unseen.map(\.id)
                DispatchQueue.main.async {
                    consumeInsertions(ids)
                }
            }
        }

        if isFocused, editor.window?.firstResponder !== editor {
            editor.window?.makeFirstResponder(editor)
        }
        context.coordinator.updateHeight()
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextEditor
        fileprivate weak var editor: ComposerTextView?
        var lastResetRevision = 0
        var appliedInsertionIDs: Set<UUID> = []

        init(_ parent: ComposerTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor else { return }
            let segments = editor.extractSegments()
            parent.onSegmentsChanged(segments)
            updateHeight()
        }

        func updateHeight() {
            guard let editor, let container = editor.textContainer, let layout = editor.layoutManager else { return }
            layout.ensureLayout(for: container)
            let height = min(160, max(28, layout.usedRect(for: container).height + 8))
            if abs(parent.height - height) > 1 {
                DispatchQueue.main.async { [weak self] in self?.parent.height = height }
            }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            return false
        }
    }
}
