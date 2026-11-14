# AI 澄清表单与自填回答

日期：2026-11-14。

## 行为

- AI 需要澄清需求、确认方案或收集缺失参数时，优先生成现有 `asky-form`；有合理候选时提供 radio 与 `allowCustom:true`，没有候选时使用 text。
- radio/select 增加可选 `allowCustom`；开启后显示「自己填写」，选中后可输入最多 4000 字的回答。预设答案与自填互斥，切换保留自填草稿；默认不替用户选择。
- 提交沿用同一会话的普通用户消息路径，保留聊天输入框草稿和附件，提交后关闭旧表单，系统操作继续遵循 ToolService 确认。

## 实际运行

1. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`（Packages/KulaCore）：通过，Swift Testing 43 个测试。
2. `xcodegen generate` 与 README 的 Debug `xcodebuild`：通过。
3. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc App/Sources/ChatForm.swift App/Tests/ChatFormParserRegression.swift -o build/clarification-parser && build/clarification-parser`：通过。覆盖 radio/select 自填与封闭选项兼容、空白/超长/多答案拒绝、原有解析与时间字段回归。
4. `python3 App/Tests/run-agent-reply-regression.py --forms-preview --custom-preview`：通过。实际原生窗口验证 radio 与下拉自填输入、切回预设选项、自填草稿恢复、字段隔离、同会话用户消息落库、双重提交拒绝、历史重开禁用、输入区草稿和附件保留。也运行了脚本原有回复与历史回归。
5. 检查 `build/form-narrow.png`：560 pt 窗口中选项与自填输入显示正常；回归同时生成浅色与深色截图。
6. 中英文 Localizable.strings 经 `plutil -lint` 通过；`git diff --check` 通过。

## 范围

UI 回归使用隔离数据与故意不存在的测试凭证，验证到正常用户消息提交与请求失败后的历史保存；没有调用真实模型，未验证模型遵循新提示生成表单及提交后真实模型续答。已生成新的 Debug 应用，未替换 /Applications 中的安装版本，未打包或发布。

README 已同步中英文功能说明与回归命令。AGENTS.md 及现有指南适用于本次修改，无新增模块边界或开发规则，保持不变。日志、测试应用和截图沿用现有 `build/` 忽略规则。
