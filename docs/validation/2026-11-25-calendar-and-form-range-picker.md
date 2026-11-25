# 日程弹窗与聊天表单时间段选择器统一验证

日期：2026-11-25。针对新建日程弹窗仍拆分为「开始时间 / 结束时间」以及 AI 聊天表单偶尔拆出独立起止字段的问题，完成以下改动与验证：

- **新建日程弹窗统一时间段选择器**：
  - [MessageCalendarEditor.swift](../../App/Sources/MessageCalendarEditor.swift) 移除拆分的「开始时间」「结束时间」四格输入（`CalendarEditorDateField` + `CalendarEditorTimeField`），改为单个「时间」时间段输入控件（`CalendarEditorDateTimeRangeField`），复用 `ChatFormDateTimeRangePopover` 窗口内液态玻璃浮层，同日显示 `YYYY-MM-DD HH:mm – HH:mm`、跨日自动带结束日期，右侧实时显示时长或过去/倒挂校验提示。
  - 弹窗尺寸由 `448 × 592` 调整为 `460 × 580`，确保 `ChatFormDateTimeRangePopover` 在时间输入框下方完整展开且不遮挡输入区。
- **聊天表单自动合并拆分起止字段与提示词强化**：
  - [ChatForm.swift](../../App/Sources/ChatForm.swift) 在 `ChatFormParser` 解析完成时自动将模型拆出的相邻起止字段合并为区间选择器：`datetime` + `datetime` → `datetime_range`、`date` + `time`(start) + `time`(end) → `datetime_range`、`start_date` + `start_time` + `end_date` + `end_time` → `datetime_range`、`start_date` + `end_date` → `date_range`、`start_time` + `end_time` → `time_range`，同时合并 `defaultValue` 与保留语义前缀（不同前缀不误合并）。
  - [NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift) 将日程、会议、请假、勿扰等区间场景的字段要求强化为强制使用 `datetime_range` / `date_range` / `time_range`，禁止拆成多个独立起止字段。

## 实际运行的检查

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（含 `AgentHost` 与全部核心套件）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc App/Sources/ChatForm.swift App/Tests/ChatFormParserRegression.swift -o /tmp/chat-form-parser-regression && /tmp/chat-form-parser-regression`：通过（含拆分起止字段自动合并与前缀保护用例）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-calendar-editor-regression.py --snapshot-dir build/calendar-editor-review-v3`：通过（验证 `calendar-editor-time-range-picker` 打开窗口内液态玻璃 `ChatFormDateTimeRangePopover`、起止切换标签存在、外部点击关闭并消费事件，以及明暗截图）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --forms-only`：通过。

## 视觉复核截图

- 明暗常规与错误校验态：[calendar-light.png](../../build/calendar-editor-review-v3/calendar-light.png)、[calendar-dark.png](../../build/calendar-editor-review-v3/calendar-dark.png)、[calendar-error-dark.png](../../build/calendar-editor-review-v3/calendar-error-dark.png)
- 明暗时间段液态玻璃浮层展开态：[calendar-range-popover-dark.png](../../build/calendar-editor-review-v3/calendar-range-popover-dark.png)、[calendar-range-popover-light.png](../../build/calendar-editor-review-v3/calendar-range-popover-light.png)（已目视确认浮层与时间输入框保持 6 pt 间距无遮挡、圆角与边距完整）。
