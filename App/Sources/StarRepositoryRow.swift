import AppKit
import SwiftUI
import Theme
import ToolService

/// Invites the user to star the Asky repository and shows a filled star once they have.
struct StarRepositoryRow: View {
    /// Last known star state; a GitHub CLI answer overrides it, otherwise visiting the page counts.
    @AppStorage("about.starredRepository") private var starred = false
    @State private var openedPage = false
    @State private var bounce = 0

    var body: some View {
        HStack(spacing: 14) {
            Image(mingCute: starred ? "star.fill" : "star", size: 20)
                .foregroundStyle(starred ? AnyShapeStyle(Color.yellow) : AnyShapeStyle(ThemeColor.kIconSubtle))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: bounce)
                .frame(width: 40, height: 40)
                .background(ThemeColor.kBackgroundNeutral,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(starred ? NSLocalizedString("已点亮 Star，感谢支持！", comment: "")
                             : NSLocalizedString("喜欢 Asky？去 GitHub 点个 Star", comment: ""))
                Text(starred ? NSLocalizedString("你的支持是持续更新的动力", comment: "")
                             : NSLocalizedString("Star 能让更多人发现这个项目", comment: ""))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            SettingsButton(starred ? NSLocalizedString("查看仓库", comment: "")
                                   : NSLocalizedString("去点 Star", comment: ""),
                           assetImage: "GitHubMark") {
                openedPage = true
                _ = ToolService.openLauncherURL(ToolService.appRepositoryURL)
            }
        }
        .padding(.vertical, 4)
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if openedPage { Task { await refresh() } }
        }
    }

    private func refresh() async {
        let known = await ToolService.appRepositoryStarred()
        let visited = openedPage
        openedPage = false
        let next = known ?? (starred || visited)
        guard next != starred else { return }
        withAnimation(.snappy) { starred = next }
        if next { bounce += 1 }
    }
}
