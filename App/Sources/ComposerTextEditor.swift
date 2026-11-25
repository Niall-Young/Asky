import AppKit
import SwiftUI
import LocalStore
import Theme

struct ComposerTagInsertion: Identifiable, Equatable {
    let id = UUID()
    let kind: InlineTagKind
    let atStart: Bool
}

/// Keeps plain text lines and inline-tag lines at identical height and baseline
/// so inserting or removing a tag never shifts the composer height or text baseline.
private final class ComposerLineLayoutDelegate: NSObject, NSLayoutManagerDelegate {
    let lineHeight: CGFloat
    let lineSpacing: CGFloat
    let baseline: CGFloat

    init(lineHeight: CGFloat, lineSpacing: CGFloat, baseline: CGFloat) {
        self.lineHeight = lineHeight
        self.lineSpacing = lineSpacing
        self.baseline = baseline
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        var changed = false
        if lineFragmentRect.pointee.height < lineHeight {
            lineFragmentRect.pointee.size.height = lineHeight
            changed = true
        }
        if lineFragmentUsedRect.pointee.height < lineHeight {
            lineFragmentUsedRect.pointee.size.height = lineHeight
            changed = true
        }
        if lineFragmentUsedRect.pointee.height <= lineHeight + lineSpacing + 0.5,
           abs(baselineOffset.pointee - baseline) > 0.01 {
            baselineOffset.pointee = baseline
            changed = true
        }
        return changed
    }
}

private final class ComposerScrollView: NSScrollView {
    override func setFrameOrigin(_ newOrigin: NSPoint) {
        let changed = frame.origin != newOrigin
        super.setFrameOrigin(newOrigin)
        if changed { invalidateIMEIfComposing() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = frame.size != newSize
        super.setFrameSize(newSize)
        if changed { invalidateIMEIfComposing() }
    }

    private func invalidateIMEIfComposing() {
        guard let editor = documentView as? ComposerTextView, editor.hasMarkedText() else { return }
        editor.inputContext?.invalidateCharacterCoordinates()
    }
}

private final class ComposerTextView: NSTextView {
    var pasteAttachment: () -> Bool = { false }
    var pasteLongText: (String) -> InlineTagKind? = { _ in nil }
    var onRevealReply: ((String) -> Void)?
    var onMarkedTextChanged: ((Bool) -> Void)?
    var shortcuts = SettingsPreferences()
    var submit: () -> Void = {}
    var focusChanged: (Bool) -> Void = { _ in }
    var tagAppearance = InlineTagAppearance(colorScheme: .light, inBubble: false, reduceTransparency: false)
    var placeholderColor: NSColor = .placeholderTextColor {
        didSet {
            if (textStorage?.length ?? 0) == 0 { needsDisplay = true }
        }
    }
    var baseTextColor: NSColor = .labelColor

    private let popoverPresenter = InlineTagPopoverPresenter()
    private var tracking: NSTrackingArea?
    private weak var hoveredTag: InlineTagAttachment?
    private var hoveredTagIndex: Int?

    static let lineHeight: CGFloat = InlineTagAttachment.pillHeight
    static let lineSpacing: CGFloat = 3
    static let verticalInset: CGFloat = 3
    static let minEditorHeight: CGFloat = lineHeight + verticalInset * 2
    static let maxEditorHeight: CGFloat = 160
    static let bodyFont = NSFont.systemFont(ofSize: 14, weight: .regular)
    static let maxCaretHeight: CGFloat = ceil(bodyFont.ascender - bodyFont.descender) + 1
    static let lineBaseline: CGFloat = InlineTagAttachment.pillHeight + InlineTagAttachment.pillYOffset
    static let bodyParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.lineSpacing = lineSpacing
        return style.copy() as! NSParagraphStyle
    }()
    let lineLayoutDelegate = ComposerLineLayoutDelegate(
        lineHeight: lineHeight,
        lineSpacing: lineSpacing,
        baseline: lineBaseline
    )

