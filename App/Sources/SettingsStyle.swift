import AppKit
import SwiftUI
import Theme

enum SettingsPalette {
    static func card(_ scheme: ColorScheme) -> Color {
        // Cards sit on the tinted glass; a strong white fill overwhelms it in light mode.
        scheme == .dark ? ThemeColor.kBackgroundNeutral.color(for: scheme)
            : ThemeColor.kBackground.color(for: scheme, opaque: true).opacity(0.18)
    }
    static func separator(_ scheme: ColorScheme) -> Color {
        ThemeColor.kBorder.color(for: scheme).opacity(scheme == .light ? 0.5 : 1)
    }
    static func surface(_ scheme: ColorScheme, opaque: Bool = false) -> Color {
        ThemeColor.kBackground.color(for: scheme, opaque: true).opacity(opaque ? 1 : 0.7)
    }
    /// Monochrome control accent so switches, focus rings, and prominent controls stay black-and-white.
    static func monochromeTint(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(.sRGB, white: 0.96, opacity: 1)
            : Color(.sRGB, red: 0.11, green: 0.115, blue: 0.13, opacity: 1)
    }
    static func focusBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.55)
    }
}

/// Shared template for every settings page: section headings and quiet inset cards.
struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if #available(macOS 15, *), !SurfaceCompatibility.useMacOS14Compatibility {
                sectionCards
            } else {
                Form { content }
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(ThemeColor.kText)
        .labeledContentStyle(SettingsLabelStyle())
        .textFieldStyle(.roundedBorder)
        .controlSize(.regular)
    }

    @available(macOS 15, *)
    private var sectionCards: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(sections: content) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        if !section.header.isEmpty {
                            section.header
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        VStack(spacing: 0) {
                            ForEach(subviews: section.content) { row in
                                if row.id != section.content.first?.id {
                                    Rectangle().fill(SettingsPalette.separator(scheme))
                                        .frame(height: 1).padding(.horizontal, 16)
                                }
                                row
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                            }
                        }
                        .background(SettingsPalette.card(scheme),
                                    in: RoundedRectangle(cornerRadius: 12))
                        if !section.footer.isEmpty {
                            section.footer.font(.system(size: 12)).foregroundStyle(ThemeColor.kTextSubtlest)
                        }
                    }
                }
            }
            .padding(20).padding(.top, -4)
        }
    }
}

private struct SettingsLabelStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 24) {
            configuration.label
            Spacer(minLength: 24)
            configuration.content
        }
    }
}

extension VerticalAlignment {
    /// Centers trailing controls on a labeled input's field rather than on the label + field stack.
    private enum SettingsInput: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }
    static let settingsInput = VerticalAlignment(SettingsInput.self)
}

/// Single-line fields scroll to keep the caret visible when text overflows.
private let SettingsInputWidth: CGFloat = 260

struct SettingsTextField: View {
    let title: String
    @Binding var text: String
    var prompt: Text? = nil
    init(_ title: String, text: Binding<String>, prompt: Text? = nil) {
        self.title = title; _text = text; self.prompt = prompt
    }
    var body: some View {
        HStack(spacing: 24) {
            Text(title)
            Spacer(minLength: 24)
            SettingsInputField(title, text: $text, prompt: prompt)
                .frame(width: SettingsInputWidth)
        }
    }
}

/// The actual Settings input, reusable without its labeled-row layout or fixed column width.
struct SettingsInputField: View {
    let title: String
    @Binding var text: String
    var prompt: Text?
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    init(_ title: String, text: Binding<String>, prompt: Text? = nil) {
        self.title = title; _text = text; self.prompt = prompt
    }
    var body: some View {
        TextField(title, text: $text,
                  prompt: prompt ?? Text(title).foregroundStyle(ThemeColor.kTextSubtlest)).labelsHidden()
            .textFieldStyle(.plain).focused($focused)
            .settingsInputSurface(scheme: scheme, focused: focused)
            .accessibilityLabel(title)
    }
}

