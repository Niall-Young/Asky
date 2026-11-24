# 对话消息删除确认弹窗优化验证（2026-11-24）

## 变更范围

- [ChatDeleteConfirmDialog.swift](../../App/Sources/ChatDeleteConfirmDialog.swift)：新增窗口内居中的原生 Regular 液态玻璃删除确认弹窗 `ChatDeleteConfirmPresentation`，替换原有 `NSAlert` sheet：
  - 容器采用 `340 pt` 宽、`24 pt` 连续圆角、水平 `20 pt` / 顶 `18 pt` / 底 `20 pt` 内距，经 `nativeGlassBackground` 使用原生 Regular 液态玻璃（不叠加暗色遮罩与硬黑边，自动兼容减少透明度、增强对比度与旧系统回退）。
  - 顶栏统一采用 `16 pt` semibold 标题（`ThemeColor.kText`）与右侧 `28 × 28 pt` 原生圆形玻璃关闭按钮（`12.5 pt` MingCute `xmark`）；正文采用 `14 pt` `ThemeColor.kTextSubtle`，中文单行完整显示不再出现「撤销」孤字换行。
  - 底部采用等宽横排 `36 pt` 高原生液态玻璃胶囊按钮（左侧中性「取消」，右侧 `.primary` 红色破坏性「删除」），交由 AppKit 原生渲染标题对比度，亮暗模式及窗口非活跃态均清晰可读。
  - 弹窗打开时暂停输入框焦点并拦截窗口内滚动与点击；按 `Esc` 或点击卡片外部仅关闭弹窗而不关闭 AI 对话窗口，按 `Return` 或点击「删除」确认删除并保留同会话 AI 回复；配轻微缩放上浮弹簧入场（`response 0.26 / dampingFraction 0.86`）与 `140 ms` 退场，开启减少动态效果时退化为短淡入淡出。
- [AgentModel.swift](../../App/Sources/AgentModel.swift) 与 [AgentView.swift](../../App/Sources/AgentView.swift)：以 `pendingDeleteMessage` 状态驱动窗口内删除确认弹窗，切换会话/时间线或窗口关闭时自动清理，并拦截 `agentEscape` 快捷键避免误关对话窗。
- [AgentReactionRegression.swift](../../App/Tests/AgentReactionRegression.swift) 与 [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)：新增 `--delete-dialog-preview` 回归用例，覆盖居中几何、等宽按钮、输入框失焦、`Esc` 与外部点击取消不删消息、确认删除仅移除目标用户消息并保留 AI 回复，以及亮/暗模式实际窗口截图。
- [design-system.md](../design-system.md)：在 `Dialog 与 Alert` 一节补充对话消息删除确认弹窗规范。

## 实际执行与结果

1. 工程生成与 Debug 构建：
   - 命令：`xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`
   - 结果：通过（修改文件零新增告警）。
2. 删除确认弹窗原生回归与视觉验收：
   - 命令：`python3 App/Tests/run-agent-reply-regression.py --delete-dialog-preview`
   - 结果：通过（`Delete confirmation dialog regression passed in light and dark`）。
   - 实际窗口截图人工核查 `build/delete-dialog-light.png` 与 `build/delete-dialog-dark.png`：亮暗双模式液态玻璃边缘、标题/正文层次、单行正文排版、等宽胶囊按钮、红色删除按钮清晰度与无输入框光标残留均符合预期。
3. 既有表情回应与单条删除回归：
   - 命令：`python3 App/Tests/run-agent-reply-regression.py --reactions-preview`
   - 结果：通过（`Reaction regression passed: ... and single user message deletion`）。
4. `KulaCore` 单元测试：
   - 命令：`cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
   - 结果：通过（全部测试通过，退出码 0）。
