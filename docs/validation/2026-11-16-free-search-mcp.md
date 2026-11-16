# 免 Key 远程搜索与页面读取验收

日期：2026-11-16。此记录替代此前 Bing + Chrome 正文读取方案的当前实现说明；[上一轮记录](2026-11-16-search-and-chrome-reading.md)保留为历史证据。

## 选型与实际调用

查阅并调用现成工具，未安装依赖、启动浏览器或克隆项目：

- [Parallel Search MCP](https://github.com/parallel-web/search-mcp)：匿名 Streamable HTTP 接口，仓库为文档与客户端连接配置，服务运行在 Parallel。`initialize`、`tools/list`、`web_search`、`web_fetch` 均实测可用。
- [Exa MCP](https://github.com/exa-labs/exa-mcp-server)：MCP 服务代码开源；匿名托管接口实测搜索与正文读取可用。Slack 中文查询直接得到 Slack 中文官网介绍与中文百科内容。
- [Firecrawl MCP](https://github.com/firecrawl/firecrawl-mcp-server)：握手与工具列表正常，但本次搜索实际返回 `isError=true`、匿名访问不可用并要求 Key，未纳入实现。
- DDGS / 自托管 SearXNG 需要另装运行环境或部署服务，不符合本次无额外安装约束，未安装或接入。

托管服务的索引没有因 MCP 连接器开源而变成完整开源搜索引擎。匿名接口有限流及服务变更风险；当前实现没有付费凭据、OAuth、作者代理或自动付费路径，限流返回显式状态，不轮换身份绕过限制。

## 实现

- ToolService 下的 `web_search` 默认调用 Parallel，覆盖不足或错误时调用 Exa，最多两源。保留原查询和完整型号。
- 词法覆盖用于诊断与排序，不再作为删除语义搜索候选的硬条件；仍过滤违反 `site:` 范围和登录入口的候选。
- 每源返回状态、缺失词与失败记录；无结果、限流、服务不可用可区分。外层 `completed` 不代表有内容。
- `web_read_page` 通过远程工具读取单个公开 URL，保留截断标记，最多 24,000 字符。
- 删除 `chrome_read_page`、页面 JavaScript 和对应权限提示；保留 Chrome 列标签与切标签。
- 不引入 SwiftPM 依赖或本地后台服务；无浏览器、付费凭据、Cookie、额外组件下载或网页下载文件。

## 真实 ToolService 验收

运行：

```bash
ASKY_LIVE_WEB_SEARCH=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore --filter 'FreeWebSearchTests|WebSearchQualityTests'
ASKY_LIVE_WEB_X=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore
```

| 输入 | 实际结果 |
| --- | --- |
| Slack 是什么公司 | Parallel 单次返回相关来源，包括 Slack About Us；摘录约 1,800–3,500 字符 |
| Kimi K3.1 Pro 评测 SWE-bench | Parallel 单次返回 DataLearnerAI、302.AI、4sysops 评测页面；前三条摘录约 1,800–4,500 字符 |
| Gemini 4 Carbon 评测 开发者实测 | Parallel 单次返回中文开发案例实测等页面；前三条摘录约 3,500–5,100 字符 |
| 打工人三件套 | Parallel 单次返回凤凰网、华尔街见闻、虎嗅等来源；词语具体含义仍需按上下文判断 |
| https://slack.com/intl/zh-cn/about | Parallel 返回 3,099 字符正文，包含 Salesforce 收购信息，truncated=false |
| Gemini 4 Carbon site:x.com | 返回 5 条来源；随后读取 https://x.com/GoogleAI/status/2120187753329791341 得到 3,524 字符，包含实际帖子正文 |

四组中文查询在本轮均为 `matched`，只表示词法覆盖通过，不代表文章可信度、型号事实或评测结论已完成独立核实。X 只验证了一条公开帖子，不保证私密、登录受限、删除或所有其他帖子可读。

## 自动检查

- 最终完整 `swift test`：369 个 Swift Testing 测试、5 个 XCTest 测试通过。
- 覆盖匿名请求无凭据、SSE 与 JSON-RPC 错误、两种工具返回格式、中文近义表达保留、限流换源、空结果与网络失败区分、取消传播、网站范围、页面大小限制与 ToolService 来源开关。
- `plutil -lint`：两份 Core.strings 通过。
- `xcodegen generate` 与 Debug `xcodebuild` 通过；构建禁用自动包解析和包更新，使用已有本地依赖。
- `git diff --check` 通过。

日志：`/tmp/asky-free-search-live.log`、`/tmp/asky-free-search-full-final.log`、`/tmp/asky-free-search-verified.log`、`/tmp/asky-free-search-build-verified.log`。

本次交付为源码与本地 Debug 构建，尚未替换 `/Applications/Asky.app` 或验证安装版本中的模型自主调用；既有 Chrome 切换索引错误仍缺少原窗口复现。README 与隐私、工具说明已同步；无新运行时、独立子项目或权限边界变化，AGENTS.md 保持不变。
