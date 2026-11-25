# 输入框与气泡行内 Tag 样式收敛与去悬停变色验证

日期：2026 年 11 月 25 日

## 变更文件

- [InlineTagAttachment.swift](../../App/Sources/InlineTagAttachment.swift)
- [ComposerTextEditor.swift](../../App/Sources/ComposerTextEditor.swift)
- [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)
- [design-system.md](../design-system.md)

## 改动摘要

- **去掉悬停变色**：`InlineTagAttachment` 将悬停态收敛为单一布尔值 `isHovered`，悬停时不再改变胶囊底色、不再变化或绘制描边，也不再为左侧 `✕` 绘制圆形底板或加深遮罩；仅静默将左侧类型图标切换为同色 12 pt `✕`（图片缩略图保持固定 45% 暗遮罩配 11 pt 白色 `✕`），保留点击移除、提示文案与手型光标。
- **收敛视觉杂乱度**：
  - 标准模式下移除外层 0.5 pt 灰色边框（仅在「降低透明度」模式保留描边），使用柔和无边框半透明底板与 7 pt 圆角；水平外距收紧为 4 pt、最大宽度收紧为 176 pt。
  - 修复 `tintedImage` 的混合模式（`.sourceAtop` → `.sourceIn`），使 `kIconSubtle` 在浅色与深色模式下均以真实半透明度渲染，避免浅色模式下图标发黑过重。
  - 图标尺寸收敛为 13 pt，图片缩略图收敛为 16 × 16 pt（4 pt 同心圆角 + 0.5 pt 细内边），与文本起止位置保持统一视觉节奏。
  - 划词引用改用 `text.bubble`（`MingCute-chat_1`）以区分文件与剪贴板图标，并移除全角中文引号 `“”` 包裹，消除左右不对称留白与截断后单边引号问题。
  - 使用 CoreText（`CTLineCreateTruncatedLine` + 统一 `capHeight` 基线）替代 `NSString.draw(in:)`，统一中英文标签的垂直光学居中与精确宽度裁剪。
- **回归测试**：在 `AgentReplyRegression` 新增 `--composer-inline-tag-styles`，校验浅/深模式悬停前后像素底色无变化、划词引用不带全角引号包裹，并输出含全部 5 类 Tag 的浅色常态、浅色悬停态与深色悬停态实窗截图。

## 实际执行的验证

1. `xcodegen generate`：生成 `Asky.xcodeproj` 成功。
2. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build -skipPackageUpdates`：`BUILD SUCCEEDED`。
3. `ASKY_DERIVED_DATA=/Users/niallyoung/orca/Asky/build/DerivedData python3 App/Tests/run-agent-reply-regression.py --composer-inline-tag-styles --capture-prefix build/after-inline-tags`：通过，并已目视核对浅色常态、浅色悬停态与深色悬停态三张实窗截图（5 类 Tag 在输入框与用户气泡内排列整齐、图标柔和、基线居中、悬停无底色变化）。
4. `build/DerivedData/AgentReplyRegression/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --composer-tag-height --capture-prefix build/after-tag-height`：通过（`empty=28.0, tagOnly=28.0, plain=28.0, text+tag=28.0, baseline=16.0->16.0, twoLine=53.0->53.0`）。
5. `build/DerivedData/AgentReplyRegression/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --inline-tag-alignment --capture build/after-inline-align.png`：通过。
6. `build/DerivedData/AgentReplyRegression/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --composer-backspace`：通过。
7. `(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)`：通过（83 tests in 15 suites passed）。
