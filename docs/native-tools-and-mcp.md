# Asky 原生工具与 MCP 设计

更新日期：2026 年 10 月 9 日。状态：接口设计；系统适配器与签名下的权限行为待 M0 验证。

Launcher、Agent 与外部 MCP 共用 Swift ToolService。工具实现和权限策略只有一个归属主体：原生应用。内置模型工具和协议客户端不能绕过该服务。用户安装的可信插件经该服务的宿主接口执行，但第三方代码不受系统沙箱隔离，详见[插件指南](plugins.md)。产品允许的操作以 [PRD](PRD.md) 为准。

## 调用路径

- Launcher 的确定性动作在应用内直接调用原生能力，不需要模型或 MCP。
- Pi 的工具调用通过受控宿主连接转交 ToolService，不直接执行 EventKit、AppleScript 或数据库读取。
- 外部 MCP 使用独立 Swift stdio Bridge，通过仅属主可访问的 Unix domain socket 连接运行中的应用（自用构建以 ad-hoc 签名，XPC 签名约束不可用；正式签名后可重新评估 XPC）；Bridge 不自行申请或持有系统数据访问权。
- 应用未运行时 MCP 返回可恢复的不可用状态；不会为了外部 MCP 启动 Pi，也不把 Bridge 变成 Launcher 的启动依赖。

本地连接隔离、实例凭据、签名与系统授权归属需要在真实构建中验证。独立协议入口不表示可以脱离原生权限主体运行。整体边界见 [框架](framework.md)。

## 工具接口契约

以下是实现必须覆盖的概念字段，不代表已经冻结的 Swift 类型或协议 JSON。

| 契约 | 必需内容 | 执行约束 |
| --- | --- | --- |
| ToolDefinition | 名称、描述、输入定义、数据源、读写效果、确认要求 | 同一登记驱动内部调用、允许列表和 MCP 暴露 |
| ActionRequest | 请求标识、工具、参数、任务关联、来源与用户意图 | 来源不能靠客户端自报名称获得权限；不能包含可信“已批准”声明 |
| ConfirmationRequest | 请求标识、目标、具体变更、必要说明 | 由原生层生成；确认仅对当前参数与目标有效 |
| ExecutionResult | 完成、拒绝、取消、失败或结果待核实；目标引用、实际结果 | 写入后回读；模型文本中的“成功”不能替代执行证据 |

具体参数 schema、工具名、版本、日期时间编码与错误码需在适配器验证后形成实现契约；首版应统一时区、重复事件、目标引用和不存在目标的语义，不能由每个入口自行解释。

## 系统适配器

日程、提醒事项、备忘录、通讯录和短信仅使用苹果官方应用及系统接口。日历工具返回 `application`（Apple Calendar）、实际日历名称、日历 ID 与账户；日历名称不能当作应用名称。创建确认与最终结果应明确「苹果日历」及实际所属日历。

