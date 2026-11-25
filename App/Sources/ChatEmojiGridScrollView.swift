import AppKit
import CoreText
import SwiftUI
import Theme

enum ChatEmojiFullPickerLayout {
    static let columns = 8
    static let cellSize: CGFloat = 34
    static let columnSpacing: CGFloat = 2
    static let rowSpacing: CGFloat = 4
    static let horizontalPadding: CGFloat = 10
    static let topPadding: CGFloat = 2
    static let bottomPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 4
    static let sectionTopPadding: CGFloat = 8
    static let headerHeight: CGFloat = 16
    static let headerToGridSpacing: CGFloat = 6
    static let headerHorizontalInset: CGFloat = 4
    static let width: CGFloat = CGFloat(columns) * cellSize
        + CGFloat(columns - 1) * columnSpacing
        + horizontalPadding * 2
    static let preferredHeight: CGFloat = 310
}

@MainActor @Observable
final class ChatEmojiPickerScrollState {
    var activeCategoryID: String
    @ObservationIgnored var scrollToCategoryHandler: ((String, Bool) -> Void)?

    init(initialCategoryID: String) {
        self.activeCategoryID = initialCategoryID
    }

    func selectCategory(_ id: String, animated: Bool) {
        activeCategoryID = id
        scrollToCategoryHandler?(id, animated)
    }
}

/// Deterministic geometry for the static 8-category emoji catalog so hit-testing,
/// active-category tracking, and row virtualization are all O(1)/O(log N) math.
private struct ChatEmojiGridLayout {
    struct Section {
        let index: Int
        let id: String
        let title: String
        let minY: CGFloat
        let maxY: CGFloat
        let headerRect: CGRect
        let gridStartY: CGFloat
        let rowRange: Range<Int>
        let cellRange: Range<Int>
    }

    struct Row {
        let index: Int
        let sectionIndex: Int
        let minY: CGFloat
        let maxY: CGFloat
        let cellRange: Range<Int>
    }

    struct Cell {
        let index: Int
        let sectionIndex: Int
        let emoji: String
        let frame: CGRect
    }

    static let shared = ChatEmojiGridLayout(categories: ChatUserReactionCatalog.categories)

    let sections: [Section]
    let rows: [Row]
    let cells: [Cell]
    let allEmojis: [String]
    let emojiToCellIndex: [String: Int]
    let categoryIDToSectionIndex: [String: Int]
    let totalHeight: CGFloat