struct SettingsSecureField: View {
    let title: String
    @Binding var text: String
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool
    var prompt: Text? = nil
    init(_ title: String, text: Binding<String>, prompt: Text? = nil) {
        self.title = title; _text = text; self.prompt = prompt
    }
    var body: some View {
        HStack(spacing: 24) {
            Text(title)
            Spacer(minLength: 24)
            SecureField(title, text: $text, prompt: prompt).labelsHidden()
                .textFieldStyle(.plain).focused($focused)
                .settingsInputSurface(scheme: scheme, focused: focused)
                .frame(width: SettingsInputWidth)
        }
    }
}

extension View {
    func settingsInputSurface(scheme: ColorScheme, focused: Bool) -> some View {
        modifier(SettingsInputSurface(scheme: scheme, focused: focused))
    }

    /// Translucent field fill with a focus ring, shared by fields of any height.
    func settingsInputChrome(scheme: ColorScheme, focused: Bool, cornerRadius: CGFloat = 14.5,
                             borderWidth: CGFloat = 1) -> some View {
        modifier(SettingsInputChrome(scheme: scheme, focused: focused, cornerRadius: cornerRadius,
                                     borderWidth: borderWidth))
    }
}

private struct SettingsInputSurface: ViewModifier {
    let scheme: ColorScheme
    let focused: Bool
    @Environment(\.settingsInputHeight) private var height
    @Environment(\.settingsInputCornerRadius) private var cornerRadius
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorSchemeContrast) private var contrast

    private var borderWidth: CGFloat {
        // Capsule Settings fields use a 1px hairline border so their 28pt bright interior
        // matches NSSegmentedControl (.large) while their 29pt outer edge matches NSButton (.glass, .large).
        let isCapsule = cornerRadius >= height / 2 - 0.5
        guard isCapsule, contrast != .increased else { return 1 }
        return max(0.5, 1 / displayScale)
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(height: height)
            .settingsInputChrome(scheme: scheme, focused: focused, cornerRadius: cornerRadius,
                                 borderWidth: borderWidth)
            .alignmentGuide(.settingsInput) { $0[VerticalAlignment.center] }
    }
}

private struct SettingsInputFillKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

private struct SettingsInputHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 29
}

private struct SettingsInputCornerRadiusKey: EnvironmentKey {
    static let defaultValue: CGFloat = 14.5
}

extension EnvironmentValues {
    var settingsInputFill: Color? {
        get { self[SettingsInputFillKey.self] }
        set { self[SettingsInputFillKey.self] = newValue }
    }
    var settingsInputHeight: CGFloat {
        get { self[SettingsInputHeightKey.self] }
        set { self[SettingsInputHeightKey.self] = newValue }
    }
    var settingsInputCornerRadius: CGFloat {
        get { self[SettingsInputCornerRadiusKey.self] }
        set { self[SettingsInputCornerRadiusKey.self] = newValue }
    }
}

private struct SettingsInputChrome: ViewModifier {
    let scheme: ColorScheme
    let focused: Bool
    let cornerRadius: CGFloat
    let borderWidth: CGFloat
    @Environment(\.settingsInputFill) private var fill
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let border = ThemeColor.kBorder.color(for: scheme)
        content.background(fill ?? (scheme == .dark ? ThemeColor.kBackgroundNeutral.color(for: scheme)
                            : SettingsPalette.surface(scheme, opaque: true).opacity(0.45)), in: shape)
            .overlay {
                shape.strokeBorder(focused ? SettingsPalette.focusBorder(scheme) : border,
                                   lineWidth: focused ? 1.5 : borderWidth)
                    .allowsHitTesting(false)
            }
    }
}

struct SettingsBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    private var opaque: Bool { reduceTransparency || contrast == .increased }
    var body: some View {
        if opaque {
            Rectangle().fill(SettingsPalette.surface(scheme, opaque: true))
        } else if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial {
            SettingsRegularGlass(scheme: scheme)
                .overlay(ThemeColor.kBackgroundNeutral.color(for: scheme))
        } else {
            Color.clear.nativeGlassBackground(in: Rectangle())
        }
    }
}

/// Use AppKit's window-aware Regular glass, with the template background as tint.
@available(macOS 26, *)
private struct SettingsRegularGlass: NSViewRepresentable {
    let scheme: ColorScheme
    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.cornerRadius = LauncherLayout.shellCornerRadius
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.tintColor = NSColor(SettingsPalette.surface(scheme, opaque: true)).withAlphaComponent(0.25)
    }
}

