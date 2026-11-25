# ToolResultCard 视觉重设计验证记录（2026-11-25）

## 变更范围

- [ToolResultCard.swift](../../Packages/KulaCore/Sources/Contracts/ToolResultCard.swift)：
  - `DetailRow` 新增向后兼容的可选字段 `dateLabel`，在 `calendar_search_events` 与 `reminders_list` 构建时写入单条日期与完整时段/非默认清单信息，同时保留原有 `headline`/`trailing`/`subtitle` 契约以兼容旧消息。
  - 日历与提醒卡片顶部标题改为按分组名动态拼接（如日历分组 `工作` → `工作日程`、提醒分组 `工作` → `工作事项提醒`；多分组或默认分组回退为 `日历日程` / `提醒事项`）。
  - 路线卡片类别标题更新为 `路线规划`，提醒卡片操作按钮文案更新为 `查看事项`，`memory_correct` 卡片标题与状态更新为 `更新记忆` / `记忆已更新`。
- [ToolResultCardTests.swift](../../Packages/KulaCore/Tests/ContractsTests/ToolResultCardTests.swift)：补充日程/提醒分组名标题、行级 `dateLabel`/自定义清单 `badge`、`路线规划`、`查看事项` 与 `memory_correct` 单测断言。
- [ToolResultCardView.swift](../../App/Sources/ToolResultCardView.swift)：按 Figma `142:608` 任务卡片规范重构：
  - 外框圆角 `24 pt`（连体气泡保留 `4 pt` 连接角）、`1 pt` `black4/white4` 内描边、`16 pt` 水平内边距。
  - 顶部区域调整为 `24 × 24 pt` 图标、`4 pt` 间距、`14 pt Regular` 主文字与 `1 pt` 分割线。
  - 日程与提醒改为「标题（14 Medium 70%）+ 时间 `|` 日期（16 Medium 90%，中间 `1×16 pt` 20% 竖线）+ 可选地点/清单（14 Regular 50%）」结构；多条列表采用 `16 pt` 间距，移除行间横线。
  - 备忘录、信息草稿、快捷指令与记忆采用 `16 pt Medium` 标题 + `14 pt Regular 50%` 两行截断摘要。
  - 路线规划支持「起点 `至` 终点」与 `1×12 pt` 竖线分隔距离/出发建议；地点列表统一为 `16 pt Medium` 名称 + `14 pt Regular 50%` 地址。
  - 底部按钮改为 `40 pt` 高、`12 pt` 圆角的柔和浅底样式（`backgroundPrimarySubtle`，`14 pt Medium` 70% 文字，悬停平滑过渡）。

## 实际执行的验证

1. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（全部 13 个测试目标共计 473 项测试全部通过）。
2. `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过（`** BUILD SUCCEEDED **`）。
3. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --tool-result-cards`：通过，已目视核验新构建实窗截图 `build/tool-result-cards-light.png` 与 `build/tool-result-cards-dark.png`，确认亮暗模式下头图尺寸、竖线分割、柔和按钮及历史卡片兼容渲染符合设计稿。
4. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --bubble-chain`：通过（`Rendered linked gaps: assistant=4.0 pt, user=4.0 pt`），已目视核验 `build/bubble-chain-light.png` 与 `build/bubble-chain-dark.png` 中的连体气泡衔接与新卡片视觉一致。
