import AppKit
import SwiftUI
import LocalStore
import ToolService
import Theme
import AVKit
import UniformTypeIdentifiers

private struct ClipboardColorPreview: View {
    let value: ClipboardColor
    var diameter: CGFloat = 160

    var body: some View {
        VStack(spacing: diameter > 64 ? 16 : 8) {
            Circle().fill(value.color)
                .overlay { Circle().strokeBorder(ThemeColor.kBorderIntense, lineWidth: 1) }
                .frame(width: diameter, height: diameter)
                .accessibilityHidden(true)
            Text(value.text).textStyle(.resultPrimary).monospaced()
                .lineLimit(2).multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private final class ClipboardPanel: NSPanel {
    var dismiss: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var handleKey: (NSEvent) -> Bool = { _ in false }
    var shortcuts: () -> SettingsPreferences = { SettingsPreferences() }
    var onMouseDown: (NSEvent) -> Void = { _ in }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) {
        if let event = NSApp.currentEvent, !shortcuts().shortcut(.clipboardEscape).matches(event) { return }
        dismiss()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { onMouseDown(event) }
        if event.type == .keyDown, handleKey(event) { return }
        if shortcuts().shortcut(.settings).matches(event) { onOpenSettings(); return }
        if shortcuts().shortcut(.clipboardEscape).matches(event),
           (firstResponder as? NSTextView)?.hasMarkedText() != true { dismiss(); return }
        super.sendEvent(event)
    }
}

enum ClipboardHistoryAction {
    case copy, pasteKeepingOpen, delete, clearAll

    var title: String {
        switch self {
        case .copy: "复制到剪贴板"
        case .pasteKeepingOpen: "粘贴并保持窗口开启"
        case .delete: "删除记录"
        case .clearAll: "清空全部"
        }
    }

    var icon: String {
        switch self {
        case .copy: "doc.on.clipboard"
        case .pasteKeepingOpen: "cursor_3"
        case .delete: "trash"
        case .clearAll: "trash"
        }
    }
}

@MainActor @Observable
final class ClipboardController {
    private let app: AppModel
    private let panel: ClipboardPanel
    private let dragSource = ClipboardDragSource()
    private var refreshTimer: Timer?
    private var searchTask: Task<Void, Never>?
    private var searchWorker: Task<(ClipboardAccess.SearchPage?, Int), Never>?
    private var searchGeneration = 0
    private var searchRevision: Int?
    private var lastFullRefresh = Date.distantPast
    private var pageCursor: ClipboardItem?
    private(set) var hasMore = false
    private(set) var isLoading = false
    private static let pageSize = 40
    private let outsideClickDismissal = OutsideClickDismissal()
    private let toastPanel = SurfacePanel()
    private var toastDismissTask: Task<Void, Never>?
    var actionsMenuFrame: CGRect = .zero
    var actionSelection = 0
    var isActionsMenuPresented = false {
        didSet { updateOutsideClickDismissal() }
    }
    private var isConfirmingClearAll = false
    private var hiding = false
    private var pasteTarget: ClipboardPasteTarget?
    private var pasteTask: Task<Void, Never>?
    private var keepingOpenForPaste = false
    private let pasteTargetProvider: @MainActor () -> ClipboardPasteTarget
    private(set) var hasPasteTarget = false
    var actionKinds: [ClipboardHistoryAction] { hasPasteTarget ? [.copy, .pasteKeepingOpen, .delete, .clearAll] : [.copy, .delete, .clearAll] }
    var isDragging: Bool { dragSource.active }

    func updateLayout() {
        isActionsMenuPresented = false
        resizePanel()
        updateToast()
    }

    private func resizePanel() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let available = screen.visibleFrame.insetBy(dx: 16, dy: 16)
        let height = min(560.0, available.height)
        let width = min(WindowMetrics.launcherWidth, available.width)
        let x = min(max(panel.frame.minX, available.minX), available.maxX - width)
        let y = max(available.minY, min(panel.frame.maxY, available.maxY) - height)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel.invalidateShadow()
    }

    func select(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        selection = index
    }

    var selectedItem: ClipboardItem? { items.indices.contains(selection) ? items[selection] : nil }

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            isActionsMenuPresented = false
            selection = 0
            items = []
            pageCursor = nil
            hasMore = false
            searchRevision = nil
            requestPage(append: false, debounce: true)
        }
    }

    func escape() {
        if isActionsMenuPresented { isActionsMenuPresented = false }
        else { hide() }
    }
    var items: [ClipboardItem] = []
    var selection = 0 { didSet { if selection != oldValue { isActionsMenuPresented = false } } }
    var pinned = false { didSet { updateOutsideClickDismissal() } }
    var status: String? {
        didSet {
            toastDismissTask?.cancel()
            toastDismissTask = nil
            if status != oldValue { updateToast() }
            guard status != nil else { return }
            toastDismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.status = nil
            }
        }
    }

    init(app: AppModel, pasteTargetProvider: @escaping @MainActor () -> ClipboardPasteTarget = ClipboardPasteTarget.capture) {
        self.app = app
        self.pasteTargetProvider = pasteTargetProvider
        panel = ClipboardPanel(contentRect: NSRect(x: 0, y: 0, width: WindowMetrics.launcherWidth, height: 560),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        for window in [panel] {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.level = .floating
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        toastPanel.ignoresMouseEvents = true
        panel.level = .normal
        panel.title = NSLocalizedString("剪贴板历史", comment: "")
        panel.dismiss = { [weak self] in
            guard let self else { return }
            self.escape()
        }
        panel.onMouseDown = { [weak self] event in
            guard let self else { return }
            let moreButton = NSRect(x: self.panel.frame.width - 130, y: 0, width: 116, height: LauncherLayout.actionBarHeight)
            if !moreButton.contains(event.locationInWindow),
               !(self.isActionsMenuPresented && self.actionsMenuFrame.contains(event.locationInWindow)) {
                self.isActionsMenuPresented = false
            }

        }
        panel.handleKey = { [weak self] in self?.handleActionKey($0) ?? false }
        panel.onOpenSettings = { [weak app] in app?.openSettings() }
        panel.shortcuts = { [weak app] in app?.preferences ?? SettingsPreferences() }
        // Keyboard application switching must also remove outside-click observation.
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self, !self.pinned, !self.dragSource.active, !self.keepingOpenForPaste, !self.isConfirmingClearAll { self.hide() } }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel.level = .floating }
        }
    }

    /// The panel frame is exactly the glass shell, so the system shadow follows it.
    private var shellFrame: NSRect { panel.frame }

    var isVisible: Bool { panel.isVisible }
    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        pasteTask?.cancel()
        keepingOpenForPaste = false
        pasteTarget = pasteTargetProvider()
        hasPasteTarget = pasteTarget?.canPaste == true
        query = ""
        items = []
        selection = 0
        pageCursor = nil
        hasMore = false
        searchRevision = nil
        status = nil
        refresh()
        // Every opening starts from the default spot; a drag only moves this session.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let width = min(WindowMetrics.launcherWidth, frame.width - 32)
            panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.maxY - frame.height * 0.16 - 560,
                                  width: width, height: 560), display: false)
        }
        updateLayout()
        let host = NSHostingView(rootView: ClipboardHistoryView(controller: self))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: panel.frame.size)
        panel.contentView = WindowSurface.glassContentView(host, cornerRadius: ClipboardHistoryView.cornerRadius)
        WindowSurface.updateCorners(of: panel.contentView!,
            radius: ClipboardHistoryView.cornerRadius, circular: true)
        panel.invalidateShadow()
        panel.level = .floating
        panel.orderFrontRegardless()
        panel.makeKey()
        updateOutsideClickDismissal()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(onlyIfChanged: true) }
        }
    }

    func hide() {
        guard !hiding else { return }
        hiding = true
        if keepingOpenForPaste { pasteTask?.cancel() }
        keepingOpenForPaste = false
        defer { hiding = false }
        isActionsMenuPresented = false
        outsideClickDismissal.hide()
        status = nil
        toastPanel.remove()
        refreshTimer?.invalidate()
        refreshTimer = nil
        searchTask?.cancel()
        searchWorker?.cancel()
        searchGeneration += 1
        isLoading = false
        panel.orderOut(nil)
        panel.contentView = nil
        items = []
    }

    private func updateOutsideClickDismissal() {
        guard !isConfirmingClearAll, panel.isVisible, (!pinned || isActionsMenuPresented), !dragSource.active else { outsideClickDismissal.hide(); return }
        outsideClickDismissal.show(contains: { [weak self] point in
            guard let self else { return false }
            return self.shellFrame.contains(point)
        }, dismiss: { [weak self] in
            guard let self else { return }
            if self.pinned { self.isActionsMenuPresented = false } else { self.hide() }
        })
    }

    /// The status toast is its own opaque surface centered 12 pt above the shell.
    private func updateToast() {
        guard let status else { toastPanel.remove(); return }
        let view = ClipboardStatusToast(message: status)
        let size = SurfacePanel.fittingSize(of: view, maxWidth: shellFrame.width - 48)
        toastPanel.setSurface(view, size: size, cornerRadius: ClipboardStatusToast.cornerRadius, glass: false)
        toastPanel.setFrameOrigin(NSPoint(x: shellFrame.midX - size.width / 2, y: shellFrame.maxY + 12))
        if panel.isVisible {
            if toastPanel.parent == nil { panel.addChildWindow(toastPanel, ordered: .above) }
        } else {
            if let parent = toastPanel.parent { parent.removeChildWindow(toastPanel) }
            toastPanel.orderFrontRegardless()
        }
    }

    func toggleActionsMenu() {
        guard selectedItem != nil else { return }
        actionSelection = 0
        isActionsMenuPresented.toggle()
    }

    func performSelectedAction(_ index: Int) {
        guard let item = selectedItem else { isActionsMenuPresented = false; return }
        isActionsMenuPresented = false
        guard actionKinds.indices.contains(index) else { return }
        switch actionKinds[index] {
        case .copy: copy(item)
        case .pasteKeepingOpen: pasteSelection(keepingOpen: true)
        case .delete: delete(item)
        case .clearAll: Task { await clearAll() }
        }
    }

    func handleActionKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              (panel.firstResponder as? NSTextView)?.hasMarkedText() != true else { return false }
        func matches(_ action: LocalShortcutAction) -> Bool { app.preferences.shortcut(action).matches(event) }
        if matches(.clipboardMore) { toggleActionsMenu(); return true }
        if matches(.clipboardCopy) {
            isActionsMenuPresented = false
            if !event.isARepeat { submitSelection(copyOnly: true) }
            return true
        }
        if matches(.delete) {
            isActionsMenuPresented = false
            if !event.isARepeat, let item = selectedItem { delete(item) }
            return true
        }
        if matches(.clipboardEscape) { escape(); return true }
        if matches(.clipboardUp) || matches(.clipboardDown) {
            let delta = matches(.clipboardUp) ? -1 : 1
            if isActionsMenuPresented { actionSelection = min(max(0, actionSelection + delta), actionKinds.count - 1) }
            else { moveSelection(delta) }
            return true
        }
        if matches(.clipboardLeft) || matches(.clipboardRight) {
            moveSelection(matches(.clipboardLeft) ? -1 : 1); return true
        }
        if matches(.paste) {
            if !event.isARepeat {
                if isActionsMenuPresented { performSelectedAction(actionSelection) }
                else { submitSelection(copyOnly: false) }
            }
            return true
        }
        return false
    }

    var shortcutPreferences: SettingsPreferences { app.preferences }

    func refresh(onlyIfChanged: Bool = false) {
        if onlyIfChanged && isLoading { return }
        requestPage(append: false, onlyIfChanged: onlyIfChanged)
    }

    func loadMore() {
        guard hasMore, !isLoading else { return }
        requestPage(append: true)
    }

    private func requestPage(append: Bool, debounce: Bool = false, onlyIfChanged: Bool = false) {
        searchTask?.cancel()
        searchWorker?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        let store = app.clipboardStore
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cursor = append ? pageCursor : nil
        let limit = append ? Self.pageSize : max(Self.pageSize, items.count)
        // Periodically recheck external files even when the database did not change.
        let previousRevision = onlyIfChanged && Date().timeIntervalSince(lastFullRefresh) < 3 ? searchRevision : nil
        isLoading = true
        searchTask = Task { [weak self] in
            if debounce {
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            }
            guard !Task.isCancelled, let self else { return }
            let worker = Task.detached(priority: .userInitiated) {
                let revision = store.changeRevision
                if revision == previousRevision { return (nil as ClipboardAccess.SearchPage?, revision) }
                return (ClipboardAccess.searchPage(in: store, query: value, limit: limit, before: cursor), revision)
            }
            self.searchWorker = worker
            let (page, revision) = await worker.value
            guard !Task.isCancelled, generation == self.searchGeneration else { return }
            self.isLoading = false
            guard let page else { return }
            // Capture before the next refresh; a write during the scan must trigger another read.
            if !append { self.searchRevision = revision; self.lastFullRefresh = Date() }
            let selectedID = self.selectedItem?.id
            let next = append ? self.items + page.items : page.items
            if next != self.items {
                self.isActionsMenuPresented = false
                self.items = next
                self.selection = next.firstIndex { $0.id == selectedID } ?? min(self.selection, max(0, next.count - 1))
            }
            self.pageCursor = page.cursor
            self.hasMore = page.hasMore
        }
    }

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        selection = min(max(0, selection + delta), items.count - 1)
        if delta > 0, selection >= items.count - 3 { loadMore() }
    }

    func copySelection() {
        guard items.indices.contains(selection) else { return }
        copy(items[selection])
    }

    func submitSelection(copyOnly: Bool) {
        if copyOnly { copySelection() } else if hasPasteTarget { pasteSelection() }
    }

    /// Release keyboard focus for the original app before dispatching its paste shortcut.
    func pasteSelection(keepingOpen: Bool = false) {
        guard items.indices.contains(selection) else { return }
        guard ClipboardAccess.copy(items[selection]) else {
            refresh()
            status = NSLocalizedString("无法复制：原始内容已不可用", comment: "")
            return
        }
        guard let pasteTarget else { showPasteFallback(.unavailable); return }
        let ready = pasteTarget.prepare()
        guard ready == .posted else { showPasteFallback(ready); return }
        let changeCount = ClipboardAccess.changeCount
        pasteTask?.cancel()
        if keepingOpen {
            keepingOpenForPaste = true
            outsideClickDismissal.hide()
            // A nonactivating panel must release its stolen keyboard focus for Cmd V.
            // Retain its content, frame, query and selection while the target receives it.
            panel.orderOut(nil)
        } else {
            hide()
        }
        pasteTask = Task { @MainActor [weak self] in
            let result = await pasteTarget.paste(expectedChangeCount: changeCount)
            // Allow WindowServer to deliver the shortcut before showing the panel again.
            if keepingOpen { try? await Task.sleep(for: .milliseconds(150)) }
            guard !Task.isCancelled, let self else { return }
            if keepingOpen {
                self.panel.orderFrontRegardless()
                self.keepingOpenForPaste = false
                self.updateOutsideClickDismissal()
            }
            self.showPasteFallback(result)
        }
    }

    private func showPasteFallback(_ result: ClipboardPasteTarget.Result) {
        switch result {
        case .posted: break
        case .noInputFocus:
            status = NSLocalizedString("已复制；未找到输入位置，请手动粘贴", comment: "")
        case .accessibilityRequired:
            status = NSLocalizedString("已复制；自动粘贴需要辅助功能权限", comment: "")
        case .unavailable:
            status = NSLocalizedString("未能自动粘贴，请使用剪贴板手动粘贴", comment: "")
        }
    }

    func togglePinned() {
        pinned.toggle()
        panel.level = pinned ? .floating : .normal
    }

    func copy(_ item: ClipboardItem) {
        let copied = ClipboardAccess.copy(item)
        if !copied { refresh() }
        status = copied ? NSLocalizedString("已复制", comment: "") : NSLocalizedString("无法复制：原始内容已不可用", comment: "")
    }

    /// AppKit drag with eagerly written pasteboard data; SwiftUI `.onDrag` promises are ignored by Chromium/Electron targets.
    func beginDrag(_ item: ClipboardItem, from view: NSView, event: NSEvent) {
        guard !dragSource.active, event.type == .leftMouseDragged else { return }
        guard let pasteboardItems = ClipboardAccess.dragItems(for: item) else {
            status = NSLocalizedString("无法拖拽：原始内容已不可用", comment: "")
            return
        }
        #if DEBUG
        if CommandLine.arguments.contains("--test-clipboard") {
            NSLog("Clipboard drag started: %@, %ld items", item.kind.rawValue, pasteboardItems.count)
        }
        #endif
        let preview = ClipboardDragSource.snapshot(of: view)
        let dragging = pasteboardItems.enumerated().map { index, writer in
            let entry = NSDraggingItem(pasteboardWriter: writer)
            entry.setDraggingFrame(view.bounds.offsetBy(dx: CGFloat(index) * 4, dy: CGFloat(index) * 4), contents: preview)
            return entry
        }
        dragSource.beginTracking(verifyNativeTextDrop: item.kind == .text)
        // Pause dismissal while dragging to another application.
        outsideClickDismissal.hide()
        dragSource.onEnd = { [weak self] operation, point, wasReleased in
            #if DEBUG
            if CommandLine.arguments.contains("--test-clipboard") {
                NSLog("Clipboard drag ended: operation %lu", operation.rawValue)
            }
            #endif
            guard let self else { return }
            let nativeSnapshot = self.dragSource.nativeTextDropTarget
            let verifyNative = operation == .copy && nativeSnapshot != nil
            guard wasReleased, operation == [] || verifyNative else {
                if operation != [], !self.pinned { self.hide() }
                else { self.updateOutsideClickDismissal() }
                return
            }
            self.pasteTask?.cancel()
            self.pasteTask = Task { @MainActor [weak self] in
                // AppKit is still inside its drag tracking loop during the delegate callback.
                // Wait for it to remove the drag image and finish restoring destination focus.
                try? await Task.sleep(for: .milliseconds(verifyNative ? 300 : 80))
                guard !Task.isCancelled, let self else { return }
                let dropTarget = ClipboardDropTarget.capture(at: point)
                if verifyNative, !(dropTarget.map { $0.hasUnchangedText(since: nativeSnapshot!) } ?? false) {
                    if !self.pinned { self.hide() }
                    else { self.updateOutsideClickDismissal() }
                    return
                }
                if CommandLine.arguments.contains("--drag-paste-target") || CommandLine.arguments.contains("--test-clipboard") {
                    NSLog("Drag completion: operation=%lu released=%d editableTarget=%d", operation.rawValue, wasReleased, dropTarget != nil)
                }
                guard let target = dropTarget else { self.updateOutsideClickDismissal(); return }
                guard ClipboardAccess.copy(item) else {
                    self.status = NSLocalizedString("无法拖拽：原始内容已不可用", comment: "")
                    self.updateOutsideClickDismissal()
                    return
                }
                let changeCount = ClipboardAccess.changeCount
                let restorePinnedPanel = self.pinned
                // A nonactivating panel can hold keyboard focus while the destination app
                // is already frontmost. Release it before Cmd V, even when the panel is pinned.
                if restorePinnedPanel { self.panel.orderOut(nil) }
                else { self.hide() }
                let result = await target.paste(expectedChangeCount: changeCount)
                // Posting is asynchronous: restoring the panel immediately can blur a web
                // editor before WindowServer delivers Cmd V.
                if restorePinnedPanel { try? await Task.sleep(for: .milliseconds(150)) }
                if restorePinnedPanel, !Task.isCancelled {
                    self.panel.orderFrontRegardless()
                    self.updateOutsideClickDismissal()
                }
                if CommandLine.arguments.contains("--drag-paste-target") || CommandLine.arguments.contains("--test-clipboard") {
                    NSLog("Drop paste result: %@", String(describing: result))
                }
                guard !Task.isCancelled else { return }
                self.showPasteFallback(result)
            }
        }
        view.beginDraggingSession(with: dragging, event: event, source: dragSource)
            .animatesToStartingPositionsOnCancelOrFail = true
    }

    static func makeClearAllAlert() -> NSAlert {
        let alert = AppDialog.make()
        alert.messageText = NSLocalizedString("清空全部剪贴板历史？", tableName: "Clipboard", comment: "")
        alert.informativeText = NSLocalizedString("所有剪贴板历史（包括固定的记录）都将被删除，且无法恢复。原始文件不会被删除。", tableName: "Clipboard", comment: "")
        let confirm = alert.addButton(withTitle: NSLocalizedString("清空全部", tableName: "Clipboard", comment: ""))
        confirm.hasDestructiveAction = true
        confirm.keyEquivalent = "\r"
        alert.addButton(withTitle: NSLocalizedString("取消", comment: "")).keyEquivalent = "\u{1b}"
        return alert
    }

    func clearAll() async {
        guard !isConfirmingClearAll else { return }
        isConfirmingClearAll = true
        isActionsMenuPresented = false
        updateOutsideClickDismissal()
        defer {
            isConfirmingClearAll = false
            updateOutsideClickDismissal()
        }
        guard await AppDialog.present(Self.makeClearAllAlert(), for: panel) == .alertFirstButtonReturn else { return }
        do {
            let paths = try app.clipboardStore.clearAll()
            ClipboardMonitor.removeFiles(paths)
            items = []
            selection = 0
            pageCursor = nil
            hasMore = false
            refresh()
        } catch {
            status = NSLocalizedString("无法清空剪贴板历史", tableName: "Clipboard", comment: "")
        }
    }

    func delete(_ item: ClipboardItem) {
        do {
            let paths = try app.clipboardStore.delete(ids: [item.id])
            ClipboardMonitor.removeFiles(paths)
            let selectedID = selectedItem?.id
            items.removeAll { $0.id == item.id }
            selection = items.firstIndex { $0.id == selectedID } ?? min(selection, max(0, items.count - 1))
            isActionsMenuPresented = false
            refresh()
        } catch { status = NSLocalizedString("无法删除这条记录", comment: "") }
    }
}

