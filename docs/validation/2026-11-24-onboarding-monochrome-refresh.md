# 欢迎页轻拟态液态玻璃重设计与全局黑白主题验证（2026-11-24）

## 变更范围

- 全局黑白强调色与去除设置/欢迎页蓝色高亮：
  - 新增 [`AccentColor.colorset`](../../App/Assets.xcassets/AccentColor.colorset/Contents.json)，并在 [`project.yml`](../../project.yml) 中配置 `NSAccentColorName` 与 `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`。
  - [`SettingsStyle.swift`](../../App/Sources/SettingsStyle.swift)：新增 `SettingsPalette.monochromeTint(_:)` 与 `SettingsPalette.focusBorder(_:)`，输入框聚焦描边改用中性黑白边框。
  - [`SettingsView.swift`](../../App/Sources/SettingsView.swift)：`SettingsView` 显式应用黑白 `.tint(...)`；`HotKeyRecorderField` 录制态外圈、边框及激活修饰键/主键由 `NSColor.controlAccentColor` 改为明暗自适应中性墨色。
  - [`AuthorSettings.swift`](../../App/Sources/AuthorSettings.swift)：外链移除系统蓝色 `.link` 前景色，改为黑白正文色并保留下划线。
  - [`NativeGlassBackground.swift`](../../App/Sources/NativeGlassBackground.swift)：`CompatibleGlassButtonStyle` 的 prominent 按钮改为黑白强调色。
- 欢迎页重设计（[`OnboardingWindow.swift`](../../App/Sources/OnboardingWindow.swift)）：
  - 背景改为多光源弥散光渐变（冷雾蓝紫 + 暖珍珠桃色 + 柔和下层微光），随步骤平滑过渡，并在降低透明度/增强对比度时回退为中性不透明底。
  - 收敛字号：欢迎页主标题 20 pt / 副标题 13 pt，步骤标题 17 pt / 副标题 12.5 pt，列表标题 13 pt / 说明 11.5 pt，胶囊按钮高 34–36 pt。
  - 采用单层大圆角轻拟态液态玻璃结构（避免多层套娃边框）：仅保留 `24 pt` 连续圆角外层玻璃卡片（`OnboardingGlassCard`）与柔和顶部方向高光描边，内部列表行无独立框线、仅以 `0.75 pt` 极细分割线与悬停微亮区分；图标底座采用无框轻底（`OnboardingIconWell`），卡片内「保存并检查」改为次级磨砂胶囊，避免与底部主操作按钮争抢视觉焦点。
  - 欢迎页主按钮、进度指示器、开关与行内操作按钮全部采用黑白高对比胶囊与轻拟态玻璃质感，彻底移除蓝色高亮。

## 实际运行的检查

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`（位于 `Packages/KulaCore`）：通过。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO`：通过（`** BUILD SUCCEEDED **`）。