    func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: Self.bodyFont,
            .foregroundColor: baseTextColor,
            .paragraphStyle: Self.bodyParagraphStyle
        ]
    }

    func updateTypingAttributes() {
        let expected = baseAttributes()
        if (typingAttributes[.font] as? NSFont) == Self.bodyFont,
           (typingAttributes[.foregroundColor] as? NSColor) == baseTextColor,
           (typingAttributes[.paragraphStyle] as? NSParagraphStyle) == Self.bodyParagraphStyle,
           typingAttributes.count == expected.count {
            return
        }
        typingAttributes = expected
    }

    func applyThemeColors(text: NSColor, placeholder: NSColor) {
        baseTextColor = text
        placeholderColor = placeholder
        insertionPointColor = text
        guard !hasMarkedText() else { return }
        updateTypingAttributes()
        guard let storage = textStorage, storage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: text, range: fullRange)
        storage.endEditing()
    }

    func naturalContentHeight() -> CGFloat {
        guard let container = textContainer, let layout = layoutManager else { return Self.minEditorHeight }
        layout.ensureLayout(for: container)
        return ceil(layout.usedRect(for: container).height + textContainerInset.height * 2)
    }

    func pinScrollToTop() {
        guard let scroll = enclosingScrollView else { return }
        if scroll.contentView.bounds.origin != .zero {
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    override func scrollToVisible(_ rect: NSRect) -> Bool {
        // While the composer is still below maxEditorHeight it grows to fit all lines;
        // suppress intermediate clip-view scrolling so line 1 never vanishes before resize.
        if naturalContentHeight() <= Self.maxEditorHeight {
            pinScrollToTop()
            return false
        }
        return super.scrollToVisible(rect)
    }

    private func clampedCaretRect(_ rect: NSRect) -> NSRect {
        guard rect.height > Self.maxCaretHeight else { return rect }
        let effectiveLineHeight = min(rect.height, Self.lineHeight)
        let delta = floor((effectiveLineHeight - Self.maxCaretHeight) / 2)
        return NSRect(x: rect.origin.x, y: rect.origin.y + delta,
                      width: rect.width, height: Self.maxCaretHeight)
    }

    private func clampInsertionIndicators(in view: NSView) {
        for subview in view.subviews {
            if subview is NSTextInsertionIndicator {
                let clamped = clampedCaretRect(subview.frame)
                if clamped != subview.frame {
                    subview.frame = clamped
                }
            } else if !subview.subviews.isEmpty {
                clampInsertionIndicators(in: subview)
            }
        }
    }

    override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
        super.updateInsertionPointStateAndRestartTimer(restartFlag)
        clampInsertionIndicators(in: self)
    }

    override func layout() {
        super.layout()
        clampInsertionIndicators(in: self)
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        super.drawInsertionPoint(in: clampedCaretRect(rect), color: color, turnedOn: flag)
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

    private func isPointInCloseButton(_ pt: NSPoint, tag: InlineTagAttachment, rect: NSRect) -> Bool {
        let atLineStart = rect.minX - textContainerOrigin.x <= 0.5
        let closeRect = NSRect(x: rect.minX, y: rect.minY, width: tag.closeHitWidth(atLineStart: atLineStart), height: rect.height)
        return closeRect.insetBy(dx: -2, dy: -2).contains(pt)
    }

    private func invalidateTagDisplay(at index: Int) {
        guard let storage = textStorage, index >= 0, index < storage.length else {
            needsDisplay = true
            return
        }
        layoutManager?.invalidateDisplay(forCharacterRange: NSRange(location: index, length: 1))
        needsDisplay = true
    }

    func clearHoveredTag() {
        guard let previous = hoveredTag else {
            hoveredTagIndex = nil
            return
        }
        let changed = previous.setHoverState(.none)
        let prevIndex = hoveredTagIndex
        hoveredTag = nil
        hoveredTagIndex = nil
        if changed {
            if let prevIndex {
                invalidateTagDisplay(at: prevIndex)
            } else {
                needsDisplay = true
            }
        }
    }

    func resetDraft() {
        clearHoveredTag()
        popoverPresenter.close()
        if hasMarkedText() {
            unmarkText()
        }
        textStorage?.setAttributedString(NSAttributedString())
        updateTypingAttributes()
        needsDisplay = true
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onMarkedTextChanged?(hasMarkedText())
    }

    override func unmarkText() {
        super.unmarkText()
        onMarkedTextChanged?(hasMarkedText())
        if (textStorage?.length ?? 0) == 0 {
            needsDisplay = true
        }
    }

    override func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let rect = super.firstRect(forCharacterRange: aRange, actualRange: actualRange)
        if rect.height > 0 { return rect }
        return fallbackFirstRect(forCharacterRange: aRange, actualRange: actualRange) ?? rect
    }

    private func fallbackFirstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer?) -> NSRect? {
        guard aRange.location != NSNotFound,
              let storage = textStorage,
              let layout = layoutManager,
              let container = textContainer,
              let window else { return nil }
        layout.ensureLayout(for: container)
        let length = storage.length
        let loc = min(aRange.location, length)
        let len = min(aRange.length, max(0, length - loc))

        var localRect: NSRect
        if len > 0 {
            let glyphRange = layout.glyphRange(forCharacterRange: NSRange(location: loc, length: len), actualCharacterRange: nil)
            if glyphRange.length > 0 {
                var lineGlyphRange = NSRange()
                _ = layout.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: &lineGlyphRange)
                let firstLineGlyphs = NSIntersectionRange(glyphRange, lineGlyphRange)
                let targetGlyphs = firstLineGlyphs.length > 0
                    ? firstLineGlyphs
                    : NSRange(location: glyphRange.location, length: 1)
                localRect = layout.boundingRect(forGlyphRange: targetGlyphs, in: container)
                if let actualRange {
                    actualRange.pointee = layout.characterRange(forGlyphRange: targetGlyphs, actualGlyphRange: nil)
                }
            } else {
                localRect = caretContainerRect(at: loc, length: length, layout: layout, container: container)
                if let actualRange { actualRange.pointee = NSRange(location: loc, length: 0) }
            }
        } else {
            localRect = caretContainerRect(at: loc, length: length, layout: layout, container: container)
            if let actualRange { actualRange.pointee = NSRange(location: loc, length: 0) }
        }

        if localRect.height <= 0 {
            localRect.size.height = Self.lineHeight
        }
        localRect.origin.x += textContainerOrigin.x
        localRect.origin.y += textContainerOrigin.y
        let windowRect = convert(localRect, to: nil)
        return window.convertToScreen(windowRect)
    }

    private func caretContainerRect(
        at loc: Int,
        length: Int,
        layout: NSLayoutManager,
        container: NSTextContainer
    ) -> NSRect {
        if length == 0 {
            return NSRect(x: 0, y: 0, width: 0, height: Self.lineHeight)
        }
        if loc == length, layout.extraLineFragmentRect.height > 0 {
            return NSRect(
                x: layout.extraLineFragmentUsedRect.minX,
                y: layout.extraLineFragmentRect.minY,
                width: 0,
                height: layout.extraLineFragmentRect.height
            )
        }
        if loc < length {
            let glyphIndex = layout.glyphIndexForCharacter(at: loc)
            let lineRect = layout.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let glyphLoc = layout.location(forGlyphAt: glyphIndex)
            return NSRect(
                x: lineRect.minX + glyphLoc.x,
                y: lineRect.minY,
                width: 0,
                height: max(lineRect.height, Self.lineHeight)
            )
        }
        let glyphIndex = layout.glyphIndexForCharacter(at: length - 1)
        let glyphRect = layout.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
        return NSRect(
            x: glyphRect.maxX,
            y: glyphRect.minY,
            width: 0,
            height: max(glyphRect.height, Self.lineHeight)
        )
    }

    override func cursorUpdate(with event: NSEvent) {
        guard !ActionArrowCursor.applyIfCovered(event, in: window) else { return }
        super.cursorUpdate(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        if ActionArrowCursor.applyIfCovered(event, in: window) {
            clearHoveredTag()
            toolTip = nil
            return
        }
        let pt = convert(event.locationInWindow, from: nil)
        if let (tag, index, rect) = tagAt(windowPoint: event.locationInWindow) {
            let overClose = isPointInCloseButton(pt, tag: tag, rect: rect)
            let newState: InlineTagHoverState = overClose ? .closeButton : .pill
            if hoveredTag !== tag {
                clearHoveredTag()
                hoveredTag = tag
                hoveredTagIndex = index
            } else {
                hoveredTagIndex = index
            }
            if tag.setHoverState(newState) {
                invalidateTagDisplay(at: index)
            }
            toolTip = overClose ? NSLocalizedString("移除", comment: "") : tag.kind.helpText
            if overClose || tag.kind.supportsComposerPopover {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        } else {
            clearHoveredTag()
            toolTip = nil
            super.mouseMoved(with: event)
        }
    }

    override func mouseExited(with event: NSEvent) {
        clearHoveredTag()
        toolTip = nil
        super.mouseExited(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if let (tag, index, rect) = tagAt(windowPoint: event.locationInWindow) {
            if isPointInCloseButton(pt, tag: tag, rect: rect) {
                clearHoveredTag()
                popoverPresenter.close()
                replaceTag(at: index, with: "")
                return
            }
            if tag.kind.supportsComposerPopover {
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
        layout.delegate = lineLayoutDelegate
        let container = NSTextContainer(containerSize: textContainer.containerSize)
        container.lineFragmentPadding = textContainer.lineFragmentPadding
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let glyphs = layout.glyphRange(for: container)
        layout.drawGlyphs(forGlyphRange: glyphs, at: textContainerOrigin)
    }

    override func didChangeText() {
        super.didChangeText()
        clearHoveredTag()
        if !hasMarkedText() {
            normalizeTextAttributesIfNeeded()
            updateTypingAttributes()
        }
        if (textStorage?.length ?? 0) == 0 {
            needsDisplay = true
        }
    }

    private func normalizeTextAttributesIfNeeded() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        let expectedFont = Self.bodyFont
        let expectedColor = baseTextColor
        let expectedParagraph = Self.bodyParagraphStyle
        var rangesToFix: [NSRange] = []
        storage.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            let fontOK = (attrs[.font] as? NSFont) == expectedFont
            let colorOK = (attrs[.foregroundColor] as? NSColor) == expectedColor
            let paraOK = (attrs[.paragraphStyle] as? NSParagraphStyle) == expectedParagraph
            if !fontOK || !colorOK || !paraOK {
                rangesToFix.append(range)
            }
        }
        guard !rangesToFix.isEmpty else { return }
        let base = baseAttributes()
        storage.beginEditing()
        for range in rangesToFix {
            storage.addAttributes(base, range: range)
        }
        storage.endEditing()
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
    var onMarkedTextChanged: (Bool) -> Void = { _ in }
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
        let scroll = ComposerScrollView()
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let editor = ComposerTextView(frame: NSRect(x: 0, y: 0, width: 0, height: ComposerTextView.minEditorHeight),
                                      textContainer: container)
        layout.delegate = editor.lineLayoutDelegate
        editor.isRichText = true
        editor.allowsUndo = true
        editor.importsGraphics = false
        editor.drawsBackground = false
        editor.font = ComposerTextView.bodyFont
        editor.defaultParagraphStyle = ComposerTextView.bodyParagraphStyle
        editor.updateTypingAttributes()
        // Keep text 12 pt from the glass while the scroll view sits only 4 pt in.
        editor.textContainerInset = NSSize(width: 8, height: ComposerTextView.verticalInset)
        editor.minSize = NSSize(width: 0, height: ComposerTextView.minEditorHeight)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.delegate = context.coordinator
        editor.focusChanged = { [weak coordinator = context.coordinator] focused in
            DispatchQueue.main.async { coordinator?.parent.isFocused = focused }
        }
        editor.onMarkedTextChanged = { [weak coordinator = context.coordinator] composing in
            coordinator?.handleMarkedTextChanged(composing)
        }
        editor.setAccessibilityLabel(NSLocalizedString("消息输入", comment: ""))
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
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
        let targetWidth = scroll.contentSize.width
        if targetWidth > 0, abs(editor.frame.width - targetWidth) > 0.5 {
            editor.setFrameSize(NSSize(width: targetWidth, height: max(ComposerTextView.minEditorHeight, editor.frame.height)))
        }
        editor.pasteAttachment = pasteAttachment
        editor.pasteLongText = pasteLongText
        editor.onRevealReply = onRevealReply
        editor.shortcuts = shortcuts
        editor.submit = submit

        if context.coordinator.lastColorScheme != colorScheme {
            context.coordinator.lastColorScheme = colorScheme
            editor.applyThemeColors(
                text: NSColor(ThemeColor.kText.color(for: colorScheme)),
                placeholder: NSColor(ThemeColor.kTextSubtlest.color(for: colorScheme))
            )
        }
        if context.coordinator.lastSelectionColor != selectionColor {
            context.coordinator.lastSelectionColor = selectionColor
            editor.selectedTextAttributes = [.backgroundColor: NSColor(selectionColor).withAlphaComponent(0.45)]
        }

        let appearance = InlineTagAppearance(colorScheme: colorScheme, inBubble: false, reduceTransparency: reduceTransparency)
        if editor.tagAppearance != appearance {
            editor.tagAppearance = appearance
            editor.refreshTagAppearances()
        }

        if context.coordinator.lastResetRevision != resetRevision {
            context.coordinator.lastResetRevision = resetRevision
            editor.resetDraft()
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
        if editor.hasMarkedText() {
            DispatchQueue.main.async { [weak editor] in
                guard let editor, editor.hasMarkedText() else { return }
                editor.inputContext?.invalidateCharacterCoordinates()
            }
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextEditor
        fileprivate weak var editor: ComposerTextView?
        var lastResetRevision = 0
        var lastColorScheme: ColorScheme?
        var lastSelectionColor: Color?
        var lastMarkedText = false
        var appliedInsertionIDs: Set<UUID> = []

        init(_ parent: ComposerTextEditor) { self.parent = parent }

        func handleMarkedTextChanged(_ composing: Bool) {
            syncMarkedTextState(composing)
            updateHeight()
        }

        private func syncMarkedTextState(_ composing: Bool) {
            guard lastMarkedText != composing else { return }
            lastMarkedText = composing
            DispatchQueue.main.async { [weak self] in
                self?.parent.onMarkedTextChanged(composing)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let editor else { return }
            syncMarkedTextState(editor.hasMarkedText())
            let segments = editor.extractSegments()
            parent.onSegmentsChanged(segments)
            updateHeight()
        }

        func updateHeight() {
            guard let editor, let scroll = editor.enclosingScrollView else { return }
            let natural = editor.naturalContentHeight()
            let needsScroll = natural > ComposerTextView.maxEditorHeight
            let scrollerChanged = scroll.hasVerticalScroller != needsScroll
            if scrollerChanged {
                scroll.hasVerticalScroller = needsScroll
                scroll.tile()
            }
            if needsScroll {
                if editor.frame.height < natural {
                    editor.setFrameSize(NSSize(width: editor.frame.width, height: natural))
                }
                scroll.reflectScrolledClipView(scroll.contentView)
                if scrollerChanged {
                    DispatchQueue.main.async { [weak scroll, weak editor] in
                        guard let scroll else { return }
                        scroll.tile()
                        scroll.reflectScrolledClipView(scroll.contentView)
                        if let editor {
                            editor.scrollRangeToVisible(editor.selectedRange())
                            if editor.hasMarkedText() {
                                editor.inputContext?.invalidateCharacterCoordinates()
                            }
                        }
                        scroll.flashScrollers()
                    }
                } else if editor.hasMarkedText() {
                    editor.scrollRangeToVisible(editor.selectedRange())
                }
            } else {
                editor.pinScrollToTop()
            }
            let height = min(ComposerTextView.maxEditorHeight, max(ComposerTextView.minEditorHeight, natural))
            if abs(parent.height - height) > 1 {
                DispatchQueue.main.async { [weak self] in self?.parent.height = height }
            }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            return false
        }
    }
}
