import AppKit
import SwiftUI
import Contracts
import Scheduler
import Theme

struct MessageCalendarChoice: Identifiable {
    let id: String
    let name: String
    let account: String
    var isDefault = false

    static func writableChoices(_ value: JSONValue?) -> [Self] {
        (value?.arrayValue ?? []).compactMap {
            guard $0["writable"]?.boolValue == true,
                  let id = $0["id"]?.stringValue, let name = $0["name"]?.stringValue else { return nil }
            return Self(id: id, name: name, account: $0["account"]?.stringValue ?? "",
                        isDefault: $0["isDefault"]?.boolValue == true)
        }
    }
}

@MainActor @Observable
final class MessageCalendarEditorModel {
    var title: String
    var start: Date
    var end: Date
    var location: String
    var notes: String
    var calendarID: String
    let calendars: [MessageCalendarChoice]
    var saving = false
    var uncertain = false
    var error: String?

    init(_ draft: MessageCalendarDraft, calendars: [MessageCalendarChoice], source: String) {
        title = draft.title
        start = draft.start
        end = draft.proposedEnd
        location = draft.location ?? ""
        notes = draft.notes ?? source
        self.calendars = calendars
        calendarID = calendars.first { $0.id == draft.calendar }?.id
            ?? calendars.first { $0.isDefault }?.id ?? calendars.first?.id ?? ""
    }

    var draft: MessageCalendarDraft {
        .init(title: title, start: start, end: end, location: location, calendar: calendarID, notes: notes)
    }
    var isValid: Bool { draft.isValid(at: Date()) && calendars.contains { $0.id == calendarID } }
}

@MainActor
enum MessageCalendarEditor {
    static func present(_ draft: MessageCalendarDraft, calendars: [MessageCalendarChoice], source: String,
                        submit: @escaping @MainActor (MessageCalendarDraft) async -> ExecutionResult) async -> ExecutionResult? {
        let session = Session(model: MessageCalendarEditorModel(draft, calendars: calendars, source: source), submit: submit)
        return await session.present()
    }

    @MainActor private final class Session {
        let model: MessageCalendarEditorModel
        let submit: @MainActor (MessageCalendarDraft) async -> ExecutionResult
        var window: EditorPanel?
        var continuation: CheckedContinuation<ExecutionResult?, Never>?

        init(model: MessageCalendarEditorModel,
             submit: @escaping @MainActor (MessageCalendarDraft) async -> ExecutionResult) {
            self.model = model
            self.submit = submit
        }

        func present() async -> ExecutionResult? {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                let view = MessageCalendarEditorView(model: model, cancel: { [weak self] in self?.finish(nil) },
                    create: { [weak self] in Task { @MainActor in await self?.create() } })
                let host = NSHostingView(rootView: view)
                host.sizingOptions = []
                let size = NSSize(width: 380, height: 480)
                host.frame = NSRect(origin: .zero, size: size)
                let panel = EditorPanel(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                panel.title = NSLocalizedString("新建日程", comment: "")
                panel.isReleasedWhenClosed = false
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.level = .floating
                panel.hidesOnDeactivate = false
                panel.isMovableByWindowBackground = true
                panel.contentView = WindowSurface.glassContentView(host, cornerRadius: 24)
                window = panel
                panel.center()
                NSApp.activate()
                panel.makeKeyAndOrderFront(nil)
            }
        }

        func create() async {
            guard model.isValid, !model.saving, !model.uncertain else { return }
            model.saving = true
            model.error = nil
            let result = await submit(model.draft)
            model.saving = false
            if result.status == .completed { finish(result) }
            else {
                model.uncertain = result.status == .pendingVerification
                model.error = model.uncertain ? NSLocalizedString("创建结果待核实，请勿重复创建。", comment: "")
                    : result.error?.message ?? NSLocalizedString("日程未创建，请重试。", comment: "")
            }
        }

        func finish(_ result: ExecutionResult?) {
            guard !model.saving, let continuation else { return }
            self.continuation = nil
            window?.orderOut(nil)
            window?.contentView = nil
            window = nil
            continuation.resume(returning: result)
        }
    }
}