private struct ClipboardHistoryView: View {
    static let cornerRadius = LauncherLayout.shellCornerRadius
    @Bindable var controller: ClipboardController
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: LauncherLayout.inputSpacing) {
                LauncherSearchField(text: $controller.query, fontSize: 16,
                                    textColor: NSColor(ThemeColor.kText.color(for: scheme)),
                                    accessibilityLabel: NSLocalizedString("搜索剪贴板历史", comment: ""),
                                    placeholder: NSLocalizedString("搜索剪贴板内容", comment: ""),
                                    placeholderColor: NSColor(ThemeColor.kTextSubtlest.color(for: scheme)),
                                    backspaceOnEmpty: { false }, move: controller.moveSelection,
                                    moveHorizontal: controller.moveSelection,
                                    submit: { controller.submitSelection(copyOnly: $0) },
                                    shortcuts: controller.shortcutPreferences, shortcutScope: "clipboard")
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                HStack(spacing: LauncherLayout.inputSpacing) {
                    ClipboardHeaderButton(symbol: controller.pinned ? "pin.fill" : "pin",
                                          title: controller.pinned ? NSLocalizedString("取消固定窗口", comment: "") : NSLocalizedString("固定窗口", comment: ""),
                                          action: controller.togglePinned)
                        .accessibilityValue(controller.pinned ? NSLocalizedString("已固定", comment: "") : NSLocalizedString("未固定", comment: ""))
                }
            }
            .padding(.leading, LauncherLayout.inputLeadingPadding)
            .padding(.trailing, LauncherLayout.inputTrailingPadding)
            .frame(height: LauncherLayout.inputHeight)
            // The header gaps drag the panel, like the agent window's title bar.
            .contentShape(Rectangle())
            .compatibleWindowDrag()
            Rectangle().fill(ThemeColor.kBorder)
                .frame(height: LauncherLayout.dividerHeight)
                .padding(.horizontal, 28)
            if controller.items.isEmpty {
                VStack(spacing: 8) {
                    Text(controller.query.isEmpty ? NSLocalizedString("暂无剪贴板历史", comment: "") : NSLocalizedString("没有匹配的内容", comment: ""))
                    Text(NSLocalizedString("复制文字或图片后会显示在这里", comment: "")).textStyle(.secondary).foregroundStyle(ThemeColor.kTextSubtlest)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ClipboardListView(controller: controller)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(ThemeColor.kText)
        .windowSurfaceBackground(in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .circular))
        .overlayPreferenceValue(LauncherMoreAnchorKey.self) { anchor in
            GeometryReader { geometry in
                if let anchor {
                    let rect = geometry[anchor]
                    let availableHeight = max(32, rect.maxY - LauncherLayout.inputHeight - 12)
                    let height = min(availableHeight, LauncherMorphingActions.menuHeight(actionCount: controller.actionKinds.count))
                    let hitRect = CGRect(x: rect.maxX - LauncherLayout.actionsMenuWidth,
                                         y: geometry.size.height - rect.maxY,
                                         width: LauncherLayout.actionsMenuWidth, height: height)
                    let width = controller.isActionsMenuPresented ? LauncherLayout.actionsMenuWidth : rect.width
                    let surfaceHeight = controller.isActionsMenuPresented ? height : rect.height
                    ClipboardMorphingActions(controller: controller, availableHeight: availableHeight)
                        .frame(width: width, height: surfaceHeight, alignment: .bottomTrailing)
                        .position(x: rect.maxX - width / 2, y: rect.maxY - surfaceHeight / 2)
                        .onChange(of: hitRect, initial: true) { _, frame in controller.actionsMenuFrame = frame }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .circular))
        .onExitCommand {
            controller.escape()
        }
    }

}

