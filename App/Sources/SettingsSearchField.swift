import SwiftUI

struct SettingsSearchField: View {
    @Binding var query: String
    let focus: FocusState<Bool>.Binding
    let placeholder: String
    let identifier: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Image(mingCute: "magnifyingglass").foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(NSLocalizedString(placeholder, comment: ""), text: $query)
                .textFieldStyle(.plain)
                .focused(focus)
                .accessibilityIdentifier(identifier)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(mingCute: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("清除搜索", comment: ""))
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 8)
        .frame(height: 28)
        .settingsInputChrome(scheme: scheme, focused: focus.wrappedValue, cornerRadius: 8)
    }
}
