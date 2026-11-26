# AI 表单聚焦与选择器选中态低对比度统一验证

日期：2026-11-26。将 AI 对话表单（`asky-form`）中所有聚焦边框与选择器选中态统一为与单选 / 多选行一致的低对比度柔和单色风格：

- **共享表单低对比度色板（`ChatFormPalette`）**：
  - [ChatFormView.swift](../../App/Sources/ChatFormView.swift) 提取 `ChatFormPalette.selectedBorder`（浅色黑 28% / 深色白 34%，高对比度 +16%）、`selectedFill`（浅色白 56% / 深色白 12%）与 `pickerSelectedBorder`（浅色黑 26% / 深色白 32%，高对比度 +16%）。
  - `ChatFormOptionRow` 复用 `ChatFormPalette.selectedBorder`。
- **聚焦与触发器高亮边框**：
  - [SettingsStyle.swift](../../App/Sources/SettingsStyle.swift) 为 `SettingsInputChrome` 新增 `settingsInputFocusBorder` 与 `settingsInputFocusBorderWidth` 环境覆写，不影响设置页与日程弹窗既有聚焦样式。
  - [ChatFormView.swift](../../App/Sources/ChatFormView.swift) 与 [FormPickerOverlay.swift](../../App/Sources/FormPickerOverlay.swift) 为 AI 表单文本输入、自定义输入以及日期 / 时间触发器（含形变快照）应用 `1 pt` 低对比度聚焦边框，与单选 / 多选选中边框完全对齐。
- **日期、时间列与范围标签选中态**：
  - [CalendarMonthPicker.swift](../../App/Sources/CalendarMonthPicker.swift) 在 `monochrome`（AI 表单）模式下，将选中日期由纯黑 / 纯白反色实心圆调整为 `ChatFormPalette.selectedFill` + `1 pt` `pickerSelectedBorder` 与常规 `kText` 粗体文字，并同步柔化范围端点与区间底色，保持「当前编辑选中日 > 非活跃范围端点 > 区间内 / 今日 / 悬停」的清晰层次。
  - [ChatFormView.swift](../../App/Sources/ChatFormView.swift) 将 `ChatFormTimeCell`（小时 / 分钟 / 秒钟选中项）与 `ChatFormRangeTabPill`（开始 / 结束活跃标签）统一为 `selectedFill` + `1 pt` `pickerSelectedBorder` 与 `kText` 粗体文字。

## 实际执行结果

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：全部通过。
- `xcodegen generate` + `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：成功（`BUILD SUCCEEDED`）。
- `python3 App/Tests/run-agent-reply-regression.py --forms-only --radio-preview`：通过。
- `python3 App/Tests/run-agent-reply-regression.py --forms-only --time-preview`：通过。
- `python3 App/Tests/run-agent-reply-regression.py --forms-only --components-preview`：通过。

## 已查看的实际窗口截图

- 文本聚焦与单选选中对比：[form-field-light-focused.png](../../build/form-field-light-focused.png)、[form-field-dark-focused.png](../../build/form-field-dark-focused.png)
- 日期与时间选择器选中态：[form-datetime-bitmap-light.png](../../build/form-datetime-bitmap-light.png)、[form-datetime-bitmap-dark.png](../../build/form-datetime-bitmap-dark.png)
- 范围标签与区间日历选中态：[form-range-bitmap-light.png](../../build/form-range-bitmap-light.png)、[form-range-bitmap-dark.png](../../build/form-range-bitmap-dark.png)
- 多列时间选择器选中态：[form-time-bitmap-light.png](../../build/form-time-bitmap-light.png)、[form-time-bitmap-dark.png](../../build/form-time-bitmap-dark.png)

本次未调用真实模型，也未在 macOS 14/15 实机验证。
