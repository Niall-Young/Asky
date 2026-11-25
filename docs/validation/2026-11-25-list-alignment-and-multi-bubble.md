# 2026-11-25 列表标记基线对齐与自然分条多气泡回复验证

## 变更范围

- **无序与有序列表首行基线对齐**：
  - 在 `App/Sources/ChatMarkdownView.swift` 中新增 `ChatListBulletAttachmentCell`（矢量 `NSTextAttachmentCell`，沿用 14 pt 正文上下行高与基线度量，按设备像素对齐绘制圆点/空心圆/方块）和 `ChatInlineBaselineLayout`（在同一次布局中把 AppKit 首行基线同步桥接到 SwiftUI `.firstTextBaseline`），并将 `ChatListItemLabelStyle` 改为 `.firstTextBaseline` 对齐，修复列表圆点在中文及行内来源标签场景下整体上漂的问题。
  - 在 `App/Sources/ChatTextSelection.swift` 中重写 `firstBaselineOffsetFromTop`（正确扣除 `NSTextAttachmentCell` 的基线偏移），并在 `App/Sources/ChatSelectionGroup.swift` 中改用窗口首行基线坐标排序与判断同行 `\t` 分隔，确保带来源标签的列表项在跨块拖选与复制时保持原有阅读顺序。
  - 在 `App/Sources/ChatImageGalleryContent.swift` 中过滤 `cmark-gfm` 重排相邻列表时产生的独立 `<!-- end list -->` HTML 注释行，避免其作为可见正文或选区文本透出。
- **自然分条多气泡输出与滚动锚点**：
  - 在 `Packages/KulaCore/Sources/Contracts/AgentMessageSplit.swift` 中升级 `AgentMessageSplit.split(_:)`：优先尊重代码块外的显式 `<asky-split/>` 标记；在模型未输出显式标记时，按顶层 Markdown 段落自动切分为连续气泡（最多 4 条），同时保持语义成对内容完整（`asky-form` 表单整体不拆、标题绑定后续块、冒号导语绑定紧随其后的列表/代码/表格/引用/图片/公式、松散列表项合并、图片与下方 `[来源](url)` 合并、独立分隔线 `---` 作为分条边界）。
  - 在 `Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift` 中调整 `runtimeProtocolPrompt` 与 `defaultSystemPrompt`，引导模型像真人聊天一样将多段回复自然拆分为 2–4 条连续气泡，且不在用户可编辑人设中暴露 `<asky-split/>` 协议标签。
  - 在 `App/Sources/AgentView.swift` 中将 `completedReplyID` 与 `morphsFromTyping` 改为指向最新回复组的**第一条** `.assistant` 气泡，确保多气泡长回复从第一条气泡开头开始阅读，且等待气泡平滑变形为首条气泡。
- **回归与单元测试**：
  - `Packages/KulaCore/Tests/ContractsTests/AgentMessageSplitTests.swift` 新增自动分段、冒号导语+列表绑定、松散列表合并、标题/图片+来源绑定、`asky-form` 不拆分与上限封顶测试。
  - `Packages/KulaCore/Tests/AgentHostTests/NativeRuntimeTests.swift` 新增多气泡提示词分层断言。
  - `App/Tests/AgentReplyRegression.swift` 在 `--bubble-width-preview` 中新增复现截图结构的无序/有序列表与来源标签首行基线几何断言及浅色/深色窗口截图输出。

## 实际执行检查

（注：当前共享工作区存在其他并发任务对 `steerAccepted` 的进行中改动，隔离验证基于当前 `HEAD` (`033097b`) + 本次任务修改的独立 worktree `build/VerifyTree` 执行，未改动任何无关文件。）

- `cd build/VerifyTree/Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（含新增 `AgentMessageSplit` 与 `NativeRuntimeTests` 全部用例）。
- `cd build/VerifyTree && xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath /Users/niallyoung/orca/Asky/build/VerifyDerivedData -clonedSourcePackagesDirPath /Users/niallyoung/orca/Asky/build/DerivedData/SourcePackages -skipPackageUpdates build`：通过（`** BUILD SUCCEEDED **`）。
- 原生回归测试（浅色与深色真实窗口渲染）：
  - `--bubble-width-preview`：通过；实测所有无序列表圆点（含行内 `[baidu.com]` 来源标签及纯中文/换行项）与有序编号 `1.`、`2.` 与对应首行正文基线偏差全部为 `delta=0.0 pt`（浅色与深色均已目视复核 `list-alignment-light.png` 与 `list-alignment-dark.png`）。
  - `--continuous-selection-preview`：通过（正向/反向拖选、嵌套与有序列表、无 `<!-- end list -->` 透出）。
  - `--bubble-chain`：通过（`Rendered linked gaps: assistant=4.0 pt, user=4.0 pt`，目视复核 `bubble-chain-light.png`）。
  - `--sources-preview`：通过。
