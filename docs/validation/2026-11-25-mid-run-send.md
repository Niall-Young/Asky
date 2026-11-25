# 生成中发送消息与中途注入验证

日期：2026 年 11 月 25 日

## 变更范围

- 协议与运行时（[Agent.swift](../../Packages/KulaCore/Sources/Contracts/Agent.swift)、[WireProtocol.swift](../../Packages/KulaCore/Sources/AgentHost/WireProtocol.swift)、[AgentHost.swift](../../Packages/KulaCore/Sources/AgentHost/AgentHost.swift)、[NativeRuntime.swift](../../Packages/KulaCore/Sources/AgentHost/NativeRuntime.swift)）：新增 `HostMessage.steer`、`RuntimeMessage.steerAccepted` 与 `AgentEvent.steerAccepted`。支持在任务启动前暂存并在派发 `prompt` 后补发 `steer`；`NativeRuntime` 在工具调用批次返回后、下一次模型请求前注入用户新消息，重置 `illustrationsFinished` / `webCoolingDown`，保存快照并发出 `steerAccepted`；若已处于无工具收尾阶段则不吞入该消息。
- 模型与界面（[AgentModel.swift](../../App/Sources/AgentModel.swift)、[AgentView.swift](../../App/Sources/AgentView.swift)、[AppModel.swift](../../App/Sources/AppModel.swift)）：支持在 `isRunning` 期间直接发送消息并立即落盘与上屏，右下角按钮按 `composerPrimaryAction` 在停止（空输入）与发送（有内容）间动态切换；支持回车发送（空输入回车不触发停止）；未在工具边界消费的消息在本轮正常完成后自动发起续答且不重复落盘或重复显示用户气泡，显式停止清空待续答队列；修复跨用户消息分段的响应分组唯一 ID 与底部单 `•••` 思考气泡展示。

## 已执行验证

1. 核心包自动化测试：
   ```sh
   (cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
   ```
   结果：全部通过（包含新增的 `steerInjectedAfterToolRoundAndResetsWebGuards`、`steerDuringFinalResponseIsNotAccepted`、`steerQueuesBeforeDispatchAndForwardsSteerAccepted`、`encodesSteerAndDecodesSteerAccepted`）。

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
   python3 App/Tests/run-agent-reply-regression.py --composer-backspace
   ```
   结果：全部通过，覆盖真实窗口内的停止/发送按钮切换、回车发送、工具中注入合并回答、收尾期自动续答无重复、显式停止取消待续答、气泡链圆角间距及输入框退格撤销。

## 未覆盖范围

- 真实在线模型提供商在复杂多工具链下中途注入的响应质量与长文本滚动手感，仍需实机体验验收。