enum SettingsMoreMenuItem {
    case action(String, disabled: Bool = false, destructive: Bool = false, () -> Void)
    case divider
}

@MainActor
private final class SettingsMoreMenuTarget: NSObject {
    @objc func invoke(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }
}

@MainActor
private final class SettingsMoreMenuAnchorBox {
    weak var view: NSView?
    var activeTarget: SettingsMoreMenuTarget?
}

private struct SettingsMoreMenuAnchor: NSViewRepresentable {
    let box: SettingsMoreMenuAnchorBox
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }
}

/// Shared icon button for row actions; keeps the native NSMenu and its keyboard behavior
/// while rendering destructive items in the desaturated negative tint.
struct SettingsMoreMenu: View {
    let items: [SettingsMoreMenuItem]
    @State private var hovered = false
    @State private var anchorBox = SettingsMoreMenuAnchorBox()
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: showMenu) {
            Image(nsImage: MingCute.image("ellipsis.vertical", size: 15, canvas: 28))
                .renderingMode(.template)
                .foregroundStyle(ThemeColor.kIconSubtle)
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .contentShape(Capsule())
        .background(SettingsMoreMenuAnchor(box: anchorBox).allowsHitTesting(false))
        .settingsRowHoverFill(hovered && enabled)
        .onHover { hovered = $0 }
    }

    private func showMenu() {
        guard let anchor = anchorBox.view else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let target = SettingsMoreMenuTarget()
        let destructiveColor = NSColor(ThemeColor.kTextNegative.color(for: scheme))
        for item in items {
            switch item {
            case .divider:
                menu.addItem(.separator())
            case .action(let title, let disabled, let destructive, let handler):
                let menuItem = NSMenuItem(title: title,
                                          action: #selector(SettingsMoreMenuTarget.invoke(_:)),
                                          keyEquivalent: "")
                menuItem.target = target
                menuItem.representedObject = handler
                menuItem.isEnabled = !disabled
                if destructive {
                    menuItem.attributedTitle = NSAttributedString(string: title, attributes: [
                        .font: NSFont.menuFont(ofSize: 0),
                        .foregroundColor: disabled ? destructiveColor.withAlphaComponent(0.45) : destructiveColor
                    ])
                }
                menu.addItem(menuItem)
            }
        }
        anchorBox.activeTarget = target
        let origin = NSPoint(x: 0, y: anchor.isFlipped ? anchor.bounds.maxY + 4 : -4)
        menu.popUp(positioning: nil, at: origin, in: anchor)
        anchorBox.activeTarget = nil
    }
}

/// Borderless row action that mirrors `SettingsMoreMenu`'s glyph, hit target and hover fill.
struct SettingsIconButton: View {
    let systemImage: String
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(nsImage: MingCute.image(systemImage, size: 15, canvas: 28))
                .renderingMode(.template)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .frame(width: 28, height: 28)
        .contentShape(Capsule())
        .settingsRowHoverFill(hovered && enabled)
        .onHover { hovered = $0 }
    }
}

