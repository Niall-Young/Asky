# 完全访问状态颜色

将输入区「完全访问」按钮与审批菜单项改为共享 `FullAccessTint`：浅色 `#AC5B55`，深色 `#D98F87`。图标、文字及菜单选中标记同步使用，降低持续状态的红色饱和度。

## 已运行验证

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。首次直接运行 `swift test` 因默认工具链找不到 XCTest 失败，指定完整 Xcode 后通过。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过；构建仍有现存并发隔离、捕获与 App Intents 警告。
- `python3 App/Tests/run-agent-reply-regression.py --approval-menu-hover`：通过。使用新构建产物与当前 App 源码，验证浅色和深色菜单两行悬停、移出恢复与两种模式选择。
- 查看 `build/approval-hover-light-idle.png` 与 `build/approval-hover-dark-idle.png`：两种外观下菜单图标与文字呈柔和暖红，保持可辨识。
- `git diff --check`：通过。

本次未替换已安装应用；未单独截图选中完全访问后的收起按钮，也未覆盖其他壁纸、辅助功能显示设置或旧版 macOS。按钮与菜单使用同一外观解析样式。

README 保持不变：仅调整颜色，使用方式与构建命令未变。构建与截图沿用已有 `build/`、`Packages/KulaCore/.build/` 忽略规则。
