# AI 对话引用来源标签改为点击触发

日期：2026-11-25

## 变更范围

- [ChatSourcePreview.swift](../../App/Sources/ChatSourcePreview.swift)：
  - 移除引用来源标签的 300 ms 悬停弹出逻辑（`hoverTask`、`mouseExited`、`cancelPendingHover`）及专用于抑制悬停弹出的 `ChatSourceScrollGuard`，悬停标签仅保留箭头光标并继续抑制原生原始 URL tooltip。
  - `ChatSourceTextView.textView(_:clickedOnLink:at:)` 改为：单来源标签（`sources.count == 1`）点击后直接经 `openLinkHandler`（默认 `ToolService.openLauncherURL`）跳转并关闭已有来源卡片，不弹出卡片；多来源标签（`sources.count > 1`）点击展开/再次点击收起 `ChatSourcePopover`。
  - `ChatSourcePopover` 移除鼠标移出 400 ms 自动关闭轮询，改为点击触发弹层生命周期：保持展开直至再次点击同一标签、点击外部、按 `Esc`（消费按键不关闭对话窗）、父窗口失焦/关闭、或滚动对话列表（短卡片上滚轮直接关闭并转发给对话滚动视图，长列表卡片内部继续独立滚动）；点击卡片内来源条目经 `ToolService.openLauncherURL`（可由 `openLinkHandler` 注入）打开并关闭卡片。
- [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)：
  - 更新 `sourcesPreview()`：验证悬停多来源/单来源标签均不弹出卡片、单来源标签点击直接打开目标链接且不弹卡片、多来源标签点击展开并保持打开、再次点击同一标签切换收起、`Esc`/点外部/滚动关闭卡片，以及暗色滚动容器中贴底多来源标签向上翻转。
  - 更新 `actionCursorPreview()`：改为多来源标签，验证悬停显示箭头光标但不弹出卡片，点击后展开卡片并保持卡片行箭头光标。

## 实际执行的检查

- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过（`** BUILD SUCCEEDED **`）。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（全部 15 个 Suite / 83 个 Swift Testing 用例及 XCTest 用例均通过，0 失败）。
- `PYTHONDONTWRITEBYTECODE=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --sources-preview`：通过；并目视核对新生成的 `build/sources-light.png`、`build/source-card-light.png` 与 `build/source-card-dark.png`，确认来源胶囊与展开玻璃卡片布局、图标与浅深色外观正常。
- 未能完整通过：`build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --action-cursor-preview` 在到达来源标签检查前的通用重叠按钮指针测试（`AgentReplyRegression.swift:3305`）处因后台运行环境指针/窗口焦点限制中断，未纳入通过项。

## 维护门禁结论

- `AGENTS.md: unchanged` — 仅调整对话引用来源标签的点击与弹层交互，不改变项目架构边界、开发命令或持久协作规范。
- `README: unchanged` — README 未描述引用来源标签的悬停/点击细节，功能概览与开发构建命令无变化。