private extension View {
    func settingsRowHoverFill(_ visible: Bool) -> some View {
        background {
            Capsule()
                .fill(ThemeColor.kInteractionHover)
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}

/// A native AppKit push button, including the system bezel, focus and disabled states.
struct SettingsButton: View {
    let title: String
    let action: () -> Void
    let role: ButtonRole?
    var systemImage: String?
    var assetImage: String?
    var isLoading: Bool
    var isComplete: Bool
    var loadingTitle: String?
    var isBordered: Bool
    init(_ title: String, role: ButtonRole? = nil, systemImage: String? = nil, assetImage: String? = nil,
         isLoading: Bool = false, isComplete: Bool = false, loadingTitle: String? = nil,
         isBordered: Bool = true, action: @escaping () -> Void) {
        self.title = title; self.role = role; self.systemImage = systemImage; self.assetImage = assetImage; self.action = action
        self.isLoading = isLoading; self.isComplete = isComplete; self.loadingTitle = loadingTitle
        self.isBordered = isBordered
    }
    var body: some View {
        let activeLoadingTitle = (!isComplete && isLoading) ? loadingTitle : nil
        let hidesContent = isComplete || (isLoading && loadingTitle == nil)
        SettingsPushButton(title: title,
                           displayedTitle: hidesContent ? nil : (activeLoadingTitle ?? title),
                           role: role,
                           systemImage: hidesContent || activeLoadingTitle != nil ? nil : systemImage,
                           assetImage: hidesContent || activeLoadingTitle != nil ? nil : assetImage,
                           baseSystemImage: systemImage,
                           baseAssetImage: assetImage,
                           preservesBaseSize: isLoading || isComplete,
                           isBordered: isBordered,
                           action: action)
            .controlSize(.large)
            .fixedSize()
            .overlay {
                Group {
                    if isComplete { Image(mingCute: "checkmark").accessibilityHidden(true) }
                    else if isLoading, loadingTitle == nil {
                        ProgressView().controlSize(.small)
                    }
                }
                .allowsHitTesting(false)
            }
    }
}

private extension NSImage {
    /// Adds transparent trailing space so a leading template image does not sit flush
    /// against the button title; the artwork itself keeps its size and baseline.
    func paddedForTitleGap(_ gap: CGFloat) -> NSImage {
        let contentSize = size
        let padded = NSImage(size: NSSize(width: contentSize.width + gap, height: contentSize.height),
                             flipped: false) { _ in
            self.draw(in: NSRect(origin: .zero, size: contentSize))
            return true
        }
        padded.isTemplate = isTemplate
        return padded
    }
}

private struct SettingsPushButton: NSViewRepresentable {
    let title: String
    let displayedTitle: String?
    let role: ButtonRole?
    let systemImage: String?
    let assetImage: String?
    let baseSystemImage: String?
    let baseAssetImage: String?
    let preservesBaseSize: Bool
    let isBordered: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.press))
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 14)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        applyChrome(to: button)
        applyContent(to: button, title: displayedTitle, systemImage: systemImage, assetImage: assetImage)
        button.isEnabled = enabled
        context.coordinator.action = action
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        let current = nsView.intrinsicContentSize
        var width = current.width
        var height = current.height
        if preservesBaseSize {
            let sizingButton = context.coordinator.sizingButton
            applyChrome(to: sizingButton)
            applyContent(to: sizingButton, title: title, systemImage: baseSystemImage, assetImage: baseAssetImage)
            let base = sizingButton.intrinsicContentSize
            width = max(width, base.width)
            height = max(height, base.height)
        }
        return CGSize(width: width, height: isBordered ? 28 : height)
    }
    private func applyChrome(to button: NSButton) {
        if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial,
           isBordered, !reduceTransparency, contrast != .increased {
            button.bezelStyle = .glass
            button.borderShape = .capsule
        } else {
            button.bezelStyle = .rounded
            if #available(macOS 26, *) { button.borderShape = .automatic }
        }
        button.controlSize = isBordered || controlSize == .large || controlSize == .extraLarge ? .large : .regular
        let destructiveColor = NSColor(ThemeColor.kTextNegative.color(for: scheme))
        button.contentTintColor = role == .destructive ? destructiveColor : nil
        button.isBordered = isBordered
    }
    private func applyContent(to button: NSButton, title: String?, systemImage: String?, assetImage: String?) {
        let text = title ?? ""
        button.title = text
        if text.isEmpty {
            button.attributedTitle = NSAttributedString()
        } else {
            let destructiveColor = NSColor(ThemeColor.kTextNegative.color(for: scheme))
            button.attributedTitle = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: role == .destructive ? destructiveColor :
                    enabled ? NSColor.controlTextColor : NSColor.disabledControlTextColor
            ])
        }
        var leadingImage = systemImage.map { MingCute.image($0, size: text.isEmpty ? 12 : 14) }
        if let assetImage, let image = NSImage(named: assetImage)?.copy() as? NSImage {
            image.size = NSSize(width: 14, height: 14)
            image.isTemplate = true
            leadingImage = image
        }
        // The native gap is only about 2.5 pt, so artwork that fills its canvas reads as
        // touching the title. Pad the image instead of the title to keep labels, tests and
        // accessibility names exact.
        button.image = text.isEmpty ? leadingImage : leadingImage.map { $0.paddedForTitleGap(4) }
        button.imagePosition = button.image == nil ? .noImage : text.isEmpty ? .imageOnly : .imageLeading
    }
    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        lazy var sizingButton: NSButton = {
            let button = NSButton(title: "", target: nil, action: nil)
            button.font = .systemFont(ofSize: 14)
            return button
        }()
        init(action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
}

