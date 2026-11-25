import AppKit
import Observation
import QuartzCore
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
    var isStartInPast: Bool { start <= Date() }
    var isEndBeforeStart: Bool { end <= start }

    /// Preserves the current duration (defaulting to 1 hour if invalid) when moving the start timestamp.
    func updateStart(_ newStart: Date) {
        let duration = end > start ? end.timeIntervalSince(start) : 3600
        start = newStart
        end = newStart.addingTimeInterval(duration)
    }

    func updateStartDate(_ day: Date, calendar: Calendar = .current) {
        if let updated = CalendarMonthPicker.selecting(day, preservingTimeFrom: start, calendar: calendar) {
            updateStart(updated)
        }
    }

    func updateStartTime(hour: Int, minute: Int, calendar: Calendar = .current) {
        if let updated = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start) {
            updateStart(updated)
        }
    }

    func updateEndDate(_ day: Date, calendar: Calendar = .current) {
        if let updated = CalendarMonthPicker.selecting(day, preservingTimeFrom: end, calendar: calendar) {
            end = updated
        }
    }

    func updateEndTime(hour: Int, minute: Int, calendar: Calendar = .current) {
        if let updated = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: end) {
            end = updated
        }
    }

    var formattedDuration: String? {
        let interval = end.timeIntervalSince(start)
        guard interval > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = interval >= 86400 ? [.day, .hour] : [.hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: interval)
    }
}

@MainActor @Observable
final class CalendarEditorEntranceState {
    var isPresented: Bool

    init(isPresented: Bool = true) {
        self.isPresented = isPresented
    }
}

/// Display-link driven entrance mirroring the Share window: fast ease-out alpha reveal
/// paired with a gentle upward spring while keeping the Spotlight glass window size fixed.
@MainActor
private final class CalendarWindowEntranceAnimator: NSObject {
    private static let riseDistance: CGFloat = 16
    private static let fadeDuration: Double = 0.16
    private static let reduceMotionFadeDuration: Double = 0.15
    private static let springResponse: Double = 0.30
    private static let springDamping: Double = 0.88

    private weak var window: NSWindow?
    private var link: CADisplayLink?
    private var startTime: CFTimeInterval?
    private var targetOrigin: NSPoint = .zero
    private var targetAlpha: CGFloat = 1
    private var startOffsetY: CGFloat = 0
    private var reduceMotion = false
    private var allowPositionUpdates = true
    private(set) var isUpdatingFrame = false

    func start(window: NSWindow, targetOrigin: NSPoint, targetAlpha: CGFloat, reduceMotion: Bool) {
        stop()
        self.window = window
        self.targetOrigin = targetOrigin
        self.targetAlpha = targetAlpha
        self.reduceMotion = reduceMotion
        self.allowPositionUpdates = !reduceMotion
        self.startOffsetY = reduceMotion ? 0 : -Self.riseDistance

        window.alphaValue = 0
        if allowPositionUpdates {
            setOrigin(NSPoint(x: targetOrigin.x, y: targetOrigin.y + startOffsetY), on: window)
        } else {
            setOrigin(targetOrigin, on: window)
        }

        let link = window.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func cancelPositionMotion() {
        allowPositionUpdates = false
    }

    func stop() {
        link?.invalidate()
        link = nil
        startTime = nil
        window = nil
        allowPositionUpdates = true
    }

    private func setOrigin(_ origin: NSPoint, on window: NSWindow) {
        isUpdatingFrame = true
        window.setFrameOrigin(origin)
        isUpdatingFrame = false
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let window, window.isVisible else {
            stop()
            return
        }
        let start = startTime ?? link.timestamp
        startTime = start
        let t = max(0, link.targetTimestamp - start)

        if reduceMotion {
            let u = min(1.0, t / Self.reduceMotionFadeDuration)
            let eased = 1.0 - pow(1.0 - u, 2)
            window.alphaValue = targetAlpha * CGFloat(eased)
            if u >= 1.0 {
                window.alphaValue = targetAlpha
                stop()
            }
            return
        }

        let fadeProgress = min(1.0, t / Self.fadeDuration)
        let alphaEased = 1.0 - pow(1.0 - fadeProgress, 3)
        window.alphaValue = targetAlpha * CGFloat(alphaEased)

        let omega = 2.0 * Double.pi / Self.springResponse
        let decay = Self.springDamping * omega
        let wd = omega * (1.0 - Self.springDamping * Self.springDamping).squareRoot()
        let springProgress = 1.0 - exp(-decay * t) * (cos(wd * t) + (decay / wd) * sin(wd * t))
        let remaining = abs(1.0 - springProgress) * abs(Double(startOffsetY))
        let settled = t > 1.2 || (fadeProgress >= 1.0 && t > Self.springResponse && remaining < 0.01)

        if allowPositionUpdates {
            if settled {
                setOrigin(targetOrigin, on: window)
            } else {
                let scale = max(1.0, Double(window.backingScaleFactor))
                let rawY = Double(targetOrigin.y) + Double(startOffsetY) * (1.0 - springProgress)
                let alignedY = (rawY * scale).rounded() / scale
                setOrigin(NSPoint(x: targetOrigin.x, y: CGFloat(alignedY)), on: window)
            }
        }

        if settled {
            window.alphaValue = targetAlpha
            stop()
        }
    }
}

@MainActor
enum MessageCalendarEditor {
    static let windowSize = NSSize(width: 448, height: 592)
    static let cornerRadius: CGFloat = 24

