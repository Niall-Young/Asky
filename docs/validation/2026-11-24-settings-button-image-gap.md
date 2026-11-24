# 调整设置按钮图标与文字间距

## 问题与修复

- macOS 26 的 `.glass` 胶囊按钮只在前置图片与标题之间保留约 2.5 pt；`GitHubMark` 这类铺满画布的模板徽标看起来会紧贴文字。
- 在 [SettingsStyle.swift](../../App/Sources/SettingsStyle.swift) 中不改原生标题，也不调整 `imageHugsTitle`，而是在 `SettingsPushButton.applyContent` 给带文字的前置图片补 4 pt 透明尾部间距（`NSImage.paddedForTitleGap`）。标题字符串保持原样，回归查找与辅助功能名称不受影响；无文字的纯图标按钮不加间距。

## 实际验证

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，83 个测试全部通过。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-settings-regression.py`：通过；查看 `build/settings-light-about.png` 与 `build/settings-dark-about.png` 确认 GitHub 按钮图标与文字之间留有间距，其他设置页布局未变。
- 临时探针以 0 / 4 / 6 pt 额外间距在真实设置窗口抓取 `screencapture -l`，对比确认 4 pt 时视觉效果为“一点点距离”；探针代码已移除，未留在提交中。
- Debug 构建按钮宽度由 89.5 pt 增至 93.5 pt，标题起点由 30 pt 移至 34 pt，与加宽量一致。

README: unchanged — 未改变功能范围、使用流程或开发命令。
AGENTS.md: unchanged — 未引入或变更持久性协作规则与架构边界。
