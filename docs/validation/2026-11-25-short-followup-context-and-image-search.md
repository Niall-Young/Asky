# 短追问串台修复与主动配图召回验证

日期：2026-11-25

## 问题根因

1. **短追问串台**：用户在「吴磊是谁啊」后回复 2 字追问「明星」，[AgentModel.swift](../../App/Sources/AgentModel.swift) 的 `buildContext` 直接用 `"明星"` 触发全库 `relevant-history` 检索，捞出更早关于「钟丽缇是什么明星啊」的历史片段并紧贴用户输入注入，劫持了 11 秒前刚刚结束的「吴磊」对话主线。
2. **人物/景点不出图**：
   - 模型在「杭州千岛湖怎么样」「吴磊是谁啊」等凭训练知识熟悉或有同名歧义的问题上跳过工具直接纯文字回复；
   - [WebPageImageService.swift](../../Packages/KulaCore/Sources/ToolService/WebPageImageService.swift) 抓取新闻页元数据时未过滤 `scorecardresearch.com` 等追踪像素，且多张无图注侧边栏杂图挤掉了 `og:image` 封面主图。

## 修复内容

- [AgentModel.swift](../../App/Sources/AgentModel.swift)：新增 `shouldSearchRelevantHistory(for:hasRecentHistory:)`，存在近期对话时对 4 字以内的极短追问跳过陈年全库历史召回；将 `relevant-history` 预算从 8,000 字节收紧至 3,000 字节，并明确声明指代优先承接近期对话。
- [NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift)：在 `imageCapabilities` 中明确介绍人物/明星、景点/城市、动植物或外观时即使凭已有知识能答或有同名歧义也必须先找图再答，优先百科/官方页并支持 `imagesOnly` 并行读 1–2 个来源；在 `defaultSystemPrompt` 补充简短配图提醒（不引入工具名）。
- [WebPageImageService.swift](../../Packages/KulaCore/Sources/ToolService/WebPageImageService.swift) 与 [WebPageImages.swift](../../Packages/KulaCore/Sources/Adapters/WebPageImages.swift)：统一过滤追踪像素域名；当页面正文/侧边栏图超过 7 张时，为带 `og:title`/`twitter:title` 图注的主 `og:image` 保留 1 个候选槽位。

## 验证结果

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（含 `WebPageImageServiceTests`、`WebPageImagesTests`、`NativeRuntimeTests` 新增断言）。
- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：`BUILD SUCCEEDED`。
- `python3 App/Tests/run-agent-reply-regression.py --share-and-user-reply`：通过（含 `AgentModel.shouldSearchRelevantHistory` 短追问防串台回归断言）。
