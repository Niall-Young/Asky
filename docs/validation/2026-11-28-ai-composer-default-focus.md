# AI 对话窗口打开默认聚焦输入框验证（2026-11-28）

## 变更范围

- [AgentView.swift](../../App/Sources/AgentView.swift)：将 `AgentWindow` 扩展为持有 `composerTextView` 与 `pendingComposerFocus` 状态，在 `AgentWindowController.show(prompt:)` 与 `restoreAfterAuthentication()`（未展示删除确认弹窗时）请求聚焦输入框，并在 `registerComposerTextView(_:)` 与 `becomeKey()` 中完成聚焦，窗口关闭时清理待聚焦标记；将 `Composer` 中的引用聚焦传递改为 `focusRevision`。
- [ComposerTextEditor.swift](../../App/Sources/ComposerTextEditor.swift)：在 `ComposerTextView.viewDidMoveToWindow()` 中向 `AgentWindow` 注册输入框视图；新增 `focusRevision` 触发机制避免与失焦回调竞态，并在 `AgentWindow` 场景下交由窗口统一管理聚焦时机。
- [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)：新增 `--composer-focus` 回归用例，覆盖首次打开、手动失焦不抢焦、关闭后重开、可见状态再次呼出以及失焦后引用消息重新聚焦。

## 实际执行验证

1. `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过。
2. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（91 tests in 16 suites passed）。
3. `python3 App/Tests/run-agent-reply-regression.py --composer-focus`：通过（`Composer focus regression passed: initial show, close+reopen, visible re-show, and quote focus verified`）。
4. `python3 App/Tests/run-agent-reply-regression.py --composer-tag-height`：通过（`Composer tag height regression passed: empty=28.0, tagOnly=28.0, plain=28.0, text+tag=28.0, baseline=16.0->16.0, twoLine=53.0->53.0`）。
