# 输入区与用户消息行内 Tag 验证

日期：2026 年 11 月 23 日

## 变更范围

- `Packages/KulaCore/Sources/LocalStore/Repositories.swift`：新增 `MessagePastedText`、`MessageSegment`，扩展 `MessagePresentation`（`pastedTexts`、`segments`、`promptText`、`copyableText`），保留对旧历史消息的向后兼容解码。
- `App/Sources/InlineTagAttachment.swift`：新增统一行内 Tag 附件渲染器（22 pt 高、6 pt 圆角、最大宽 188 pt，支持图片、文件、粘贴长文本、划词引用与回复消息）、点击预览 `NSPopover` 与已发送用户消息内联视图 `UserInlineMessageView`。
- `App/Sources/ComposerTextEditor.swift`：支持在 `NSTextView` 中直接插入与编辑行内 Tag，支持粘贴长文本自动折叠（≥ 300 字或 ≥ 6 行，⌘⇧V 保留纯文本粘贴）、点击预览/展开/移除、⌘Z 撤销与浅深外观同步。
- `App/Sources/AgentModel.swift`、`App/Sources/AgentView.swift`：移除输入框上方 58 pt 大卡片区，将 5 类内容统一接入行内 Tag 流；发送时按原位生成编号锚点并携带完整上下文；已发送消息在气泡内原位呈现行内 Tag，回复 Tag 继续支持跳转原回答。
- `App/Resources/zh-Hans.lproj/Localizable.strings`、`App/Resources/en.lproj/Localizable.strings`、`docs/design-system.md`：补齐双语本地化与设计文档。

## 实际执行的检查

1. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
   - 结果：通过（含新增 `inlineSegmentsAndPastedTextsSurviveReopenAndSerializePrompt` 单测）。
2. `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug build CODE_SIGNING_ALLOWED=NO`
   - 结果：`BUILD SUCCEEDED`。

## 待在真实窗口确认的项

- 在浅色/深色外观与实际壁纸下目检输入区及已发送用户气泡内 5 类行内 Tag 的基线对齐、截断与 `NSPopover` 预览交互。