    private init(categories: [ChatEmojiCategory]) {
        let columns = ChatEmojiFullPickerLayout.columns
        let cellSize = ChatEmojiFullPickerLayout.cellSize
        let colSpacing = ChatEmojiFullPickerLayout.columnSpacing
        let rowSpacing = ChatEmojiFullPickerLayout.rowSpacing
        let hPad = ChatEmojiFullPickerLayout.horizontalPadding
        let contentWidth = ChatEmojiFullPickerLayout.width - hPad * 2

        var sections: [Section] = []
        var rows: [Row] = []
        var cells: [Cell] = []
        var allEmojis: [String] = []
        var emojiToCellIndex: [String: Int] = [:]
        var categoryIDToSectionIndex: [String: Int] = [:]

        var cursorY = ChatEmojiFullPickerLayout.topPadding

        for (sectionIndex, category) in categories.enumerated() {
            if sectionIndex > 0 {
                cursorY += ChatEmojiFullPickerLayout.sectionSpacing
            }
            let sectionMinY = cursorY
            let headerY = sectionMinY + ChatEmojiFullPickerLayout.sectionTopPadding
            let headerRect = CGRect(
                x: hPad + ChatEmojiFullPickerLayout.headerHorizontalInset,
                y: headerY,
                width: contentWidth - ChatEmojiFullPickerLayout.headerHorizontalInset * 2,
                height: ChatEmojiFullPickerLayout.headerHeight
            )
            let gridStartY = headerRect.maxY + ChatEmojiFullPickerLayout.headerToGridSpacing
            let firstRow = rows.count
            let firstCell = cells.count

            let rowCount = (category.emojis.count + columns - 1) / columns
            for rowInSection in 0..<rowCount {
                let rowMinY = gridStartY + CGFloat(rowInSection) * (cellSize + rowSpacing)
                let rowStartCell = cells.count
                let startEmoji = rowInSection * columns
                let endEmoji = min(startEmoji + columns, category.emojis.count)
                for offset in startEmoji..<endEmoji {
                    let col = offset - startEmoji
                    let emoji = category.emojis[offset]
                    let cellIndex = cells.count
                    let frame = CGRect(
                        x: hPad + CGFloat(col) * (cellSize + colSpacing),
                        y: rowMinY,
                        width: cellSize,
                        height: cellSize
                    )
                    cells.append(Cell(index: cellIndex, sectionIndex: sectionIndex, emoji: emoji, frame: frame))
                    allEmojis.append(emoji)
                    emojiToCellIndex[emoji] = cellIndex
                }
                rows.append(
                    Row(
                        index: rows.count,
                        sectionIndex: sectionIndex,
                        minY: rowMinY,
                        maxY: rowMinY + cellSize,
                        cellRange: rowStartCell..<cells.count
                    )
                )
            }

            let sectionMaxY: CGFloat
            if let lastRow = rows.last, rows.count > firstRow {
                sectionMaxY = lastRow.maxY
            } else {
                sectionMaxY = gridStartY
            }
            categoryIDToSectionIndex[category.id] = sectionIndex
            sections.append(
                Section(
                    index: sectionIndex,
                    id: category.id,
                    title: category.title,
                    minY: sectionMinY,
                    maxY: sectionMaxY,
                    headerRect: headerRect,
                    gridStartY: gridStartY,
                    rowRange: firstRow..<rows.count,
                    cellRange: firstCell..<cells.count
                )
            )
            cursorY = sectionMaxY
        }

        self.sections = sections
        self.rows = rows
        self.cells = cells
        self.allEmojis = allEmojis
        self.emojiToCellIndex = emojiToCellIndex
        self.categoryIDToSectionIndex = categoryIDToSectionIndex
        self.totalHeight = cursorY + ChatEmojiFullPickerLayout.bottomPadding
    }

