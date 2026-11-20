import AppKit
import QuartzCore
import SwiftUI
import Contracts
import DirectActions
import Theme
import Router
import ToolService

enum LauncherLayout {
    // Keep empty and populated fields aligned to the populated search layout.
    static let topInsetFraction: CGFloat = 0.18
    static let bottomClearance: CGFloat = 24
    static let inputHeight: CGFloat = 52
    static let toolbarWidth = WindowMetrics.launcherWidth
    static let inputLeadingPadding: CGFloat = 28
    static let inputTrailingPadding: CGFloat = 22
    static let inputSpacing: CGFloat = 12
    static let folderScopeMaxWidth: CGFloat = 180
    static let folderScopeHeight: CGFloat = 24
    static let inputAccessoryWidth: CGFloat = 19
    static let inputAccessoryHeight: CGFloat = 24
    static let searchIconSize: CGFloat = 17
    static let shellCornerRadius = inputHeight / 2
    static let dividerHeight: CGFloat = 1
    // Compact, single-line results based on the supplied Tinycast reference.
    static let currencyCardHeight: CGFloat = 146
    static let rowHeight: CGFloat = 38
    static let rowIconSize: CGFloat = 24
    static let maxVisibleResults = 10
    static let expandedHeight = inputHeight + dividerHeight + CGFloat(maxVisibleResults) * rowHeight
    static let sectionHeaderHeight: CGFloat = 30
    static let rowSpacing: CGFloat = 0
    static let listHorizontalPadding: CGFloat = 13
    static let actionBarHeight: CGFloat = 56
    static let actionsMenuWidth: CGFloat = 280
    static let listBottomPadding: CGFloat = 12
    static let rowHorizontalPadding: CGFloat = 16
    static let rowCornerRadius = CGFloat(Radius.values["radius16"] ?? 16)
}

/// Floating, non-activating launcher panel that still takes key focus for the input field.
final class LauncherPanel: NSPanel {
    var onEscape: () -> Void = {}
    var onBlur: () -> Void = {}
    var onKeyChange: (Bool) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}
    var onActionKey: (NSEvent) -> Bool = { _ in false }
    var actionMenuContainsPoint: (NSPoint) -> Bool = { _ in false }
    var onCopyPath: () -> Bool = { false }
    var onRevealInFinder: () -> Bool = { false }
    var actionPreferences: () -> SettingsPreferences = { SettingsPreferences() }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: LauncherLayout.toolbarWidth,
                                      height: LauncherLayout.inputHeight),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        // The shell is presented fully laid out; AppKit's default window
        // transition must not expose an intermediate borderless backing store.
        animationBehavior = .none
        // The frame is exactly the glass shell, so the system shadow follows it.
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
    }

    override func sendEvent(_ event: NSEvent) {
        if onActionKey(event) { return }
        if actionPreferences().shortcut(.settings).matches(event) { onOpenSettings(); return }
        if actionPreferences().shortcut(.launcherEscape).matches(event),
           (firstResponder as? NSTextView)?.hasMarkedText() != true { onEscape(); return }
        // Intercept before SwiftUI/field editor routing so ⌥⌘C never degrades to ⌘C.
        if actionPreferences().copyPathHotKey.matches(event),
           (firstResponder as? NSTextView)?.hasMarkedText() != true,
           onCopyPath() { return }
        if actionPreferences().revealInFinderHotKey.matches(event),
           (firstResponder as? NSTextView)?.hasMarkedText() != true,
           onRevealInFinder() { return }
        if event.type == .scrollWheel, !actionMenuContainsPoint(event.locationInWindow),
           routeScrollWheel(event, at: event.locationInWindow) { return }
        super.sendEvent(event)
    }

    /// Route before the field editor or a SwiftUI row can consume the gesture.
    /// Forward the original event to retain precise deltas, phases and momentum.
    @discardableResult
    func routeScrollWheel(_ event: NSEvent, at point: NSPoint) -> Bool {
        guard event.type == .scrollWheel, let contentView,
              let scroll = Self.scrollView(in: contentView) else { return false }
        var interactionRect = scroll.convert(scroll.bounds, to: nil)
        // The input and divider share the result list's scroll interaction.
        interactionRect.size.height += LauncherLayout.inputHeight + LauncherLayout.dividerHeight
        guard interactionRect.contains(point) else { return false }
        scroll.scrollWheel(with: event)
        return true
    }

    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) {
        if let event = NSApp.currentEvent, !actionPreferences().shortcut(.launcherEscape).matches(event) { return }
        onEscape()
    }
    override func becomeKey() {
        super.becomeKey()
        LauncherPresentationTrace.record("became-key", panel: self)
        onKeyChange(true)
    }
    override func resignKey() {
        super.resignKey()
        onKeyChange(false)
        onBlur()
    }
}

/// Transient surfaces outside the single launcher shell.
struct LauncherChrome: Equatable {
    var toast: String?
}

/// Only the shell/header survive hiding. A new session mounts fresh result content.
@MainActor @Observable
final class LauncherPresentationState {
    var isPresented = false
    var sessionID = UUID()
    var maxShellHeight = LauncherLayout.expandedHeight
    var hasExpanded = false
    var statusHeight: CGFloat = 0
}

@MainActor
final class LauncherController {
    private let panel = LauncherPanel()
    private let toastPanel = SurfacePanel()
    private let resultReveal = SurfaceSpring()
    private let outsideClickDismissal = OutsideClickDismissal()
    private let model: LauncherModel
    private var hosting: NSHostingView<AnyView>?
    private let presentation = LauncherPresentationState()
    private weak var searchField: NSTextField?
    private var resizeTask: Task<Void, Never>?
    private var hiding = false
    private var chrome = LauncherChrome()
    private var availableShellHeight = LauncherLayout.expandedHeight
    private var shellHeight = LauncherLayout.inputHeight
    private var targetShellHeight = LauncherLayout.inputHeight
    /// The full-width toolbar's top-left corner; every surface is placed from it.
    private var origin = NSPoint.zero

