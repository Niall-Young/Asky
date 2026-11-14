# 聊天底部追加与回复阅读位置

## 行为

- 聊天窗口固定 560 × 680 pt，禁用用户拉伸，最小与最大尺寸相同；宽度保持现状。

- 短对话贴着输入框排列；新消息及等待回复气泡出现在底部，旧内容向上推。
- 发送校正与手动回到底部分开管理；回答完成立即取消发送校正，独立定位回答开头，露出最多四行正文高度（88 pt），不足四行则完整露出；不把完整回答拉到结尾。
- 用户主动滚动或关闭窗口会取消校正；手动回到底部仍可用。

## 实际验证

- `xcodegen generate` 与 README 的 Debug `xcodebuild` 命令通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：KulaCore 43 tests / 10 suites 通过。首次未指定 Xcode 的运行因找不到 Testing 失败，切换 Xcode 后通过。
- 固定当前源码与 Debug 编译产物副本后，以 `ASKY_DERIVED_DATA=build/FourLineVerification python3 build/FourLineSnapshot/App/Tests/run-agent-reply-regression.py --bottom-push` 运行同一回归脚本：真实原生窗口断言固定 560 × 680 尺寸、无 resizable 样式与相同尺寸上下限，覆盖短对话、超过两屏的历史、新消息与等待回复，底部偏差 0 pt；新增 40 ms 后完成长回答的回归，长回答开头实际露出的正文高度为 88 pt，误差小于 2 pt；不足四行的短回复完整处于可见区域。
- 固定副本编译的回归程序 `--reading-scroll` 通过：固定 680 高度下重复单次回到底部以及后续回答保持阅读位置。
- 固定副本编译的回归程序 `--bottom-push --preview-macos14` 通过相同断言；是在当前系统强制兼容路径，并非真实 macOS 14。
- 检查 `build/bottom-push-before.png`、`after.png`、`completed.png` 和 `short.png`：旧气泡上移、新问题与等待气泡在下方，完成后从回答开头露出四行高度。
- 本地 Debug app 已重启，使用当前工作区 `build/DerivedData/Build/Products/Debug/Asky.app`。没有安装或发布正式版。

固定副本仅用于隔离同工作区的并行表单修改；未把表单修改纳入本次提交。

## 文档与产物

- README 中英文与 PRD 同步底部追加行为；AGENTS.md 无持久规则变化，保持不变。
- 截图与回归 bundle 使用现有 `build/` 忽略规则；无新增忽略规则。
