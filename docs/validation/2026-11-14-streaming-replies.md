# 多轮工具调用的流式回复与排版修复

日期：2026-11-14。用户现象：多轮工具前后的说明和最终标题粘成一段，生成阶段长时间显示“处理中”，完成后才形成最终 Markdown。

## 原因与修复

- Swift Runtime 原本仅在任务最终回答时发出 message，前面各轮 textDelta 在前端同一缓冲区累积。现在每轮模型输出完整后即发出独立 message，之后再执行工具；AgentModel 也在工具边界保存尚未结束的文本，兼容缺少完整消息事件的运行时。
- SSE 原本忽略 [DONE]，继续等网络响应关闭。现在收到结束标记就完成解析并取消该响应的剩余等待；仍需已收到有效 finish_reason，截断输出不会标为成功。
- 生成正文时不再重复显示“处理中”；等待模型、工具调用、确认与上下文压缩仍沿用其状态。中间说明不重复显示复制/时间操作栏，最终回答保留操作栏。
- 现有 Markdown 与原生表单继续共用同一套渲染，不改写模型正文或插入制作说明。

## 实际验证

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore --scratch-path build/NativeCoreTests`：330 项通过。
- 新增多轮模型/工具事件顺序回归，确认三轮正文各自完成后才进入下一轮；标题、空行、列表和代码文本保持原样。
- 真实回环 HTTP 测试服务在 [DONE] 后继续保持响应打开 5 秒，Swift 工具闭环在约 0.13 秒完成，不等待连接关闭。
- `xcodegen generate` 与 README 中 Debug 构建命令通过；`build/NativeDerivedData` 下 Release 构建通过。Debug 签名校验通过。
- `python3 App/Tests/run-agent-reply-regression.py --streaming-preview`：通过；使用实际 AgentModel / AgentWindowController 构造多轮工具事件，在尚未结束任务时截取原生窗口。工具结果为测试数据，没有实际启动 Orca 或 Claude Code。
- 已查看 `build/streaming-reply-running.png` 和 `build/streaming-reply-completed.png`：生成中的两个说明段落独立，最终标题、列表、行内代码已排版；没有重复“处理中”。结束前后内容位置保持一致，结束后显示复制操作。
- 编译产物直接运行普通 AgentReplyRegression：流式分组、历史恢复、澄清、取消、耗时、附件与新对话回归通过。
- `python3 App/Tests/run-agent-reply-regression.py --forms-preview --radio-preview`：完整通过，含早期编辑、原生输入、单选、完成时焦点与值转移、明暗/窄屏、历史与重复提交防护。
- 表单回归原先假设最后一条永远是提交的用户消息；原生运行时会在缺少测试凭据时追加错误。已改为同时确认预期请求失败、提交的用户回复在历史中恰好保留一次。未改动真实表单提交流程。
- `python3 App/Tests/check-localization.py`：通过；`git diff --check` 通过。
- 已重新打开 `build/DerivedData/Build/Products/Debug/Asky.app`，进程 PID 69172，启动时间 17:13:36，晚于本次 Debug 二进制更新时间 17:11:43。日常 `/Applications/Asky.app` 未替换。

日志位于 `/tmp/asky-stream-{core,build,release,preview,ui-tests,form-verified}.log`。仍需用户实际多轮模型与插件任务验收；上述窗口检查使用确定性事件夹具，不冒充真实 Orca 操作结果。
