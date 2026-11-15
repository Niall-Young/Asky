# Markdown 列表标记占宽修复

## 原因与修改

截图原文在实际 `ChatMarkdownView` 中可复现：原生圆点和编号外的 `frame(minWidth: 21)` 接受横向栈分配的额外宽度，使标记列占据约半行，正文被挤到右侧。

- 无序标记使用明确的 21 pt 列宽。
- 有序标记按当前 14 pt 系统字体测量编号宽度，保留原生文本的 2 pt 测量余量及 21 pt 最小列宽；MarkdownUI 继续将同级编号按最宽标记右对齐，支持三位及更长编号。
- 保留可选中的原生标记、正文样式、8 pt 图文间距和既有列表项上下间距。
- 在现有 `--bubble-width-preview` 中加入用户截图原文、280/460 pt、深浅外观、编号 98–100 与嵌套列表的真实窗口几何断言和截图。

## 验证

- 修复前新增断言实际失败：`Bullet must not consume half the paragraph width`，截图 `build/list-width-before.png` 复现正文占右半边。
- `xcodegen generate` 和 README 的 Debug `xcodebuild`：通过，日志 `build/list-width-build.log`。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，日志 `build/list-width-core-tests.log`（在其他并行改动出现之前运行）。
- 原生 `--bubble-width-preview`：通过。280/460 pt 窗口正文 x 均为 45 pt（含测试容器 16 pt 留白），正文宽分别为 219/399 pt；深浅外观、98–100 编号右对齐、嵌套缩进、文字与标记无裁剪断言全部通过。
- 原生 `--continuous-selection-preview`：通过正向/反向原生拖选、跨段/嵌套/编号列表、部分端点、引用载荷、全选、空白取消与胶囊圆角检查。
- 实际查看 `build/ListWidthSource/build/list-width-460-light.png` 和 `list-width-280-dark.png`，确认原文恢复正常列表排版。

编译期间其他任务改动 `AgentReactionRegression.swift` 导致一次编译中断，因此最终原生回归使用 `build/ListWidthSource`：基于当前任务起点 `ac0aadc` 的 App 源码，仅叠加本次列表修复及气泡宽度回归函数，链接 README Debug 产物。命令为 `ASKY_DERIVED_DATA=/Users/niallyoung/orca/Asky/build/DerivedData python3 build/ListWidthSource/App/Tests/run-agent-reply-regression.py --bubble-width-preview`；随后在该副本目录运行 `build/DerivedData/AgentReplyRegression/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --continuous-selection-preview`（二进制使用仓库绝对路径）。日志分别为 `build/list-width-isolated.log`、`build/list-width-selection.log`。中间失败的尝试不记为通过。

未重启当前用户调试进程，也未覆盖安装目录；已生成包含本次修复的 Debug bundle，当前已打开的旧进程需要重启才生效。

## 文档与产物

README: unchanged。修复现有 Markdown 排版缺陷，没有改变操作方式或开发命令；沿用 README 已列出的回归入口。构建、日志与截图复用 `build/` 忽略规则，生成工程复用 `Asky.xcodeproj/` 忽略规则。本次不发布 Release。
