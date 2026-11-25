# 2026-11-25 AI 对话双向自动滚动加载与滚动流畅度优化

## 背景与问题

在顶部「加载更早的消息」修复后，人工交互预览反馈两类体验问题：

1. **普通滚动本身偏卡顿**：实测定位到两处主因——每个未悬停气泡的 `AssistantSideActionBar` / `UserSideActionBar` 仍常驻 2–3 个带 `ActionArrowCursor` / `KeyViewProxy` / `_FocusRingView` 的隐藏按钮视图（占视口内总 NSView 约 21%），且触控板滚动经过鼠标指针下方时会连续触发 `.onHover` 动画与布局更新；同时 `TranscriptGroupWindow` 的 1 视口预取边界偏紧、滚动途中仍可能触发折叠/重建，并且 `ChatInlineText` 对无图片/无来源的普通段落也挂载了两条空 `.task(id:)`。
2. **手动点击翻页打断阅读**：用户期望滚动接近历史边界时自动加载续接，无需停下来点击「加载更早的消息」或「加载更新的消息」。

## 变更内容

- [AgentModel.swift](../../App/Sources/AgentModel.swift)
  - 新增 `AgentModel.scrollPage = 16`，为 `loadOlder(limit:)` 与 `loadNewer(limit:)` 增加可配置页大小参数（默认保持 `firstPage = 40` 以兼容现有分页语义），自动滚动加载按 16 条小步续接。
- [AgentView.swift](../../App/Sources/AgentView.swift)
  - 移除手动翻页按钮 `TranscriptPagingButton`，在 `TranscriptPosition.ObserverView.updatePosition()` 中监听距顶/距底 `<= 420 pt` 自动触发 `loadOlder(limit: scrollPage)` / `loadNewer(limit: scrollPage)`，并配合防重入冷却与滚动代数门控避免静止时循环加载；底部悬浮「回到底部」按钮保持不变。
  - 将 `TranscriptViewport` 的翻页位置保持升级为**增量补偿**（`deltaY = newDocumentY - lastObservedDocumentY`），前插/裁剪只叠加锚点自身的文档位移，不回撤用户正在进行的触控板惯性滚动。
  - 新增 `TranscriptScrollActivity` 跟踪滚动状态：隐藏态侧边操作栏不再挂载按钮、`GeometryReader`、`ActionArrowCursor` 与 `ChatBubbleAnchorReader`，滚动过程中抑制悬停浮现；`TranscriptGroupWindow` 预取边界放宽至 `max(900, 1.5× 视口)`、保留边界放宽至 `max(2400, 4× 视口)`，且滚动中暂停折叠。
- [ChatMarkdownView.swift](../../App/Sources/ChatMarkdownView.swift)
  - 拆分 `ChatInlineImageLoader` / `ChatInlineSourceLoader`，仅在存在实际图片或来源链接时挂载 `.task(id:)`。
- [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)
  - 更新 `scrollStabilityRegression` 与 `splitMultiBubbleLoadOlderRegression`：分别验证无更早消息时的恒定高度滚动、滚动到顶/底自动双向续接、跨页多气泡零漂移以及悬浮回到底部。

## 实际验证

由于工作区存在并行表单/卡片改造，原生回归采用 `build/DerivedData` 产物快照与源码快照隔离构建验证，结果如下：

| 检查 | 结果 |
| --- | --- |
| `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | 通过 |
| `AgentReplyRegression --scroll-stability` | 通过；恒定高度 7636.0 pt，自动顶/底续接与回到底部通过；跨页多气泡自动前插 `expected=-12.0 after=-12.0`，`maxInFlightDrift=0.0`，`maxFrameGap=156.2ms` |
| `AgentReplyRegression --scroll-stability --preview-macos14` | 通过；跨页多气泡自动前插 `maxInFlightDrift=0.0`，`maxFrameGap=166.4ms` |
| `AgentReplyRegression --paging` | 通过 |
| `AgentReplyRegression --reply-navigation` | 通过 |
| `AgentReplyRegression --reading-scroll` | 通过 |
| `AgentReplyRegression --restored-transcript` | 通过 |
| `AgentReplyRegression --send-stability` | 通过（6 组 `overUp=0.0`） |
| `AgentReplyRegression --copy-toast-preview` | 通过（浅色/深色悬停、更多菜单与复制提示条均正常） |
| `AgentReplyRegression --scroll-perf`（120 条富 Markdown 含列表/代码块/表格） | 通过；`totalNSViews=757`（原 `3053`）、`trackingAreas=81`（原 `367`）、`p50=16.67ms`、`p95=16.80ms`（原 `30.26ms` / 前版 `51.93ms`）、`max=62.06ms`（原 `96.00ms` / 前版 `268.20ms`）、`>33.3ms=7`（原 `13` / 前版 `27`） |

## 补充优化（滚动到边界加载节奏与加载态）

首轮自动加载实机体验反馈：距顶 `420 pt` 就中途静默前插，会让连续触控板惯性滚动在半路突然卡一下，且 `16` 条小页导致翻阅时频繁触发。随后做以下收口：

- [AgentModel.swift](../../App/Sources/AgentModel.swift)
  - 将 `AgentModel.scrollPage` 从 `16` 调整为 `24`，减少翻阅长历史时的加载次数。
- [AgentView.swift](../../App/Sources/AgentView.swift)
  - 将自动加载触发边界收紧到真正到达顶/底边缘（`autoLoadThreshold = 72 pt`），普通滚动全程零打断。
  - 新增 `TranscriptHistoryLoader` 与定高（`36 pt`）的 `TranscriptHistoryLoadingRow`：到达边界后立即在顶/底部展示轻量 `ProgressView` + 提示文案，强制保持至少 `400 ms` 的明确加载节奏并等待触控板惯性减速稳定（上限 `700 ms`）后再提交历史消息；若用户在加载前滑离边界则自动取消；加载行使用独立 `@Observable` 状态，切换旋转态不触发消息列表重绘。
- [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)
  - 补充验证中段滚动（`y = 260 pt`）不提前触发、触达顶部边缘后存在加载等待期不中途改写列表、以及 `scrollPage = 24` 下的跨页多气泡零漂移与回到底部。

### 补充验证结果

| 检查 | 结果 |
| --- | --- |
| `AgentReplyRegression --scroll-stability` | 通过；恒定高度 `7636.0 pt`，中段不提前触发、边缘延迟加载与回到底部通过；跨页多气泡自动前插 `expected=104.0 after=104.0`，`maxInFlightDrift=0.0`，`maxFrameGap=186.6ms` |
| `AgentReplyRegression --scroll-stability --preview-macos14` | 通过；跨页多气泡自动前插 `expected=104.0 after=104.0`，`maxInFlightDrift=0.0`，`maxFrameGap=323.8ms` |
| `AgentReplyRegression --scroll-perf` | 通过；`totalNSViews=757`、`trackingAreas=81`、`p50=16.67ms`、`p95=22.36ms`、`max=56.47ms`、`>33.3ms=5` |
| `AgentReplyRegression --paging` / `--reply-navigation` / `--reading-scroll` / `--send-stability` | 全部通过 |

## 边界说明

- 同步构建并启动隔离预览包 `LoadOlderPreview.app`（162 条含跨页多气泡与表格/代码块的测试数据）供人工实机触控板体验；自动化回归未替代真实 macOS 14/15 实机验收。
- `AGENTS.md`: unchanged；`README`: unchanged。本次不改变模块边界、开发命令或对外文档说明。
