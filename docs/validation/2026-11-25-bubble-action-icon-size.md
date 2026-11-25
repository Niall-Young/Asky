# 气泡悬停操作栏图标尺寸对齐 AI 输入框

日期：2026-11-25

## 改动

- [App/Sources/AgentView.swift](../../App/Sources/AgentView.swift)：新增 `ChatSideActionButtonLayout`，将气泡悬停操作栏的 `iconSize` 统一复用 AI 输入框中 `ApprovalModePicker.iconSize`（`16 pt`，原 `14 pt`），并显式保持 `buttonSize = 28 pt` 不变，覆盖：
  - `ChatEmojiButton`（贴表情 `ChatEmoji`）
  - `ChatReplyButton`（回复 `share_forward`）
  - `ChatMoreButton`（更多 `ellipsis.vertical` 旋转 90°）
  - `ChatCopyButton`（用户气泡复制 `ChatCopy` 与复制反馈 `checkmark`）
- [docs/design-system.md](../design-system.md)：同步记录气泡悬停操作栏 16 pt 图标与 28 × 28 pt 按钮尺寸规范。

## 验证

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（86 tests in 15 suites passed）。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过（`BUILD SUCCEEDED`）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --bubble-menu-preview`：通过（浅/深模式完整捕获）；人工核查 `build/bubble-menu-emoji-light.png`、`build/bubble-menu-emoji-dark.png`、`build/bubble-menu-assistant-more-dark.png` 与 `build/bubble-menu-user-more-dark.png`，确认贴表情、回复、更多与复制图标均与 AI 输入框 16 pt 图标保持一致，按钮悬停与点击区域维持 28 × 28 pt。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --user-bubble-hover`：通过（72 native pointer transitions，浅/深模式气泡位置、悬停显示与像素稳定性全部通过）；人工核查 `build/user-bubble-hover-1-dark-0.png`。
