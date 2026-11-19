# 智能体提示词分层：人设文风与内部协议拼接

日期：2026-11-19

## 变更

- 将 `NativeAgentPrompt.defaultSystemPrompt` 精简为面向用户的角色定义与交流文风（Soul 层），不再在设置页编辑器中暴露客户端协议与工具操作细节。
- 新增内部 `NativeAgentPrompt.runtimeProtocolPrompt`，收纳行动与提问门槛、联网核实与来源标签渲染、远程图片配图流程、`<asky-reaction>` 表情反应、系统工具边界与权限确认、记忆读写及 `asky-form` 表单协议。
- `NativeAgentPrompt.system(basePrompt:guidance:hasPageReader:)` 在运行时始终按 `persona + runtimeProtocolPrompt + guidance + capability` 拼接最终系统提示词；无论用户使用默认人设还是自定义人设，内部协议与客户端渲染契约均保持生效。
- 更新 `NativeRuntimeTests` 校验：默认人设不外露 `asky-form`、`<asky-reaction>`、`web_read_page`、`calendar_list_calendars`、`memory_save` 等内部协议；自定义人设实时生效时依然拼接完整内部协议与来源标签约束。

## 实际验证

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（含 `NativeRuntimeTests.customSystemPromptUpdatesLiveAndRevertsToDefault` 与 `webCitationGuidancePreservedAcrossFormattingAndTerminalImages`）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过（`BUILD SUCCEEDED`）。
- `python3 App/Tests/run-settings-regression.py && build/SettingsRegression.app/Contents/MacOS/SettingsRegression --agent-prompt -AppleLanguages '(zh-Hans)'`：通过（验证设置页默认提示词预填、校验、自定义持久化、恢复默认与收起）。

## 产物与边界

- 构建产物与回归包位于 `build/`（已忽略，不提交）。
- 本次未运行真实外部模型网络请求；拼接后的系统提示词透传由 `NativeRuntimeTests` 使用 mock transport 验证。
