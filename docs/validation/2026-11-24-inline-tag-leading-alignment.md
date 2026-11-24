# 2026-11-24 气泡行首内联 Tag 左侧对齐修复验证

## 变更文件

- [InlineTagAttachment.swift](../../App/Sources/InlineTagAttachment.swift)
- [ComposerTextEditor.swift](../../App/Sources/ComposerTextEditor.swift)
- [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)

## 根因与修复

- **根因**：`InlineTagAttachment` 此前将左右外边距（`horizontalMargin = 5 pt`）固定画入附件图片两侧，当内联 Tag 位于行首（如用户消息气泡第一行开头、换行后的首字符或自动折行到新行行首）时，Tag 左侧仍保留 5 pt 透明空白，导致与第二行正文无法左对齐；单独发送 Tag 的气泡右侧也会多出 5 pt 空白。
- **修复**：
  - 在 `InlineTagAttachment` 中通过 `attachmentBounds(for:proposedLineFragment:glyphPosition:characterIndex:)` 与 `image(forBounds:textContainer:characterIndex:)` 按实际排版位置动态决定水平边距：当 `position.x <= lineFrag.minX + 0.5`（位于行首）时左侧边距为 `0`，行中仍保留 `5 pt`；在消息气泡中位于段落末尾（字符串末尾或紧接换行符）时右侧边距为 `0`，并按 `(leading, trailing)` 缓存绘制结果。
  - 在 `ComposerTextEditor` 中将 `closeHitWidth` 改为 `closeHitWidth(atLineStart:)`，使行首 Tag 的关闭按钮点击命中区域与无左边距的新布局一致。
  - 在 `AgentReplyRegression` 中补充 `--inline-tag-alignment` 回归检查，校验行首 Tag 像素左对齐、行中 Tag 保留左侧边距以及单 Tag 气泡左右对称。

## 已执行的验证

- `xcodegen generate`：生成 `Asky.xcodeproj` 成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build -skipPackageUpdates`：`BUILD SUCCEEDED`。
- `(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)`：全部通过（`ToolServiceTests` 9 项，Swift Testing 15 个套件 83 项）。
- `python3 App/Tests/run-agent-reply-regression.py --inline-tag-alignment`：通过，并已对渲染窗口截图目视确认行首 Tag 与第二行正文左对齐、单 Tag 气泡左右边距对称。
- `python3 App/Tests/run-agent-reply-regression.py --composer-backspace`：通过。
