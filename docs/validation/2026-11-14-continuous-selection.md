# 连续文字选区与胶囊菜单

## 修复

- 每个 `ChatMarkdownView` 持有一个弱引用注册的选区组。原生拖选按阅读顺序跨段落、无序列表、有序列表及嵌套列表扩展；复制和添加引用共用完整选区文本，保留行内公式源码。
- 列表标记参与选区并对齐首行。原生文本宽度测量不再修改最终渲染尺寸，避免 SwiftUI 的临时宽度探测把长列表挤窄、造成文字重叠。
- 菜单使用胶囊形状，原生玻璃与裁剪层的圆角始终为实际窗口高度的一半，包括按压时系统取整后的尺寸。保留既有侧向提亮、回弹及无额外窗口阴影。
- 全选作用于同一 Markdown 回复；点击空白处或 Esc 清除整组选区。

## 已运行

- `xcodegen generate` 与 README 的 Debug `xcodebuild` 命令：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `--continuous-selection-preview`：真实 AppKit 窗口内注入原生拖选事件；通过正向/反向拖选、部分起止文字、换行长列表、嵌套列表、无序到有序列表、引用载荷、全选、空白点击取消，以及静止/按压时胶囊圆角断言。
- `--selection-preview`：通过五种 Agent 颜色的深浅外观、公式源码、菜单真实操作、重复引用去重、输入焦点、发送失败保留及历史恢复。
- `--math-preview`：通过公式解析、原生排版、无效源码回退与深浅/窄窗口检查。
- 查看实际窗口截图 `build/ContinuousSelectionSource/build/continuous-selection.png`，确认跨列表选区、首行对齐、长行换行和胶囊外形；另检查窄窗口公式截图。

工作区同时有其他任务更新 Swift 文件和编译产物，因此原生回归使用 `build/ContinuousSelectionSource` 源码快照及 `build/ContinuousSelectionDerivedData` 产物快照隔离编译。本次改动的源码和新增测试函数与工作区对应内容一致；临时诊断输出不进入提交。原生拖选测试保持真实 AppKit 主循环运行，避免异步命令行主循环在切换鼠标追踪模式后提前退出。中途失败的检查没有计为通过。

已重启 `build/DerivedData/Build/Products/Debug/Asky.app --show-agent`，通过进程完整路径确认运行的是最新 Debug bundle。

## 边界与文档

本次验证覆盖同一 Markdown 回复中的文本块，不把跨消息、跨交互表单或独立图片的拖选记为已验证。没有重新发布 Release。

README 中英功能说明与新回归命令已同步，设计系统已同步。根级与 App 的 AGENTS.md 现有规则覆盖此改动，无需修改。构建产物、截图、隔离副本沿用既有 `build/` 忽略规则，生成工程沿用 `Asky.xcodeproj/` 忽略规则。
