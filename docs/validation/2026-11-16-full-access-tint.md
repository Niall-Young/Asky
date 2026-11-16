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

## 第二轮：减少灰感

用户实看首版后反馈偏灰。提高红色饱和度，最终浅色为 `#D94F55`、深色为 `#F57478`；按钮与菜单继续共用样式。

重新运行上述指定 Xcode 的 `swift test`、`xcodegen generate`、Debug `xcodebuild` 与 `--approval-menu-hover`，均通过。重新检查两张亮暗菜单截图，红色更鲜明。`git diff --check` 通过。

已退出旧 Debug 进程并启动 `build/DerivedData/Build/Products/Debug/Asky.app`，确认新 PID 4576 使用该路径。此轮已重启用户的 Debug 应用，未替换 `/Applications` 安装包。README 与忽略规则保持不变。

## 第三轮：亮暗统一橙黄色

按用户最新要求，亮暗两种外观均改为橙黄色：浅色 `#AD690B`，深色 `#E8AD52`。浅色加深以保持可读性。

最终色值应用后重新运行指定 Xcode 的 `swift test`、`xcodegen generate`、Debug `xcodebuild` 与 `--approval-menu-hover`，均通过。检查新生成的亮暗菜单截图，图标与文字均为对应的橙黄色；`git diff --check` 通过。仅修改暗色的中间回归在用户补充要求后中止，不作为本轮通过依据。

Debug 已重启，确认 PID 5288 运行 `build/DerivedData/Build/Products/Debug/Asky.app/Contents/MacOS/Asky`。README 保持不变，使用方式未变；构建和截图沿用现有忽略规则。
