# Agent 历史工具记录恢复

日期：2026-11-14。

## 原因与修复

原生消息投影此前只保存用户消息和助手正文，工具调用、结果、错误及提示仅在 AgentModel 内存中。重开历史后还会丢失同轮回复分组、完成时间和耗时。

- SQLite v6 为消息增加可选展示元数据，旧消息保持可读；工具步骤使用原调用 ID 保存并原位更新状态、权限入口和错误文案，不保存额外的工具参数或原始结果。
- 同轮消息保存 responseID、完成时间和耗时；错误和中断提示随历史恢复。重开时未收到结果的工具显示待核实。
- 超过 120 条可见记录时保留历史游标；已移出可见窗口的工具结果更新原记录，避免重复插入。
- 记忆提炼在分页限制前筛选用户和助手正文，避免工具展示记录挤占对话上下文。
- 此前没有写入消息投影的工具记录不自动补录。

## 实际检查

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/HistoryDerivedData -clonedSourcePackagesDirPath build/DerivedData/SourcePackages build`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path /tmp/asky-history-xcode-tests --jobs 4`：最终通过，13 个测试产品共 323 项测试。首次默认 Command Line Tools 缺少 Testing；改用 Xcode 后，运行期间的源码改动和另一处 NativePluginTests 缺少 intent 参数曾导致编译中止，固定后的最终运行退出码为 0。
- 另以临时 SwiftPM 包直接引用本仓库 Contracts、LocalStore 和 LocalStoreTests：19 项测试通过，覆盖旧数据库迁移、磁盘重开、跨页顺序、工具状态原位更新、错误/权限元数据、全文索引及删除联动。
- `ASKY_DERIVED_DATA=/Users/niallyoung/orca/Asky/build/HistoryDerivedData DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py`：首次运行被另一处 ChatSourcePreview.swift 在编译期间的修改中止；将 App/Sources、回归入口及辅助脚本复制到临时快照后重跑。新增断言曾错误检查末尾中断提示的耗时，改为检查助手回复并使用固定时钟后，最终编译、签名、运行退出码为 0。45 条工具记录跨页重开后的完整 ChatItem 快照相同；125 条记录的可见窗口裁剪、迟到结果原位更新及向前分页通过，既有澄清、取消、耗时、附件和新对话回归通过。未以此替代真实窗口视觉验收。
- 本次修改文件的 `git diff --check`：通过。构建和回归产物沿用已有 `build/` 忽略规则。

## 验证范围

未替换当前安装版，未进行真实模型或真实系统工具调用。现有工作区正在进行其他改动；本次保留其源码、测试及文档，不创建混合提交。README 仅补充中英文对话历史说明；本次修复未改变项目级开发规范，AGENTS.md 无需因本任务更新。
