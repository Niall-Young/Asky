# AI 窗口与日程编辑器点击空白失焦验证（2026-11-26）

## 变更内容

- [SettingsEditingWindow.swift](../../App/Sources/SettingsEditingWindow.swift)：提取 `NSWindow.endEditingIfOutsideClick(_:)`，在 `leftMouseDown` 派发前判断点击是否落在当前处于编辑态的可编辑 `NSTextView`（含 `NSTextField` field editor）之外，落在外部时调用 `makeFirstResponder(nil)`，保留点击目标控件的正常事件派发，且不影响只读文本选区视图。
- [AgentView.swift](../../App/Sources/AgentView.swift)：`AgentWindow.sendEvent(_:)` 调用 `endEditingIfOutsideClick(_:)`，修复对话表单输入框与底部输入框聚焦后点击窗口空白处无法失焦的问题。
- [MessageCalendarEditor.swift](../../App/Sources/MessageCalendarEditor.swift)：`CalendarEditorWindow.sendEvent(_:)` 同步调用 `endEditingIfOutsideClick(_:)`。
- [ComposerTextEditor.swift](../../App/Sources/ComposerTextEditor.swift)：在 `Coordinator` 中记录 `pendingResign`，避免 `resignFirstResponder()` 异步回写 `isFocused = false` 前被同步 `updateNSView` 抢回焦点。
- [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)：在 `formPreview` 中补充原生点击回归断言，覆盖表单输入框内点击保持焦点、点击空白处失焦并保留输入值，以及底部 `ComposerTextView` 点击空白处失焦。

## 实际执行与结果

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --forms-only`：通过（表单生命周期、单项表单、原生表单输入内点保焦/空白点击失焦/值保留及底部输入区空白点击失焦断言全部通过）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-calendar-editor-regression.py`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过（`** BUILD SUCCEEDED **`）。
