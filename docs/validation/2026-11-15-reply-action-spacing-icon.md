# 回复按钮间距与图标

- 复制和回复使用独立 `HStack(spacing: 0)`；完成时间 label 位于组外，与按钮组保留 16 pt 间距。
- 回复使用固定版本 MingCute `corner_down_left`，保持 14 pt 图形和 28 pt 点击区域。SVG 与上游原文件逐字一致。
- `xcodegen generate`：通过。
- README 中的 Debug `xcodebuild` 命令：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `python3 App/Tests/run-agent-reply-regression.py --bubble-width-preview`：通过；已查看新生成的 `build/bubble-width-chat.png`，确认回转箭头、紧邻的两个按钮及独立时间 label。
- 首次构建碰到并行引用功能修改未写完；首次新图标截图编译碰到共享 MCPLink.o 被其他构建更新。重新运行后均通过，未改动那些功能来规避错误。
- README: unchanged（本任务仅调整视觉间距与图标，不改变使用方式；工作区其他任务的 README 修改保留）。
- 构建和截图产物复用现有 `build/` 忽略规则；未替换已安装应用、未发布。
