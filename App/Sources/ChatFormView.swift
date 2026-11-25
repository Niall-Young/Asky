import AppKit
import SwiftUI
import Theme

enum ChatFormMetrics {
    static let controlHeight: CGFloat = 34
    static let controlCornerRadius: CGFloat = 10
    static let optionMinHeight: CGFloat = 38
    static let optionCornerRadius: CGFloat = 10
    static let optionSpacing: CGFloat = 8
    static let labelControlSpacing: CGFloat = 10
    static let fieldSpacing: CGFloat = 22
    static let replyPartSpacing: CGFloat = 20
}

struct ChatReplyView: View {
    let text: String
    var isStreaming = false
    var values: Binding<[String: [String]]> = .constant([:])
    var active = false
    var submit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: ChatFormMetrics.replyPartSpacing) {
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
                VStack(alignment: .leading, spacing: ChatFormMetrics.labelControlSpacing) {
                    HStack(spacing: 4) {
                        Text(field.label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ThemeColor.kTextSubtle)
                        if field.required == true {
                            Text(verbatim: "*")
                                .font(.system(size: 14, weight: .medium))
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
                ChatFormSubmitButton(NSLocalizedString("提交回复", comment: ""), action: submit)
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
        case .radio:
            if field.allowsCustomAnswer {
                ChatCustomChoice(field: field, answer: scalar(field.id), active: active)
            } else {
                ChatFormRadioGroup(label: field.label, options: field.options ?? [], selection: scalar(field.id), active: active)
            }
        case .multi:
            ChatFormMultiGroup(label: field.label, options: field.options ?? [], selection: multiBinding(field.id), active: active)
        case .datetime:
            if !active, values[field.id] == nil {
                Text(verbatim: "—").foregroundStyle(ThemeColor.kTextSubtle)
            } else {
                ChatFormDateTimeField(field: field, value: scalar(field.id), active: active)
                    .onChange(of: active, initial: true) {
                        if active, values[field.id] == nil {
                            values[field.id] = [field.initialDateTime()]
                        }
                    }
            }
        case .datetimeRange:
            if !active, values[field.id] == nil {
                Text(verbatim: "—").foregroundStyle(ThemeColor.kTextSubtle)
            } else {
                ChatFormDateTimeRangeField(field: field, value: scalar(field.id), active: active)
                    .onChange(of: active, initial: true) {
                        if active, values[field.id] == nil {
                            values[field.id] = [field.initialDateTimeRange()]
                        }
                    }
            }
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
        case .timeRange:
            if !active, values[field.id] == nil {
                Text(verbatim: "—").foregroundStyle(ThemeColor.kTextSubtle)
            } else {
                ChatFormTimeRangeField(field: field, value: scalar(field.id), active: active)
                    .onChange(of: active, initial: true) {
                        if active, values[field.id] == nil {
                            values[field.id] = [field.initialTimeRange()]
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
        case .dateRange:
            if !active, values[field.id] == nil {
                Text(verbatim: "—").foregroundStyle(ThemeColor.kTextSubtle)
            } else {
                ChatFormDateRangeField(field: field, value: scalar(field.id), active: active)
                    .onChange(of: active, initial: true) {
                        if active, values[field.id] == nil {
                            values[field.id] = [field.initialDateRange()]
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
        if !active {
            if selected {
                return scheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.28)
            }
            return scheme == .dark ? Color.white.opacity(0.015) : Color.white.opacity(0.14)
        }
        if selected {
            return scheme == .dark ? Color.white.opacity(0.065) : Color.white.opacity(0.46)
        }
        if hovered {
            return scheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.36)
        }
        return scheme == .dark ? Color.white.opacity(0.02) : Color.white.opacity(0.20)
    }

    private var selectedBorderColor: Color {
        let boost: Double = contrast == .increased ? 0.16 : 0
        if !active {
            let base: Double = scheme == .dark ? 0.16 : 0.14
            return (scheme == .dark ? Color.white : Color.black).opacity(min(1, base + boost))
        }
        let base: Double = scheme == .dark ? 0.34 : 0.28
        return (scheme == .dark ? Color.white : Color.black).opacity(min(1, base + boost))
    }

    private var unselectedBorderColor: Color {
        let boost: Double = contrast == .increased ? 0.16 : 0
        let base: Double
        if hovered && active {
            base = scheme == .dark ? 0.24 : 0.22
        } else if dimmed || !active {
            base = scheme == .dark ? 0.10 : 0.09
        } else {
            base = scheme == .dark ? 0.15 : 0.14
        }
        return (scheme == .dark ? Color.white : Color.black).opacity(min(1, base + boost))
    }

    private var textColor: Color {
        if !active {
            return selected
                ? ThemeColor.kTextSubtle.color(for: scheme)
                : ThemeColor("textDisabled").color(for: scheme)
        }
        if selected || hovered {
            return ThemeColor.kText.color(for: scheme)
        }
        if dimmed {
            return ThemeColor.kTextSubtle.color(for: scheme)
        }
        return ThemeColor.kText.color(for: scheme)
    }

    private var selectedBadgeFill: Color {
        if !active {
            return (scheme == .dark ? Color.white : Color.black).opacity(0.32)
        }
        return ThemeColor.kBackgroundPrimary.color(for: scheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.system(size: 14, weight: .regular))
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
                    shape.strokeBorder(selectedBorderColor, lineWidth: 1)
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
        .opacity(!active && !selected ? 0.62 : 1)
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
            ZStack {
                Color.clear
                ZStack {
                    Circle().fill(selectedBadgeFill)
                    Image(mingCute: "checkmark", size: 10)
                        .foregroundStyle(ThemeColor("textInverted").color(for: scheme))
                }
                .scaleEffect(selected || reduceMotion ? 1 : 0.82)
                .opacity(selected ? 1 : 0)
            }
        case .multiple:
            let box = RoundedRectangle(cornerRadius: 5, style: .continuous)
            ZStack {
                if selected {
                    box.fill(selectedBadgeFill)
                    Image(mingCute: "checkmark", size: 10.5)
                        .foregroundStyle(ThemeColor("textInverted").color(for: scheme))
                } else {
                    box.fill(scheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.45))
                    box.strokeBorder(
                        (scheme == .dark ? Color.white : Color.black).opacity(hovered && active ? 0.42 : 0.22),
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

// MARK: - Custom Choice (Radio with allowCustom)

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
            ChatFormRadioGroup(label: field.label, options: (field.options ?? []) + [customOption], selection: selection, active: active)
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

// MARK: - Combined Date & Time Field (Unified Input + Inline Icon + Floating Glass Picker)

private struct ChatFormDateTimeField: View {
    let field: ChatForm.Field
    @Binding var value: String
    let active: Bool

    @State private var draftText: String
    @State private var anchorBox = ChatBubbleAnchorBox()
    @FocusState private var inputFocused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.formPickerOverlay) private var pickerOverlay

    init(field: ChatForm.Field, value: Binding<String>, active: Bool) {
        self.field = field
        _value = value
        self.active = active
        let initial = value.wrappedValue.isEmpty ? field.initialDateTime() : value.wrappedValue
        _draftText = State(initialValue: initial)
    }

    private var pickerID: String { "chat-form-picker-" + field.id }
    private var isPickerOpen: Bool { pickerOverlay?.isOpen(pickerID) == true }

    private var currentComponents: (date: Date, time: [Int]) {
        field.dateTimeComponents(value) ?? (Date(), field.initialTemporalValues())
    }

    private func dateBinding(overlay: FormPickerOverlayController?) -> Binding<Date> {
        Binding(
            get: { currentComponents.date },
            set: { newDate in
                let formatted = field.dateTimeString(date: newDate, time: currentComponents.time)
                value = formatted
                draftText = formatted
                overlay?.notifyChanged()
            }
        )
    }

    private func timeBinding(overlay: FormPickerOverlayController?) -> Binding<[Int]> {
        Binding(
            get: { currentComponents.time },
            set: { newTime in
                let formatted = field.dateTimeString(date: currentComponents.date, time: newTime)
                value = formatted
                draftText = formatted
                overlay?.notifyChanged()
            }
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField(field.dateTimePlaceholder, text: $draftText,
                      prompt: Text(verbatim: field.dateTimePlaceholder).foregroundStyle(ThemeColor.kTextSubtlest))
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
                    guard active, let parsed = field.parseDateTimeInput(newValue) else { return }
                    let formatted = field.dateTimeString(date: parsed.date, time: parsed.time)
                    if value != formatted {
                        value = formatted
                        pickerOverlay?.notifyChanged()
                    }
                }
                .onChange(of: value) { _, newValue in
                    let parsedDraft = field.parseDateTimeInput(draftText).map {
                        field.dateTimeString(date: $0.date, time: $0.time)
                    }
                    if !newValue.isEmpty, (!inputFocused || parsedDraft != newValue) {
                        draftText = newValue
                    }
                }
                .onChange(of: active) { _, isActive in
                    if !isActive, isPickerOpen { pickerOverlay?.dismiss() }
                }
                .accessibilityLabel(field.label)
                .accessibilityIdentifier("chat-form-field-" + field.id)

            ChatFormInlinePickerIcon(
                isOpen: isPickerOpen,
                enabled: active,
                accessibilityLabel: NSLocalizedString("选择日期与时间", comment: ""),
                accessibilityIdentifier: pickerID
            ) {
                togglePicker()
            } icon: {
                ChatFormClockGlyph(size: 15)
            }
        }
        .settingsInputSurface(scheme: scheme, focused: inputFocused || isPickerOpen)
        .background(ChatFormControlMarker(id: "chat-form-field-" + field.id))
        .background(ChatBubbleAnchorReader(box: anchorBox).allowsHitTesting(false))
    }

    private func togglePicker() {
        commitDraft()
        inputFocused = false
        guard let anchor = anchorBox.swiftUIFrameInWindow() else { return }
        let overlay = pickerOverlay
        overlay?.toggle(
            id: pickerID,
            anchor: anchor,
            preferredSize: ChatFormDateTimePopover.preferredSize(for: field)
        ) {
            AnyView(ChatFormDateTimePopover(
                field: field,
                date: dateBinding(overlay: overlay),
                timeValues: timeBinding(overlay: overlay)
            ))
        }
    }

    private func commitDraft() {
        if let parsed = field.parseDateTimeInput(draftText) {
            let formatted = field.dateTimeString(date: parsed.date, time: parsed.time)
            value = formatted
            draftText = formatted
        } else {
            draftText = value.isEmpty ? field.initialDateTime() : value
        }
    }
}

struct ChatFormDateTimePopover: View {
    let field: ChatForm.Field
    @Binding var date: Date
    @Binding var timeValues: [Int]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.formPickerOverlay) private var pickerOverlay

    private static func timeColumnsWidth(for field: ChatForm.Field) -> CGFloat {
        switch field.timeUnits.count {
        case 1: 68
        case 2: 128
        default: 188
        }
    }

    static func preferredSize(for field: ChatForm.Field) -> CGSize {
        CGSize(width: 248 + 12 + 1 + 12 + timeColumnsWidth(for: field) + 28, height: 292)
    }

    private var normalizedTime: [Int] {
        timeValues.count == field.timeUnits.count ? timeValues : field.initialTemporalValues()
    }

    var body: some View {
        let _ = pickerOverlay?.revision
        HStack(alignment: .top, spacing: 12) {
            CalendarMonthPicker(selection: $date, monochrome: true)
                .frame(width: 248)

            Rectangle()
                .fill(ThemeColor.kBorder.color(for: scheme))
                .frame(width: 1)

            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(field.timeUnits.enumerated()), id: \.element) { index, unit in
                    ChatFormTimeColumn(
                        unit: unit,
                        range: 0...field.maximum(at: index),
                        selected: normalizedTime[index],
                        columnHeight: 240
                    ) { picked in
                        var updated = normalizedTime
                        updated[index] = picked
                        timeValues = updated
                    }
                }
            }
            .frame(width: Self.timeColumnsWidth(for: field))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .fixedSize()
    }
}

// MARK: - Date & Time Range Field (Merged Start + End Selector)

private struct ChatFormDateTimeRangeField: View {
    let field: ChatForm.Field
    @Binding var value: String
    let active: Bool

    @State private var draftText: String
    @State private var anchorBox = ChatBubbleAnchorBox()
    @FocusState private var inputFocused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.formPickerOverlay) private var pickerOverlay

    init(field: ChatForm.Field, value: Binding<String>, active: Bool) {
        self.field = field
        _value = value
        self.active = active
        let initial = value.wrappedValue.isEmpty ? field.initialDateTimeRange() : value.wrappedValue
        _draftText = State(initialValue: initial)
    }

    private var pickerID: String { "chat-form-picker-" + field.id }
    private var isPickerOpen: Bool { pickerOverlay?.isOpen(pickerID) == true }

    var body: some View {
        HStack(spacing: 6) {
            TextField(field.dateTimeRangePlaceholder, text: $draftText,
                      prompt: Text(verbatim: field.dateTimeRangePlaceholder).foregroundStyle(ThemeColor.kTextSubtlest))
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
                    guard active, let parsed = field.parseDateTimeRangeInput(newValue) else { return }
                    let formatted = field.dateTimeRangeString(
                        startDate: parsed.startDate,
                        startTime: parsed.startTime,
                        endDate: parsed.endDate,
                        endTime: parsed.endTime
                    )
                    if value != formatted {
                        value = formatted
                        pickerOverlay?.notifyChanged()
                    }
                }
                .onChange(of: value) { _, newValue in
                    let parsedDraft = field.parseDateTimeRangeInput(draftText).map {
                        field.dateTimeRangeString(
                            startDate: $0.startDate,
                            startTime: $0.startTime,
                            endDate: $0.endDate,
                            endTime: $0.endTime
                        )
                    }
                    if !newValue.isEmpty, (!inputFocused || parsedDraft != newValue) {
                        draftText = newValue
                    }
                }
                .onChange(of: active) { _, isActive in
                    if !isActive, isPickerOpen { pickerOverlay?.dismiss() }
                }
                .accessibilityLabel(field.label)
                .accessibilityIdentifier("chat-form-field-" + field.id)

            ChatFormInlinePickerIcon(
                isOpen: isPickerOpen,
                enabled: active,
                accessibilityLabel: NSLocalizedString("选择时间段", comment: ""),
                accessibilityIdentifier: pickerID
            ) {
                togglePicker()
            } icon: {
                ChatFormClockGlyph(size: 15)
            }
        }
        .settingsInputSurface(scheme: scheme, focused: inputFocused || isPickerOpen)
        .background(ChatFormControlMarker(id: "chat-form-field-" + field.id))
        .background(ChatBubbleAnchorReader(box: anchorBox).allowsHitTesting(false))
    }

    private func togglePicker() {
        commitDraft()
        inputFocused = false
        guard let anchor = anchorBox.swiftUIFrameInWindow() else { return }
        let overlay = pickerOverlay
        overlay?.toggle(
            id: pickerID,
            anchor: anchor,
            preferredSize: ChatFormDateTimeRangePopover.preferredSize(for: field)
        ) {
            AnyView(ChatFormDateTimeRangePopover(field: field, value: $value))
        }
    }

    private func commitDraft() {
        if let parsed = field.parseDateTimeRangeInput(draftText) {
            let formatted = field.dateTimeRangeString(
                startDate: parsed.startDate,
                startTime: parsed.startTime,
                endDate: parsed.endDate,
                endTime: parsed.endTime
            )
            value = formatted
            draftText = formatted
        } else {
            draftText = value.isEmpty ? field.initialDateTimeRange() : value
        }
    }
}

struct ChatFormDateTimeRangePopover: View {
    let field: ChatForm.Field
    @Binding var value: String

    @State private var editingEnd = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.formPickerOverlay) private var pickerOverlay

    private static func timeColumnsWidth(for field: ChatForm.Field) -> CGFloat {
        switch field.timeUnits.count {
        case 1: 68
        case 2: 128
        default: 188
        }
    }

    static func preferredSize(for field: ChatForm.Field) -> CGSize {
        CGSize(width: 248 + 12 + 1 + 12 + timeColumnsWidth(for: field) + 28, height: 356)
    }

    private var currentRange: (startDate: Date, startTime: [Int], endDate: Date, endTime: [Int]) {
        if let parsed = field.dateTimeRangeComponents(value) {
            return parsed
        }
        let now = Date()
        let end = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)
        return (now, field.initialTemporalValues(now: now), end, field.initialTemporalValues(now: end))
    }

    private func applyRange(startDate: Date, startTime: [Int], endDate: Date, endTime: [Int]) {
        value = field.dateTimeRangeString(
            startDate: startDate,
            startTime: startTime,
            endDate: endDate,
            endTime: endTime
        )
        pickerOverlay?.notifyChanged()
    }

    private func updateStart(date newDate: Date? = nil, time newTime: [Int]? = nil) {
        let current = currentRange
        let calendar = Calendar.current
        let oldStart = field.combinedInstant(date: current.startDate, time: current.startTime, calendar: calendar) ?? current.startDate
        let oldEnd = field.combinedInstant(date: current.endDate, time: current.endTime, calendar: calendar) ?? oldStart.addingTimeInterval(3600)
        let duration = max(oldEnd.timeIntervalSince(oldStart), 3600)

        let startDate = newDate ?? current.startDate
        let startTime = newTime ?? current.startTime
        let newStart = field.combinedInstant(date: startDate, time: startTime, calendar: calendar) ?? startDate
        let shiftedEnd = newStart.addingTimeInterval(duration)
        let endTime = field.initialTemporalValues(now: shiftedEnd)
        applyRange(startDate: startDate, startTime: startTime, endDate: shiftedEnd, endTime: endTime)
    }

    private func updateEndDate(_ pickedDate: Date) {
        let current = currentRange
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: current.startDate)
        let pickedDay = calendar.startOfDay(for: pickedDate)

        if pickedDay < startDay {
            let newStart = pickedDate
            let newEnd = current.startDate
            let startInstant = field.combinedInstant(date: newStart, time: current.startTime, calendar: calendar) ?? newStart
            let endInstant = field.combinedInstant(date: newEnd, time: current.endTime, calendar: calendar) ?? newEnd
            if endInstant > startInstant {
                applyRange(startDate: newStart, startTime: current.startTime, endDate: newEnd, endTime: current.endTime)
            } else {
                let bumped = startInstant.addingTimeInterval(3600)
                applyRange(startDate: newStart, startTime: current.startTime, endDate: bumped, endTime: field.initialTemporalValues(now: bumped))
            }
            return
        }

        let startInstant = field.combinedInstant(date: current.startDate, time: current.startTime, calendar: calendar) ?? current.startDate
        let candidateEnd = field.combinedInstant(date: pickedDate, time: current.endTime, calendar: calendar) ?? pickedDate
        if candidateEnd > startInstant {
            applyRange(startDate: current.startDate, startTime: current.startTime, endDate: pickedDate, endTime: current.endTime)
        } else {
            let bumped = startInstant.addingTimeInterval(3600)
            applyRange(startDate: current.startDate, startTime: current.startTime, endDate: bumped, endTime: field.initialTemporalValues(now: bumped))
        }
    }

    private func updateEndTime(unitIndex: Int, picked: Int) {
        let current = currentRange
        let calendar = Calendar.current
        var candidateTime = current.endTime
        guard candidateTime.indices.contains(unitIndex) else { return }
        candidateTime[unitIndex] = picked

        let startInstant = field.combinedInstant(date: current.startDate, time: current.startTime, calendar: calendar) ?? current.startDate
        let oldEndInstant = field.combinedInstant(date: current.endDate, time: current.endTime, calendar: calendar) ?? startInstant.addingTimeInterval(3600)
        let candidateInstant = field.combinedInstant(date: current.endDate, time: candidateTime, calendar: calendar) ?? oldEndInstant

        if candidateInstant > startInstant {
            applyRange(startDate: current.startDate, startTime: current.startTime, endDate: current.endDate, endTime: candidateTime)
            return
        }

        if calendar.isDate(current.startDate, inSameDayAs: current.endDate),
           field.timeUnits[unitIndex] == .hour,
           let hourIdx = field.timeUnits.firstIndex(of: .hour),
           picked == current.startTime[hourIdx],
           let minIdx = field.timeUnits.firstIndex(of: .minute),
           current.startTime[minIdx] < 59 {
            var adjusted = candidateTime
            adjusted[minIdx] = min(59, current.startTime[minIdx] + 15)
            applyRange(startDate: current.startDate, startTime: current.startTime, endDate: current.endDate, endTime: adjusted)
            return
        }

        let duration = max(oldEndInstant.timeIntervalSince(startInstant), 3600)
        let shiftedStart = candidateInstant.addingTimeInterval(-duration)
        applyRange(
            startDate: shiftedStart,
            startTime: field.initialTemporalValues(now: shiftedStart),
            endDate: current.endDate,
            endTime: candidateTime
        )
    }

    private var activeDateBinding: Binding<Date> {
        Binding(
            get: { editingEnd ? currentRange.endDate : currentRange.startDate },
            set: { picked in
                if editingEnd {
                    updateEndDate(picked)
                } else {
                    updateStart(date: picked)
                }
            }
        )
    }

    var body: some View {
        let _ = pickerOverlay?.revision
        let range = currentRange
        let rawActiveTime = editingEnd ? range.endTime : range.startTime
        let activeTime = rawActiveTime.count == field.timeUnits.count ? rawActiveTime : field.initialTemporalValues()

        VStack(spacing: 12) {
            ChatFormRangeTabs(
                startSummary: field.dateTimeString(date: range.startDate, time: range.startTime),
                endSummary: field.dateTimeString(date: range.endDate, time: range.endTime),
                editingEnd: $editingEnd
            )

            Rectangle()
                .fill(ThemeColor.kBorder.color(for: scheme))
                .frame(height: 1)

            HStack(alignment: .top, spacing: 12) {
                CalendarMonthPicker(
                    selection: activeDateBinding,
                    monochrome: true,
                    rangeStart: range.startDate,
                    rangeEnd: range.endDate
                )
                .frame(width: 248)

                Rectangle()
                    .fill(ThemeColor.kBorder.color(for: scheme))
                    .frame(width: 1)

                HStack(alignment: .top, spacing: 6) {
                    ForEach(Array(field.timeUnits.enumerated()), id: \.element) { index, unit in
                        ChatFormTimeColumn(
                            unit: unit,
                            range: 0...field.maximum(at: index),
                            selected: activeTime[index],
                            columnHeight: 240
                        ) { picked in
                            if editingEnd {
                                updateEndTime(unitIndex: index, picked: picked)
                            } else {
                                var updated = range.startTime
                                if updated.indices.contains(index) {
                                    updated[index] = picked
                                    updateStart(time: updated)
                                }
                            }
                        }
                    }
                }
                .frame(width: Self.timeColumnsWidth(for: field))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .fixedSize()
    }
}

// MARK: - Date Field (Unified Input + Inline Calendar Icon + Floating Glass Picker)

private struct ChatFormDateField: View {
    let field: ChatForm.Field
    @Binding var value: String
    let active: Bool

    @State private var draftText: String
    @State private var anchorBox = ChatBubbleAnchorBox()
    @FocusState private var inputFocused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.formPickerOverlay) private var pickerOverlay

    init(field: ChatForm.Field, value: Binding<String>, active: Bool) {
        self.field = field
        _value = value
        self.active = active
        let initial = value.wrappedValue.isEmpty ? ChatForm.dateString(Date()) : value.wrappedValue
        _draftText = State(initialValue: initial)
    }

    private var pickerID: String { "chat-form-picker-" + field.id }
    private var isPickerOpen: Bool { pickerOverlay?.isOpen(pickerID) == true }

    private func dateBinding(overlay: FormPickerOverlayController?) -> Binding<Date> {
        Binding(
            get: { ChatForm.date(value) ?? Date() },
            set: { date in
                let formatted = ChatForm.dateString(date)
                value = formatted
                draftText = formatted
                overlay?.notifyChanged()
            }
        )
    }

    var body: some View {
        HStack(spacing: 6) {
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
                    if value != formatted {
                        value = formatted
                        pickerOverlay?.notifyChanged()
                    }
                }
                .onChange(of: value) { _, newValue in
                    if !newValue.isEmpty, (!inputFocused || ChatForm.parseDateInput(draftText).map(ChatForm.dateString) != newValue) {
                        draftText = newValue
                    }
                }
                .onChange(of: active) { _, isActive in
                    if !isActive, isPickerOpen { pickerOverlay?.dismiss() }
                }
                .accessibilityLabel(field.label)
                .accessibilityIdentifier("chat-form-field-" + field.id)

            ChatFormInlinePickerIcon(
                isOpen: isPickerOpen,
                enabled: active,
                accessibilityLabel: NSLocalizedString("选择日期", comment: ""),
                accessibilityIdentifier: pickerID
            ) {
                togglePicker()
            } icon: {
                Image(mingCute: "calendar", size: 15)
            }
        }
        .settingsInputSurface(scheme: scheme, focused: inputFocused || isPickerOpen)
        .background(ChatFormControlMarker(id: "chat-form-field-" + field.id))
        .background(ChatBubbleAnchorReader(box: anchorBox).allowsHitTesting(false))
    }

    private func togglePicker() {
        commitDraft()
        inputFocused = false
        guard let anchor = anchorBox.swiftUIFrameInWindow() else { return }
        let overlay = pickerOverlay
        overlay?.toggle(
            id: pickerID,
            anchor: anchor,
            preferredSize: ChatFormDatePopover.preferredSize
        ) {
            AnyView(ChatFormDatePopover(selection: dateBinding(overlay: overlay)))
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
    @Environment(\.formPickerOverlay) private var pickerOverlay

    static let preferredSize = CGSize(width: 276, height: 292)

    var body: some View {
        let _ = pickerOverlay?.revision
        CalendarMonthPicker(selection: $selection, monochrome: true)
            .padding(14)
            .frame(width: Self.preferredSize.width)
            .fixedSize()
    }
}

// MARK: - Date Range Field (Unified Input + Inline Calendar Icon + Range Calendar Overlay)

private struct ChatFormDateRangeField: View {
    let field: ChatForm.Field
    @Binding var value: String
    let active: Bool

    @State private var draftText: String
    @State private var anchorBox = ChatBubbleAnchorBox()
    @FocusState private var inputFocused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.formPickerOverlay) private var pickerOverlay

    init(field: ChatForm.Field, value: Binding<String>, active: Bool) {
        self.field = field
        _value = value
        self.active = active
        let initial = value.wrappedValue.isEmpty ? field.initialDateRange() : value.wrappedValue
        _draftText = State(initialValue: initial)
    }

    private var pickerID: String { "chat-form-picker-" + field.id }
    private var isPickerOpen: Bool { pickerOverlay?.isOpen(pickerID) == true }

    var body: some View {
        HStack(spacing: 6) {
            TextField(field.dateRangePlaceholder, text: $draftText,
                      prompt: Text(verbatim: field.dateRangePlaceholder).foregroundStyle(ThemeColor.kTextSubtlest))
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
                    guard active, let parsed = field.parseDateRangeInput(newValue) else { return }
                    let formatted = field.dateRangeString(start: parsed.start, end: parsed.end)
                    if value != formatted {
                        value = formatted
                        pickerOverlay?.notifyChanged()
                    }
                }
                .onChange(of: value) { _, newValue in
                    let parsedDraft = field.parseDateRangeInput(draftText).map {
                        field.dateRangeString(start: $0.start, end: $0.end)
                    }
                    if !newValue.isEmpty, (!inputFocused || parsedDraft != newValue) {
                        draftText = newValue
                    }
                }
                .onChange(of: active) { _, isActive in
                    if !isActive, isPickerOpen { pickerOverlay?.dismiss() }
                }
                .accessibilityLabel(field.label)
                .accessibilityIdentifier("chat-form-field-" + field.id)

            ChatFormInlinePickerIcon(
                isOpen: isPickerOpen,
                enabled: active,
                accessibilityLabel: NSLocalizedString("选择日期范围", comment: ""),
                accessibilityIdentifier: pickerID
            ) {
                togglePicker()
            } icon: {
                Image(mingCute: "calendar", size: 15)
            }
        }
        .settingsInputSurface(scheme: scheme, focused: inputFocused || isPickerOpen)
        .background(ChatFormControlMarker(id: "chat-form-field-" + field.id))
        .background(ChatBubbleAnchorReader(box: anchorBox).allowsHitTesting(false))
    }

    private func togglePicker() {
        commitDraft()
        inputFocused = false
        guard let anchor = anchorBox.swiftUIFrameInWindow() else { return }
        let overlay = pickerOverlay
        overlay?.toggle(
            id: pickerID,
            anchor: anchor,
            preferredSize: ChatFormDateRangePopover.preferredSize
        ) {
            AnyView(ChatFormDateRangePopover(field: field, value: $value))
        }
    }

    private func commitDraft() {
        if let parsed = field.parseDateRangeInput(draftText) {
            let formatted = field.dateRangeString(start: parsed.start, end: parsed.end)
            value = formatted
            draftText = formatted
        } else {
            draftText = value.isEmpty ? field.initialDateRange() : value
        }
    }
}

struct ChatFormDateRangePopover: View {
    let field: ChatForm.Field
    @Binding var value: String

    @State private var editingEnd = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.formPickerOverlay) private var pickerOverlay

    static let preferredSize = CGSize(width: 276, height: 356)

    private var currentRange: (start: Date, end: Date) {
        if let parsed = field.dateRangeComponents(value) {
            return parsed
        }
        let today = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        return (today, tomorrow)
    }

    private func applyRange(start: Date, end: Date) {
        value = field.dateRangeString(start: start, end: end)
        pickerOverlay?.notifyChanged()
    }

    private func updateStart(_ picked: Date) {
        let current = currentRange
        let calendar = Calendar.current
        let dayDiff = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: current.start), to: calendar.startOfDay(for: current.end)).day ?? 0)
        let shiftedEnd = calendar.date(byAdding: .day, value: dayDiff, to: picked) ?? picked
        applyRange(start: picked, end: shiftedEnd)
    }

    private func updateEnd(_ picked: Date) {
        let current = currentRange
        let calendar = Calendar.current
        if calendar.startOfDay(for: picked) < calendar.startOfDay(for: current.start) {
            applyRange(start: picked, end: current.start)
        } else {
            applyRange(start: current.start, end: picked)
        }
    }

    private var activeDateBinding: Binding<Date> {
        Binding(
            get: { editingEnd ? currentRange.end : currentRange.start },
            set: { picked in
                if editingEnd { updateEnd(picked) } else { updateStart(picked) }
            }
        )
    }

    var body: some View {
        let _ = pickerOverlay?.revision
        let range = currentRange
        VStack(spacing: 12) {
            ChatFormRangeTabs(
                startSummary: ChatForm.dateString(range.start),
                endSummary: ChatForm.dateString(range.end),
                editingEnd: $editingEnd
            )

            Rectangle()
                .fill(ThemeColor.kBorder.color(for: scheme))
                .frame(height: 1)

            CalendarMonthPicker(
                selection: activeDateBinding,
                monochrome: true,
                rangeStart: range.start,
                rangeEnd: range.end
            )
        }
        .padding(14)
        .frame(width: Self.preferredSize.width)
        .fixedSize()
    }
}