    init(model: LauncherModel) {
        self.model = model
        panel.onEscape = { [weak self] in
            guard let self else { return }
            if self.model.isActionsMenuPresented { self.model.closeActionsMenu() }
            else if self.model.hasScope { self.model.leaveCommand() }
            else { self.hide() }
        }
        panel.onBlur = { [weak self] in
            guard let self else { return }
            guard !ContentPreviewWindow.quick.isShowing(from: self.panel) else { return }
            guard !LauncherPresentationTrace.isEnabled else { return }
            self.model.closeActionsMenu()
            guard !self.model.isConfirmingQuit, !self.model.isConfirmingPluginCommand else { return }
            self.hide()
        }
        panel.onActionKey = { [weak self] event in
            guard let self else { return false }
            return self.handlePreviewKey(event) || self.model.handleActionKey(event)
        }
        panel.onKeyChange = { [weak self] key in
            guard let self else { return }
            if key {
                ContentPreviewWindow.quick.captureShortcut(in: self.panel) { [weak self] event in
                    self?.previewAction(for: event) != nil
                }
            } else {
                ContentPreviewWindow.quick.releaseShortcut(in: self.panel)
            }
        }
        panel.actionMenuContainsPoint = { [weak model] point in
            guard let model, model.isActionsMenuPresented else { return false }
            return model.actionsMenuFrame.contains(point)
        }
        panel.actionPreferences = { [weak model] in model?.actionPreferences ?? SettingsPreferences() }
        panel.onCopyPath = { [weak model] in model?.copySelectedPath() ?? false }
        panel.onRevealInFinder = { [weak model] in model?.revealSelectionInFinder() ?? false }
        model.onHide = { [weak self] in self?.hide() }
        model.onPreviewFile = { [weak self] file in
            guard let self else { return }
            ContentPreviewWindow.quick.show(file: file, label: file.url.lastPathComponent, from: self.panel,
                shortcut: self.model.actionPreferences.shortcut(.launcherPreview), onBlur: self.panel.onBlur)
        }
        resultReveal.onStep = { [weak self] height in
            guard let self else { return }
            self.shellHeight = CGFloat(height)
            self.layoutSurfaces()
        }
        toastPanel.ignoresMouseEvents = true
    }

