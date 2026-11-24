# AI 对话表单样式优化验证

日期：2026-11-24。按用户要求优化 AI 对话内嵌表单的控件视觉与交互，延续 Asky 的黑白单色语义体系（`ThemeColor` / `SettingsPalette`）并同时适配浅色、深色与增强对比度外观：

- **单选（`radio`）**：改为类似 Muse 的全宽按钮式选项行（38 pt 最小高、10 pt 圆角）；未选中态使用低对比虚线边框与轻填充，选中态切换为 1.5 pt 实线高对比描边、轻提亮底色及右侧单色实心圆形勾选徽标（`kBackgroundPrimary` + `textInverted`），其余未选项与已提交状态下的未选项柔和降噪。`allowCustom: true` 的「自己填写」沿用同一按钮行样式，选中后在下方展开同规格文本输入框。
- **多选（`multi`）**：沿用同款全宽按钮行，右侧常驻 18 × 18 pt 圆角方形复选框（未选为空心描边、已选为单色实心填充 + `MingCute-check` 勾选，同时行边框切为实线高亮）。
- **时间 / 时长与日期（`time` / `duration` / `date`）**：统一为「可编辑单行输入框 + 右侧图标触发按钮」（34 pt 高、10 pt 圆角，等宽数字），与文本输入框和下拉选择共用同一表单控件高度与圆角（仅通过 `ChatFormView` 作用域覆盖环境变量，不影响设置页与日程编辑弹窗）。
  - 输入框支持直接键入常见格式（如 `9:5`、`14：30`、`1430`、`2026/11/5`、`20261124`），失焦或回车自动规范化或回退到上一个合法值；单单位时长在输入框右侧附轻量单位提示。
  - 点击时间 / 时长按钮弹出单色样式的分列滚动选择弹层（实时预览值、「现在」/「归零」、上下边缘渐隐滚动列与「完成」）；点击日期按钮弹出单色样式月历弹层（含「今天」与「完成」）。

## 实际执行结果

- `xcodegen generate` + Debug `xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：成功（`BUILD SUCCEEDED`）。
- `App/Tests/ChatFormParserRegression.swift`：通过（含宽松时间/时长及日期输入解析与严格校验断言）。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：全部通过。
- `App/Tests/run-agent-reply-regression.py` 全部表单回归：
  - `--forms-only --radio-preview`：通过（真实鼠标点击切换单选与多选复选框行、隔离多组单选、保留历史与防重复提交）。
  - `--forms-only --custom-preview`：通过（含「自己填写」按钮行展开自定义输入与草稿保留）。
  - `--forms-only --time-preview`：通过（含输入框直接输入、点击按钮打开时间弹层、真实点击弹层分钟项 `31` 更新为 `14:31` 并恢复 `14:30`，以及日期弹层打开）。
  - `--forms-only --components-preview`：通过（时分秒、仅分秒、仅秒钟组合及单单位后缀展示）。
  - `--prefill-preview` 与 `--latex-form-preview`：全部通过。
- `App/Tests/run-calendar-editor-regression.py`：通过，确认短信日程弹窗未受影响。
- `python3 App/Tests/check-localization.py`：本次新增键（`选择时间`、`选择时长`、`选择日期`、`归零`、`今天`、`完成`）在中英文表均无报错；脚本报告的其余告警均为本任务外的既有键。

## 已查看的实际窗口与弹层截图

- 单选与多选（浅色 / 深色 / 560 pt 窄窗）：[radio-light.png](../../build/form-review/radio-light.png)、[radio-dark.png](../../build/form-review/radio-dark.png)、[radio-narrow.png](../../build/form-review/radio-narrow.png)
- 自定义单选与回填表单：[custom-light.png](../../build/form-review/custom-light.png)、[custom-dark.png](../../build/form-review/custom-dark.png)、[prefill-light.png](../../build/form-review/prefill-light.png)、[prefill-dark.png](../../build/form-review/prefill-dark.png)、[latex-light.png](../../build/form-review/latex-light.png)、[latex-dark.png](../../build/form-review/latex-dark.png)
- 时间 / 时长与组件表单：[time-light.png](../../build/form-review/time-light.png)、[time-dark.png](../../build/form-review/time-dark.png)、[components-light.png](../../build/form-review/components-light.png)、[components-dark.png](../../build/form-review/components-dark.png)
- 真实窗口时间与日期弹层（`screencapture`）：[time-popover-dark.png](../../build/form-review/time-popover-dark.png)、[date-popover-dark.png](../../build/form-review/date-popover-dark.png)（并已复核时间弹层上下边缘渐隐修复后的截图）

截图与编译产物位于已忽略的 `build/` 目录。本次未调用真实模型，也未在 macOS 14/15 实机验证。
