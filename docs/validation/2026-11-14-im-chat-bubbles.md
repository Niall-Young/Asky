# Agent IM 气泡对话验证

日期：2026-11-14。

## 改动

- 用户靠右、Agent 靠左，统一圆角气泡；Agent 气泡下方保留复制和完成时间。
- 运行中的工具、过程说明、压缩状态、耗时和增量正文不展示；完整回答出现前只显示三点等待气泡。
- Markdown 各级标题使用普通正文的字号和字重；原生表单继续随完整回复显示。
- 历史记录保留原始工具与过程数据，但恢复后不展示这些记录；停止、错误和系统操作确认流程保留。

## 已执行

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `python3 App/Tests/run-agent-reply-regression.py --reply-activity-preview`：通过；使用临时会话和新编译的原生回归窗口，验证工具执行、流式片段及完整 message 到达时都只有等待占位，本轮结束后显示一次完整回答，历史重开不将过程说明混入最终结果。
- 同一新编译回归程序执行 `--forms-preview`：通过；验证原生文字输入、下拉选择、浅色/深色/560 pt 窄窗口截图、历史恢复与重复提交保护。
- 同一程序无参数执行回复回归：通过。
- `git diff --check`：通过。

已查看本轮生成的 `build/reply-activity-thinking.png`、`build/reply-activity-completed.png` 和 `build/form-narrow.png`，确认气泡、三点、普通正文标题、回复操作区和表单实际呈现。测试使用隔离数据，未请求真实模型或执行真实系统写入；不代表已安装版本更新或真实提供商验收。

## 文档与工作区

README 中英文、PRD、设计系统及 Runtime 说明已同步。AGENTS.md 无需修改：本次仅调整对话展示，原有原生组件、ToolService 和验证边界继续适用。

工作区原有未提交改动涉及相同视图、回归与文档，执行期间同文件也有外部改动；保留这些改动，本次不创建混合提交。构建、截图和日志沿用现有 `build/` 忽略规则。

## 对齐与动效修正

- 去掉复制按钮的负向偏移，将复制图标与气泡正文的左内距对齐；回复明确使用左对齐。
- 三点使用连续正弦相位驱动大小、透明度和轻微上下浮动，不再每 0.35 秒直接切换高亮点。
- 等待与回答气泡通过左上锚点共享几何尺寸，使用 0.32 秒弹簧衔接；正文和操作区淡入。减少动态效果时，三点静止，仅短淡入，不变形或位移。
- 重新执行工程生成、Debug 构建及 KulaCore 测试，均通过。共享构建产物在编译回归时被外部任务更新，改用 `build/im-polish-snapshot` 中的产物快照后，`--reply-activity-preview` 回归通过。
- 已查看新的 `reply-activity-thinking.png`、`reply-activity-thinking-pulse.png`、`reply-activity-transition.png` 和 `reply-activity-completed.png`：两次等待帧可见三点大小和位置变化；70 毫秒过渡帧可见正在扩大的背景与淡入正文；完成帧中的复制图标与正文左缘对齐。
- README: unchanged，原有气泡、等待和表单使用说明仍准确；精确动效同步至设计系统。AGENTS.md: unchanged，未改变开发或架构规则。

## 边距与表单层级修正

- 对话正文左右外距从 32 pt 改为 12 pt，与输入区和历史列表一致。
- 删除表单自身的 16 pt 内距、背景卡片和边框，表单直接排在回复气泡里。
- 聊天表单通过局部输入填充覆盖统一文本与选择控件底色：浅色为 55% 白色，深色沿用中性色；不修改设置页面默认样式。
- 日期改用与文本框相同的 24 pt 输入表面，保留月历弹层；时间/时长删除大块日程底板，只显示原有组件选择器。
- 工程生成、Debug 构建、KulaCore 测试通过；使用独立产物快照执行 `--forms-preview --components-preview` 通过，覆盖原生编辑、小时/分钟/秒钟选择、历史恢复及浅色/深色/560 pt 窄窗口。
- 已查看新生成的浅色与窄窗口组件截图，确认只有一层气泡背景、紧凑浅底输入表面及统一外边距。截图备份在 `build/im-form-flat-components-light.png` 和 `build/im-form-flat-components-narrow.png`。
- 同一新编译程序另执行普通 `--forms-preview` 通过；查看 `build/form-light.png`，确认日期字段也使用与文本、下拉一致的轻填充和紧凑高度。
- README: unchanged，本次仅修正既有界面表现，使用方法未改变；设计系统已同步。AGENTS.md: unchanged，原有约束继续适用。工作区仍有同文件的原有及外部改动，不创建混合提交。
