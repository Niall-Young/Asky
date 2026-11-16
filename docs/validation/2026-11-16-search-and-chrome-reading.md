# 中文搜索召回、失败诊断与 Chrome 页面读取

日期：2026-11-16。源码修改与 Debug 构建；未替换 `/Applications/Asky.app`，未声称用户正在运行新版本。

## 诊断证据

- 从原生会话工具调用/结果配对确认：`quality`、`missingTerms`、`attempts` 已完整送入模型，问题并非这些字段被 Runtime 丢弃。外层执行 `completed` 和内层 `no_relevant_results` 同时出现，模型仍进行了多轮相似查询。
- 原补搜把 `Gemini 4 Carbon 评测 口碑 benchmark` 缩成 `carbon 口碑`，丢失品牌和版本；中英文检索意图被当成必须匹配的主题词，中文公司问题和英文来源之间也存在误过滤。
- Bing 的部分响应确实主要是门户页或同名实体，不能把全部问题归于本地过滤，也不能由空搜索推断内容不存在。
- 免 Key 备用入口探测：DuckDuckGo HTML 返回 HTTP 202 人机验证，Google 返回依赖浏览器执行的页面；本次未接入这些入口、未配置搜索 API 或付费服务。DuckDuckGo 官方说明传统网页结果主要来自 Bing：<https://duckduckgo.com/duckduckgo-help-pages/results/sources>。

## 实现

- 按文字脚本分词；中文显式指定中文语言；保留 K3.1、完整型号和数字版本。主题身份与评测等检索意图区分，常见中英文意图等价匹配，缺少评测的相关介绍可返回 `partial`。比较查询和规格附加条件保留部分来源，不冒充完整覆盖。
- 补搜保留完整主题；过滤无关登录入口和同名品牌的错误模型语境。输出 `status`、`reason`、`subjectTerms`、`missingTerms`、每轮接受数/拒绝原因、`contentAvailability=unknown` 和 `nextAction`；全部请求失败仍报错，取消仍传播。
- Agent 说明区分调用执行状态和内容质量，避免反复提交已经尝试过的同组关键词。摘要合并搜索结果内已有段落，上限 1,500 字符，不补写正文。
- 独立新增 `chrome_read_page`，经 ToolService 和 `.chrome` 来源鉴权，只读已加载正文，精确校验标签 ID/URL，排除无痕和非 HTTP(S)，最多 24,000 UTF-16 单元；不对 MCP 开放，不接收任意脚本，不自动改权限。权限提示中英文同步。
- 切标签匹配后固定整数索引并立即结束遍历，执行前检查失效目标。原来的“索引无效”没有在临时窗口复现，不能声称已证明其根因。

## 检查结果

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore`：通过，380 项 Swift Testing，另有 2 项 ChatLinkService XCTest 和 3 项 AgentReaction XCTest。
- `ASKY_LIVE_WEB_SEARCH=1 ASKY_LIVE_WEB_SEARCH_CHINESE=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore --filter WebSearch`：22 项通过，真实经过 ToolService → WebSearchTool → Bing。默认离线测试中，带环境变量门控的联网用例不执行网络。
- 最终联网样本：Slack 中文问题返回 5 条，Kimi K3.1 Pro 中文评测返回 5 条，两组 Gemini 中文评测各返回 2 条，均为 `partial`。Slack 公司词、Kimi 评测/SWE-bench、Gemini 评测/开发者实测仍有未覆盖项；这不是这些评测已经找到或不存在的证明。搜索结果会随时间变化。
- 额外启用历史 `ASKY_LIVE_WEB_SEARCH_RECOVERY=1` 的回放没有全通过：8 条旧查询中 5 条找到所断言的官方 Carbon 来源，3 条未找到，分别是 `Gemini Carbon model Google`、`Google Gemini 4 Argon Carbon 旗舰模型 对比` 和 `Gemini 4 Carbon 模型 Google 发布`。保留原联网断言，未为了绿色测试删掉它们。该轮另发现的规格条件单测缺陷已修复，并由全包测试确认。
- Chrome 实机 `osascript`：在临时双标签窗口切到指定首标签，核对 active tab ID 正确；关闭目标后返回 -1728。测试窗口已关闭。
- 尝试在 Swift Testing 进程内做 Chrome Apple Events 实机用例未完成，等待超过两分钟后终止本次测试进程；未将其记为通过，也未保留会阻塞默认测试的实机用例。上述实机结果来自独立 AppleScript，不冒称来自 App 内 ToolService。
- 独立 headless Chrome 合成页面验证：使用工具中的原样正文提取脚本，正确提取可见文章段落，排除隐藏文字、textarea、输入框和 contenteditable 草稿；这不代表登录后的 X 或 App 内 Apple Events 成功路径已验证。
- Chrome 正文探测：实际返回错误 12，“允许 Apple 事件中的 JavaScript”关闭。没有更改该设置；X 正文读取成功路径、登录状态和实际模型使用尚未验证。权限关闭不是 X 网站打不开。
- `xcodegen generate` 与 README 中的 Debug `xcodebuild`：通过。构建日志存在本机 iOS Simulator 版本警告，macOS App 构建成功。
- 中英 `Core.strings` 的 `plutil -lint`：通过；`git diff --check`：通过。README 已同步中英文能力与权限说明，PRD、工具说明和隐私说明同步。

## 日志与产物

本机临时日志：`/tmp/asky-search-all-final.log`、`/tmp/asky-search-live-acceptance.log`、`/tmp/asky-search-live-final.log`、`/tmp/asky-search-app-localized.log`。Debug 产物：`build/DerivedData/Build/Products/Debug/Asky.app`。既有忽略规则覆盖 `build/`、`Asky.xcodeproj/`、`Packages/KulaCore/.build/`，没有新增忽略规则。
