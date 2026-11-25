# 设置页搜索框与单行输入控件高度对齐

## 根因

在 macOS 26/27 原生 Liquid Glass 样式下，设置页顶部栏与表单行中三类相邻控件的视觉高度存在明显落差：

- `SettingsSearchField` 与 `SettingsInputSurface` 原先使用 `28 pt` 高度并在内部绘制 `1 pt`（Retina 2 px）`strokeBorder`，浅色模式下 8% 黑色内描边把可见白色底色收缩到 `26 pt`（52 px）。
- 同行原生 `SettingsSegmentedControl`（`NSSegmentedControl` `.large` + `.capsule`）实际绘制高度为 `28 pt`（56 px）。
- 同行原生 `SettingsButton`（`NSButton` `.glass` + `.capsule` + `.large`）尽管布局约束为 `28 pt`，其内部 `_NSCoreHostingView<AppKitButton>` / `SDFLayer` 实际绘制 `29 pt`（58 px）亮玻璃主体外加 1 px 阴影缘。
- 此外，`HotKeyRecorderField` 在 `30 pt` 高度内四周留白 `2.5 pt`，实际可见胶囊高度仅 `25 pt`；`AliasKindPicker` 选项高 `22 pt` 加 `2 pt` 上下内距，总高仅 `26 pt`。

## 改动

- [SettingsStyle.swift](../../App/Sources/SettingsStyle.swift)：
  - 将 `SettingsInputHeightKey.defaultValue` 由 `28` 调整为 `29`，`SettingsInputCornerRadiusKey.defaultValue` 由 `14` 调整为 `14.5`。
  - `settingsInputChrome` 与 `SettingsInputChrome` 新增 `borderWidth: CGFloat = 1` 参数；`SettingsInputSurface` 在胶囊单行输入（`cornerRadius >= height / 2 - 0.5`）且非高对比度模式下采用 1 物理像素细描边 `max(0.5, 1 / displayScale)`（Retina 为 `0.5 pt`，1x 与高对比度保持 `1 pt`），使填充内高精确为 `28 pt`、外缘精确为 `29 pt`。
  - 通过 `settingsInputHeight` / `settingsInputCornerRadius` 覆写为 `24 pt` / `6 pt` 的 `ChatFormView` 与 `MessageCalendarEditor` 以及多行/列表输入保持原有高度与 `1 pt` 描边。
- [SettingsSearchField.swift](../../App/Sources/SettingsSearchField.swift)：
  - 移除重复的 `.padding(.horizontal, 12)`、`.frame(height: 28)` 与 `.settingsInputChrome(...)`，统一复用 `.settingsInputSurface(scheme: scheme, focused: focus.wrappedValue)`。
- [PluginSettings.swift](../../App/Sources/PluginSettings.swift)、[CommandSettings.swift](../../App/Sources/CommandSettings.swift)：
  - 移除 `SettingsSearchField` 外层覆盖性的 `.frame(height: 28)`。
- [SettingsView.swift](../../App/Sources/SettingsView.swift)：
  - 将 `HotKeyRecorder` 外框与 `HotKeyRecorderField.intrinsicContentSize` 高度由 `30` 调整为 `33`，扣除 `2.5 pt` 焦点光晕留白后可见胶囊为 `28 pt` 填充 / `29 pt` 外缘，与相邻 `恢复默认` 按钮齐平。
- [AliasSettings.swift](../../App/Sources/AliasSettings.swift)：
  - 将 `AliasKindPicker` 选项高度由 `22` 调整为 `25`（加 `2 pt` 上下内距共 `29 pt`），未聚焦描边在非高对比度下采用 `max(0.5, 1 / displayScale)`。
- [design-system.md](../design-system.md)：
  - 补充 2026-11-25 设置页单行胶囊输入、快捷键录制框与别名类型切换的高度与描边校准说明。

## 实际验证

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：91 项测试（16 个套件）全部通过。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData-settings-heights -skipPackageUpdates build`：构建成功（`BUILD SUCCEEDED`）。
- `ASKY_DERIVED_DATA=build/DerivedData-settings-heights DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-settings-regression.py --plugin-tabs -AppleLanguages "(zh-Hans)"`：通过。
- `ASKY_DERIVED_DATA=build/DerivedData-settings-heights DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-settings-regression.py`：通过。
- 新构建原生窗口实测截图视觉验收：
  - `build/plugin-tabs-zh-Hans-ai-light.png` 与 `build/plugin-tabs-zh-Hans-ai-dark.png`（`screencapture` 实拍，2x Retina）：顶部栏搜索框外缘 `58 px`（`29.0 pt`）/ 填充内高 `56 px`（`28.0 pt`），与同行 `AI 插件 | 功能插件`（`56 px` / `28.0 pt`）及 `+ 添加` 玻璃按钮（亮体 `58 px` / `29.0 pt`）上下边缘齐平，深浅模式均无裁切或重影。
  - `build/plugin-tabs-zh-Hans-add-dialog-light.png` 与 `build/plugin-tabs-zh-Hans-alias-dialog.png`（`screencapture` 实拍）：弹窗内聚焦单行输入框、`AliasKindPicker` 与相邻按钮高度一致，描边平滑。
  - `build/settings-dark-keywords.png` 与 `build/settings-dark-hotkey.png`：指令关键词编辑框与快捷键录制框均与右侧操作按钮对齐。

## 交付边界

本次仅校准设置页单行胶囊搜索框、单行输入框、快捷键录制框与别名类型切换的高度与未聚焦描边，不改动聊天表单与日程弹窗的 `24 pt` / `6 pt` 紧凑输入样式，也未替换用户已安装版本。
