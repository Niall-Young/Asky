# 2026-11-25 历史持久化结果卡片展示归一化验证

## 变更范围

- [ToolResultCard.swift](../../Packages/KulaCore/Sources/Contracts/ToolResultCard.swift)：
  - 新增 `ToolResultCard.normalizedForDisplay(calendar:)`，将旧版本持久化在 `MessagePresentation.resultCard` 中的历史卡片幂等地归一化为当前精简展示格式：
    - 备忘录卡片（`.note`）去除旧路径 `subtitle`（如 `iCloud › Notes`）与多余 `metadata`，并兼容更早期 `footnote` 摘要迁移。
    - 提醒事项卡片（`.reminder`）清空旧备注 `metadata`，并在 `subtitle` 中剔除默认列表后缀（`提醒` / `提醒事项` / `Reminders`），保留自定义列表名。
    - 日历日程卡片（`.calendarSchedule`）将旧 `N 个日程` 主标题替换为日期或日期范围（单日优先使用 `action.target` ISO 日期补全星期），去除列表行冗余日期与日历名小字，多日时合并短日期至右侧时间列；不影响新版带真实地点 `subtitle` 的卡片。
    - 全天单日程（`.calendarEvent`）、待办列表（`.reminderList`）、记忆（`.memory`）与多地点（`.mapPlaces`）卡片同步兼容旧版主标题与冗余小字。
- [AgentModel.swift](../../App/Sources/AgentModel.swift) 与 [ToolResultCardView.swift](../../App/Sources/ToolResultCardView.swift)：
  - 加载历史消息与渲染结果卡片时应用 `normalizedForDisplay()`，保证老对话中已保存的卡片无需重建数据库即可立即以新样式呈现，同时保持 `LocalStore` 存储序列化无损。
- [ToolResultCardTests.swift](../../Packages/KulaCore/Tests/ContractsTests/ToolResultCardTests.swift) 与 [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)：
  - 补充全部旧版卡片类型归一化与新版卡片幂等性单元测试；将 `--tool-result-cards` 原生窗口回归改为先持久化旧版日历日程、备忘录、提醒事项卡片，再经 `AgentModel.open` 加载并校验归一化结果与亮/暗模式真实窗口渲染。

## 实际执行检查

1. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（全部测试套件 0 失败）。
2. `xcodegen generate`：通过。
3. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`：通过（`** BUILD SUCCEEDED **`）。
4. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --tool-result-cards`：通过，已检查新构建真实窗口生成的 `build/tool-result-cards-light.png` 与 `build/tool-result-cards-dark.png`，确认历史持久化的日历日程、备忘录与提醒事项卡片在亮暗模式下均已去除路径、默认列表、备注段落与计数占位标题。