    var onOpenSettings: () -> Void {
        get { panel.onOpenSettings }
        set { panel.onOpenSettings = newValue }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { isVisible ? hide() : show() }

    private func previewAction(for event: NSEvent) -> LauncherAction? {
        guard model.actionPreferences.shortcut(.launcherPreview).matches(event),
              (panel.firstResponder as? NSTextView)?.hasMarkedText() != true else { return nil }
        return model.previewLauncherAction
    }

    private func handlePreviewKey(_ event: NSEvent) -> Bool {
        guard let action = previewAction(for: event) else { return false }
        if !event.isARepeat { model.performLauncherAction(action) }
        return true
    }

    func show(on targetScreen: NSScreen? = nil) {
        LauncherPresentationTrace.record("show-request", panel: panel)
        let isFirstOpen = hosting == nil
        WindowDiagnostics.shared.record("launcher-show-start", window: panel, includeEvent: true, extra: [
            ("first", isFirstOpen ? "1" : "0"),
        ])
        // Menu/Dock reopen requests can arrive while the launcher is visible.
        // Resetting the spring then would leave the unchanged chrome at alpha 0.
        guard !panel.isVisible else {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        model.rebuildProviders()
        let screen = targetScreen ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            availableShellHeight = min(LauncherLayout.expandedHeight, floor(f.height * (1 - LauncherLayout.topInsetFraction) - LauncherLayout.bottomClearance))
            // Anchor near the top of the pointer screen, leaving room for results below.
            // NSWindow rounds origins and sizes independently to whole points.
            // A fractional top anchor plus a fractional spring height can round
            // their sum to alternating top edges (a visible one-point jump).
            origin = NSPoint(x: (f.midX - LauncherLayout.toolbarWidth / 2).rounded(),
                             y: (f.maxY - f.height * LauncherLayout.topInsetFraction).rounded())
        }
        // Every show is a fresh content session, but keeps the same glass and input.
        presentation.sessionID = UUID()
        presentation.maxShellHeight = availableShellHeight
        presentation.hasExpanded = false
        presentation.statusHeight = 0
        presentation.isPresented = true
        shellHeight = LauncherLayout.inputHeight
        targetShellHeight = shellHeight
        resultReveal.set(Double(shellHeight))
        // Install first content at its final screen frame, not at the origin.
        layoutSurfaces()
        if hosting == nil {
            let view = NSHostingView(rootView: AnyView(LauncherView(model: model, presentation: presentation,
                onHeightChange: { [weak self] sessionID, height in
                    guard let self, self.presentation.isPresented,
                          self.presentation.sessionID == sessionID else { return }
                    self.resizeTask?.cancel()
                    self.resizeTask = Task { @MainActor [weak self] in
                        guard !Task.isCancelled, let self, self.presentation.isPresented,
                              self.presentation.sessionID == sessionID else { return }
                        self.resize(to: height)
                    }
                }, onChromeChange: { [weak self] sessionID, chrome in
                    guard let self, self.presentation.isPresented,
                          self.presentation.sessionID == sessionID else { return }
                    self.update(chrome)
                }, onSearchFieldCreated: { [weak self] field in
                    self?.searchField = field
                })
                .frame(maxHeight: .infinity, alignment: .top)))
            view.sizingOptions = []
            let size = NSSize(width: LauncherLayout.toolbarWidth, height: shellHeight)
            let container = NSView(frame: NSRect(origin: .zero, size: size))
            container.clipsToBounds = true
            view.frame = NSRect(x: 0, y: size.height - availableShellHeight,
                                width: size.width, height: availableShellHeight)
            view.autoresizingMask = [.width, .minYMargin]
            container.addSubview(view)
            panel.contentView = WindowSurface.glassContentView(container, cornerRadius: LauncherLayout.shellCornerRadius)
            hosting = view
            LauncherPresentationTrace.record("content-installed", panel: panel)
        } else {
            // Re-resolve the stable canvas when moving between differently sized screens.
            hosting?.frame = NSRect(x: 0, y: shellHeight - availableShellHeight,
                                    width: LauncherLayout.toolbarWidth, height: availableShellHeight)
        }
        // Cold SwiftUI/glass construction can leave the first backing-store
        // update pending. Finish layout, including AppKit's frame view, while
        // the window is still off screen rather than ordering an empty frame.
        panel.contentView?.superview?.layoutSubtreeIfNeeded()
        panel.contentView?.layoutSubtreeIfNeeded()
        if let surface = panel.contentView {
            WindowSurface.updateCorners(of: surface,
                radius: LauncherLayout.shellCornerRadius, circular: true)
        }
        // The launcher owns focus timing; no creation-time async request can outlive a show.
        if let searchField, searchField.window === panel {
            panel.makeFirstResponder(searchField)
            LauncherPresentationTrace.record("editor-focused", panel: panel)
            panel.contentView?.layoutSubtreeIfNeeded()
        }
        panel.displayIfNeeded()
        LauncherPresentationTrace.record("layout-ready", panel: panel)
        panel.makeKeyAndOrderFront(nil)
        LauncherPresentationTrace.record("ordered-front", panel: panel)
        if isFirstOpen {
            WindowDiagnostics.shared.recordLauncherFirstOpen(panel: panel)
        }
        updateOutsideClickDismissal()
    }

    private func updateOutsideClickDismissal() {
        guard panel.isVisible else { outsideClickDismissal.hide(); return }
        outsideClickDismissal.show(contains: { [weak self] point in
            guard let self else { return false }
            if self.model.isConfirmingPluginCommand { return true }
            if ContentPreviewWindow.quick.contains(point, from: self.panel) { return true }
            let surfaces = [self.panel]
            return surfaces.contains { $0.isVisible && !$0.ignoresMouseEvents && $0.alphaValue > 0 && $0.frame.contains(point) }
        }, dismiss: { [weak self] in self?.hide() })
    }

    private func update(_ next: LauncherChrome) {
        let previous = chrome
        chrome = next
        if next.toast != previous.toast { setToast(next.toast) }
        layoutSurfaces()
    }

    private func setToast(_ message: String?) {
        guard let message else { toastPanel.remove(); return }
        let view = ClipboardStatusToast(message: message)
        toastPanel.setSurface(view, size: SurfacePanel.fittingSize(of: view, maxWidth: LauncherLayout.toolbarWidth - 48),
                              cornerRadius: ClipboardStatusToast.cornerRadius, glass: false)
        layoutSurfaces()
        panel.addChildWindow(toastPanel, ordered: .above)
    }

    /// Places every surface from the toolbar origin. Child windows follow the
    /// parent's origin automatically, so they are reset after each shell move.
    private func layoutSurfaces() {
        let width = LauncherLayout.toolbarWidth
        let height = shellHeight.rounded()
        let frame = NSRect(x: origin.x, y: origin.y - height, width: width, height: height)
        if panel.frame != frame {
            // The display link already animates the frame. Commit the glass,
            // clipping layers and field editor together, without a second layer
            // animation trailing the window during contraction.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            panel.setFrame(frame, display: false)
            panel.contentView?.superview?.layoutSubtreeIfNeeded()
            hosting?.layoutSubtreeIfNeeded()
            CATransaction.commit()
        }
        if toastPanel.isVisible {
            let size = toastPanel.frame.size
            toastPanel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY + 12))
        }
    }

    private func resize(to contentHeight: CGFloat) {
        let height = min(availableShellHeight, max(LauncherLayout.inputHeight, ceil(contentHeight)))
        guard targetShellHeight != height else { return }
        targetShellHeight = height
        // AppKit's origin is at the bottom left; the input stays anchored while expanding down.
        // Reveal the fixed-height glass window while preserving the hosting
        // canvas and field editor. Later result batches keep this target.
        if panel.isVisible,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            resultReveal.animate(to: Double(height), response: 0.18, damping: 1, in: panel)
        } else {
            resultReveal.set(Double(height))
        }
    }

    /// Keep the light shell/header; explicitly unmount result content and cancel its work.
    func hide() {
        guard panel.isVisible, !hiding else { return }
        LauncherPresentationTrace.record("hide-request", panel: panel)
        hiding = true
        defer { hiding = false }
        // Invalidate before orderOut or model reset can invoke any old callbacks.
        presentation.isPresented = false
        presentation.sessionID = UUID()
        ContentPreviewWindow.quick.dismiss(from: panel)
        outsideClickDismissal.hide()
        resultReveal.stop()
        for surface in [toastPanel] { surface.remove() }
        panel.orderOut(nil)
        resizeTask?.cancel()
        resizeTask = nil
        chrome = LauncherChrome()
        panel.makeFirstResponder(nil)
        model.reset()
        presentation.hasExpanded = false
        presentation.statusHeight = 0
        hosting?.layoutSubtreeIfNeeded()
        // Reset the retained shell off-screen. Never leave it expanded until next show.
        shellHeight = LauncherLayout.inputHeight
        targetShellHeight = shellHeight
        resultReveal.set(Double(shellHeight))
        LauncherPresentationTrace.record("session-unmounted", panel: panel)
    }
}

