# 菜单栏入口快捷键显示验证（2026-11-24）

## 变更范围

- [App/Sources/SettingsPreferences.swift](../../App/Sources/SettingsPreferences.swift)：为全局快捷键（启动器、剪贴板历史、AI 对话）提供 `LauncherActionShortcut` 访问器与统一的 Carbon 到 `NSEvent.ModifierFlags` 转换。
- [App/Sources/LocalShortcuts.swift](../../App/Sources/LocalShortcuts.swift)：新增 `LauncherActionShortcut.menuKeyEquivalent`，将空格、方向键、功能键与常规字符转换为原生 `NSMenuItem.keyEquivalent`。
- [App/Sources/AskyApp.swift](../../App/Sources/AskyApp.swift)：在 `menuNeedsUpdate(_:)` 中为「打开启动器」「剪贴板历史」「AI 对话」设置对应的 `keyEquivalent` 与 `keyEquivalentModifierMask`，随设置实时更新。
- [App/Tests/LocalShortcutsRegression.swift](../../App/Tests/LocalShortcutsRegression.swift)：补充全局快捷键到菜单快捷键字符与修饰键掩码映射的断言。

## 已运行验证

- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过（`BUILD SUCCEEDED`）。
- `python3 App/Tests/run-settings-regression.py --local-shortcuts`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（15 suites / 83 tests）。
