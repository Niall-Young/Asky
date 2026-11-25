# 智能体个性化配置：亲和 / 严谨风格与自定义提示词

日期：2026-11-25

## 变更

- 移除“设置 › 智能体”中直接暴露和编辑整段内置系统提示词的「系统提示词 / 编辑」区域，改为类似 ChatGPT 个性化的「个性化」卡片：
  - **回复风格**：原生下拉选择「亲和」（默认）与「严谨」，附对应 14 pt 次要说明，切换即刻保存并在下一轮对话热生效。
  - **自定义提示词**：原生多行输入框（`SettingsMultilineTextEditor` 新增内置占位符绘制与辅助功能占位值），默认留空不暴露任何内置提示词正文，支持保存、取消修改与清空；空白或清空时回退为仅使用所选风格。
- 在 `Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift` 中新增 `AgentPromptStyle`（`.friendly` / `.rigorous`）、`AgentPromptConfiguration` 与全新内置严谨风格人设 `rigorousSystemPrompt`，并将内置人设收归核心层内部（不向 App 层暴露）；最终系统提示词按 `runtimeProtocolPrompt → guidance → capabilities → personaPrompt(for: style) → optional customInstructionsBlock` 顺序组装，确保自定义提示词叠加在所选风格与运行时协议之上。
- 更新 `WireProtocol`、`AgentHost`、`NativeRuntime` 与 `AppModel`（`AppSettings.agentPromptStyleID` + `agentCustomInstructions`），旧版包含 `agentSystemPrompt` 或未知风格 ID 的持久化配置可安全解码回默认「亲和」与空自定义提示词，不会泄漏旧内置提示词或重置其他设置。
- 同步更新 `App/Resources/zh-Hans.lproj/Localizable.strings` 与 `App/Resources/en.lproj/Localizable.strings`（中文文案末尾不加句号），并更新 `docs/agent-runtime.md`。

## 实际验证

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore`：通过（含 `AgentHostTests` 58 项测试、`NativeRuntimeTests.promptStyleAndCustomInstructionsUpdateLive` 等全量测试）。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过（`** BUILD SUCCEEDED **`）。
- `python3 App/Tests/run-settings-regression.py --agent-prompt -AppleLanguages '(zh-Hans)'`：通过（验证默认亲和风格、无旧版「编辑」按钮、自定义输入框默认留空、旧配置与无效风格 ID 安全解码、切换严谨风格与持久化、空白不启用保存、自定义提示词保存与重启持久化、清空恢复）。
- 人工查看明暗模式及填写态原生设置窗口截图（`build/settings-agent-personalization-{light,dark}.png` 与 `build/settings-agent-personalization-filled-light.png`）：「对话历史」「记忆」「个性化」三张卡片在 900 × 700 窗口内完整呈现，无多余滚动，占位符排版清晰，风格切换与已保存对勾反馈正常。
- 注：`python3 App/Tests/check-localization.py` 报告仓库既有重复键 `['剪贴板历史']`（非本次修改引入），本次新增本地化键无缺失、重复或格式参数问题。

## 产物与边界

- 回归截图与构建产物位于 `build/`，不提交。
- 本次未运行真实外部模型在线请求；风格切换与自定义提示词分层拼接由 `NativeRuntimeTests` 使用 mock transport 验证。
