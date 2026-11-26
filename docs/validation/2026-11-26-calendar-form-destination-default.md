# 新建日程表单多日历默认预选目标日历验证

日期：2026-11-26

## 问题背景

此前在 [NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift) 中要求“已有可写默认日历或唯一可写日历时，不必在表单中再追问‘加到哪个日历’”，导致系统设置了默认日历时，AI 在对话中输出的新建日程 `asky-form` 表单不再提供个人、工作或自定义日历分组选项，用户无法在表单内直接切换目标日历。

## 变更

- [NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift)：
  - 保留调用 `calendar_list_calendars` 获取实时列表并禁止读取记忆/历史缓存的要求，以及参数齐全时直接按默认或唯一可写日历创建的逻辑。
  - 明确当需要通过 `asky-form` 表单收集新建日程信息且本次返回多个可写日历时，应在表单中加入目标日历单选字段（`radio`，不设 `allowCustom`），列出本次返回的实时可写日历名称，并用 `defaultValue` 预选一个日历（用户已指定则预选该日历，否则优先预选可写默认日历，无可写默认日历时预选首个可写日历）；仅有一个可写日历时无需该字段。
- [NativeRuntimeTests.swift](../../Packages/KulaCore/Tests/AgentHostTests/NativeRuntimeTests.swift)：
  - 在 `calendarFormRequiresLiveCalendarListWithoutMemoryFallback` 中补充目标日历单选字段与 `defaultValue` 预选规则的断言。

## 实际验证

| 检查 | 结果 |
| --- | --- |
| `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | 通过（全部测试目标通过，含 `AgentHostTests` 60 tests in 7 suites 及 `calendarFormRequiresLiveCalendarListWithoutMemoryFallback()`，0 failures） |

## 边界说明

- 本次仅修改 `Packages/KulaCore` 提示词与单元测试，未修改 `App/` 代码，未调用真实外部 LLM API 进行线上生成验证。
