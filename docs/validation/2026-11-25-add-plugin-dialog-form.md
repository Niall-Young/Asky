# 添加插件弹窗表单统一验证（2026-11-25）

## 变更范围

- [App/Sources/PluginSettings.swift](../../App/Sources/PluginSettings.swift)：将「添加插件」弹窗宽度统一为 480 pt（与添加／编辑别名弹窗一致），将纵向无卡片表单改为与其他设置弹窗一致的 12 pt 连续圆角分组卡片（`SettingsPalette.card`）+ 左标签右输入（`SettingsTextField`）；标签精简为「仓库链接」／“Repository”，输入框占位符展示 `https://github.com/owner/repo`。
- [App/Resources/zh-Hans.lproj/Localizable.strings](../../App/Resources/zh-Hans.lproj/Localizable.strings)、[App/Resources/en.lproj/Localizable.strings](../../App/Resources/en.lproj/Localizable.strings)：将 `GitHub 仓库链接` 键更新为 `仓库链接`（中文「仓库链接」，英文 `Repository`）。
- [App/Tests/PluginSettingsRegression.swift](../../App/Tests/PluginSettingsRegression.swift)：更新添加插件弹窗的 480 pt 宽度、占位符与左标签右输入横向几何断言。
- [docs/design-system.md](../design-system.md)：同步更新 Dialog 与 Alert 章节的添加插件弹窗表单规范。

## 已运行验证

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/SettingsDialogDerivedData -skipPackageUpdates build`：通过（`BUILD SUCCEEDED`）。
- `ASKY_DERIVED_DATA=build/SettingsDialogDerivedData python3 App/Tests/run-settings-regression.py --plugin-tabs -AppleLanguages "(zh-Hans)"`：通过，并人工复核浅色／深色中文添加插件弹窗截图。
- `ASKY_DERIVED_DATA=build/SettingsDialogDerivedData python3 App/Tests/run-settings-regression.py --plugin-tabs -AppleLanguages "(en)"`：通过，并人工复核浅色／深色英文添加插件弹窗截图（标签单行、无截断，与别名与插件配置弹窗视觉一致）。
