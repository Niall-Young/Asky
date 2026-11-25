# 日期时间统一输入框、范围选择与窗口内玻璃浮层验证

日期：2026-11-25。针对聊天表单（`asky-form`）与新建日程弹窗（`MessageCalendarEditor`）中的日期/时间输入体验完成以下改动与验证：

- **统一大圆角输入框与行内触发图标**：
  - 移除独立外部触发按钮（`ChatFormPickerTriggerButton`），改为将 `ChatFormInlinePickerIcon` 嵌入共享的 `settingsInputSurface` 大圆角输入框右侧，覆盖 `datetime`、`datetime_range`、`date`、`date_range`、`time`、`time_range`、`duration` 以及日历编辑器的日期/时间字段。
- **去除浮层确认按钮并改用窗口内 Liquid Glass 浮层**：
  - 新增 [FormPickerOverlay.swift](../../App/Sources/FormPickerOverlay.swift)，用窗口内原生 Regular 液态玻璃浮层（`18 pt` 圆角）替代 `NSPopover`，接入与聊天菜单/审批菜单一致的触发器锚定弹窗动效（[AnchoredPopoverMotion.swift](../../App/Sources/AnchoredPopoverMotion.swift)），同步更新 [design-system.md](../design-system.md)。
  - 移除浮层底部确认按钮，点选日期/时间即实时生效，点击浮层外区域、滚轮滚动或按 `Escape` 即确认并收起。
  - 修复 [MessageCalendarEditor.swift](../../App/Sources/MessageCalendarEditor.swift) 中 `.environment(\.formPickerOverlay, formPickerOverlay)` 位于 `.modifier(FormPickerOverlayPresentation(...))` 之前导致浮层内视图无法读取 `pickerOverlay` 环境的问题。
- **支持时间段与日期范围选择**：
  - [ChatForm.swift](../../App/Sources/ChatForm.swift)、[ChatFormView.swift](../../App/Sources/ChatFormView.swift) 与 [NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift) 新增 `datetime_range`、`date_range`、`time_range` 字段类型及区间切换标签与自动保序逻辑，使开始时间与结束时间可合并在同一输入框和浮层内完成选择。
- **回归用例稳定性修复**：
  - [CalendarEditorRegression.swift](../../App/Tests/CalendarEditorRegression.swift) 在 `--snapshot-dir` 模式下使用 `.accessory` 激活策略并调用 `orderFrontRegardless()`，避免多窗口连续开关时系统异步失焦触发 `didResignKeyNotification` 提前关闭浮层。

## 实际执行结果

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：全部通过（0 失败）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc App/Sources/ChatForm.swift App/Tests/ChatFormParserRegression.swift -o build/chat-form-parser-regression && build/chat-form-parser-regression`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --forms-only --time-preview --time-components`：通过（覆盖 `datetime_range`、`datetime`、`date`、`time`、`duration` 浮层打开、点选更新、外部点击与 Escape 关闭及明暗截图）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-calendar-editor-regression.py --snapshot-dir build/calendar-editor-review-v2`：通过（验证日历编辑器日期/时间浮层非 `NSPopover`、外部点击关闭与消费事件及明暗截图）。
- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：成功（`BUILD SUCCEEDED`）。
- `python3 App/Tests/check-localization.py`：新增键 `选择时间段`、`选择日期范围` 无缺失告警（仅存仓库既有重复键 `剪贴板历史`）。

## 已查看的实际窗口与浮层截图

- 聊天表单时间段与日期时间浮层：[form-range-popover-dark.png](../../build/form-range-popover-dark.png)、[form-datetime-popover-dark.png](../../build/form-datetime-popover-dark.png)
- 日历编辑器明暗模式日期/时间浮层：[calendar-date-popover-dark.png](../../build/calendar-editor-review-v2/calendar-date-popover-dark.png)、[calendar-date-popover-light.png](../../build/calendar-editor-review-v2/calendar-date-popover-light.png)、[calendar-time-popover-dark.png](../../build/calendar-editor-review-v2/calendar-time-popover-dark.png)、[calendar-time-popover-light.png](../../build/calendar-editor-review-v2/calendar-time-popover-light.png)

本次未调用真实模型，也未在 macOS 14/15 实机验证。
