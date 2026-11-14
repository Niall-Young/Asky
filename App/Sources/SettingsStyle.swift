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
        padding(.horizontal, 12).frame(height: 28)
            .settingsInputChrome(scheme: scheme, focused: focused)
            .alignmentGuide(.settingsInput) { $0[VerticalAlignment.center] }
    }

    /// Translucent field fill with a focus ring, shared by fields of any height.
    func settingsInputChrome(scheme: ColorScheme, focused: Bool, cornerRadius: CGFloat = 14) -> some View {
        modifier(SettingsInputChrome(scheme: scheme, focused: focused, cornerRadius: cornerRadius))
    }
}

private struct SettingsInputFillKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var settingsInputFill: Color? {
        get { self[SettingsInputFillKey.self] }
        set { self[SettingsInputFillKey.self] = newValue }
    }
}

private struct SettingsInputChrome: ViewModifier {
    let scheme: ColorScheme
    let focused: Bool
    let cornerRadius: CGFloat
    @Environment(\.settingsInputFill) private var fill
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let border = ThemeColor.kBorder.color(for: scheme)
        content.background(fill ?? (scheme == .dark ? ThemeColor.kBackgroundNeutral.color(for: scheme)
                            : SettingsPalette.surface(scheme, opaque: true).opacity(0.45)), in: shape)
            .overlay {
                shape.strokeBorder(focused ? Color.accentColor : border,
                                   lineWidth: focused ? 2 : 1)
                    .allowsHitTesting(false)
            }
    }
}

struct SettingsBackdrop: View {
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    private var opaque: Bool { reduceTransparency || contrast == .increased }
    var body: some View {
        if opaque {
            Rectangle().fill(SettingsPalette.surface(scheme, opaque: true))
        } else if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial {
            SettingsRegularGlass(scheme: scheme, inactive: activeState == .inactive)
                .overlay(ThemeColor.kBackgroundNeutral.color(for: scheme).opacity(activeState == .inactive ? 0.5 : 1))
        } else {
            Color.clear.nativeGlassBackground(in: Rectangle())
        }
    }
}

/// Use AppKit's window-aware Regular glass, with the template background as tint.
@available(macOS 26, *)
private struct SettingsRegularGlass: NSViewRepresentable {
    let scheme: ColorScheme
    let inactive: Bool
    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.cornerRadius = LauncherLayout.shellCornerRadius
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.tintColor = NSColor(SettingsPalette.surface(scheme, opaque: true)).withAlphaComponent(inactive ? 0.55 : 0.25)
    }
}

/// Shared icon button for row actions; keeps the native menu and its keyboard behavior.
struct SettingsMoreMenu<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Menu {
            content
        } label: {
            // Pad the glyph into the hit target itself; the borderless menu only accepts
            // clicks on the label's image, not on a surrounding frame.
            Image(nsImage: MingCute.image("ellipsis.vertical", size: 15, canvas: 28))
                .renderingMode(.template)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 28, height: 28)
        .contentShape(Capsule())
        .settingsRowHoverFill(hovered && enabled)
        .onHover { hovered = $0 }
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
        SettingsPushButton(title: title, role: role, systemImage: systemImage, assetImage: assetImage,
                           hidesTitle: isLoading || isComplete, isBordered: isBordered, action: action)
            .fixedSize()
            .overlay {
                if isComplete { Image(mingCute: "checkmark").accessibilityHidden(true) }
                else if isLoading {
                    if let loadingTitle { Text(loadingTitle).font(.system(size: 14)) }
                    else { ProgressView().controlSize(.small) }
                }
            }
    }
}

private struct SettingsPushButton: NSViewRepresentable {
    let title: String
    let role: ButtonRole?
    let systemImage: String?
    let assetImage: String?
    let hidesTitle: Bool
    let isBordered: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.press))
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 14)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        if #available(macOS 26, *), !SurfaceCompatibility.useLegacyMaterial,
           isBordered, !reduceTransparency, contrast != .increased {
            button.bezelStyle = .glass
            button.borderShape = .capsule
        } else {
            button.bezelStyle = .rounded
            if #available(macOS 26, *) { button.borderShape = .automatic }
        }
        button.title = title
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: hidesTitle ? NSColor.clear : role == .destructive ? NSColor.systemRed :
                enabled ? NSColor.controlTextColor : NSColor.disabledControlTextColor
        ])
        button.controlSize = controlSize == .large || controlSize == .extraLarge ? .large : .regular
        button.image = systemImage.map { MingCute.image($0, size: title.isEmpty ? 12 : 14) }
        if let assetImage, let image = NSImage(named: assetImage)?.copy() as? NSImage {
            image.size = NSSize(width: 14, height: 14)
            image.isTemplate = true
            button.image = image
        }
        button.imagePosition = button.image == nil ? .noImage : title.isEmpty ? .imageOnly : .imageLeading
        button.contentTintColor = role == .destructive ? .systemRed : nil
        button.isBordered = isBordered
        button.isEnabled = enabled
        context.coordinator.action = action
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
    final class Coordinator: NSObject {
        var action: () -> Void
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
struct SettingsSegmentedControl<Value: Hashable>: NSViewRepresentable {
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

/// Choices and text inputs share one surface, including when composited over bright glass.
struct SettingsChoice<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    var images: [Value: NSImage] = [:]
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    var body: some View {
        SettingsChoiceControl(selection: $selection, options: options, images: images)
            .focused($focused)
            .settingsInputSurface(scheme: scheme, focused: focused)
    }
}

private struct SettingsChoiceControl<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    let options: [(Value, String)]
    var images: [Value: NSImage] = [:]
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection, options: options) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.focusRingType = .none
        button.font = .systemFont(ofSize: 14)
        button.target = context.coordinator
        button.action = #selector(Coordinator.select(_:))
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.options = options
        button.isEnabled = enabled
        if button.itemTitles != options.map({ $0.1 }) {
            button.removeAllItems(); button.addItems(withTitles: options.map { $0.1 })
        }
        for (index, option) in options.enumerated() {
            button.item(at: index)?.image = images[option.0].map { image in
                let thumbnail = (image.copy() as? NSImage) ?? image
                thumbnail.size = NSSize(width: 16, height: 16)
                return thumbnail
            }
        }
        if let index = options.firstIndex(where: { $0.0 == selection }) { button.selectItem(at: index) }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        let ideal = nsView.intrinsicContentSize
        return CGSize(width: min(ideal.width, proposal.width ?? ideal.width), height: ideal.height)
    }
    final class Coordinator: NSObject {
        var selection: Binding<Value>
        var options: [(Value, String)]
        init(selection: Binding<Value>, options: [(Value, String)]) { self.selection = selection; self.options = options }
        @objc func select(_ sender: NSPopUpButton) {
            guard options.indices.contains(sender.indexOfSelectedItem) else { return }
            selection.wrappedValue = options[sender.indexOfSelectedItem].0
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
