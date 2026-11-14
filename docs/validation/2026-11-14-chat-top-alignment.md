# 对话顶部对齐验证

2026-11-14。窗口保持 560 × 680 pt。

## 行为

- 打开会话、发送问题和回答首次呈现时，当前轮的问题在 64 pt 顶栏下方留出 12 pt，回答跟随其后。
- 移除 88 pt / 四行预览限制。能放下的回答完整显示；长回答填满剩余高度，向下滚动继续阅读。
- 当前轮保留最小可视高度，让短对话也可顶部对齐；较早的消息仍可向上翻阅。
- 用户滚动后停止自动定位；手动回到底部继续可用。

## 实际运行

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path /tmp/asky-turn-top-core-build`（在 `Packages/KulaCore`）：通过，359 个 Swift Testing 用例及 5 个 XCTest 用例。
- 实际 App 源码的原生回归：`--bottom-push`、`--reading-scroll --scroll-history`、`--restored-transcript`、`--restored-transcript --restored-long-reply`、`--bottom-push --preview-macos14` 均通过。
- 长回答首屏显示 403 pt，问题顶边距离滚动区域顶边 76 pt；七行回答超过原四行限制，仍完整显示。
- 带历史的手动滚动保持位置；三次回到底部点击均到实际末端（误差 0 pt）。含公式、表格的长回答在首次打开及两次重开后均从当前问题开始展示，手动滚动可接管。
- 已查看原生窗口长回答及七行回答截图，确认问题与回答顶部排列、长回答填充可视区域。

## 验证环境与限制

工作区存在并行任务：首轮核心测试因 Command Line Tools 缺少 XCTest 失败，改用 Xcode 工具链；共享构建产物与测试源码先后被其他任务写入，导致两次回归编译失败。最终复制源码至 `build/TurnTopSource`、构建产物至 `build/TurnTopDerivedData`，通过 `ASKY_DERIVED_DATA` 编译并运行独立回归包；截图位于 `build/TurnTopSource/build/bottom-push-{completed,short}.png`，后续兼容分支截图位于根目录 `build/`。上述目录沿用已有 `build/` 忽略规则。

macOS 14 分支由 Debug 参数强制走兼容路径，并非在 macOS 14 实机测试。没有调用在线模型或发布安装包。

README 中英文、PRD 与设计系统已同步；AGENTS.md 的工具链、架构边界与指南入口不变。
