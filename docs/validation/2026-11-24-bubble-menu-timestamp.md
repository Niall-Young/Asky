# 气泡更多菜单时间展示

## 变更

- 在 `App/Sources/ChatBubbleMenu.swift` 中移除 AI 气泡与用户气泡更多菜单顶部的“回复时间 / 发送时间”标题，仅保留单行时间文本。
- 复用既有 `ChatCompletionTime.label(_:now:)`（不足 60 秒显示“刚刚”，随后按分钟前、小时前、天前递进，满 3 天显示 `yyyy-MM-dd HH:mm:ss`），配合 `BubbleTimestampSchedule` 按节点刷新，并在时间行悬停时通过 `.help(ChatCompletionTime.exact(_:))` 显示完整时间。
- 从 `App/Resources/zh-Hans.lproj/Localizable.strings` 与 `App/Resources/en.lproj/Localizable.strings` 移除未再使用的 `回复时间`、`发送时间` 本地化项。

## 实际执行

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：在最终修改 `ChatBubbleMenu.swift` 后重新构建，通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：83 tests in 15 suites 通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --bubble-menu-preview`：通过，已检查新构建实际窗口在浅色与深色模式下的 `bubble-menu-assistant-more-{light,dark}.png` 与 `bubble-menu-user-more-{light,dark}.png` 截图，确认 AI 气泡与用户气泡的更多菜单均仅显示单行相对时间（`刚刚`），无前缀标题。
- `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression`：`Reaction regression` 与 `Form lifecycle` 通过；后续用例在既有的非本次任务改动断言（`AgentReplyRegression.swift:1667`：`Tool execution must retain only the typing bubble`）处失败。
