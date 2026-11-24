import AppKit
import SwiftUI
import Theme

enum ChatFormMetrics {
    static let controlHeight: CGFloat = 34
    static let controlCornerRadius: CGFloat = 10
    static let optionMinHeight: CGFloat = 38
    static let optionCornerRadius: CGFloat = 10
    static let optionSpacing: CGFloat = 8
    static let fieldSpacing: CGFloat = 16
}

struct ChatReplyView: View {
    let text: String
    var isStreaming = false
    var values: Binding<[String: [String]]> = .constant([:])
    var active = false
    var submit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(ChatFormParser.parse(text, streaming: isStreaming)) { part in
                switch part.content {
                case .markdown(let text): ChatMarkdownView(text: text).equatable()
                case .form(let form):
                    if !isStreaming { ChatFormView(form: form, values: values, active: active, submit: submit) }
                }
            }
        }
    }
}

struct ChatFormView: View {
    let form: ChatForm
    @Binding var values: [String: [String]]
    let active: Bool
    let submit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ChatFormMetrics.fieldSpacing) {
            Text(form.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ThemeColor.kText)
            ForEach(form.fields) { field in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text(field.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ThemeColor.kTextSubtle)
                        if field.required == true {
                            Text(verbatim: "*")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ThemeColor.kTextSubtlest)
                                .accessibilityLabel(NSLocalizedString("必填", comment: ""))
                        }
                    }
                    control(field)
                }
            }
            if !form.isComplete {
                Text(NSLocalizedString("表单未生成完整，请在输入框回复。", comment: ""))
                    .font(.system(size: 12))
                    .foregroundStyle(ThemeColor.kTextSubtle)
            } else {
                SettingsButton(NSLocalizedString("提交回复", comment: ""), action: submit)
                    .disabled(!active || !form.accepts(values))
                    .padding(.top, 2)
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(ThemeColor.kText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.settingsInputHeight, ChatFormMetrics.controlHeight)
        .environment(\.settingsInputCornerRadius, ChatFormMetrics.controlCornerRadius)
    }

    @ViewBuilder private func control(_ field: ChatForm.Field) -> some View {
        switch field.type {
        case .text:
            SettingsInputField(field.label, text: scalar(field.id))
                .disabled(!active)
        case .select:
            if field.allowsCustomAnswer {
                ChatCustomChoice(field: field, answer: scalar(field.id), active: active)
            } else {
                SettingsChoice(selection: scalar(field.id), options:
                    [("", NSLocalizedString("请选择", comment: ""))] + (field.options ?? []).map { ($0, $0) })
                    .accessibilityLabel(field.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .disabled(!active)
            }
        case .radio:
            if field.allowsCustomAnswer {
                ChatCustomChoice(field: field, answer: scalar(field.id), active: active)
            } else {
                ChatFormRadioGroup(label: field.label, options: field.options ?? [], selection: scalar(field.id), active: active)
            }
        case .multi:
            ChatFormMultiGroup(label: field.label, options: field.options ?? [], selection: multiBinding(field.id), active: active)
        case .time, .duration:
            if !active, values[field.id] == nil {
                Text(verbatim: "—").foregroundStyle(ThemeColor.kTextSubtle)
            } else {
                ChatFormTemporalField(field: field, value: scalar(field.id), active: active)
                    .onChange(of: active, initial: true) {
                        if active, values[field.id] == nil {
                            values[field.id] = [field.temporalString(field.initialTemporalValues())]
                        }
                    }
            }
        case .date:
            if !active, values[field.id] == nil {
                Text(verbatim: "—").foregroundStyle(ThemeColor.kTextSubtle)
            } else {
                ChatFormDateField(field: field, value: scalar(field.id), active: active)
                    .onChange(of: active, initial: true) {
                        if active, values[field.id] == nil {
                            values[field.id] = [ChatForm.dateString(Date())]
                        }
                    }
            }
        }
    }

    private func scalar(_ id: String) -> Binding<String> {
        Binding(get: { values[id]?.first ?? "" }, set: { values[id] = [String($0.prefix(4000))] })
    }

    private func multiBinding(_ id: String) -> Binding<[String]> {
        Binding(get: { values[id] ?? [] }, set: { values[id] = $0 })
    }
}