struct LauncherView: View {
    @Bindable var model: LauncherModel
    @Bindable var presentation: LauncherPresentationState
    var onHeightChange: (UUID, CGFloat) -> Void = { _, _ in }
    var onChromeChange: (UUID, LauncherChrome) -> Void = { _, _ in }
    var onSearchFieldCreated: (NSTextField) -> Void = { _ in }
    private var maxShellHeight: CGFloat { presentation.maxShellHeight }
    @Environment(\.colorScheme) private var colorScheme

    private var shellShape: RoundedRectangle {
        // Preserve the same circular corners before and after results expand.
        RoundedRectangle(cornerRadius: LauncherLayout.shellCornerRadius, style: .circular)
    }

    private var inputHeight: CGFloat { LauncherLayout.inputHeight }
    private var isEmptyRoot: Bool {
        !model.hasScope && model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && model.terminal == nil
    }
    private var hasContent: Bool {
        !model.results.isEmpty || model.hasScope || model.status != nil || model.terminal != nil
            || model.calculation != nil || model.unitConversion != nil || model.currencyConversion != nil
    }
    private var chrome: LauncherChrome {
        LauncherChrome(toast: model.toast)
    }

    var body: some View {
        let sessionID = presentation.sessionID
        return searchShell
            .overlayPreferenceValue(LauncherMoreAnchorKey.self) { anchor in
                GeometryReader { geometry in
                    if presentation.isPresented, let anchor {
                        let rect = geometry[anchor]
                        let availableHeight = max(32, rect.maxY - 12)
                        let height = min(availableHeight, LauncherMorphingActions.menuHeight(actionCount: model.secondaryActions.count))
                        let hitRect = CGRect(x: rect.maxX - LauncherLayout.actionsMenuWidth,
                                             y: geometry.size.height - rect.maxY,
                                             width: LauncherLayout.actionsMenuWidth, height: height)
                        let surfaceWidth = model.isActionsMenuPresented ? LauncherLayout.actionsMenuWidth : rect.width
                        let surfaceHeight = model.isActionsMenuPresented ? height : rect.height
                        LauncherMorphingActions(model: model, availableHeight: availableHeight)
                            .frame(width: surfaceWidth, height: surfaceHeight, alignment: .bottomTrailing)
                            .position(x: rect.maxX - surfaceWidth / 2, y: rect.maxY - surfaceHeight / 2)
                            .onChange(of: hitRect, initial: true) { _, frame in
                                guard presentation.isPresented, presentation.sessionID == sessionID else { return }
                                model.actionsMenuFrame = frame
                            }
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                onHeightChange(sessionID, height)
            }
            .onChange(of: chrome, initial: true) { _, chrome in onChromeChange(sessionID, chrome) }
            .onChange(of: presentation.sessionID) { _, _ in
                presentation.hasExpanded = presentation.isPresented && hasContent && !isEmptyRoot
            }
            .onChange(of: hasContent, initial: true) { _, hasContent in
                if presentation.isPresented && hasContent && !isEmptyRoot { presentation.hasExpanded = true }
            }
            .onChange(of: isEmptyRoot, initial: true) { _, empty in
                if empty { presentation.hasExpanded = false }
            }
    }

    private var searchShell: some View {
        VStack(spacing: 0) {
            HStack(spacing: LauncherLayout.inputSpacing) {
                if let folder = model.folderScope {
                    HStack(spacing: 6) {
                        LauncherSystemArtwork(request: .file(path: folder.path), fallback: "folder")
                            .frame(width: 24, height: 24)
                        Text(folder.lastPathComponent)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .frame(maxWidth: LauncherLayout.folderScopeMaxWidth, alignment: .leading)
                    .frame(height: LauncherLayout.folderScopeHeight)
                    .fixedSize(horizontal: true, vertical: false)
                    .help(folder.path)
                    .accessibilityLabel(folder.path)
                } else if model.hasScope {
                    commandIcon
                        .frame(width: 24, height: 24)
                        .accessibilityLabel(model.pluginScope?.command.title ?? (model.filter != .all ? NSLocalizedString(model.filter.title, tableName: "Launcher", comment: "Launcher filter") : model.isTerminalScope ? NSLocalizedString("终端命令", comment: "") : model.isTabScope ? NSLocalizedString("搜索开启的标签页", comment: "") : model.isBookmarkScope ? NSLocalizedString("搜索书签", comment: "") : model.isAIScope ? NSLocalizedString("AI 搜索", comment: "") : model.isLinkScope ? NSLocalizedString("搜索链接", comment: "") : model.commandInput.map { NSLocalizedString($0.command.name, comment: "Built-in website command") } ?? NSLocalizedString("关键词命令", comment: "")))
                }
                LauncherSearchField(
                    text: Binding(get: { model.inputText }, set: { model.inputText = $0 }),
                    fontSize: 16,
                    textColor: NSColor(ThemeColor.kText.color(for: colorScheme)),
                    placeholder: NSLocalizedString("搜索或输入你的任务", comment: "Launcher empty input placeholder"),
                    placeholderColor: NSColor(ThemeColor.kTextSubtlest.color(for: colorScheme)),
                    completion: model.calculationCompletion,
                    backspaceOnEmpty: model.backspaceOnEmptyInput,
                    move: model.move,
                    submit: { model.submit($0 ? .submitToAI : .executeSelection) },
                    copyPath: model.copySelectedPath,
                    revealInFinder: model.revealSelectionInFinder,
                    copyPathShortcut: model.actionPreferences.copyPathHotKey,
                    revealInFinderShortcut: model.actionPreferences.revealInFinderHotKey,
                    enterFolder: model.enterSelectedFolder,
                    shortcuts: model.actionPreferences, shortcutScope: "launcher",
                    automaticallyFocus: false, onCreate: onSearchFieldCreated
                )
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                searchIcon
            }
            .padding(.leading, LauncherLayout.inputLeadingPadding)
            .padding(.trailing, LauncherLayout.inputTrailingPadding)
            .frame(height: inputHeight)

            if presentation.isPresented {
                sessionContent(sessionID: presentation.sessionID)
                    .id(presentation.sessionID)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: presentation.hasExpanded ? maxShellHeight : inputHeight, alignment: .top)
        .foregroundStyle(ThemeColor.kText.color(for: colorScheme))
        // Blank input/result areas must belong to the shell's pointer region.
        .contentShape(shellShape)
        .clipShape(shellShape)
        .windowSurfaceBackground(in: shellShape)
        .contentShape(shellShape)
        .onChange(of: model.status) { _, status in
            if status == nil { presentation.statusHeight = 0 }
        }
    }
    /// Unmounted while hidden, including scroll state, menus and terminal display.
    private func sessionContent(sessionID: UUID) -> some View {
        VStack(spacing: 0) {
            if let t = model.terminal {
                inputDivider
                TerminalOutputView(session: t, stop: model.stopTerminal)
            } else if let calculation = model.calculation {
                inputDivider
                CalculationView(expression: calculation.expression, result: calculation.result)
                    .frame(height: LauncherLayout.currencyCardHeight)
                    .padding(.bottom, LauncherLayout.actionBarHeight)
                    .frame(height: maxShellHeight - inputHeight - LauncherLayout.dividerHeight - presentation.statusHeight, alignment: .top)
                    .overlay(alignment: .bottom) { LauncherActionBar(model: model) }
            } else if let conversion = model.unitConversion {
                inputDivider
                ConversionPairView {
                    ConversionValueCard(title: conversion.fromSymbol, amount: Calculator.format(conversion.input))
                } destination: {
                    ConversionValueCard(title: conversion.toSymbol,
                                        amount: conversion.formattedValue)
                }
                .frame(height: LauncherLayout.currencyCardHeight)
            } else if case .converted(let value, _, _, _, let query) = model.currencyConversion {
                inputDivider
                CurrencyConversionView(query: query, value: value)
                    .frame(height: LauncherLayout.currencyCardHeight)
                if model.results.contains(where: { $0.source == .currency && $0.target.identifier != query.to }) {
                    ResultList(model: model, maxHeight: maxShellHeight - inputHeight
                               - LauncherLayout.dividerHeight - LauncherLayout.currencyCardHeight - presentation.statusHeight,
                               excludedCurrencyCode: query.to)
                }
            } else if presentation.hasExpanded || !model.results.isEmpty {
                inputDivider
                ResultList(model: model, maxHeight: maxShellHeight
                           - inputHeight - LauncherLayout.dividerHeight - presentation.statusHeight)
            }
            if let s = model.status {
                Text(s).font(.system(size: 14)).foregroundStyle(ThemeColor.kTextSubtle)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, LauncherLayout.inputLeadingPadding)
                    .padding(.trailing, LauncherLayout.inputTrailingPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                        guard presentation.isPresented, presentation.sessionID == sessionID else { return }
                        presentation.statusHeight = height
                    }
            }
        }
    }

    private var searchIcon: some View {
        Image(mingCute: "magnifyingglass", size: LauncherLayout.searchIconSize)
            .foregroundStyle(ThemeColor.kIconSubtle.color(for: colorScheme))
            .frame(width: LauncherLayout.inputAccessoryWidth, height: LauncherLayout.inputAccessoryHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var commandIcon: some View {
        if model.pluginScope != nil {
            LauncherFunctionIcon(kind: .plugin)
        } else if model.filter != .all {
            LauncherFunctionIcon(kind: .searchCommand(model.filter.rawValue))
        } else if model.isTerminalScope {
            LauncherSystemArtwork(request: .application(bundleID: model.terminalApplication.rawValue), fallback: "terminal")
        } else if model.isTabScope {
            LauncherFunctionIcon(kind: .tabs)
        } else if model.isBookmarkScope {
            LauncherFunctionIcon(kind: .bookmark)
        } else if model.isAIScope {
            LauncherFunctionIcon(kind: .ai)
        } else if model.isLinkScope {
            LauncherFunctionIcon(kind: .link)
        } else if let command = model.commandInput?.command {
            CommandIcon(keyword: KeywordCommand.builtIn.first { $0.urlTemplate == command.urlTemplate }?.keyword ?? command.keyword)
        } else {
            Image(mingCute: "globe", size: 20).foregroundStyle(ThemeColor.kIcon)
        }
    }

    private var inputDivider: some View {
        Rectangle().fill(ThemeColor.kBorder)
            .frame(height: LauncherLayout.dividerHeight)
            .padding(.horizontal, 28)
    }

}

/// The input field owns editing and Return still copies the computed result.
private struct CalculationView: View {
    let expression: String
    let result: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(expression)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(ThemeColor.kTextSubtle)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(expression)
            Text(result)
                .font(.system(size: 28, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(ThemeColor.kText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .help(result)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeColor.kBackgroundNeutral,
                    in: RoundedRectangle(cornerRadius: LauncherLayout.rowCornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(expression) = \(result)")
        .padding(.horizontal, LauncherLayout.inputLeadingPadding)
        .padding(.top, 16)
        .padding(.bottom, 20)
    }
}

/// A read-only conversion pair; the input field owns editing.
private struct CurrencyConversionView: View {
    let query: CurrencyQuery
    let value: Double

    var body: some View {
        ConversionPairView {
            currency(code: query.from, amount: query.amount)
        } destination: {
            currency(code: query.to, amount: value)
        }
    }

    private func currency(code: String, amount: Double) -> some View {
        ConversionValueCard(title: code, subtitle: CurrencyPresentation.name(for: code),
                            flag: CurrencyPresentation.flag(for: code),
                            amount: amount.formatted(.number.precision(.fractionLength(0...2))))
    }
}

/// Units and currencies share the same read-only two-card layout.
private struct ConversionPairView<Source: View, Destination: View>: View {
    @ViewBuilder var source: Source
    @ViewBuilder var destination: Destination

    var body: some View {
        HStack(spacing: 12) {
            source
            Image(mingCute: "arrow.left.arrow.right", size: 16)
                .foregroundStyle(ThemeColor.kIcon)
                .accessibilityHidden(true)
            destination
        }
        .padding(.horizontal, LauncherLayout.inputLeadingPadding)
        .padding(.top, 16)
        .padding(.bottom, 20)
    }
}

private struct ConversionValueCard: View {
    let title: String
    var subtitle: String? = nil
    var flag: String? = nil
    let amount: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let flag {
                    Text(flag).font(.system(size: 22)).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ThemeColor.kText)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(ThemeColor.kTextSubtle)
                            .lineLimit(1)
                    }
                }
            }
            .frame(height: 34, alignment: .leading)
            Text(amount)
                .font(.system(size: 28, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(ThemeColor.kText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThemeColor.kBackgroundNeutral,
                    in: RoundedRectangle(cornerRadius: LauncherLayout.rowCornerRadius))
        .accessibilityElement(children: .combine)
    }
}

private struct ResultList: View {
    @Bindable var model: LauncherModel
    let maxHeight: CGFloat
    var excludedCurrencyCode: String? = nil
    @State private var pointerSelection: Int?
    @State private var lastSelectionPointerLocation = NSEvent.mouseLocation
    @State private var isRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleResults: [SearchResult] {
        model.results.filter { $0.source != .currency || $0.target.identifier != excludedCurrencyCode }
    }

    private enum Row: Identifiable {
        case header(String)
        case result(index: Int, value: SearchResult)

        var id: String {
            switch self {
            case .header(let title): "section:\(title)"
            case .result(_, let value): value.id
            }
        }
    }

    /// Flatten sections so even an unrealized row has a scroll target in the lazy stack.
    private var rows: [Row] {
        let visible = model.results.enumerated().filter {
            $0.element.source != .currency || $0.element.target.identifier != excludedCurrencyCode
        }
        var order: [String] = []
        var groups: [String: [Row]] = [:]
        for (index, result) in visible {
            let section = Self.section(for: result)
            if groups[section] == nil { order.append(section) }
            groups[section, default: []].append(.result(index: index, value: result))
        }
        let showsHeaders = !model.hasScope && Set(visible.filter { $0.element.source != .askAI }
            .map { Self.section(for: $0.element) }).count > 1
        return order.flatMap { section in
            (showsHeaders ? [Row.header(section)] : []) + (groups[section] ?? [])
        }
    }

    private var footerHeight: CGFloat { model.primaryLauncherAction == nil ? 0 : LauncherLayout.actionBarHeight }
    private var bottomPadding: CGFloat { LauncherLayout.listBottomPadding + footerHeight }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let source):
                            Text(source).font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ThemeColor.kTextSubtle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 6).padding(.bottom, 4)
                                .frame(height: LauncherLayout.sectionHeaderHeight)
                        case .result(let i, let r):
                            if r.source == .currency {
                                ResultRow(result: r, selected: false, keyword: nil)
                                    .accessibilityLabel(r.title)
                                    .padding(.bottom, r.id == visibleResults.last?.id ? bottomPadding : 0)
                                    .id(r.id)
                            } else {
                                Button {
                                    model.selection = i
                                    model.submit(.executeSelection)
                                } label: {
                                    ResultRow(result: r, selected: i == model.selection, keyword: model.keyword(for: r),
                                              terminalApplication: model.terminalApplication,
                                              applicationIconPath: model.windowApplicationPath(for: r))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(r.title)
                                .accessibilityAddTraits(i == model.selection ? .isSelected : [])
                                .onHover { inside in
                                    guard inside, !model.isActionsMenuPresented else { return }
                                    let location = NSEvent.mouseLocation
                                    guard location != lastSelectionPointerLocation else { return }
                                    lastSelectionPointerLocation = location
                                    guard model.selection != i else { return }
                                    pointerSelection = i
                                    model.selection = i
                                }
                                .padding(.bottom, r.id == visibleResults.last?.id ? bottomPadding : 0)
                                .id(r.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, LauncherLayout.listHorizontalPadding)
                .overlay(alignment: .top) {
                    Color.clear.frame(height: 0).id("launcher-results-origin")
                }
            }
            .scrollIndicators(.hidden)
            .mask(alignment: .bottom) {
                GeometryReader { geometry in
                    let fade = footerHeight / max(1, geometry.size.height)
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: max(0, 1 - fade - 0.06)),
                        .init(color: .clear, location: max(0, 1 - fade * 0.35)),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
            }
            .overlay(alignment: .bottom) {
                if footerHeight > 0 { LauncherActionBar(model: model) }
            }
            .frame(height: max(0, maxHeight))
            .onChange(of: model.query) { _, _ in
                pointerSelection = nil
                proxy.scrollTo("launcher-results-origin", anchor: .top)
            }
            .onChange(of: model.selection) { _, s in
                // Hover must select the row without moving it away from the pointer.
                let fromPointer = pointerSelection == s
                pointerSelection = nil
                if fromPointer { return }
                guard model.results.indices.contains(s) else { return }
                if s == 0 { proxy.scrollTo("launcher-results-origin", anchor: .top) }
                else { proxy.scrollTo(model.results[s].id, anchor: .center) }
            }
        }
        .onChange(of: model.isActionsMenuPresented) { _, _ in
            // Revealing a row under the transforming surface is not pointer movement.
            lastSelectionPointerLocation = NSEvent.mouseLocation
        }
        // Only reveal the list on insertion. Provider batches, typing and
        // keyboard selection must not restart the entrance or animate rows.
        .opacity(isRevealed ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0.10 : 0.18)) {
                isRevealed = true
            }
        }
    }

    private static func section(for result: SearchResult) -> String {
        if result.target.kind.hasPrefix("plugin-") { return NSLocalizedString("插件", tableName: "Plugins", comment: "") }
        if QuitAskyCommand.isResult(result) { return title(.app) }
        if result.target.kind == "search-command", result.target.identifier == "colorPicker" { return NSLocalizedString("取色", comment: "") }
        if ["search-command", "tab-search"].contains(result.target.kind) { return NSLocalizedString("搜索指令", comment: "") }
        if ["keyword-match", "launcher-alias"].contains(result.target.kind) { return NSLocalizedString("别名匹配", comment: "") }
        switch result.source {
        case .app, .link, .bookmark: return title(.app)
        default: return title(result.source)
        }
    }

    private static func title(_ source: SearchSource) -> String {
        switch source {
        case .app: NSLocalizedString("APP 应用", comment: "")
        case .file: NSLocalizedString("文件文档", comment: "")
        case .link: NSLocalizedString("链接", comment: "")
        case .bookmark: NSLocalizedString("书签", comment: "")
        case .chromeTab: NSLocalizedString("Chrome 标签页", comment: "")
        case .shortcut: NSLocalizedString("快捷指令", comment: "")
        case .keyword: NSLocalizedString("默认搜索", comment: "")
        case .askAI: "AI"
        case .calculator, .conversion, .currency: NSLocalizedString("计算与换算", comment: "")
        case .terminal: NSLocalizedString("终端命令", comment: "")
        case .clipboard: NSLocalizedString("剪贴板", comment: "")
        }
    }
}

private struct ResultRow: View {
    let result: SearchResult
    let selected: Bool
    let keyword: String?
    var terminalApplication = LauncherTerminalApplication.system
    var applicationIconPath: String?
    @State private var loaded: Loaded?

