# 2026-11-24 AI 对话分享窗口点击外部自动关闭验证

## 变更范围

- [ChatShareCard.swift](../../App/Sources/ChatShareCard.swift)：为 `ChatShareWindowController` 接入 `OutsideClickDismissal` 与 `windowDidResignKey` 自动关闭逻辑；在保存图片（`NSSavePanel` sheet）、系统分享（`NSSharingServicePicker` / `NSSharingService` 生命周期）及失败提示弹窗（`appDialog`）展示期间暂停自动关闭，操作结束或取消后恢复；窗口关闭时统一移除外部点击观察器并清理内容视图。
- [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)：在 `--share-and-user-reply` 回归中接入真实 `NSApplication` 事件循环，补充验证窗口内点击不关闭、暂停自动关闭期间点击外部与失焦不关闭、恢复后点击外部自动关闭，以及重新打开后失焦自动关闭。

## 实际执行与结果

1. 核心包单测：
   ```sh
   cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
   ```
   - 结果：通过（XCTest `ToolServiceTests` 9 项、Swift Testing 15 个套件 83 项全部通过）。

2. 原生 App 工程生成与 Debug 构建：
   ```sh
   xcodegen generate
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build
   ```
   - 结果：通过（`** BUILD SUCCEEDED **`）。

3. 分享窗口与自动关闭原生回归：
   ```sh
   python3 App/Tests/run-agent-reply-regression.py --share-and-user-reply
   ./build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --share-and-user-reply
   ```
   - 结果：通过（`Share card light: 1200x792`、`Share card dark: 1200x792`、`Share card and user reply regression passed`；首次运行因同机并发测试进程抢占前台触发 `windowDidResignKey`，并发测试结束后复跑通过）。
