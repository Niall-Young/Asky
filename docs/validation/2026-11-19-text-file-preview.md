# 纯文本文件快速预览

2026-11-19 在 macOS 27.0.1 上运行以下检查，均通过。

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build
(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-launcher-window-regression.py --file-preview --capture
```

- 快速搜索通过预览快捷键打开 CSV、带 BOM 的 UTF-16 JSON 和 Swift 源码，剪贴板历史打开单个 CSV 文件。测试比对原生文本视图中的完整内容，涵盖中文、CRLF、缩进和标点，并检查只读与可选择状态。
- 浅色和深色窗口回归通过。检查了浅色 Swift 与深色 JSON 的截图，确认文件名和等宽原文可见。原有图片、Markdown、菜单、快捷键重绑及关闭后恢复选中的回归通过。
- 核心测试覆盖普通文本、日志、配置、源码、常见无扩展名文件以及空文件。无效 UTF-8、包含 NUL 的文本和超过 2 MiB 的文件进入读取失败路径。
