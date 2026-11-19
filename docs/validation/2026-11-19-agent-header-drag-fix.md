# 2026-11-19 AI 对话窗口顶部区域拖动修复

## 问题现象

滚动修复将 `AgentWindow` 的 `isMovableByWindowBackground` 设为 `false`，并把 `AgentView.header` 从 `.compatibleWindowDrag()` 改为 `.background(WindowDragArea())` 后，点击 AI 对话窗口上方区域无法拖动窗口。

## 根因定位

`App/Sources/AgentView.swift` 中 `header` 在 `.background(WindowDragArea())` 之前保留了 `.contentShape(Rectangle())`。前景 `HStack` 因此在 `NSHostingView` 命中测试中拦截了整个顶部区域（返回 `NSHostingView<AgentView>`），点击事件无法穿透到底层的 `WindowDragArea.DragView`，从而未触发 `window?.performDrag(with: event)`。

## 修复内容

- `App/Sources/AgentView.swift`：移除 `header` 上多余的 `.contentShape(Rectangle())`，让顶部空白区域点击直接命中 `.background(WindowDragArea())` 中的 `DragView`，同时保留顶部按钮和头像选择器的正常点击交互。
- `App/Tests/AgentReplyRegression.swift`：新增 `--header-drag` 回归测试，覆盖非空会话滚动后顶部多点命中 `WindowDragArea.DragView`、顶部工具栏按钮可点击、正文区域不被 `DragView` 遮挡，以及空会话顶部区域命中 `DragView`。

## 验证记录

- `python3 App/Tests/run-agent-reply-regression.py --header-drag`：通过（`Header drag passed: non-empty scrolled header, toolbar buttons, body transcript, and empty conversation header`）
- `python3 App/Tests/run-agent-reply-regression.py --header-cursor-preview`：通过（`Header cursor passed: 120 synchronous cursor/move pairs over real scrolled chat text, return to body`）
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过
- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：`BUILD SUCCEEDED`
