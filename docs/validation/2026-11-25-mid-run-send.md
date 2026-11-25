# 生成中发送消息与顺延承接验证

日期：2026 年 11 月 25 日

## 变更范围

- 运行时与提示词（[NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift)、[NativeRuntime.swift](../../Packages/KulaCore/Sources/AgentHost/NativeRuntime.swift)、[AgentHost.swift](../../Packages/KulaCore/Sources/AgentHost/AgentHost.swift)、[WireProtocol.swift](../../Packages/KulaCore/Sources/AgentHost/WireProtocol.swift)、[Agent.swift](../../Packages/KulaCore/Sources/Contracts/Agent.swift)）：移除中途劫持当前轮次的 `steer` 帧，确保第一件事先完整回复；当续答轮次携带 `source="mid-run-followup"` 上下文时，`NativeRuntime` 仅在首轮模型请求末尾按需追加系统过渡提示（不增加常规轮次与压缩请求的字节开销），引导模型先用自然口语过渡承接第二件事。
- 模型与界面（[AgentModel.swift](../../App/Sources/AgentModel.swift)、[AgentView.swift](../../App/Sources/AgentView.swift)、[AppModel.swift](../../App/Sources/AppModel.swift)）：生成中发送的新消息立即写入当前会话并上屏、清空输入框，当前轮正常答完后自动续答且不重复落盘或重复渲染用户气泡；期间连发多条合并为同一续答轮次；右下角按钮按 `composerPrimaryAction` 在停止（空输入）与发送（有内容）间动态切换；显式停止清空待续答队列。

## 已执行验证

1. 核心包自动化测试：
   ```sh
   (cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
   ```
   结果：全部通过（含新增的 `midRunFollowUpInjectsInitialSystemGuidanceOnlyOnce` 及全部上下文压缩测试）。

2. 工程生成与 Debug 构建：
   ```sh
   xcodegen generate
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build
   ```
   结果：构建成功。

3. 原生界面回归检查：
   ```sh
   python3 App/Tests/run-agent-reply-regression.py --mid-run-send
   python3 App/Tests/run-agent-reply-regression.py --bubble-chain
   ```
   结果：全部通过，验证了真实窗口内先完整答完第一个问题再紧接自然过渡承接第二个问题、多条连续补发合并且无重复、停止/发送动态切换与回车提交、显式停止取消待续答及气泡链布局。

## 未覆盖范围

- 真实在线模型提供商在各类中英文闲聊与工具场景下的自然过渡语气，仍需实机体验验收。
