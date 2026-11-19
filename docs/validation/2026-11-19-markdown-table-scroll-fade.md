# Markdown 表格横向滚动边缘渐变

## 原因与修改

当 AI 回复中的 Markdown 表格宽度超出气泡可用宽度时，原有 `ScrollView(.horizontal)` 在右边缘硬裁切内容，用户不易感知右侧仍有可滚动列。

- 在 `App/Sources/ChatMarkdownView.swift` 中为 `.markdownBlockStyle(\.table)` 增加 `ChatMarkdownTable` 与 `ChatTableScrollObserver`，通过内层横向 `NSScrollView` 的 `documentVisibleRect` 与 `documentView.bounds` 计算左右溢出量（`ChatTableScrollFade`）。
- 仅在存在未滚动完全的一侧通过 alpha `.mask` 渐变淡出（最大宽度 36 pt，且不超过可视宽度的 20%），在最后 8 pt 内平滑消退至 0，避免滚到底时突变；完全能放下时不触发渐隐，保留四边圆角边框。
- 使用 alpha 渐隐而非不透明色块遮罩，确保在浅色/深色外观及原生液态玻璃气泡表面下无色差，并保持表格内原生文本（`ChatSelectableTextView`）可选中。
- 在 `App/Tests/AgentReplyRegression.swift` 中新增 `--table-fade-preview` 回归用例，覆盖 `ChatTableScrollFade` 边界计算、真实 `AgentWindowController` 对话窗口与表格选中能力，以及浅色/深色外观下初始、滚动中、滚到右端三种状态与窄表对比截图。

## 验证

- `xcodegen generate` 与 README 的 Debug `xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（XCTest 及 15 个 Swift Testing suites 共 83 项测试全部通过）。
- `cd MCPBridge && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`：通过。
- `python3 App/Tests/run-agent-reply-regression.py --table-fade-preview`：通过。实测宽表 `docWidth=607.0`、`visibleWidth=460.0`、`maxX=147.0`，真实聊天窗口表格文本选中断言通过；核对 `build/table-fade-chat.png` 以及 `build/table-fade-{light,dark}-{start,mid,end}.png` 截图：
  - 初始位置：仅右侧平滑渐隐，左侧圆角边框完整清晰。
  - 滚动到中间：左右两侧均平滑渐隐。
  - 滚动到最右侧：右侧渐隐消失、右圆角边框完整呈现，仅左侧渐隐。
  - 窄表（未溢出）：左右均无渐隐，四边完整清晰。
- `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --bubble-width-preview`：通过。

## 文档与产物

README: unchanged。本次仅增强 Markdown 表格横向滚动视觉提示，未改变开发或运行命令；构建产物与截图沿用 `build/` 忽略规则。