// MARK: - Button-style Single & Multi Choice

private struct ChatFormRadioGroup: View {
    let label: String
    let options: [String]
    @Binding var selection: String
    let active: Bool

    var body: some View {
        let hasSelection = !selection.isEmpty
        VStack(alignment: .leading, spacing: ChatFormMetrics.optionSpacing) {
            ForEach(options, id: \.self) { option in
                let selected = selection == option
                ChatFormOptionRow(
                    title: option,
                    selected: selected,
                    dimmed: hasSelection && !selected,
                    active: active,
                    mode: .single
                ) {
                    guard active else { return }
                    selection = option
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

private struct ChatFormMultiGroup: View {
    let label: String
    let options: [String]
    @Binding var selection: [String]
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ChatFormMetrics.optionSpacing) {
            ForEach(options, id: \.self) { option in
                let selected = selection.contains(option)
                ChatFormOptionRow(
                    title: option,
                    selected: selected,
                    dimmed: false,
                    active: active,
                    mode: .multiple
                ) {
                    guard active else { return }
                    var updated = selection
                    if selected {
                        updated.removeAll { $0 == option }
                    } else {
                        updated.append(option)
                    }
                    selection = updated
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

private struct ChatFormOptionRow: View {
    enum Mode { case single, multiple }

    let title: String
    let selected: Bool
    let dimmed: Bool
    let active: Bool
    let mode: Mode
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ChatFormMetrics.optionCornerRadius, style: .continuous)
    }

    private var backgroundFill: Color {
        if selected {
            return scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.72)
        }
        if hovered && active {
            return scheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.48)
        }
        return scheme == .dark ? Color.white.opacity(0.02) : Color.white.opacity(0.24)
    }

    private var selectedBorderColor: Color {
        let boost: Double = contrast == .increased ? 0.12 : 0
        return scheme == .dark
            ? Color.white.opacity(min(1, 0.84 + boost))
            : Color.black.opacity(min(1, 0.76 + boost))
    }

    private var unselectedBorderColor: Color {
        let boost: Double = contrast == .increased ? 0.16 : 0
        let base: Double
        if hovered && active {
            base = scheme == .dark ? 0.28 : 0.26
        } else if dimmed || !active {
            base = scheme == .dark ? 0.11 : 0.10
        } else {
            base = scheme == .dark ? 0.17 : 0.16
        }
        return (scheme == .dark ? Color.white : Color.black).opacity(min(1, base + boost))
    }

    private var textColor: Color {
        if selected || (hovered && active) {
            return ThemeColor.kText.color(for: scheme)
        }
        if !active {
            return ThemeColor("textDisabled").color(for: scheme)
        }
        if dimmed {
            return ThemeColor.kTextSubtle.color(for: scheme)
        }
        return ThemeColor.kText.color(for: scheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.system(size: 14, weight: selected ? .medium : .regular))
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                trailingIndicator
                    .frame(width: 18, height: 18)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: ChatFormMetrics.optionMinHeight, alignment: .leading)
            .background(backgroundFill, in: shape)
            .overlay {
                if selected {
                    shape.strokeBorder(selectedBorderColor, lineWidth: 1.5)
                        .allowsHitTesting(false)
                } else {
                    shape.strokeBorder(unselectedBorderColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(ChatFormOptionButtonStyle(active: active, reduceMotion: reduceMotion))
        .disabled(!active)
        .opacity(!active && !selected ? 0.58 : 1)
        .onHover { hovered = $0 }
        .background(ChatFormControlMarker(id: "chat-form-option-" + title))
        .actionArrowCursor(enabled: active)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: selected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: hovered)
        .accessibilityLabel(title)
        .accessibilityIdentifier("chat-form-option-" + title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var trailingIndicator: some View {
        switch mode {
        case .single:
            if selected {
                ZStack {
                    Circle().fill(ThemeColor.kBackgroundPrimary.color(for: scheme))
                    Image(mingCute: "checkmark", size: 10)
                        .foregroundStyle(ThemeColor("textInverted").color(for: scheme))
                }
                .transition(reduceMotion ? .opacity : .scale(scale: 0.82).combined(with: .opacity))
            } else {
                Color.clear
            }
        case .multiple:
            let box = RoundedRectangle(cornerRadius: 5, style: .continuous)
            ZStack {
                if selected {
                    box.fill(ThemeColor.kBackgroundPrimary.color(for: scheme))
                    Image(mingCute: "checkmark", size: 10.5)
                        .foregroundStyle(ThemeColor("textInverted").color(for: scheme))
                } else {
                    box.fill(scheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.55))
                    box.strokeBorder(
                        (scheme == .dark ? Color.white : Color.black).opacity(hovered && active ? 0.48 : 0.26),
                        lineWidth: 1.25
                    )
                }
            }
        }
    }
}

private struct ChatFormOptionButtonStyle: ButtonStyle {
    let active: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = active && configuration.isPressed
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? 0.992 : 1)
            .opacity(pressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: pressed)
    }
}

// MARK: - Custom Choice (Radio / Select with allowCustom)

/// Keeps the custom draft while switching choices; only the active answer is submitted.
private struct ChatCustomChoice: View {
    let field: ChatForm.Field
    @Binding var answer: String
    let active: Bool
    @State private var usingCustom: Bool
    @State private var customDraft: String

    init(field: ChatForm.Field, answer: Binding<String>, active: Bool) {
        self.field = field
        _answer = answer
        self.active = active
        let custom = !answer.wrappedValue.isEmpty && !(field.options ?? []).contains(answer.wrappedValue)
        _usingCustom = State(initialValue: custom)
        _customDraft = State(initialValue: custom ? answer.wrappedValue : "")
    }

    private var customOption: String {
        var label = NSLocalizedString("自己填写", comment: "")
        while (field.options ?? []).contains(label) { label += "…" }
        return label
    }

    private var selection: Binding<String> {
        Binding(get: { usingCustom ? customOption : answer }, set: { value in
            usingCustom = value == customOption
            answer = usingCustom ? customDraft : value
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if field.type == .radio {
                ChatFormRadioGroup(label: field.label, options: (field.options ?? []) + [customOption], selection: selection, active: active)
            } else {
                SettingsChoice(selection: selection, options:
                    [("", NSLocalizedString("请选择", comment: ""))] + ((field.options ?? []) + [customOption]).map { ($0, $0) })
                    .accessibilityLabel(field.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .disabled(!active)
            }
            if usingCustom {
                SettingsInputField(NSLocalizedString("输入你的回答", comment: ""), text: Binding(get: { customDraft }, set: {
                    customDraft = String($0.prefix(4000))
                    answer = customDraft
                }))
                .disabled(!active)
            }
        }
    }
}

// MARK: - Date Field (Input + Calendar Popover Button)

private struct ChatFormDateField: View {
    let field: ChatForm.Field
    @Binding var value: String
    let active: Bool

    @State private var draftText: String
    @State private var showingPopover = false
    @FocusState private var inputFocused: Bool
    @Environment(\.colorScheme) private var scheme

    init(field: ChatForm.Field, value: Binding<String>, active: Bool) {
        self.field = field
        _value = value
        self.active = active
        let initial = value.wrappedValue.isEmpty ? ChatForm.dateString(Date()) : value.wrappedValue
        _draftText = State(initialValue: initial)
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { ChatForm.date(value) ?? Date() },
            set: { date in
                let formatted = ChatForm.dateString(date)
                value = formatted
                draftText = formatted
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("YYYY-MM-DD", text: $draftText,
                      prompt: Text(verbatim: "YYYY-MM-DD").foregroundStyle(ThemeColor.kTextSubtlest))
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.system(size: 14).monospacedDigit())
                .focused($inputFocused)
                .disabled(!active)
                .onSubmit { commitDraft() }
                .onChange(of: inputFocused) { _, focused in
                    if !focused { commitDraft() }
                }
                .onChange(of: draftText) { _, newValue in
                    guard active, let parsed = ChatForm.parseDateInput(newValue) else { return }
                    let formatted = ChatForm.dateString(parsed)
                    if value != formatted { value = formatted }
                }
                .onChange(of: value) { _, newValue in
                    if !newValue.isEmpty, (!inputFocused || ChatForm.parseDateInput(draftText).map(ChatForm.dateString) != newValue) {
                        draftText = newValue
                    }
                }
                .onChange(of: active) { _, isActive in
                    if !isActive { showingPopover = false }
                }
                .settingsInputSurface(scheme: scheme, focused: inputFocused)
                .background(ChatFormControlMarker(id: "chat-form-field-" + field.id))
                .accessibilityLabel(field.label)
                .accessibilityIdentifier("chat-form-field-" + field.id)

            ChatFormPickerTriggerButton(
                isOpen: showingPopover,
                enabled: active,
                accessibilityLabel: NSLocalizedString("选择日期", comment: ""),
                accessibilityIdentifier: "chat-form-picker-" + field.id
            ) {
                commitDraft()
                inputFocused = false
                showingPopover.toggle()
            } icon: {
                Image(mingCute: "calendar", size: 15)
            }
            .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
                ChatFormDatePopover(selection: dateBinding, dismiss: { showingPopover = false })
            }
        }
    }

    private func commitDraft() {
        if let parsed = ChatForm.parseDateInput(draftText) {
            let formatted = ChatForm.dateString(parsed)
            value = formatted
            draftText = formatted
        } else {
            draftText = value.isEmpty ? ChatForm.dateString(Date()) : value
        }
    }
}

struct ChatFormDatePopover: View {
    @Binding var selection: Date
    let dismiss: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 12) {
            CalendarMonthPicker(selection: $selection, monochrome: true)
            Rectangle()
                .fill(ThemeColor.kBorder.color(for: scheme))
                .frame(height: 1)
            HStack {
                ChatFormPopoverGhostButton(title: NSLocalizedString("今天", comment: "")) {
                    selection = Date()
                }
                Spacer(minLength: 0)
                ChatFormPopoverPrimaryButton(title: NSLocalizedString("完成", comment: ""), action: dismiss)
            }
        }
        .padding(14)
        .frame(width: 276)
        .fixedSize()
    }
}

// MARK: - Time & Duration Field (Input + Popover Picker Button)

private struct ChatFormTemporalField: View {
    let field: ChatForm.Field
    @Binding var value: String
    let active: Bool

    @State private var draftText: String
    @State private var showingPopover = false
    @FocusState private var inputFocused: Bool
    @Environment(\.colorScheme) private var scheme

    init(field: ChatForm.Field, value: Binding<String>, active: Bool) {
        self.field = field
        _value = value
        self.active = active
        let initial = value.wrappedValue.isEmpty
            ? field.temporalString(field.initialTemporalValues())
            : value.wrappedValue
        _draftText = State(initialValue: initial)
    }

    private var temporalBinding: Binding<[Int]> {
        Binding(
            get: { field.temporalValues(value) ?? field.initialTemporalValues() },
            set: { numbers in
                let formatted = field.temporalString(numbers)
                value = formatted
                draftText = formatted
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField(field.temporalPlaceholder, text: $draftText,
                          prompt: Text(verbatim: field.temporalPlaceholder).foregroundStyle(ThemeColor.kTextSubtlest))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.system(size: 14).monospacedDigit())
                    .focused($inputFocused)
                    .disabled(!active)
                    .onSubmit { commitDraft() }
                    .onChange(of: inputFocused) { _, focused in
                        if !focused { commitDraft() }
                    }
                    .onChange(of: draftText) { _, newValue in
                        guard active, let parsed = field.parseTemporalInput(newValue) else { return }
                        let formatted = field.temporalString(parsed)
                        if value != formatted { value = formatted }
                    }
                    .onChange(of: value) { _, newValue in
                        if !newValue.isEmpty, (!inputFocused || field.parseTemporalInput(draftText).map(field.temporalString) != newValue) {
                            draftText = newValue
                        }
                    }
                    .onChange(of: active) { _, isActive in
                        if !isActive { showingPopover = false }
                    }
                    .accessibilityLabel(field.label)
                    .accessibilityIdentifier("chat-form-field-" + field.id)

                if field.type == .duration, field.timeUnits.count == 1, let unit = field.timeUnits.first {
                    Text(NSLocalizedString(unit.label, comment: ""))
                        .font(.system(size: 12))
                        .foregroundStyle(ThemeColor.kTextSubtlest)
                        .allowsHitTesting(false)
                }
            }
            .settingsInputSurface(scheme: scheme, focused: inputFocused)
            .background(ChatFormControlMarker(id: "chat-form-field-" + field.id))

            ChatFormPickerTriggerButton(
                isOpen: showingPopover,
                enabled: active,
                accessibilityLabel: NSLocalizedString(field.type == .duration ? "选择时长" : "选择时间", comment: ""),
                accessibilityIdentifier: "chat-form-picker-" + field.id
            ) {
                commitDraft()
                inputFocused = false
                showingPopover.toggle()
            } icon: {
                ChatFormClockGlyph(size: 15)
            }
            .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
                ChatFormTemporalPopover(field: field, values: temporalBinding, dismiss: { showingPopover = false })
            }
        }
    }