struct SettingsCheckbox: NSViewRepresentable {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var enabled

    func makeCoordinator() -> Coordinator { Coordinator(isOn: $isOn) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: context.coordinator,
                              action: #selector(Coordinator.toggle(_:)))
        button.font = .systemFont(ofSize: 14)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.isOn = $isOn
        button.title = title
        button.state = isOn ? .on : .off
        button.isEnabled = enabled
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
    final class Coordinator: NSObject {
        var isOn: Binding<Bool>
        init(isOn: Binding<Bool>) { self.isOn = isOn }
        @objc func toggle(_ sender: NSButton) { isOn.wrappedValue = sender.state == .on }
    }
}

/// Native capsule tabs with a neutral selection, shared by commands and plugins.
struct SettingsSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    var identifier: String = ""
    var accessibilityLabel: String = ""

    var body: some View {
        SettingsNativeSegmentedControl(selection: $selection, options: options,
                                       identifier: identifier, accessibilityLabel: accessibilityLabel)
            .controlSize(.large)
    }
}

private struct SettingsNativeSegmentedControl<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    let options: [(Value, String)]
    var identifier: String = ""
    var accessibilityLabel: String = ""
    @Environment(\.isEnabled) private var enabled

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.trackingMode = .selectOne
        control.segmentStyle = .capsule
        control.selectedSegmentBezelColor = .controlColor
        control.target = context.coordinator
        control.action = #selector(Coordinator.select(_:))
        return control
    }
    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.values = options.map(\.0)
        control.controlSize = .large
        control.font = .systemFont(ofSize: 14)
        control.segmentCount = options.count
        for (index, option) in options.enumerated() {
            control.setLabel(option.1, forSegment: index)
        }
        control.selectedSegment = options.firstIndex { $0.0 == selection } ?? -1
        control.isEnabled = enabled
        control.setAccessibilityIdentifier(identifier)
        control.setAccessibilityLabel(accessibilityLabel)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    final class Coordinator: NSObject {
        var selection: Binding<Value>
        var values: [Value] = []
        init(selection: Binding<Value>) { self.selection = selection }
        @objc func select(_ sender: NSSegmentedControl) {
            guard values.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = values[sender.selectedSegment]
        }
    }
}

/// Liquid Glass select button that morphs in place into an AI-chat-styled floating menu.
struct SettingsChoice<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    var images: [Value: NSImage] = [:]
    @State private var anchorBox = SettingsChoiceAnchorBox()
    @State private var activeSessionID: UUID?
    @State private var isPresenting = false
    @Environment(\.isEnabled) private var enabled

    private var selectedIndex: Int {
        options.firstIndex(where: { $0.0 == selection }) ?? (options.isEmpty ? -1 : 0)
    }

    private var selectedOption: (Value, String)? {
        options.indices.contains(selectedIndex) ? options[selectedIndex] : nil
    }

    private var selectedTitle: String {
        selectedOption?.1 ?? ""
    }

    private var selectedImage: NSImage? {
        selectedOption.flatMap { images[$0.0] }
    }

    var body: some View {
        Button(action: openMenu) {
            SettingsChoiceTriggerLabel(
                title: selectedTitle,
                image: selectedImage,
                enabled: enabled
            )
        }
        .buttonStyle(SettingsChoiceTriggerButtonStyle())
        .opacity(isPresenting ? 0 : 1)
        .allowsHitTesting(!isPresenting)
        .background(
            SettingsChoiceAnchorReader(
                box: anchorBox,
                titles: options.map(\.1),
                selectedIndex: selectedIndex,
                isMenuOpen: isPresenting,
                onOpen: openMenu,
                onSelect: selectOption(at:),
                onClose: closeMenu
            )
            .allowsHitTesting(false)
        )
        .accessibilityValue(selectedTitle)
        .accessibilityIdentifier("settings-choice-trigger")
        .onDisappear {
            if let activeSessionID {
                SettingsChoicePresenter.shared.dismiss(sessionID: activeSessionID, animated: false)
            }
            activeSessionID = nil
            isPresenting = false
        }
    }

    private func openMenu() {
        guard enabled, !options.isEmpty, let anchor = anchorBox.view else { return }
        let items = options.enumerated().map { index, option in
            SettingsChoiceOption(id: index, title: option.1, image: images[option.0])
        }
        activeSessionID = SettingsChoicePresenter.shared.present(
            from: anchor,
            options: items,
            selectedIndex: selectedIndex,
            onSelect: { index in
                selectOption(at: index)
            },
            onOpenChanged: { open in
                isPresenting = open
                if !open { activeSessionID = nil }
            }
        )
    }

    private func selectOption(at index: Int) {
        guard options.indices.contains(index) else { return }
        selection = options[index].0
    }

    private func closeMenu() {
        if let activeSessionID {
            SettingsChoicePresenter.shared.dismiss(sessionID: activeSessionID, animated: true)
        }
    }
}


