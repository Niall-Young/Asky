import SwiftUI
import ToolService

/// Adds exclusions through a picker and removes them individually.
struct SettingsExclusionList: View {
    let title: String
    let selection: SettingsExclusionSelection
    @Binding var items: [String]

    var body: some View {
        SettingsEditableList(title: title, emptyText: NSLocalizedString("暂无排除项", comment: ""), items: $items) {
            await ToolService.chooseSettingsExclusion(selection)
        }
    }
}

/// Shared "title + 添加 button, items in an inset box with 删除" list used across settings.
struct SettingsEditableList: View {
    let title: String
    let emptyText: String
    var systemImage: String?
    @Binding var items: [String]
    let choose: @MainActor () async -> String?
    @State private var choosing = false
    @State private var pendingRemoval: String?
    @State private var confirmingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsListHeader(title: title) {
                SettingsButton(NSLocalizedString("添加", comment: ""), systemImage: "plus") { add() }
                    .accessibilityLabel(NSLocalizedString("添加", comment: "") + " " + title)
            }
            SettingsInsetBox {
                if items.isEmpty {
                    Text(emptyText).foregroundStyle(.secondary)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 12) {
                        Group {
                            if let systemImage { Label { Text(item) } icon: { Image(mingCute: systemImage) } } else { Text(item) }
                        }
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item)
                        .textSelection(.enabled)
                        Spacer(minLength: 12)
                        SettingsIconButton(systemImage: "trash") {
                            pendingRemoval = item
                            confirmingRemoval = true
                        }
                        .help(NSLocalizedString("删除", comment: ""))
                        .accessibilityLabel(NSLocalizedString("删除", comment: "") + " " + item)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .disabled(choosing)
        .appDialog(NSLocalizedString("删除这一项？", comment: ""), isPresented: $confirmingRemoval,
                   message: pendingRemoval ?? "",
                   buttons: [NSLocalizedString("删除", comment: ""), NSLocalizedString("取消", comment: "")]) { response in
            if response == 0, let item = pendingRemoval {
                items.removeAll { $0 == item }
            }
            pendingRemoval = nil
        }
    }

    private func add() {
        choosing = true
        Task { @MainActor in
            defer { choosing = false }
            guard let value = await choose(), !items.contains(value) else { return }
            items.append(value)
        }
    }
}

struct SettingsListHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            trailing
        }
    }
}

struct SettingsInsetBox<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsInputChrome(scheme: scheme, focused: false, cornerRadius: 8)
    }
}
