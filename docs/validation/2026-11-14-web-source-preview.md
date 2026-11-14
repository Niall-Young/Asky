# 网页来源标签与列表

## 当前行为

- 每段 / 每个列表项的网页来源合并为一个 24 pt 高的文字胶囊标签。单来源显示来源名称，多来源显示“首个来源名称 +N”，N 为额外来源数量，例如四个 URL 显示 `Kimi +3`。相同 URL 去重，不按网站合并不同文章。
- 数字与“来源”引用标签不占正文；描述性链接文字保留为正文。会话仍保存原始 Markdown，已有回复使用相同的新样式。
- 悬停 300 ms 或点击标签展开文字来源列表，逐项展示网站名称、文章标题和可获取的发布日期。点击条目打开对应原文；缺少元数据时显示真实域名和 URL，不虚构来源名称或日期。
- 移除 favicon 抓取、图标缓存和封面预览，不再显示并排小图标或大封面。元数据 HTML 上限 512 KiB，缓存最多 32 个 URL，并合并相同 URL 的在途请求。展开列表最多同时读取 4 个来源。
- 卡片宽 380 pt，最高 460 pt（小屏进一步约束）；长列表在卡片内滚动。元数据更新时保留同一宿主视图与 ScrollView。卡片继续使用独立 SurfacePanel、原生玻璃和系统阴影，以标签位置为中心展开，保留滚动后定位、屏幕边界和底部向上展开。

## 检查

- `xcodegen generate`：通过。
- README 的 Debug `xcodebuild` 命令：通过，日志 `/tmp/asky-source-tag-build-final.log`。一次中间构建遇到另一个并行 Debug 构建的数据库锁，重试后通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，日志 `/tmp/asky-source-tag-tests-final.log`。其中 2 项来源元数据测试覆盖网站名称、标题、发布日期、实体解码、属性顺序和缺失字段回退。
- 从 `AgentReplyRegression.sourcesPreview()` 提取窗口回归，编译实际 Markdown、来源列表、SurfaceWindow 与玻璃代码，针对冻结的 Debug 产物运行：通过。覆盖单来源、四来源 `+3`、去重、hover / click 入口、12 条来源的真实原生列表滚动、段末标签、负坐标屏幕和真实 clip-view 滚动后的底部向上展开。日志 `/tmp/asky-source-tag-preview-final.log`。
- 已检查实际浅色段落标签、深色滚动段落及两条来源列表截图。段落读取真实 Devin 网站名称；独立两条列表使用测试标题与日期验证参考图中的排版。截图 `build/sources-{light,dark}.png`、`build/source-tag-list.png`，复用已有 `build/` 忽略规则。

## 验证边界

- 未调用真实模型重新生成联网搜索回复；原生窗口回归使用 Markdown 样例，网站名称读取和元数据解析分别验证。
- 未发布或安装新版。没有网站名称时标签使用域名，没有发布日期时省略日期。

## 历次调整

初版数字标记和 NSPopover 定位已被替换；后续段末 favicon 方案在本轮按用户提供的新参考改为文字标签和多来源列表。此前截图与日志不代表当前样式。
