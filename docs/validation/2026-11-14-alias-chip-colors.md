# 别名标签颜色同步

`AliasChip` 移除旧 `.quaternary` 灰底，复用 `settingsInputChrome` 的浅深色填充与描边。保留字体、内边距和 5pt 圆角，不改变别名功能。

已执行：

- `xcodegen generate`：通过。
- README 的 Debug `xcodebuild` 命令：通过，日志 `build/alias-chip-build.log`。
- `Packages/KulaCore` 中 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，43 tests，日志 `build/alias-chip-core-test.log`。
- 已尝试打开新构建的 Debug 应用；CUA 在打开设置时报告 `noWindowsAvailable`，未完成实际窗口的浅深色视觉检查，不记为通过。

README: unchanged，仅修复既有标签配色，使用方式及开发命令不变。
AGENTS.md: unchanged，没有工作流、模块边界或持久规则变化。
构建日志与检查清单沿用已有 `build/` 忽略规则。