private struct ClipboardActionBar: View {
    let controller: ClipboardController

    var body: some View {
        HStack {
            Button { controller.hasPasteTarget ? controller.pasteSelection() : controller.copySelection() } label: {
                if controller.hasPasteTarget {
                    label("粘贴到光标位置", shortcut: controller.shortcutPreferences.shortcut(.paste).label)
                } else {
                    label("复制到剪贴板", shortcut: controller.shortcutPreferences.shortcut(.clipboardCopy).label)
                }
            }
            .buttonStyle(LauncherActionButtonStyle())
            Spacer(minLength: 12)
            label("更多", shortcut: controller.shortcutPreferences.shortcut(.clipboardMore).label)
                .hidden()
                .accessibilityHidden(true)
                .anchorPreference(key: LauncherMoreAnchorKey.self, value: .bounds) { $0 }
        }
        .disabled(controller.selectedItem == nil)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(height: LauncherLayout.actionBarHeight, alignment: .bottom)
    }

    private func label(_ title: String, shortcut: String) -> some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString(title, tableName: "Clipboard", comment: "Clipboard action"))
            LauncherActionKeyCap(value: shortcut)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .frame(height: 32)
        .contentShape(Capsule())
    }
}

private struct ClipboardMorphingActions: View {
    @Bindable var controller: ClipboardController
    let availableHeight: CGFloat
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial {
                GlassEffectContainer {
                    ZStack(alignment: .bottomTrailing) {
                        if controller.isActionsMenuPresented {
                            menu
                                .nativeGlassBackground(in: RoundedRectangle(cornerRadius: 18))
                                .glassEffectID("more", in: glassNamespace)
                                .glassEffectTransition(.matchedGeometry)
                        } else {
                            button
                                .glassEffectID("more", in: glassNamespace)
                                .glassEffectTransition(.matchedGeometry)
                        }
                    }
                }
            } else {
                ZStack(alignment: .bottomTrailing) {
                    if controller.isActionsMenuPresented {
                        menu.nativeGlassBackground(in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        button
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: controller.isActionsMenuPresented)
    }

    private var button: some View {
        Button { controller.toggleActionsMenu() } label: {
            LauncherActionLabel(title: "更多", shortcut: controller.shortcutPreferences.shortcut(.clipboardMore).label)
        }
        .buttonStyle(LauncherActionButtonStyle())
        .fixedSize()
        .focusable(false)
        .accessibilityIdentifier("clipboard-more-button")
        .accessibilityValue("Off")
    }

    private var menu: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ClipboardActionsMenu(controller: controller)
            }
            .scrollIndicators(.hidden)
            .focusable(false)
            .onChange(of: controller.actionSelection) { _, selection in
                proxy.scrollTo(selection, anchor: .center)
            }
        }
        .frame(width: LauncherLayout.actionsMenuWidth,
               height: min(availableHeight, LauncherMorphingActions.menuHeight(actionCount: controller.actionKinds.count)))
    }
}

