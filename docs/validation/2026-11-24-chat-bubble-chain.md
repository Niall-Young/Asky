# 2026-11-24 连续气泡链接与间距收紧验证

## 变更范围

- 在 `App/Sources/AgentView.swift` 与 `App/Sources/ToolResultCardView.swift` 中新增并接入 `ChatBubbleSide`、`ChatBubbleGrouping` 与 `ChatTranscriptBubbleLayout`，统一计算跨组与组内连续同侧气泡的连接状态、圆角与垂直间距：
  - 单条独立气泡保持四角 16 pt 全圆角。
  - 连续同侧气泡（Agent 侧含 `toolNarration`、`assistant`、原生结果卡片 `.tool`（含 `resultCard`）及紧随其后的 `ChatTypingBubble`；用户侧含连续 `.user` 气泡）之间间距收紧为 4 pt，外侧相接角改为 4 pt 圆角（首条底角、中间条顶底角、末条顶角），其余角保持 16 pt；结果卡片底色与 1 pt 边框同步使用 `grouping.shape(for: .leading)`。
  - 带 `agentReaction` 的用户消息及带权限入口的 Agent 消息在下方断开链接，带旧版上方附件卡片的用户消息在上方断开链接；`.notice`、`.error` 保持独立不参与链接；跨说话方轮次间距为 20 pt。
- 在 `App/Tests/AgentReplyRegression.swift` 中新增 `--bubble-chain` 回归检查，覆盖圆角/间距状态矩阵（含结果卡片单卡、连卡与权限入口后断开场景）与真实 `AgentWindow` 浅色/深色截图渲染及实际垂直间距校验。
- 同步更新 `docs/design-system.md`。

## 实际执行检查

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过（`** BUILD SUCCEEDED **`）。
- `python3 App/Tests/run-agent-reply-regression.py --bubble-chain`：通过，实测 `Rendered linked gaps: assistant=4.0 pt, user=4.0 pt`，并在浅色与深色实际窗口截图（`build/bubble-chain-light.png`、`build/bubble-chain-dark.png`）中目视确认连续聊天气泡以及回复气泡 + `信息草稿` 结果卡片的 4 pt 间距与自适应圆角轮廓及描边均正常。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（83 tests in 15 suites passed）。