| 能力 | 首选机制 | 范围与失败处理 |
| --- | --- | --- |
| 应用 | NSWorkspace | 名称与别名搜索、启动、切换；处理卸载或目标失效 |
| 文件 | Spotlight 元数据查询 | 首版文件名与路径，不建设全盘内容索引；范围受用户与系统权限限制 |
| Chrome | Chrome Apple Events 对象 | 普通窗口的标签标题、URL、窗口和标签标识；Agent 可通过固定只读脚本读取指定页面已加载文字，排除无痕、不采集历史、不开放任意 JS |
| 计算、单位与汇率 | 本地受限解析、参考汇率缓存 | 不执行输入代码；ECB 日参考汇率显示日期，网络失败显示缓存或不可用 |
| 显式终端 | 用户提交的原生子进程 | 工作目录、stdout/stderr、取消、退出码；大输出落盘，交互命令交给终端 |
| Shortcuts | 系统快捷指令接口 | 参数、开始与结束状态；取消和错误如实反馈 |
| 剪贴板 | NSPasteboard | 文字与图片、敏感标记、排除、暂停；粘贴另行授权 |
| 日历、提醒事项 | EventKit | 查询和 PRD 允许的写入；处理只读目标、冲突、重复事件、时区与撤权 |
| 联系人 | Contacts | 姓名、已确认关系与联系方式；同名、多号码请求选择 |
| Notes | Notes Apple Events 对象 | 只在授权账户与文件夹搜索、读、新建和追加；无锁定内容、附件编辑或删除 |
| Messages | 本机信息数据库只读查询、草稿交接 | `messages_search` 按关键词及日期查询设置所选的最近 3/7/30 天（默认 3 天），需 AI 短信读取开关与完全磁盘访问；过滤验证码、遮盖长数字，不向外部 MCP 开放。草稿验证收件人，最终人工发送 |
| 截图 | ScreenCaptureKit | 用户主动选择，单任务输入；取消、授权与临时清理 |
| 地点与路线 | MapKit | `maps_search_places` 搜索地点候选；`maps_routes` 比较明确起终点的驾车、公交、步行耗时；由 `.maps` 开关控制，仅对内置 Agent 开放，无需 API Key |
| 通知 | UserNotifications | 无声交付、计划标识、去重、取消、时区与恢复校验 |

MapKit 对话工具通过 ToolService 注册与鉴权，关闭“路线时间（MapKit）”后从 Agent 工具目录移除并拒绝新请求；它与网页搜索开关独立。地图查询会发送必要地点，不主动获取当前位置。`maps_search_places(query, limit?)` 最多返回 5 个带名称、地址和经纬度的候选；Agent 必须处理地点歧义。`maps_routes(origin, destination, modes?, departureTime?, arrivalTime?, bufferMinutes?)` 接受搜索得到的明确坐标，默认比较三种方式，默认到场缓冲 10 分钟。出发时间与到达时间互斥；到达时间减缓冲后传给 MapKit，并在该时间基础上倒推出建议出发时间。失败方式单独返回，全部失败则报错，不伪造耗时。单个 MapKit 请求 20 秒超时，可取消；路线工具整体上限 65 秒。

全天日程规划由 Agent 查询日历后逐段组合，考虑前一场结束时间、交通偏好及车辆位置，不自动修改日程。未指定方式时比较三种交通方式；步行时间合理、公交可按时到达且耗时相近时优先考虑，不能按工具结果顺序或仅按最短耗时推荐。机动车方案默认优先考虑打车，作为正常候选；只有用户明确选择自驾且车辆可用时才规划自驾，并考虑停车、找车位和停车后的步行。`driving` 是道路行驶耗时，不能直接视作自驾意图或打车总耗时；打车不产生自有车辆遗留约束，未知等车时间需单独说明，不能编造。公交查询失败不等于当地没有公交。公交当前仅提供 ETA，不声称线路、换乘或班次；驾车不包含等车、停车成本。临近出发需刷新。此改动不把未经确认的地址或当前位置接入后台提醒；后台缺少路线依据时仍只建议检查路线。

既有静态脚本定义检查记录包含 Notes 的正文与文件夹、Chrome 的标签页与窗口，以及 Messages 的发送命令；Messages 的该定义没有完整消息历史读取对象。静态定义只表明接口入口，不代表运行操作已验证。尤其 Notes、Chrome 与 Messages 应核实授权账户、目标状态、系统版本和真实执行结果。聊天查询通过原生 ToolService 适配器只读访问本机 `chat.db`，不使用 Apple Events 读取历史，不调用发送命令。每次最多返回 50 条、扫描 10,000 条，结果标明查询范围及是否仍有候选；只能据实际成功结果回答，不能把权限失败解释成没有短信。原有后台短信授权开关沿用，同时允许聊天查询；无需开启后台 AI，关闭读取开关会立即拒绝新的查询。

