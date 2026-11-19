import AppKit
import SwiftUI
import Theme

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
        VStack(alignment: .leading, spacing: 16) {
            Text(form.title).font(.system(size: 14, weight: .medium))
            ForEach(form.fields) { field in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text(field.label)
                        if field.required == true { Text(verbatim: "*").foregroundStyle(ThemeColor.kTextSubtle).accessibilityLabel(NSLocalizedString("必填", comment: "")) }
                    }
                    control(field).disabled(!active)
                }
            }
            if !form.isComplete {
                Text(NSLocalizedString("表单未生成完整，请在输入框回复。", comment: ""))
                    .font(.system(size: 12)).foregroundStyle(ThemeColor.kTextSubtle)
            } else {
                SettingsButton(NSLocalizedString("提交回复", comment: ""), action: submit)
                    .disabled(!active || !form.accepts(values))
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(ThemeColor.kText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func control(_ field: ChatForm.Field) -> some View {
        switch field.type {
        case .text:
            SettingsInputField(field.label, text: scalar(field.id))
        case .select:
            if field.allowsCustomAnswer {
                ChatCustomChoice(field: field, answer: scalar(field.id))
            } else {
                SettingsChoice(selection: scalar(field.id), options:
                    [("", NSLocalizedString("请选择", comment: ""))] + (field.options ?? []).map { ($0, $0) })
                    .accessibilityLabel(field.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .radio:
            if field.allowsCustomAnswer {
                ChatCustomChoice(field: field, answer: scalar(field.id))
            } else {
                SettingsRadioGroup(label: field.label, options: field.options ?? [], selection: scalar(field.id))
            }
        case .multi:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(field.options ?? [], id: \.self) { option in
                    SettingsCheckbox(title: option, isOn: Binding(get: { (values[field.id] ?? []).contains(option) }, set: { selected in
                        var answer = values[field.id] ?? []
                        answer.removeAll { $0 == option }
                        if selected { answer.append(option) }
                        values[field.id] = answer
                    }))
                }
            }
        case .time, .duration:
            if !active, values[field.id] == nil {
                Text(verbatim: "—").foregroundStyle(ThemeColor.kTextSubtle)
            } else {
                TimeComponentsPicker(units: field.timeUnits, values: Binding(get: {
                    field.temporalValues(values[field.id]?.first ?? "") ?? field.initialTemporalValues()
                }, set: { values[field.id] = [field.temporalString($0)] }), duration: field.type == .duration)
                    .onChange(of: active, initial: true) {
                        if active, values[field.id] == nil { values[field.id] = [field.temporalString(field.initialTemporalValues())] }
                    }
            }
        case .date:
            if !active, values[field.id] == nil {
                Text(verbatim: "—").foregroundStyle(ThemeColor.kTextSubtle)
            } else {
                CalendarDateSelection(label: field.label, usesInputSurface: true, selection: Binding(get: {
                    ChatForm.date(values[field.id]?.first ?? "") ?? Date()
                }, set: { values[field.id] = [ChatForm.dateString($0)] }))
                    .onChange(of: active, initial: true) {
                        if active, values[field.id] == nil { values[field.id] = [ChatForm.dateString(Date())] }
                    }
            }
        }
    }

    private func scalar(_ id: String) -> Binding<String> {
        Binding(get: { values[id]?.first ?? "" }, set: { values[id] = [String($0.prefix(4000))] })
    }
}

/// Keeps the custom draft while switching choices; only the active answer is submitted.
private struct ChatCustomChoice: View {
    let field: ChatForm.Field
    @Binding var answer: String
    @State private var usingCustom: Bool
    @State private var customDraft: String

    init(field: ChatForm.Field, answer: Binding<String>) {
        self.field = field
        _answer = answer
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
                SettingsRadioGroup(label: field.label, options: (field.options ?? []) + [customOption], selection: selection)
            } else {
                SettingsChoice(selection: selection, options:
                    [("", NSLocalizedString("请选择", comment: ""))] + ((field.options ?? []) + [customOption]).map { ($0, $0) })
                    .accessibilityLabel(field.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if usingCustom {
                SettingsInputField(NSLocalizedString("输入你的回答", comment: ""), text: Binding(get: { customDraft }, set: {
                    customDraft = String($0.prefix(4000))
                    answer = customDraft
                }))
            }
        }
    }
}
