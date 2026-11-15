# 用户消息气泡内距微调

- 用户消息上下内距由各 14 pt 收紧至各 12 pt，总高度减少 4 pt；水平 18 pt、圆角 16 pt、Agent 回复内距保持原值。
- 表情贴纸向下偏移从 13 pt 调整为 14 pt，使其侵入气泡的部分不超过新的底部内距。
- 设计系统同步记录数值。README: unchanged；仅视觉微调，使用方式、功能及构建命令均未变化。

## 实际验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：53 项测试通过。
- `python3 App/Tests/run-agent-reply-regression.py --bubble-width-preview`：通过；检查新编译原生窗口截图 `build/bubble-width-chat.png`，短用户消息保持内容宽度，文字无裁切。
- 使用同一新编译测试应用执行 `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --reactions-preview`：通过；检查 `build/reactions-2-light.png` 与 `build/reactions-2-dark.png`，气泡及贴纸正常，贴纸未遮挡文字。
- 构建仍输出 CoreSimulator 版本提示、既有 AgentView actor 隔离警告及 AppIntents 元数据提示，未影响 macOS 构建成功。
- 日志、截图与构建产物使用已有 `build/` 忽略规则；未安装替换或重启用户的日常应用。