    static func present(_ draft: MessageCalendarDraft, calendars: [MessageCalendarChoice], source: String,
                        submit: @escaping @MainActor (MessageCalendarDraft) async -> ExecutionResult) async -> ExecutionResult? {
        let session = Session(model: MessageCalendarEditorModel(draft, calendars: calendars, source: source), submit: submit)
        return await session.present()
    }

    @MainActor private final class Session: NSObject, NSWindowDelegate {
        let model: MessageCalendarEditorModel
        let submit: @MainActor (MessageCalendarDraft) async -> ExecutionResult
        private let presentation = WindowPresentation()
        private let entranceAnimator = CalendarWindowEntranceAnimator()
        private var entranceState: CalendarEditorEntranceState?
        var window: CalendarEditorWindow?
        var continuation: CheckedContinuation<ExecutionResult?, Never>?

        init(model: MessageCalendarEditorModel,
             submit: @escaping @MainActor (MessageCalendarDraft) async -> ExecutionResult) {
            self.model = model
            self.submit = submit
        }

        func present() async -> ExecutionResult? {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                let entrance = CalendarEditorEntranceState(isPresented: reduceMotion)
                entranceState = entrance

                let view = MessageCalendarEditorView(
                    model: model,
                    entrance: entrance,
                    cancel: { [weak self] in self?.finish(nil) },
                    create: { [weak self] in Task { @MainActor in await self?.create() } }
                )
                let host = NSHostingView(rootView: view
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea())
                host.sizingOptions = []
                let size = MessageCalendarEditor.windowSize
                host.frame = NSRect(origin: .zero, size: size)

                let panel = CalendarEditorWindow(
                    contentRect: host.frame,
                    styleMask: [.borderless, .fullSizeContentView],
                    backing: .buffered,
                    defer: false
                )
                panel.delegate = self
                panel.onCancel = { [weak self] in self?.finish(nil) }
                panel.title = NSLocalizedString("新建日程", comment: "")
                panel.titleVisibility = .hidden
                panel.titlebarAppearsTransparent = true
                panel.isReleasedWhenClosed = false
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = true
                panel.level = .floating
                panel.hidesOnDeactivate = false
                panel.isMovableByWindowBackground = false
                panel.contentView = WindowSurface.glassContentView(host, cornerRadius: MessageCalendarEditor.cornerRadius)
                if let surface = panel.contentView {
                    WindowSurface.updateCorners(of: surface, radius: MessageCalendarEditor.cornerRadius, circular: true)
                }
                panel.center()
                let targetOrigin = panel.frame.origin
                window = panel

                presentation.show(panel, level: .floating) { [weak self] revealedWindow, targetAlpha in
                    self?.beginEntrance(
                        window: revealedWindow,
                        targetOrigin: targetOrigin,
                        targetAlpha: targetAlpha,
                        entrance: entrance
                    )
                }
            }
        }

