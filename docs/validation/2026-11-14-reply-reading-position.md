# AI 回答阅读位置

## 改动

- 去掉消息条数和回答活动变化触发的自动到底部。仅最新用户消息 ID 变化时定位到底部。
- 首次打开仍定位到历史底部；回答出现及内容尺寸变化以顶部锚定保留阅读位置。保留手动回到底部按钮。
- macOS 15+ 使用 ScrollViewReader 显式定位，避免 ScrollPosition 记录的底部边缘持续跟随内容增长。macOS 14 兼容路径同步调整。

## 实际验证

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`（Packages/KulaCore）：通过。
- `xcodegen generate`：通过。
- README Debug `xcodebuild`：通过。
- `python3 App/Tests/run-agent-reply-regression.py --reading-scroll`：通过。独立隔离数据的原生窗口中，70 段回答超过两屏，完成后滚动偏移变化小于 2 pt；手动滚到 200 pt 后仍保持该位置。
- `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --reading-scroll --preview-macos14`：同一断言通过。这是在当前系统强制兼容路径，未在真实 macOS 14 系统运行。
- `git diff --check`：通过。

## 范围与限制

未请求线上模型，未替换或重启日常运行的 Asky。构建与回归使用当前工作区，其中已有本任务前的气泡和完整回复修改。

README 的中英文行为与回归命令已同步；AGENTS.md 无新增持久规则，保持不变。构建产物沿用已有 `build/` 忽略规则。

本次所改 AgentView、回归测试及文档在任务开始前已经修改；为保留已有修改及其依赖，未自动提交混合工作区。
