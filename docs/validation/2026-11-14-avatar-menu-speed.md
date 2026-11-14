# 头像颜色菜单动画速度

- 将 `AgentAvatarPicker` 展开、收起的弹簧 response 从 0.36 s 调整为 0.28 s，缩短约 22%；dampingFraction 保持 0.58。
- 保留原生玻璃变形、菜单尺寸和减少动态效果时直接切换的行为；同步设计系统中的参数。

## 已执行验证

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，退出码 0。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过，`BUILD SUCCEEDED`。
- `git diff --check`：通过。
- 未运行原生窗口点击检查，未验证实际视觉手感，未替换已安装应用。

## 文档与产物

- README: unchanged — 仅微调动画节奏，已有头像菜单功能和使用说明仍然准确。
- AGENTS.md: unchanged — 未改变架构、命令或持久开发约束。
- 构建产物与生成工程由已有 `build/`、`Asky.xcodeproj/` 忽略规则覆盖，无新增忽略规则。
