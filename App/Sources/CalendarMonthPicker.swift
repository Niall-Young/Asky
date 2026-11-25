import SwiftUI
import Theme

/// A readable month grid; changing the date preserves the selected hour and minute.
struct CalendarMonthPicker: View {
    @Binding var selection: Date
    var monochrome = false
    var rangeStart: Date? = nil
    var rangeEnd: Date? = nil
    @State private var displayedMonth: Date
    @Environment(\.colorScheme) private var scheme
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    init(selection: Binding<Date>, monochrome: Bool = false, rangeStart: Date? = nil, rangeEnd: Date? = nil) {
        _selection = selection
        self.monochrome = monochrome
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        _displayedMonth = State(initialValue: selection.wrappedValue)
    }

    private var days: [Date] {
        guard let start = calendar.dateInterval(of: .month, for: displayedMonth)?.start else { return [] }
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0 - offset, to: start) }
    }

    private var normalizedRangeDays: (start: Date, end: Date)? {
        guard let rangeStart, let rangeEnd else { return nil }
        let s = calendar.startOfDay(for: rangeStart)
        let e = calendar.startOfDay(for: rangeEnd)
        return s <= e ? (s, e) : (e, s)
    }

    var body: some View {
        let rangeDays = normalizedRangeDays
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(displayedMonth, format: .dateTime.year().month(.wide))
                    .font(.system(size: monochrome ? 14 : 16, weight: .semibold))
                    .foregroundStyle(monochrome ? ThemeColor.kText.color(for: scheme) : Color.primary)
                Spacer()
                monthButton("上一月", symbol: "chevron.left", offset: -1)
                monthButton("下一月", symbol: "chevron.right", offset: 1)
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    Text(calendar.veryShortStandaloneWeekdaySymbols[(index + calendar.firstWeekday - 1) % 7])
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(monochrome ? ThemeColor.kTextSubtlest.color(for: scheme) : Color.secondary)
                        .frame(height: 24).accessibilityHidden(true)
                }
                ForEach(days, id: \.self) { day in
                    let dayStart = calendar.startOfDay(for: day)
                    let selected = calendar.isDate(day, inSameDayAs: selection)
                    let isRangeEndpoint: Bool = {
                        guard let rangeDays, rangeDays.start != rangeDays.end else { return false }
                        return !selected && (dayStart == rangeDays.start || dayStart == rangeDays.end)
                    }()
                    let isInRange: Bool = {
                        guard let rangeDays, rangeDays.start != rangeDays.end else { return false }
                        return dayStart > rangeDays.start && dayStart < rangeDays.end
                    }()
                    let isToday = calendar.isDateInToday(day)
                    let currentMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
                    CalendarDayCell(
                        dayNumber: calendar.component(.day, from: day),
                        selected: selected,
                        isRangeEndpoint: isRangeEndpoint,
                        isInRange: isInRange,
                        isToday: isToday,
                        currentMonth: currentMonth,
                        monochrome: monochrome
                    ) {
                        if let date = Self.selecting(day, preservingTimeFrom: selection, calendar: calendar) {
                            selection = date
                        }
                    }
                    .background {
                        if monochrome && currentMonth {
                            ChatFormControlMarker(id: "chat-form-day-" + ChatForm.dateString(day))
                        }
                    }
                    .accessibilityLabel(Text(day, format: .dateTime.year().month().day().weekday(.wide)))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .onChange(of: selection) { _, date in
            if !calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month) { displayedMonth = date }
        }
    }

    private func monthButton(_ title: String, symbol: String, offset: Int) -> some View {
        CalendarMonthNavButton(title: title, symbol: symbol, monochrome: monochrome) {
            if let date = calendar.date(byAdding: .month, value: offset, to: displayedMonth) {
                displayedMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
            }
        }
    }

    static func selecting(_ day: Date, preservingTimeFrom date: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: calendar.component(.hour, from: date),
                      minute: calendar.component(.minute, from: date),
                      second: calendar.component(.second, from: date), of: day)
    }
}

private struct CalendarDayCell: View {
    let dayNumber: Int
    let selected: Bool
    let isRangeEndpoint: Bool
    let isInRange: Bool
    let isToday: Bool
    let currentMonth: Bool
    let monochrome: Bool
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme

