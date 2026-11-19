# 联网搜索来源标签缺失修复验证

日期：2026-11-19。

## 根因定位

1. 检查本地最近会话后确认，来源标签的 UI 矢量渲染本身正常（`ChatSourceBadgeAttachmentCell` 与 `ChatMarkdownView` 正常工作），问题在于模型在联网检索后的正文段落里没有输出 Markdown 链接，仅在配图下方附了 1 条 `[来源：...](url)`（该行会被 `ChatImageGalleryContent` 提入图片卡片的来源按钮，不生成正文段末来源标签）。
2. 两处提示词与尾部指令叠加导致模型省去正文链接：
   - 近期自然文风改造在 `NativeAgentPrompt.defaultSystemPrompt` 中大幅强化了“平实聊天、少格式装饰、不加粗短自然段”的约束，而原有的联网引用要求只有嵌入长段中的一句简短表述，且未说明客户端会把 Markdown 链接自动渲染为简洁的来源标签，模型容易连同来源链接一并省去。
   - `NativeRuntime` 在最终生成前追加的请求级尾部系统提示（`imageCapabilities`、`illustrationsFinished`、`webCoolingDown`）仅提醒配图附 `sourceURL` 与紧凑对比格式，未提醒正文事实段落仍需保留 Markdown 来源链接；历史会话中多次走完 `imagesOnly` 收尾的回答都出现“只有图片来源、正文 0 链接”。

## 变更

- [NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift)：
  - 强化联网事实引用说明，明确要求在依据 `web_search` / `web_read_page` 写出的关键事实段保留真实来源 Markdown 链接（如 `[来源](URL)` 或自然嵌入句中的 `[站点名](URL)`），说明客户端会自动将其渲染为简洁的来源标签、不会破坏自然聊天观感，且不能只给配图附来源。
  - 在 Markdown 格式规则段与 `imageCapabilities` 尾部能力提示中明确保留联网事实来源链接。
- [NativeRuntime.swift](../../Packages/KulaCore/Sources/AgentHost/NativeRuntime.swift)：
  - 在 `illustrationsFinished` 与 `webCoolingDown` 尾部系统提示中补充提醒：正文事实仍须在对应段落保留真实来源的 Markdown 链接，不能只给配图附来源。
- [ChatMarkdownView.swift](../../App/Sources/ChatMarkdownView.swift)：
  - 连续引用标签（如 `[来源](u1)、[来源](u2)` 或 `[1](u1) [2](u2)`）被隐藏为段末聚合标签时，一并跳过夹在两个被隐藏引用之间的纯分隔符（`、`、`,`、`;`、空格），避免正文残留多余顿号或空白。
- [NativeRuntimeTests.swift](../../Packages/KulaCore/Tests/AgentHostTests/NativeRuntimeTests.swift) 与 [agent-runtime.md](../agent-runtime.md)：补充回归单测并同步文档。

## 已执行检查

| 检查 | 结果 |
| --- | --- |
| `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | 通过（含新增 `webCitationGuidancePreservedAcrossFormattingAndTerminalImages`） |
| 真实联网模型抽测 1（`deepseek-flash` + 真实 `web_search`，复用原对比问题「Neon / Fable 5.2 / GPT-6.2 Astra」） | 生成正文包含 5 条真实来源 `[来源](URL)` 链接，分布在各事实段落 |
| 真实联网模型抽测 2（`NativeImageLiveTests`，`deepseek-flash` + 真实 `web_search`/`web_read_page` + `imagesOnly`，问题「水豚和河狸有什么区别」） | 通过（`imageOnlyCalls=2`、`images=2`、无错误），共输出 6 条 `[来源](URL)` 链接（含 4 条正文与表格内事实来源 + 2 条配图来源） |
| `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build` | 通过（`** BUILD SUCCEEDED **`） |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --sources-preview` | 通过，且目视确认 `build/sources-light.png` 中多引用段末标签间距干净、无残留分隔符 |

## 验证边界

- 真实模型抽测针对当前配置的 `deepseek-flash` 完成两题（纯文本对比与带 `imagesOnly` 配图对比）；若用户此前在设置页保存了自定义系统提示词，需自行保留或恢复默认提示词。
- 正在运行的旧 Debug 进程需重启后才会加载本次重新编译的产物。
