# 修复日程表单复用记忆中过期日历列表的问题

日期：2026-11-25

## 问题背景

当长期记忆（`MEMORY.md`）中残留过去记录的日历名称列表与系统默认日历（例如已删除的「大麦」日历）时，模型在生成 `asky-form` 询问日程目标日历前跳过了 `calendar_list_calendars`，直接将过期记忆中的列表和默认值填入单选框。

## 变更

- [NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift)：
  - 明确要求在创建日程以及在回复或 `asky-form` 表单中列出、预选、询问目标日历前，必须先在本轮调用 `calendar_list_calendars` 获取实时日历列表与默认日历，严禁从记忆或历史对话读取日历名称、列表或默认日历。
  - 明确已有可写默认日历或唯一可写日历时不必在表单中再追问“加到哪个日历”。
  - 移除提示词中对特定日历名「大麦」的硬编码示例，改为通用表述，并强调历史对话与记忆既不能替代本轮实时查询，也不能覆盖本次工具返回信息。
- [MemoryExtractor.swift](../../Packages/KulaCore/Sources/Memory/MemoryExtractor.swift)：
  - 在禁止写入记忆的条目中明确列出系统实时可查的易变状态（当前日历名称列表、系统默认日历、联系人号码、应用列表）。
- [MemoryConsolidator.swift](../../Packages/KulaCore/Sources/Memory/MemoryConsolidator.swift)：
  - 在定期整理规则中补充清理可由系统工具实时查询的易变状态（当前日历名称列表、系统默认日历、提醒列表、联系人号码等）。
- [NativeRuntimeTests.swift](../../Packages/KulaCore/Tests/AgentHostTests/NativeRuntimeTests.swift)、[MemoryExtractorTests.swift](../../Packages/KulaCore/Tests/MemoryTests/MemoryExtractorTests.swift)、[MemoryConsolidatorTests.swift](../../Packages/KulaCore/Tests/MemoryTests/MemoryConsolidatorTests.swift)：
  - 新增提示词与记忆整理约束回归测试。
- 本机清理：移除用户本地 `~/Library/Application Support/KulaHere/Memory/MEMORY.md` 中过期的日历列表条目。

## 实际验证

| 检查 | 结果 |
| --- | --- |
| `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | 通过（全部测试目标通过，含 `AgentHostTests` 52 tests in 6 suites、`MemoryTests` 15 tests in 3 suites 等，0 failures） |

## 边界说明

- 本次仅修改 `Packages/KulaCore` 内提示词、记忆整理提示词与对应单元测试，未修改 `App/` 代码，因此未重新生成 Xcode 工程或调用真实外部 LLM API 进行线上生成验证。
