# 消除防御性免责文案提示词调整验证

日期：2026-11-19。

## 根因定位

1. `NativeAgentPrompt.defaultSystemPrompt` 虽已禁止以「说明一下」「需要强调的是」开头或结尾补「至于……我没查到公开说法」，但仍保留「信息不全或不确定时坦白说不清楚」及宽泛的「信息缺口影响决策时说明」条款，模型容易换壳生成「不过我得先承认：我这轮没有你那个群的反馈数据……所以下面是我基于已知信息能给的判断，不是查证结论」这类怕担责、先撇清关系的防御性叠甲文案。
2. `NativeAgentPrompt.runtimeProtocolPrompt` 中的「区分来源事实、推断和未核实内容」会被模型字面化为在正文中加注「以下只是判断，不是查证结论」式自我免责。
3. `NativeAgentPrompt.webSearchCapabilities(hasWebSearch:)` 末尾的「确实查不到时再坦白说明」在用户提及私密群聊等本就不可公开检索的场景时，容易诱导模型专门交代「进不去/没数据」的能力边界。

## 变更

- [NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift)：
  - `defaultSystemPrompt`：改为要求直接为判断负责，明确禁止「我得先承认」「先说清楚」等提前撇清关系的口吻、禁止专门交代显而易见的能力边界（如看不到私密群聊、没法替用户亲测）以及「以下只是基于已知信息的判断，不是查证结论」类自我免责；将「信息不全或不确定时坦白说不清楚」收紧为「真不知道就直接说不知道，不硬编也不绕弯叠甲」。
  - `runtimeProtocolPrompt`：将「区分来源事实、推断和未核实内容」调整为「事实陈述要有本次来源支撑，个人推断直接用正常语气表达，不必用‘这是判断不是结论’之类的话自我免责，也不把猜测写成已查证的事实」。
  - `webSearchCapabilities(hasWebSearch:)`：补充说明私密群聊等本就无法检索的内容无需专门解释「进不去/没数据」，直接就公开可查部分和问题本身作答。
- [NativeRuntimeTests.swift](../../Packages/KulaCore/Tests/AgentHostTests/NativeRuntimeTests.swift)：
  - 新增 `antiDefensiveDisclaimerGuidancePresentAcrossLayers`，验证三层提示词均已移除旧诱导表述并包含新的反防御性免责约束。

## 已执行检查

| 检查 | 结果 |
| --- | --- |
| `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | 通过（含新增 `antiDefensiveDisclaimerGuidancePresentAcrossLayers`，`AgentHostTests` 及全部 Swift Testing / XCTest 用例通过） |