    private struct Loaded {
        let request: LauncherArtworkRequest
        let presentation: LauncherRowPresentation
    }

    private var artworkRequest: LauncherArtworkRequest? {
        if result.target.kind.hasPrefix("plugin-") || result.target.kind == "search-command" || QuitAskyCommand.isResult(result) { return nil }
        if result.target.kind == "application-window", let applicationIconPath, !applicationIconPath.isEmpty {
            return .file(path: applicationIconPath)
        }
        switch result.source {
        case .app: return .file(path: result.target.identifier)
        case .file: return .file(path: result.target.identifier, includeType: true)
        case .shortcut: return .application(bundleID: "com.apple.shortcuts")
        case .terminal: return .application(bundleID: terminalApplication.rawValue)
        case .bookmark, .keyword:
            if result.source == .keyword, let keyword, CommandIcon.Brand(rawValue: keyword) != nil { return nil }
            if result.target.kind == "launcher-alias", result.primaryAction == .open {
                return .file(path: result.target.identifier)
            }
            if result.target.kind == "launcher-alias", case .runShortcut = result.primaryAction {
                return .application(bundleID: "com.apple.shortcuts")
            }
            if result.target.kind == "bookmark-search" { return nil }
            if case .openURL(let url) = result.primaryAction { return .browser(url) }
            return nil
        default: return nil
        }
    }