// MARK: - Time & Duration Field (Unified Input + Inline Clock Icon + Floating Glass Picker)

private struct ChatFormTemporalField: View {
    let field: ChatForm.Field
    @Binding var value: String
    let active: Bool

    @State private var draftText: String
    @State private var anchorBox = ChatBubbleAnchorBox()
    @FocusState private var inputFocused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.formPickerOverlay) private var pickerOverlay

    init(field: ChatForm.Field, value: Binding<String>, active: Bool) {
        self.field = field
        _value = value
        self.active = active
        let initial = value.wrappedValue.isEmpty
            ? field.temporalString(field.initialTemporalValues())
            : value.wrappedValue
        _draftText = State(initialValue: initial)
    }

    private var pickerID: String { "chat-form-picker-" + field.id }
    private var isPickerOpen: Bool { pickerOverlay?.isOpen(pickerID) == true }

    private func temporalBinding(overlay: FormPickerOverlayController?) -> Binding<[Int]> {
        Binding(
            get: { field.temporalValues(value) ?? field.initialTemporalValues() },
            set: { numbers in
                let formatted = field.temporalString(numbers)
                value = formatted
                draftText = formatted
                overlay?.notifyChanged()
            }
        )
    }

    var body: some View {
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
                    if value != formatted {
                        value = formatted
                        pickerOverlay?.notifyChanged()
                    }
                }
                .onChange(of: value) { _, newValue in
                    if !newValue.isEmpty, (!inputFocused || field.parseTemporalInput(draftText).map(field.temporalString) != newValue) {
                        draftText = newValue
                    }
                }
                .onChange(of: active) { _, isActive in
                    if !isActive, isPickerOpen { pickerOverlay?.dismiss() }
                }
                .accessibilityLabel(field.label)
                .accessibilityIdentifier("chat-form-field-" + field.id)

            if field.type == .duration, field.timeUnits.count == 1, let unit = field.timeUnits.first {
                Text(NSLocalizedString(unit.label, comment: ""))
                    .font(.system(size: 12))
                    .foregroundStyle(ThemeColor.kTextSubtlest)
                    .allowsHitTesting(false)
            }

            ChatFormInlinePickerIcon(
                isOpen: isPickerOpen,
                enabled: active,
                accessibilityLabel: NSLocalizedString(field.type == .duration ? "选择时长" : "选择时间", comment: ""),
                accessibilityIdentifier: pickerID
            ) {
                togglePicker()
            } icon: {
                ChatFormClockGlyph(size: 15)
            }
        }
        .settingsInputSurface(scheme: scheme, focused: inputFocused || isPickerOpen)
        .background(ChatFormControlMarker(id: "chat-form-field-" + field.id))
        .background(ChatBubbleAnchorReader(box: anchorBox).allowsHitTesting(false))
    }

    private func togglePicker() {
        commitDraft()
        inputFocused = false
        guard let anchor = anchorBox.swiftUIFrameInWindow() else { return }
        let overlay = pickerOverlay
        overlay?.toggle(
            id: pickerID,
            anchor: anchor,
            preferredSize: ChatFormTemporalPopover.preferredSize(for: field)
        ) {
            AnyView(ChatFormTemporalPopover(field: field, values: temporalBinding(overlay: overlay)))
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
    @Environment(\.formPickerOverlay) private var pickerOverlay

    static func preferredSize(for field: ChatForm.Field) -> CGSize {
        let width: CGFloat = switch field.timeUnits.count {
        case 1: 112
        case 2: 172
        default: 236
        }
        return CGSize(width: width, height: 236)
    }

    var body: some View {
        let _ = pickerOverlay?.revision
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(field.timeUnits.enumerated()), id: \.element) { index, unit in
                ChatFormTimeColumn(
                    unit: unit,
                    range: 0...field.maximum(at: index),
                    selected: normalizedValues[index],
                    columnHeight: 192
                ) { picked in
                    var updated = normalizedValues
                    updated[index] = picked
                    values = updated
                }
            }
        }
        .padding(12)
        .frame(width: Self.preferredSize(for: field).width)
        .fixedSize()
    }

    private var normalizedValues: [Int] {
        values.count == field.timeUnits.count ? values : field.initialTemporalValues()
    }
}

