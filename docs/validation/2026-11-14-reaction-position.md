# 表情贴附位置修正

日期：2026-11-14。

用户要求表情与用户气泡左下角真实交叉重叠，不遮挡正文。

- 从复制按钮所在的独立操作行移除表情，改为用户气泡自身的 bottomLeading overlay。
- 表情胶囊高 26 pt，向下偏移 13 pt，向左偏移 8 pt。上半部分压住气泡底部边缘，位于正文下方 14 pt 留白内；下半部分位于气泡外，原操作行保留所需下方空间。
- 复制按钮仍位于右侧，表情不拦截文字操作；历史表情直接采用新位置，无需重新生成。

已执行：

- KulaCore `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/ReactionDerivedData -clonedSourcePackagesDirPath build/DerivedData/SourcePackages -disableAutomaticPackageResolution build`：通过。
- 沿用上一轮的独立源码快照回归入口，刷新 App/Sources，并使用“给我这个消息贴一个 emoji”作为原生窗口样例；`ASKY_DERIVED_DATA=/Users/niallyoung/orca/Asky/build/ReactionDerivedData python3 build/ReactionSnapshot/App/Tests/run-agent-reply-regression.py --reactions-preview`：通过。
- 已查看浅色、深色实际窗口截图：表情贴住左下角，跨越气泡底边，正文无覆盖。截图位于 `build/ReactionSnapshot/build/reactions-1-{light,dark}.png`。
- 已退出旧版并打开 `build/ReactionDerivedData/Build/Products/Debug/Asky.app --show-agent`；通过实际用户历史窗口检查，原消息上的 💬 已在左下角交叉重叠，正文无遮挡。没有新发模型请求或改动历史内容。
- README 中英文与 PRD 已同步位置规则；AGENTS.md 无新增持久规则，保持不变。构建与截图沿用已有 `build/` 忽略规则。