        private func beginEntrance(
            window: NSWindow,
            targetOrigin: NSPoint,
            targetAlpha: CGFloat,
            entrance: CalendarEditorEntranceState
        ) {
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            entranceAnimator.start(
                window: window,
                targetOrigin: targetOrigin,
                targetAlpha: targetAlpha,
                reduceMotion: reduceMotion
            )
            guard !reduceMotion else {
                entrance.isPresented = true
                return
            }
            DispatchQueue.main.async { [weak self, weak entrance] in
                guard let self, let entrance, self.entranceState === entrance else { return }
                entrance.isPresented = true
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
            entranceAnimator.stop()
            entranceState = nil
            window?.delegate = nil
            window?.orderOut(nil)
            window?.alphaValue = 1
            window?.contentView = nil
            window = nil
            continuation.resume(returning: result)
        }

        func windowWillMove(_ notification: Notification) {
            if !entranceAnimator.isUpdatingFrame {
                entranceAnimator.cancelPositionMotion()
            }
        }

        func windowWillClose(_ notification: Notification) {
            finish(nil)
        }
    }
}

final class CalendarEditorWindow: NSWindow {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

struct MessageCalendarEditorView: View {
    @Bindable var model: MessageCalendarEditorModel
    var entrance: CalendarEditorEntranceState
    var cancel: () -> Void
    var create: () -> Void

    @State private var formPickerOverlay = FormPickerOverlayController()
    @FocusState private var notesFocused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        model: MessageCalendarEditorModel,
        entrance: CalendarEditorEntranceState = CalendarEditorEntranceState(isPresented: true),
        cancel: @escaping () -> Void,
        create: @escaping () -> Void
    ) {
        self.model = model
        self.entrance = entrance
        self.cancel = cancel
        self.create = create
    }

