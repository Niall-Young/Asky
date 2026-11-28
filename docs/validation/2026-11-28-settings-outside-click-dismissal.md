# Settings 窗口点击外部自动关闭验证

- 日期：2026-11-28
- 范围：`App/Sources/SettingsWindow.swift`、`App/Sources/AskyApp.swift`、`App/Tests/SettingsRegression.swift`

## 变更说明

1. 在 `SettingsWindow.swift` 新增 `SettingsWindowController`，复用 `OutsideClickDismissal` 在设置窗口可见时监听窗口外点击并自动关闭窗口；同时保留 5 pt 窗口边缘缩放热区，并在存在 sheet、`NSApp.modalWindow`、`AppDialog`、子窗口或菜单追踪（`.eventTracking`）时阻止误关。
2. 在 `AskyApp.swift` 中改用 `SettingsWindowController` 管理设置窗口，并在通过快捷键、菜单栏或启动器打开启动器、剪贴板或 AI 对话时同步关闭设置窗口，避免忘记关闭设置后因应用激活重新弹出。

## 实际执行验证

- `xcodegen generate`：通过，生成 `Asky.xcodeproj`。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：`SettingsWindow.swift` 与 `AskyApp.swift` 编译通过；全量构建受工作区已有未提交改动 `App/Sources/AgentView.swift:378` 的类型检查超时阻塞（未改动该文件）。
- `Packages/KulaCore` 单元测试（`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`）：通过（91 tests in 16 suites）。
- 原生回归 `SettingsRegression --outside-click`（在不改动工作区 `AgentView.swift` / `ComposerTextEditor.swift` 的前提下以 `HEAD` 对应文件编译运行）：通过（`Settings outside-click dismissal regression passed`），覆盖点击窗口内保持打开、点击窗口外自动关闭、关闭后重新打开、以及 `AppDialog` 展示期间拦截外部点击关闭。
