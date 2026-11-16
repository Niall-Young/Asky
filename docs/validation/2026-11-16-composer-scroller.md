# 输入框滚动条位置

编辑器外侧水平留白由 12 pt 改为 4 pt，NSTextView 的水平 textContainerInset 由 0 改为 8 pt。滚动区域向两侧扩展，文字起点与可用文字宽度保持原样；右侧滚动条向玻璃边缘移动 8 pt。

## 验证

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `xcodegen generate` 和 README 中 Debug `xcodebuild` 命令：通过。
- `python3 App/Tests/run-agent-reply-regression.py --bottom-push`：通过。将已有长草稿夹具扩展到 20 行，实际窗口断言文字起点距窗口左边 24 pt、滚动视口距窗口右边 16 pt（玻璃外边距 12 pt，加内部 4 pt）；长草稿、底部内容避让检查均通过。
- 查看 `build/bottom-push-composer-scroller-light.png`、`build/bottom-push-composer-scroller-dark.png`，确认长草稿文本布局。此缓存视图截图未捕获系统合成的滚动条与玻璃，滚动条位置以实际窗口几何断言为依据。
- 使用 orca-computer-use 读取当前输入框，重启前为空；未改写用户草稿。重启后确认 PID 6034 运行 `build/DerivedData/Build/Products/Debug/Asky.app/Contents/MacOS/Asky --show-agent`。查看实际 Debug 窗口截图时输入框为空，未将其记作溢出状态的视觉验收。
- `git diff --check`：通过。

README 保持不变：仅修正局部布局，使用方式与命令未变。构建、回归截图沿用 `build/`、`Packages/KulaCore/.build/` 忽略规则；工具截图与日志保留在临时目录。
