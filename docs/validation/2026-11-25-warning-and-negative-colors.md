# 警告警戒色与低饱和破坏性／负向红分层

将警告警戒色与删除／破坏性／负向红拆分为两层共享语义令牌，统一由 `Packages/KulaCore/Sources/Theme` 解析：

- **警告／警戒色（`textWarning` / `ThemeColor.kWarning` / `FullAccessTint`）**：沿用浅色 `#AD690B`、深色 `#E8AD52`，用于「完全访问」按钮与审批菜单项、插件「需要配置」标记及登录项状态提示。
- **删除／破坏性／负向红（降饱和红）**：文字／图标／描边（`textNegative` / `iconNegative` / `borderNegative`）使用浅色 `#B84542`、深色 `#DC726E`，实心破坏性弹窗按钮底色（`backgroundNegative` / `ThemeColor.kBackgroundNegative`）使用浅色 `#B84542`、深色 `#B54B48`（保留白色文字高对比）。覆盖气泡更多菜单「删除」、全局液态玻璃确认弹窗破坏性按钮、启动器与剪贴板更多菜单破坏性项、设置行更多菜单（「删除」「卸载」）、设置破坏性按钮、行内 Tag 浮层「移除」以及错误提示。`ToolIconPalette.red`（`#FF0000` 退出工具图标底板）与设置装饰图标色块保持原值。

## 已运行验证

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`（`Packages/KulaCore`）：通过（16 suites / 91 tests，含新增 `ThemeTests.warningAndNegativeTokensUseAppearanceAdaptivePalette`）。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过（`BUILD SUCCEEDED`）。
- `python3 App/Tests/run-agent-reply-regression.py --bubble-menu-preview`：通过；人工查看 `build/bubble-menu-user-more-light.png` 与 `build/bubble-menu-user-more-dark.png`，确认亮暗模式下「删除」图标与文字呈柔和低饱和红，边缘清晰、无刺眼高亮。
- `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --delete-dialog-preview`：通过；人工查看 `build/delete-dialog-light.png` 与 `build/delete-dialog-dark.png`，确认亮暗模式下确认弹窗「删除」胶囊按钮呈低饱和红底配高对比白色文字。
- `git diff --check`：通过。

未覆盖项：未单独截图剪贴板／启动器更多菜单、设置行 `NSMenu`（别名「删除」／插件「卸载」）与设置页破坏性按钮，均经共享 `ThemeColor.kTextNegative` 解析，逻辑与截图界面共用同一颜色令牌；`--approval-menu-hover` 因同屏并发回归抢占焦点未在本轮记为通过。

README 与 AGENTS 保持不变：仅调整 Theme 语义色与界面色彩映射，目录结构、构建命令与协作规则无变化。
