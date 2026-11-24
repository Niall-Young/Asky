# 修复冷启动首次打开启动器时的自动填充窗口一闪

## 问题与修复

- 实机捕获 `/Applications/Asky.app`（v0.3.7）冷启动后首次打开启动器（`<Asky.LauncherPanel>`）的系统日志：输入框聚焦后，`launchd` 首次拉起 `com.apple.SafariPlatformSupport.Helper`（一次性验证码自动填充），并短暂以默认尺寸 `{302, 223}` 将 `<SPRoundedWindow>` 挂载到 `LauncherPanel` 前台，约 25ms 后收到 `{0, 0}` 更新再撤回，导致肉眼可见的瞬间闪窗。
- 在 [project.yml](../../project.yml) 的 `Asky` target `info.properties` 中添加 `NSAutoFillRequiresTextContentTypeForOneTimeCodeOnMac: true`，使 macOS 仅在显式声明 `.oneTimeCode` 的输入框上触发验证码自动填充，避免启动器、剪贴板等普通搜索输入框拉起 `SafariPlatformSupport.Helper` 与 `<SPRoundedWindow>`。

## 实际验证

- `xcodegen generate`：通过，生成 `App/Info.plist` 与 `Asky.xcodeproj`。
- `plutil -extract NSAutoFillRequiresTextContentTypeForOneTimeCodeOnMac raw App/Info.plist`：输出 `true`。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO`：构建通过。
- `plutil -extract NSAutoFillRequiresTextContentTypeForOneTimeCodeOnMac raw build/DerivedData/Build/Products/Debug/Asky.app/Contents/Info.plist`：输出 `true`。

README: unchanged — 仅在 Info.plist 中关闭普通输入框的系统验证码自动填充探测，不改变功能范围、使用流程或开发命令。
AGENTS.md: unchanged — 未引入或变更持久性协作规则与架构边界。