    private var revealed: Bool { entrance.isPresented || reduceMotion }
    private var fieldsEnabled: Bool { !model.saving && !model.uncertain }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 6)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: revealed)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    CalendarFormField(title: NSLocalizedString("日程标题", comment: ""), required: true) {
                        SettingsInputField(NSLocalizedString("日程标题", comment: ""), text: $model.title)
                            .background(ChatFormControlMarker(id: "calendar-editor-title"))
                            .accessibilityIdentifier("calendar-editor-title")
                    }

                    CalendarFormField(
                        title: NSLocalizedString("开始时间", comment: ""),
                        required: true,
                        trailingHint: model.isStartInPast ? NSLocalizedString("须晚于当前时间", comment: "") : nil,
                        trailingHintIsError: model.isStartInPast
                    ) {
                        HStack(spacing: 10) {
                            CalendarEditorDateField(
                                accessibilityLabel: NSLocalizedString("开始时间", comment: ""),
                                fieldID: "calendar-editor-start-date",
                                pickerID: "calendar-editor-start-date-picker",
                                date: Binding(
                                    get: { model.start },
                                    set: { model.updateStartDate($0) }
                                ),
                                active: fieldsEnabled
                            )
                            CalendarEditorTimeField(
                                accessibilityLabel: NSLocalizedString("开始时间", comment: ""),
                                fieldID: "calendar-editor-start-time",
                                pickerID: "calendar-editor-start-time-picker",
                                date: Binding(
                                    get: { model.start },
                                    set: { updated in
                                        let cal = Calendar.current
                                        model.updateStartTime(
                                            hour: cal.component(.hour, from: updated),
                                            minute: cal.component(.minute, from: updated)
                                        )
                                    }
                                ),
                                active: fieldsEnabled
                            )
                            .frame(width: 156)
                        }
                    }

                    CalendarFormField(
                        title: NSLocalizedString("结束时间", comment: ""),
                        required: true,
                        trailingHint: model.isEndBeforeStart
                            ? NSLocalizedString("须晚于开始时间", comment: "")
                            : model.formattedDuration,
                        trailingHintIsError: model.isEndBeforeStart
                    ) {
                        HStack(spacing: 10) {
                            CalendarEditorDateField(
                                accessibilityLabel: NSLocalizedString("结束时间", comment: ""),
                                fieldID: "calendar-editor-end-date",
                                pickerID: "calendar-editor-end-date-picker",
                                date: Binding(
                                    get: { model.end },
                                    set: { model.updateEndDate($0) }
                                ),
                                active: fieldsEnabled
                            )
                            CalendarEditorTimeField(
                                accessibilityLabel: NSLocalizedString("结束时间", comment: ""),
                                fieldID: "calendar-editor-end-time",
                                pickerID: "calendar-editor-end-time-picker",
                                date: Binding(
                                    get: { model.end },
                                    set: { updated in
                                        let cal = Calendar.current
                                        model.updateEndTime(
                                            hour: cal.component(.hour, from: updated),
                                            minute: cal.component(.minute, from: updated)
                                        )
                                    }
                                ),
                                active: fieldsEnabled
                            )
                            .frame(width: 156)
                        }
                    }

                    CalendarFormField(title: NSLocalizedString("地点", comment: "")) {
                        SettingsInputField(NSLocalizedString("添加地点", comment: ""), text: $model.location)
                            .background(ChatFormControlMarker(id: "calendar-editor-location"))
                            .accessibilityIdentifier("calendar-editor-location")
                    }

                    CalendarFormField(title: NSLocalizedString("目标日历", comment: "")) {
                        CalendarDestinationField(
                            selection: $model.calendarID,
                            calendars: model.calendars,
                            active: fieldsEnabled
                        )
                    }

                    CalendarFormField(title: NSLocalizedString("备注", comment: "")) {
                        TextField(
                            NSLocalizedString("添加备注", comment: ""),
                            text: $model.notes,
                            prompt: Text(NSLocalizedString("添加备注", comment: ""))
                                .foregroundStyle(ThemeColor.kTextSubtlest),
                            axis: .vertical
                        )
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .lineLimit(3...5)
                        .focused($notesFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
                        .settingsInputChrome(
                            scheme: scheme,
                            focused: notesFocused,
                            cornerRadius: ChatFormMetrics.controlCornerRadius
                        )
                        .accessibilityLabel(NSLocalizedString("备注", comment: ""))
                        .accessibilityIdentifier("calendar-editor-notes")
                    }
                }
                .disabled(!fieldsEnabled)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 10)
            .animation(
                reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.84).delay(0.02),
                value: revealed
            )

            if let error = model.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(mingCute: "exclamationmark.triangle", size: 13.5)
                        .foregroundStyle(ThemeColor.kTextNegative)
                        .padding(.top, 1.5)
                    Text(error)
                        .font(.system(size: 12.5))
                        .foregroundStyle(ThemeColor.kTextNegative)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    ThemeColor.kTextNegative.color(for: scheme).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: ChatFormMetrics.controlCornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: ChatFormMetrics.controlCornerRadius, style: .continuous)
                        .strokeBorder(ThemeColor.kTextNegative.color(for: scheme).opacity(0.24), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 8)
            }

            Rectangle()
                .fill(ThemeColor.kBorder.color(for: scheme).opacity(0.65))
                .frame(height: 1)
                .padding(.horizontal, 20)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                if model.saving {
                    ProgressView().controlSize(.small)
                }
                Button(NSLocalizedString("取消", comment: ""), action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.saving)
                    .compatibleGlassButtonStyle()
                    .accessibilityIdentifier("calendar-editor-cancel")
                Button(NSLocalizedString(model.saving ? "创建中…" : "创建", comment: ""), action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.isValid || model.saving || model.uncertain)
                    .compatibleGlassButtonStyle(prominent: true)
                    .accessibilityIdentifier("calendar-editor-create")
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 8)
            .animation(
                reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82).delay(0.04),
                value: revealed
            )
        }
        .font(.system(size: 14))
        .foregroundStyle(ThemeColor.kText)
        .frame(width: MessageCalendarEditor.windowSize.width, height: MessageCalendarEditor.windowSize.height)
        .environment(\.settingsInputHeight, ChatFormMetrics.controlHeight)
        .environment(\.settingsInputCornerRadius, ChatFormMetrics.controlCornerRadius)
        .modifier(FormPickerOverlayPresentation(controller: formPickerOverlay, topInset: 12))
        .environment(\.formPickerOverlay, formPickerOverlay)
        .windowSurfaceBackground(in: RoundedRectangle(cornerRadius: MessageCalendarEditor.cornerRadius, style: .circular))
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                Text(NSLocalizedString("新建日程", comment: ""))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ThemeColor.kText)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(.rect)
            .background(WindowDragArea())

            Button(action: cancel) {
                Image(mingCute: "xmark", size: 12.5)
                    .foregroundStyle(ThemeColor.kIcon)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(CalendarGlassCircleButtonStyle())
            .disabled(model.saving)
            .accessibilityLabel(NSLocalizedString("关闭", comment: ""))
            .accessibilityIdentifier("calendar-editor-close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }
}

private struct CalendarGlassCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .nativeGlassBackground(in: Circle(), interactive: true)
            .contentShape(.interaction, Circle())
            .glassPointerFeedback(pressed: configuration.isPressed, in: Circle())
    }
}

