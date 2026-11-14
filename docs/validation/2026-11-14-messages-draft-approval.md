# 短信草稿重复审批修复

## 问题与改动

`MessagesDraftTool` 将 `messages_prepare_draft` 声明为 `.always`，导致自动审批模式下，用户已明确要求准备短信仍会出现“准备信息草稿？”确认框。

改为现有 `.explicitDirectOtherwiseConfirm` 策略：明确请求通过收件人与正文校验后直接交接；AI 推导的请求仍返回建议，外部 MCP 请求仍需原生确认。工具继续只打开草稿并复制正文，返回 `sent: false`，不自动发送。同步模型提示词和中英文工具描述，避免模型在执行前重复询问。

## 实际验证

- 修复前：新增 `MessagesDraftApprovalTests` 通过真实工具定义与收件人校验进入 ToolService；明确 Agent / Launcher 请求被确认回调拒绝，回归用例失败，复现问题。
- 修复后：`cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` 通过，13 个测试目标共 351 个 Swift Testing 测试。
- 新增 4 个测试、8 个参数场景：Agent / Launcher 明确请求不调用确认；两种审批模式下外部 MCP 仍调用确认且拒绝后不执行；AI 建议不执行；缺少收件人、无效收件人、空正文在执行前失败。
- `plutil -lint` 检查两种语言的 `Core.strings` 通过。
- `xcodegen generate` 及 README 中的 Debug `xcodebuild` 命令通过，生成 `build/DerivedData/Build/Products/Debug/Asky.app`。
- `git diff --check` 通过；README 两种语言、PRD 与原生工具文档同步。

## 验证范围

测试替换最终系统交接为计数探针，保留真实工具定义、参数校验与 ToolService 审批流程，没有打开 Messages、修改剪贴板或发送短信。未调用真实模型重走截图中的会话，也未重启当前运行的 Asky；现有进程需重启到新构建后才载入修复。

工作区已有头像与文本选择等并行修改；本次提交仅包含短信草稿修复。Debug 构建基于当时完整工作区，不能视为其他改动已通过功能验收。构建产物沿用既有 `build/` 忽略规则。

README: updated — 同步中英文短信草稿交接与确认行为。

AGENTS.md: unchanged — 工具仍经 ToolService，未改变模块边界、构建入口或持久开发规范。