/// A native radio group: its own AppKit container isolates selection and keyboard navigation.
struct SettingsRadioGroup: NSViewRepresentable {
    let label: String
    let options: [String]
    @Binding var selection: String

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> RadioStack {
        let stack = RadioStack()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setAccessibilityElement(true)
        stack.setAccessibilityRole(.radioGroup)
        return stack
    }
    func updateNSView(_ stack: RadioStack, context: Context) {
        context.coordinator.selection = $selection
        if stack.options != options {
            stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
            stack.options = options
            stack.heights = []
            for option in options {
                let button = NSButton(radioButtonWithTitle: option, target: context.coordinator, action: #selector(Coordinator.choose(_:)))
                button.setAccessibilityRole(.radioButton)
                button.setAccessibilityLabel(option)
                button.font = .systemFont(ofSize: 14)
                button.cell?.wraps = true
                button.cell?.usesSingleLineMode = false
                button.cell?.lineBreakMode = .byWordWrapping
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                stack.addArrangedSubview(button)
                button.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
                let height = button.heightAnchor.constraint(equalToConstant: 18)
                height.isActive = true
                stack.heights.append(height)
            }
        }
        stack.setAccessibilityLabel(label)
        for case let button as NSButton in stack.arrangedSubviews {
            button.state = button.title == selection ? .on : .off
            button.isEnabled = context.environment.isEnabled
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RadioStack, context: Context) -> CGSize? {
        nsView.measure(width: proposal.width)
    }

    @MainActor final class RadioStack: NSStackView {
        var options: [String] = []
        var heights: [NSLayoutConstraint] = []
        func measure(width: CGFloat?) -> CGSize {
            let buttons = arrangedSubviews.compactMap { $0 as? NSButton }
            let ideal = buttons.map { $0.cell?.cellSize.width ?? 0 }.max() ?? 0
            let width = min(ideal, width ?? ideal)
            var height: CGFloat = 0
            for (index, button) in buttons.enumerated() {
                let measured = button.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10000)).height ?? 18
                let rowHeight = ceil(max(18, measured))
                heights[index].constant = rowHeight
                height += rowHeight
            }
            return CGSize(width: width, height: height + CGFloat(max(0, buttons.count - 1)) * spacing)
        }
    }
    @MainActor final class Coordinator: NSObject {
        var selection: Binding<String> = .constant("")
        @objc func choose(_ sender: NSButton) { selection.wrappedValue = sender.title }
    }
}

private final class SettingsPromptTextView: NSTextView {
    var focusChanged: (Bool) -> Void = { _ in }
    var placeholder: String = "" { didSet { if oldValue != placeholder { needsDisplay = true } } }
    var placeholderColor: NSColor = .placeholderTextColor { didSet { if oldValue != placeholderColor { needsDisplay = true } } }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusChanged(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { focusChanged(false) }
        return accepted
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), !placeholder.isEmpty else { return }
        let padding = textContainer?.lineFragmentPadding ?? 0
        let origin = textContainerOrigin
        let insetWidth = (textContainer?.containerSize.width ?? bounds.width) - padding * 2
        let rect = NSRect(x: origin.x + padding,
                          y: origin.y,
                          width: max(0, insetWidth),
                          height: max(0, bounds.height - origin.y * 2))
        let paragraph = (defaultParagraphStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: placeholderColor,
            .paragraphStyle: paragraph
        ]
        (placeholder as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }
}

/// Hosts the expanding prompt editor without scrolling itself; wheel events go to the Settings page.
final class SettingsPassthroughScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

