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

    private var usesLargeHeadline: Bool {
        switch card.kind {
        case .calendarEvent:
            return card.headline != card.title
        case .reminder:
            return !card.title.isEmpty
        case .calendarSchedule, .reminderList:
            return true
        case .mapPlaces:
            return !card.rows.isEmpty
        default:
            return false
        }
    }

    var body: some View {
        let bubbleShape = grouping.shape(for: .leading)
        VStack(alignment: .leading, spacing: 12) {
            header
            Rectangle()
                .fill(ThemeColor.kBorder.color(for: scheme).opacity(scheme == .light ? 0.55 : 0.9))
                .frame(height: 1)

            content

            if let action = card.action {
                actionButton(action)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 360, alignment: .leading)
        .background {
            bubbleShape.fill(ThemeColor.kBackgroundNeutral)
        }
        .overlay {
            bubbleShape.strokeBorder(ThemeColor.kBorder.color(for: scheme).opacity(scheme == .light ? 0.55 : 0.85), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            DataSourceIcon(source: card.source)
                .frame(width: 18, height: 18)
            Text(card.categoryTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ThemeColor.kTextSubtle)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !card.headline.isEmpty {
                Text(card.headline)
                    .font(.system(size: usesLargeHeadline ? 22 : 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(ThemeColor.kText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !card.title.isEmpty {
                Text(card.title)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(usesLargeHeadline ? ThemeColor.kText : ThemeColor.kTextSubtle)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let subtitle = card.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(card.title.isEmpty ? ThemeColor.kTextSubtle : ThemeColor.kTextSubtlest)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !card.metadata.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(card.metadata, id: \.self) { entry in
                        Text(entry)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(ThemeColor.kTextSubtlest)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !card.rows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(card.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle()
                                .fill(ThemeColor.kBorder.color(for: scheme).opacity(scheme == .light ? 0.45 : 0.7))
                                .frame(height: 1)
                                .padding(.vertical, 8)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.title)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(ThemeColor.kText)
                                    .lineLimit(2)
                                if let sub = row.subtitle, !sub.isEmpty {
                                    Text(sub)
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(ThemeColor.kTextSubtlest)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 8)
                            if let trailing = row.trailing, !trailing.isEmpty {
                                Text(trailing)
                                    .font(.system(size: 14, weight: .regular))
                                    .monospacedDigit()
                                    .foregroundStyle(ThemeColor.kTextSubtle)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func actionButton(_ action: ToolResultCard.Action) -> some View {
        Button {
            onAction(action)
        } label: {
            Text(action.label)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(scheme == .dark ? Color.black.opacity(0.92) : Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(buttonFill)
                }
        }
        .buttonStyle(.plain)
        .onHover { actionHovered = $0 }
    }

    private var buttonFill: Color {
        if scheme == .dark {
            return Color.white.opacity(actionHovered ? 0.98 : 0.9)
        }
        return Color(.sRGB, red: 0.11, green: 0.115, blue: 0.13, opacity: actionHovered ? 0.92 : 0.84)
    }
}
