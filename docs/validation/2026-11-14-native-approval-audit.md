# 内置工具重复审批检查

## 检查结论与修复

「自动审批」读取工具声明的固定确认规则，没有额外模型审批调用。「完全访问」在 ToolService 中跳过应用内 Agent 的建议与审批步骤；系统权限、来源范围、目标与参数校验仍执行，Launcher 和外部 MCP 不继承该豁免。

| 操作 | 自动审批下的明确用户请求 | 本次处理 |
| --- | --- | --- |
| 搜索、查询与读取 | 授权范围内直接执行 | 检查注册定义，无需修改 |
| 新建备忘录、日程、提醒事项 | 参数与目标校验后直接执行 | 原本已支持，加入回归矩阵 |
| 追加备忘录 | 校验后直接执行 | 从 `.always` 改为 `.explicitDirectOtherwiseConfirm` |
| 修改单个日程 | 校验后直接执行，重复日程只改本次 | 从 `.always` 改为 `.explicitDirectOtherwiseConfirm` |
| 短信草稿 | 直接打开草稿，人工发送 | 上轮已修复，本轮纳入矩阵 |
| 切换 Chrome 标签页 | 直接执行 | 原本已支持，加入回归矩阵 |
| 保存、纠正、忘记个人记忆 | 明确请求直接执行 | 原本已支持，沿用现有 MemoryToolsTests |
| 删除日程、运行快捷指令 | 原生确认 | 保留现有风险规则，验证完全访问会跳过应用内确认 |
| 外部 MCP 写入 | 原生确认 | 完全访问也不跳过，加入矩阵 |

当前 Agent 注册的提醒事项工具为查询与新建；未发现已注册的提醒事项修改、完成或删除工具，本次未扩展其功能。插件遵循各自声明的确认规则，本次未改变插件策略。

同步中英文工具描述与模型提示词，明确日常操作参数充分时直接提交，避免工具规则已放行、模型仍先出表单重复询问。备忘录目标范围、锁定状态、日程可写性和执行后回读逻辑保持不变；AI 自行推导的操作在自动审批模式下仍先返回建议。

## 已执行检查

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：13 个目标共 359 个 Swift Testing 测试通过。
- 新增 `NativeApprovalAuditTests`：6 个测试、30 个参数场景通过，覆盖 7 类直接操作、2 类保留确认操作、9 类完全访问操作、8 类外部写入，以及建议请求和禁用来源。
- `plutil -lint`：两种语言的 `Core.strings` 通过。
- `xcodegen generate` 和 Debug 构建通过。为避免并行任务争用构建目录，执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/ApprovalDerivedData -clonedSourcePackagesDirPath build/DerivedData/SourcePackages -disableAutomaticPackageResolution build`；产物为 `build/ApprovalDerivedData/Build/Products/Debug/Asky.app`，沿用既有 `build/` 忽略规则。
- `git diff --check`：通过。

新测试使用真实注册的工具定义进入 ToolService，系统执行由计数探针替代，没有读写实际备忘录、日程、提醒事项或发送短信。首次并行测试在 EventKit 授权查询中等待，已终止本次测试进程；改为共享一次工具定义并串行运行后，上述完整测试通过。

## 验证范围与文档维护

没有使用真实模型或原生界面重走这些操作，也未重启当前运行的 Asky。新构建需启动后才载入修复。工作区的其他并行修改不纳入本次提交；本次构建与全量测试基于执行时的完整工作区，不代表其他功能均已验收。

README: updated — 中英文同步日常操作与两种审批模式的实际行为。

AGENTS.md: unchanged — 仍由 ToolService 管理权限与确认，没有新增开发入口或模块边界。