    private func commitDraft() {
        if let parsed = field.parseTemporalInput(draftText) {
            let formatted = field.temporalString(parsed)
            value = formatted
            draftText = formatted
        } else {
            draftText = value.isEmpty ? field.temporalString(field.initialTemporalValues()) : value
        }
    }
}

struct ChatFormTemporalPopover: View {
    let field: ChatForm.Field
    @Binding var values: [Int]
    let dismiss: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var popoverWidth: CGFloat {
        switch field.timeUnits.count {
        case 1: 136
        case 2: 196
        default: 260
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(field.temporalString(normalizedValues))
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(ThemeColor.kText)
                Spacer(minLength: 0)
                ChatFormPopoverGhostButton(
                    title: NSLocalizedString(field.type == .duration ? "归零" : "现在", comment: "")
                ) {
                    values = field.initialTemporalValues()
                }
            }

            Rectangle()
                .fill(ThemeColor.kBorder.color(for: scheme))
                .frame(height: 1)

            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(field.timeUnits.enumerated()), id: \.element) { index, unit in
                    ChatFormTimeColumn(
                        unit: unit,
                        range: 0...field.maximum(at: index),
                        selected: normalizedValues[index]
                    ) { picked in
                        var updated = normalizedValues
                        updated[index] = picked
                        values = updated
                    }
                }
            }

            Rectangle()
                .fill(ThemeColor.kBorder.color(for: scheme))
                .frame(height: 1)

            HStack {
                Spacer(minLength: 0)
                ChatFormPopoverPrimaryButton(title: NSLocalizedString("完成", comment: ""), action: dismiss)
            }
        }
        .padding(14)
        .frame(width: popoverWidth)
        .fixedSize()
    }

    private var normalizedValues: [Int] {
        values.count == field.timeUnits.count ? values : field.initialTemporalValues()
    }
}

