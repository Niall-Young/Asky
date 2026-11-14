# 网页引用与来源卡片

## 当前行为

- 每段 / 每个列表项的网页来源统一显示在信息末尾，同一段相同 URL 去重。数字与“来源”类引用标签不占正文；描述性链接文字保留为正文，不再以下划线链接充当悬停入口。会话仍保存原始 Markdown。
- 来源图标读取网站声明的 favicon / touch icon，失败再尝试该网站的 `/favicon.ico`；全部不可用时回退通用网页图标。只访问来源网站，不使用第三方 favicon 代理。按 origin 合并并缓存请求，最多保留 64 个站点，图标缩小至 32 px。
- 悬停图标 300 ms 后显示独立、无箭头的 `SurfacePanel`，复用 `WindowSurface.glassContentView` 与系统窗口阴影。按附件 glyph 的实际屏幕坐标定位，空间不足时向上展开，约束在来源所在屏幕内；滚动 / 窗口移动时跟随，来源离开可视区域时关闭。同一时刻只展示一张来源卡片。
- 封面、标题与域名由 ToolService 在悬停时获取。HTML 上限 512 KiB，最多缓存 8 份预览。读取失败时使用文字卡片，点击图标或卡片打开原文。

## 本次检查

- `xcodegen generate`：通过。
- README 中的 Debug `xcodebuild` 命令：通过，日志 `/tmp/asky-citations-favicon-final-build.log`。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，日志 `/tmp/asky-citations-favicon-tests.log`。
- `swift test --filter ChatLinkServiceTests`：新增 favicon 解析用例与原 metadata 用例共 2 项通过；覆盖相对图标地址、HTML 实体、shortcut icon / touch icon 优先顺序和非 HTTP 地址过滤。日志 `/tmp/asky-citations-favicon-parser.log`。
- 原生 UI 回归：从 `AgentReplyRegression.sourcesPreview()` 提取本次窗口回归，编译实际 Markdown、来源卡片、SurfaceWindow 与玻璃呈现代码，使用 `build/citation-preview` 中冻结的 Debug 产物运行，通过。覆盖所有网页来源移到段末、去重、真实 favicon、负坐标屏幕边界、原生鼠标事件触发卡片、滚动 200 pt 后的附件坐标和底部来源向上展开。日志 `/tmp/asky-citations-favicon-scroll.log`。
- 从 `https://devin.ai/` 获取 1269 字节 favicon；预加载真实封面后检查浅色正文、深色滚动后的段落及圆角卡片截图。截图 `build/sources-{light,dark}.png`、`build/source-card-{light,dark}.png`，复用已有 `build/` 忽略规则。
- 已重启当前 `build/DerivedData/Build/Products/Debug/Asky.app`，确认实际进程来自该路径。

## 验证边界

- 未通过真实模型重新发起联网搜索；窗口回归使用 Markdown 样例与真实网站图标 / 元数据。
- 未安装或发布新版。来源不提供可解码图标或封面时使用上述回退。

## 修正背景

初版仅把数字引用改成标记，描述性链接仍为正文链接；使用 NSPopover 时在用户真实滚动会话中出现远离来源的定位问题。本轮替换了该实现，并补充真实 clip-view 偏移和低位置来源的定位断言。初版构建与专项测试日志仍保留在 `/tmp/asky-citations-*`；以本页当前检查结果为准。
