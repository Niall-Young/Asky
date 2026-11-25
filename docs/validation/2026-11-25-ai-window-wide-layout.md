# AI 窗口宽屏内容区居中与气泡最大宽度限制验证

日期：2026-11-25。针对 AI 对话窗口在大于默认宽度（560 pt）时的内容区与消息气泡布局完成以下改动与验证：

- **核心内容区居中与最大宽度约束**（[AgentView.swift](../../App/Sources/AgentView.swift)）：
  - 在 `AgentLayout` 中统一定义内容区横向内边距 `contentHorizontalPadding = 12`、内容区最大宽度 `contentMaxWidth = 600`、默认窗口内容宽度 `defaultContentWidth = WindowMetrics.agentWidth - 24`（536 pt），以及默认窗口对应的助手气泡最大宽度 `assistantBubbleMaxWidth = 442` 与用户气泡最大宽度 `userBubbleMaxWidth = 470`。
  - `Transcript` 消息列表列与底部 `Composer` 输入区均以 `.frame(maxWidth: AgentLayout.contentMaxWidth)` 限制最大宽度并在窗口内水平居中，窗口超出 600 pt 时四周自然留白，默认 560 pt 窗口下保持原有 536 pt 宽度不变。
- **消息气泡保持默认最大宽度且不拉伸短气泡**（[AgentView.swift](../../App/Sources/AgentView.swift)）：
  - 新增 `MaxWidthLayout`，在不撑宽短消息气泡的前提下将 `.assistant`、`.toolNarration`、`.notice`、`.error` 气泡最大宽度固定为 `442 pt`、`.user` 气泡最大宽度固定为 `470 pt`（历史旧附件卡片行限制在 `536 pt` 内）。
  - 在更宽窗口中，左侧助手气泡与右侧用户气泡保持默认宽度并沿居中内容区两端自然错开。
- **新增宽屏布局回归测试**（[AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)）：
  - 新增 `--wide-window-layout` 回归用例，实测默认 560 pt 与 960 pt 窗口下的输入区宽度与居中位置、长/短用户与助手表单气泡宽度以及左右错开距离。

## 实际执行结果

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：成功（`BUILD SUCCEEDED`）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --wide-window-layout --capture-prefix build/wide-layout`：通过（`composer=528.0->592.0@midX=480.0, assistantForm=410.0->410.0@minX=196.0, userLong=438.0->438.0@maxX=764.0, stagger=66.0->130.0`）。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：全部通过（0 失败）。

## 已查看的实际窗口截图

- 默认 560 pt 窗口：[wide-layout-560.png](../../build/wide-layout-560.png)
- 宽屏 960 pt 窗口：[wide-layout-960.png](../../build/wide-layout-960.png)
