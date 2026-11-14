# 头像玻璃容器

2026-11-14：将左上角固定小怪物与 Asky 名字整体放入 36 pt 高的 Clear 液态玻璃胶囊，背景强度 35%，复用右侧按钮组材质。左内距 4 pt、右内距 12 pt，仍不提供点击配置。

实际运行并通过：

- `xcodegen generate`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- `git diff --check`
- 重启本次 Debug 构建，通过 Computer Use 检查实际窗口中的胶囊与右侧按钮组

README: unchanged — 仅更改容器视觉，固定头像的入口与使用说明仍准确
AGENTS.md: unchanged — 无构建流程或模块边界变化

保留工作区原有未提交改动，未自动提交混合内容。工程及构建产物使用现有忽略规则。

## 后续按圆形头像参考修正

头像与名字分离：32 pt 图形区域加 3 pt 内距，使用独立圆形玻璃。去除实色底板，圆形头像和右侧按钮组均调用 `nativeGlassBackground(interactive: true, clear: true, glassOpacity: 0.35)`，只保留形状差异。

本次重新执行 XcodeGen、Debug 构建及 KulaCore `swift test`，均通过；已退出旧进程并打开新构建，实际窗口中确认圆形头像与右侧按钮组的玻璃材质。`git diff --check` 通过。README 和 AGENTS.md 仍无需修改。