private struct ClipboardActionsMenu: View {
    @Bindable var controller: ClipboardController
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 4) {
            ForEach(controller.actionKinds.indices, id: \.self) { index in
                Button { controller.performSelectedAction(index) } label: {
                    HStack(spacing: 10) {
                        let kind = controller.actionKinds[index]
                        Text(NSLocalizedString(kind.title, tableName: "Clipboard", comment: "Clipboard action"))
                            .foregroundStyle(kind == .delete || kind == .clearAll ? ThemeColor.kTextNegative : ThemeColor.kText)
                        Spacer(minLength: 8)
                        if kind == .copy {
                            LauncherActionKeyCap(value: controller.shortcutPreferences.shortcut(.clipboardCopy).label)
                        } else if kind == .delete {
                            LauncherActionKeyCap(value: controller.shortcutPreferences.shortcut(.delete).label)
                        }
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(controller.actionSelection == index ? ThemeColor.kInteractionHover.color(for: scheme) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10))
                .focusable(false)
                .onHover { if $0 { controller.actionSelection = index } }
                .id(index)
                .accessibilityIdentifier("clipboard-action-\(index)")
                .accessibilityAddTraits(controller.actionSelection == index ? .isSelected : [])
            }
        }
        .padding(8)
        .frame(width: LauncherLayout.actionsMenuWidth)
        .foregroundStyle(ThemeColor.kText)
        .accessibilityIdentifier("clipboard-actions-menu")
    }
}

