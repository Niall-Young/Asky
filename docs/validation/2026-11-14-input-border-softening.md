# 浅色输入框描边减弱

日期：2026-11-14

- 浅色未聚焦输入框的描边由 8% 黑色降为 2% 黑色，保留 12% 白色填充。
- 文本、密码、搜索、下拉和聊天表单共用此描边；尺寸与圆角保持原样。
- 聚焦时保留 2 pt 强调色边框。增强对比度时保留原 8% 描边，暗色外观不变。

## 验证

- `xcodegen generate`：通过。
- README 的 Debug `xcodebuild` 命令：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- 前两次设置回归编译分别因 AgentView.swift 和 Contracts.o 被其他任务修改而中断，不计为通过。
- 使用 `build/InputBorderSnapshot/` 固定源码和 `build/InputBorderDerivedData/` 固定构建产物后，`--settings-focus` 回归通过：深浅色下的输入框内点击、输入切换、外部失焦和值保留均通过。
- 新编译的隔离设置预览已通过电脑界面切换到浅色终端页，目视确认触发指令、工作目录和终端下拉的未聚焦边界变轻；未将预览结果等同于正式安装包验收。Debug 应用已重新构建并启动。

## 文档与产物

- README: unchanged — 仅视觉细节修正，既有开发和使用命令不变。
- AGENTS.md: unchanged — 不涉及持久开发规则或模块边界。
- 验证截图、源码副本及二进制沿用既有 `build/` 忽略规则。
