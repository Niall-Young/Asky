# 聊天输入框与顶部操作组统一为 Clear 玻璃

## 改动

- [`App/Sources/AgentView.swift`](../../App/Sources/AgentView.swift)：
  - 右上角置顶／关闭按钮胶囊（`AgentView.header`）由默认 `.regular` 改为 `.nativeGlassBackground(in: Capsule(), clear: true, glassOpacity: 0.85)`。
  - 底部输入框容器（`Composer`）由默认 `.regular` 改为 `.nativeGlassBackground(in: RoundedRectangle(cornerRadius: AgentLayout.composerCornerRadius, style: .circular), clear: true, glassOpacity: 0.85)`。
  - 两者与左上角收起态头像（`AgentAvatarPicker` 的 `.clear` + `0.85` 透明度）统一使用相同的原生 Clear 玻璃配置，消除窗口失焦时 Regular 退化为实心浅灰块造成的样式差异。
- [`docs/design-system.md`](../design-system.md)：同步更新聊天输入框、右上按钮组与收起态头像的 Clear 玻璃材质说明。

## 已执行验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过（`** BUILD SUCCEEDED **`）。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（91 tests in 16 suites passed）。
- `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --reactions-preview`：通过（`Reaction regression passed`）。
- `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --header-drag`：通过（`Header drag passed`）。
- 重启本机 Debug `Asky.app`（`build/DerivedData/Build/Products/Debug/Asky.app`，PID 83463，启动时间晚于本次构建），以便直接在真实桌面窗口查看活跃与失焦态效果。

## 未执行与边界

- 当前命令执行环境缺少 Screen Recording 权限，`screencapture` 输出纯黑图像，因此未能在本会话中通过截图像素直接自动校验实时玻璃合成（`--approval-menu-hover` 的像素亮度差检查也受此限制失败）；实际视觉一致性请在已重启的 Debug `Asky.app` 对话窗口中失焦核对。
- `python3 App/Tests/run-agent-reply-regression.py --window-glass` 在执行到前置的 `toolRepliesRegression`（`AgentReplyRegression.swift:2295`：`Tool execution must retain only the typing bubble`）时中止，属于与本次玻璃参数修改无关的既有回归断言。
- 未测试 macOS 14/15 实机，未改动启动器、剪贴板及弹出菜单（审批菜单、头像展开面板仍为 Regular）材质。

## 同步核对

- `README.md`: unchanged（当前精简版 README 不记录聊天局部控件的 Clear/Regular 子材质）。
- `AGENTS.md`: unchanged（无新增或变更的持久工程约束）。