private struct ClipboardHeaderButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    var selected = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(mingCute: symbol, size: LauncherLayout.searchIconSize)
                .frame(width: 32, height: 32)
                .contentShape(.interaction, Circle())
        }
        .buttonStyle(ClipboardHeaderButtonStyle())
        .frame(width: LauncherLayout.inputAccessoryWidth, height: LauncherLayout.inputAccessoryHeight)
        .foregroundStyle(selected ? ThemeColor.kText.color(for: scheme) : ThemeColor.kIconSubtle.color(for: scheme))
        .accessibilityLabel(title).help(title)
    }
}

private struct ClipboardHeaderButtonStyle: ButtonStyle {
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                Circle()
                    .fill(ThemeColor.kInteractionHover.color(for: colorScheme))
                    .opacity(isEnabled ? (configuration.isPressed ? 1 : isHovered ? 0.6 : 0) : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .contentShape(.interaction, Circle())
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

private struct ClipboardListView: View {
    let controller: ClipboardController

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: LauncherLayout.rowSpacing) {
                        ForEach(controller.items) { item in
                            ClipboardHistoryRow(item: item, controller: controller).id(item.id)
                                .onAppear {
                                    if item.id == controller.items.last?.id { controller.loadMore() }
                                }
                        }
                    }.padding(.horizontal, LauncherLayout.listHorizontalPadding)
                        .padding(.top, LauncherLayout.listBottomPadding)
                        .padding(.bottom, LauncherLayout.listBottomPadding + LauncherLayout.actionBarHeight)
                }
                .scrollIndicators(.hidden)
                .onChange(of: controller.selection) { _, _ in
                    if let item = controller.selectedItem { proxy.scrollTo(item.id, anchor: .center) }
                }
                .onAppear {
                    if let item = controller.selectedItem { proxy.scrollTo(item.id, anchor: .center) }
                }
            }
            .frame(width: 272)
            Rectangle().fill(ThemeColor.kBorder).frame(width: 1)
                .padding(.top, 12)
                .padding(.bottom, LauncherLayout.actionBarHeight + 12)
            if let item = controller.selectedItem {
                ClipboardListDetail(item: item).id(item.id)
                    .padding(.bottom, LauncherLayout.actionBarHeight)
            }
        }
        // Match search: content continues beneath floating actions and fades away.
        .mask {
            GeometryReader { geometry in
                let fade = LauncherLayout.actionBarHeight / max(1, geometry.size.height)
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: max(0, 1 - fade - 0.06)),
                    .init(color: .clear, location: max(0, 1 - fade * 0.35)),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .overlay(alignment: .bottom) {
            ClipboardActionBar(controller: controller)
        }
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardItem
    let controller: ClipboardController
    @State private var hovering = false
    private var selected: Bool { controller.selectedItem?.id == item.id }
    private var title: String {
        if item.kind == .image { return item.imageTitle }
        return item.text ?? item.filePaths.map { URL(filePath: $0).lastPathComponent }.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if item.kind == .image, let path = item.thumbPath ?? item.filePath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else if let value = ClipboardColor(item: item) {
                    Circle().fill(value.color)
                        .overlay { Circle().strokeBorder(ThemeColor.kBorderIntense, lineWidth: 1) }
                        .padding(2)
                } else if item.kind == .text {
                    Image(mingCute: "doc.on.clipboard", size: 18)
                        .foregroundStyle(ThemeColor.kIconSubtle)
                        .frame(width: LauncherLayout.rowIconSize, height: LauncherLayout.rowIconSize)
                        .background(ThemeColor.kBackgroundNeutral, in: RoundedRectangle(cornerRadius: 6))
                } else if let icon = ClipboardAccess.fileIcon(for: item) {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(mingCute: item.kind == .file ? "doc" : "text.document", size: 18)
                        .foregroundStyle(ThemeColor.kIconSubtle)
                }
            }
            .frame(width: LauncherLayout.rowIconSize, height: LauncherLayout.rowIconSize).clipShape(RoundedRectangle(cornerRadius: 6))
            Text(title.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 14)).foregroundStyle(ThemeColor.kText).lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, LauncherLayout.rowHorizontalPadding)
        .frame(height: LauncherLayout.rowHeight)
        .background(hovering ? AnyShapeStyle(ThemeColor.kInteractionHover) :
                        selected ? AnyShapeStyle(ThemeColor.kBackgroundSelected) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: LauncherLayout.rowCornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: LauncherLayout.rowCornerRadius))
        .overlay(ClipboardCardMouseSurface(
            copy: { controller.copy(item) },
            select: { controller.select(item) }, requiresDoubleClick: true,
            hover: { _, inside in hovering = inside },
            drag: { view, event in controller.select(item); controller.beginDrag(item, from: view, event: event) }
        ).clipShape(RoundedRectangle(cornerRadius: LauncherLayout.rowCornerRadius)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : [.isButton])
        .accessibilityAction { controller.select(item) }
        .accessibilityAction(named: NSLocalizedString("复制", comment: "")) { controller.copy(item) }
    }
}

