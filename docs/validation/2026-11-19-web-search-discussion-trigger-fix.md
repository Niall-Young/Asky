# 观点讨论场景下联网核实提醒修复验证

日期：2026-11-19。

## 根因定位

1. `NativeAgentPrompt.system(...)` 将 `persona`（`defaultSystemPrompt` 或用户自定义人设）置于系统提示词最末尾，而联网核实规则位于较长的 `runtimeProtocolPrompt` 前部。
2. 当用户在观点讨论、吐槽或承接上一轮搜索后的追问中提及新的可核实公开事实（如近期模型的真实用户反馈/社区口碑）时，模型易将其归类为纯聊天/讨论，直接触发人设中「信息不全时坦白说不清楚」的表达，而不是先调用 `web_search` 核实。
3. 联网核实规则不应写入用户可编辑的 `defaultSystemPrompt`（persona），避免用户自定义人设时被改掉。

## 变更

- [NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift)：
  - 保持 `defaultSystemPrompt` 为纯人设层，不含联网工具规则。
  - 新增 `webSearchCapabilities(hasWebSearch:)`，在 `web_search` 可用时紧邻 `persona` 之前注入请求级联网核实提醒，明确观点讨论、吐槽和承接上轮讨论中涉及近期事件、产品表现或社区口碑时先查证再接话，不以「手上没数据」或反问社区推给用户。
  - 强化 `runtimeProtocolPrompt` 中讨论/咨询、观点吐槽、用户口碑与社区评价、以及多轮新维度的联网核实规则。
- [NativeRuntime.swift](../../Packages/KulaCore/Sources/AgentHost/NativeRuntime.swift)：
  - 根据工具目录是否包含 `web_search`，向 `NativeAgentPrompt.system(...)` 传入 `hasWebSearch`。
- [NativeRuntimeTests.swift](../../Packages/KulaCore/Tests/AgentHostTests/NativeRuntimeTests.swift)：
  - 新增 `webSearchCapabilityInjectedOutsidePersona`，验证 `defaultSystemPrompt` 不含 `web_search`、启用 `web_search` 时即使使用自定义人设也会在人设前注入提醒，且未启用时不注入。

## 已执行检查

| 检查 | 结果 |
| --- | --- |
| `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | 通过（含新增 `webSearchCapabilityInjectedOutsidePersona`，83 个 Swift Testing 用例及全部 XCTest 用例通过） |
