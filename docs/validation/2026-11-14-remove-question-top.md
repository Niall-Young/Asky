# 移除新问题自动置顶

按用户最终指令移除“发送新问题后自动置顶”整项能力：删除问题锚点、最新轮次预留一屏高度、提交后的延迟定位和校正逻辑，以及对应回归与原验证文档。消息列表和原有回归已逐字核对恢复到 `74563ed` 之前的实现；保留后续独立玻璃样式修改。

实际执行：

- KulaCore `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` 通过，日志 `build/remove-question-top-core.log`。
- `xcodegen generate` 与 README Debug `xcodebuild` 命令通过，日志 `build/remove-question-top-build.log`。
- 源码比对通过：Transcript 至 ChatResponseGroup 前的全部列表实现，以及 AgentReplyRegression.swift，与添加置顶前的版本完全一致。
- Debug 可执行文件构建于 21:42:57；重启后核对 PID 65284，21:43:09 启动，来自仓库 Debug Asky.app，参数 `--show-agent`。未作真实会话视觉验收，未发布新版本。
- 产物沿用现有 `build/` 忽略规则。

README: updated，中英文移除自动置顶说明，恢复原有行为描述。
AGENTS.md: unchanged，移除未引入新的长期规则或命令。
