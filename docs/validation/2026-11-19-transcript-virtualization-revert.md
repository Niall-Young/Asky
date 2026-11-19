# 回退对话转录虚拟化并优化 SwiftUI 滚动

日期：2026-11-19

## 问题

用户反馈 AI 对话界面布局变了、动画消失、生成完成后跳一下、发送消息卡顿。排查后确认与提示词拼装（`cdc7c52`、`e0b27cf`）无关：这两个提交只改动发给模型的上下文，本地数据库查询开销可忽略。真正原因是 `ddd2d1e`（虚拟化转录列表）把 SwiftUI `ScrollView` + `VStack` 换成了自写的 AppKit 列表，每行是独立的 `NSHostingController`：

- 行与行之间没有 SwiftUI 过渡，加载气泡被托管行居中；
- 生成完成时，新建一个测量用 HostingController 同步重测行高，行框直接跳到最终高度；
- 发送时，测量和整行替换都在主线程同步进行。

## 变更

- `App/Sources/AgentView.swift`
  - 撤销 `ddd2d1e` 的列表虚拟化部分、`2b60126`（基于虚拟化的首开修复），以及 `5ee6a7a` 中为虚拟化补的加载气泡对齐和标记视图。转录区重新回到一棵 SwiftUI 树，插入、加载气泡变形为回复和高度变化都恢复动画。
  - 保留 `ddd2d1e` 中与虚拟化无关的优化：`FallbackClipShape`、复制按钮和悬停状态拆分、完成时间按需刷新、Markdown 尺寸缓存与表格共享滚动监听。
  - 新增 `TranscriptGroupWindow`：距离可视区超过 3 个视口高度、持续 300ms 以上的分组，换成相同高度的占位；进入 1 个视口范围内时重新渲染。只有高度稳定 600ms 后才允许折叠，最新两组和回复跳转目标始终渲染。分组定位标记留在占位之外。
  - `matchedGeometryEffect` 只加在最新分组的最后一条回复上；回到底部按钮的状态改成独立的 `@Observable`；滚动位置回调按每个 run loop 合并一次。
  - 首次打开时初始滚动锚点改为底部，第一帧就显示最新消息，避免先停在顶部再往下跳。
- `App/Sources/GlassPointerFeedback.swift`：按压缩放改为只跟踪尺寸（`onGeometryChange`），不再用 `visualEffect`，因为它会在每次滚动偏移变化时重新执行。
- `App/Sources/ChatMarkdownView.swift`：表格渐隐遮罩用 `onGeometryChange` 跟踪宽度，替换 `GeometryReader`。
- `App/Tests/AgentReplyRegression.swift`：移除依赖虚拟化标记视图的加载气泡断言（保留截图）；`--first-open-stability` 改为按通用条件查找转录滚动视图。

## 实际验证

| 检查 | 结果 |
| --- | --- |
| `xcodegen generate` + README 中的 Debug `xcodebuild`（加 `-skipPackageUpdates`） | `BUILD SUCCEEDED` |
| `cd Packages/KulaCore && swift test` | 通过，83 tests in 15 suites |
| `--scroll-perf`（120 条、含代码块与表格），虚拟化版本 HEAD `e40465a` | p50 16.67ms，p95 22.83ms，>33.3ms 6 帧 |
| `--scroll-perf`，单纯回退（未优化） | p50 33.17ms，p95 39.68ms，每帧都超过 16.7ms，NSView 5230 个 |
| `--scroll-perf`，本次最终版本 | p50 16.67–16.68ms，p95 28.5–39.9ms（多次运行），>33.3ms 11–15 帧，NSView 416 个 |
| 默认回归、`--reply-navigation`、`--scroll-stability`、`--reading-scroll`、`--bottom-push`、`--restored-transcript`、`--paging`、`--bubble-width-preview`、`--first-open-stability`、`--header-drag`、`--table-fade-preview`、`--approval-menu-hover`、`--window-presentation` | 全部通过 |
| `--user-bubble-hover` | 失败（复制按钮悬停像素断言）。在回退前的原始 SwiftUI 版本 `ddd2d1e^` 上同样失败，不是本次引入的问题；虚拟化版本可以通过 |

## 边界说明

- 中位帧时间恢复到 60fps，但滚动进入新分组时，原生文本挂载仍会产生少量长帧，p95 高于虚拟化版本。
- 分组折叠后会丢失其中的文字选区（仅限距离可视区 3 个视口以外的分组）。
- 发送、生成完成的动画手感需要在真实使用中确认，自动化回归无法判断动画是否自然。
