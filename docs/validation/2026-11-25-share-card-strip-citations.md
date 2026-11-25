# 分享卡片移除不可点击来源链接验证

日期：2026 年 11 月 25 日

## 变更范围

- 分享卡片排版（[ChatShareCard.swift](../../App/Sources/ChatShareCard.swift)）：在 `ChatShareCardContent.formattedMarkdown(from:)` 中新增 `stripCitations(from:)`，生成分享预览与导出 PNG 图片前自动移除不可点击的来源引用链接（含 `[来源](url)`、`[1](url)`、`[source](url)`、`[来源：...](url)`、`[图片来源](url)`、参考式引用链接、连续引用及其分隔符、空括号/加粗包裹，以及独立成行的 `来源：[...](url)` / `图片来源：[...](url)`），同时保留正文描述性链接、Markdown 图片、行内代码、围栏代码块与表格结构并整理相邻空白。
- 来源行识别复用（[ChatImageGalleryContent.swift](../../App/Sources/ChatImageGalleryContent.swift)）：将 `ChatImageGalleryContent.source(in:)` 调整为内部可见，供分享卡片复用独立来源行判定。
- 回归测试（[AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)）：在 `shareAndUserReplyRegression` 中补充分享卡片来源链接清理断言及带来源链接回复的浅色/深色 PNG 与预览窗口渲染检查。

## 已执行验证

1. 工程生成与 Debug 构建：
   ```sh
   xcodegen generate
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build
   ```
   结果：构建成功。

2. 原生界面回归与视觉验证：
   ```sh
   python3 App/Tests/run-agent-reply-regression.py --share-and-user-reply
   python3 App/Tests/run-agent-reply-regression.py --image-gallery
   ```
   结果：全部通过；实际检查了生成的 `build/share-card-light.png`（1200×792）、`build/share-card-dark.png`（1200×792）与 `build/share-preview-window.png`，确认来源链接已干净移除且无多余空白或标点错位。

3. 核心包自动化测试：
   ```sh
   (cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
   ```
   结果：全部通过（83 tests in 15 suites 及全部 XCTest 用例）。

## 未覆盖范围

- 极长多段含混合复杂嵌套 Markdown 的真实对话分享长图，仍可结合日常使用进一步观察。
