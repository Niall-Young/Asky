# 设置居中弹窗重设计验证（2026-11-24）

## 变更范围

- [App/Sources/SettingsDialog.swift](../../App/Sources/SettingsDialog.swift)：新增共享 `SettingsDialogScaffold`、`SettingsDialogHeader`（左侧 16 pt semibold 标题 + 右侧 28 × 28 pt 原生圆形玻璃关闭按钮）与 `SettingsDialogActions`（全宽 36 pt 高、上下排列的原生胶囊按钮，主操作置顶并使用单色 `.primary` 突出样式与 Return 快捷键，取消置底并使用中性玻璃样式与 Esc 快捷键）；外壳升级为 24 pt 连续圆角与 20/18/20 pt 内距，弹窗打开时优先聚焦首个可编辑输入框。
- [App/Sources/AliasSettings.swift](../../App/Sources/AliasSettings.swift)：添加／编辑别名弹窗迁移至 `SettingsDialogScaffold`，统一顶栏与底部堆叠操作按钮。
- [App/Sources/PluginSettings.swift](../../App/Sources/PluginSettings.swift)：添加插件与插件配置弹窗迁移至 `SettingsDialogScaffold`；插件配置改用与弹窗内容区左右齐平的分组卡片（超过 5 项时内部滚动）。
- [App/Tests/PluginSettingsRegression.swift](../../App/Tests/PluginSettingsRegression.swift)：补充三个居中弹窗的 28 pt 圆形关闭按钮、点击关闭与底部全宽 36 pt 垂直堆叠按钮几何断言。
- [docs/design-system.md](../design-system.md)：同步更新 Dialog 与 Alert 章节规范。

## 已运行验证

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（XCTest 9 tests + Swift Testing 83 tests / 15 suites）。
- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/SettingsDialogDerivedData -skipPackageUpdates build`：通过（`BUILD SUCCEEDED`）。
- `ASKY_DERIVED_DATA=build/SettingsDialogDerivedData python3 App/Tests/run-settings-regression.py --plugin-tabs -AppleLanguages "(zh-Hans)"`：通过，并检查生成的浅色／深色添加插件、插件配置与添加别名弹窗截图。
- `ASKY_DERIVED_DATA=build/SettingsDialogDerivedData python3 App/Tests/run-settings-regression.py --plugin-tabs -AppleLanguages "(en)"`：通过，并检查英文界面弹窗截图。
- 活跃窗口原生 `NSButton`（`.glass` + `.capsule` + `.extraLarge` + `.primary` + `monochromeTint`）浅色与深色对比截图验证：与 SwiftUI `.glassProminent` 渲染一致，启用／禁用／取消三态层次清晰。
