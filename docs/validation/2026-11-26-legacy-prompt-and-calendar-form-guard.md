# 2026-11-26 旧版系统提示词升级保留与新建日程表单边界修复验证

## 变更范围

1. **旧版系统提示词保留与只读查看/复制（v0.3.9 → v0.3.10+）**
   - [AppModel.swift](../../App/Sources/AppModel.swift)：恢复 `AppSettings.agentSystemPrompt` 字段并新增 `preservedLegacySystemPrompt`，确保升级后修改任意其他设置时不会覆写丢失旧版自定义提示词，且不自动启用到 `agentPromptConfiguration`。
   - [ClipboardAccess.swift](../../Packages/KulaCore/Sources/ToolService/ClipboardAccess.swift)：新增 `ClipboardAccess.copyText(_:to:)`，保持剪贴板写入经由 `ToolService`。
   - [SettingsView.swift](../../App/Sources/SettingsView.swift)：当存在非空 `preservedLegacySystemPrompt` 时，在「个性化」分区展示只读「旧版系统提示词」卡片，提供「复制旧文本」与「移除旧文本」按钮；中英文文案同步至 [Localizable.strings](../../App/Resources/zh-Hans.lproj/Localizable.strings) 与 [Localizable.strings](../../App/Resources/en.lproj/Localizable.strings)。

2. **新建日程表单守卫与提示词边界修复**
   - [NativeCalendarFormGuard.swift](../../Packages/KulaCore/Sources/AgentHost/NativeCalendarFormGuard.swift)：`WritableCalendar` 保留 `id` 与 `account`，移除按名称去重；当多个账户存在同名可写日历时，生成带所属账户的选项标签（如 `Calendar（iCloud）`、`Calendar（Google）`）并在纠偏中附带对应 ID。
   - [NativeRuntime.swift](../../Packages/KulaCore/Sources/AgentHost/NativeRuntime.swift) 与 [NativeCalendarFormGuard.swift](../../Packages/KulaCore/Sources/AgentHost/NativeCalendarFormGuard.swift)：引入 `CalendarListState`（`.notFetched` / `.failed` / `.loaded`），当 `calendar_list_calendars` 查询失败或无可写日历时拦截新建日程表单，要求仅展示失败说明与单选「重试」按钮。
   - [NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift)：同步补充同名日历附带账户、按 ID 创建与查询失败时仅提供「重试」的指令。

## 已执行验证

1. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
   - 结果：全部通过（含 [NativeRuntimeTests.swift](../../Packages/KulaCore/Tests/AgentHostTests/NativeRuntimeTests.swift) 新增的同名多账户日历去重防护测试、查询失败拦截并要求「重试」测试及零可写日历拦截测试）。
2. `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`
   - 结果：`BUILD SUCCEEDED`。
3. `python3 App/Tests/run-settings-regression.py --agent-prompt`
   - 结果：通过（`Agent personalization settings: friendly/rigorous style, empty custom prompt, legacy upgrade preservation/copy/remove, persistence and clear passed`）。
   - 验证内容：模拟 v0.3.9 JSON 写入 SQLite → 升级加载 → 修改无关设置（`clipboardEnabled`、`agentPromptStyle`）→ 再次加载确认旧文本仍在且未自动启用 → 点击「复制旧文本」核验剪贴板内容一致 → 点击「移除旧文本」核验持久化清除，并目视检查了新构建窗口截图 `build/settings-agent-personalization-legacy-light.png`。
