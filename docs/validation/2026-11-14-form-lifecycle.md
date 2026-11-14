# 原生表单刚生成即结束

## 根因与修复

每轮 finishTask 后的历史清理会回调 onConversationHistoryDeleted，即使 deletedIDs 为空。原回调无条件 resumeTimeline，清空当前 conversationID 与未提交字段；formIsActive 依赖当前 conversationID，导致完整表单立刻失效。

- 空删除回调不再刷新视图；删除其他记录不会重置正在查看的独立存储段。
- 时间线确需刷新时保留仍可见消息的未提交字段。
- ChatItem 保留实际所属的存储段，表单根据原消息归属检查存储，不依赖时间线中为空的当前 conversationID。
- 后续用户/助手消息仍会结束旧表单，已删除消息不可提交。

## 实际验证

- 旧 AgentModel 配合新增生命周期回归在 `cleanup must not expire a just-completed form` 断言失败，确认回归能捕获本次问题。
- `xcodegen generate` 与 README 的 Debug xcodebuild 命令通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：43 tests / 10 suites 通过。
- `ASKY_DERIVED_DATA=build/FormLifecycleDerivedData python3 App/Tests/run-agent-reply-regression.py --forms-preview --custom-preview` 通过：真实完成清理、字段保留、时间线重开、无关记录删除、后续输入与删除后拒绝提交；原生输入、预设与自填切换、提交后的草稿与附件保留、单次发送、历史恢复及防重复提交。
- 检查本次生成的深色原生窗口截图，表单字段正常显示并保留输入；回归同时生成浅色、深色与窄窗口截图。
- 初次旧版回归因编译期间源码被改写而中止；一次修复版回归因共享 Router.o 被其他构建改写而中止。最终使用独立产品副本完成上述验证。原生预览初始化也已适配 show() 恢复时间线的现有行为。
- 本地 Debug 应用已重启；未发布正式版。提交测试使用缺失凭据和本机不可用地址，没有验证真实模型返回后续回答。

## 维护

README: unchanged：恢复既有表单用法，没有新增配置或操作方式。AGENTS.md: unchanged：没有新的持久指令或模块边界。回归产物使用已有 build/ 忽略规则。
