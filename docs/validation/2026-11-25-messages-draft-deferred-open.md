# 短信草稿改为卡片按钮触发打开

## 问题与改动

在 AI 对话窗口中执行 `messages_prepare_draft` 时，`MessagesDraftTool` 原本直接调用 `NSWorkspace.shared.open(url)`，导致系统「信息」窗口立即弹出到最前并遮挡 AI 对话窗口，而回复下方原本就提供了带「在信息中打开」按钮的信息草稿卡片。同时，macOS 的 `Messages.app` 在处理 `sms:` URL 时即便传入 `NSWorkspace.OpenConfiguration.activates = false` 仍会主动激活自身。

改动内容：

- `ToolAdapter` 增加 `execute(_:requestID:origin:)`（带向后兼容默认实现），`ToolService` 执行读写工具时透传 `request.origin`。
- `MessagesDraftTool`（`Packages/KulaCore/Sources/Adapters/PeopleAndHandoffTools.swift`）在 `.agent` 来源调用时只完成收件人与正文校验并返回草稿数据（`opened: false`、`copiedToClipboard: false`、`sent: false`），不再主动拉起 Messages 或覆盖剪贴板，等待用户点击结果卡片中的「在信息中打开」（经 `ToolService.performCardAction(.openMessagesDraft)` 复制正文并打开 `sms:` 草稿）。
- 外部 MCP（`.mcp`）与 `.launcher` 来源仍保持即时交接行为；`MessagesDraftTool` 支持注入 `handoff` 以便测试隔离。
- 同步 `NativeAgentPrompt`、中英文 `Core.strings`、`docs/PRD.md` 与 `docs/native-tools-and-mcp.md`。
- 排查其余内置工具确认：日历、提醒事项、联系人、地图、记忆、短信读取与备忘录读写均不会在工具执行时将对应应用弹到 AI 窗口前方；仅 `chrome_activate_tab` 按其“切换标签页”语义保留前景切换。

## 实际验证

- `plutil -lint Packages/KulaCore/Sources/Contracts/Resources/en.lproj/Core.strings Packages/KulaCore/Sources/Contracts/Resources/zh-Hans.lproj/Core.strings`：两个文件均 `OK`。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`（工作目录 `Packages/KulaCore`）：退出码 0，13 个测试目标全部通过（9 个 XCTest + 477 个 Swift Testing 用例），包含新增的 3 个 `MessagesDraftApprovalTests` 用例：
  - `agentDraftPreparesCardWithoutOpeningMessages`：验证 `.agent` 明确请求不弹窗确认、不触发系统 `handoff`、返回 `opened: false` / `copiedToClipboard: false` / `sent: false`，并能生成带 `.openMessagesDraft` 动作的 `ToolResultCard`。
  - `approvedMCPDraftHandsOffToMessages`：验证 `.mcp` 经确认后仍触发 1 次 `handoff` 并传递正确 `sms:` URL 与正文。
  - `launcherDraftHandsOffImmediately`：验证 `.launcher` 仍直接触发 1 次 `handoff`。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`（工作目录 `MCPBridge`）：构建通过。
- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：`BUILD SUCCEEDED`。

## 验证范围

测试通过注入 `handoff` 探针验证系统交接调用次数，未拉起真实 Messages 窗口、未改写本机剪贴板，也未重启当前正在运行的 Debug `Asky.app` 进程（需重新启动新构建后生效）。工作区原有 `App/Sources/AgentModel.swift`、`App/Sources/AgentView.swift`、`App/Sources/ChatFormView.swift`、`App/Tests/AgentReplyRegression.swift` 的未提交改动未触碰；Debug 构建基于当时工作区完成，仅验证本次改动与当前工程可编译链接。

README: unchanged — 中英文 README 已准确描述短信草稿交接与结果卡片一键跳转能力，未新增命令或配置项。

AGENTS.md: unchanged — 工具仍经 `ToolService` 统一调度，未改变模块边界或构建规范。
