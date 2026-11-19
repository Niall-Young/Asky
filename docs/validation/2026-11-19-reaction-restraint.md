# AI 表情回应克制收敛验证

日期：2026-11-19。

## 修改范围

- 收紧 `Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift` 中关于用户消息贴 emoji（`<asky-reaction>`）的系统提示词：
  - 将默认策略改为“默认只用正常文字回复，绝大多数对话不要给用户消息贴 emoji 表情”。
  - 明确列出不应贴表情的常见场景（普通提问、信息查询、日常讨论、布置任务、修改要求、追问、纠错、功能反馈），禁止为了表示“收到/明白/有意思”或显得热情而顺手贴表情，并禁止因历史对话中出现过表情回应而每轮模仿。
  - 保留原有三种呈现模式与 `<asky-reaction>` 格式约束，仅将贴表情限制在纯感谢/夸奖/简单收尾，以及极少数用户表达明显情绪且贴表情确实加分的时刻。

## 已执行

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（423 个 Swift Testing 用例及 5 个 XCTest 用例全部通过，0 失败）。
- `git diff --check`：通过。

## 验证边界

- 本次仅修改 `Packages/KulaCore` 中的系统提示词，未改动 `App/` 源码与界面逻辑，未执行 `xcodegen` / `xcodebuild` 或真实远端模型回归；不同模型在真实多轮对话中的实际触发频率需在实际对话中继续观察。
