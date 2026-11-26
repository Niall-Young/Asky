# AI 表单控件高度、内边距与尾部图标尺寸统一验证

日期：2026-11-26。统一 AI 对话表单（`asky-form`）中文本框、日期时间触发器、单选行与多选行的尺寸规范：

- [ChatFormView.swift](../../App/Sources/ChatFormView.swift)：
  - `ChatFormMetrics` 新增 `controlHorizontalPadding = 12`、`optionVerticalPadding = 6`、`trailingIconSize = 15`、`optionIndicatorSize = 14`，并将 `optionMinHeight` 与 `optionCornerRadius` 直接复用 `controlHeight`（`34 pt`）与 `controlCornerRadius`（`10 pt`）。
  - `ChatFormOptionRow` 水平内边距由 `13 pt` 调整为 `12 pt`（与 `SettingsInputSurface` 的文本框和日期时间触发器一致），垂直内边距由 `9 pt` 调整为 `6 pt`，使单行单选/多选行与文本框、日期时间触发器保持一致的 `34 pt` 高度，同时保留多行文案自动撑高能力。
  - `ChatFormOptionRow.trailingIndicator` 外框尺寸由 `18 × 18 pt` 收敛为 `15 × 15 pt`（与时钟/日历触发图标同宽居中对齐），单选实心勾选圆点与多选复选框尺寸统一为 `14 × 14 pt`（复选框圆角 `4 pt`、勾选图标 `8.5 pt`）。

## 实际执行结果

- `xcodegen generate` + `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：成功（`BUILD SUCCEEDED`）。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（91 tests in 16 suites passed）。
- `python3 App/Tests/run-agent-reply-regression.py --latex-form-preview`：通过，已检查新构建窗口导出的 `build/latex-form-light.png` 与 `build/latex-form-dark.png`。
- `python3 App/Tests/run-agent-reply-regression.py --forms-only --radio-preview`：通过（表单生命周期、单字段即时提交、单选/多选明暗与窄窗渲染回归均通过），已检查新构建窗口导出的 `build/form-submitted-readonly.png`，确认文本框、单选行与多选行高度、水平内边距及尾部指示图标视觉一致。

本次未调用真实模型，也未在 macOS 14/15 实机验证。
