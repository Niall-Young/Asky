# 主动配图与公开网页图片候选

日期：2026-11-17。

## 改动

- 系统提示词明确客户端可展示 Markdown 远程图片，区分展示照片、视觉理解与生成图片；图片能帮助识别或比较时主动查找，纯文字任务与用户不联网/不配图要求优先。
- `web_read_page` 返回最多 8 个有来源的图片候选；`includeImages:true` 在正文无图时尝试其他来源，仍无图则通过 ToolService 读取公开网页图片元数据。普通正文读取不增加元数据请求。
- 按来源核对候选，通常选 1–3 张，使用独立 Markdown 图片段落与来源链接；不猜地址、不把生成图冒充实拍、缺图不影响正文回答。
- 同步中英文 README、工具描述、PRD、运行时/工具专题与隐私说明。没有新增界面说明文字。

## 已执行检查

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：386 个测试、13 个测试目标全部通过。默认运行未启用 opt-in 真实网络检查；总数包含其提前返回的测试。
- `ASKY_LIVE_WEB_IMAGES=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter WebPageImagesTests`：6 个测试通过；经 ToolService 读取 `https://en.wikipedia.org/wiki/Capybara` 得到 8 个候选，`ChatImageService.imageData` 成功下载并解码一张水豚照片，显示数据为 92,977 字节。最终该组耗时约 7.4 秒。此结果不保证所有站点的图片可用。
- 定向覆盖：Markdown 相对与引用式图片、排除代码/普通链接/本地与凭据地址/SVG、去重与数量限制、截断正文之后的图片、独立缓存、备用来源、可选元数据失败仍返回正文、取消传播与参数校验。
- HTML 元数据覆盖：img、懒加载 data-src、社交预览图、HTML 实体、相对链接；跳过脚本/注释、SVG、明确微小图片与不允许的地址；同 URL 优先保留正文图片说明。
- `xcodegen generate` 与 README 的 Debug `xcodebuild ... -derivedDataPath build/DerivedData build`：通过。
- 中英文 Core.strings 的 `plutil -lint`：通过；`git diff --check`：通过。

## 验证边界与运行状态

- 原 `/Applications/Asky.app` 已退出，为验证启动了 `build/DerivedData/Build/Products/Debug/Asky.app`，通过进程路径核实。未替换 /Applications 的正式版本，未发布 Release。最后一次构建后的元数据去重小修正尚未重启进程；磁盘 Debug 包已包含全部修改。
- 尝试通过 CUA 向新版启动器输入“水豚长什么样，简单介绍一下”，但 typeText、paste、setValue 未使输入内容进入界面，期间出现 timeout/noWindowsAvailable；未成功提交真实模型请求。不能将本次检查记为模型主动配图率或最终聊天 UI 验收通过。
- 配图选择仍由当前配置模型在 `tool_choice: auto` 下执行。尚未做人物/旅行/产品与纯文字负例的真实模型对照测试。
- cyberbrain context 读取返回 GitHub API 404；未取得附加模块，本次按仓库当前指南与用户要求执行。
- 构建产物复用现有 build/、Packages/KulaCore/.build/、Asky.xcodeproj/ 忽略规则；测试日志与 README 检查报告保存在 /tmp，无新增忽略规则。