    func visibleRowRange(in rect: CGRect, overscanRows: Int = 2) -> Range<Int> {
        guard !rows.isEmpty else { return 0..<0 }

        var low = 0
        var high = rows.count
        while low < high {
            let mid = (low + high) / 2
            if rows[mid].maxY < rect.minY {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let firstVisible = low

        low = firstVisible
        high = rows.count
        while low < high {
            let mid = (low + high) / 2
            if rows[mid].minY <= rect.maxY {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let lastVisibleExclusive = low

        let start = max(0, firstVisible - overscanRows)
        let end = min(rows.count, lastVisibleExclusive + overscanRows)
        return start < end ? start..<end : 0..<0
    }

    func cellIndex(at point: CGPoint) -> Int? {
        guard let section = sections.first(where: { point.y >= $0.gridStartY && point.y <= $0.maxY }) else {
            return nil
        }
        let rowPitch = ChatEmojiFullPickerLayout.cellSize + ChatEmojiFullPickerLayout.rowSpacing
        let rowOffset = Int(floor((point.y - section.gridStartY) / rowPitch))
        let globalRowIndex = section.rowRange.lowerBound + rowOffset
        guard section.rowRange.contains(globalRowIndex) else { return nil }
        let row = rows[globalRowIndex]
        guard point.y >= row.minY && point.y <= row.maxY else { return nil }

        let colPitch = ChatEmojiFullPickerLayout.cellSize + ChatEmojiFullPickerLayout.columnSpacing
        let col = Int(floor((point.x - ChatEmojiFullPickerLayout.horizontalPadding) / colPitch))
        guard col >= 0 && col < ChatEmojiFullPickerLayout.columns else { return nil }
        let cellIndex = row.cellRange.lowerBound + col
        guard row.cellRange.contains(cellIndex) else { return nil }
        let cell = cells[cellIndex]
        return cell.frame.contains(point) ? cellIndex : nil
    }

    func activeCategoryID(forScrollY scrollY: CGFloat) -> String {
        let anchorY = scrollY + 18
        if let spanning = sections.first(where: { $0.minY <= anchorY && $0.maxY > anchorY }) {
            return spanning.id
        }
        if let passed = sections.last(where: { $0.minY <= anchorY }) {
            return passed.id
        }
        return sections.first?.id ?? "smileys"
    }
}

/// Thread-safe Retina bitmap cache for Apple Color Emoji glyphs so scrolling never
/// invokes CoreText shaping or SwiftUI Text view materialization on the main thread.
final class ChatEmojiGlyphCache: @unchecked Sendable {
    private final class ImageBox: NSObject {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    static let shared = ChatEmojiGlyphCache()

    private let cache: NSCache<NSString, ImageBox> = {
        let cache = NSCache<NSString, ImageBox>()
        cache.countLimit = 1800
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    private let lock = NSLock()
    private var warmedScaleBuckets: Set<Int> = []

    func prewarmCatalog(scale: CGFloat) {
        prewarmIfNeeded(emojis: ChatEmojiGridLayout.shared.allEmojis, scale: scale)
    }

    func image(for emoji: String, scale: CGFloat) -> CGImage? {
        let clampedScale = max(1, min(scale, 3))
        let key = cacheKey(emoji: emoji, scale: clampedScale)
        if let cached = cache.object(forKey: key) {
            return cached.image
        }
        guard let rendered = Self.renderEmoji(emoji, scale: clampedScale) else { return nil }
        let cost = rendered.bytesPerRow * rendered.height
        cache.setObject(ImageBox(rendered), forKey: key, cost: cost)
        return rendered
    }

    func prewarmIfNeeded(emojis: [String], scale: CGFloat) {
        let clampedScale = max(1, min(scale, 3))
        let bucket = Self.scaleBucket(for: clampedScale)
        lock.lock()
        let inserted = warmedScaleBuckets.insert(bucket).inserted
        lock.unlock()
        guard inserted else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            for emoji in emojis {
                _ = self.image(for: emoji, scale: clampedScale)
            }
        }
    }

    private func cacheKey(emoji: String, scale: CGFloat) -> NSString {
        "\(Self.scaleBucket(for: scale))|\(emoji)" as NSString
    }

    private static func scaleBucket(for scale: CGFloat) -> Int {
        max(100, Int(round(scale * 100)))
    }

    private static func renderEmoji(_ emoji: String, scale: CGFloat) -> CGImage? {
        let cellSize = ChatEmojiFullPickerLayout.cellSize
        let pixelSize = max(1, Int(ceil(cellSize * scale)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false)

        let font = CTFontCreateUIFontForLanguage(.system, 21, nil)
            ?? CTFontCreateWithName("AppleColorEmoji" as CFString, 21, nil)
        let attributes: [CFString: Any] = [kCTFontAttributeName: font]
        guard let attributed = CFAttributedStringCreate(nil, emoji as CFString, attributes as CFDictionary) else {
            return nil
        }
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

        let drawX = (cellSize - width) * 0.5
        let baselineY = (cellSize - (ascent + descent)) * 0.5 + descent
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: drawX, y: baselineY)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}

struct ChatEmojiGridScrollView: NSViewRepresentable {
    let selectedEmoji: String?
    let accentColor: Color
    let initialCategoryID: String
    let scrollState: ChatEmojiPickerScrollState
    let onSelect: (String) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator {
        Coordinator(scrollState: scrollState)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = EmojiGridNSScrollView()
        let documentView = EmojiGridDocumentView(
            layout: .shared,
            onSelect: onSelect,
            onActiveCategoryChanged: { [weak scrollState] categoryID in
                guard let scrollState, scrollState.activeCategoryID != categoryID else { return }
                scrollState.activeCategoryID = categoryID
            }
        )
        documentView.frame = CGRect(
            x: 0,
            y: 0,
            width: ChatEmojiFullPickerLayout.width,
            height: ChatEmojiGridLayout.shared.totalHeight
        )
        scrollView.documentView = documentView
        documentView.attach(to: scrollView)
        documentView.configure(
            selectedEmoji: selectedEmoji,
            accentColor: accentColor,
            scheme: scheme,
            reduceMotion: reduceMotion
        )
        documentView.scheduleInitialCategoryScroll(initialCategoryID)

        context.coordinator.documentView = documentView
        context.coordinator.bindScrollState(scrollState)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.bindScrollState(scrollState)
        guard let documentView = nsView.documentView as? EmojiGridDocumentView else { return }
        documentView.onSelect = onSelect
        documentView.configure(
            selectedEmoji: selectedEmoji,
            accentColor: accentColor,
            scheme: scheme,
            reduceMotion: reduceMotion
        )
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.documentView?.detachObservers()
        coordinator.documentView = nil
    }

    @MainActor
    final class Coordinator {
        fileprivate weak var documentView: EmojiGridDocumentView?
        private weak var boundScrollState: ChatEmojiPickerScrollState?

        init(scrollState: ChatEmojiPickerScrollState) {
            self.boundScrollState = scrollState
        }

        func bindScrollState(_ state: ChatEmojiPickerScrollState) {
            boundScrollState = state
            state.scrollToCategoryHandler = { [weak self] categoryID, animated in
                self?.documentView?.scrollToCategory(categoryID, animated: animated)
            }
        }
    }
}

private final class EmojiGridNSScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        contentView.drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = false
        scrollerStyle = .overlay
        autohidesScrollers = true
        automaticallyAdjustsContentInsets = false
        verticalScrollElasticity = .allowed
        horizontalScrollElasticity = .none
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 18
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        if let doc = documentView as? EmojiGridDocumentView {
            doc.handleScrollViewportLayout()
        }
    }
}

@MainActor
private final class EmojiGridDocumentView: NSView {
    private let layout: ChatEmojiGridLayout
    var onSelect: (String) -> Void
    private let onActiveCategoryChanged: (String) -> Void

    private weak var observedScrollView: NSScrollView?
    private var hoverTrackingArea: NSTrackingArea?

    private var selectedEmoji: String?
    private var selectedIndex: Int?
    private var accentColor: Color = .accentColor
    private var scheme: ColorScheme = .light
    private var reduceMotion = false
    private var lastRenderedScale: CGFloat = 0
    private var lastHeaderScheme: ColorScheme?
    private var lastSelectionKey: String?

    private var pendingInitialCategoryID: String?
    private var ignoreScrollSyncUntil: Date = .distantPast
    private var isLiveScrolling = false

    private var hoveredIndex: Int?
    private var pressedIndex: Int?
    private var trackingPressIndex: Int?

    private let selectionBackgroundLayer = CALayer()
    private let hoverBackgroundLayer = CALayer()
    private let headerContainerLayer = CALayer()
    private let cellsContainerLayer = CALayer()
    private let selectionBadgeLayer = CALayer()

    private var headerLayers: [CALayer] = []
    private var activeCellLayers: [Int: CALayer] = [:]
    private var recycledCellLayers: [CALayer] = []
    private var activeRowRange: Range<Int> = 0..<0

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateLayer() {}

    init(
        layout: ChatEmojiGridLayout,
        onSelect: @escaping (String) -> Void,
        onActiveCategoryChanged: @escaping (String) -> Void
    ) {
        self.layout = layout
        self.onSelect = onSelect
        self.onActiveCategoryChanged = onActiveCategoryChanged
        super.init(frame: .zero)
        wantsLayer = true
        setupLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupLayers() {
        guard let root = layer else { return }
        root.masksToBounds = false

        selectionBackgroundLayer.cornerRadius = 8
        selectionBackgroundLayer.borderWidth = 1.5
        selectionBackgroundLayer.isHidden = true
        root.addSublayer(selectionBackgroundLayer)

        hoverBackgroundLayer.cornerRadius = 8
        hoverBackgroundLayer.isHidden = true
        root.addSublayer(hoverBackgroundLayer)

        root.addSublayer(headerContainerLayer)
        root.addSublayer(cellsContainerLayer)

        selectionBadgeLayer.isHidden = true
        root.addSublayer(selectionBadgeLayer)

        headerLayers = layout.sections.map { section in
            let headerLayer = CALayer()
            headerLayer.frame = section.headerRect
            headerLayer.contentsGravity = .left
            headerContainerLayer.addSublayer(headerLayer)
            return headerLayer
        }
    }

    func attach(to scrollView: NSScrollView) {
        detachObservers()
        observedScrollView = scrollView
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClipBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLiveScrollWillStart(_:)),
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLiveScrollDidEnd(_:)),
            name: NSScrollView.didEndLiveScrollNotification,
            object: scrollView
        )
    }

    func detachObservers() {
        NotificationCenter.default.removeObserver(self)
        observedScrollView = nil
    }

    @objc private func handleClipBoundsDidChange(_ notification: Notification) {
        handleScrollPositionChanged()
    }

    @objc private func handleLiveScrollWillStart(_ notification: Notification) {
        isLiveScrolling = true
        ignoreScrollSyncUntil = .distantPast
        setHoveredIndex(nil, animated: false)
    }

    @objc private func handleLiveScrollDidEnd(_ notification: Notification) {
        isLiveScrolling = false
        refreshHoverForCurrentPointer()
    }

    func scheduleInitialCategoryScroll(_ categoryID: String) {
        if categoryID != layout.sections.first?.id {
            pendingInitialCategoryID = categoryID
        } else {
            pendingInitialCategoryID = nil
        }
    }

    func configure(
        selectedEmoji: String?,
        accentColor: Color,
        scheme: ColorScheme,
        reduceMotion: Bool
    ) {
        let scale = currentBackingScale
        let appearanceChanged = lastHeaderScheme != scheme || lastRenderedScale != scale
        self.selectedEmoji = selectedEmoji
        self.selectedIndex = selectedEmoji.flatMap { layout.emojiToCellIndex[$0] }
        self.accentColor = accentColor
        self.scheme = scheme
        self.reduceMotion = reduceMotion

        if appearanceChanged {
            lastHeaderScheme = scheme
            lastRenderedScale = scale
            updateHeaderImages(scale: scale)
            updateVisibleCellContentsScale(scale: scale)
            ChatEmojiGlyphCache.shared.prewarmIfNeeded(emojis: layout.allEmojis, scale: scale)
        }

        updateSelectionAppearance(scale: scale)
        updateHoverBackgroundColor()
        syncVisibleCells()
    }

    func handleScrollViewportLayout() {
        guard let scrollView = observedScrollView, scrollView.contentView.bounds.height > 0 else { return }
        if let pending = pendingInitialCategoryID {
            pendingInitialCategoryID = nil
            scrollToCategory(pending, animated: false)
        } else {
            syncVisibleCells()
        }
    }

    func scrollToCategory(_ categoryID: String, animated: Bool) {
        guard let scrollView = observedScrollView,
              let sectionIndex = layout.categoryIDToSectionIndex[categoryID] else { return }
        let clipView = scrollView.contentView
        let viewportHeight = clipView.bounds.height
        let maxY = max(0, layout.totalHeight - viewportHeight)
        let targetY = min(max(0, layout.sections[sectionIndex].minY), maxY)
        let targetOrigin = NSPoint(x: 0, y: targetY)

        ignoreScrollSyncUntil = Date().addingTimeInterval(animated ? 0.32 : 0.15)
        setHoveredIndex(nil, animated: false)

        if animated && !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                clipView.animator().setBoundsOrigin(targetOrigin)
            } completionHandler: { [weak scrollView, weak clipView] in
                MainActor.assumeIsolated {
                    if let scrollView, let clipView {
                        scrollView.reflectScrolledClipView(clipView)
                    }
                }
            }
        } else {
            clipView.setBoundsOrigin(targetOrigin)
            scrollView.reflectScrolledClipView(clipView)
            syncVisibleCells()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        let scale = currentBackingScale
        if scale != lastRenderedScale {
            lastRenderedScale = scale
            updateHeaderImages(scale: scale)
            updateSelectionAppearance(scale: scale, force: true)
            updateVisibleCellContentsScale(scale: scale)
        }
        ChatEmojiGlyphCache.shared.prewarmIfNeeded(emojis: layout.allEmojis, scale: scale)
        handleScrollViewportLayout()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = currentBackingScale
        guard scale != lastRenderedScale else { return }
        lastRenderedScale = scale
        updateHeaderImages(scale: scale)
        updateSelectionAppearance(scale: scale, force: true)
        updateVisibleCellContentsScale(scale: scale)
        ChatEmojiGlyphCache.shared.prewarmIfNeeded(emojis: layout.allEmojis, scale: scale)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isLiveScrolling else { return }
        let localPoint = convert(event.locationInWindow, from: nil)
        setHoveredIndex(layout.cellIndex(at: localPoint), animated: true)
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isLiveScrolling else { return }
        let localPoint = convert(event.locationInWindow, from: nil)
        setHoveredIndex(layout.cellIndex(at: localPoint), animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        setHoveredIndex(nil, animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        guard let hit = layout.cellIndex(at: localPoint) else { return }
        trackingPressIndex = hit
        setPressedIndex(hit)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let tracked = trackingPressIndex else { return }
        let localPoint = convert(event.locationInWindow, from: nil)
        let inside = layout.cells[tracked].frame.contains(localPoint)
        setPressedIndex(inside ? tracked : nil)
    }

    override func mouseUp(with event: NSEvent) {
        guard let tracked = trackingPressIndex else { return }
        let localPoint = convert(event.locationInWindow, from: nil)
        let confirmed = layout.cells[tracked].frame.contains(localPoint)
        trackingPressIndex = nil
        setPressedIndex(nil)
        if confirmed {
            onSelect(layout.cells[tracked].emoji)
        }
    }

    override func accessibilityChildren() -> [Any]? {
        guard !activeRowRange.isEmpty else { return [] }
        var elements: [NSAccessibilityElement] = []
        for rowIndex in activeRowRange {
            for cellIndex in layout.rows[rowIndex].cellRange {
                let cell = layout.cells[cellIndex]
                let element = NSAccessibilityElement()
                element.setAccessibilityParent(self)
                element.setAccessibilityRole(.button)
                element.setAccessibilityLabel(cell.emoji)
                element.setAccessibilityIdentifier("bubble-emoji-grid-option-" + cell.emoji)
                element.setAccessibilityFrameInParentSpace(cell.frame)
                elements.append(element)
            }
        }
        return elements
    }

    private var currentBackingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func handleScrollPositionChanged() {
        if hoveredIndex != nil {
            setHoveredIndex(nil, animated: false)
        }
        syncVisibleCells()
        guard Date() >= ignoreScrollSyncUntil,
              let scrollY = observedScrollView?.contentView.bounds.minY else { return }
        let categoryID = layout.activeCategoryID(forScrollY: scrollY)
        onActiveCategoryChanged(categoryID)
    }

    private func syncVisibleCells() {
        let visibleRect = observedScrollView?.contentView.bounds ?? CGRect(
            x: 0,
            y: 0,
            width: ChatEmojiFullPickerLayout.width,
            height: ChatEmojiFullPickerLayout.preferredHeight
        )
        let desiredRows = layout.visibleRowRange(in: visibleRect, overscanRows: 2)
        guard desiredRows != activeRowRange || activeCellLayers.isEmpty else { return }

        let desiredCells: Range<Int>
        if let firstRow = desiredRows.first, let lastRow = desiredRows.last {
            desiredCells = layout.rows[firstRow].cellRange.lowerBound..<layout.rows[lastRow].cellRange.upperBound
        } else {
            desiredCells = 0..<0
        }

        let scale = currentBackingScale
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Recycle cell layers outside the desired window.
        let staleKeys = activeCellLayers.keys.filter { !desiredCells.contains($0) }
        for key in staleKeys {
            if let layer = activeCellLayers.removeValue(forKey: key) {
                layer.removeAllAnimations()
                layer.transform = CATransform3DIdentity
                layer.isHidden = true
                recycledCellLayers.append(layer)
            }
        }

        // Populate newly entered cells from the recycled pool.
        for cellIndex in desiredCells where activeCellLayers[cellIndex] == nil {
            let cell = layout.cells[cellIndex]
            let layer = dequeueCellLayer()
            layer.isHidden = false
            layer.bounds = CGRect(x: 0, y: 0, width: cell.frame.width, height: cell.frame.height)
            layer.position = CGPoint(x: cell.frame.midX, y: cell.frame.midY)
            layer.contentsScale = scale
            layer.contents = ChatEmojiGlyphCache.shared.image(for: cell.emoji, scale: scale)
            let s = desiredScale(for: cellIndex)
            layer.transform = s == 1 ? CATransform3DIdentity : CATransform3DMakeScale(s, s, 1)
            activeCellLayers[cellIndex] = layer
        }

        activeRowRange = desiredRows
        CATransaction.commit()
    }

    private func dequeueCellLayer() -> CALayer {
        if let reused = recycledCellLayers.popLast() {
            return reused
        }
        let layer = CALayer()
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.contentsGravity = .resizeAspect
        layer.magnificationFilter = .trilinear
        layer.minificationFilter = .trilinear
        cellsContainerLayer.addSublayer(layer)
        return layer
    }

    private func updateVisibleCellContentsScale(scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (cellIndex, layer) in activeCellLayers {
            layer.contentsScale = scale
            layer.contents = ChatEmojiGlyphCache.shared.image(for: layout.cells[cellIndex].emoji, scale: scale)
        }
        CATransaction.commit()
    }

    private func refreshHoverForCurrentPointer() {
        guard let window, window.isVisible else { return }
        let pointInWindow = window.mouseLocationOutsideOfEventStream
        let localPoint = convert(pointInWindow, from: nil)
        guard visibleRect.contains(localPoint) else {
            setHoveredIndex(nil, animated: true)
            return
        }
        setHoveredIndex(layout.cellIndex(at: localPoint), animated: true)
    }

    private func setHoveredIndex(_ newIndex: Int?, animated: Bool) {
        guard hoveredIndex != newIndex else { return }
        let oldIndex = hoveredIndex
        hoveredIndex = newIndex

        if let oldIndex {
            applyTransform(for: oldIndex, animated: animated, duration: 0.12)
        }
        if let newIndex {
            applyTransform(for: newIndex, animated: animated, duration: 0.12)
        }
        updateHoverBackgroundLayer()
    }

    private func setPressedIndex(_ newIndex: Int?) {
        guard pressedIndex != newIndex else { return }
        let oldIndex = pressedIndex
        pressedIndex = newIndex

        if let oldIndex {
            applyTransform(for: oldIndex, animated: true, duration: 0.08)
        }
        if let newIndex {
            applyTransform(for: newIndex, animated: true, duration: 0.08)
        }
    }

    private func desiredScale(for cellIndex: Int) -> CGFloat {
        guard !reduceMotion else { return 1 }
        if pressedIndex == cellIndex { return 0.92 }
        if hoveredIndex == cellIndex { return 1.14 }
        return 1
    }

    private func applyTransform(for cellIndex: Int, animated: Bool, duration: CFTimeInterval) {
        guard let layer = activeCellLayers[cellIndex] else { return }
        let scale = desiredScale(for: cellIndex)
        let target = scale == 1 ? CATransform3DIdentity : CATransform3DMakeScale(scale, scale, 1)

        if animated && !reduceMotion {
            let current = layer.presentation()?.transform ?? layer.transform
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = target
            CATransaction.commit()

            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = NSValue(caTransform3D: current)
            animation.toValue = NSValue(caTransform3D: target)
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "emoji-scale")
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.removeAnimation(forKey: "emoji-scale")
            layer.transform = target
            CATransaction.commit()
        }
    }

    private func updateHoverBackgroundLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let hoveredIndex, hoveredIndex != selectedIndex {
            hoverBackgroundLayer.frame = layout.cells[hoveredIndex].frame
            hoverBackgroundLayer.isHidden = false
        } else {
            hoverBackgroundLayer.isHidden = true
        }
        CATransaction.commit()
    }

    private func updateHoverBackgroundColor() {
        let color: NSColor = scheme == .dark
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.07)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hoverBackgroundLayer.backgroundColor = color.cgColor
        CATransaction.commit()
    }

