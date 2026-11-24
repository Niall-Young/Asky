# AI 与用户气泡操作区、用户贴表情与自定义液态玻璃菜单验证（2026-11-24）

## 变更范围

- **AI 气泡操作区与用户贴表情**：
  - `MessagePresentation`（`Packages/KulaCore/Sources/LocalStore/Repositories.swift`）新增向后兼容的可选字段 `userReaction: String?`。
  - `AgentModel` 新增 `setUserReaction(_:for:)` 与 `toggleUserReaction(_:for:)`，仅持久化用户给 AI 气泡（`.assistant` / `.toolNarration`）贴上的表情，绝不触发 AI 回复。
  - AI 气泡右侧悬停操作栏调整为「贴表情、回复、更多」三项（新增 `ChatEmoji.imageset` 矢量模板图标与水平三点更多图标）；贴上表情后在气泡右下角展示对称胶囊徽章，点击徽章可直接移除，且连续气泡排版自动断开底部粘连。
  - 点击「贴表情」弹出自绘液态玻璃胶囊表情选择器（`ChatBubbleMenu.swift`，含当前选中态高亮与再次点击取消）；点击「更多」弹出自绘液态玻璃菜单（非原生 `NSMenu` / SwiftUI `Menu`），展示消息「回复时间」（精确到秒的等宽数字时间戳）及隐藏的「复制」「分享」操作。
- **用户气泡操作区与单条消息删除**：
  - `ConversationHistoryService` 新增 `deleteMessage(_:protecting:draftPaths:)`，仅永久删除单条用户消息并清理无引用的附件、FTS 索引与空会话记录，保留同会话中的 AI 回复与共享附件。
  - 用户气泡左侧悬停操作栏默认仅展示「复制」与「更多」；点击「更多」弹出同款自绘液态玻璃菜单，展示「发送时间」及隐藏的「回复」「删除」操作。
  - 点击「删除」通过 `AppDialog` 弹出与设置一致的原生二次确认表单（「删除这条消息？」/「这会永久删除你的消息。此操作无法撤销」，红色破坏性「删除」与「取消」按钮）。

## 已运行验证

1. `KulaCore` 单元测试：
   - 命令：`(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)`
   - 结果：全部通过，包含新增的 `AgentReactionStorageTests.userReactionOnAssistantSurvivesReopeningAndClears()` 与 `ConversationHistoryTests.deleteSingleMessagePreservesSiblingRepliesAndCleansUnusedAttachments()`。
2. 应用工程生成与 Debug 构建：
   - 命令：`xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`
   - 结果：构建通过。
3. 原生回归与实际窗口视觉验收：
   - `--reactions-preview`：通过（覆盖 AI 贴表情、用户给 AI 贴表情不触发回复、重开历史保留、非法非表情忽略、再次选择清除、单条用户消息删除保留 AI 回复）。
   - `--bubble-menu-preview`：实际窗口渲染并人工检查亮/暗模式截图（`build/bubble-menu-emoji-light.png`、`build/bubble-menu-emoji-dark.png`、`build/bubble-menu-assistant-more-light.png`、`build/bubble-menu-assistant-more-dark.png`、`build/bubble-menu-user-more-light.png`），确认液态玻璃表情选择器、AI/用户「更多」液态玻璃菜单、时间戳与操作项排版、表情徽章位置及折射效果均正常。
