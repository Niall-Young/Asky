# 通知创建日程窗口视觉与表单样式优化验证

日期：2026-11-24。参考分享弹窗（`ChatShareCard.swift`）的窗口框架与入场动效，以及最新 AI 对话表单（`ChatFormView.swift`）的黑白单色控件规范，优化 Asky 通知触发的日程创建窗口（`MessageCalendarEditor.swift`）：

- **窗口框架与头部（参考分享弹窗）**：
  - 采用 `448 × 592 pt`、`24 pt` 圆角的 Spotlight 式原生液态玻璃独立窗口（`CalendarEditorWindow`，`canBecomeKey = true`、`canBecomeMain = true`），保留原生窗口投影与圆角裁剪；通过 `WindowPresentation` 在活跃态展示，并配以 `CADisplayLink` 驱动的轻柔上浮弹簧与淡入入场动效（尊重「减少动态效果」，拖拽窗口时立即停止位移）。
  - 顶栏改为左对齐 `16 pt` 半粗体标题「新建日程」、全宽 `WindowDragArea()` 拖拽热区，以及右侧 `28 × 28 pt` 圆形原生液态玻璃关闭按钮（复用 `GlassPointerFeedback` 与 `MingCute "xmark"`）。
- **表单控件与交互（对齐新 AI 表单样式）**：
  - 复用 `ChatFormView.swift` 的 `ChatFormMetrics`（`34 pt` 控件高、`10 pt` 圆角）、`ChatFormDatePopover`、`ChatFormTemporalPopover`、`ChatFormPickerTriggerButton` 与 `ChatFormClockGlyph`，全表单采用统一黑白单色语义表面与聚焦描边。
  - 开始时间与结束时间统一为「可编辑单行日期（`YYYY-MM-DD`）+ 月历弹层按钮」与「可编辑单行时间（`HH:MM`）+ 滚动时间弹层按钮」两列对齐排布，支持宽松输入与失焦/回车自动规范化；修改开始日期或时间自动保持原有时长同步平移结束时间，结束时间标签右侧实时显示时长或校验提示（`须晚于开始时间`），开始时间过早时显示 `须晚于当前时间`。
  - 地点、目标日历（移除多余蓝色圆点，改为全宽统一输入表面）与多行备注统一至相同表单控件视觉体系；错误提示以紧凑警告条常驻底栏上方，底栏「取消」「创建」均使用原生玻璃胶囊按钮（主操作为单色 prominent 样式）。

## 实际执行结果

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：全部通过。
- `xcodegen generate` + Debug `xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：成功（`BUILD SUCCEEDED`）。
- `python3 App/Tests/run-calendar-editor-regression.py --snapshot-dir build/calendar-editor-review`：通过（含模型校验、开始日期/时间修改保时长、结束时间独立调整、过去时间/倒挂校验、真实鼠标点击打开单色月历与滚动时间弹层）。
- `python3 App/Tests/run-agent-reply-regression.py --forms-only --time-preview`：通过，确认共享表单控件开放为内部可见后 AI 对话表单行为不受影响。
- `python3 App/Tests/check-localization.py`：本次新增键（`须晚于当前时间`、`须晚于开始时间`）及日程相关键在中英文表中均无报错；脚本报告的既有告警（`剪贴板历史` 重复键及 `ToolResultCard.swift` Core 键）为本任务外既有项。

## 已查看的实际窗口与弹层截图

- 浅色 / 深色常规状态：[calendar-light.png](../../build/calendar-editor-review/calendar-light.png)、[calendar-dark.png](../../build/calendar-editor-review/calendar-dark.png)
- 深色校验提示与错误横幅状态：[calendar-error-dark.png](../../build/calendar-editor-review/calendar-error-dark.png)（已复核备注框无裁切、错误条与禁用态清晰）
- 浅色创建中状态：[calendar-saving-light.png](../../build/calendar-editor-review/calendar-saving-light.png)
- 真实点击触发的日期与时间弹层：[calendar-date-popover-dark.png](../../build/calendar-editor-review/calendar-date-popover-dark.png)、[calendar-time-popover-dark.png](../../build/calendar-editor-review/calendar-time-popover-dark.png)

截图与编译产物位于已忽略的 `build/` 目录。本次未执行真实系统日历写入，也未在 macOS 14/15 实机验证。
