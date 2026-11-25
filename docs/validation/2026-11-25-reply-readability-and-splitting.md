# 对话长回复轻层级排版、按事项分条与整轮分享验证

日期：2026-11-25

## 变更范围

- [AgentMessageSplit.swift](../../Packages/KulaCore/Sources/Contracts/AgentMessageSplit.swift)：移除按空行自动拆段兜底，改为仅按显式 `<asky-split/>` 分条，含 `asky-form` 表单时剥离标记并保持单条。
- [NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift)：补充默认篇幅直觉（250–450 字）、单主题结构化内容合并与按事项分条边界，允许长回复使用极简 `###` 分组小标题与紧凑表格，继续禁止一句一行、空洞套话标题与段首标签式加粗。
- [ChatMarkdownView.swift](../../App/Sources/ChatMarkdownView.swift)：保持 14 pt 同字号并将 Markdown 标题恢复为 `semibold` 字重与三级间距阶梯（标题段前 16 pt / 段后 6 pt、段落段后 12 pt、列表项上下 8 pt）。
- [ChatShareCard.swift](../../App/Sources/ChatShareCard.swift) 与 [AgentView.swift](../../App/Sources/AgentView.swift)：分享卡片对齐轻量标题样式（`h1` 15.5 pt semibold、`h2–h6` 14 pt semibold）；当单轮回复包含多条 `.assistant` 气泡时，通过 `ChatShareTurnText.merged(from:)` 合成整轮文本，在分享预览顶栏提供「整轮回复 / 仅此条」切换（默认整轮，单条时不显示）。
- [design-system.md](../design-system.md) 与中英文本地化字符串同步更新。

## 已执行验证

1. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` — 通过，包含更新后的 `AgentMessageSplitTests` 与 `NativeRuntimeTests`。
2. `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build` — `BUILD SUCCEEDED`。
3. `python3 App/Tests/run-agent-reply-regression.py --share-and-user-reply` — 通过（含 `ChatShareTurnText.merged` 单条/多条/跳过 `toolNarration` 断言及多条同轮窗口打开验证，并已肉眼检查新生成的浅色/深色分享卡与预览窗渲染图）。
4. `python3 App/Tests/run-agent-reply-regression.py --bubble-chain` — 通过（`Rendered linked gaps: assistant=4.0 pt, user=4.0 pt`）。