private struct CalendarFormField<Content: View>: View {
    let title: String
    var required: Bool = false
    var trailingHint: String? = nil
    var trailingHintIsError: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ThemeColor.kTextSubtle)
                if required {
                    Text(verbatim: "*")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ThemeColor.kTextSubtlest)
                        .accessibilityLabel(NSLocalizedString("必填", comment: ""))
                }
                Spacer(minLength: 8)
                if let trailingHint, !trailingHint.isEmpty {
                    Text(trailingHint)
                        .font(.system(size: 12, weight: trailingHintIsError ? .medium : .regular))
                        .monospacedDigit()
                        .foregroundStyle(trailingHintIsError ? ThemeColor.kTextNegative : ThemeColor.kTextSubtlest)
                        .lineLimit(1)
                }
            }
            content
        }
    }
}

private struct CalendarEditorDateField: View {
    let accessibilityLabel: String
    let fieldID: String
    let pickerID: String
    @Binding var date: Date
    let active: Bool

    @State private var draftText: String
    @State private var anchorBox = ChatBubbleAnchorBox()
    @FocusState private var inputFocused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.formPickerOverlay) private var pickerOverlay

    init(accessibilityLabel: String, fieldID: String, pickerID: String, date: Binding<Date>, active: Bool) {
        self.accessibilityLabel = accessibilityLabel
        self.fieldID = fieldID
        self.pickerID = pickerID
        _date = date
        self.active = active
        _draftText = State(initialValue: ChatForm.dateString(date.wrappedValue))
    }

    private var formattedDate: String { ChatForm.dateString(date) }
    private var isPickerOpen: Bool { pickerOverlay?.isOpen(pickerID) == true }

    private func popoverBinding(overlay: FormPickerOverlayController?) -> Binding<Date> {
        Binding(
            get: { date },
            set: { picked in
                if let preserved = CalendarMonthPicker.selecting(picked, preservingTimeFrom: date, calendar: .current) {
                    date = preserved
                    draftText = ChatForm.dateString(preserved)
                    overlay?.notifyChanged()
                }
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
                    if formatted != formattedDate {
                        date = parsed
                        pickerOverlay?.notifyChanged()
                    }
                }
                .onChange(of: formattedDate) { _, newFormatted in
                    if !inputFocused || ChatForm.parseDateInput(draftText).map(ChatForm.dateString) != newFormatted {
                        draftText = newFormatted
                    }
                }
                .onChange(of: active) { _, isActive in
                    if !isActive, isPickerOpen { pickerOverlay?.dismiss() }
                }
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(fieldID)

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
        .background(ChatFormControlMarker(id: fieldID))
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
            AnyView(ChatFormDatePopover(selection: popoverBinding(overlay: overlay)))
        }
    }

    private func commitDraft() {
        if let parsed = ChatForm.parseDateInput(draftText) {
            date = parsed
            draftText = ChatForm.dateString(parsed)
        } else {
            draftText = formattedDate
        }
    }
}

private struct CalendarEditorTimeField: View {
    private static let timeField = ChatForm.Field(
        id: "calendar-time",
        type: .time,
        label: NSLocalizedString("时间", comment: ""),
        required: true,
        options: nil,
        allowCustom: nil,
        components: [.hour, .minute],
        defaultValue: nil
    )

    let accessibilityLabel: String
    let fieldID: String
    let pickerID: String
    @Binding var date: Date
    let active: Bool

