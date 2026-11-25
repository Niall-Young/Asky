# 对话气泡内边距收紧与单行胶囊圆角验证

日期：2026-11-25

## 变更范围

- [AgentView.swift](../../App/Sources/AgentView.swift)：
  - 将 `AgentLayout` 调整为模块内可见，供回归测试直接复用布局常量。
  - 参照 Muse 对话气泡比例，将用户消息与 Agent 回复（含工具前置说明、通知与错误）气泡内边距统一收紧为 `messageHorizontalInset = 14 pt`、`messageVerticalInset = 9 pt`、`userMessageVerticalInset = 9 pt`（原水平 `18 pt`、Agent 垂直 `14 pt`、用户垂直 `12 pt`）。
  - 将 `bubbleCornerRadius` 从 `16 pt` 调整为 `19.5 pt`（单行文本气泡总高 `21 + 9 × 2 = 39 pt` 的精确一半），使单行气泡直接呈标准胶囊形，多行气泡、工具结果卡片与通知/错误气泡统一沿用同一 `19.5 pt` 外圆角，连续同侧气泡保持 `4 pt` 相接角与 `4 pt` 间距。
  - 将 `ChatTypingBubble` 内边距同步调整为水平 `14 pt`、垂直 `17 pt`（总高同为 `39 pt`），与单行回复气泡保持一致的胶囊形态。
- [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift) 与 [AgentReactionRegression.swift](../../App/Tests/AgentReactionRegression.swift)：
  - 将硬编码的旧气泡内边距（`18 / 14 / 12`、`90`、`28 / 24`）及圆角断言（`16`）改为引用 `AgentLayout`，并断言 `AgentLayout.bubbleCornerRadius == 19.5`。
- [design-system.md](../design-system.md)：
  - 记录 2026-11-25 对话气泡内边距收紧与单行胶囊圆角规则。

## 实际执行的检查

- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过（`** BUILD SUCCEEDED **`）。
- `python3 App/Tests/run-agent-reply-regression.py --bubble-chain`：通过（单元圆角/间距矩阵及真实亮/暗窗口渲染几何断言全部通过，并目视核对 `build/bubble-chain-light.png` 与 `build/bubble-chain-dark.png`）。
- `python3 App/Tests/run-agent-reply-regression.py --bubble-width-preview`：通过（短/长中文、emoji、列表基线对齐在亮/暗模式下通过）。
- `python3 App/Tests/run-agent-reply-regression.py --bubble-menu-preview`：通过（亮/暗模式下表情快捷胶囊、展开面板、更多菜单及气泡跨底边表情徽章位置全部通过，并目视核对 `build/bubble-menu-emoji-light.png` 与 `build/bubble-menu-user-more-dark.png`）。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（15 suites / 83 tests 全部通过）。

## 维护门禁结论

- `AGENTS.md: unchanged` — 仅调整聊天界面气泡内边距与外圆角常量及对应设计文档与回归断言，不改变架构边界、开发命令或持久协作规则。
- `README: unchanged` — 界面视觉样式微调，不改变 README 描述的功能范围、快捷键、安装或构建测试命令。
