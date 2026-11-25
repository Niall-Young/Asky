# 全服务商模型预设更新与 OpenAI 参数兼容验证

日期：2026-11-25。

## 变更

对照各家服务商截至 2026 年 11 月的官方开放文档，更新 `App/Sources/ModelProviderPreset.swift` 中的全部预设模型列表，并补齐 OpenAI GPT-5/GPT-6 在 Chat Completions 端点下的参数兼容：

1. **DeepSeek**（`https://api.deepseek.com`）：保持 `["deepseek-flash", "deepseek-v4-pro"]`。官方当前仍为这两个正式模型 ID（底层分别对应 `DeepSeek-V4.1-Flash-1017` 与 `DeepSeek-V4-Pro-0813`），`deepseek-chat` 与 `deepseek-reasoner` 已于 2026-07-24 下线。
2. **MiniMax**（`https://api.minimax.cn/v1`）：更新为 `["MiniMax-M3.1-Flash", "MiniMax-M3"]`。加入 2026-10-19 发布的多模态旗舰 `MiniMax-M3.1-Flash` 为默认，保留 `MiniMax-M3`，移除已于 2026-11-18 下线的 `MiniMax-M2.7`、`MiniMax-M2.5`（旧保存配置会安全保留为自定义而不覆盖）。
3. **GLM（智谱）**（`https://open.bigmodel.cn/api/paas/v4`）：延续上一提交的 `["glm-5.3-flash", "glm-5.3-flashx", "glm-5.3", "glm-5.4"]`。
4. **Kimi**（`https://api.moonshot.ai/v1`）：更新为 `["kimi-k3.1-pro", "kimi-k3.1-pro-highspeed", "kimi-k3"]`。加入 2026-10 发布的 K3.1 Pro 系列，保留 `kimi-k3`，移除 2026-11-01 起对新注册账号关闭、计划 2026 年 12 月底退役的 `kimi-k2.6` 与 `kimi-k2.7-code`。
5. **Qwen（通义千问 · 北京）**（`https://dashscope.aliyuncs.com/compatible-mode/v1`）：更新为 `["qwen3.8-flash", "qwen3.7-plus", "qwen4-max", "qwen3.8-max", "qwen-plus"]`。新增 `qwen3.8-flash`（默认，原生多模态、低成本）、`qwen3.7-plus`（最新 Plus）和 `qwen4-max`（2026-11-16 正式上线旗舰），同时保留仍在线的 `qwen3.8-max` 与 `qwen-plus` 以兼容已有配置。
6. **OpenAI**（`https://api.openai.com/v1`）：更新为 `["gpt-6-luna", "gpt-5.6-terra", "gpt-5.6-sol", "gpt-5.4"]`。替换将于 2027-01-14 关停的 `gpt-4.1` / `gpt-4.1-mini`；未列入 `gpt-6.2-astra`、`gpt-6.2-sol`、`gpt-6.1-terra`，因为 OpenAI 官方文档明确说明它们在 Chat Completions 端点不支持工具调用（仅支持 Responses API）。
7. **OpenAI Chat Completions 参数兼容**：在 `ModelHTTPConnection` 新增 `usesMaxCompletionTokens` 与 `usesOpenAIReasoningEffortNone`，并在 `NativeModelClient`、`SmartAdvisor` 与 `ModelCapabilityCheck` 中复用：仅针对 `api.openai.com` 的 GPT-5/GPT-6 推理模型发送 `max_completion_tokens`，并为 `gpt-6-luna` / `gpt-5.6*` / `gpt-5.4*` 发送 `reasoning_effort: "none"`（OpenAI 文档要求 GPT-5.4+ 与 GPT-6 Luna 在 Chat Completions 中开启工具调用时必须传入该值）；自定义代理、`gpt-4.1`、`gpt-6.2-*` 与其他服务商不受影响。

## 实际检查

通过：

1. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library -swift-version 6 App/Sources/ModelProviderPreset.swift App/Tests/ModelProviderRegression.swift -o build/model-provider-regression && build/model-provider-regression`：通过，覆盖全部 6 家预设、已有配置保留与退役模型退回自定义。
2. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore --filter ModelHTTPParametersTests`：通过。
3. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore`：13 个运行组共 487 项 Swift Testing 测试全部通过。
4. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path MCPBridge`：构建通过。
5. `xcodegen generate` 与 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/ModelPresetDerivedData -skipPackageUpdates build`：构建成功（`BUILD SUCCEEDED`）。

未验证：未使用各服务商真实付费 API Key 发起线上请求，不宣称线上账号权限与端到端响应已验收；本次未运行 `run-settings-regression.py`（工作区同时存在其他并行任务对 `App/Tests/SettingsRegression.swift` 的未完成改动，未触碰其文件），也未打包替换 `/Applications/Asky.app`。

## 文档与 Git

- `AGENTS.md` 无变化：沿用既有 App、KulaCore 与测试边界。
- `README.md` 无变化：未列举具体服务商模型版本号，构建与测试命令未变。
- 仅暂存并提交本任务相关的 8 个文件，保留工作区中并行任务的全部未提交改动。
