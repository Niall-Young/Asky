# 日常对话与资料型文章的搜索用量实测

日期：2026-11-16；目标是测量真实任务的调用量，不探测或承诺供应商的每日额度。

## 环境与方法

- 使用已运行的 `build/DerivedData/Build/Products/Debug/Asky.app`，进程 PID 93718，未修改或重新构建应用。
- 当前配置：原厂 `https://api.deepseek.com`，`deepseek-flash`；使用应用已有认证，未导出密钥或更改模型配置。
- 通过原生应用 UI 提交文章与两次追问，由真实模型自主决定搜索、读取与停止时机；不是预先编排工具次数的脚本。
- 沿用应用的连续对话上下文。日常查询样本取自用户此前在同一 Debug 版完成的实际对话，不重新请求。
- 依据 ToolService 保存的 `runtime/native-sessions/*.json` 中的 `tool_calls`、配对工具结果及 `attempts` 计数；确认最终 UI 已结束生成。
- 全程匿名 Parallel / Exa 搜索，不接入付费搜索凭据、浏览器页面读取或新依赖。文章仅在 Asky 对话中生成，未创建、修改或发送飞书文档。
- UI 首次按应用名连接时启动了旧安装版；发现后退出本轮启动的旧进程，再按 Debug 完整路径连接。所有测试消息均在确认 Debug 路径后提交。

## 计数口径

1. **工具调用**：模型调用一次 `web_search` 或 `web_read_page`。
2. **供应商尝试**：工具结果 `attempts` 的一条记录。同一次工具调用可能先尝试 Parallel，再尝试 Exa。
3. **成功结果**：搜索返回 `matched` 或正文返回 `read`。`matched` 是词法覆盖状态，不是内容真实性保证。

供应商尝试不等同于计费调用：初始化或响应解析失败也可能产生一条失败记录，现有日志无法断定失败发生在握手还是实际 `tools/call` 阶段。HTTP 握手请求也不应直接换算为搜索额度。

## 结果

| 场景 | 搜索 | 读取正文 | 供应商尝试 | Parallel 成功 / 失败 | Exa 成功 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 用户此前查询腾讯 HY4 | 2 | 0 | 2 | 2 / 0 | 0 |
| 用户此前查询 Gemini Carbon 的 X 评价 | 2 | 0 | 4 | 0 / 2 | 2 |
| 本轮三家免费搜索方案文章初稿 | 3 | 10 | 19 | 7 / 6 | 6 |
| 追问：压缩并突出作者不承担账单 | 0 | 0 | 0 | 0 / 0 | 0 |
| 追问：纠正匿名直连与作者账单关系 | 0 | 0 | 0 | 0 / 0 | 0 |

文章三个回合合计 13 次联网工具调用、19 次供应商尝试，Exa 实际返回了 6 次成功结果。不是“每轮聊天固定消耗额度”，也不是“每篇文章保证只用 13 次”。

### 实际文章任务

初始提示：

> 帮我查一下 Parallel、Exa 和 Firecrawl 的免费联网搜索方案，写一篇适合放到飞书的约 1200 字中文文章，面向不懂开发的开源应用作者。讲清楚免费额度、超额会不会扣钱、是否需要安装额外程序，以及怎样选。用当前官方资料核实，附来源链接，查不到的额度别编。只在对话里输出文章草稿，不创建或发送飞书文档，不打开浏览器，不安装或下载软件。

三次搜索依次查询 Parallel、Exa、Firecrawl 的价格和免费额度。随后实际读取：

| URL | Parallel | 后备结果 |
| --- | --- | --- |
| `https://parallel.ai/pricing` | read | 未调用 |
| `https://www.firecrawl.dev/pricing` | read | 未调用 |
| `https://exa.ai/docs/admin/billing` | read | 未调用 |
| `https://exa.ai/pricing` | unavailable | Exa read |
| `https://parallel.ai/mcp` | unavailable | Exa read |
| `https://docs.firecrawl.dev/mcp-server` | read | 未调用 |
| `https://docs.firecrawl.dev/mcp-server/keyless` | read | 未调用 |
| `https://docs.firecrawl.dev/rate-limits` | unavailable | Exa read |
| `https://exa.ai/auth.md` | read | 未调用 |
| `https://parallel.ai/blog/free-tier-parallel` | unavailable | Exa read |

文章三次搜索中，前两次由 Exa 后备完成，第三次由 Parallel 完成。

追问一要求压缩到约 600 字、自然口吻、保留来源并区分匿名与注册额度；追问二指出匿名直连不会产生作者账单，要求按此前提修订。两轮都正常完成，未调用任何联网工具。

## 暴露的问题与验证边界

- 六次 Parallel 失败都被记录为 `Invalid or failed MCP response`，随后其他 Parallel 请求仍成功。现有证据不能把这些失败归因于每日额度耗尽，也不能排除短时限流。当前解码器会把 JSON-RPC 错误和未找到匹配响应合并成通用错误，具体原因尚未定位。
- 额外做了一次匿名 `initialize` 诊断，返回 HTTP 200 和合法协议响应。它不是搜索请求，未计入文章任务，也不能证明搜索额度充足。
- 两条日常查询和一篇文章是小样本。不能据此计算 Parallel 的每日限额、所有用户的平均量、成功率或同 IP 用户的可用量。
- 原先“复杂任务 5～10 次”的估算低于本次资料核实型文章的实测。此例可作为容量样本：初稿 13 次工具调用，换源后 19 次尝试；不能直接设置为所有文章的硬性上限。
- 改写复用了已有内容，未重复联网；但第一轮压缩错误地声称客户端使用公共匿名 endpoint 就会让作者承担账单。明确纠正后，模型区分了匿名直连与作者付费 Key。检索成功与文章事实正确必须分别验收，当前草稿不视为全面事实审核通过。
- Gemini 的历史样本是调用计数证据，不表示已验证 X 原帖或模型对二手材料的推断。
- 只测了资料检索和生成飞书格式文章草稿；未测飞书插件创建、排版或发布。文档写入调用不计入搜索次数，但真实写作流程是否额外查资料仍需按任务观察。
- 本次未直接调用 Firecrawl，因此其文档中声明的匿名可用性不能当作本机实测结果。此前记录已有一次匿名搜索失败，见[免 Key 搜索验收](2026-11-16-free-search-mcp.md)。

本机证据快照位于 `~/Library/Application Support/KulaHere/runtime/native-sessions/`：初稿 `26197A03-CFE9-4082-A77C-AEC8B2999C40.json`，压缩 `88C79127-8B9A-4AD9-AE21-85230FA79086.json`，纠正 `7FBDCAEA-C07E-465F-9DB2-D1937C9F7D21.json`。未把含个人上下文的完整会话提交进仓库。

## 检查与交付

- 已完成：实际 Debug 应用 UI 三轮任务、ToolService 会话结果计数、最终草稿状态核验。
- 五份会话的工具数、供应商尝试数与 Exa 次数已用只读脚本逐项断言核对；记录中的相对链接与 `git diff --check` 检查通过。
- 本轮仅增加验证记录，无 Swift、App、接口或依赖改动；未重新运行 Swift 测试或构建。
- README 与 AGENTS.md 保持不变：未改变能力、使用方式、开发命令或项目边界。记录中发现的问题不宣称已修复。
