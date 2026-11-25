# 对话气泡文案光学居中与上下内边距调整验证

日期：2026-11-25

## 根因定位

1. **文案整体偏上**：`ChatInlineNativeText.Measurement.height(for:)` 原先在 `ceil(manager.usedRect(for: container).height)` 基础上固定向底部追加 `+ 4 pt`（`textContainerInset = .zero`），且 `UserInlineMessageView` 使用 `max(22, ceil(usedRect.height) + 2)`。14 pt 中英文正文在 `17 pt` 行框内字形顶距约 `2.5 pt`、底距约 `0.5–1.0 pt`，底部额外 `+ 4 pt` 使文本视图底部净空达到 `4.5–6.0 pt`，导致单行与多行气泡中的文字视觉上整体偏上 `2.5–3.5 pt`（Retina 下 `5–7 px`）。
2. **上下内边距偏挤**：此前将 `messageVerticalInset` 与 `userMessageVerticalInset` 收紧至 `9 pt` 后，叠加上述偏上偏移，气泡顶部字形距边缘仅 `11.5 pt`（`23 px`），在多行气泡大圆角旁显得紧贴顶边。

## 变更范围

- [ChatMarkdownView.swift](../../App/Sources/ChatMarkdownView.swift)：
  - 将 `ChatInlineNativeText.Measurement.height(for:)` 调整为仅对常规正文末行（`lastLine.height < 21.5`）追加 `1.5 pt` 光学底距补偿（单行 `17.0 pt → 19.0 pt`，上下字形净空均约 `2.5 pt`）；24 pt 来源徽章等高附件末行不额外加高。
  - 将行内代码背景胶囊的上下扩展由 `-2 / +4` 调整为 `-1 / +2`，与 `19 pt` 行高精确居中且不裁切。
- [InlineTagAttachment.swift](../../App/Sources/InlineTagAttachment.swift)：
  - 将 `UserInlineMessageView.Coordinator.height(for:)` 同步改为同一末行光学补偿策略（纯文本 `19 pt`，含 22 pt 行内 Tag 时保持 `22 pt`）。
- [AgentView.swift](../../App/Sources/AgentView.swift)：
  - `AgentLayout` 气泡内边距调整为 `messageHorizontalInset = 16`、`messageVerticalInset = 12`、`userMessageVerticalInset = 12`；单行文本气泡总高 `19 + 12 × 2 = 43 pt`，`bubbleCornerRadius = 21.5` 保持单行标准胶囊外形；`ChatTypingBubble` 垂直内边距同步调整为 `19 pt`（总高 `5 + 38 = 43 pt`）。
- [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)：
  - 将 `bubbleChainRegression` 的圆角断言更新为 `21.5 pt`。
- [design-system.md](../design-system.md)：
  - 更新 2026-11-25 对话气泡内边距、文字光学居中与胶囊圆角规范。

## 实际执行的检查

- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过（`** BUILD SUCCEEDED **`）。
- `python3 App/Tests/run-agent-reply-regression.py --bubble-chain`：通过，实测亮/暗窗口渲染截图 `build/bubble-chain-light.png` 与 `build/bubble-chain-dark.png` 中用户单行气泡（高 `43 pt`）与 AI 多行气泡的字形上下可视留白均在 `14–15 pt`（偏差 ≤ 1 pt，原顶部 `11.5 pt` 偏上与发挤已消除）。
- `python3 App/Tests/run-agent-reply-regression.py --bubble-width-preview`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（XCTest 9 tests + Swift Testing 15 suites / 83 tests 全部通过）。
- 说明：`python3 App/Tests/run-agent-reply-regression.py --bubble-menu-preview` 在当前无录屏权限的终端环境下调用 `/usr/sbin/screencapture -R` 失败（`could not create image from rect`），未计为通过。

## 维护门禁结论

- `AGENTS.md: unchanged` — 仅调整聊天内联文本高度测量与气泡内边距/圆角常量及对应设计与回归测试，不改变架构边界、开发命令或持久协作规则。
- `README: unchanged` — 聊天气泡视觉对齐与内边距修复，不改变 README 描述的功能范围、快捷键、安装或构建测试命令。
