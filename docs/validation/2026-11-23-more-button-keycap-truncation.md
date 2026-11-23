# 操作栏快捷键徽标截断修复验证

- 日期：2026-11-23
- 涉及文件：
  - [LauncherActions.swift](../../App/Sources/LauncherActions.swift)
  - [ClipboardWindow.swift](../../App/Sources/ClipboardWindow.swift)

## 问题与改动

- `LauncherActionKeyCap` 中的 `Text(value)` 未设置 `.lineLimit(1)` 与 `.fixedSize()`，在父 `HStack` 传入具体宽度时，`⌘ K` 会在空格处尝试折行并因 `.frame(height: 20)` 限制而被截断为 `…`。
- 为 `LauncherActionKeyCap` 添加 `.lineLimit(1)` 和 `.fixedSize()`，为 `LauncherActionLabel` 及 `ClipboardActionBar.label` 标题添加 `.lineLimit(1)`，并为 `LauncherActionBar` 与 `ClipboardActionBar` 的隐藏“更多”锚点补上 `.fixedSize()`。

## 已执行验证

1. 最小复现对照（macOS 27.0.1，`swift -e` 渲染 `ActionLabel`）：修复前在 `width: 90` 下复现 `更多 [ ... ]`；添加 `.lineLimit(1)` + `.fixedSize()` 后完整显示 `更多 [ ⌘ K ]`。
2. `xcodegen generate` + `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过（`BUILD SUCCEEDED`）。
3. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（`83 tests in 15 suites passed`）。
