# 聊天 LaTeX 公式主动渲染与中文公式排版修复验证

日期：2026-11-25

## 问题背景

用户反馈客户端虽然支持 LaTeX 渲染，但 AI 在解释公式（如“收入公式基本等于有效播放乘 eCPM 再乘填充率”）时仍会偷懒用口语平铺，没有输出 LaTeX 公式。同时排查发现，现有本地排版引擎 SwiftMath 1.7.3 的字符解析仅接收 ASCII、西里尔字母及固定拉丁重音表，直接渲染含中文的公式（如 `\text{收入} = \text{有效播放} \times \text{eCPM} \times \text{填充率}`）会静默丢弃所有中文字符。

## 改动

- [App/Sources/ChatMath.swift](../../App/Sources/ChatMath.swift)：在 `ChatMathRenderer` 中新增 `buildMathList(from:)` 与 AST 占位符还原流程；对 SwiftMath 无法识别的非 ASCII 连续字符段（含中文及全角标点）先用唯一 ASCII 占位符通过 `MTMathListBuilder` 解析，再在生成的 `MTMathList` 中还原为 `.ordinary` 原子（并保留上下标与分数、根号、表格、矩阵等嵌套结构），交由 CoreText 系统字体回退完成清晰渲染，同时保持原有 TeX 间距、复制原文与无障碍文本不变。
- [Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift)：
  - 在 `runtimeProtocolPrompt` 中独立新增“LaTeX 公式”排版约束，明确客户端原生渲染 `$...$`、`$$...$$`、`\(...\)`、`\[...\]` 并支持 `\text{...}` 写中文，要求涉及数学、物理、财务或业务指标公式/等式时一律用 LaTeX 写出，避免口语平铺或纯文本星号拼公式，同时保持普通单个数字、金额、比例为纯文本；移除原先附在 `asky-form` 转义条款末尾的弱提示句。
  - 在 `defaultSystemPrompt` 排版段同步强化 LaTeX 公式要求，保证默认人设与自定义人设均生效。
- [Packages/KulaCore/Tests/AgentHostTests/NativeRuntimeTests.swift](../../Packages/KulaCore/Tests/AgentHostTests/NativeRuntimeTests.swift)：新增 `latexFormulaGuidanceActivelyRequiresMathRenderingAcrossLayers`，并将 `compactionPreservesCurrentRequestAndSavesSummary` 的压缩后体积断言调整为相对当前系统提示词字节数（`+ 5_000`）校验，避免系统提示词微增触发误报。
- [App/Tests/AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)：在 `--math-preview` 回归中新增中文收入公式、中文分式（毛利率）、中文下标与括号混合公式及行内中文公式，断言中文公式渲染宽度显著大于去中文版本且上下留白无裁切。

## 已执行检查

```sh
(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --math-preview
```

- `KulaCore` 全部单元测试通过（含 `NativeRuntimeTests.latexFormulaGuidanceActivelyRequiresMathRenderingAcrossLayers` 与 `compactionPreservesCurrentRequestAndSavesSummary`）。
- `xcodegen generate` 与 Debug `Asky` 构建通过（`BUILD SUCCEEDED`）。
- `run-agent-reply-regression.py --math-preview` 通过（`Math parsing, native layout, invalid-source fallback and light/dark window captures passed`）。
- 已人工目视检查真实 `NSWindow` 渲染截图 `build/math-light.png`、`build/math-dark.png` 与 `build/math-dark-narrow.png`：`收入 = 有效播放 × eCPM × 填充率`、中文分式、中文下标及行内中文公式在浅色、深色和窄宽度下字形完整、配色与基线对齐正常、无裁切。

## 范围说明

- 本次未调用外部在线模型执行端到端生成抽样；提示词拼接与透传由 `NativeRuntimeTests` 验证，中文与常规 LaTeX 排版由真实 `ChatMarkdownView` 原生回归验证。
- 构建与截图产物位于已被 `.gitignore` 忽略的 `build/` 目录。
