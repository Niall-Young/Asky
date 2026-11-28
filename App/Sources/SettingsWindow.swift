import AppKit
import SwiftUI
import Theme

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "advanced", search, clipboard, model, hotkey, aliases, keywords, terminal
    case mcp, data, sources, permissions, plugins, about, author

    var id: String { rawValue }
    var title: String {
        switch self {
        case .search: NSLocalizedString("搜索与导航", comment: "")
        case .clipboard: NSLocalizedString("剪贴板", comment: "")
        case .general: NSLocalizedString("通用", comment: "")
        case .model: NSLocalizedString("模型配置", comment: "")
        case .mcp: "MCP"
        case .data: NSLocalizedString("智能体", comment: "")
        case .hotkey: NSLocalizedString("触发快捷键", comment: "")
        case .aliases: NSLocalizedString("别名与快捷指令", comment: "")
        case .keywords: NSLocalizedString("指令", comment: "")
        case .terminal: NSLocalizedString("终端", comment: "")
        case .sources: NSLocalizedString("数据来源", comment: "")
        case .permissions: NSLocalizedString("系统权限", comment: "")
        case .plugins: NSLocalizedString("插件", comment: "")
        case .about: NSLocalizedString("关于 Asky", comment: "")
        case .author: NSLocalizedString("关于作者", comment: "")
        }
    }
    var symbol: String {
        switch self {
        case .search: "magnifyingglass"
        case .clipboard: "doc.on.clipboard"
        case .general: "gearshape"
        case .model: "sparkles"
        case .mcp: "link"
        case .data: "brain"
        case .hotkey: "keyboard"
        case .aliases: "command"
        case .keywords: "command.square"
        case .terminal: "terminal"
        case .sources: "square.stack.3d.up"
        case .permissions: "hand.raised.fill"
        case .plugins: "puzzlepiece.extension"
        case .about: "info.circle"
        case .author: "person.crop.circle"
        }
    }
    var iconAsset: String {
        "Settings-" + rawValue
    }
    var color: Color {
        switch self {
        case .general, .hotkey, .about, .author: .gray
        case .model, .mcp, .data: .purple
        case .aliases, .keywords, .terminal: .orange
        case .sources, .search, .clipboard: .blue
        case .permissions: .green
        case .plugins: .teal
        }
    }
    static func resolve(_ id: String) -> Self { Self(rawValue: id) ?? .general }
}

/// The app and regression harness share the same AppKit window and sidebar chrome.
@MainActor
enum SettingsWindow {
    static let initialSize = NSSize(width: 900, height: 700)
    static let minimumSize = NSSize(width: 820, height: 560)

    static func make(app: AppModel) -> NSWindow {
        let controller = SettingsContainerController(app: app)
        let window = SettingsEditingWindow(contentRect: NSRect(origin: .zero, size: initialSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.animationBehavior = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentViewController = controller
        window.contentMinSize = minimumSize
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        let toolbar = NSToolbar(identifier: "AskySettings")
        toolbar.delegate = controller.panes
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.setContentSize(initialSize)
        controller.panes.updateChrome()
        return window
    }
}

/// Owns the live Settings window lifecycle and closes it when clicking outside,
/// unless a modal sheet, file panel, dialog, or menu tracking loop is active.
@MainActor
final class SettingsWindowController {
    private let app: AppModel
    private let outsideClickDismissal = OutsideClickDismissal()
    private var observers: [NSObjectProtocol] = []
    private(set) var window: NSWindow?

    init(app: AppModel) {
        self.app = app
    }

    var isVisible: Bool { window?.isVisible == true }

    @discardableResult
    func show(presentation: WindowPresentation) -> NSWindow {
        let created = window == nil
        let target: NSWindow
        if let existing = window {
            target = existing
        } else {
            let made = SettingsWindow.make(app: app)
            made.level = .normal
            made.collectionBehavior = [.moveToActiveSpace, .primary]
            made.isReleasedWhenClosed = false
            made.center()
            installObservers(for: made)
            window = made
            target = made
        }
        WindowDiagnostics.shared.record("open-settings", window: target, includeEvent: true,
                                        includeStack: true, extra: [("created", created ? "1" : "0")])
        presentation.show(target)
        updateOutsideClickDismissal()
        return target
    }

    func close() {
        outsideClickDismissal.hide()
        guard let window, window.isVisible || window.isMiniaturized else { return }
        window.close()
    }

    func shouldKeepOpen(at point: NSPoint) -> Bool {
        guard let window, window.isVisible, !window.isMiniaturized else { return false }
        if window.attachedSheet != nil
            || NSApp.modalWindow != nil
            || RunLoop.current.currentMode == .eventTracking
            || AppDialogPresenter.shared.isPresenting(in: window)
            || AppDialogPresenter.shared.activeStandalonePanel != nil {
            return true
        }
        // Preserve macOS resize-edge hit targets just outside the window frame.
        if window.frame.insetBy(dx: -5, dy: -5).contains(point) { return true }
        if let children = window.childWindows,
           children.contains(where: { $0.isVisible && !$0.ignoresMouseEvents && $0.alphaValue > 0 && $0.frame.contains(point) }) {
            return true
        }
        return false
    }

    private func installObservers(for window: NSWindow) {
        let center = NotificationCenter.default
        let hideNames: [Notification.Name] = [
            NSWindow.willCloseNotification,
            NSWindow.willMiniaturizeNotification,
        ]
        observers = hideNames.map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.outsideClickDismissal.hide() }
            }
        }
        observers.append(center.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateOutsideClickDismissal() }
        })
    }

    private func updateOutsideClickDismissal() {
        guard let window, window.isVisible, !window.isMiniaturized else {
            outsideClickDismissal.hide()
            return
        }
        outsideClickDismissal.show(contains: { [weak self] point in
            self?.shouldKeepOpen(at: point) ?? false
        }, dismiss: { [weak self] in
            self?.close()
        })
    }
}

