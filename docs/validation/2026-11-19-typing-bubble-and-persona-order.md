# 修复加载气泡居中与 AI 口癖回潮

日期：2026-11-19

## 变更

- `App/Sources/AgentView.swift`：
  - 在 `ResponseGroupView` 外层 `VStack` 补充 `.frame(maxWidth: .infinity, alignment: .leading)`，修复虚拟化转录列表中独立 `NSHostingController` 将窄幅 `ChatTypingBubble` 水平居中的布局回归。
  - 在 `ChatTypingBubble` 添加轻量 `TranscriptTypingPosition` 视图标识（`chat-typing-bubble`），供 UI 回归检查定位测量。
- `Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift`：
  - 将 `NativeAgentPrompt.system(...)` 的拼接顺序调整为 `runtimeProtocolPrompt + guidance + capability + persona`，使人设与交流文风位于系统提示词最末尾、紧贴对话上下文，避免被前部数千字内置协议稀释，同时保持连续对话的提示词前缀缓存稳定。
  - 收紧 `defaultSystemPrompt` 的反 AI 腔与直白表达约束（禁止开场先点评迎合用户、禁止评论员过渡语与自我预告、禁止“不是……而是……”套路、禁止末尾防御性免责与推销下一步）。
  - 兼容升级前保存在设置中的旧版全量自定义提示词，检测到已包含内置协议标记时不再重复叠加 `runtimeProtocolPrompt`。
- `Packages/KulaCore/Tests/AgentHostTests/NativeRuntimeTests.swift`：
  - 同步校验人设后置拼接顺序与旧版全量自定义提示词去重逻辑。
- `App/Tests/AgentReplyRegression.swift`：
  - 在 `--bubble-width-preview` 中新增运行态加载气泡位置回归检查，断言 `minX < 40` 且 `width < 120`（靠左对齐并贴合圆点尺寸）。

## 实际验证

| 检查 | 结果 |
| --- | --- |
| `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | 通过，83 tests in 15 suites 全部通过 |
| `python3 App/Tests/run-agent-reply-regression.py && build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --bubble-width-preview` | 通过；实测 `Typing bubble in window: minX=12.0, width=57.0, windowWidth=560.0`，截图 `build/typing-bubble-alignment.png` 确认靠左对齐 |
| `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build` | 通过（`BUILD SUCCEEDED`） |

## 边界说明

- 本次未调用真实外部 LLM API 进行线上生成抽测；提示词拼接顺序与去重由 `NativeRuntimeTests` 通过 mock transport 验证。
- 回归截图与构建产物位于 `build/`（已被 `.gitignore` 忽略）。
