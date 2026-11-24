# AI 对话滚动时抑制引用链接悬停弹窗

## 变更

- [ChatSourcePreview.swift](../../App/Sources/ChatSourcePreview.swift)：
  - 新增 `ChatSourceScrollGuard`，在窗口存在引用来源标签时监听本地 `.scrollWheel` 事件，跟踪触控板手势、惯性滚动与离散滚轮的滚动状态及冷却时间（并带有超时兜底，避免遗漏结束事件导致永久抑制）。
  - 滚动 AI 对话窗口时，立即取消待触发的 300 ms 悬停任务、关闭当前打开的 `ChatSourcePopover`，并在滚动及短暂冷却期内抑制悬停弹出；显式点击引用标签仍可立即打开。
  - `ChatSourceTextView` 在 300 ms 悬停定时器到期时再次校验未处于滚动抑制期且引用标签锚点未发生位移，避免拖动滚动条等非滚轮滚动后误弹出。
  - 若当前打开的来源弹窗内容无需滚动（`!isScrollable`）且滚轮事件落在弹窗上，自动关闭弹窗并将滚动事件转发回外层对话 `NSScrollView`，不中断滚动；长来源列表弹窗（`isScrollable == true`）仍保留内部滚动。
- [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)：在 `--sources-preview` 中补充滚动状态机、滚动期间抑制悬停、悬停中途滚动取消、锚点位移取消、滚动关闭已打开弹窗、滚动后点击打开以及冷却结束后恢复悬停的回归断言。

## 验证

- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过。
- `python3 App/Tests/run-agent-reply-regression.py --sources-preview`：通过（`Source tags, +N grouping, hover/click lists, long-list scrolling and light/dark positioning passed`）。
- `(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)`：通过（全部测试套件 0 失败）。

## 维护门禁

- `AGENTS.md: unchanged` — 本次为对话引用悬停与滚动交互缺陷修复，未新增或变更持久项目规则、命令或模块边界。
- `README: unchanged` — 属于内部交互体验修复，未改变产品功能说明、安装/构建命令或使用方式。
