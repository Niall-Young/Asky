# 移除行内 Tag 点击弹出层

## 改动

- 在 `App/Sources/InlineTagAttachment.swift` 彻底移除 `InlineTagPopoverPresenter`、`InlineTagPopoverContent` 与 `InlineTagKind.supportsComposerPopover`；`supportsBubbleAction` 仅保留 `.reply` 用于点击定位原消息，不再为任何行内 Tag 弹出 `NSPopover`。
- 在 `App/Sources/ComposerTextEditor.swift` 移除输入区点击行内 Tag 弹出 `NSPopover` 的分支以及仅用于该弹窗的 `onRevealReply` 回调；输入区内仅悬停左侧 `✕` 时显示手型光标并支持点击移除。
- 同步清理 `App/Sources/AgentView.swift`、`App/Tests/ClipboardRegression.swift`、`App/Tests/LocalShortcutsRegression.swift` 中的无用 `onRevealReply` 传参，并更新 `docs/design-system.md`。

## 已执行

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（全部测试套件均通过，最终套件 `91 tests in 16 suites passed`）。
- `xcodegen generate`：成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：构建成功（`** BUILD SUCCEEDED **`）。
