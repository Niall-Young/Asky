# DeepSeek 输入缓存前缀稳定性优化验证

2026 年 11 月 19 日。

## 改动范围

- [Repositories.swift](../../Packages/KulaCore/Sources/LocalStore/Repositories.swift)：在 `ConversationStore` 新增 `recentDialogue`、`dialogue(from:limit:)`、`contextByteCount(_:)` 与 `anchoredDialogue(in:maxBytes:rolloverBytes:maxMessages:rolloverMessages:)`，将持续对话历史由每轮头部滑出的滑动窗口改为锚点追加 + 超限批量滚动（40,000 字节 / 80 条上限，滚动后保留约 20,000 字节 / 40 条），并在锚点被删或清空历史时自动恢复。
- [AgentModel.swift](../../App/Sources/AgentModel.swift)：提交请求改用 `anchoredDialogue`，将每轮变化的 `relevant-history`（去重且限制 8,000 字节）和 `selected-quotes` 移至固定 `history` 之后，避免打断历史前缀。
- [NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift) 与 [NativeRuntime.swift](../../Packages/KulaCore/Sources/AgentHost/NativeRuntime.swift)：将 `imageCapabilities` 并入顶部固定 `system` 提示词（仅在包含 `web_read_page` 时加入，压缩请求不携带，不落盘）；同轮续轮期间冻结 `tools` 列表，冷却或 `imagesOnly` 收尾时继续依靠运行时拦截和末尾提示阻止额外网页调用。
- [NativeWebContext.swift](../../Packages/KulaCore/Sources/AgentHost/NativeWebContext.swift)：将网页摘录预算改为按调用顺序从 `remainingBudget`（48,000 字节，单条上限 12,000 字节）逐条分配，不再因后续网页调用回改已发送的旧工具结果。
- [agent-runtime.md](../agent-runtime.md)：同步更新冷却/配图收尾、配图能力提示、网页上下文预算与 DeepSeek 输入缓存说明。

## 本地验证

- 运行 `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`，全部测试通过（包含新增的 `anchoredDialogueStaysAppendOnlyUntilBatchRolloverAndRecoversOnDeletion`、`webProjectionPreservesEarlierResultsAcrossAppendedWebCalls` 及更新后的 `NativeRuntimeTests` 冻结工具与顶部配图能力回归）。
- 运行 `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`，构建成功（`** BUILD SUCCEEDED **`）。
- 本次未触发消耗真实额度的在线 `CacheLiveTests`，线上实际命中率变化需在日常 DeepSeek 对话后观察控制台统计或 `ModelCache` 统一日志。
