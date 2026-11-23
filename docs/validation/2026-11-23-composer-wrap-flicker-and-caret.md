# 2026-11-23 AI 输入框换行闪烁与标签旁光标过高修复验证

## 变更文件

- [ComposerTextEditor.swift](../../App/Sources/ComposerTextEditor.swift)

## 根因与修复

1. **换行时首行消失再出现（滚动条闪现 + 视图重排）**
   - 原实现始终开启 `scroll.hasVerticalScroller = true`，并在 `updateHeight()` 中通过 `DispatchQueue.main.async` 异步更新容器高度；换行瞬间 `NSTextView` 高度已增加而 `NSScrollView` 仍停留在旧高度，触发 `scrollToVisible` 将首行滚出视口并闪出滚动条，下一帧高度撑开后再弹回顶部。
   - 同时 `updateNSView` 每次按键都会无条件调用 `setFrameSize`、重置 `baseTextColor`（进而触发 `textColor` 重写整段 `textStorage` 前景色与 `typingAttributes`）并设置 `needsDisplay = true`，`didChangeText` 也无条件重写整段属性。
   - 修复：
     - 改用显式 TextKit 1 栈初始化 `ComposerTextView`，避免运行期从 TextKit 2 回退。
     - 当自然内容高度 `<= 160 pt` 时关闭垂直滚动条，并在 `scrollToVisible(_:)` 中抑制中间态滚动、保持 `clipView` 固定在顶部；仅当内容超过 `160 pt` 时再启用垂直滚动条（不开启 `autohidesScrollers`）、调用 `tile()` 与 `reflectScrolledClipView(_:)` 并 `flashScrollers()`，保证超长内容时滚动条正常出现与滚动。
     - `updateNSView` 仅在宽度、配色方案或选区色实际变化时更新；`didChangeText` 跳过 `hasMarkedText()` 并仅修正属性实际不一致的区间。

2. **行内 Tag 导致输入光标过高**
   - `InlineTagAttachment` 高度为 `22 pt`，高于 14 pt 正文行高，AppKit 默认按整行片段高度绘制输入光标（`NSTextInsertionIndicator` / `drawInsertionPoint`）。
   - 修复：在 `updateInsertionPointStateAndRestartTimer(_:)`、`layout()` 与 `drawInsertionPoint(in:color:turnedOn:)` 中将光标高度限制在正文基准高度（`ceil(bodyFont.ascender - bodyFont.descender) + 1`）并垂直居中。

## 已执行的验证

- `(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)`：全部通过（含 `ToolServiceTests` 9 项、`AgentHostTests` 等 83 项）。
- `xcodegen generate`：生成 `Asky.xcodeproj` 成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：`BUILD SUCCEEDED`。

## 未覆盖项

- 尚未通过交互式 UI 自动化或人工实机输入验证中文输入法换行与行内标签旁光标的视觉效果，需在新建 Debug 应用中实测确认。
