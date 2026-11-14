# Swift 原生 Agent 迁移验证

日期：2026-11-14。环境：Apple Silicon、macOS 27.0.1（26A434）、Xcode 27.2（27B52）。本次是源码与本机构建验证，不是 GitHub Release 发布。

## 交付范围

- Swift NativeRuntime 替代 Pi / TypeScript AgentRuntime；主应用不再寻找或启动 Node。
- Swift 实现 Chat Completions、SSE / JSON 响应、碎片工具参数、工具循环、原生澄清、上下文压缩、取消与恢复。保留现有记忆、系统工具、表单和确认路径。
- 会话与附件 I/O 由 ToolService 的 AgentSessionStorage 管理。Pi 活动分支按需导入；未完成调用补为待核实，不自动重放。
- API v2 原生可执行插件直接由 ToolService 启动；API v1 保留约 4 KiB 的独立 JS 兼容脚本，使用本机 Node。移除 Pi 依赖树、随包 Node 和相关签名权限。
- 原生插件示例提供 Swift 源码与清单。插件作者发布前编译入口；安装不需要用户安装编译器或 npm。

## 实际执行的检查

| 检查 | 结果 |
| --- | --- |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore --scratch-path build/NativeCoreTests` | 通过，13 个测试 target 合计 323 项 |
| 最后连接复用与资源超时调整后，以上命令增加 `--filter NativeRuntimeTests` | 通过，8 项 |
| `xcodegen generate` | 通过 |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/NativeDerivedData build` | 通过 |
| 同路径 `-configuration Release` | 通过；含 arm64 与 x86_64 |
| `codesign --verify --deep --strict --verbose=2 build/NativeDerivedData/Build/Products/Release/Asky.app` | 通过 |
| `python3 App/Tests/check-localization.py` | 通过，语言键与格式参数一致 |
| `node --check PluginSupport/plugin-runner.mjs` | 通过；仅检查旧插件兼容脚本，不是 Agent 的运行依赖 |
| `python3 -m py_compile scripts/package-release.py scripts/signing.py` | 通过 |
| `python3 scripts/package-release.py --help` | 已确认不再要求 `--runtime` / `--node-root` |

核心回归实际覆盖：

- 无 Node 配置的原生插件编译、安装、启用、启动器命令、调用与无效参数拒绝。
- 旧 JavaScript 插件的执行、CLI RPC、状态、回读、确认策略与生命周期回归。
- 真实回环 HTTP 服务的逐字节 UTF-8 / CRLF SSE、工具调用与结果后续轮次。测试服务使用 Python，模型调用与 Agent 本身均由 Swift 执行。
- 文本增量和完整消息、重建运行时后的历史续聊、密钥不写会话、ask_user 后不执行同批后续工具。
- 写操作意图转发与剥离、工具在途取消、未知结果不重放、真实网络连接失败、碎片 JSON 与中断输出拒绝。
- 长上下文压缩保存摘要并保留当前请求、Pi 废弃分支排除、未完成工具修复、路径拒绝、附件引用与读取上限。

## 应用包体积

对比本机已安装的 Asky 0.2.10（50）与当前源码的 Release 构建。两者均为 universal Mach-O；当前工程默认版本仍为 0.1.0（1），本次没有分配新的发布版本。

| 指标 | 旧安装 | 原生 Release |
| --- | ---: | ---: |
| `du -sk` 应用包磁盘占用 | 335,408 KiB，约 327.5 MiB | 48,012 KiB，约 46.9 MiB |
| 普通文件逻辑大小合计 | 299,195,157 字节 | 49,027,859 字节 |
| Resources/node | 109,784 KiB | 不存在 |
| Resources/AgentRuntime | 173,072 KiB | 不存在 |
| 旧插件兼容脚本 | 在 AgentRuntime 内 | 4,053 字节 |

应用包磁盘占用下降约 86%。这是旧安装与当前工作区产物的参考对比，包含其他同期改动，并非同一提交的严格 A/B，也不是最终 DMG / ZIP 压缩大小。没有据此推断首字延迟、RSS、CPU 或耗电改善。

## 验证边界

除下节会话路径修复后的简单文本对话外，没有调用用户真实模型或执行真实系统写入、迁移用户实际会话库、发布官方原生插件、覆盖日常安装、公证或发布 DMG / ZIP。完整原生 UI、各厂商图像 / 思考协议、真实 TCC 权限、24 小时待机、实际大历史迁移和长期内存仍需专项验收。

Orca / 飞书独立仓库保持原样；旧 JS 版本在无本机 Node 的设备上会明确报告缺少依赖。要让这些插件也完全免 Node，需要各仓库发布 API v2 原生程序。Asky 的普通 Agent、原生工具和原生插件不依赖这些旧插件。

工作区同时有其他任务的修改与暂存内容，本次不将它们混入迁移提交；实际 Git 状态以交付时检查为准。构建、缓存与日志放在已有忽略的 build/ 或临时目录。

## 会话路径误判修复与实机补验

用户随后在实际 Debug 应用中遇到“会话路径无效”。原因是校验使用 Foundation URL 整体相等比较，目录创建前后的 directory hint / 尾斜杠不同，实际指向同一目录的 URL 被误判不等。原测试使用的临时 URL 构造方式没有覆盖应用的目录形式。

- 新增目录 URL 回归，在修复前实际失败并返回同一错误；修复后通过。
- 将目录和文件父目录比较改为解析符号链接后的规范文件系统路径；没有取消路径限制。
- 新增目录外符号链接拒绝检查，并把真实 HTTP 工具闭环测试改为使用带 directory hint 的根目录。
- 全套 KulaCore 测试通过：325 项；随后 NativeRuntimeTests 的 8 项真实 HTTP / 循环回归再次通过。
- 重建当前使用的 `build/DerivedData/Build/Products/Debug/Asky.app`，核对新运行进程 PID 61020 与该完整路径；Debug 签名校验通过。
- 通过应用的 AI 入口提交一条简单文本请求，实际配置模型正常返回回复，窗口显示完成耗时与复制按钮，未出现会话路径错误。这只验证了基础对话，不代表所有厂商、系统工具或长期运行均已实测。
- 同时重建此前交付路径 `build/NativeDerivedData/Build/Products/Release/Asky.app`，更新该构建中的修复。

本次日志：`/tmp/asky-session-path-before.log`、`/tmp/asky-session-path-tests.log`、`/tmp/asky-session-path-http.log`、`/tmp/asky-session-path-debug.log`、`/tmp/asky-session-path-release.log`。