private final class EditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct MessageCalendarEditorView: View {
    @Bindable var model: MessageCalendarEditorModel
    var cancel: () -> Void
    var create: () -> Void
    @State private var datePopover = false
    @State private var editingEnd = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: cancel) {
                    Image(mingCute: "xmark.circle.fill", size: 18)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).accessibilityLabel("取消").disabled(model.saving)
                Spacer()
                Text("新建日程").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Color.clear.frame(width: 18, height: 18)
            }
            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: 10) {
                        TextField("日程标题", text: $model.title)
                            .font(.system(size: 20, weight: .semibold))
                            .accessibilityLabel("日程标题")
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading).calendarEditorRow()
                        Button { datePopover = true } label: {
                            HStack(spacing: 8) {
                                Text(model.start, format: .dateTime.year().month().day())
                                Text(model.start, style: .time)
                                Text("–").foregroundStyle(.secondary)
                                if !Calendar.current.isDate(model.start, inSameDayAs: model.end) {
                                    Text(model.end, format: .dateTime.month().day())
                                }
                                Text(model.end, style: .time)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 14)).padding(14).calendarEditorRow()
                        }
                        .buttonStyle(.plain).accessibilityLabel("修改日期和时间")
                        .popover(isPresented: $datePopover) {
                            VStack(spacing: 12) {
                                Picker("时间", selection: $editingEnd) {
                                    Text("开始").tag(false)
                                    Text("结束").tag(true)
                                }.pickerStyle(.segmented).labelsHidden()
                                CalendarMonthPicker(selection: editingEnd ? $model.end : $model.start)
                                CalendarTimePicker(selection: editingEnd ? $model.end : $model.start)
                            }.frame(width: 280).padding(16).fixedSize()
                        }
                    }
                    TextField("添加地点", text: $model.location)
                        .accessibilityLabel("地点").padding(14).calendarEditorRow()
                    HStack(spacing: 10) {
                        Circle().fill(Color.accentColor).frame(width: 10, height: 10)
                        CalendarDestinationPicker(selection: $model.calendarID, calendars: model.calendars)
                            .frame(maxWidth: .infinity).frame(height: 24)
                    }.padding(12).calendarEditorRow()
                    TextField("添加备注", text: $model.notes, axis: .vertical)
                        .lineLimit(3...5).accessibilityLabel("备注")
                        .padding(14).frame(maxWidth: .infinity, alignment: .topLeading).calendarEditorRow()
                }
                .textFieldStyle(.plain)
                .disabled(model.saving || model.uncertain)
            }
            .scrollIndicators(.hidden)
            if let error = model.error {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Spacer()
                if model.saving { ProgressView().controlSize(.small) }
                Button("取消", action: cancel).keyboardShortcut(.cancelAction).disabled(model.saving)
                Button(NSLocalizedString(model.saving ? "创建中…" : "创建", comment: ""), action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.isValid || model.saving || model.uncertain)
                    .compatibleGlassButtonStyle(prominent: true)
            }.controlSize(.large)
        }
        .font(.system(size: 14))
        .padding(20)
        .frame(width: 380, height: 480)
        .windowSurfaceBackground(in: RoundedRectangle(cornerRadius: 24))
    }


}

extension View {
    func calendarEditorRow() -> some View {
        background(ThemeColor.kBackgroundNeutral.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct CalendarDestinationPicker: NSViewRepresentable {
    @Binding var selection: String
    let calendars: [MessageCalendarChoice]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let select = NSPopUpButton(frame: .zero, pullsDown: false)
        select.isBordered = false
        select.alignment = .left
        select.font = .systemFont(ofSize: 14)
        select.controlSize = .regular
        select.setContentHuggingPriority(.defaultLow, for: .horizontal)
        select.setAccessibilityLabel(NSLocalizedString("目标日历", comment: ""))
        select.addItems(withTitles: calendars.map { $0.account.isEmpty ? $0.name : "\($0.name) · \($0.account)" })
        select.target = context.coordinator
        select.action = #selector(Coordinator.changed(_:))
        return select
    }

    func updateNSView(_ select: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        if let index = calendars.firstIndex(where: { $0.id == selection }) { select.selectItem(at: index) }
    }

    @MainActor final class Coordinator: NSObject {
        var parent: CalendarDestinationPicker
        init(_ parent: CalendarDestinationPicker) { self.parent = parent }
        @objc func changed(_ select: NSPopUpButton) {
            let index = select.indexOfSelectedItem
            if parent.calendars.indices.contains(index) { parent.selection = parent.calendars[index].id }
        }
    }
}
