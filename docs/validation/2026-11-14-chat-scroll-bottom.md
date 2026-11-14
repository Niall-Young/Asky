# AI 对话回到底部修复

## 原因与修改

- 原 `bottom` 标记位于 12 pt 底部 padding 之前，而底部状态按完整文档高度判断。原逻辑的独立副本在实际窗口中点击一次后，测得剩余距离为 `12.0` pt。
- 将这段留白纳入底部标记，标记由 1 pt 改为 13 pt，外层仅保留顶部 padding。对话总高度和视觉间距不变。
- macOS 14 兼容分支在多条不同高度的懒加载消息中，首次动画后还能剩下 `241.0` pt。该分支改为在动画完成后按最终布局再定位一次；没有增加回复更新时的自动滚动。
- 扩展现有 `--reading-scroll` 窗口回归，通过原生鼠标按下/抬起事件点击实际按钮，检查文档底部与可见区域底部的差值。`--scroll-history` 增加 30 条不同高度的历史消息。

## 实际验证

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`（在 `Packages/KulaCore`）：通过。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- 新编译的 `AgentReplyRegression.app`：以下四组均通过，最终距离均为 `0.0` pt，并保留回答出现时的阅读位置。

| 参数 | 场景 |
| --- | --- |
| `--reading-scroll` | 普通分支，70 段长回答 |
| `--reading-scroll --scroll-history` | 普通分支，30 条历史消息加长回答 |
| `--reading-scroll --preview-macos14` | 兼容分支，长回答 |
| `--reading-scroll --scroll-history --preview-macos14` | 兼容分支，历史消息加长回答 |

共享源码与构建目录在验证期间被其他任务更新，曾触发编译器的 `input file was modified during the build` 检查。最终窗口回归使用 `build/ScrollRegressionSources` 源码快照和 `build/ScrollRegressionData` 构建产物副本，由现有回归脚本的临时路径适配副本编译；这些产物均受现有 `build/` 忽略规则覆盖。修复后的 App 常规构建另行通过。

macOS 14 检查是在当前系统强制进入兼容分支，并非在 macOS 14 真机执行。未替换已安装应用或重启用户正在使用的 Asky。现有 actor isolation 与 AppIntents 元数据警告不属于本次改动。

## 文档检查

- README: unchanged。修复恢复既有手动回到底部行为，不改变使用方式与现有开发命令。
- AGENTS.md: unchanged。未引入新的模块边界或长期开发约束。
