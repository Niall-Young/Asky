# 回复操作栏左侧对齐

- 问题：AI 回复下方复制按钮额外带有 10 pt 左侧 padding，导致按钮区域相对气泡左边缘内缩。
- 修改：移除该 padding，让操作栏与气泡共用父级 leading 对齐；保留按钮自身内距、复制与时间之间的间距。
- `xcodegen generate`：通过。
- README 中的 Debug `xcodebuild` 命令：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：53 项测试通过。
- `python3 App/Tests/run-agent-reply-regression.py --bubble-width-preview`：通过；已查看新编译原生窗口的 `build/bubble-width-chat.png`，确认操作栏额外缩进已去除。
- 构建保留既有 actor isolation 警告；未在本次修改范围内处理。
- README: unchanged，本次仅调整已有操作栏对齐，不改变功能、用法或构建命令。
- 构建和截图产物沿用 `.gitignore` 的 `build/` 规则；未替换已安装的应用。
