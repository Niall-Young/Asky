# AI 日期/时间/范围选择器原位形变触发器与玻璃弹出层验证

日期：2026-11-25。将 AI 对话表单（`asky-form`）与新建日程弹窗（`MessageCalendarEditor`）中的全部日期、时间、日期范围、时间段与时长选择器由「文本框 + 右侧图标 + 分离浮层」改为「保留输入框视觉样式的纯触发器按钮 + 原位液态玻璃形变弹出层」：

- **共享触发器与原位形变弹出层**（[FormPickerOverlay.swift](../../App/Sources/FormPickerOverlay.swift)、[AnchoredPopoverMotion.swift](../../App/Sources/AnchoredPopoverMotion.swift)）：
  - 新增 `ChatFormPickerTrigger` 与 `ChatFormPickerTriggerContent`，保留 `settingsInputSurface`（`34 pt` 高、`10 pt` 圆角、等宽数字、单单位时长后缀与右侧日历/时钟图标）的纯按钮交互，点击整块触发器即可展开选择浮层。
  - 重构 `FormPickerOverlayController` 与 `FormPickerOverlayPresentation`：采用与设置页下拉菜单一致的单一连续液态玻璃表面（macOS 26 `GlassEffectContainer` + `RoundedRectangle(...).glassEffect(.regular, in:)`），首帧提交收起态触发器（`10 pt` 圆角）后以 `spring(response: 0.28, dampingFraction: 0.76)` 原位形变展开为 `18 pt` 圆角液态玻璃选择浮层，关闭时以 `spring(response: 0.22, dampingFraction: 0.86)` 缩回原触发器尺寸并交叉淡入更新后的数值；同步兼容减少动态效果、降低透明度、增强对比度及 macOS 14/15 回退路径。
  - 移除 `AnchoredPopoverMotion` 中不再使用的旧表单浮层动效常量与方法。
- **全量覆盖 AI 表单与日程弹窗时间字段**（[ChatFormView.swift](../../App/Sources/ChatFormView.swift)、[MessageCalendarEditor.swift](../../App/Sources/MessageCalendarEditor.swift)）：
  - 统一改造 `datetime`、`datetime_range`、`date`、`date_range`、`time`、`time_range`、`duration` 与新建日程弹窗的 `CalendarEditorDateTimeRangeField`。
- **文档与回归适配**（[design-system.md](../design-system.md)、[AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)、[CalendarEditorRegression.swift](../../App/Tests/CalendarEditorRegression.swift)）：
  - 同步更新设计系统规范，并将表单与日程弹窗回归适配到纯触发器按钮与形变浮层动画时序。

## 实际执行结果

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：全部通过（0 失败）。
- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：成功（`BUILD SUCCEEDED`）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc App/Sources/ChatForm.swift App/Tests/ChatFormParserRegression.swift -o build/chat-form-parser-regression && build/chat-form-parser-regression`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --forms-only --time-preview`：通过（首轮因测试窗口失焦中断，复测完整通过；验证 `datetime` 与 `datetime_range` 纯触发器点击展开、实时更新、点击外部与 `Escape` 收起及明暗截图）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --forms-only --components-preview`：通过（验证 `time` 与 `duration` 触发器点击展开、分钟选择实时更新、外部点击收起及明暗截图）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-calendar-editor-regression.py --snapshot-dir build/calendar-editor-morph-review`：通过（验证新建日程弹窗时间段纯触发器样式、原位形变玻璃浮层与外部点击收起及明暗截图）。

## 已查看的实际窗口与浮层截图

- 聊天表单日期时间与时间段形变浮层：[form-datetime-popover-dark.png](../../build/form-datetime-popover-dark.png)、[form-range-popover-dark.png](../../build/form-range-popover-dark.png)、[form-range-popover-light.png](../../build/form-range-popover-light.png)
- 聊天表单时间/时长形变浮层：[form-time-popover-dark.png](../../build/form-time-popover-dark.png)、[form-time-popover-light.png](../../build/form-time-popover-light.png)
- 新建日程弹窗收起态触发器与展开态时间段浮层：[calendar-dark.png](../../build/calendar-editor-morph-review/calendar-dark.png)、[calendar-light.png](../../build/calendar-editor-morph-review/calendar-light.png)、[calendar-range-popover-dark.png](../../build/calendar-editor-morph-review/calendar-range-popover-dark.png)、[calendar-range-popover-light.png](../../build/calendar-editor-morph-review/calendar-range-popover-light.png)

## 未覆盖边界

- 本次未调用真实模型，也未在 macOS 14/15 实机或系统辅助功能开关（减少透明度/增强对比度/减少动态效果）下实拍验证。
