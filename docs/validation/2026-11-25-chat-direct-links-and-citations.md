# 2026-11-25 聊天正文直达链接与参考来源标签分流验证

## 变更范围

- [ChatSourcePreview.swift](../../App/Sources/ChatSourcePreview.swift)：
  - 扩展 `ChatSourceTextView.isCitation(_:)`（覆盖数字索引与 `来源`/`引用`/`参考`/`出处`/`source`/`citation`/`ref`/`reference` 及其编号形式），确保只有引用类链接进入 `ChatSourceTextView.sources(in:)`，裸网址和带文字的行内链接不再重复生成段末来源标签。
  - 新增 `ChatSourceTextView.isDirectOpenableLink(_:)` 与可注入的 `openLinkHandler`（默认调用 `ToolService.openLauncherURL`），点击正文非引用链接（`http`/`https`/`mailto`）直接通过默认应用打开，点击来源标签仍打开来源预览卡片。
- [ChatMarkdownView.swift](../../App/Sources/ChatMarkdownView.swift)：
  - 正文非引用链接保留 `.link` 属性、系统链接蓝（浅色 `#146BD9` / 深色 `#73B8FF`）、单下划线与手型指针（`NSCursor.pointingHand`）；段末来源标签显式保持箭头光标（`NSCursor.arrow`）。
- [ChatLinkService.swift](../../Packages/KulaCore/Sources/ToolService/ChatLinkService.swift)：
  - 在 `validateInferredSiteName(_:titlePrefix:)` 中拒绝包含顿号、逗号、句号、感叹号、问号、分号等句内标点的标题后缀，避免将官网口号（如 `百度开发者中心 - 汇聚、开放、助力、共赢` 中的 `汇聚、开放、助力、共赢`）误判为站点名。
- [NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift)：
  - 更新运行时协议提示词，明确区分参考出处（段末 `[来源](URL)`，由客户端折叠为来源标签）与直接提供给用户的网址/入口（直接输出完整网址或 `[名称](URL)`，由客户端渲染为可点击正文链接且无需对同地址重复附 `[来源](URL)`）。
- [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)、[ChatLinkServiceTests.swift](../../Packages/KulaCore/Tests/ToolServiceTests/ChatLinkServiceTests.swift) 与 [NativeRuntimeTests.swift](../../Packages/KulaCore/Tests/AgentHostTests/NativeRuntimeTests.swift)：
  - 补充正文命名链接与裸网址可点击样式、不附多余来源标签、直接触发打开回调、标题宣传语过滤与提示词约束测试。

## 实际执行检查

1. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（全部测试套件 0 失败，包含 `ChatLinkServiceTests` 9/9 及 `AgentHostTests` 全部用例）。
2. `xcodegen generate`：通过。
3. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过（`** BUILD SUCCEEDED **`）。
4. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --sources-preview`：通过（输出 `Source tags, +N grouping, hover/click lists, long-list scrolling and light/dark positioning passed`），已检查新构建真实窗口生成的 `build/sources-light.png` 与 `build/sources-dark.png`，确认引用链接继续显示为段末胶囊标签，正文命名链接（`打开官网`）与裸网址（`https://www.baidu.com`）均以蓝色下划线直达链接呈现且不附多余来源标签。
