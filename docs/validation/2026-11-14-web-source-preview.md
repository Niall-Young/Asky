# 网页引用与来源卡片

## 改动

- 原生 Markdown 正文和列表中的数字、`来源` / `引用` / `source` / `citation` 链接改为紧凑圆角标记，保留原始 URL 与会话 Markdown。
- 网页链接悬停 300 ms 后弹出原生来源卡片，展示封面、标题和域名；卡片与原链接均可打开原文。描述性链接保留文字。
- 网页元数据由 ToolService 按悬停请求读取，不在渲染回复时批量抓取；HTML 上限 512 KiB，最多缓存 8 份预览。没有封面或读取失败时使用文字卡片。

## 检查

- `xcodegen generate`：通过。
- README 中的 Debug `xcodebuild` 命令：通过，日志 `/tmp/asky-citations-build-check.log`。
- 核心 `swift test`：已执行，未通过。默认 Command Line Tools 缺少 `Testing`；切换 Xcode 后被当前并行改动中的 `NativePluginTests.swift` 缺少 `intent` 参数阻断，见 `/tmp/asky-citations-tests.log`。未改动该插件测试。
- 将当前 `ChatLinkService.swift`、`ChatImageService.swift` 和新增解析测试复制到 `/tmp/asky-citation-unit`，使用 Xcode 执行 `swift test --package-path /tmp/asky-citation-unit`：1 项测试通过。覆盖 meta 属性顺序、单/双引号、标题中的撇号、HTML 实体和 title 回退。

- 原生 UI：从 `AgentReplyRegression.sourcesPreview()` 提取本次回归，直接编译实际 `ChatMarkdownView`、`ChatSourcePreview`、`ChatMath` 等呈现代码，对冻结的 Debug 产物运行：通过。检查正文和列表中的 3 个引用附件保留 URL、普通链接保留文字、原生鼠标移动事件弹出卡片；已检查浅色正文与深色卡片截图。
- 原始完整 UI 回归命令在编译期间遇到并行构建替换 `LocalStore.o`；为避免竞态，使用 `build/citation-preview` 中冻结的产物验证本次 UI。日志 `/tmp/asky-citations-preview-isolated.log`，截图 `build/sources-{light,dark}.png`、`build/source-card-{light,dark}.png`，复用已有 `build/` 忽略规则。

- 真实网页封面：调用当前 ToolService 读取 `https://devin.ai/`，返回标题 `Devin: the autonomous software engineer` 与 667258 字节封面；缓存后重新运行原生卡片回归并检查深浅色截图，通过。日志 `/tmp/asky-citations-preview-live.log`。调整标题为多行后再次通过，见 `/tmp/asky-citations-preview-final.log`。

## 验证边界

- 未通过真实模型发起联网搜索，未安装或发布新的应用版本。
- 网站是否提供可用的 Open Graph 封面取决于来源；没有封面时不虚构图片。
