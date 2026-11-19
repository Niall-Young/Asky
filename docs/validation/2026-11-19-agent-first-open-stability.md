# 2026-11-19 AI 对话窗口首次打开抖动修复

## 问题现象

首次打开带有历史消息的 AI 对话窗口时，消息列表会在显示后短暂跳动一次再回到原位；关闭后再次打开不再复现。

## 根因定位

1. `NativeTranscriptScrollView.Coordinator` 首次渲染布局时，`TranscriptViewport` 默认 `readerMoved = true`、`followsLatestContent = false`，需要等 SwiftUI `.onAppear` 异步触发后才开始对齐到底部/最新回复。
2. `TranscriptDocumentView` 在 `apply(...)`、`handleRowHeightChange(...)` 与 `runPrewarmBatch()` 重新计算行高并更新 `frames` 后，`beforeMountVisibleRows` 仅处理 `restoreReadingPosition()`（依赖 `readingAnchor`），未同步执行 `alignLatestContent()` 或保留手动滚动锚点，导致可见行先随新高度偏移一帧，再在下一轮主线程异步 `updatePosition()` 中被拉回（复现测试中 `t=16ms` 出现 `288.0 pt` 跳动，`t=32ms` 回弹）。首次预热完成后高度缓存已收敛，因此后续重开不再抖动。

## 修复内容

- `App/Sources/AgentView.swift`：
  - `NativeTranscriptScrollView.Coordinator.update(...)` 首次更新时即初始化 `viewport.readerMoved = false`、`viewport.followsLatestContent = true` 与 `viewport.replyID`，使窗口在首次显示前就能同步完成对齐。
  - `TranscriptDocumentView.beforeMountVisibleRows` 同步处理 `restoreReadingPosition()` 与 `alignLatestContent()`；当用户处于手动滚动位置时，在 `handleRowHeightChange(...)` 和 `runPrewarmBatch()` 重排前后保持首个可见行的相对偏移不变。
  - `TranscriptDocumentView.ensureMarkerMounted(...)` 仅挂载目标行，避免首次对齐前多余挂载顶部行。
- `App/Tests/AgentReplyRegression.swift`：新增 `--first-open-stability` 回归测试，覆盖后台非激活与应用已激活两种首次打开路径，断言首帧已对齐且后续 40 帧采样无可见漂移。

## 验证记录

- `python3 App/Tests/run-agent-reply-regression.py --first-open-stability`：通过（修复前复现 `maxMarkerDrift=288.0`，修复后后台与前台首次打开均为 `0.0` 漂移）
- `python3 App/Tests/run-agent-reply-regression.py --window-presentation`：通过
- `python3 App/Tests/run-agent-reply-regression.py --scroll-perf`：通过（`frames=285, p50=16.67ms, p95=21.90ms`）
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过
- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：`BUILD SUCCEEDED`
