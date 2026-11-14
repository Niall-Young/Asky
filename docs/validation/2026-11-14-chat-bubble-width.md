# 聊天气泡按内容收缩

## 原因与修改

AI 回复的 `ChatInlineText` 默认未启用宽度收缩，原生文本测量直接返回可用宽度，导致短回复撑满气泡。用户消息虽然启用了收缩，但缺少与回复一致的垂直固有尺寸约束，横向栈仍可能把它撑开。

- 普通原生文本默认按内容收缩，有限宽度作为上限；长文本仍在上限内换行。
- 使用 TextKit 实际字形测量自然宽度，包含粗体、emoji、行内代码及附件；测量后恢复渲染容器尺寸，避免影响实际文本及选区布局。
- 自适应文本在未指定或无限宽度探测时也返回内容尺寸；用户文本补齐垂直固有尺寸约束。
- 不修改气泡内距、圆角、颜色或复制操作。

## 已运行并通过

- `xcodegen generate`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`
- `(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)`
- `python3 App/Tests/run-agent-reply-regression.py --bubble-width-preview`：实际聊天窗口检查短用户消息及用户截图原句的 AI 回复；280/460 pt 宽度检查短中文、emoji、粗体、行内代码及长文本换行和裁剪。
- `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --continuous-selection-preview`：正反向拖选、跨列表、嵌套列表、部分端点、引用、全选及菜单圆角。
- `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --math-preview`：公式解析、原生排版、无效源码回退及深浅/窄窗口检查。

已查看 `build/bubble-width-chat.png`：用户「发短信」气泡靠右按内容收缩，AI「给你这条消息贴了个 💬，表示要发短信这件事。」气泡靠左按内容收缩。修复过程中用户气泡断言曾失败，补齐布局约束后重新编译并通过，失败结果未记为通过。

已停止旧的 `build/ReactionDerivedData` 调试进程，启动 `build/DerivedData/Build/Products/Debug/Asky.app --show-agent`，通过完整进程路径确认新构建运行。上述截图来自使用实际聊天界面和临时会话数据的原生回归程序；未向用户真实会话发送测试消息，未发布 Release。

## 文档与产物

README 中英文同步新增回归命令，设计系统补充最大宽度规则。AGENTS.md 的现有边界和命令仍适用，无需修改。构建、日志和截图沿用 `build/` 忽略规则，生成工程沿用 `Asky.xcodeproj/` 忽略规则。
