# Agent 主动协助与表单预填验证

日期：2026-11-14。

## 改动

- `NativeAgentPrompt` 增加主动推进、提问门槛和自然沟通原则；上下文与工具可查的信息先自行补齐，低风险细节允许合理默认，必要歧义才提问。
- 工具 `userRequested` 描述与历史上下文提示一致支持继续同一未完成且未撤回的明确任务，不将旧任务、待核实写入或额外推断当成新授权；确认仍由 ToolService 控制。
- `ChatForm.Field.defaultValue` 支持单值字符串及多选字符串数组，复用答案校验。无效默认值忽略；完整表单仅填充缺失答案，显式清空与编辑优先。
- `AgentModel` 在展示和按存储 schema 提交时合并默认值；未触碰的有效预填可直接提交，已提交快照不补填或改写。

## 实际执行

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc App/Sources/ChatForm.swift App/Tests/ChatFormParserRegression.swift -o build/chat-form-parser-regression`，随后执行二进制：通过。覆盖全部字段默认值、非法值/类型、清空与覆盖、未完成表单、原有流式解析与答案校验。
- `xcodegen generate`：通过。
- README 的 Debug `xcodebuild` 命令：通过，日志 `build/agent-prefill-build.log`。
- `python3 App/Tests/run-agent-reply-regression.py --prefill-preview`：通过，日志 `build/agent-prefill-native-test.log`。实际 SwiftUI/AppKit 控件检查、浅色/深色截图、未经编辑的默认值提交、编辑/清空、重开、提交快照与重复提交保护均通过。截图为 `build/form-prefill-light.png` 和 `build/form-prefill-dark.png`，已目视检查预填文本、选择、日期、时间、时长与自填内容。
- 工作区 `swift test`：首次通过；后一次包含并行工作新加入的 `NativeApprovalAuditTests` 时，`notes_append` 与 `calendar_update_event` 两个参数用例产生 6 个断言失败。该测试与其审批策略改动不属于本次，未修改或删除。
- 隔离核心全量 `swift test`：通过，日志 `build/agent-prefill-isolated-swift-test.log`。快照基于 `6af4c2f` 加本次两份 AgentHost 源码，保留仓库测试所需 `examples`、`PluginSupport` 和 `scripts`。最初复制遗漏插件 fixture 的运行失败，补齐后完整重跑通过；不以筛掉失败测试代替全量检查。
- 隔离 App 源码的 `--prefill-preview` 回归：通过，日志 `build/agent-prefill-isolated-native-test.log`。基于同一快照加本次 App 改动，使用已构建的 Debug 包模块编译实际界面与模型；确认不依赖其他未提交的头像、布局或表情功能。
- README 中英文同步、文档本地链接与 `git diff --check`：通过。沿用现有 `build/` 忽略规则。

## 验证边界

原生回归使用独立临时数据及不存在的测试凭据，验证实际用户消息提交与持久化，不调用真实模型，不写入用户日历或备忘录。表单截图使用固定测试内容，不能据此声称模型已稳定减少追问或自然表达。真实模型行为需使用同一组自然语言任务继续验证；未替换已安装应用或发布版本。

建议真实模型场景：直接查询“明天忙不忙”；无需询问语气即完成润色；承接已给出的会议日期/标题仅补开始时间；信息齐全直接调用工具；存在多个同名联系人时先查再问；用户烦躁时给出贴合事情的简短回应；不为预填表单重复要求操作授权。

README: updated — 同步主动协助、预填行为与原生回归命令。
AGENTS.md: unchanged — 未新增模块边界、工具链或持久开发约定。
