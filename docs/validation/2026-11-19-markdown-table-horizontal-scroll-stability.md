# Markdown 表格横向滚动防上下抖动

## 原因与修改

在 `AgentView` 纵向对话流 `ScrollView` 内嵌套宽表 `ScrollView(.horizontal)` 时，触控板双指横向滑动过程中不可避免会夹带微小的纵向分量（或在减速、换向、触碰左右边界回弹时出现 `|dy| > |dx|`）。SwiftUI 的 `HostingScrollView` 会将这部分纵向滚轮事件透传给外层对话流 `NSScrollView`，导致整个表格随对话流上下跳动、回弹，并在抬手后触发外层纵向惯性（若 `TranscriptPosition` 仍处于自动对齐状态还会反复拉回）。此外，`ChatMarkdownTable` 先前将 `@State fade` 直接放在包裹 `content()` 的父视图中，滚动触发渐隐更新时会反复重建表格子树。

- 在 `App/Sources/ChatMarkdownView.swift` 中新增 `ChatTableScrollAxisLock` 状态机，并在 `ChatTableScrollObserver.ObserverView` 中通过窗口级 `.scrollWheel` 本地事件监听拦截命中溢出宽表的滚轮事件：
  - 当手势以横向为主时，在整个触控板手势及随后的惯性阶段锁定水平轴，复制 `CGEvent` 并将纵向轴（Axis 1）清零后直接派发给内层表格 `NSScrollView`，阻止纵向分量透传至外层对话流。
  - 当手势以纵向为主、使用纯纵向滚轮或表格未发生横向溢出时，事件原样透传，不影响外层对话流的上下滚动。
- 将边缘渐隐状态隔离到 `@MainActor @Observable` 的 `ChatTableScrollFadeState` 与独立遮罩视图 `ChatTableScrollFadeMask`，滚动更新渐隐时不再触发 `ChatMarkdownTable` 的表格内容子树重算。
- 在 `App/Tests/AgentReplyRegression.swift` 的 `--table-fade-preview` 中补充 `ChatTableScrollAxisLock` 状态转换断言，以及真实 `AgentWindowController` 对话窗口中带垂直抖动的触控板横向滑动与惯性零偏移验证（同时验证在宽表上垂直滑动仍能正常滚动外层对话流）。

## 验证

- `xcodegen generate` 与 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过（`** BUILD SUCCEEDED **`）。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（XCTest 及 15 个 Swift Testing suites 共 83 项测试全部通过）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --table-fade-preview`：通过。
  - `ChatTableScrollAxisLock` 覆盖 `(0, 0)` 起手横向手势、中途减速/反向纵向抖动、抬手惯性阶段与复位、垂直主导手势及离散滚轮，全部通过。
  - 真实 `AgentWindowController` 对话窗口复现带纵向抖动的横滚手势序列（含触碰右边界后立即带 `dy = ±3` 回滑及结束惯性），外层对话流 `contentView.bounds.origin.y` 偏移 `< 0.01 pt`（无上下抖动）；紧接着在表上做垂直滑动时，外层对话流正常向下滚动超过 `10 pt`。
  - 核对新构建窗口生成的 `build/table-fade-chat.png` 与 `build/table-fade-light-mid.png`：渐隐、边框与单元格选中能力正常。

## 文档与产物

README: unchanged。本次仅修复 Markdown 表格横向滚动稳定性，未改变构建或运行命令。
