# 2026-11-25 原生结果卡片文字层级优化验证

## 变更范围

- `App/Sources/ToolResultCardView.swift`：
  - 将日历日程（`.calendarSchedule`）、待办列表（`.reminderList`）与多地点列表（`.mapPlaces` 含多行）纳入大字号主标题（`22pt semibold` `kText`），并与单个日程/提醒主标题的判定改为按标题语义判断（兼容中英文）。
  - 统一主标题下方全部内容文字（`title`、`subtitle`、`metadata`、`row.title`、`row.subtitle`、`row.trailing`）为 `14pt regular`，取消列表行主文与右侧时间/状态的加粗（`.medium` -> `.regular`），通过语义颜色拉分层级（主内容 `kText`、右侧时间/状态 `kTextSubtle`、次要说明与日期/分组 `kTextSubtlest`），行内上下间距调整为 `3pt`。
- `App/Tests/AgentReplyRegression.swift`：
  - 新增 `--tool-result-cards` 原生窗口渲染回归，覆盖单条/多条日历日程卡片与单日程卡片在浅色与深色模式下的实际窗口截图。

## 实际执行检查

1. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（全部测试套件 0 失败）。
2. `xcodegen generate`：通过。
3. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`：通过（`** BUILD SUCCEEDED **`）。
4. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --tool-result-cards`：通过，已检查新构建实际窗口生成的 `build/tool-result-cards-light.png` 与 `build/tool-result-cards-dark.png`，确认亮暗模式下主标题与下方列表行的字号、字重与颜色层级清晰拉开。
5. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --bubble-chain`：通过（`Rendered linked gaps: assistant=4.0 pt, user=4.0 pt`）。