// MARK: - Time Range Field (Pure Time Window e.g. 09:00 – 18:00)

private struct ChatFormTimeRangeField: View {
    let field: ChatForm.Field
    @Binding var value: String
    let active: Bool

    @State private var draftText: String
    @State private var anchorBox = ChatBubbleAnchorBox()
    @FocusState private var inputFocused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.formPickerOverlay) private var pickerOverlay

    init(field: ChatForm.Field, value: Binding<String>, active: Bool) {
        self.field = field
        _value = value
        self.active = active
        let initial = value.wrappedValue.isEmpty ? field.initialTimeRange() : value.wrappedValue
        _draftText = State(initialValue: initial)
    }

    private var pickerID: String { "chat-form-picker-" + field.id }
    private var isPickerOpen: Bool { pickerOverlay?.isOpen(pickerID) == true }

    var body: some View {
        HStack(spacing: 6) {
            TextField(field.timeRangePlaceholder, text: $draftText,
                      prompt: Text(verbatim: field.timeRangePlaceholder).foregroundStyle(ThemeColor.kTextSubtlest))
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
                    guard active, let parsed = field.parseTimeRangeInput(newValue) else { return }
                    let formatted = field.timeRangeString(start: parsed.start, end: parsed.end)
                    if value != formatted {
                        value = formatted
                        pickerOverlay?.notifyChanged()
                    }
                }
                .onChange(of: value) { _, newValue in
                    let parsedDraft = field.parseTimeRangeInput(draftText).map {
                        field.timeRangeString(start: $0.start, end: $0.end)
                    }
                    if !newValue.isEmpty, (!inputFocused || parsedDraft != newValue) {
                        draftText = newValue
                    }
                }
                .onChange(of: active) { _, isActive in
                    if !isActive, isPickerOpen { pickerOverlay?.dismiss() }
                }
                .accessibilityLabel(field.label)
                .accessibilityIdentifier("chat-form-field-" + field.id)

            ChatFormInlinePickerIcon(
                isOpen: isPickerOpen,
                enabled: active,
                accessibilityLabel: NSLocalizedString("选择时间段", comment: ""),
                accessibilityIdentifier: pickerID
            ) {
                togglePicker()
            } icon: {
                ChatFormClockGlyph(size: 15)
            }
        }
        .settingsInputSurface(scheme: scheme, focused: inputFocused || isPickerOpen)
        .background(ChatFormControlMarker(id: "chat-form-field-" + field.id))
        .background(ChatBubbleAnchorReader(box: anchorBox).allowsHitTesting(false))
    }

    private func togglePicker() {
        commitDraft()
        inputFocused = false
        guard let anchor = anchorBox.swiftUIFrameInWindow() else { return }
        let overlay = pickerOverlay
        overlay?.toggle(
            id: pickerID,
            anchor: anchor,
            preferredSize: ChatFormTimeRangePopover.preferredSize(for: field)
        ) {
            AnyView(ChatFormTimeRangePopover(field: field, value: $value))
        }
    }

    private func commitDraft() {
        if let parsed = field.parseTimeRangeInput(draftText) {
            let formatted = field.timeRangeString(start: parsed.start, end: parsed.end)
            value = formatted
            draftText = formatted
        } else {
            draftText = value.isEmpty ? field.initialTimeRange() : value
        }
    }
}