private struct ClipboardListDetail: View {
    let item: ClipboardItem
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if item.kind == .image, let path = item.filePath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 24)
                } else if let url = ClipboardAccess.videoPreviewURL(for: item) {
                    ClipboardVideoPreview(url: url).id(url)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 24)
                } else if let value = ClipboardColor(item: item) {
                    ClipboardColorPreview(value: value).padding(.horizontal, 24)
                } else if item.kind == .file, let icon = ClipboardAccess.fileIcon(for: item) {
                    VStack(spacing: 16) {
                        Image(nsImage: icon).resizable().scaledToFit()
                            .frame(width: 160, height: 160)
                        Text(item.filePaths.map { URL(filePath: $0).lastPathComponent }.joined(separator: "\n"))
                            .textStyle(.resultPrimary).textSelection(.enabled)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                } else {
                    ScrollView {
                        Text(item.text ?? (item.kind == .image ? NSLocalizedString("原始图片已不可用", comment: "") : item.filePaths.joined(separator: "\n")))
                            .textStyle(.resultPrimary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.horizontal, 24)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(ThemeColor.kBorder).frame(height: 1).padding(.horizontal, 24)
            ClipboardInformation(item: item).padding(.horizontal, 24)
        }
        // Inset the content, not the scroll viewport, so the native scroller stays at the pane edge.
        .padding(.vertical, 24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ClipboardInformation: View {
    let item: ClipboardItem
    private func label(_ key: String) -> String { NSLocalizedString(key, tableName: "Clipboard", comment: "") }

    var body: some View {
        let info = ClipboardAccess.information(for: item)
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow {
                    Text(label("来源"))
                    HStack(spacing: 6) {
                        if let icon = ClipboardAccess.sourceIcon(bundleID: item.sourceBundleID, name: item.sourceApp) {
                            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                        }
                        Text(item.sourceApp ?? NSLocalizedString("未知来源", comment: ""))
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .gridColumnAlignment(.trailing)
                }
                GridRow {
                    Text(label("类型"))
                    Text(info.typeName ?? label(item.kind == .image ? "图片" : item.kind == .file ? "文件" : "文本"))
                }
                GridRow {
                    Text(label("尺寸"))
                    Text(info.pixelDimensions ?? "—")
                }
                GridRow {
                    Text(label("大小"))
                    Text(info.byteSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "—")
                }
                GridRow {
                    Text(label("复制时间"))
                    Text(item.createdAt, format: .dateTime.year().month().day().hour().minute())
                }
            }
            .multilineTextAlignment(.trailing)
            .font(.system(size: 14))
            .foregroundStyle(ThemeColor.kTextSubtlest)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// AVKit leaves extra space below its movable floating controls by default.
/// Locate the native glass surface using public AppKit types, and align its
/// bottom gap with its horizontal gap without replacing the playback controls.
private final class ClipboardPlayerView: AVPlayerView {
    private var controlsBottom: NSLayoutConstraint?
    private var controlsLayoutObserver: CFRunLoopObserver?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let controlsLayoutObserver { CFRunLoopObserverInvalidate(controlsLayoutObserver) }
        controlsLayoutObserver = nil
        guard window != nil else { return }
        // AVKit creates its pane asynchronously. Resolve its position at the
        // end of the event cycle, before the window server receives the frame.
        let observer = CFRunLoopObserverCreateWithHandler(nil,
            CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.alignFloatingControls() }
            }
        controlsLayoutObserver = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    override func layout() {
        super.layout()
        // AVKit lays out the floating pane below this view in its hierarchy.
        // Resolve that layout before locating and positioning its glass surface.
        subviews.forEach { $0.layoutSubtreeIfNeeded() }
        alignFloatingControls()
    }

    private func alignFloatingControls() {
        guard controlsStyle == .floating,
              let glass = glassSurface(in: self) else { return }
        var controls: NSView = glass
        while let parent = controls.superview, parent !== self,
              abs(parent.bounds.height - controls.frame.height) < 0.5 {
            controls = parent
        }
        guard let container = controls.superview, container !== self,
              controls.bounds.height > 0, controls.bounds.height < container.bounds.height else { return }
        let frame = convert(controls.bounds, from: controls)
        let inset = max(8, (bounds.width - frame.width) / 2)
        if controlsBottom?.firstItem as? NSView !== controls {
            controlsBottom?.isActive = false
            let constraint = controls.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset)
            // Override AVKit's low-priority movable position, preserving its
            // required minimum margins and compact-height fallback.
            constraint.priority = .defaultHigh
            constraint.isActive = true
            controlsBottom = constraint
        } else if abs((controlsBottom?.constant ?? 0) + inset) > 0.5 {
            controlsBottom?.constant = -inset
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            container.layoutSubtreeIfNeeded()
        }
    }

    private func glassSurface(in view: NSView) -> NSView? {
        if #available(macOS 26.0, *), view is NSGlassEffectView,
           view.bounds.width > 100, view.bounds.height >= 40 { return view }
        return view.subviews.lazy.compactMap { self.glassSurface(in: $0) }.first
    }
}

/// Keep playback local to the visible preview and release its asset when removed.
private struct ClipboardVideoPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = ClipboardPlayerView()
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.player = AVPlayer(url: url)
        return view
    }

    // The native player's intrinsic height changes when floating controls appear.
    // Always accept the preview's proposed size so controls cannot shrink the video.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AVPlayerView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite else { return nil }
        return CGSize(width: width, height: height)
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player?.replaceCurrentItem(with: nil)
        view.player = nil
    }
}

