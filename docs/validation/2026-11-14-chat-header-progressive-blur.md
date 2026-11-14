# AI 对话顶部渐进模糊修正

- 顶部模糊范围从 96 pt 缩至工具栏的 64 pt，保持顶部 18 pt 半径向底部零半径过渡。
- CABackdropLayer 使用当前窗口内采样、完整采样分辨率和透明到不透明黑色遮罩；关闭父视图的 Core Image filter 路径。
- 已执行 `xcodegen generate` 和 README 的 Debug `xcodebuild` 命令，构建通过。
- 已执行 `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`，43 项 Swift Testing 测试通过。
- 已执行 `python3 App/Tests/run-agent-reply-regression.py --window-glass`：深浅外观及窗口缩放检查通过。该检查在最终采样修正之前执行，仅用于窗口结构验证。
- 最终采样实现使用真实 AppKit 窗口、重复文字和 300 pt 放大模糊范围单独检查。屏幕截图 `/tmp/asky-progressive-check.png` 显示顶部强模糊向底部清晰逐渐过渡；不是模糊层透明度淡出。此图为临时验证素材，不进入版本库。
- 未发布、未覆盖已安装应用；实际 64 pt 区域在用户历史消息上的滚动观感仍需确认。
- README 中英文及设计系统同步为 64 pt。AGENTS.md 无新的持久规则变更。
