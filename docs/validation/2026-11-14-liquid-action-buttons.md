# 统一动作按钮的液态反馈

## 最终行为

- 按下改为整体等比放大至 1.08，松手弹回；移除此前纵向压扁的实现
- App 共用 `LiquidGlassInteraction.swift` 的反馈规则：悬停 1.015，按下 1.08，松手 response 0.28 / damping 0.45；禁用或减少动态效果时不缩放，动作不等待动画
- 对话顶部、发送、附件、复制、回到底部按钮，以及启动器、剪贴板、提醒操作和紧凑图标动作接入共用反馈；普通图标动作按下不依赖提前进入悬停状态
- 设置动作和快捷键录制按钮共用原生 NSButton 鼠标跟踪；macOS 26+ 开启玻璃且未要求不透明/增强对比度时使用 AppKit `.glass` bezel 与 capsule border，其他情况保留原生回退
- 玻璃按钮开启 interactive；主搜索装饰图标不增加交互，列表行、单选、复选、日期选择与系统面板保留原生选择语义和原有表面
- 未添加 UI 说明文字；保留原有命令、绑定、可访问名称、键盘动作和禁用逻辑

## 实际验证

- `xcodegen generate` 成功；README 中的 Debug `xcodebuild` 命令成功
- 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`，最终 335 项 Swift Testing 测试通过
- 首次核心测试曾因 `#require` 内 throwing 调用未标记 `try` 编译失败，未计为通过；工作树更新后完整重跑通过，本任务未修改相关核心测试
- 使用实际 App 源码快照与独立对象文件运行设置回归，避免并行构建改写共享产物：`--navigation-settings` 的通用/搜索/剪贴板浅色、深色快照与导航偏好持久化通过；`--hotkeys-only` 的快捷键参考页面快照和滚动通过
- 由实际共用按钮、SettingsButton、LauncherActionButtonStyle 和 ClipboardHeaderButtonStyle 源码生成隔离 AppKit/SwiftUI 检查窗口，复用真实资产；按钮动作为空操作，不加载用户日常数据
- CUA 实际按住顶部、原生设置、启动器动作和剪贴板图标按钮，检查连续帧；原生设置与启动器按钮出现膨胀和松手回弹
- 最后一次独立窗口录制中，图标像素边界由 27 × 27 增至 29 × 29 px，确认宽高同时变大；该录制记录 1106 个完整帧，请求 60 fps，最大完整帧间隔约 38.1 ms，不宣称锁定 60 fps
- 证据保存在本地忽略目录 `build/liquid-buttons-task/`：`settings-final.log`、`settings-hotkeys.log`、`swift-test-final.log`、`fixture-interaction.mp4`、`action-motion.png` 与 `measured.json`

## 验证边界与维护

- 验证覆盖代表组件和共用样式，未逐个操作每个业务按钮；未实际切换系统减少动态效果或在 macOS 14 运行
- README 中英文同步共用交互，设计系统规定统一实现和禁止压扁；AGENTS.md 无需更新，仍在既有 App 原生 UI 边界内，开发命令没有变化
- 诊断程序、对象文件、录制和快照沿用现有 `build/` 忽略规则；其他任务的未提交改动保留
- 未发布或替换正式安装版
