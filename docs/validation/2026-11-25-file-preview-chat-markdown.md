# 文件预览 Markdown 对齐 AI 对话样式

日期：2026-11-25

## 变更

- 快速搜索 / 剪贴板历史的 Markdown 文件预览不再使用 MarkdownUI `Theme.gitHub`（15 pt、放大标题、深色行内代码底），改为复用 `ChatMarkdownView`：14 pt 正文、14 pt semibold 标题与间距阶梯、聊天列表圆点、带语言标签与复制按钮的代码块、表格、引用与分割线样式全部与 AI 对话一致。
- `ChatMarkdownView` 新增 `fileDirectory` 文件模式：相对链接与图片以文件所在目录为基准解析；块级与行内图片经 `PreviewFile.loadMarkdownImage` 读取，仍限制在该目录内；不做聊天专用的数学公式改写与照片画廊拆分，文件内容按原样渲染。聊天回复路径（`fileDirectory == nil`）行为不变。

## 实际运行的检查

| 检查 | 结果 |
| --- | --- |
| `xcodegen generate` + `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build` | BUILD SUCCEEDED |
| `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | 通过（91 tests / 16 suites，无失败） |
| `python3 App/Tests/run-launcher-window-regression.py --file-preview --clipboard-only --capture` | 通过（浅色、深色两种外观）；截图 `build/file-preview-*-clipboard-Preview.MD.png` 显示聊天样式标题、列表、相对路径本地图片与代码块 |
| `python3 App/Tests/run-launcher-window-regression.py --file-preview --capture`（含启动器路径） | 未通过：在打开任何预览之前即失败于 “launcher and file fixtures must be visible before testing”（启动器面板 / 夹具可见性检查），未执行到 Markdown 预览；与本次改动无直接关联，未计为通过 |
