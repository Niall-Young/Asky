# AI 输入框插入行内 Tag 高度稳定性验证

## 改动摘要

- [InlineTagAttachment.swift](../../App/Sources/InlineTagAttachment.swift)：将 `pillYOffset` 提取为静态常量，作为行内标签与正文基线对齐的单一来源。
- [ComposerTextEditor.swift](../../App/Sources/ComposerTextEditor.swift)：
  - 为 `ComposerTextView` 与占位文本的 `NSLayoutManager` 接入 `ComposerLineLayoutDelegate`，并将 `bodyParagraphStyle.minimumLineHeight` 固定为 `InlineTagAttachment.pillHeight`（22 pt）、`lineSpacing` 设为 3 pt，使普通文本行与含行内 Tag 行的行高（22 pt）与基线（16 pt）完全一致。
  - 将 `textContainerInset.height` 调整为 3 pt，使单行自然高度（`22 + 3 * 2 = 28 pt`）与 `minEditorHeight`（28 pt）精确相等；插入或移除 Tag 时单行与多行输入框高度均不发生跳动。
  - 调整 `clampedCaretRect` 以 `min(rect.height, lineHeight)` 计算居中偏移，避免多行首行光标受行间距影响向下偏移。
- [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)：新增 `--composer-tag-height` 原生回归用例，验证空态、仅 Tag、单行文本、单行文本 + Tag、两行文本与两行含 Tag 的输入框高度及文本基线一致性，并输出窗口截图。

## 验证记录

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过（`** BUILD SUCCEEDED **`）。
- `ASKY_DERIVED_DATA=/Users/niallyoung/orca/Asky/build/DerivedData python3 App/Tests/run-agent-reply-regression.py --composer-tag-height --capture-prefix build/composer-tag-height`：通过（`empty=28.0, tagOnly=28.0, plain=28.0, text+tag=28.0, baseline=16.0->16.0, twoLine=53.0->53.0`）。目视核对新构建窗口生成的 4 张截图（空态、仅 Tag、纯文本、文本 + Tag），确认输入框高度、文本基线与上方欢迎语位置均无偏移，标签与文字垂直居中对齐。
- `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --composer-backspace`：通过。
- `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --inline-tag-alignment`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（83 tests in 15 suites passed）。
