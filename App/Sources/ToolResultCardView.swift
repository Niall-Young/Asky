import SwiftUI
import Contracts
import Theme

/// Dedicated native result card rendered below assistant replies for completed macOS capabilities.
struct ToolResultCardView: View {
    let card: ToolResultCard
    var grouping: ChatBubbleGrouping = .solo
    var onAction: (ToolResultCard.Action) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme
    @State private var actionHovered = false

    private static let cardCornerRadius: CGFloat = 24
    private static let bodyLineHeight: CGFloat = 22
    private static let headingLineHeight: CGFloat = 24

    private var displayCard: ToolResultCard {
        card.normalizedForDisplay()
    }

    var body: some View {
        let bubbleShape = UnevenRoundedRectangle(
            cornerRadii: grouping.cornerRadii(for: .leading, outerRadius: Self.cardCornerRadius),
            style: .circular
        )
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle()
                .fill(ThemeColor.kBorder)
                .frame(height: 1)

            content
                .padding(.vertical, 12)

            if let action = displayCard.action {
                actionButton(action)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 360, alignment: .leading)
        .background {
            bubbleShape.fill(ThemeColor.kBackgroundNeutral)
        }
        .overlay {
            bubbleShape.strokeBorder(ThemeColor.kBorder.color(for: scheme).opacity(0.5), lineWidth: 1)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 4) {
            DataSourceIcon(source: displayCard.source)
                .frame(width: 24, height: 24)
            Text(displayCard.categoryTitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(ThemeColor.kText)
                .lineLimit(1)
                .frame(minHeight: Self.bodyLineHeight, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .padding(.bottom, 11)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch displayCard.kind {
        case .calendarEvent:
            calendarEventContent
        case .calendarSchedule:
            calendarScheduleContent
        case .reminder:
            reminderContent
        case .reminderList:
            reminderListContent
        case .note, .messagesDraft, .shortcut, .memory:
            summaryContent
        case .mapRoutes:
            mapRoutesContent
        case .mapPlaces:
            mapPlacesContent
        }
    }

    // MARK: - Calendar

    private var calendarEventContent: some View {
        let parts = splitSubtitleParts(displayCard.subtitle)
        let firstPart = parts.first
        let isAllDay = firstPart.map(Self.isAllDayLabel) ?? false
        let location = displayCard.metadata.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let eventTitle: String
        let timeText: String?
        let dateText: String?
        if isAllDay {
            eventTitle = displayCard.title.isEmpty ? displayCard.headline : displayCard.title
            timeText = firstPart
            dateText = displayCard.headline == eventTitle ? nil : displayCard.headline
        } else if !displayCard.title.isEmpty && displayCard.headline != displayCard.title {
            eventTitle = displayCard.title
            timeText = Self.normalizeTimeRange(displayCard.headline)
            dateText = firstPart
        } else {
            eventTitle = displayCard.title.isEmpty ? displayCard.headline : displayCard.title
            timeText = nil
            dateText = firstPart
        }

        return scheduleBlock(title: eventTitle, time: timeText, date: dateText, location: location)
    }

    private var calendarScheduleContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(displayCard.rows) { row in
                let parsed = resolveScheduleDateTime(for: row)
                scheduleBlock(
                    title: row.title,
                    time: parsed.time,
                    date: parsed.date,
                    location: row.subtitle
                )
            }
        }
    }

    // MARK: - Reminders

    @ViewBuilder
    private var reminderContent: some View {
        let parts = splitSubtitleParts(displayCard.subtitle)
        if !displayCard.title.isEmpty {
            scheduleBlock(
                title: displayCard.title,
                time: Self.normalizeTimeRange(displayCard.headline),
                date: parts.first,
                location: nil
            )
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if !displayCard.headline.isEmpty {
                    Text(displayCard.headline)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ThemeColor.kTextSubtle)
                        .lineSpacing(5)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, minHeight: Self.bodyLineHeight, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let subtitle = displayCard.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(ThemeColor.kTextSubtlest)
                        .lineSpacing(5)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, minHeight: Self.bodyLineHeight, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var reminderListContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(displayCard.rows) { row in
                let parsed = resolveReminderDateTime(for: row)
                if parsed.time != nil || parsed.date != nil {
                    scheduleBlock(
                        title: row.title,
                        time: parsed.time,
                        date: parsed.date,
                        location: nil
                    )
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ThemeColor.kTextSubtle)
                            .lineSpacing(5)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, minHeight: Self.bodyLineHeight, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let listName = row.badge, !listName.isEmpty {
                            Text(listName)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(ThemeColor.kTextSubtlest)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, minHeight: Self.bodyLineHeight, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private func scheduleBlock(title: String, time: String?, date: String?, location: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ThemeColor.kTextSubtle)
                    .lineSpacing(5)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: Self.bodyLineHeight, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let hasTime = !(time?.isEmpty ?? true)
            let hasDate = !(date?.isEmpty ?? true)
            if hasTime || hasDate {
                HStack(spacing: 8) {
                    if let time, !time.isEmpty {
                        Text(time)
                            .font(.system(size: 16, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(ThemeColor.kText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    if hasTime && hasDate {
                        verticalRule(height: 16)
                    }
                    if let date, !date.isEmpty {
                        Text(date)
                            .font(.system(size: 16, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(ThemeColor.kText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: Self.headingLineHeight)
            }

            if let location, !location.isEmpty {
                Text(location)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ThemeColor.kTextSubtlest)
                    .lineSpacing(5)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: Self.bodyLineHeight, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Summary (Notes, Messages Draft, Shortcut, Memory)

    private var summaryContent: some View {
        let rawBody = !displayCard.title.isEmpty ? displayCard.title : (displayCard.subtitle ?? "")
        let bodyText = Self.collapseLineBreaks(rawBody)
        return VStack(alignment: .leading, spacing: 4) {
            if !displayCard.headline.isEmpty {
                Text(displayCard.headline)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ThemeColor.kText)
                    .lineSpacing(4)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: Self.headingLineHeight, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !bodyText.isEmpty {
                Text(bodyText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ThemeColor.kTextSubtlest)
                    .lineSpacing(5)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: Self.bodyLineHeight, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Maps (Routes & Places)

    private var mapRoutesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            routeHeadline

            ForEach(displayCard.rows) { row in
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ThemeColor.kText)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: Self.bodyLineHeight, alignment: .leading)

                        let segments = splitSubtitleParts(row.subtitle)
                        if !segments.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                                    if index > 0 {
                                        verticalRule(height: 12)
                                    }
                                    Text(segment)
                                        .font(.system(size: 14, weight: .regular))
                                        .monospacedDigit()
                                        .foregroundStyle(ThemeColor.kTextSubtlest)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.88)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(height: Self.bodyLineHeight)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let trailing = row.trailing, !trailing.isEmpty {
                        Text(trailing)
                            .font(.system(size: 14, weight: .regular))
                            .monospacedDigit()
                            .foregroundStyle(ThemeColor.kText)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(height: Self.bodyLineHeight)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var routeHeadline: some View {
        let components = displayCard.headline.components(separatedBy: " → ")
        if components.count == 2 {
            HStack(spacing: 8) {
                Text(components[0])
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ThemeColor.kText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(NSLocalizedString("至", comment: ""))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(ThemeColor.kTextSubtlest)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(components[1])
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ThemeColor.kText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .frame(height: Self.headingLineHeight)
        } else if !displayCard.headline.isEmpty {
            Text(displayCard.headline)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ThemeColor.kText)
                .lineSpacing(4)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, minHeight: Self.headingLineHeight, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var mapPlacesContent: some View {
        let places: [(id: String, name: String, address: String?)] = {
            if !displayCard.rows.isEmpty {
                return displayCard.rows.map { ($0.id, $0.title, $0.subtitle) }
            }
            guard !displayCard.headline.isEmpty else { return [] }
            return [(displayCard.id, displayCard.headline, displayCard.subtitle)]
        }()

        return VStack(alignment: .leading, spacing: 16) {
            ForEach(places, id: \.id) { place in
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(ThemeColor.kText)
                        .lineSpacing(4)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, minHeight: Self.headingLineHeight, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let address = place.address, !address.isEmpty {
                        Text(address)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(ThemeColor.kTextSubtlest)
                            .lineSpacing(5)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, minHeight: Self.bodyLineHeight, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Action Button

    private func actionButton(_ action: ToolResultCard.Action) -> some View {
        Button {
            onAction(action)
        } label: {
            Text(action.label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(actionHovered ? ThemeColor.kText : ThemeColor.kTextSubtle)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(buttonFill)
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { actionHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: actionHovered)
    }

    private var buttonFill: Color {
        if actionHovered {
            return ThemeColor("borderIntense").color(for: scheme)
        }
        return ThemeColor("backgroundPrimarySubtle").color(for: scheme)
    }

    // MARK: - Shared Visuals & Parsing Helpers

    private func verticalRule(height: CGFloat) -> some View {
        Rectangle()
            .fill(ThemeColor("borderPrimary"))
            .frame(width: 1, height: height)
    }

    private func splitSubtitleParts(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func resolveScheduleDateTime(for row: ToolResultCard.DetailRow) -> (time: String?, date: String?) {
        if let date = row.dateLabel, !date.isEmpty {
            let rawTime = (row.badge?.isEmpty == false) ? row.badge : Self.stripLeadingShortDate(row.trailing).rest
            return (rawTime.map(Self.normalizeTimeRange), date)
        }
        let split = Self.stripLeadingShortDate(row.trailing)
        let date = split.date ?? (displayCard.headline.isEmpty ? nil : displayCard.headline)
        let time = split.rest.map(Self.normalizeTimeRange)
        return (time, date)
    }

    private func resolveReminderDateTime(for row: ToolResultCard.DetailRow) -> (time: String?, date: String?) {
        if let date = row.dateLabel, !date.isEmpty {
            let split = Self.stripLeadingShortDate(row.trailing)
            let time = (split.rest ?? row.trailing).map(Self.normalizeTimeRange)
            return (time, date)
        }
        guard let trailing = row.trailing, !trailing.isEmpty else {
            return (nil, nil)
        }
        let split = Self.stripLeadingShortDate(trailing)
        let date = split.date ?? (displayCard.headline.isEmpty ? nil : displayCard.headline)
        let time = split.rest.map(Self.normalizeTimeRange)
        return (time, date)
    }

    private static func isAllDayLabel(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == "全天" || lower == "all day"
    }

    private static func collapseLineBreaks(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeTimeRange(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("–") else { return trimmed }
        let parts = trimmed.components(separatedBy: "–").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return trimmed }
        return "\(parts[0]) - \(parts[1])"
    }

    private static let englishShortMonths: Set<String> = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    private static func stripLeadingShortDate(_ raw: String?) -> (date: String?, rest: String?) {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return (nil, nil)
        }
        // Chinese short date prefix: "11月28日 ..."
        let monthDigits = trimmed.prefix { $0.isASCII && $0.isNumber }
        if (1...2).contains(monthDigits.count),
           let month = Int(monthDigits), (1...12).contains(month) {
            let afterMonth = trimmed.dropFirst(monthDigits.count)
            if afterMonth.first == "月" {
                let afterMonthMark = afterMonth.dropFirst()
                let dayDigits = afterMonthMark.prefix { $0.isASCII && $0.isNumber }
                if (1...2).contains(dayDigits.count),
                   let day = Int(dayDigits), (1...31).contains(day) {
                    let afterDay = afterMonthMark.dropFirst(dayDigits.count)
                    if afterDay.first == "日" {
                        let dateStr = "\(month)月\(day)日"
                        let rest = String(afterDay.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                        return (dateStr, rest.isEmpty ? nil : rest)
                    }
                }
            }
        }
        // English short date prefix: "Nov 28 ..."
        let tokens = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        if tokens.count >= 2,
           englishShortMonths.contains(String(tokens[0])),
           let day = Int(tokens[1]), (1...31).contains(day) {
            let dateStr = "\(tokens[0]) \(day)"
            let rest = tokens.count == 3 ? String(tokens[2]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return (dateStr, rest.isEmpty ? nil : rest)
        }
        return (nil, trimmed)
    }
}
