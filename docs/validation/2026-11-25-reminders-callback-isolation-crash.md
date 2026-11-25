# 2026-11-25 启动崩溃（提醒事项回调隔离）修复验证

## 问题

Debug 构建启动后 1–2 秒内退出，表现为“打开后立刻被关闭”。`~/Library/Logs/DiagnosticReports` 中 09:19、09:20、09:21 三份崩溃日志一致：

- `EXC_BREAKPOINT (SIGTRAP)`，崩溃线程 `com.apple.eventkit.reminders.search`
- 栈顶：`_dispatch_assert_queue_fail` ← `_swift_task_checkIsolatedSwift` ← `closure #1 ... in ToolService.openReminders(in:)`（`SchedulerCalendar.swift:18`）

根因：`ToolService.openReminders` 标注 `@MainActor`，传给 `EKEventStore.fetchReminders(matching:completion:)` 的 completion 闭包继承 MainActor 隔离；EventKit 在自身后台队列回调，Swift 运行时隔离断言失败。

## 变更范围

- `Packages/KulaCore/Sources/ToolService/SchedulerCalendar.swift`：completion 闭包显式标注 `@Sendable`，使其不继承 MainActor 隔离，可在 EventKit 后台队列安全执行后恢复 continuation。

## 实际执行检查

1. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（83 个测试、15 个套件，0 失败）。
2. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build -skipPackageUpdates`：通过（`** BUILD SUCCEEDED **`）。
3. `open build/DerivedData/Build/Products/Debug/Asky.app`：进程持续存活 20 秒以上；`~/Library/Logs/DiagnosticReports` 中 Asky 崩溃日志数量前后均为 9（无新增），最新一份仍是修复前 09:21 的日志。
