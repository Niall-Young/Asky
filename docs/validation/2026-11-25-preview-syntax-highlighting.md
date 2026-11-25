# 快速预览代码语法高亮

2026-11-25 在 macOS 27 上运行以下检查。

```sh
(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-launcher-window-regression.py --file-preview --capture
open -W -n build/LauncherWindowRegression.app --args --file-preview
build/LauncherWindowRegression.app/Contents/MacOS/LauncherWindowRegression --file-preview --capture --dark-only
```

- 新增 `SyntaxHighlighterTests` 与 `PreviewFileTests` 通过。覆盖文件名、扩展名和 shebang 识别；Swift、Python、Shell、JSON、YAML、TOML、HTML（含内嵌 script / style）、CSS、Diff、C、Rust、SQL、TypeScript 的关键字、字符串、注释、数字、类型、函数、属性等分类；URL 中的 `//`、字符串中的 `#`、英文撇号和 Shell 的 `$#` 不被误判；所有语言在未闭合字符串、注释、标签和中文与 emoji 输入下返回的范围都不越界；超过 512 KB 的文本不着色，`.txt` 和 CSV 不着色。
- 按 README 命令执行 XcodeGen 和 Debug 构建，通过。
- 文件预览窗口回归新增断言：Swift 源码首个关键字使用语法颜色，CSV 保持 `labelColor`。直接从终端运行时，浅色与深色两轮中有一次在打开 `Preview.png` 时停在“预览成为 key window”的断言，与 0.3.7 验证中记录的同类焦点不稳定一致，与本次改动无关。通过 Launch Services 启动同一测试应用四次：两次完整通过浅色与深色两轮；另外两次没有任何输出，未能确认进程已运行。仅深色的直接运行完整通过。
- 查看浅色和深色下 Swift 预览截图，以及深色下 JSON 预览截图：关键字、类型、函数、字符串和 JSON 键各自着色，玻璃背景上可读，未高亮字符仍为系统文字色。
- Release 构建中 512 KB 的 Swift 文本着色约耗时 15 ms（Debug 约 150 ms），在读取文件的后台任务中完成。
