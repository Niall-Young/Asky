# 2026-11-24 聊天气泡无容器表情悬挂与切换小动画验证

## 变更范围

- [ChatReactionBadge.swift](../../App/Sources/ChatReactionBadge.swift)：新增共享无容器表情组件 `ChatReactionBadge`，去掉原有胶囊底板与白边描边，直接以 18 pt emoji（24×24 pt 槽位、轻量悬浮阴影）跨气泡底边悬挂（横向外探 4 pt、纵向外探 12 pt）；用户表情支持悬停轻放大与按压缩放反馈。更换表情时触发专属切换小动画：旧表情斜向上剥离并微模糊淡出（180 ms），新表情紧随其后反向轻倾并以弹簧（response 0.36 s / dampingFraction 0.46）弹入落位，同时背后由 `TimelineView` 逐帧绽放随当前头像配色的柔和扩散环与 6 枚微光点（340 ms）；初始与历史恢复保持静止，减少动态效果时退化为短淡入淡出。
- [AgentView.swift](../../App/Sources/AgentView.swift)：用户消息左下角 `agentReaction` 与 AI 回复右下角 `userReactionBadge` 统一改用 `ChatReactionBadge`。
- [AgentReactionRegression.swift](../../App/Tests/AgentReactionRegression.swift)、[AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)：补充更换用户表情后的状态持久化断言，并新增 `--reaction-swap-preview` 原生窗口前后与中段帧截图回归。
- [design-system.md](../design-system.md)：记录无容器表情悬挂几何与更换表情专属动效规范。

## 实际运行的检查

1. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（全部 XCTest 与 83 个 Swift Testing 用例 0 失败）。
2. `xcodegen generate` 与 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -disableAutomaticPackageResolution build`：通过（`** BUILD SUCCEEDED **`）。
3. `python3 App/Tests/run-agent-reply-regression.py --reaction-swap-preview`：通过（浅色与深色模式均完成切换前、`early`、`peak` 与切换后截图，状态切换断言通过）。
4. `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --bubble-menu-preview`：通过（浅色与深色模式截图已确认 AI 气泡与用户气泡均无外层胶囊容器，表情悬挂位置准确不遮挡正文）。
5. `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --user-bubble-hover`：通过（72 次原生指针悬停/移入/移出，气泡像素与位置全程稳定）。
6. `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --reactions-preview`：通过（含三种 AI 回应模式、历史恢复、取消、目标隔离、用户给 AI 贴表情与更换表情持久化）。

## 视觉复核结果

- 已直接查看实际原生窗口截图：`build/reaction-swap-{before,early,peak,after}-{light,dark}.png` 与 `build/bubble-menu-emoji-{light,dark}.png`。
- 无胶囊容器：用户气泡左下角与 AI 气泡右下角均为裸 emoji 直接悬挂，边缘对称清晰，浅色与深色模式均无裁切或文字遮挡。
- 切换动效：`early`（75 ms）可见旧表情向上微模糊剥离、新表情斜向弹入且背后扩散环与 6 枚微光点绽放；`peak`（150 ms）可见新表情弹簧过冲与微光点向外柔和衰减；`after` 干净落位无残留。
