# Tinycast 按钮实现对照与误改撤回

检查版本：Tinycast `6fa8ba1225be0777ef769f1816bffc7da213f91d`，2026-11-14。

## 源码证据

- [AIChatWindowChrome.swift](https://github.com/abue-ammar/tinycast/blob/6fa8ba1225be0777ef769f1816bffc7da213f91d/Tinycast/Features/AI/UI/AIChatWindowChrome.swift)：聊天窗口实际配置 NSToolbar，toolbarStyle = unified；操作按钮 bezelStyle = toolbar，其余普通操作由 NSToolbarItem.image/target/action 提供。不是在任意 SwiftUI 背景上叠一个玻璃按钮。
- [BarButton.swift](https://github.com/abue-ammar/tinycast/blob/6fa8ba1225be0777ef769f1816bffc7da213f91d/Tinycast/DesignSystem/BarButton.swift)：启动器顶部/底部控件使用 plain 按钮，自行监听 onHover，以既有 capsule 或 rounded 形状填充 rowHover；没有在这个控件中手写按下缩放。
- [AIChatDetailView.swift](https://github.com/abue-ammar/tinycast/blob/6fa8ba1225be0777ef769f1816bffc7da213f91d/Tinycast/Features/AI/UI/AIChatDetailView.swift)：输入区玻璃是背景；发送为 plain 按钮加实心圆，其他输入控件自行绘制悬停底色。不能把这些控件统称为系统工具栏的玻璃形变。

## Asky 的差异

聊天顶部目前使用 NSStackView 内的无边框 NSButton，加 SwiftUI 胶囊玻璃背景，不处于 NSToolbar。玻璃材料和原生工具栏交互不是同一层实现；不能保证加 interactive 就与系统应用工具栏完全一致。

本轮尝试使用 ControlGroup 后改变了原有宽高与分隔线，用户明确拒绝。随后启用 accessoryBarAction 的 showsBorderOnlyWhileMouseInside 导致方块高亮，用户同样拒绝。两者均已撤回。NativeActionButtonStyle 及其对头像、发送、回到底部、启动器的样式替换也撤回，恢复此次调查前外观；保留并发已提交的头像菜单 0.28 秒动画调整。

## 已执行检查及限制

- 实验实现阶段 xcodegen generate、Debug xcodebuild 通过；KulaCore swift test 43 tests / 10 suites 通过。
- 实际窗口暴露出 ControlGroup 分隔线、尺寸变化与 accessoryBarAction 方块悬停。检查通过不能替代用户对外观和动态效果的验收。
- 撤回后的 Debug xcodebuild 再次通过，已重新打开恢复版 Debug。
- 最终源码恢复至此次调查前的已提交实现；不重新引入上一轮已删除的 1.08 倍缩放。
- 未运行 Tinycast，本记录是源码对照，不宣称已观察其实际动画。
- 目标仍未完成：保持当前 Asky 外观同时得到用户所指的系统工具栏悬停/形变反馈，尚无验证通过的实现。本轮不得标记该问题已修复。

README 与 AGENTS.md 无需改变：没有留下新的行为实现、构建命令或模块约束。构建输出沿用已有 build/ 忽略规则。