    @State private var draftText: String
    @State private var anchorBox = ChatBubbleAnchorBox()
    @FocusState private var inputFocused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.formPickerOverlay) private var pickerOverlay

    init(accessibilityLabel: String, fieldID: String, pickerID: String, date: Binding<Date>, active: Bool) {
        self.accessibilityLabel = accessibilityLabel
        self.fieldID = fieldID
        self.pickerID = pickerID
        _date = date
        self.active = active
        _draftText = State(initialValue: Self.formattedTime(date.wrappedValue))
    }

    private static func timeComponents(_ date: Date) -> [Int] {
        let cal = Calendar.current
        return [cal.component(.hour, from: date), cal.component(.minute, from: date)]
    }

    private static func formattedTime(_ date: Date) -> String {
        timeField.temporalString(timeComponents(date))
    }

    private var formattedValue: String { Self.formattedTime(date) }
    private var isPickerOpen: Bool { pickerOverlay?.isOpen(pickerID) == true }

    private func temporalBinding(overlay: FormPickerOverlayController?) -> Binding<[Int]> {
        Binding(
            get: { Self.timeComponents(date) },
            set: { numbers in
                guard numbers.count == 2,
                      let updated = Calendar.current.date(bySettingHour: numbers[0], minute: numbers[1], second: 0, of: date) else { return }
                date = updated
                draftText = Self.timeField.temporalString(numbers)
                overlay?.notifyChanged()
            }
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField(Self.timeField.temporalPlaceholder, text: $draftText,
                      prompt: Text(verbatim: Self.timeField.temporalPlaceholder).foregroundStyle(ThemeColor.kTextSubtlest))
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
                    guard active, let parsed = Self.timeField.parseTemporalInput(newValue), parsed.count == 2 else { return }
                    let formatted = Self.timeField.temporalString(parsed)
                    if formatted != formattedValue,
                       let updated = Calendar.current.date(bySettingHour: parsed[0], minute: parsed[1], second: 0, of: date) {
                        date = updated
                        pickerOverlay?.notifyChanged()
                    }
                }
                .onChange(of: formattedValue) { _, newFormatted in
                    if !inputFocused || Self.timeField.parseTemporalInput(draftText).map(Self.timeField.temporalString) != newFormatted {
                        draftText = newFormatted
                    }
                }
                .onChange(of: active) { _, isActive in
                    if !isActive, isPickerOpen { pickerOverlay?.dismiss() }
                }
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(fieldID)

            ChatFormInlinePickerIcon(
                isOpen: isPickerOpen,
                enabled: active,
                accessibilityLabel: NSLocalizedString("选择时间", comment: ""),
                accessibilityIdentifier: pickerID
            ) {
                togglePicker()
            } icon: {
                ChatFormClockGlyph(size: 15)
            }
        }
        .settingsInputSurface(scheme: scheme, focused: inputFocused || isPickerOpen)
        .background(ChatFormControlMarker(id: fieldID))
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
            preferredSize: ChatFormTemporalPopover.preferredSize(for: Self.timeField)
        ) {
            AnyView(ChatFormTemporalPopover(field: Self.timeField, values: temporalBinding(overlay: overlay)))
        }
    }

    private func commitDraft() {
        if let parsed = Self.timeField.parseTemporalInput(draftText), parsed.count == 2,
           let updated = Calendar.current.date(bySettingHour: parsed[0], minute: parsed[1], second: 0, of: date) {
            date = updated
            draftText = Self.timeField.temporalString(parsed)
        } else {
            draftText = formattedValue
        }
    }
}

private struct CalendarDestinationField: View {
    @Binding var selection: String
    let calendars: [MessageCalendarChoice]
    let active: Bool
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    var body: some View {
        CalendarDestinationPicker(selection: $selection, calendars: calendars)
            .frame(maxWidth: .infinity)
            .focused($focused)
            .disabled(!active)
            .settingsInputSurface(scheme: scheme, focused: focused)
            .background(ChatFormControlMarker(id: "calendar-editor-calendar"))
            .accessibilityIdentifier("calendar-editor-calendar")
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
    @Environment(\.isEnabled) private var enabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let select = NSPopUpButton(frame: .zero, pullsDown: false)
        select.isBordered = false
        select.focusRingType = .none
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
        select.isEnabled = enabled
        let titles = calendars.map { $0.account.isEmpty ? $0.name : "\($0.name) · \($0.account)" }
        if select.itemTitles != titles {
            select.removeAllItems()
            select.addItems(withTitles: titles)
        }
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
