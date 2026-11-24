import SwiftUI
import Theme
import ToolService

struct AboutSettings: View {
    @Bindable var app: AppModel
    @State private var confirmingInstall = false

    private var updater: AppUpdater { app.updater }

    var body: some View {
        SettingsForm {
            Section {
                HStack(spacing: 14) {
                    Image("AskyLogo").resizable().scaledToFit().frame(width: 40, height: 40)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "Asky").font(.title2.weight(.semibold))
                        Text(ToolService.currentAppBuild.isEmpty
                             ? String(format: NSLocalizedString("版本 %@", comment: ""), ToolService.currentAppVersion)
                             : String(format: NSLocalizedString("版本 %@（%@）", comment: ""),
                                      ToolService.currentAppVersion, ToolService.currentAppBuild))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 12)
                    SettingsButton("GitHub", assetImage: "GitHubMark") {
                        _ = ToolService.openLauncherURL(ToolService.appRepositoryURL)
                    }
                }
                .padding(.vertical, 4)
                StarRepositoryRow()
            }
            Section(NSLocalizedString("软件更新", comment: "")) {
                HStack(alignment: .center, spacing: 16) {
                    statusText
                    Spacer(minLength: 16)
                    actionArea
                }
                LabeledContent {
                    Toggle("", isOn: $app.preferences.automaticUpdates).labelsHidden()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("自动更新", comment: ""))
                        Text(NSLocalizedString("在后台下载并校验新版本，在你不使用 Asky 时静默重启完成更新，旧版本会被删除", comment: ""))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .appDialog(NSLocalizedString("立即重启以完成更新？", comment: ""), isPresented: $confirmingInstall,
                   message: NSLocalizedString("Asky 将退出，用新版本替换当前版本，然后重新打开", comment: ""),
                   buttons: [NSLocalizedString("重启并更新", comment: ""), NSLocalizedString("取消", comment: "")]) { response in
            if response == 0 { updater.restartToInstall() }
        }
    }

    @ViewBuilder private var statusText: some View {
        switch updater.status {
        case .idle: Text(NSLocalizedString("尚未检查更新", comment: "")).foregroundStyle(.secondary)
        case .checking: HStack(spacing: 8) { ProgressView().controlSize(.small); Text(NSLocalizedString("检查中…", comment: "")) }
        case .upToDate: Text(NSLocalizedString("已是最新版本", comment: "")).foregroundStyle(.secondary)
        case .available(let release):
            Text(String(format: NSLocalizedString("发现新版本 %@", comment: ""), release.version))
                .fixedSize(horizontal: false, vertical: true)
        case .downloading(_, let step): HStack(spacing: 8) { ProgressView().controlSize(.small); Text(step) }
        case .ready(let staged):
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: NSLocalizedString("新版本 %@ 已就绪", comment: ""), staged.release.version))
                Text(NSLocalizedString("将在你不使用 Asky 时自动完成更新", comment: ""))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .installing: HStack(spacing: 8) { ProgressView().controlSize(.small); Text(NSLocalizedString("正在安装…", comment: "")) }
        case .failed(let message): Text(message).foregroundStyle(ThemeColor.kTextNegative).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Release notes live beside the primary action rather than under the status text.
    private var pendingRelease: AppRelease? {
        switch updater.status {
        case .available(let release), .downloading(let release, _): release
        case .ready(let staged): staged.release
        default: nil
        }
    }

    @ViewBuilder private var actionArea: some View {
        HStack(spacing: 8) {
            if let release = pendingRelease {
                SettingsButton(NSLocalizedString("查看发布说明", comment: "")) {
                    _ = ToolService.openLauncherURL(release.pageURL)
                }
            }
            actionButton
        }
    }

    @ViewBuilder private var actionButton: some View {
        switch updater.status {
        case .available(let release):
            SettingsButton(NSLocalizedString("下载更新", comment: "")) { Task { await updater.download(release) } }
                .compatibleGlassButtonStyle(prominent: true)
        case .ready:
            SettingsButton(NSLocalizedString("立即重启", comment: "")) { confirmingInstall = true }.compatibleGlassButtonStyle(prominent: true)
        case .checking, .downloading, .installing:
            SettingsButton(NSLocalizedString("检查更新", comment: "")) {}.disabled(true)
        default:
            SettingsButton(NSLocalizedString("检查更新", comment: "")) {
                Task { await updater.check(stage: app.preferences.automaticUpdates && AppUpdater.isSupported) }
            }
        }
    }
}
