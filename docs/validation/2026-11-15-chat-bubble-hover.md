# 用户气泡悬停尺寸稳定性

## 根因与修复

上次按内容收缩的修改使用正在显示的 NSTextView 布局管理器测量自然宽度。原生悬停刷新时，该布局管理器可能保留当前行宽，随后再次增加 2 pt 留白，导致短气泡持续变宽。真实 AppKit 事件循环下复现了尺寸断言失败；仅调整外层 HStack 未能修复，最终保留原有外层布局。

`ChatInlineNativeText` 现在使用独立的 TextKit 测量栈：富文本内容改变时更新自然宽度缓存，按给定上限测量换行高度，不再临时修改显示中的文本容器。用户与 AI 消息共用修复，既有圆角、内距、表情贴纸和复制按钮样式保持原状。

## 已运行并通过

- `xcodegen generate`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/HoverDerivedData build`
- 在 `Packages/KulaCore` 运行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path ../../build/HoverCoreTests`
- `NSUnbufferedIO=YES ASKY_DERIVED_DATA="$PWD/build/HoverDerivedData" python3 App/Tests/run-agent-reply-regression.py --user-bubble-hover`
  - 实际 AppKit 事件循环和鼠标事件；覆盖短中英文、emoji、长文本，以及浅色、深色模式，均包含机器人表情与 AI 回复。
  - 72 次移入正文、移到复制按钮、移出；检查用户与 AI 文本位置和尺寸、气泡底板像素一致，以及复制按钮出现、维持显示、隐藏。
  - 原图短文本 `Anthropic 呢?` 的文本尺寸始终为 90 × 21 pt；长文本始终为 460 × 88 pt，正常换行。
  - 每个场景使用独立临时数据库，结束恢复鼠标位置。测试窗口置顶并确保焦点；并发原生测试曾抢占焦点，相关失败没有记为通过。仅调用 `window.sendEvent` 不足以验证 SwiftUI 悬停，因此没有将最早的静态检查作为验收依据。
- 复用隔离构建的 `AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression` 执行并通过：
  - `--bubble-width-preview`：短用户/AI 消息、富文本、280/460 pt 长文和深浅色有序/无序/嵌套列表。
  - `--continuous-selection-preview`：原生正反向跨段拖选、列表、引用及选区菜单。
  - `--math-preview`：公式布局、无效源码回退、深浅色截图。
- 使用上述编译脚本运行 `--sources-preview` 通过：来源分组、悬停、点击、长列表滚动及深浅色定位。修正了旧测试错误地选择首个标题文本及普通链接的问题，现在定位真实来源附件；没有修改来源组件实现。

已查看浅色短消息与深色长消息的真实窗口截图，复制按钮悬停态、表情与换行正常。日志和截图位于 `build/hover*`、`build/user-bubble-hover-*`。

## 文档与边界

README 中英文同步加入 `--user-bubble-hover` 命令。构建、日志及截图沿用 `build/` 忽略规则，生成工程沿用 `Asky.xcodeproj/`，无需新增规则。未发送真实 AI 请求、未改写用户会话、未发布 Release。

已结束旧的 `build/DerivedData` 调试进程，打开 `build/HoverDerivedData/Build/Products/Debug/Asky.app --show-agent`。通过进程完整路径确认当前运行的是新构建（验证时 PID 67678），没有替换 `/Applications` 安装包。
