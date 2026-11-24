# 调整设置窗口初始高度与侧栏底部留白

## 问题与修复

- 将“智能配置”拆为独立设置分组后，侧栏共有 4 组 15 项（含分组标题总高约 616 pt），而默认窗口高度 640 pt 扣除顶部工具栏安全区后可视高度仅约 588 pt，导致默认打开即出现极小幅度的多余滚动条；同时 `SettingsSidebar` 缺少底部内距，最末项“关于作者”紧贴窗口底边。
- 在 [SettingsWindow.swift](../../App/Sources/SettingsWindow.swift) 中：
  - 将 `SettingsWindow.initialSize` 从 `900 × 640` 调整为 `900 × 700`，使默认窗口可完整容纳全部侧栏分组与条目，不再出现微幅多余滚动；
  - 为 `SettingsSidebar` 内容容器补充 `.padding(.bottom, 16)`，在默认态及缩小窗口滚动到底部时均保留底部呼吸空间。
- 同步更新 [design-system.md](../design-system.md) 中的设置窗口初始尺寸说明。

## 实际验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-settings-regression.py --permissions-only` 与 `build/SettingsRegression.app/Contents/MacOS/SettingsRegression -AppleLanguages '(zh-Hans)' --permissions-only`：通过；查看实际窗口截图 `build/settings-permissions-access-light.png` 与 `build/settings-permissions-access-dark.png`（英文与简体中文），确认默认尺寸下 4 组 15 项完整显示、无多余滚动条，“关于作者”距窗口底部留白正常。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