private struct ChatFormTimeColumn: View {
    let unit: ChatForm.TimeUnit
    let range: ClosedRange<Int>
    let selected: Int
    let onSelect: (Int) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            Text(NSLocalizedString(unit.label, comment: ""))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ThemeColor.kTextSubtlest)
                .frame(maxWidth: .infinity)

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(range), id: \.self) { number in
                            ChatFormTimeCell(
                                text: String(format: "%02d", number),
                                selected: number == selected
                            ) {
                                onSelect(number)
                                if reduceMotion {
                                    proxy.scrollTo(number, anchor: .center)
                                } else {
                                    withAnimation(.easeOut(duration: 0.16)) {
                                        proxy.scrollTo(number, anchor: .center)
                                    }
                                }
                            }
                            .id(number)
                            .background(ChatFormControlMarker(id: "chat-form-unit-\(unit.rawValue)-\(number)"))
                            .accessibilityIdentifier("chat-form-unit-\(unit.rawValue)-\(number)")
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
                .frame(height: 184)
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 14)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 14)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(scheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.03))
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onAppear {
                    proxy.scrollTo(selected, anchor: .center)
                }
                .onChange(of: selected) { _, target in
                    if reduceMotion {
                        proxy.scrollTo(target, anchor: .center)
                    } else {
                        withAnimation(.easeOut(duration: 0.16)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ChatFormTimeCell: View {
    let text: String
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(
                    selected
                        ? ThemeColor("textInverted").color(for: scheme)
                        : hovered ? ThemeColor.kText.color(for: scheme) : ThemeColor.kTextSubtle.color(for: scheme)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    selected
                        ? ThemeColor.kBackgroundPrimary.color(for: scheme)
                        : hovered ? ThemeColor.kInteractionHover.color(for: scheme) : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .padding(.horizontal, 3)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - Shared Form Trigger & Popover Controls

struct ChatFormPickerTriggerButton<Icon: View>: View {
    let isOpen: Bool
    let enabled: Bool
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ChatFormMetrics.controlCornerRadius, style: .continuous)
    }

    private var fill: Color {
        if isOpen {
            return scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.80)
        }
        if hovered && enabled {
            return scheme == .dark ? Color.white.opacity(0.09) : Color.white.opacity(0.68)
        }
        return scheme == .dark
            ? ThemeColor.kBackgroundNeutral.color(for: scheme)
            : SettingsPalette.surface(scheme, opaque: true).opacity(0.45)
    }

    private var border: Color {
        if isOpen { return SettingsPalette.focusBorder(scheme) }
        if hovered && enabled {
            return (scheme == .dark ? Color.white : Color.black).opacity(0.22)
        }
        return ThemeColor.kBorder.color(for: scheme)
    }

    var body: some View {
        Button(action: action) {
            icon()
                .foregroundStyle(isOpen || (hovered && enabled) ? ThemeColor.kText.color(for: scheme) : ThemeColor.kIcon.color(for: scheme))
                .frame(width: ChatFormMetrics.controlHeight, height: ChatFormMetrics.controlHeight)
                .background(fill, in: shape)
                .overlay {
                    shape.strokeBorder(border, lineWidth: isOpen ? 1.5 : 1)
                        .allowsHitTesting(false)
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .background(ChatFormControlMarker(id: accessibilityIdentifier))
        .actionArrowCursor(enabled: enabled)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: hovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isOpen)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct ChatFormPopoverGhostButton: View {
    let title: String
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovered ? ThemeColor.kText.color(for: scheme) : ThemeColor.kTextSubtle.color(for: scheme))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    hovered ? ThemeColor.kInteractionHover.color(for: scheme) : ThemeColor.kBackgroundNeutral.color(for: scheme),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct ChatFormPopoverPrimaryButton: View {
    let title: String
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ThemeColor("textInverted").color(for: scheme))
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(
                    ThemeColor.kBackgroundPrimary.color(for: scheme).opacity(hovered ? 0.86 : 1),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// Crisp geometric clock glyph matching MingCute's 24pt/2pt round-stroke icon weight.
struct ChatFormClockGlyph: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 24
            let style = StrokeStyle(lineWidth: 2 * scale, lineCap: .round, lineJoin: .round)
            let inset = 3 * scale
            let circle = Path(ellipseIn: CGRect(x: inset, y: inset, width: 18 * scale, height: 18 * scale))
            context.stroke(circle, with: .foreground, style: style)

            var hands = Path()
            hands.move(to: CGPoint(x: 12 * scale, y: 7.5 * scale))
            hands.addLine(to: CGPoint(x: 12 * scale, y: 12 * scale))
            hands.addLine(to: CGPoint(x: 15.2 * scale, y: 14 * scale))
            context.stroke(hands, with: .foreground, style: style)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Non-interactive geometry marker so native regressions can locate and click real SwiftUI controls.
struct ChatFormControlMarker: NSViewRepresentable {
    let id: String

    func makeNSView(context: Context) -> MarkerView {
        let view = MarkerView()
        view.identifier = NSUserInterfaceItemIdentifier(id)
        return view
    }

    func updateNSView(_ view: MarkerView, context: Context) {
        view.identifier = NSUserInterfaceItemIdentifier(id)
    }

    final class MarkerView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
