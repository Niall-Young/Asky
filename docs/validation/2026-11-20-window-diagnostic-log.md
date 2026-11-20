# 仅限本机的窗口生命周期诊断日志

为定位冷启动首次打开启动器时极低频的瞬态浮窗闪现，以及重启后设置窗口偶发闪现并关闭的问题，新增了仅写本机、有大小上限、无网络上传的窗口生命周期诊断日志。

## 改动概要
- `Packages/KulaCore/Sources/ToolService/WindowDiagnosticLog.swift`：
  - 新增 `WindowDiagnosticLog`，在 `Diagnostics/window-lifecycle.log` 异步顺序写入单行结构化日志，超过 512 KiB 自动轮转至 `window-lifecycle.1.log`，无任何网络/上报能力。
  - 新增 `ToolService.sampleOnScreenWindows(near:)`，仅提取进程名（`kCGWindowOwnerName`）、是否本进程、层级、透明度与矩形范围，不读取窗口标题（`kCGWindowName`）、用户输入、查询词或文件路径。
- `App/Sources/WindowDiagnostics.swift`、`App/Sources/AskyApp.swift`、`App/Sources/WindowPresentation.swift`、`App/Sources/LauncherView.swift`：
  - 启动时绑定到 `model.store.root/Diagnostics/window-lifecycle.log`，监听 `NSWindow` 的 `didExpose` / `didBecomeKey` / `willClose`。
  - 在 `openSettings()`、`applicationShouldHandleReopen`、`WindowPresentation` 的 `show` / `didBecomeActive` / `cancelPending` 处记录窗口状态、按键事件类型/keyCode/修饰键（不记录字符）与精简调用栈。
  - 在进程首次打开启动器（`hosting == nil`）后的 `0ms` / `50ms` / `150ms` / `300ms` 采样启动器及下方 480pt 区域内的在屏窗口与 `NSApp.windows`。

## 验证记录
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（含新增 `WindowDiagnosticLog` 套件 2 项测试；全量 431 项 Swift Testing 测试与 12 项 XCTest 测试全部通过，0 失败）。
- `xcodegen generate`：成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：`BUILD SUCCEEDED`。
