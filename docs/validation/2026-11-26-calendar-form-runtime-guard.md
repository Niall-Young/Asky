# 新建日程表单强制先查日历并校验目标日历选项验证

日期：2026-11-26

## 问题背景

在用户发送“我要创建一个日程”且尚未提供标题与时间时，模型直接跳过了 `calendar_list_calendars` 调用，直接输出仅包含 `title`、`slot`、`location` 的 `asky-form` 表单，导致存在多个可写日历（如“个人”“工作”）时表单依然缺少目标日历单选字段。

## 变更

- [NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift)：
  - 明确只要用户要创建日程——包括信息尚不完整、准备通过 `asky-form` 表单收集标题或时间之前——都必须先在本轮静默调用 `calendar_list_calendars`，不得因为还没到调用 `calendar_create_event` 这一步就跳过查询。
- [NativeCalendarFormGuard.swift](../../Packages/KulaCore/Sources/AgentHost/NativeCalendarFormGuard.swift) 与 [NativeRuntime.swift](../../Packages/KulaCore/Sources/AgentHost/NativeRuntime.swift)：
  - 在运行时发布草稿前新增新建日程表单守卫：当 `calendar_list_calendars` 与 `calendar_create_event` 均可用且草稿输出新建日程 `asky-form` 时，若本轮尚未调用 `calendar_list_calendars`，拦截草稿并要求模型先调用该工具；若已调用且返回多个可写日历但表单仍缺少合规的目标日历 `radio` 字段（`allowCustom != true`、选项与实时可写日历一致且 `defaultValue` 有效），拦截草稿并提示模型补齐。
  - 单个可写日历或非日程表单（如提醒事项表单）直接放行，不额外拦截。
- [NativeRuntimeTests.swift](../../Packages/KulaCore/Tests/AgentHostTests/NativeRuntimeTests.swift)：
  - 新增 `calendarCreationFormGuardEnforcesLiveListAndCalendarRadioField` 与 `calendarCreationFormGuardAllowsSingleWritableCalendarAndReminderForms` 测试。

## 实际验证

| 检查 | 结果 |
| --- | --- |
| `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | 通过（全部测试目标通过，含 `AgentHostTests` 62 tests in 7 suites，新增守卫测试通过，0 failures） |

## 边界说明

- 本次仅修改 `Packages/KulaCore` 提示词、运行时守卫与单元测试，未修改 `App/` 源码。
