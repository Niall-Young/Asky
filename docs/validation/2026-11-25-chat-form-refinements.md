# AI 对话表单交互与视觉收敛验证

日期：2026-11-25。根据用户评审反馈完成以下 AI 对话表单（`asky-form`）优化：

- **消除单选 / 多选点击布局偏移并柔化选中态与禁用态**：
  - `ChatFormOptionRow` 固定 14 pt 常规字重与 18 × 18 pt 指示槽，避免选中切换导致文字宽度与行高抖动。
  - 选中态边框收轻为 1 pt 柔和实线（浅色黑 28% / 深色白 34%），底色收轻（浅色白 46% / 深色白 6.5%）；已提交/禁用态的选中项使用低对比边框（14% / 16%）、柔和底色、`kTextSubtle` 文字与 32% 中性勾选徽标，不再在已禁用表单中显得突兀。
- **移除下拉 `select` 控件**：
  - `ChatForm.Field.Kind` 移除 `.select`，历史记录或旧输出中的 `"type":"select"` 自动兼容解码为 `.radio`，统一使用全宽单选按钮行（支持 `allowCustom: true`）；系统提示词 `NativeAgentPrompt` 同步移除 `select`，所有选择类字段仅使用 `radio` 或 `multi`。
- **合并日期与时间选择（`datetime`）**：
  - 新增 `datetime` 字段（格式 `yyyy-MM-dd HH:mm`，支持 `components` 定制秒钟及宽松输入如 `2026/11/5 9:5`、`20261125 1430`），触发按钮使用时钟图标（`ChatFormClockGlyph`），点击弹出左右布局的 `ChatFormDateTimePopover`（左侧单色 `CalendarMonthPicker`，右侧等高分列滚动时间选择器，底栏附实时预览、「现在」与「完成」）；同时保留 `date`、`time`、`duration` 兼容纯日期/纯时刻/时长场景。
- **黑白单色品牌提交按钮**：
  - `ChatFormSubmitButton` 改为高对比黑白单色主按钮（浅色黑底白字 / 深色白底黑字，10 pt 圆角、34 pt 高），禁用态使用柔和中性灰底与禁用文字色。
- **保证表单始终位于气泡末尾**：
  - `ChatFormParser.parse` 将表单后的尾随正文统一合入表单上方，确保交互表单与提交按钮始终锚定在气泡最底部；系统提示词同步要求将说明全部写在表单之前、闭合围栏后不再输出文字。
- **放宽标签字号与纵向间距节奏**：
  - 表单字段标签与必填 `*` 调整为与正文一致的 `14 pt medium`；标签与控件间距放宽为 `10 pt`，字段间距放宽为 `22 pt`，气泡正文与表单块之间放宽为 `20 pt`。

## 实际执行结果

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：全部通过。
- `xcodegen generate` + Debug `xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：成功（`BUILD SUCCEEDED`）。
- `App/Tests/ChatFormParserRegression.swift`：通过（含旧 `select` 兼容解码、`datetime` 宽松输入与严格校验、尾随正文重排至表单上方断言）。
- `App/Tests/run-agent-reply-regression.py` 全部表单回归：
  - `--forms-only`：通过（验证无 `NSPopUpButton`、尾随文本移至表单上方、黑白品牌提交按钮、已提交只读态）。
  - `--forms-only --radio-preview`：通过（验证单选/多选点击前后几何尺寸与兄弟行 Y 坐标零偏移 `< 0.01 pt`，以及旧 `select` 渲染为单选行）。
  - `--forms-only --custom-preview`：通过（含「自己填写」展开自定义输入与草稿保留）。
  - `--forms-only --time-preview`：通过（验证 `datetime` 宽松输入规范化、点击时钟按钮弹出左右合并弹层、真实点击月历日期 `2026-11-26` 与分钟列 `31` 同步更新为 `2026-11-26 14:31` 并恢复）。
  - `--forms-only --components-preview`、`--prefill-preview`、`--latex-form-preview`：全部通过。
- `python3 App/Tests/check-localization.py`：新增键 `选择日期与时间`（中英文）无缺失告警。

## 已查看的实际窗口与弹层截图

- 默认表单与提交态：[default-light.png](../../build/form-review-v2/default-light.png)、[default-dark.png](../../build/form-review-v2/default-dark.png)、[submitted-readonly.png](../../build/form-review-v2/submitted-readonly.png)
- 单选 / 多选与自定义输入：[radio-light.png](../../build/form-review-v2/radio-light.png)、[custom-dark.png](../../build/form-review-v2/custom-dark.png)
- 合并日期与时间左右弹层：[datetime-popover-dark.png](../../build/form-review-v2/datetime-popover-dark.png)、[datetime-popover-light.png](../../build/form-review-v2/datetime-popover-light.png)

本次未调用真实模型，也未在 macOS 14/15 实机验证。
