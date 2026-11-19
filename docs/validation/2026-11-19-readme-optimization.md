# README 精简与链接修正

日期：2026-11-19。变更仅涉及文档。

## 变更

- README 首屏改为一句定位，补充 Release 徽章、Issues 入口和中英文内页导航。
- 将联网检索与 AI 配图的实现细节折入 `<details>`，保留用户可见行为并链接到专题文档；两段长文压缩后中英文语义一致。
- 安装章节改为“首次启动”三步，并明确不配置模型也能使用搜索、剪贴板与预览。
- 开发章节补充网络导致 Package 解析失败时的 `-skipPackageUpdates` 提示，目录职责与文档入口保持不变。
- 新增“参与贡献”章节，链接 `CONTRIBUTING.md`。
- 修正文档索引与数据文档中失效的使用教程域名：`asky.niallyoung2002.workers.dev` → `asky.niallspace.workers.dev`。

## 已执行检查

- 本地链接检查：README 中所有相对路径目标均存在。
- 锚点检查：中英文页内导航与 `<a id>` 目标一致；`CONTRIBUTING.md` 依赖的 `#开发与构建`、`#development` 标题保留。
- 中英文对照：六个章节标题、三处命令块、文档链接集合与折叠块数量一致。
- `curl -L` 确认新教程域名返回 200，旧域名无响应。
- `git diff --check` 通过。

本次没有修改 Swift 或资源文件，未执行构建、单元测试或 UI 回归。
