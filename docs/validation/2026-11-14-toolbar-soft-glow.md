# 对话工具栏柔和局部高光

- 根据用户提供的 `ScreenRecording_11-14-2026 22-29-37_1.MP4` 逐帧查看顶部双图标胶囊：右侧按压约在 0.65–0.8 秒，左侧按压约在 2.8–3.0 秒。亮度以当前图标附近为中心，连续衰减，中央没有半侧裁剪边界。
- 修正上次将高亮硬切为左右两块的实现。共用玻璃胶囊上叠加柔和径向高光；保留 96 × 36 pt 尺寸、48 pt 中心距和原有整体按压回弹。
- `xcodegen generate`、README 的 Debug `xcodebuild`、`Packages/KulaCore` 的 `swift test` 均通过，核心测试共 347 项。日志：`build/toolbar-glow-build.log`、`build/toolbar-glow-tests.log`。
- 使用实际 `GlassCapsuleIllumination` 组件通过 SwiftUI ImageRenderer 渲染静止、左侧按下、右侧按下三种状态。查看左右 PNG，确认亮度连续渐变，中央不再出现竖直切线。图片与临时渲染程序位于忽略目录 `build/toolbar-reference/`。
- 已正常退出旧进程，启动 `build/DerivedData/Build/Products/Debug/Asky.app --show-agent`，通过原生界面工具确认新对话窗口已打开。
- 本次渲染验证覆盖高光形状与左右状态；未完成真实指针按住期间的连续录制，不宣称与 iOS 原生光学、动画完全一致。
- README 中英文同步修正高光描述；AGENTS.md 无持久规范变化。
