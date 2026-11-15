# 联网搜索跑题检测与补搜

## 故障证据

原生会话文件实际保存了 `web_search` 的完整参数和返回值。最初仅查 SQLite 执行表而判断没有原始结果是不完整的排查，已纠正。原查询中的 Carbon 没有被截断，生成的 Bing URL 也包含完整查询；但 `Introducing Gemini 4 Carbon blog.google October 28 2026` 返回 Introducing 词典页，`Google Gemini 4 Argon Carbon 旗舰模型 对比` 返回 Google 门户页。独立使用相同 URLSession 配置重放已复现；短查询 `Gemini 4 Carbon` 则返回官方来源。没有证据能断言 Bing 内部为何忽略其余词。

## 实现

- 先检查最多 10 条候选的关键词覆盖，再过滤、排序并应用调用方的数量上限；不再拿前几条跑题页面直接交付。
- 首轮缺少主题内容时，最多补搜两次，使用被忽略的词和上下文词缩短查询；不针对 Carbon、Google 或任何产品写特判。
- 过滤没有补齐首轮遗漏主题词的门户页；优先排列覆盖遗漏词和更多原查询词的结果。
- 保留原查询、每轮实际查询、搜索 URL、候选数量、缺失词、请求错误。`quality` 明确区分关键词已覆盖、部分覆盖、无足够相关结果，不能把这些状态解释成事实真伪。
- 保留显式站点限定并校验域名边界；否定/布尔查询不自动简化。编码保留 `C++` 等查询中的字面加号。
- 单请求 10 秒 / 1 MiB，最多 3 请求，ToolService 整体 35 秒；取消继续上抛，页面损坏/验证码等错误不改为空搜索。仍只有 Bing 搜索摘要，没有多引擎或全文读取能力。

## 实际验证

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：退出码 0，13 个 Swift Testing 汇总共 369 项通过；XCTest 的 2 项 ChatLinkService 和 3 项 AgentReaction 测试也通过。默认真实联网入口因环境变量未启用而跳过，不算联网证据。
- `ASKY_LIVE_WEB_SEARCH=1 ASKY_LIVE_WEB_SEARCH_RECOVERY=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --skip-build --filter WebSearch`：14 项通过。通过实际 ToolService 调用 Bing 重放 8 条原始查询，8/8 均返回 Carbon 的 Google 官方来源；Swift Apple documentation 对照查询返回 5 条结果。
- 最后一次联网回归：前 5 条原查询和 Introducing 查询均用 2 次请求；型号 ID / 1M 查询和中文年月查询用了 3 次。型号 ID / 1M 查询标记 `partial`，其余最终标记 `matched`。这些仅为关键词覆盖状态，未据此确认 1M 或发布时间等事实。
- 确定性回归覆盖：跑题后恢复、始终跑题时空结果、先过滤再限数量、站点与伪造子域名、取消、损坏页面、编码/运算符、中文及型号分词。
- `xcodegen generate` 和 README 的 Debug `xcodebuild` 命令：退出码 0，`BUILD SUCCEEDED`。
- 中英文 Core.strings 的 `plutil -lint`、`git diff --check`：通过。README 中英文同步搜索补救行为。

## 安装与边界

已完整替换 `/Applications/Asky.app` 并启动。直接合并旧包曾因残余资源导致签名检查失败，随后改为全新暂存包验证后替换；最终 `codesign --verify --deep --strict` 通过，Developer ID Team 为 `V8GVW783CK`。安装后二进制与本次 Debug 构建 SHA-256 一致：`bda4bfe18e39545c73bcf70f5df69c3f83e244038a093536612829df97035aec`。确认运行进程来自 `/Applications/Asky.app/Contents/MacOS/Asky`。旧安装包备份位于 `/tmp/asky-before-search-fix-*.app`。

没有调用用户配置的模型做原生对话端到端验收；实际联网验收覆盖 ToolService → WebSearchTool → Bing → 结果处理链。相关性检查是分词与关键词覆盖启发式，不能保证所有语言、别名或语义查询均正确；来源内容仍需模型核实。无 GitHub 发布、推送或版本号改动。

测试/构建日志：`/tmp/asky-search-all-tests.log`、`/tmp/asky-search-live-final.log`、`/tmp/asky-search-build.log`。构建缓存使用既有 `build/` 和 `Packages/KulaCore/.build/` 忽略规则，无新增忽略规则。