    private var presentation: LauncherRowPresentation? {
        guard let request = artworkRequest else { return nil }
        if let loaded, loaded.request == request { return loaded.presentation }
        return ToolService.cachedLauncherPresentation(for: request)
    }

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: LauncherLayout.rowIconSize, height: LauncherLayout.rowIconSize)
            Text(keyword == nil ? result.title : result.title.components(separatedBy: "：").first ?? result.title)
                .font(.system(size: 14)).lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(ThemeColor.kText)
                .layoutPriority(1)
            if let keyword {
                Text(keyword).font(.system(size: 12)).lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(ThemeColor.kTextSubtle)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(ThemeColor.kBackgroundNeutral,
                                in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer(minLength: 12)
            Text(typeLabel)
                .font(.system(size: 12))
                .foregroundStyle(ThemeColor.kTextSubtlest)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 160, alignment: .trailing)
                .layoutPriority(2)
        }
        .padding(.horizontal, LauncherLayout.rowHorizontalPadding)
        .frame(height: LauncherLayout.rowHeight)
        .background(result.source == .currency ? AnyShapeStyle(.clear) :
                        selected ? AnyShapeStyle(ThemeColor.kBackgroundSelected) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: LauncherLayout.rowCornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: LauncherLayout.rowCornerRadius))
        .task(id: artworkRequest) {
            guard let request = artworkRequest else { loaded = nil; return }
            let value = await ToolService.loadLauncherPresentation(for: request)
            guard !Task.isCancelled, let value else { return }
            loaded = Loaded(request: request, presentation: value)
        }
    }

    private var typeLabel: String {
        if result.target.kind == "plugin-result", !result.subtitle.isEmpty { return result.subtitle }
        if result.target.kind.hasPrefix("plugin-") { return NSLocalizedString("插件", tableName: "Plugins", comment: "") }
        if result.target.kind == "application-window" {
            return NSLocalizedString("窗口", tableName: "Launcher", comment: "Result type")
        }
        let key: String
        switch result.source {
        case .app: key = "应用"
        case .file:
            return presentation?.fileType
                ?? NSLocalizedString("文件", tableName: "Launcher", comment: "Result type")
        case .link: key = "链接"
        case .bookmark: key = "书签"
        case .chromeTab: key = "标签页"
        case .clipboard: key = "剪贴板"
        case .keyword: key = "命令"
        case .calculator: key = "计算"
        case .conversion: key = "单位换算"
        case .currency: key = "汇率"
        case .terminal: key = "终端命令"
        case .shortcut: key = "快捷指令"
        case .askAI: return "AI"
        }
        return NSLocalizedString(key, tableName: "Launcher", comment: "Result type")
    }

    @ViewBuilder private var icon: some View {
        if result.target.kind.hasPrefix("plugin-") {
            LauncherFunctionIcon(kind: .plugin)
        } else if result.target.kind == "search-command" {
            LauncherFunctionIcon(kind: .searchCommand(result.target.identifier))
        } else if result.target.kind == "application-window", let applicationIconPath, !applicationIconPath.isEmpty {
            systemIcon(fallback: "app.badge")
        } else if QuitAskyCommand.isResult(result) {
            LauncherFunctionIcon(kind: .quit)
        } else {
            sourceIcon
        }
    }

    @ViewBuilder private var sourceIcon: some View {
        switch result.source {
        case .app, .file:
            systemIcon(fallback: result.source == .file ? "doc" : "app.badge")
        case .shortcut:
            systemIcon(fallback: "square.stack.3d.up")
        case .chromeTab:
            LauncherFunctionIcon(kind: .tabs)
        case .terminal:
            CommandIcon(terminalIcon: presentation?.icon)
        case .currency:
            if let flag = CurrencyPresentation.flag(for: result.target.identifier) {
                Text(flag).font(.system(size: LauncherLayout.rowIconSize))
                    .accessibilityLabel(CurrencyPresentation.name(for: result.target.identifier))
            } else {
                Image(mingCute: Self.symbol(.currency), size: LauncherLayout.rowIconSize).foregroundStyle(ThemeColor.kIcon)
            }
        case .link:
            LauncherFunctionIcon(kind: .link)
        case .calculator:
            LauncherFunctionIcon(kind: .calculator)
        case .conversion:
            LauncherFunctionIcon(kind: .conversion)
        case .askAI:
            LauncherFunctionIcon(kind: .ai)
        case .bookmark, .keyword:
            if result.source == .keyword, let keyword, CommandIcon.Brand(rawValue: keyword) != nil {
                CommandIcon(keyword: keyword)
            } else if result.target.kind == "launcher-alias", result.primaryAction == .open {
                systemIcon(fallback: "app.badge")
            } else if result.target.kind == "launcher-alias", case .runShortcut = result.primaryAction {
                systemIcon(fallback: "square.stack.3d.up")
            } else if result.target.kind == "search-command" {
                LauncherFunctionIcon(kind: .searchCommand(result.target.identifier))
            } else if result.target.kind == "bookmark-search" {
                LauncherFunctionIcon(kind: .bookmark)
            } else if case .openURL = result.primaryAction {
                systemIcon(fallback: "globe")
            } else {
                Image(mingCute: "globe", size: LauncherLayout.rowIconSize).foregroundStyle(ThemeColor.kIcon)
            }
        default:
            Image(mingCute: Self.symbol(result.source), size: LauncherLayout.rowIconSize).foregroundStyle(ThemeColor.kIcon)
        }
    }

    @ViewBuilder private func systemIcon(fallback: String) -> some View {
        if let icon = presentation?.icon {
            Image(nsImage: icon).resizable().scaledToFit()
        } else {
            Image(mingCute: fallback, size: LauncherLayout.rowIconSize).foregroundStyle(ThemeColor.kIcon)
        }
    }

    static func symbol(_ s: SearchSource) -> String {
        switch s {
        case .chromeTab, .keyword: "globe"
        case .clipboard: "doc.on.clipboard"
        case .calculator: "equal.square"
        case .conversion: "arrow.left.arrow.right"
        case .currency: "dollarsign.arrow.circlepath"
        case .terminal: "terminal"
        case .shortcut: "square.stack.3d.up"
        case .askAI: "sparkles"
        case .app, .file, .link, .bookmark: "doc"
        }
    }
}

