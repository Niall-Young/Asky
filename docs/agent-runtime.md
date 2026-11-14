# Asky Swift Agent Runtime

更新日期：2026 年 11 月 14 日。当前实现已替换 Pi / TypeScript Agent 宿主，模型与工具编排在 Swift 中运行。验证范围见 [迁移记录](validation/2026-11-14-native-agent.md)。

## 架构与参考

Asky 保留 AgentHost 的任务事件和 ToolService 的原生权限边界。NativeRuntime 是进程内 Swift actor，不启动 Node、Pi 或其他模型辅助进程。既有 JSONL v2 事件在内存通道传递，用于沿用宿主生命周期和 UI；负数 runtime identity 只作实例标识，不是 OS PID，runningPID 为 nil。

参考 [Codex agent loop](https://openai.com/index/unrolling-the-codex-agent-loop/)、[Codex 上下文管理](https://github.com/openai/codex/blob/main/codex-rs/core/src/compact.rs) 和 [oh-my-pi agent loop](https://github.com/can1357/oh-my-pi/blob/main/packages/agent/src/agent-loop.ts) 的循环、事件、流式工具参数和恢复边界，自行实现 Asky 所需能力。没有引入这些项目的运行依赖，也不复制完整终端、IDE、LSP、自由 Shell 或多 Agent 系统。

| 能力 | 当前实现 |
| --- | --- |
| 模型 | Foundation URLSession，OpenAI-compatible Chat Completions，BYOK；文字、图像、流式工具参数；JSON 响应兼容 |
| 事件 | starting / running / compacting 与真实工具事件驱动活动状态；仅本轮完整结果发送 message，不向 UI 发送逐字 textDelta |
| 工具 | 当前允许目录的原生工具和已启用插件；调用全部交给 ToolService，未知工具不执行 |
| 原生交互 | ask_user 结束当前轮等待补充；asky-form 保持现有 SwiftUI 控件与逐行解析 |
| 上下文 | 动态时间、来源片段、Markdown 记忆、附件引用与插件指导；不发现全局 .pi、AGENTS、skills 或 shell 配置 |
| 会话 | ToolService 管理原生 JSON 快照，Pi 活动分支按需迁移，保留未完成工具的待核实结果 |
| 压缩 | 上下文序列化大小超过 180,000 字节后在用户轮边界总结旧轮，保留完整工具往返；字节预算不等于精确 token 计数 |
| 资源 | 只在提交 AI 请求时创建运行时；任务完成释放消息，默认空闲 60 秒销毁运行时；不做模型预热 |
| 插件 | API v2 本机可执行文件，无 Node；API v1 通过独立兼容脚本使用本机 Node，见[插件文档](plugins.md) |

## 模型与凭据

模型 Key 由主应用从 Keychain 取出，只保存在内存请求中，不写会话、配置、命令行或插件环境。使用 ephemeral URLSession，关闭缓存、Cookie 与凭据存储；拒绝 HTTP 重定向以免转发 Key。API 使用 HTTPS，回环本机调试端点可用 HTTP。

流式 SSE 按字节组帧，聚合碎片工具名、ID 和 JSON 参数；完整输出确认后才允许调用工具。模型输出与工具参数总量上限 1 MiB，单次最多 128 个调用；格式无效、输出中断、达到生成长度上限不报告成功。保留提供方返回的 reasoning_content 供工具续轮使用，不作为正文展示；DeepSeek 官方端点默认关闭 thinking，与旧运行时保持一致（[提供方协议](https://api-docs.deepseek.com/guides/thinking_mode/)）。单请求超时 120 秒；429、5xx 及未输出正文前的瞬时网络故障最多重试一次。工具不因模型网络重试而重新执行。

本轮工具调用最多 50 次，当前按顺序执行；ToolService 继续负责参数、权限、确认、去重、执行与回读。写工具的 userRequested 仅表示本轮明确意图，转发前剥离，不是用户批准。awaitingConfirmation、rejected、suggestion 和 pendingVerification 都不得当作成功。

## 会话、取消与恢复

运行时快照为 runtime/native-sessions/<sessionID>.json；SQLite 保存分页 UI 与检索投影及工具执行记录。每次模型完整消息和工具结果后原子保存快照。图片以引用落盘，仅在网络边界展开为 Base64；单张读取上限 20 MiB，文本附件最多读取 64 KiB，每轮最多 16 个附件。附件缺失会提供不可读取信息，不伪造图片内容。

旧 runtime/pi/sessions/ 日志只允许从应用自有目录读取，按最后活动叶节点的 parentId 链迁移，应用压缩摘要和保留边界，不合并废弃分支。原文件保留；同一会话后续优先读取原生快照。未知格式和越界路径显式失败。原生快照总量上限 32 MiB，文件权限 0600、目录 0700。

取消会停止网络请求和宿主管理的工具任务；已有写入或在途调用显示待核实，不承诺回滚。已记录调用缺少结果时，恢复只补入未知结果，绝不重放工具。隐藏窗口不取消任务。退出会等待取消任务完成后关闭通道，不保留模型子进程。

进入历史或设置、普通搜索、确定性提醒与外部 MCP 不启动模型。后台 AI 仍遵循现有显式授权，来源管理仍归原生系统。

## 完整回复中的原生表单（试用）

组件描述通过完整 `message` 返回，协议 v2 无新增事件。模型传输仍可使用 SSE，但前端不展示正文增量或工具前的说明。App 只在本轮结束后解析完整正文，`ChatFormParser` 按 JSON 行解析字段，`ChatReplyView` 将它们映射为固定的 SwiftUI 控件。模型不输出可执行 Swift 或 HTML；没有 WebView、脚本与任意系统动作入口。

回复中最多包含一个独立的 `asky-form` 围栏，第一行标题，此后每行一个字段：

````text
请补充会议信息：
```asky-form
{"title":"会议安排"}
{"id":"title","type":"text","label":"会议名称","required":true}
{"id":"duration","type":"radio","label":"时长","options":["30 分钟","60 分钟"],"required":true}
{"id":"topics","type":"multi","label":"议题","options":["设计","开发"]}
{"id":"day","type":"date","label":"日期","required":true}
{"id":"start","type":"time","label":"开始时间","components":["hour","minute","second"],"required":true}
{"id":"countdown","type":"duration","label":"倒计时","components":["minute","second"]}
```
````

`radio` 使用原生圆形单选按钮组，`select` 保留下拉单选，`multi` 为复选框多选。radio 初始不默认选中，不同字段的单选组互相隔离；与 select 共用选项和提交校验，只接受一个合法选项。模型按场景选控件：选项少、适合直接比较时优先 radio；选项多、文字长或需要节省空间时选择 select，用户明确指定时遵循用户要求。

标题最长 120 字；最多 16 个字段；字段 ID 非空、唯一且最长 64 字；标签最长 200 字；选择字段须有 1–20 个不重复且非空的选项，每项最长 200 字。围栏内容最多 32 KiB。`required` 缺省为 false；日期默认本地今天，以 `yyyy-MM-dd` 提交；`time` 为具体时刻，`duration` 为时长，两者复用创建日程的组件选择器。`components` 为 `["hour","minute","second"]` 的非空有序子集，可只显示需要的单位，禁止重复或逆序。time 缺省为时分且初值为当前本地时间；duration 缺省为分秒且初值为零。内部值按所选单位顺序以冒号分隔，每段两位；time 小时 00–23、分秒 00–59，duration 首段 00–99、后续段 00–59。默认时分回复仍为 `HH:mm`，完整时分秒为 `HH:mm:ss`；时长及省略单位的组合在用户回复中带明确单位，避免把分秒当作钟点。时间段仍可使用 `select`；文本答案最多 4000 字。未知类型、重复 ID 或不合规结构回退为普通代码。普通 Markdown 代码围栏内的示例不转换为表单。

生成过程中不显示正文或字段；本轮结束后将完整表单一次呈现并允许填写。停止或断开不展示未完成表单。提交会重新验证存储的表单和选项，再走普通用户消息提交路径，保留输入框草稿与待发送附件。操作仍经 ToolService 按现有授权、确认与执行规则处理。

原始回复及提交后的可读文字保存在既有会话记录中。旧表单在存在后续用户/助理消息后关闭，重开历史也不能重新提交。尚未提交的字段值仅驻留当前会话，切换/重开后不恢复；分页裁剪与新会话清理字段状态。提交按钮本身不直接执行系统操作，也不增加单独的模型请求来生成组件。实际首个字段延迟取决于模型首响应、输出顺序和传输速度；本地模拟流验证不等同于真实提供商速度验收。
