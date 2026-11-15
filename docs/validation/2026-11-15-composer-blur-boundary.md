# 底部渐进模糊边界

- 移除底部模糊层向输入框上方延伸的 24 pt。模糊层高度现在等于输入框实测高度（含底部 12 pt 留白），沿用从顶端零半径到窗口底部 6 pt 的反向渐变；输入框多行增高时同步调整。
- `xcodegen generate` 与 README 中的 Debug `xcodebuild` 命令通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` 通过。首次未指定 Xcode 时因 Command Line Tools 无法导入 XCTest 失败，指定完整 Xcode 后通过。
- `python3 App/Tests/run-agent-reply-regression.py --bottom-push` 通过，覆盖短回复、长回复、自然滚动、输入框增高及末条消息避让。
- 已查看本轮新编译原生窗口的浅色和深色系统截图：`build/composer-overlay-NSAppearanceNameAqua.png`、`build/composer-overlay-NSAppearanceNameDarkAqua.png`。输入框上方正文保持清晰，无原先提前变糊的一段。
- 产物与日志沿用现有 `build/` 忽略规则；未替换已安装应用或重启用户正在运行的会话。
- README 中英文与设计系统已同步边界说明；AGENTS.md 无需调整，未改变架构、命令或维护规则。
