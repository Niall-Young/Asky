# 2026-11-25 原生结果卡片冗余小字与日程日期主标题清理验证

## 变更范围

- `Packages/KulaCore/Sources/Contracts/ToolResultCard.swift`：
  - 备忘录卡片（`noteCard`）移除 `folder`（如 `iCloud › Notes`）次要路径小字。
  - 提醒事项卡片（`reminderCard`）不再将 `arguments["notes"]` 渲染为底部灰色 `metadata`，并在默认列表（`提醒` / `提醒事项` / `Reminders`）时省略冗余列表名。
  - 日历日程卡片（`calendarScheduleCard`）主标题改用日期或日期范围（单日 `11月28日 周六`，多日 `11月28日 – 30日`）替代 `N 个日程` 计数文案；列表行移除冗余日期与日历名（仅保留显式地点），多日场景将短日期合并至右侧时间列；全天单日程卡片主标题同步改用日期。
  - 待办列表卡片（`reminderListCard`）、记忆卡片（`memoryCard`）与多地点卡片（`mapPlacesCard`）同步移除列表名/文件名小字与计数占位主标题。
- `App/Sources/ToolResultCardView.swift`：
  - 当卡片主标题与文本区为空时，去除列表行顶部的额外 `4pt` 留白。
- `Packages/KulaCore/Tests/ContractsTests/ToolResultCardTests.swift` 与 `App/Tests/AgentReplyRegression.swift`：
  - 补充备忘录、提醒事项、单日/多日日历日程、待办列表与记忆卡片单元测试，并将 `--tool-result-cards` 视觉回归切换为真实 `ToolResultCard.from(...)` 构建产物。

## 实际执行检查

1. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（全部测试套件 0 失败）。
2. `xcodegen generate`：通过。
3. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`：通过（`** BUILD SUCCEEDED **`）。
4. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --tool-result-cards`：通过，实际检查 `build/tool-result-cards-light.png` 与 `build/tool-result-cards-dark.png`，确认亮暗模式下日历日程以日期为主标题且无底部灰色小字、备忘录无目录路径、提醒事项无备注段落与冗余默认列表名。
