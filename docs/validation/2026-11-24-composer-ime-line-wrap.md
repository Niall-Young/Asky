# AI 输入框换行时输入法候选窗错位修复验证

- 日期：2026-11-24
- 相关文件：
  - `App/Sources/ComposerTextEditor.swift`
  - `App/Sources/AgentView.swift`
  - `App/Tests/AgentReplyRegression.swift`

## 问题原因

1. macOS 中文等输入法在拼写（marked text）阶段调用 `setMarkedText(_:selectedRange:replacementRange:)`，但 AppKit 不会触发 `textDidChange(_:)`，导致 `Coordinator.updateHeight()` 在换行拼写时未被调用，输入框停留在单行高度（28 pt）；且当输入区为空时，`AgentView` 仅以 `model.isComposerEmpty` 判断高度，也会在提交前将高度锁在 28 pt。
2. `ComposerTextView.scrollToVisible(_:)` 在内容未超过最大高度时将滚动位置固定在顶部以防止换行闪烁；当拼写内容折行到下一行而 `NSScrollView` 尚未增高时，新行暂时落在 `visibleRect` 之外，导致 `NSTextView.firstRect(forCharacterRange:actualRange:)` 返回 `NSZeroRect`，macOS 输入法因此回退把候选窗显示在屏幕左下角 `(0, 0)`。
3. 当 SwiftUI 完成 `NSScrollView` 高度与位置更新后，未通知 `NSTextInputContext.invalidateCharacterCoordinates()`，输入法不会及时按新坐标重排候选窗。

## 修复内容

- 在 `ComposerTextView` 中重写 `setMarkedText` 与 `unmarkText`，在输入法拼写与取消拼写期间同步更新高度和拼写状态。
- 在 `ComposerTextView` 中重写 `firstRect(forCharacterRange:actualRange:)`，当 `super` 因新行暂未进入 `visibleRect` 而返回高度为 0 的矩形时，基于 `NSLayoutManager` / `NSTextContainer` 直接计算屏幕坐标作为回退。
- 使用 `ComposerScrollView` 在 frame 原点或尺寸变化且处于拼写状态时调用 `inputContext?.invalidateCharacterCoordinates()`，并在 `updateNSView` / 滚动条切换后同步刷新坐标。
- 在 `AgentView` 的 `Composer` 中跟踪 `hasMarkedText`，在 `model.isComposerEmpty && !hasMarkedText` 时才锁定单行高度。

## 实际运行的验证

1. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
   - 结果：通过（`Test run with 83 tests in 15 suites passed`）。
2. `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`
   - 结果：通过（Debug 构建成功）。
3. `python3 App/Tests/run-agent-reply-regression.py --composer-ime-wrap`
   - 结果：通过（`single=28.0, wrapped=53.0, immediateRect=(-1534.25, 581.0, 22.544921875, 22.0), settledRect=(-1534.25, 606.0, 22.544921875, 22.0)`）。
4. `python3 App/Tests/run-agent-reply-regression.py --composer-tag-height`
   - 结果：通过（`empty=28.0, tagOnly=28.0, plain=28.0, text+tag=28.0, baseline=16.0->16.0, twoLine=53.0->53.0`）。