    private func resolvedAppearance() -> NSAppearance {
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua) ?? effectiveAppearance
    }

    private func resolvedCGColor(from color: Color, alpha: CGFloat? = nil) -> CGColor {
        var result: CGColor = NSColor.controlAccentColor.cgColor
        resolvedAppearance().performAsCurrentDrawingAppearance {
            let base = NSColor(color)
            result = (alpha.map { base.withAlphaComponent($0) } ?? base).cgColor
        }
        return result
    }

    private func updateHeaderImages(scale: CGFloat) {
        let textColor = resolvedCGColor(from: ThemeColor.kTextSubtle.color(for: scheme))
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, section) in layout.sections.enumerated() where index < headerLayers.count {
            let layer = headerLayers[index]
            layer.contentsScale = scale
            layer.contents = renderHeaderImage(
                title: section.title,
                size: section.headerRect.size,
                font: font,
                color: textColor,
                scale: scale
            )
        }
        CATransaction.commit()
    }

    private func updateSelectionAppearance(scale: CGFloat, force: Bool = false) {
        let accentCG = resolvedCGColor(from: accentColor)
        let components = accentCG.components?.map { Int(round($0 * 255)) } ?? []
        let selectionKey = "\(selectedEmoji ?? "")|\(scheme == .dark ? "d" : "l")|\(Int(round(scale * 100)))|\(components)"
        guard force || selectionKey != lastSelectionKey else { return }
        lastSelectionKey = selectionKey

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let selectedIndex {
            let cellFrame = layout.cells[selectedIndex].frame
            selectionBackgroundLayer.frame = cellFrame
            selectionBackgroundLayer.backgroundColor = resolvedCGColor(
                from: accentColor,
                alpha: scheme == .dark ? 0.20 : 0.14
            )
            selectionBackgroundLayer.borderColor = accentCG
            selectionBackgroundLayer.isHidden = false

            let badgeSize: CGFloat = 14
            selectionBadgeLayer.frame = CGRect(
                x: cellFrame.maxX - badgeSize + 2,
                y: cellFrame.minY - 2,
                width: badgeSize,
                height: badgeSize
            )
            selectionBadgeLayer.contentsScale = scale
            selectionBadgeLayer.contents = renderSelectionBadgeImage(
                size: badgeSize,
                accentCG: accentCG,
                isDark: scheme == .dark,
                scale: scale
            )
            selectionBadgeLayer.isHidden = false
        } else {
            selectionBackgroundLayer.isHidden = true
            selectionBadgeLayer.isHidden = true
        }
        CATransaction.commit()
        updateHoverBackgroundLayer()
    }

    private func renderHeaderImage(
        title: String,
        size: CGSize,
        font: NSFont,
        color: CGColor,
        scale: CGFloat
    ) -> CGImage? {
        let pixelWidth = max(1, Int(ceil(size.width * scale)))
        let pixelHeight = max(1, Int(ceil(size.height * scale)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(true)

        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font as CTFont,
            kCTForegroundColorAttributeName: color
        ]
        guard let attributed = CFAttributedStringCreate(nil, title as CFString, attributes as CFDictionary) else {
            return nil
        }
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

        let baselineY = (size.height - (ascent + descent)) * 0.5 + descent
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: 0, y: baselineY)
        CTLineDraw(line, context)
        return context.makeImage()
    }

    private func renderSelectionBadgeImage(
        size: CGFloat,
        accentCG: CGColor,
        isDark: Bool,
        scale: CGFloat
    ) -> CGImage? {
        let pixelSize = max(1, Int(ceil(size * scale)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let fillColor = isDark
            ? CGColor(gray: 0.14, alpha: 1)
            : accentCG
        context.setFillColor(fillColor)
        context.fillEllipse(in: bounds)

        let borderColor = CGColor(gray: 1, alpha: isDark ? 0.28 : 0.85)
        context.setStrokeColor(borderColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: bounds.insetBy(dx: 0.5, dy: 0.5))

        let iconSize: CGFloat = 8
        let checkmark = MingCute.image("checkmark", size: iconSize)
        var proposed = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        if let maskImage = checkmark.cgImage(forProposedRect: &proposed, context: nil, hints: [
            .ctm: AffineTransform(scale: scale)
        ]) {
            let iconRect = CGRect(
                x: (size - iconSize) * 0.5,
                y: (size - iconSize) * 0.5,
                width: iconSize,
                height: iconSize
            )
            context.saveGState()
            context.clip(to: iconRect, mask: maskImage)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(iconRect)
            context.restoreGState()
        }

        return context.makeImage()
    }
}
