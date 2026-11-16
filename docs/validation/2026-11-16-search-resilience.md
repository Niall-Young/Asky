# Parallel 故障诊断与免费备用链路

日期：2026-11-16。任务：调查历史 Parallel 失败，参考开源项目的免费备用机制改善 Asky。

## 诊断结论

- 已核对[上一轮用量记录](2026-11-16-search-usage-workflows.md)与对应原生会话快照的工具参数。六次历史失败只保存了 `Invalid or failed MCP response`，没有原始响应，无法恢复当时的具体原因。
- 使用原查询/URL 回放两次搜索和四次页面读取，本次全部 HTTP 200 且返回正常 MCP 结果；另一次中文 Parallel 查询也成功。没有复现历史故障，不能断言它由限流、服务端错误或解析不兼容中的某一种引起。
- 确认本地诊断缺陷：旧 `decode` 把 JSON-RPC 错误与缺少匹配响应合并；HTTP 非 2xx 只保留状态码；工具层拿不到失败发生在哪一步。
- 确认另一处传输缺陷：旧实现先等事件流 EOF，再解析结果。通过不关闭的 SSE 响应夹具验证，新实现收到匹配结果即可完成，不会等到网络超时。这是已验证的代码修复，但没有证据证明它就是历史六次失败的原因。
- 新实现保留错误阶段、HTTP 状态、JSON-RPC 错误码、Retry-After 和可取得的请求 ID；兼容数字/字符串 ID、无 ID 的 RPC 错误、JSON 批次和多行 SSE，仍拒绝其他请求 ID 的成功结果。
- MCP 初始化使用服务端协商的受支持协议版本；结构化工具结果优先，文本块逐个查找 JSON，不再把说明文字和 JSON 拼接后一起解析。

## 新来源实测与取舍

参考实现（本次读取源码，Asky 以 Swift 独立实现，未引入它们的运行环境）：

- [Oh My Pi Parallel 适配器](https://github.com/can1357/oh-my-pi/blob/main/packages/coding-agent/src/web/search/providers/parallel.ts)：匿名 MCP 与错误保留。
- [OpenClaw Parallel 免费适配器](https://github.com/openclaw/openclaw/blob/main/extensions/parallel/src/parallel-free-web-search-provider.runtime.ts)：协议协商、SSE 与错误解析。
- [Hermes 免费来源轮换](https://github.com/NousResearch/hermes-agent/blob/main/plugins/web/keyless_mcp.py)与[请求缓存](https://github.com/NousResearch/hermes-agent/blob/main/tools/web_result_cache.py)：多来源、合并重复请求和缓存的参考。
- [Keenable 官方接入说明](https://docs.keenable.ai/)：公开 search/fetch 端点与 `X-Keenable-Title` 应用标识。

Keenable 无 Key 搜索成功，中文 Slack 官网正文读取成功，约 2,059 字符。采用其公开 HTTP 接口，仅发送 `X-Keenable-Title: Asky`，不发送认证信息。

Firecrawl `/v2/search` 匿名实测返回 HTTP 403，明确表示当前 IP 被识别为 VPN/代理，拒绝无 Key 访问。没有更换网络身份、注册账号或改用付费入口；本次不把它加入运行时来源。

## 实现行为

- Parallel 保持主用，Exa / Keenable 轮换备用起点；失败或结果覆盖不完整时继续，每源每次最多一次，不重复改写查询。
- 限流默认退避 60 秒，401/402/403 默认 10 分钟，其他服务错误默认 15 秒；有 Retry-After 时优先遵守。明确的页面内容错误不暂停整个来源。
- 跳过退避来源时记录 `skipped=true`，不发网络请求。所有来源不可用就返回原因，不转付费。
- 搜索与页面共用有界内存缓存：10 分钟、最多 32 项、序列化内容及键总计最多 2 MiB。没有磁盘缓存，过期自动清理；该限制不代表整个应用或 Swift 对象的实际内存占用。
- 相同并发请求合并。取消一个等待者不影响其他人，最后一个等待者取消时终止底层任务，旧任务完成不会覆盖同键的新任务。
- 仅缓存成功结果，保留原始 `retrievedAt`。缓存命中 / 请求合并时 `attempts=[]`，历史尝试在 `sourceAttempts`；不可把历史尝试重新计为远程调用。
- 原有网络权限、ToolService 入口、URL 约束、无 Cookie/凭据/重定向、响应大小限制保持；未增加依赖、浏览器、辅助进程或后台网络轮询。

## 验证

### 全包回归与 App 构建

以下命令实际执行成功：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build
```

- Swift Testing：378 项通过；另有 5 项 XCTest 通过。默认不执行联网测试体，联网另行开启验证。
- 新增 9 项韧性测试（含 1 项显式启用的联网测试）：HTTP / RPC 错误保留、保持开启的 SSE、Retry-After、备用轮换与退避、缓存过期和淘汰、失败不缓存、并发合并、独立取消、取消底层任务后重试、匿名请求结构。
- Debug 构建与 `codesign --verify --deep --strict` 签名检查成功；本轮没有重启用户当前运行的应用，也没有替换 `/Applications` 安装版。

### 真实 ToolService 联网

```bash
ASKY_LIVE_WEB_SEARCH=1 ASKY_LIVE_WEB_KEENABLE=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore --skip-build --filter FreeWeb
```

19 项通过，约 11.3 秒。两组联网测试使用独立协调器，正常链路调用真实 Parallel；备用组仅注入 Parallel / Exa 不可用，Keenable 是真实远程请求，不把模拟故障算作实际服务失败。

| 查询 | 正常链路 | 强制备用组 |
| --- | --- | --- |
| Slack 是什么公司 | Parallel matched，单源完成 | Keenable matched，5 条 |
| Kimi K3.1 Pro 评测 SWE-bench | Parallel matched，单源完成 | Keenable partial，5 条 |
| Gemini 4 Carbon 评测 开发者实测 | Parallel matched，单源完成 | Keenable matched，5 条 |
| 打工人三件套 | Parallel matched，单源完成 | Keenable matched，5 条 |
| Slack 中文官网正文 | Parallel read，约 3,099 字符 | Keenable read，约 2,059 字符 |
| 再读相同网页 | — | cached=true，attempts=[] |

结果链接与正文已返回；matched / partial 只是现有覆盖诊断，不代表已核查来源每个事实。Keenable 的新模型检索仍有覆盖缺口，不将它描述为优于 Parallel。新来源的长期稳定性、所有网络出口、每天额度和生产规模均未验证。

本机测试日志：`/tmp/asky-core-resilience-full.log`、`/tmp/asky-search-final-live.log`、`/tmp/asky-search-build.log`。记录不包含模型密钥或完整私人对话。旧会话快照与交接记录均未修改。

README 中英文能力、工具说明与隐私政策已同步；相对文档链接及 `git diff --check` 通过。构建产物沿用已有忽略规则，未新增依赖或修改 AGENTS.md。