/// Multi-line plain-text editor sharing the Settings translucent input surface.
struct SettingsMultilineTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String = ""
    var accessibilityLabel: String
    var accessibilityIdentifier: String = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var enabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Shortest editor height; taller content expands the editor instead of scrolling inside it.
    var minHeight: CGFloat = 120

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = SettingsPassthroughScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true

        let editor = SettingsPromptTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        editor.importsGraphics = false
        editor.drawsBackground = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.textContainerInset = NSSize(width: 8, height: 10)
        editor.textContainer?.lineFragmentPadding = 4
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.focusChanged = { [weak coordinator = context.coordinator] focused in
            DispatchQueue.main.async { coordinator?.parent.isFocused = focused }
        }
        editor.setAccessibilityLabel(accessibilityLabel)
        if !accessibilityIdentifier.isEmpty {
            editor.setAccessibilityIdentifier(accessibilityIdentifier)
        }

        scroll.documentView = editor
        context.coordinator.editor = editor
        context.coordinator.lastColorScheme = colorScheme
        applyStyling(to: editor, replacingText: true, refreshStorageAttributes: true)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? SettingsPromptTextView else { return }
        context.coordinator.parent = self
        editor.isEditable = enabled
        editor.setAccessibilityLabel(accessibilityLabel)
        if !accessibilityIdentifier.isEmpty {
            editor.setAccessibilityIdentifier(accessibilityIdentifier)
        }
        let width = scroll.contentSize.width
        let height = scroll.contentSize.height
        if height > 0 {
            editor.minSize = NSSize(width: 0, height: height)
        }
        if width > 0, abs(editor.frame.width - width) > 0.5 {
            editor.setFrameSize(NSSize(width: width, height: max(height, editor.frame.height)))
        }
        let shouldReplace = editor.string != text && !editor.hasMarkedText()
        let schemeChanged = context.coordinator.lastColorScheme != colorScheme
        if schemeChanged { context.coordinator.lastColorScheme = colorScheme }
        applyStyling(to: editor, replacingText: shouldReplace,
                     refreshStorageAttributes: shouldReplace || (schemeChanged && !editor.hasMarkedText()))
    }

    /// Sizes the editor to its full text height so the surrounding Settings page owns scrolling.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        guard let editor = scroll.documentView as? SettingsPromptTextView,
              let container = editor.textContainer,
              let layout = editor.layoutManager else { return nil }
        let width = proposal.width ?? scroll.frame.width
        guard width.isFinite, width > 0 else { return nil }
        if editor.string != text, !editor.hasMarkedText() {
            applyStyling(to: editor, replacingText: true, refreshStorageAttributes: true)
        }
        let inset = editor.textContainerInset
        container.containerSize = NSSize(width: max(width - inset.width * 2, 1),
                                         height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let contentHeight = ceil(layout.usedRect(for: container).height + inset.height * 2)
        return CGSize(width: width, height: max(minHeight, contentHeight))
    }

    private func applyStyling(to editor: SettingsPromptTextView, replacingText: Bool, refreshStorageAttributes: Bool) {
        let font = NSFont.systemFont(ofSize: 14)
        let color = NSColor(ThemeColor.kText.color(for: colorScheme))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 6
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        editor.font = font
        editor.textColor = color
        editor.insertionPointColor = color
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = attributes
        editor.placeholder = placeholder
        editor.placeholderColor = NSColor(ThemeColor.kTextSubtlest.color(for: colorScheme))
        editor.setAccessibilityPlaceholderValue(placeholder.isEmpty ? nil : placeholder)

        if replacingText {
            editor.string = text
        }
        if refreshStorageAttributes, let storage = editor.textStorage, storage.length > 0 {
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttributes(attributes, range: fullRange)
            storage.endEditing()
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SettingsMultilineTextEditor
        weak var editor: NSTextView?
        var lastColorScheme: ColorScheme?
        init(_ parent: SettingsMultilineTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor else { return }
            parent.text = editor.string
            // Once SwiftUI has grown the editor, keep the caret visible in the outer Settings scroll.
            DispatchQueue.main.async { [weak editor] in
                guard let editor else { return }
                editor.scrollRangeToVisible(editor.selectedRange())
            }
        }
    }
}
