# 原有工具样式与流式最终答复

日期：2026-11-14。用户明确修正：工具执行必须保留已有的对应样式，最终正文仍然流式输出。本记录取代同日“所有阶段统一活动行、结果一次出现”的展示方案。

## 实现

- 执行过程重新使用原有 ToolCallRow，保留 MingCute / 数据源图标、执行中、完成、失败、待核实和可展开错误详情；工具状态不再被通用 loading 替代。
- 运行中工具详情默认展开，并允许用户手动收起/展开；任务结束后沿用原有耗时和可展开工具历史。
- 仅在等待模型、没有活动工具且没有正文输出时显示思考。上下文整理与等待确认仍按真实状态显示。
- Runtime 恢复正文 textDelta；最终完整 message 校准内容，结束后只持久化一次最终答复。进入 toolCall 时将上一轮已显示说明转入工具过程记录，保留内容且不把多轮说明拼到最终正文上。
- 最终正文边接收边使用原有 Markdown 样式排版，生成时没有重复 loading。原生表单维持完整后出现，避免输出中暴露半段 JSON 或不完整字段。

## 验证结果

- KulaCore 全套测试：331 项通过，包括增量正文、单个最终 message、多轮工具、真实 HTTP SSE 与连接保持、取消、恢复和压缩。
- `xcodegen generate`、Debug / Release 构建通过；两份应用的 `codesign --verify --deep --strict --verbose=2` 通过。
- 共享工作区两次发生并行修改干扰：一次 Router.o、一遍回归测试源文件在编译期间被其他任务改写。随后复制实际 App 源码与 Debug 模块/资源到 `build/ToolReplyVerification/` 独立快照执行回归，避免交叉写入。当前 AgentModel、AgentView、ChatFormView 已与验证快照逐字比对一致。
- 独立窗口回归通过：工具前的临时文字清空，工具行展示实际执行状态，流式最终回答在完成之前可见，历史最终只保存一条回答。
- 已查看原生窗口截图：Orca 完成图标与 Web Search 执行中状态同时显示；Web Search 失败使用原来的警告与详情入口；最终标题与部分列表在任务仍执行时已显示。
- 普通 AgentReplyRegression 通过：聊天历史、澄清、取消、耗时、附件、新对话。原生表单单选回归通过：完整后显示、原生输入、明暗/窄屏、历史与重复提交防护。
- 本次 UI 夹具的 ChatResponseGroup 补入实际 streaming 字段，确保“正文输出期间不显示重复 loading”的断言与真实 Transcript 传值一致。
- `python3 App/Tests/check-localization.py`：166 个 Swift 源文件通过；中英文本与格式参数一致。`git diff --check` 通过。
- 当前运行的 Debug PID 83603，路径 `build/DerivedData/Build/Products/Debug/Asky.app/Contents/MacOS/Asky`，启动于 17:36:12，晚于二进制更新时间 17:33:46。未替换日常安装或发布。

可查看 `build/tool-replies-progress.png`、`build/tool-replies-streaming.png`、`build/tool-replies-completed.png`。窗口工具事件与文字为测试夹具，没有实际启动 Orca 或 Claude Code。日志位于 `/tmp/asky-tool-reply-{core,debug,release,isolated-final,ui,forms}.log`。


## 工具前说明消失的修复

用户随后指出“先说一句，然后消失再调用工具”。原因是前端在 toolCall 时直接清空已经显示的正文缓冲。现在先将其保存为 tool_narration，再重置下一轮缓冲；工具过程按原顺序显示说明和工具行，任务结束后统一收起。说明不是最终 assistant 回复，也不进入 dialogueOnly 的记忆提炼查询。

- 新增碎片 textDelta → toolCall 回归，另一路覆盖完整 message → toolCall：两种情况均保留原说明，且只出现一次。
- 历史重开验证说明与工具步骤保留，最终仍只有一条 assistant 答复；dialogueOnly 明确排除过程说明。
- 已查看调用前、调用中及最终流式答复的原生窗口截图：同一句“先查看项目。”在工具启动后仍保留，不会被删除；工具图标、状态与错误详情不变。
- Debug / Release 构建和签名检查通过；KulaCore 331 项通过。独立 UI 快照的聊天、历史、澄清、取消、耗时、附件、新对话和原生表单回归全部通过。
- 当前 AgentView 与快照的差异仅为并行顶栏改动；ChatResponseGroup / ResponseGroupView / ChatBubble 与 ToolCallRow 均已逐字比对一致。AgentModel 与 ChatFormView 也一致。
- 当前 Debug PID 89066，启动时间 17:48:54，晚于二进制更新时间 17:48:37。应用路径仍为 build/DerivedData/Build/Products/Debug/Asky.app。

新增截图：build/tool-narration-before-tool.png、build/tool-narration-tool.png、build/tool-narration-streaming-result.png。日志：/tmp/asky-narration-{core,debug-final,release,ui-verified,ui-default,ui-forms}.log。窗口使用确定性事件夹具，未真实执行 Orca / Claude Code 操作。
