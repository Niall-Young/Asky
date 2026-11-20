# 2026-11-20 AI 对话窗口首次打开上下滚动修复

## 问题现象

首次打开带有历史消息（尤其是长回复或富 Markdown）的 AI 对话窗口时，消息列表会在窗口显示后发生一次可见的上下滚动跳动。

## 根因定位

1. 回退转录列表虚拟化后，`ModernTranscriptScroll` 使用 `.defaultScrollAnchor(.bottom, for: .initialOffset)` 在首帧将滚动位置锚定到最底部；但 `TranscriptViewport` 默认 `readerMoved = true`、`followsLatestContent = false`，且 `TranscriptPosition.ObserverView` 在 `viewDidMoveToWindow()` / `boundsChanged` 中仅通过 `DispatchQueue.main.async` 异步触发 `updatePosition()`，`.onAppear` 中的 `alignTranscriptContent` 也异步排入 `Task`。
2. 当窗口首次显示（`WindowPresentation.didBecomeActive()` 执行 `layoutSubtreeIfNeeded()` 与 `displayIfNeeded()` 后立即将 `alphaValue` 置为 `1`）时，若最后一条消息是长回复，首帧会先渲染在底部，随后在下一个 run loop（约 16ms 后）被 `alignLatestContent()` 向上拉回该长回复顶部（复现测试中测得 `2317.0 pt` 跳动）。
3. 在跟随最新内容期间，若文档高度因富 Markdown / 布局收敛触发 `frameDidChangeNotification`，原有的异步 `DispatchQueue.main.async` 对齐也会导致先随 `.defaultScrollAnchor(.top, for: .sizeChanges)` 偏移一帧、下一帧再被拉回。

## 修复内容

- `App/Sources/AgentView.swift`：
  - `TranscriptViewport` 新增 `prepareInitialAlignmentIfNeeded(replyID:)` 与 `isAligning` 重入保护，`alignLatestContent(layoutIfNeeded:)` 支持在 AppKit 布局/通知回调中同步对齐而不触发重入布局。
  - `TranscriptPosition` 接收 `initialReplyID`，其 `ObserverView` 在 `viewDidMoveToWindow()`、`viewDidMoveToSuperview()`、`layout()` 与 `updateNSView()` 中同步绑定滚动视图并初始化对齐；收到 `boundsDidChangeNotification` / `frameDidChangeNotification` 时在跟随状态下同步校正滚动位置，同时保留按 run loop 合并更新 `bottomState` 的优化。
  - `alignTranscriptContent` 在启动轮询 `Task` 前同步执行一次 `alignLatestContent()`。
- `App/Tests/AgentReplyRegression.swift`：
  - 扩展 `--first-open-stability` 回归测试，覆盖富 Markdown（列表、表格、代码块、公式）的短回复与长回复，在前台激活与后台非激活两种首次打开路径下均断言首帧即对齐且后续 40 帧漂移为 `0`。

## 实际验证

| 检查 | 结果 |
| --- | --- |
| `python3 App/Tests/run-agent-reply-regression.py --first-open-stability` | 通过（修复前长回复首帧跳动 `2317.0 pt`，修复后短/长回复 × 前/后台均为 `drift=0.0`） |
| `python3 App/Tests/run-agent-reply-regression.py --restored-transcript` | 通过 |
| `python3 App/Tests/run-agent-reply-regression.py --restored-transcript --restored-long-reply` | 通过 |
| `python3 App/Tests/run-agent-reply-regression.py --send-stability` | 通过 |
| `python3 App/Tests/run-agent-reply-regression.py --scroll-stability` | 通过 |
| `python3 App/Tests/run-agent-reply-regression.py --reading-scroll` | 通过 |
| `python3 App/Tests/run-agent-reply-regression.py --reply-navigation` | 通过 |
| `python3 App/Tests/run-agent-reply-regression.py --window-presentation` | 通过 |
| `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | 通过 |
| `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build` | `BUILD SUCCEEDED` |