struct ChatFormTimeRangePopover: View {
    let field: ChatForm.Field
    @Binding var value: String

    @State private var editingEnd = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.formPickerOverlay) private var pickerOverlay

    static func preferredSize(for field: ChatForm.Field) -> CGSize {
        let width: CGFloat = switch field.timeUnits.count {
        case 1: 184
        case 2: 204
        default: 248
        }
        return CGSize(width: width, height: 300)
    }

    private var currentRange: (start: [Int], end: [Int]) {
        if let parsed = field.timeRangeComponents(value) {
            return parsed
        }
        let fallback = field.initialTimeRange()
        return field.timeRangeComponents(fallback) ?? (field.initialTemporalValues(), field.initialTemporalValues())
    }

    private func applyRange(start: [Int], end: [Int]) {
        value = field.timeRangeString(start: start, end: end)
        pickerOverlay?.notifyChanged()
    }

    private func clampToTimeComponents(totalSeconds: Int) -> [Int] {
        let maxSec = 23 * 3600 + 59 * 60 + 59
        let clamped = min(max(0, totalSeconds), maxSec)
        let h = clamped / 3600
        let m = (clamped % 3600) / 60
        let s = clamped % 60
        return field.timeUnits.map { unit in
            switch unit {
            case .hour: h
            case .minute: m
            case .second: s
            }
        }
    }

    private func updateStart(unitIndex: Int, picked: Int) {
        let current = currentRange
        var start = current.start
        guard start.indices.contains(unitIndex) else { return }
        let oldDuration = max(field.temporalRank(current.end) - field.temporalRank(current.start), 3600)
        start[unitIndex] = picked
        let newStartRank = field.temporalRank(start)
        var end = clampToTimeComponents(totalSeconds: newStartRank + oldDuration)
        if field.temporalRank(end) <= newStartRank {
            end = field.timeUnits.enumerated().map { field.maximum(at: $0.offset) }
        }
        if field.temporalRank(end) > newStartRank {
            applyRange(start: start, end: end)
        }
    }

    private func updateEnd(unitIndex: Int, picked: Int) {
        let current = currentRange
        var end = current.end
        guard end.indices.contains(unitIndex) else { return }
        let oldDuration = max(field.temporalRank(current.end) - field.temporalRank(current.start), 3600)
        end[unitIndex] = picked

        let startRank = field.temporalRank(current.start)
        let endRank = field.temporalRank(end)
        if endRank > startRank {
            applyRange(start: current.start, end: end)
            return
        }

        if field.timeUnits[unitIndex] == .hour,
           let hourIdx = field.timeUnits.firstIndex(of: .hour),
           picked == current.start[hourIdx],
           let minIdx = field.timeUnits.firstIndex(of: .minute),
           current.start[minIdx] < 59 {
            var adjusted = end
            adjusted[minIdx] = min(59, current.start[minIdx] + 15)
            applyRange(start: current.start, end: adjusted)
            return
        }

        let shiftedStart = clampToTimeComponents(totalSeconds: endRank - oldDuration)
        if field.temporalRank(end) > field.temporalRank(shiftedStart) {
            applyRange(start: shiftedStart, end: end)
        }
    }

    var body: some View {
        let _ = pickerOverlay?.revision
        let range = currentRange
        let rawActive = editingEnd ? range.end : range.start
        let activeValues = rawActive.count == field.timeUnits.count ? rawActive : field.initialTemporalValues()

        VStack(spacing: 12) {
            ChatFormRangeTabs(
                startSummary: field.temporalString(range.start),
                endSummary: field.temporalString(range.end),
                editingEnd: $editingEnd
            )

            Rectangle()
                .fill(ThemeColor.kBorder.color(for: scheme))
                .frame(height: 1)

            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(field.timeUnits.enumerated()), id: \.element) { index, unit in
                    ChatFormTimeColumn(
                        unit: unit,
                        range: 0...field.maximum(at: index),
                        selected: activeValues[index],
                        columnHeight: 192
                    ) { picked in
                        if editingEnd {
                            updateEnd(unitIndex: index, picked: picked)
                        } else {
                            updateStart(unitIndex: index, picked: picked)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: Self.preferredSize(for: field).width)
        .fixedSize()
    }
}

// MARK: - Range Start / End Switcher Header

private struct ChatFormRangeTabs: View {
    let startSummary: String
    let endSummary: String
    @Binding var editingEnd: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ChatFormRangeTabPill(
                title: NSLocalizedString("开始", comment: ""),
                value: startSummary,
                active: !editingEnd,
                identifier: "chat-form-range-start"
            ) {
                if reduceMotion {
                    editingEnd = false
                } else {
                    withAnimation(.easeOut(duration: 0.14)) { editingEnd = false }
                }
            }

            Text(verbatim: "→")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ThemeColor.kTextSubtlest.color(for: scheme))
                .accessibilityHidden(true)

            ChatFormRangeTabPill(
                title: NSLocalizedString("结束", comment: ""),
                value: endSummary,
                active: editingEnd,
                identifier: "chat-form-range-end"
            ) {
                if reduceMotion {
                    editingEnd = true
                } else {
                    withAnimation(.easeOut(duration: 0.14)) { editingEnd = true }
                }
            }
        }
    }
}