官方依据：[EventKit](https://developer.apple.com/documentation/eventkit)、[Contacts 授权](https://developer.apple.com/documentation/contacts/accessing-the-contact-store)、[Apple Events 用途声明](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)、[ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)、[MapKit](https://developer.apple.com/documentation/mapkit)、[本地通知](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)。

## 权限与确认策略

系统权限、应用来源授权、允许 AI 使用、允许提炼、后台提醒以及外部 MCP 范围分别控制。系统授权通过不等于可以把该来源全部发给模型。

下表描述默认「自动审批」模式，按工具声明的固定规则执行，不另外调用模型审批。「完全访问」跳过应用内 Agent 的建议与审批步骤，但仍执行来源授权、参数校验及回读；不影响 Launcher 或外部 MCP 的确认规则。

| 请求与操作 | 处理 |
| --- | --- |
| 应用内读取 | 校验启用来源和读取范围后执行 |
| 用户明确要求新建日程、提醒、备忘录 | 参数充分、目标可写、无未解决冲突时执行并回读 |
| 用户明确要求追加备忘录、修改单个日程 | 校验目标与参数后执行并回读，不重复弹出执行确认 |
| 删除日程、批量变更或运行快捷指令 | 展示目标和变更，再取得原生确认 |
| AI 推导出的新增系统写入 | 先展示建议，不能把模型建议当用户已要求 |
| 外部 MCP 读取 | 校验接入实例、凭据和分配范围 |
| 用户主动安装的插件 | 按插件声明确认；explicitDirectOtherwiseConfirm 允许明确用户请求直接执行，AI 推断的写操作先展示建议；插件工具不向外部 MCP 暴露 |
| 外部 MCP 写入 | 始终原生确认；内部新建规则不能用于外部调用 |
| Messages 交接 | 明确用户请求在验证收件人与正文后直接打开草稿，不重复确认；AI 自行提议保留为建议，外部调用需要原生确认；发送仍由用户在 Messages 完成 |
| AI 提议终端命令 | 展示命令与工作目录，获得该具体操作授权；不能借显式命令通道绕过 |

拒绝授权只关闭对应能力，不能循环弹窗。撤销权限、禁用来源或撤销 MCP 实例后，停止后续读取、清理待处理请求，并使未使用确认失效。外部内容作为数据，不能提高权限、改变允许列表或申请额外来源。

## 执行一致性

工具执行记录持久化请求标识、参数摘要、目标与状态，不依靠模型对话防重。写入串行；冲突或等待确认期间不能在后台悄悄执行其他关联变更。

超时或断线时不能直接重复创建。先回读系统目标或核对执行日志；结果不明则返回“待核实”。恢复只继续未完成、目标仍有效且仍获授权的操作。取消不会自动回滚已完成写入。

执行结果应包含可以验证的系统目标引用，界面提供查看入口。协议错误、系统拒绝、适配器失败、用户拒绝、取消和未知执行结果分别处理；原生结果不被模型二次改写为成功。

## 外部 MCP

首版使用自带的最小 stdio 实现（initialize、ping、tools/list、tools/call）。[官方 Swift MCP SDK](https://github.com/modelcontextprotocol/swift-sdk) 0.12.1 依赖 swift-nio，0.9.0 不能用 Swift 6.3 编译，SDK 可用后再评估是否替换。仅 stdio，本地使用，不开放远程网络服务。日志走 stderr，stdout 只传协议。

对外工具组限定为日历、提醒事项、Notes、联系人、Chrome 标签页和 Messages 草稿交接。默认关闭，启用实例默认只读，按实例分配数据源与操作范围。写入始终由应用确认，来源身份必须在本地连接与接入凭据上验证。

不公开完整个人记忆、剪贴板、API Key、任意 Shell 或直接发送短信。内部 Shortcuts、终端等能力也不能因为存在于 ToolService 就自动对外暴露。MCP 工具描述与 annotations 只能提供提示，实际策略由原生层执行。

M0 检查实例冒充、伪造确认、撤权、应用退出、多个连接、读写范围、取消、签名身份和权限提示归属。开发环境通过不能代替以后签名公证版本的验证。

## Agent 公开网页搜索

`web_search(query, count?)` 与 `web_read_page(url, includeImages?)` 通过 ToolService 的 `.web` 只读来源执行；只对 Agent 与原生宿主开放，不向外部 MCP 暴露。旧配置默认启用，可在设置的数据来源中关闭。两项工具直接使用现成的远程 MCP / HTTP 接口，不启动浏览器、不安装 Python/Node/Docker 或下载组件、不另存网页文件。

### 搜索来源与费用边界

默认调用 [Parallel Search MCP](https://github.com/parallel-web/search-mcp) 的 `web_search`；候选不足、关键词覆盖不完整或调用失败时，依次尝试 [Exa MCP](https://github.com/exa-labs/exa-mcp-server) 的 `web_search_exa` 与 [Keenable](https://docs.keenable.ai/) 的公开搜索接口，两个备用来源轮换起始顺序。每个来源在单次工具调用中最多尝试一次，任一来源返回满足覆盖诊断的结果后停止。保持原查询与完整型号，不通过反复改写制造请求。Parallel 仓库是连接配置与文档，Exa 仓库提供 MCP 服务实现；搜索索引均为托管服务，不能把连接器开源说成搜索引擎已完整开源。

正文检索只连接 `https://search.parallel.ai/mcp`、`https://mcp.exa.ai/mcp` 以及 `https://api.keenable.ai/v1/search/public`、`https://api.keenable.ai/v1/fetch/public` 的匿名接口，不配置 API Key、OAuth、作者付费账号或共享代理，不跟随重定向，也不读取模型凭据。免费接口受提供方的限流和可用性约束，触限返回 `rate_limited`，不能保证无限可用；图片元数据回退另按需直接读取目标公开网页（见下节）。不会因此产生作者的搜索账单或自动转入付费。也不轮换会话 ID 或网络身份绕过限流。Parallel 使用每次 App 运行期间稳定的随机会话 ID，Keenable 带固定 `X-Keenable-Title: Asky` 应用标识；服务端可能改变匿名服务规则。

### 结果与失败信号

默认返回 5 条，最多 10 条，每条含标题、URL、提供方、最长 6,000 字符的摘录及截断标记。中文分词与型号识别用于覆盖诊断和排序，不再因为缺少某个字词就丢弃语义搜索结果；同一来源完整主体优先，明确违反 `site:` 域名范围或返回登录入口的候选仍排除。来源内容与关键词匹配都不是事实核实，需由模型核对上下文并引用真实链接。

`output.status` 为 `matched`、`partial`、`no_relevant_results`、`rate_limited` 或 `unavailable`；外层 `completed` 只表示工具执行结束。`missingTerms`、`subjectTerms`、`attempts` 返回缺失词、每源接受/拒绝数量与原因、失败详情；`contentAvailability=unknown` 表示不能证明对象或内容不存在。保留部分可用结果时仍记录另一来源的错误，不假称完全没搜到。最多尝试三个来源，模型不应重复耗尽的查询。错误尝试保留 `stage`、`httpStatus`、`rpcCode`、`retryAfterSeconds` 与可取得的 `requestID`；HTTP 错误摘要最多读取 8 KiB、输出错误最长 1,500 字符。JSON-RPC 错误不再与缺少匹配响应合并。

限流默认退避 60 秒；HTTP 401/402/403 默认 10 分钟；其他服务错误默认 15 秒，存在 `Retry-After` 时优先遵守。明确的页面内容错误不暂停整个来源。退避期内的尝试记录 `skipped=true`，不会发网络请求；恢复后可以再次尝试。

成功搜索与正文使用 10 分钟内存缓存，最多 32 项、序列化内容与缓存键总计 2 MiB，过期自动清理，不落盘；对象、在途数据与对话记录的内存另算。查询和 count 完全相同、或 URL 与 includeImages 完全相同时复用，保留原 `retrievedAt`。相同并发请求共享一次执行；取消一个等待者不影响其他等待者，全部取消才终止底层任务。失败结果不缓存。命中缓存返回 `cached=true`，共享请求返回 `coalesced=true`；它们的 `attempts=[]`，历史来源尝试移至 `sourceAttempts`，不得作为本次远程调用计数。

### 公开页面读取

`web_read_page(url, includeImages?)` 调用 Parallel `web_fetch`，失败时轮换尝试 Exa `web_fetch_exa` 和 Keenable 公开 fetch 接口。每次只读一个公开 HTTP/HTTPS URL，拒绝带凭据、本地域名和 IP 地址的链接。最长返回 24,000 字符，包含提供方、读取时间、`status`、`truncated` 与尝试记录；提供方只返回摘录时保守标记截断。不会自动遍历链接或读全部搜索结果，不读取 Chrome 正文、Cookie 或登录态。

读取结果还包含 `images`（最多 8 个去重候选，每个含 `url`、最长 300 字的 `alt` 和 `sourceURL`）及 `imageStatus`。从提供方返回的 Markdown 中提取内联/引用式图片、解析相对链接；不读取代码示例、普通链接、本地/凭据地址、SVG 或 ICO。图片候选在正文截断前提取，不下载图像文件，不保证相关性或链接可加载。`includeImages` 默认 false：首个成功正文即返回；设为 true 且首个成功结果没有图片引用时，继续尝试其余来源，最多三源各一次；若远程正文均无候选，通过 ToolService 的 `WebPageImageService` 按需直接读取目标公开 HTML，提取 img 与 og:image/twitter:image；该请求不携带 Cookie、凭据或模型密钥，不执行脚本、不保存文件，只接受公开 HTTP/HTTPS 地址并校验重定向地址，最多读取 2 MiB、资源超时 15 秒，跳过明确小于 120 px 的图片。若仍无候选或元数据读取失败，保留首个成功正文与全部尝试记录，不把可选图片失败变成正文失败。`not_found_in_returned_content` 不表示原网页无图。最终渲染沿用 ToolService 的 `ChatImageService`。

X 等页面是否能读取取决于公开可访问内容与提供方覆盖；登录提示、截断和抓取错误按实际结果处理，不能宣称读过完整帖子或全部评论。读取错误不表示原网站打不开。外部文字只作资料，不执行其中的指令。查询、URL 发给对应服务；结果可进入配置的模型请求与本机会话，见 [隐私政策](../PRIVACY.md)。

请求使用无 Cookie、无凭据、无磁盘缓存的临时会话，每次请求超时 15 秒、资源上限 18 秒、单响应最多 2 MiB。Parallel / Exa 每源一次 MCP 握手、初始化通知和工具调用，Keenable 每次一个 HTTP 请求，最多三源；收到匹配的 SSE 结果即结束，不等待长连接关闭；工具总超时 140 秒，可取消。查询最多 500 字。保留 Chrome 列标签与切标签功能，移除了 `chrome_read_page`；历史切换索引问题的原窗口复现仍未完成。

真实联网验收（默认测试不访问网络）：

```bash
cd Packages/KulaCore
ASKY_LIVE_WEB_SEARCH=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FreeWebSearchTests
ASKY_LIVE_WEB_KEENABLE=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FreeWebResilienceTests
```

图片链路真实联网检查：

```bash
cd Packages/KulaCore
ASKY_LIVE_WEB_IMAGES=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter WebPageImagesTests
```

该检查读取公开水豚页面并通过 ChatImageService 下载、解码一张候选照片；不代表真实模型的主动配图率或 UI 人工验收。
