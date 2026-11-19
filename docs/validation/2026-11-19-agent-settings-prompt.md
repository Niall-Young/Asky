# 智能体设置页与系统提示词编辑

日期：2026-11-19

## 变更

- 侧栏“智能配置”分组调整顺序，将 MCP 移至最后，依次为：模型配置、智能体、数据来源、MCP。
- 原“数据管理”改名为“智能体”（英文 Agent），侧栏图标更换为已打包的 MingCute 大脑图标（`MingCute-brain`）。
- 在“智能体”页面原有“对话历史”与“记忆”下方新增“提示词”卡片，默认收起展示当前状态与「编辑」按钮；点击「编辑」在下方展开原生多行编辑器，预填当前 AI 系统提示词（`NativeAgentPrompt.defaultSystemPrompt`），支持修改、校验非空、保存、取消修改、恢复默认与收起。
- `AppSettings` 新增可选字段 `agentSystemPrompt`，通过 `AgentHost` 的 `systemPromptProvider` 与协议消息同步到 `NativeRuntime`，修改后无需重启运行时，下一次 AI 对话即刻生效；清空或恢复默认时回退至默认提示词，且继续附加插件 guidance。

## 实际验证

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，包含新增的 `NativeRuntimeTests.customSystemPromptUpdatesLiveAndRevertsToDefault`（默认提示词、热更新自定义提示词、空白回退与恢复默认）。
- `python3 App/Tests/check-localization.py`：通过（193 个 Swift 源文件语言键与格式参数一致）。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- `python3 App/Tests/run-settings-regression.py`：通过。
- `build/SettingsRegression.app/Contents/MacOS/SettingsRegression --agent-prompt -AppleLanguages '(zh-Hans)'`：通过（验证默认收起、点击编辑展开、默认提示词填充、空白校验、自定义保存与重启持久化、恢复默认及收起）。
- `build/SettingsRegression.app/Contents/MacOS/SettingsRegression --conversation-retention -AppleLanguages '(zh-Hans)'`：通过。
- 人工查看明暗模式下的原生窗口截图（收起态与展开态）：侧栏排序、“智能体”标题与大脑图标、下方提示词卡片及 176 pt 展开编辑器与操作栏均完整显示于默认 900 × 640 窗口内。

## 产物与边界

- 回归截图与构建产物位于 `build/`，不提交。
- 本次未运行真实外部模型网络请求；自定义提示词透传已由 `NativeRuntimeTests` 使用 mock transport 验证。