    private var foreground: Color {
        if selected {
            return monochrome ? ThemeColor("textInverted").color(for: scheme) : .white
        }
        if isRangeEndpoint {
            return monochrome ? ThemeColor.kText.color(for: scheme) : Color.primary
        }
        if isToday {
            return monochrome ? ThemeColor.kText.color(for: scheme) : Color.accentColor
        }
        if currentMonth {
            return monochrome ? ThemeColor.kText.color(for: scheme) : Color.primary
        }
        return monochrome ? ThemeColor.kTextSubtlest.color(for: scheme).opacity(0.6) : Color.secondary.opacity(0.55)
    }

    private var circleFill: Color {
        if selected {
            return monochrome ? ThemeColor.kBackgroundPrimary.color(for: scheme) : Color.accentColor
        }
        if isRangeEndpoint {
            return scheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.14)
        }
        if hovered {
            return ThemeColor.kInteractionHover.color(for: scheme)
        }
        return .clear
    }

    private var rangeFill: Color {
        guard isInRange else { return .clear }
        return scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.065)
    }

    var body: some View {
        Button(action: action) {
            Text("\(dayNumber)")
                .font(.system(size: 13.5, weight: selected || isRangeEndpoint || (monochrome && isToday) ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background {
                    if isInRange && !hovered {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(rangeFill)
                    }
                    Circle().fill(circleFill)
                }
                .overlay {
                    if monochrome && isToday && !selected && !isRangeEndpoint {
                        Circle()
                            .strokeBorder(ThemeColor("borderPrimary").color(for: scheme), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct CalendarMonthNavButton: View {
    let title: String
    let symbol: String
    let monochrome: Bool
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(mingCute: symbol, size: 12)
                .foregroundStyle(monochrome ? ThemeColor.kIcon.color(for: scheme) : Color.primary)
                .frame(width: 28, height: 28)
                .background(hovered ? ThemeColor.kInteractionHover.color(for: scheme) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(Text(NSLocalizedString(title, comment: "")))
    }
}


/// Date-only variant of the creation dialog's date row and its existing month picker.
struct CalendarDateSelection: View {
    let label: String
    var usesInputSurface = false
    @Binding var selection: Date
    @Environment(\.colorScheme) private var scheme
    @State private var showingCalendar = false

    var body: some View {
        Button { showingCalendar = true } label: {
            if usesInputSurface {
                dateLabel.settingsInputSurface(scheme: scheme, focused: showingCalendar)
            } else {
                dateLabel.padding(14).calendarEditorRow()
            }
        }
        .buttonStyle(.plain).accessibilityLabel(label)
        .popover(isPresented: $showingCalendar) {
            CalendarMonthPicker(selection: $selection)
                .frame(width: 280).padding(16).fixedSize()
        }
    }

    private var dateLabel: some View {
        HStack(spacing: 8) {
            Text(selection, format: .dateTime.year().month().day())
            Spacer(minLength: 0)
        }
        .font(.system(size: 14))
    }

}


/// The creation dialog uses the same configurable component picker as chat forms.
struct CalendarTimePicker: View {
    @Binding var selection: Date

    var body: some View {
        TimeComponentsPicker(units: [.hour, .minute], values: Binding(get: {
            [Calendar.current.component(.hour, from: selection), Calendar.current.component(.minute, from: selection)]
        }, set: { numbers in
            if let updated = Calendar.current.date(bySettingHour: numbers[0], minute: numbers[1], second: 0, of: selection) {
                selection = updated
            }
        }))
    }
}

/// Only requested units appear. Duration's leading component may exceed a clock component's range.
struct TimeComponentsPicker: View {
    let units: [ChatForm.TimeUnit]
    @Binding var values: [Int]
    var duration = false

    var body: some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString(duration ? "时长" : "时间", comment: "")).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            ForEach(Array(units.enumerated()), id: \.element) { index, unit in
                SettingsChoice(selection: component(index), options: (0...maximum(index)).map { ($0, String(format: "%02d", $0)) })
                    .accessibilityLabel(NSLocalizedString(unit.label, comment: "")).frame(width: 60)
                Text(NSLocalizedString(unit.label, comment: "")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.controlSize(.regular)
    }

    private func maximum(_ index: Int) -> Int {
        duration && index == 0 ? 99 : units[index] == .hour ? 23 : 59
    }
    private func component(_ index: Int) -> Binding<Int> {
        Binding(get: { values.indices.contains(index) ? values[index] : 0 }, set: { value in
            var updated = values
            if updated.count != units.count { updated = Array(repeating: 0, count: units.count) }
            updated[index] = value
            values = updated
        })
    }
}
