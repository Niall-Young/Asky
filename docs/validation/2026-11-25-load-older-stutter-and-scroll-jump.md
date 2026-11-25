# 2026-11-25 AI 对话顶部加载更早消息卡顿与滚动位置跳动修复

## 问题现象

滚动到 AI 对话顶部点击「加载更早的消息」时，主线程会出现一次明显卡顿，同时当前阅读位置发生跳动或漂移。

## 根因定位

1. **按分组锚点在跨页分条回复上漂移**：`TranscriptViewport.preserveReadingPosition` 仅记录 `transcript-group-<group.id>`（`ChatResponseGroup.id`，即 `responseID` 或其分段编号）的顶部位置，且遍历 `document.subviews` 时未按视觉纵向顺序排序、未对顶部橡皮筋回弹偏移（`bounds.minY < 0`）做夹紧。当同一轮多气泡回复被 40 条分页边界切分时，前插旧消息后更早的分条气泡会合并进同一个 `ChatResponseGroup` 顶部，导致旧锚点上移（复现中实测漂移 `+277.0 pt`）。
2. **同步恢复窗口过短且易被触控板 `.tracking` 误取消**：`TranscriptPosition.ObserverView` 的 `layout()` 与 `boundsChanged()` 未同步校正 `preserveReadingPosition` 锚点，而 `documentFrameChanged` 内重入调用 `layoutSubtreeIfNeeded()`；`.onScrollPhaseChange` 在手指仅轻触触控板（`.tracking`）时即清空翻页锚点，且旧 `anchorTask` 固定 `10 × 30 ms = 300 ms` 退出，短于富文本整页挂载耗时。
3. **单帧同步挂载整页 40 条富 Markdown 与重复测量开销**：
   - `loadOlder()` 一次性将 40 条旧消息插入非惰性 `VStack`，且每个 `TranscriptGroupWindow` 初始 `near = true`，在单个主线程布局帧内同步创建整页 `ChatMarkdownView` 与全部 `NSTextView`（162 条含列表/代码块/表格的多气泡复现场景下，单帧主线程卡顿达 `793.6–1280.7 ms`）。
   - `ChatBubble` 对每条不含表单的 AI 消息都调用 `model.formIsActive(item.id)`（线性扫描并查 SQLite），`ChatReplyView` / `ResponseGroupView` 未做等价性短路，`ChatInlineNativeText.Measurement` 的单槽宽度缓存在 SwiftUI 多宽度探测下反复失效，隐藏态侧边操作栏的 `GeometryReader` 与 `ChatBubbleAnchorReader` 持续驻留。

## 修复内容

- [AgentView.swift](../../App/Sources/AgentView.swift)
  - 锚点升级为消息级（优先 `transcript-reply-` / 补齐非用户/助手消息的 `transcript-item-`，回退 `transcript-group-`），按视觉 `minY` 排序并保留顶部 4 个候选锚点及弱引用快速 O(1) 查找；记录偏移前通过 `constrainBoundsRect` 消除顶部回弹偏移。
  - 在 `TranscriptPosition.ObserverView` 的 `documentFrameChanged`、`boundsChanged`、`layout()` 中以重入保护同步校正翻页位置；区分 `.revealReply` 与 `.preservePosition`，`.tracking` 轻触不再取消翻页位置保持，且 `anchorTask` 在分批与布局收敛后退出。
  - 新增 `TranscriptPrependPacer`：点击「加载更早的消息」后，由近及远按渲染复杂度预算分批前插旧消息，每批之间等待当轮主线程提交与一个帧间隔；若读者在分批期间开始手动滚动，每批前插前自动重锚至当前可见消息，避免拉回或跳动。
  - 为 `ChatResponseGroup` 与 `ResponseGroupView` 补齐 `Equatable`；仅含表单栅栏的消息才查询 `formIsActive` / `formAnswers`；隐藏态侧边操作栏跳过 `transcriptScroll` 坐标读取并按可见态挂载 `ChatBubbleAnchorReader`。
- [ChatMarkdownView.swift](../../App/Sources/ChatMarkdownView.swift)
  - 无公式定界符时跳过 `ChatMath.markdown` 扫描，无图片语法时跳过多余的 `MarkdownContent(...).renderMarkdown()` 往返与 `.paragraph` 二次 `AttributedString(markdown:)` 解析。
  - `ChatInlineNativeText.Measurement` 改为多宽度测量缓存（最多保留 8 组宽度结果），并在无需 `naturalWidth` 时跳过 `100_000 pt` 预布局。
- [ChatForm.swift](../../App/Sources/ChatForm.swift)
  - 非流式且不含 ```` ```asky-form ```` 的文本在 `ChatFormParser.parse` 直接快速返回单段 Markdown。
- [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)
  - 在 `--scroll-stability` 中新增 `splitMultiBubbleLoadOlderRegression`，覆盖跨页切分的多气泡富 Markdown 历史向前翻页，断言 `maxInFlightDrift <= 1.0 pt`、`finalDrift <= 1.0 pt` 与单帧最大耗时受控。

## 实际验证

| 检查 | 结果 |
| --- | --- |
| `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | 通过（83 tests in 15 suites + XCTest 全部通过） |
| `cd MCPBridge && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` | 通过（6.38s） |
| `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build` | `BUILD SUCCEEDED` |
| `python3 App/Tests/run-agent-reply-regression.py --scroll-stability` | 通过；跨页多气泡富 Markdown `before=132.0 -> after=132.0`，`maxInFlightDrift=0.0`，`maxFrameGap=356.7ms`（修复前漂移 `+277.0pt`，三页峰值卡顿 `793.6–1280.7ms`） |
| `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --scroll-stability --preview-macos14` | 通过；`before=132.0 -> after=132.0`，`maxInFlightDrift=0.0`，`maxFrameGap=198.4ms` |
| `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --paging` | 通过 |
| `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --reply-navigation` | 通过 |
| `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --first-open-stability` | 通过（4 组短/长富文本 × 前/后台 `drift=0.0`） |
| `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --reading-scroll` | 通过 |
| `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --restored-transcript` | 通过 |
| `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --send-stability` | 通过（6 组 `overUp=0.0`） |
| `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --copy-toast-preview` | 通过（浅色与深色气泡悬停、更多菜单与复制提示条均正常） |
| `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --scroll-perf` | 通过；120 条富 Markdown 下 `totalNSViews` 从 `3053` 降至 `751`、`textViews` 从 `449` 降至 `89`、`trackingAreas` 从 `367` 降至 `87`，`p50=16.68ms` |
| `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --bottom-push` | 未通过（停在 `AgentReplyRegression.swift:3060` 的草稿输入框高度断言：直接赋值 `model.draft` 未驱动行内 Tag 编辑器增高，属既有无关用例，不记为通过） |

## 边界说明

- 自动化回归使用隔离临时数据库与合成事件，未替代真实触控板惯性手势或已安装应用的实机体验验收，也未在 macOS 14/15 实机上验证。
- 极端密度的全表格 + 全代码块 40 条历史页在分批加载期间仍会产生约 `200–360 ms` 的单个布局批次，但较修复前的 `794–1281 ms` 已大幅降低，且全过程阅读位置漂移保持 `0.0 pt`。
- `AGENTS.md`: unchanged；`README`: unchanged。本次为内部滚动定位与渲染性能优化，不涉及命令、模块边界或用户文档变更。