private struct TerminalOutputView: View {
    let session: TerminalSession
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("> \(session.command)").font(.system(.body, design: .monospaced)).lineLimit(1)
                Spacer()
                if session.handedOff {
                    Text(NSLocalizedString("已转到“终端”", comment: "")).textStyle(.secondary)
                } else if let code = session.exitCode {
                    Text(String(format: NSLocalizedString("退出码 %@", comment: ""), String(code))).textStyle(.secondary)
                        .foregroundStyle(code == 0 ? ThemeColor.kTextPositive : ThemeColor.kTextNegative)
                } else {
                    Button(NSLocalizedString("停止", comment: ""), action: stop)
                }
            }
            ScrollView {
                Text(session.output.isEmpty ? " " : session.output)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 260)
            if let spilled = session.spilled {
                Button(String(format: NSLocalizedString("完整输出已保存：%@", comment: ""), spilled.lastPathComponent)) { NSWorkspace.shared.activateFileViewerSelecting([spilled]) }
                    .buttonStyle(.link)
            }
        }
        .padding(12)
    }
}

/// Scope artwork follows the same cache-only draw / background-load path as result rows.
private struct LauncherSystemArtwork: View {
    let request: LauncherArtworkRequest
    let fallback: String
    @State private var loadedRequest: LauncherArtworkRequest?
    @State private var image: NSImage?

    var body: some View {
        let warm = ToolService.cachedLauncherPresentation(for: request)?.icon
        let icon = warm ?? (loadedRequest == request ? image : nil)
        Group {
            if let icon {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(mingCute: fallback).resizable().scaledToFit()
            }
        }
        .task(id: request) {
            let value = await ToolService.loadLauncherPresentation(for: request)
            guard !Task.isCancelled else { return }
            image = value?.icon
            loadedRequest = request
        }
    }
}