@MainActor
final class ClipboardDragSource: NSObject, NSDraggingSource {
    var active = false
    var onEnd: (NSDragOperation, NSPoint, Bool) -> Void = { _, _, _ in }
    private var gesture: ClipboardDragGesture?
    private(set) var nativeTextDropTarget: ClipboardDropTarget?
    private var verifyNativeTextDrop = false

    func beginTracking(verifyNativeTextDrop: Bool) {
        active = true
        nativeTextDropTarget = nil
        self.verifyNativeTextDrop = verifyNativeTextDrop
        gesture = ClipboardDragGesture()
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        guard verifyNativeTextDrop, nativeTextDropTarget == nil else { return }
        // A collapsed chat editor can be crossed in less than one throttle interval.
        if let target = ClipboardDropTarget.captureNativeTextDrop(at: screenPoint), target.canVerifyNativeTextDrop {
            nativeTextDropTarget = target
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        active = false
        let release = gesture?.finish()
        gesture = nil
        let wasReleased = release != nil
        let point = release ?? screenPoint
        if (CommandLine.arguments.contains("--drag-paste-target") || CommandLine.arguments.contains("--test-clipboard")) {
            NSLog("Drag end event: %lu", NSApp.currentEvent?.type.rawValue ?? 0)
        }
        onEnd(operation, point, wasReleased)
    }

    /// The mouse surface draws no content, so capture the card's area from the window instead.
    static func snapshot(of view: NSView) -> NSImage {
        let image = NSImage(size: view.bounds.size)
        guard let content = view.window?.contentView else { return image }
        let rect = view.convert(view.bounds, to: content)
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: rect) else { return image }
        content.cacheDisplay(in: rect, to: bitmap)
        image.addRepresentation(bitmap)
        return image
    }
}