private struct ChatFormRangeTabPill: View {
    let title: String
    let value: String
    let active: Bool
    let identifier: String
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    private var fill: Color {
        if active {
            return scheme == .dark ? Color.white.opacity(0.11) : Color.white.opacity(0.68)
        }
        if hovered {
            return ThemeColor.kInteractionHover.color(for: scheme)
        }
        return .clear
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        active
                            ? ThemeColor.kTextSubtle.color(for: scheme)
                            : ThemeColor.kTextSubtlest.color(for: scheme)
                    )
                Text(value)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(
                        active
                            ? ThemeColor.kText.color(for: scheme)
                            : ThemeColor.kTextSubtle.color(for: scheme)
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: shape)
            .overlay {
                if active {
                    shape.strokeBorder(ThemeColor.kBorder.color(for: scheme), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .background(ChatFormControlMarker(id: identifier))
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

private struct ChatFormTimeColumn: View {
    let unit: ChatForm.TimeUnit
    let range: ClosedRange<Int>
    let selected: Int
    var columnHeight: CGFloat = 184
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
                .frame(height: columnHeight)
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

// MARK: - Shared Form Trigger, Submit & Popover Controls

/// Prominent monochrome brand submit button matching Asky's primary controls (black-on-white / white-on-black).
private struct ChatFormSubmitButton: View {
    let title: String
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ChatFormMetrics.controlCornerRadius, style: .continuous)
    }

    private var backgroundFill: Color {
        if !enabled {
            return (scheme == .dark ? Color.white : Color.black).opacity(0.09)
        }
        return ThemeColor.kBackgroundPrimary.color(for: scheme).opacity(hovered ? 0.86 : 1)
    }

    private var foregroundColor: Color {
        if !enabled {
            return ThemeColor("textDisabled").color(for: scheme)
        }
        return ThemeColor("textInverted").color(for: scheme)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, 18)
                .frame(height: ChatFormMetrics.controlHeight)
                .background(backgroundFill, in: shape)
                .contentShape(shape)
        }
        .buttonStyle(ChatFormOptionButtonStyle(active: enabled, reduceMotion: reduceMotion))
        .onHover { hovered = $0 }
        .background(ChatFormControlMarker(id: "chat-form-submit"))
        .actionArrowCursor(enabled: enabled)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: hovered)
        .accessibilityLabel(title)
        .accessibilityIdentifier("chat-form-submit")
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
