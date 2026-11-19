# 修复发送消息时气泡突然上跳再回落的一闪动画

日期：2026-11-19

## 根因

1. `App/Sources/AgentView.swift` 中持续对话容器（`.id("continuous-transcript")`）外层仍残留 `.animation(navigationAnimation, value: model.conversationID)`。每次 `model.send()` 都会创建新的 `conversationID`，导致整个 `Transcript` 滚动树被包进 0.24s 的隐式动画：
   - 当持续对话达到 120 条窗口上限、`appendTrimmed` 移除顶部最旧消息时，顶部旧消息立即移出，但 `VStack` 文档总高度 `docH` 仍在 0.24s 内缓动收缩；`alignLatestContent()` 将滚动位置贴齐动画中的 `docH` 底部，使新发送的消息瞬间向上偏移（实测在移除长回复时上跳 251–363 pt），再在 240 ms 内回落到底部。
   - 由于只有顶部被裁掉的消息高度大于新消息与加载气泡之和时才会出现明显上跳，因此表现为“不是每次都出现”。
2. 发送多行草稿（或附带引用/附件）时，`model.draft` 清空后 `Composer` 通过异步高度回调和 `onGeometryChange` 在下一帧才收缩回空输入框高度，导致发送首帧底部占位 `bottomInset` 偏大，新消息短暂上移（实测 3 行草稿上跳 31 pt）再在下一帧回落。

## 变更

- `App/Sources/AgentView.swift`
  - 移除持续对话容器上多余的 `.animation(navigationAnimation, value: model.conversationID)`，保留空会话与对话视图切换的 `.animation(navigationAnimation, value: isEmptyConversation)`。
  - 在 `AgentView` 中记录空输入框高度 `emptyComposerHeight`，当草稿、附件与引用均为空时立即使用 `effectiveComposerHeight`，并在 `Composer` 发送清空草稿的同一帧将编辑器高度复位为 28 pt。
- `App/Tests/AgentReplyRegression.swift`
  - 新增 `--send-stability` 回归检查，采样常规溢出对话、多行草稿、120 条窗口裁切及长回复后发送场景下新消息气泡的模型层与呈现层 Y 坐标，断言不再出现超过 2 pt 的向上过冲。

## 实际验证

| 检查 | 结果 |
| --- | --- |
| `python3 App/Tests/run-agent-reply-regression.py --send-stability`（修复前） | 复现：`B2/B3` 上跳 `251.0 pt`，`C1` 上跳 `363.0 pt`（240 ms 回落） |
| `python3 App/Tests/run-agent-reply-regression.py --send-stability`（修复后） | 通过：`A1`、`A2-multiline`、`B1/B2/B3-120window`、`C1-afterLongReply` 均为 `overUp = (m: 0.0, p: 0.0)` |
| `xcodegen generate` + Debug `xcodebuild -skipPackageUpdates build` | `BUILD SUCCEEDED` |
| `cd Packages/KulaCore && swift test` | 首次全量运行中 `LauncherRowPresentationTests.coldFileArtworkIsDecodedAndWarmLookupReusesIt()` 偶发失败（136/137 + 83/83 + 9/9）；单独重跑 `--filter LauncherRowPresentationTests` 3/3 通过 |
| `python3 App/Tests/run-agent-reply-regression.py --scroll-stability` | 通过 |
| `python3 App/Tests/run-agent-reply-regression.py --reading-scroll` | 通过 |
| `python3 App/Tests/run-agent-reply-regression.py --bottom-push` | 布局断言全部通过；末尾 `screencapture` 因当前非前台/锁屏会话返回 `could not create image from window` 未完成截图步骤 |
| `python3 App/Tests/run-agent-reply-regression.py --first-open-stability` | 当前会话下窗口未获焦，未通过前置 `Window must become visible and key` 断言 |
