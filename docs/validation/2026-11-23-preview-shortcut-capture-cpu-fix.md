# 2026-11-23 PreviewShortcutCapture CPU 与 WindowServer 死循环修复验证

## 现象与根因

- 本机诊断报告 `/Library/Logs/DiagnosticReports/Asky_2026-11-23-094036_NialldeMacBook-Air.cpu_resource.diag` 与 `WindowServer_2026-11-23-094004_NialldeMacBook-Air.cpu_resource.diag` 显示，`LauncherPanel` 失焦后 1 秒内 `Asky` 持续占用 ~60% CPU、`WindowServer` 持续占用 ~80% CPU。
- 热点调用栈全部集中在 `PreviewShortcutCapture` 的 `CGEventTap` 回调：失焦调用 `CGEvent.tapEnable(tap: port, enable: false)` 后，SkyLight 派发 `.tapDisabledByUserInput`，回调再次调用 `capture.setEnabled(capture.enabled)`（即 `tapEnable(false)`），导致 `Asky` 与 `WindowServer` 之间形成无限 Mach IPC 循环。

## 修复内容

- [PreviewShortcutCapture.swift](../../Packages/KulaCore/Sources/ToolService/PreviewShortcutCapture.swift)：
  - 仅在 `type == .tapDisabledByTimeout && desiredEnabled` 时重新启用 tap，忽略 `.tapDisabledByUserInput`。
  - `setEnabled(_:)` 增加状态去重，并新增 `invalidate()` 从主 RunLoop 移除 source 并销毁 `CFMachPort`。
- [ContentPreviewWindow.swift](../../App/Sources/ContentPreviewWindow.swift)：
  - `releaseShortcut(in:)` 失焦时直接调用 `invalidate()` 并释放 `shortcutCapture`，空闲后台不再保留 `CGEventTap`。
- [PreviewShortcutCaptureTests.swift](../../Packages/KulaCore/Tests/ToolServiceTests/PreviewShortcutCaptureTests.swift)：
  - 覆盖 `.tapDisabledByUserInput`（`desiredEnabled` 为 `false`/`true`）与 `.tapDisabledByTimeout`（`desiredEnabled` 为 `false`/`true`）的恢复判定。

## 实际执行的验证

1. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PreviewShortcutCaptureTests && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
   - 结果：通过（`PreviewShortcutCaptureTests` 与完整 `KulaCore` 测试套件全部通过，exit code 0）。
2. `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`
   - 结果：通过（`** BUILD SUCCEEDED **`）。
