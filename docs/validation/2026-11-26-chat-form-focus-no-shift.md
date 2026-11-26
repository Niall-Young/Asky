# AI 表单输入框聚焦零位移验证

日期：2026-11-26。修复聚焦 AI 对话表单（`asky-form`）输入框时出现 1 pt 布局上下位移的问题：

- **根因**：[ChatFormView.swift](../../App/Sources/ChatFormView.swift) 中的原生液态玻璃提交按钮 `ChatFormSubmitPushButton` 在 `sizeThatFits` 中读取了 `nsView.intrinsicContentSize`。在 macOS 26 上，`.glass` / `.capsule` / `.extraLarge` 规格的 `NSButton` 在窗口或第一响应者状态切换时，`intrinsicContentSize` 会在 `(80, 25)` 与 `(92, 37)` 间波动，导致按钮布局高度在 `36 pt` 与 `37 pt` 间跳变，进而带动表单与对话滚动容器发生 1 pt 上下位移。
- **修复**：
  - `ChatFormSubmitPushButton.sizeThatFits` 改为使用按钮字体测量标题宽度与固定高度（macOS 26 为 `36 pt`，更早版本为 `ChatFormMetrics.controlHeight`），不再依赖易抖动的 `intrinsicContentSize`。
  - `ChatFormSubmitPushButton.updateNSView` 仅在属性变化时写入 `NSButton` 状态，避免每次 SwiftUI 更新触发多余的 AppKit 布局失效。
- **回归断言**：在 [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift) 中新增可滚动对话场景下「底部输入框 → 表单输入框」「表单输入框 → 点击空白失焦」「失焦 → 再次聚焦表单输入框」三段切换的几何零位移校验（校验输入框、提交按钮、`clipView.bounds.origin.y` 与 `documentView.bounds.height` 均无上下偏移）。

## 实际执行结果

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：全部通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build`：成功（`BUILD SUCCEEDED`）。
- `python3 App/Tests/run-agent-reply-regression.py --forms-only`：全部通过（包含新增的聚焦/失焦零垂直位移断言）。

本次未在 macOS 14/15 实机验证。