/// Own the backdrop outside NSSplitView: adding it to the split view would make
/// AppKit treat the glass as an extra pane and apply independent pane materials.
@MainActor
private final class SettingsContainerController: NSViewController {
    let panes: SettingsSplitViewController
    init(app: AppModel) {
        panes = SettingsSplitViewController(app: app)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = LauncherLayout.shellCornerRadius
        view.layer?.masksToBounds = true
        let backdrop = NSHostingView(rootView: SettingsBackdrop().ignoresSafeArea())
        addChild(panes)
        for child in [backdrop, panes.view] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
            NSLayoutConstraint.activate([
                child.topAnchor.constraint(equalTo: view.topAnchor),
                child.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                child.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        }
    }
}

private final class SettingsHeadingField: NSTextField {
    static let leadingInset: CGFloat = 12

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += Self.leadingInset
        return size
    }
}

@MainActor
private final class SettingsSplitViewController: NSSplitViewController, NSToolbarDelegate {
    private let app: AppModel
    private let heading = SettingsHeadingField(labelWithString: "")
    private static let separator = NSToolbarItem.Identifier("settingsSeparator")
    private static let title = NSToolbarItem.Identifier("settingsTitle")

    init(app: AppModel) {
        self.app = app
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        let sidebar = NSHostingController(rootView: SettingsSidebar(app: app) { [weak self] in
            self?.updateChrome()
        })
        let sidebarItem = NSSplitViewItem(viewController: sidebar)
        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 220
        sidebarItem.canCollapse = false
        sidebarItem.canCollapseFromWindowResize = false
        sidebarItem.holdingPriority = .defaultHigh
        sidebarItem.allowsFullHeightLayout = true
        addSplitViewItem(sidebarItem)

        let detail = SettingsDetailViewController(app: app)
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 540
        detailItem.titlebarSeparatorStyle = .line
        if #available(macOS 26, *) {
            detailItem.automaticallyAdjustsSafeAreaInsets = true
        }
        addSplitViewItem(detailItem)
        heading.font = .systemFont(ofSize: 16, weight: .medium)
        heading.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    func updateChrome() {
        let title = SettingsPage.resolve(app.settingsTab).title
        let paragraph = NSMutableParagraphStyle()
        // Include the label's optical inset when matching the form's leading edge.
        paragraph.firstLineHeadIndent = SettingsHeadingField.leadingInset
        heading.attributedStringValue = NSAttributedString(string: title, attributes: [
            .font: heading.font!, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ])
        heading.sizeToFit()
        heading.frame.size.width += paragraph.firstLineHeadIndent
        view.window?.title = "\(heading.stringValue) — \(NSLocalizedString("Asky 设置", comment: ""))"
        switch app.preferences.appearance {
        case "light": view.window?.appearance = NSAppearance(named: .aqua)
        case "dark": view.window?.appearance = NSAppearance(named: .darkAqua)
        default: view.window?.appearance = nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.separator, Self.title, .flexibleSpace]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id == Self.separator {
            return NSTrackingSeparatorToolbarItem(identifier: id, splitView: splitView, dividerIndex: 0)
        }
        if id == Self.title {
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = heading
            item.label = NSLocalizedString("设置页面", comment: "")
            return item
        }
        return nil
    }
}

/// Keep the scroll viewport below the toolbar, rather than merely insetting its
/// content: a full-height Form can otherwise scroll rows behind the page heading.
@MainActor
private final class SettingsDetailViewController: NSViewController {
    private let hosting: NSHostingController<AnyView>

    init(app: AppModel) {
        hosting = NSHostingController(rootView: AnyView(SettingsView(app: app)))
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()
        addChild(hosting)
        let content = hosting.view
        content.translatesAutoresizingMaskIntoConstraints = false
        content.clipsToBounds = true
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])
    }
}

private struct SettingsSidebar: View {
    @Bindable var app: AppModel
    let updateChrome: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sidebarGroup("Settings", pages: [.general, .search, .clipboard, .hotkey, .permissions])
                sidebarGroup("智能配置", pages: [.model, .data, .sources, .mcp])
                sidebarGroup("Tools", pages: [.aliases, .keywords, .terminal, .plugins])
                sidebarGroup("Others", pages: [.about, .author])
            }
            .padding(.horizontal, 12).padding(.top, 0).padding(.bottom, 16)
        }
        .onChange(of: app.settingsTab) { _, _ in updateChrome() }
        .onChange(of: app.preferences.appearance) { _, _ in updateChrome() }
    }

    private func sidebarGroup(_ title: String, pages: [SettingsPage]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString(title, comment: ""))
                .font(.system(size: 14)).foregroundStyle(ThemeColor.kTextSubtlest)
                .padding(.horizontal, 10).padding(.top, 9).padding(.bottom, 5)
            ForEach(pages) { page in
                Button { app.settingsTab = page.rawValue } label: {
                    HStack(spacing: 8) {
                        Image(page.iconAsset)
                            .renderingMode(.template).resizable().frame(width: 16, height: 16)
                        Text(page.title).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(app.settingsTab == page.rawValue ? ThemeColor.kText : ThemeColor.kTextSubtle)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .frame(minHeight: 32)
                    .background(app.settingsTab == page.rawValue ? ThemeColor.kBackgroundSelected.color(for: scheme) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(SettingsSidebarButtonStyle())
                .accessibilityLabel(page.title)
                .accessibilityAddTraits(app.settingsTab == page.rawValue ? .isSelected : [])
            }
        }
    }
}

/// PlainButtonStyle dims its label while pressed on macOS; keep sidebar items static on click.
private struct SettingsSidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
