# 启动器底部 Clear 玻璃按钮

## 改动

- `LauncherActionButtonStyle` 改为 Clear 玻璃、60% 背景强度。启动器主操作、访达操作、更多按钮，以及复用该样式的剪贴板底部按钮同步生效。
- 强度仅作用于玻璃背景；文字、快捷键、尺寸与指针反馈保持原实现。展开的菜单保留 Regular 玻璃。
- README 中英文与设计系统同步；AGENTS.md 无需调整，本次没有新增开发命令或架构边界。

## 实际执行

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，Swift Testing 43 项。
- `python3 App/Tests/run-launcher-window-regression.py --action-bar`：编译成功并生成浅色实际窗口截图，但失败于 `Cmd K must open on first action`。
- 直接运行该回归可执行文件并添加 `--action-bar --dark-only`：生成深色窗口截图，同样失败于上述快捷键断言。菜单展开交互不记为通过；本次未修改键盘路由。
- 已目视检查 `build/launcher-actions-NSAppearanceNameAqua-closed.png` 与 `build/launcher-actions-NSAppearanceNameDarkAqua-closed.png`：底部按钮使用轻量玻璃，标签和快捷键可见。
- 截图与回归产物复用 `.gitignore` 中已有 `build/` 规则，不提交产物；未替换已安装应用。

工作区同时存在其他任务的聊天与共享玻璃代码变更；本次仅提交按钮样式及相关文档。