/// Start the AppKit session inside mouseDragged, using the event delivered to the card itself.
/// SwiftUI gesture updates can run after NSApp.currentEvent has changed or been cleared.
private struct ClipboardCardMouseSurface: NSViewRepresentable {
    let copy: () -> Void
    var select: () -> Void = {}
    var requiresDoubleClick = false
    let hover: (NSView, Bool) -> Void
    let drag: (NSView, NSEvent) -> Void

    func makeNSView(context: Context) -> ClipboardCardMouseView { ClipboardCardMouseView() }
    func updateNSView(_ view: ClipboardCardMouseView, context: Context) {
        view.select = select
        view.requiresDoubleClick = requiresDoubleClick
        view.copy = copy
        view.hover = hover
        view.drag = drag
    }
}

final class ClipboardCardMouseView: NSView {
    var select: () -> Void = {}
    var requiresDoubleClick = false
    var copy: () -> Void = {}
    var hover: (NSView, Bool) -> Void = { _, _ in }
    private var hoverTracking: NSTrackingArea?
    var drag: (NSView, NSEvent) -> Void = { _, _ in }
    private var press: NSPoint?
    private var dragged = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    // The drag overlay receives pointer hits, so it must own hover tracking too.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // inVisibleRect follows scrolling/resizing without rebuilding the area.
        guard hoverTracking == nil else { return }
        let tracking = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) { hover(self, true) }
    override func mouseExited(with event: NSEvent) { hover(self, false) }

    override func mouseDown(with event: NSEvent) {
        press = event.locationInWindow
        dragged = false
        select()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragged, let press,
              hypot(event.locationInWindow.x - press.x, event.locationInWindow.y - press.y) >= 3 else { return }
        dragged = true
        drag(self, event)
    }

    override func mouseUp(with event: NSEvent) {
        if press != nil, !dragged, !requiresDoubleClick || event.clickCount == 2 { copy() }
        press = nil
        dragged = false
    }
}
