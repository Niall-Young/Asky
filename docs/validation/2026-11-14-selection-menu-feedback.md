# 选区菜单阴影、图标与按压反馈

日期：2026-11-14。

- 仅文字选区菜单关闭 `NSPanel.hasShadow`，保留原生玻璃边缘和窗口与玻璃等大的结构，避免额外黑色投影。
- 「添加到对话」改用固定版本 MingCute `chat_2` 圆形聊天气泡，新增共享语义映射 `bubble.left`。
- 菜单两项操作共用按压状态；复用 GlassPointerFeedback 提亮前景，以 SurfaceSpring 同步扩张实际窗口与玻璃外形，最大增加 3 pt，释放使用弹簧回弹。
- 操作立即执行，浮层保留 220 ms 显示释放反馈，再关闭；再次点击不会重复执行。点击别处、滚动和失焦仍可提前关闭。减少动态效果时关闭缩放且立即收起。

## 已执行

- `xcodegen generate` 和 README 的 Debug `xcodebuild`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `python3 App/Tests/run-agent-reply-regression.py --selection-preview`：通过。五种配色与浅深外观下，检查菜单未开启窗口投影；真实鼠标按下 140 ms 后检查窗口宽度增加超过 1 pt；释放 50 ms 后菜单仍可见；随后关闭，添加引用、焦点和历史恢复正常。
- 已查看新构建窗口的 `build/selection-dark-menu.png` 与 `build/selection-pressed-menu.png`：圆形聊天图标、整块表面按压提亮和扩张可见。截图与构建产物复用现有 `build/` 忽略规则。
- `git diff --check`：通过。

降低动态效果和跨屏场景未做本轮实机矩阵验证。未调用真实模型，本轮仅更改菜单表现。

README 中英文同步当前菜单行为；AGENTS.md 更新选区菜单的阴影例外，其他玻璃表面沿用既有规则。
