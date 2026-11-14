# 完整回复与真实活动状态

日期：2026-11-14。根据用户最新要求，前端停止逐字输出：发送后显示实际活动，整轮结束后一次展示结果。本规则取代同日先前的流式正文排版方案。

## 当前行为

- 运行中只显示活动行与耗时，按实际事件切换思考、正在使用的工具、上下文压缩及等待确认，不随机轮播状态。
- Runtime 保留底层 SSE、工具参数完整性校验、取消与会话快照，但不向 UI 发送 textDelta，也不发布工具前的中间说明；仅在最终一轮发出完整 message。
- AgentModel 忽略旧增量事件，临时保存完整 message，直到任务结束后才一次追加、持久化和排版。中间说明不会进入聊天投影；Runtime 的模型历史仍保留必要上下文。
- 生成过程中没有正文或表单。完整回复出现后，Markdown、代码、列表与原生表单一起呈现；表单可填写并提交到原会话。原生确认与错误提示不延迟到最终结果。
- 取消时不发布未完成正文，显示已停止；写入未知时继续显示待核实。工具历史与最终复制操作保留。
- 移除正文增量对应的滚动监听、流式占位消息与表单字段转移，活动和完整消息更新仍保留跟随底部及手动回到底部。

## 已执行检查

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore --scratch-path build/NativeCoreTests`：330 项通过。
- NativeRuntime 回归确认两次工具调用期间没有 textDelta 或中间 message，最终仅发布一次完整回复；模型历史仍保留前面各轮。
- 原有真实回环 HTTP 的 SSE 碎片工具调用、[DONE] 后连接不关闭、取消、压缩与会话恢复回归继续通过。
- `xcodegen generate`、README 中 Debug 构建以及 `build/NativeDerivedData` 下 Release 构建通过；两份应用签名验证通过。
- `python3 App/Tests/run-agent-reply-regression.py --reply-activity-preview`：通过。使用实际 AppModel / AgentModel / AgentWindowController，依次验证思考、Orca 工具、思考、上下文整理、完整结果；正文和中间说明始终不可见，直到任务结束后恰好出现一次最终回答。历史重开仍只有最终回答。
- 已查看原生窗口截图 `build/reply-activity-{thinking,tool,completed}.png`，并生成 `pending-result` 截图：运行中只有活动行；最终呈现完整标题、列表、行内代码和复制操作。
- 同一编译产物的普通 AgentReplyRegression 通过：完整回复、历史恢复、澄清、取消、耗时、附件及新对话。
- 同一编译产物增加 `--forms-preview --radio-preview` 通过：表单完成前隐藏、完成后一次显示、真实原生输入、单选组、明暗/窄屏、历史、重复提交与清理。
- `python3 App/Tests/check-localization.py`：166 个 Swift 源文件检查通过；中文/英文键、格式参数一致。
- 已重新打开当前 Debug：PID 72722，进程路径 `build/DerivedData/Build/Products/Debug/Asky.app/Contents/MacOS/Asky`，启动时间 17:24:44，晚于二进制构建时间 17:23:06。已通过可访问性树确认新进程就绪。未覆盖日常安装或发布。

窗口中的工具调用与最终文字来自确定性测试夹具，没有实际启动 Orca / Claude Code。截图用于验证呈现时机，不作为真实插件操作成功证据。日志位于 `/tmp/asky-complete-{core,debug-verified,release,preview,ui,forms}.log`。
