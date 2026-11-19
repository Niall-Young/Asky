# 来源标签清晰度修复验证（2026-11-19）

## 问题根因

聊天回复段末的来源胶囊此前通过 `ChatSourceTextView.badge` 生成 `NSImage(size:flipped:drawingHandler:)` 并赋给 `NSTextAttachment.image`。由于该附件紧跟在正文及不换行空格 `\u{00A0}` 之后且 `attachment.bounds.origin.y` 使用未取整的浮点基线偏移 `-baseline`，附件矩形常落在分数像素坐标上；经 `NSImage` 贴图合成（尤其在 1x 外接显示器下）会发生亚像素双线性重采样，导致胶囊边缘与内部文字明显发虚。

## 修复内容

- 在 [ChatSourcePreview.swift](file:///Users/niallyoung/orca/Asky/App/Sources/ChatSourcePreview.swift) 中新增 `ChatSourceBadgeAttachmentCell`（继承 `NSTextAttachmentCell`）与 `ChatSourceTextView.badgeAttachment`，改为在 `NSTextView` 的当前 `CGContext` 中直接矢量绘制胶囊背景与 `CTLine` 文字，并将绘制原点与基线对齐到设备物理像素网格（同时适配 1x 与 2x Retina 显示器）。
- 更新 [ChatMarkdownView.swift](file:///Users/niallyoung/orca/Asky/App/Sources/ChatMarkdownView.swift) 使用 `ChatSourceTextView.badgeAttachment`。
- 在 [AgentReplyRegression.swift](file:///Users/niallyoung/orca/Asky/App/Tests/AgentReplyRegression.swift) 的 `sourcesPreview()` 中补充断言，确认来源附件使用矢量 `attachmentCell` 而非 `NSImage` 贴图。

## 实际验证记录

- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：构建成功（`** BUILD SUCCEEDED **`）。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（XCTest 9 tests + Swift Testing 83 tests in 15 suites 全部通过）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --sources-preview`：通过（覆盖来源标签矢量绘制断言、单/多来源分组、悬停/点击展开卡片、长列表滚动与浅色/深色窗口渲染）；已目视复核新生成的 `build/sources-light.png` 与 `build/sources-dark.png` 像素放大图，确认浅色与深色模式下的胶囊边缘与标签文字均锐利对齐。
- 独立 1x / 2x 对比实验（紧跟 `\u{00A0}` 的分数 X 坐标场景）：复现了原 `NSImage` 实现在 1x 下的双线性模糊，并确认新 `ChatSourceBadgeAttachmentCell` 在 1x 与 2x 下均与原生 `NSTextView` 文本保持一致的锐度。
