# 聊天选区与引用标签

日期：2026-11-14。

## 实现

- 原生聊天文字选区使用 Agent 当前配色的 45% 透明度，失焦后的选区仍保留配色。
- 拖选后出现独立窗口承载的横向玻璃菜单，提供复制和添加到对话；复制经 ToolService 的 MessageClipboard，公式附件转换为 LaTeX 原文。
- 引用复用上传附件组件，使用同版本 MingCute 文本图标，标签只显示「引用的文本」，不展示原文、摘要或大小；输入区支持移除，与文件、图片共用附件行。发送后的标签排在用户消息上方。
- 引用保存片段与来源消息 ID，通过可选 presentation 字段兼容旧历史；发送时加入 selected-quotes 上下文，后续历史上下文也保留引用。添加引用不自动发送；未配置模型时保留草稿，已进入发送流程的引用随用户消息保存。

## 已执行

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，包括引用落盘重开、旧 presentation 解码与上下文文本检查。
- `python3 App/Tests/run-agent-reply-regression.py --selection-preview`：通过。以新编译的真实 App 源码窗口检查五种配色 × 浅深外观、公式选区源码、菜单尺寸和屏幕边界；真实点击添加按钮，检查去重、输入焦点、配置失败保留、发送保存及历史恢复。
- 复用上述刚生成的 `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression` 运行 `--math-preview` 与 `--bottom-push`：通过公式解析、原生换行、浅深截图、短长对话、发送推移和等待状态回归。
- 检查 `build/selection-light.png`、`selection-dark.png`、`selection-draft.png`、`selection-sent.png`：选区随头像色，菜单横排，输入区及已发送消息使用文本标签，不暴露引用原文。截图和测试 bundle 沿用现有 `build/` 忽略规则。
- `git diff --check`：通过。

## 范围

自动化用临时数据与缺失的测试凭据运行发送路径；截图中的凭据错误为测试结果。未使用真实模型验证续问回答，未更换用户已安装应用，未发布 Release。菜单使用现有原生玻璃封装；未完成多显示器、跨段落拖选及辅助功能全矩阵验收。选区内容转换与复制入口已检查，但未回读系统剪贴板验证本次菜单复制结果。

README 已同步中英文功能说明与回归命令。AGENTS.md 保持不变：沿用现有 App、LocalStore、ToolService 边界和构建入口，无新项目级规则。
