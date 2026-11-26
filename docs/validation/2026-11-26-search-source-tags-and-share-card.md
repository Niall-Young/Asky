# 搜索来源标签收敛与分享卡片链接清理验证

日期：2026 年 11 月 26 日

## 问题背景

联网搜索回答中出现三处叠加问题：

1. 模型在正文句中或段末直接输出媒体名/文章标题形式的 Markdown 链接（如 `（[财新口径以外的华尔街见闻汇总](url)）`、`[凤凰网的分析](url)`、`[澎湃](url)`、`。[虎嗅](url)`），而非统一的段末 `[来源](URL)`。
2. 对话渲染层仅按严格标签词（`来源`/`1`/`source` 等）识别引用，导致 `[来源：虎嗅](url)` 或段末句号后的独立媒体引用（`。[虎嗅](url)`）未能折叠为来源标签，仍以蓝字下划线链接呈现。
3. 静态分享卡片 PNG 未剥离段末媒体名引用，且对残留行内链接沿用蓝色下划线超链接样式，将不可点击的搜索链接样式带入分享图片。

## 变更范围

- 提示词约束（[NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift)）：
  - 在 `runtimeProtocolPrompt`、`webSearchCapabilities` 与 `imageCapabilities` 中明确要求联网参考出处固定在段末使用 `[来源](URL)`（链接文字固定为“来源”），禁止把媒体名、网站名或报道标题写成句中或段末的 `[媒体名](URL)` 蓝字链接；需要提及媒体名时在正文写纯文本并把 `[来源](URL)` 置于段末，仅在用户要链接或给出官网/下载/直达入口时使用正文直达链接。
- 对话来源标签识别（[ChatSourcePreview.swift](../../App/Sources/ChatSourcePreview.swift)、[ChatMarkdownView.swift](../../App/Sources/ChatMarkdownView.swift)）：
  - 统一 `ChatSourceTextView.isCitation(_:)`（补齐 `来源：...` / `source: ...` / `图片来源` 等形式），并新增 `citationRunFlags(in:)`、`isTrailingCitationCandidate(label:url:)` 与 `endsWithSentenceTerminator(_:)`：将段末句号等句末标点后的独立非裸网址、非操作引导短链接（如 `。[虎嗅](url)`、`。（[虎嗅](url)）`）自动归类为来源标签，同时保留直达链接与裸网址。
  - 在 `ChatInlineNativeText` 中同步清理折叠引用后留下的空括号包裹（`（）`/`()`/`【】`/`[]`）与段末多余空格。
- 分享卡片清理与静态排版（[ChatShareCard.swift](../../App/Sources/ChatShareCard.swift)）：
  - `ChatShareCardContent.stripCitations(from:)` 复用 `ChatSourceTextView` 的引用与段末来源判定，自动剥离段末句号后的媒体名引用（如 `。[虎嗅](url)`、`。（[虎嗅](url)）`）。
  - 静态分享卡片（`ChatShareCardContent.markdownBlock`）移除 `.link` 的蓝色与下划线超链接样式，统一以正文主色呈现，避免静态 PNG 中出现不可点击的蓝字下划线链接。
- 自动化测试（[NativeRuntimeTests.swift](../../Packages/KulaCore/Tests/AgentHostTests/NativeRuntimeTests.swift)、[AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)）：
  - 补充提示词约束断言、前缀/段末媒体引用归类为来源标签断言、直达操作/裸网址保留断言、分享卡片剥离段末媒体引用断言及导出 PNG 零链接蓝像素检查。

## 已执行验证

1. 核心包测试：
   ```sh
   (cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
   ```
   结果：通过（含 `NativeRuntimeTests` 新增提示词断言，全部测试套件通过）。

2. 工程生成与 Debug 构建：
   ```sh
   xcodegen generate
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build
   ```
   结果：构建成功。

3. 原生来源标签与分享卡片回归及视觉复核：
   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --sources-preview
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --share-and-user-reply
   ```
   结果：全部通过；实际检查了新生成的 `build/sources-light.png`、`build/share-card-light.png`（1200×832）与 `build/share-card-dark.png`（1200×832），确认对话中来源标签与直达链接分流清晰，分享卡片中段末媒体引用已彻底移除且正文行内链接不再显示蓝色下划线。
