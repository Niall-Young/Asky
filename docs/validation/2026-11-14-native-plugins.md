# Agent 与聚焦搜索的原生插件 · 2026-11-14

## 本次实现

- Orca、飞书两个独立官方仓库迁移为 API v2 Swift 原生入口，保持 ID、工具名、配置与持久化状态；插件执行器无需 Node / npm。CLI 自身的运行环境由使用者准备。
- Text Tools 聚焦搜索示例迁移为 API v2 Swift 可执行文件，保留 URL 编解码、Base64 编码、UUID；`agentVisible: false`，不向 Agent 发布工具。
- Agent 的 tools 与启动器的 commands 共用 ToolService 执行、权限、状态、确认、取消与回读接口。动态搜索仍由宿主防抖并抛弃旧结果；没有新增 UI 或模型调用。

## 已运行

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：331 项 Swift Testing、2 项 XCTest 全部通过。
- `NativePluginUpgradeTests.legacyLauncherUpgradesWithoutNodeAndPreservesConfigurationStateAndRollback`：在未配置 Node / JS runner 的宿主中，将旧 API v1 安装更新为真实原生 Text Tools；验证配置、启用状态、持久化状态保留，以及双向回退。覆盖中文、字面 Shell 字符、不完整 URL 转义、解码与空结果。
- `PluginLauncherTests`：原生示例从安装、启用到动态结果、UUID、停用、卸载通过；Agent 无权调用隐藏工具。另保留 API v1 写入测试，确认拒绝与回读行为继续通过。
- `./examples/plugins/text-tools/build.sh`：生成 macOS 14+ arm64 原生二进制；`codesign --verify --strict` 通过。产物随示例分发。
- 单独复制 Text Tools 目录，在 `PATH=/usr/bin:/bin` 的隔离环境中直接执行 transform 与 UUID：通过；不依赖项目目录、Node、npm 或编译器。
- 两个独立插件分别编译、签名检查、9 项原生 JSONL / RPC 回归通过；暂存区导出的干净安装也分别通过 9 项测试，保留二进制可执行位。
- 原生 Orca 执行器经 exec RPC 实际读取本机 `skills get orca-cli` 和 `repo list`；原生飞书执行器读取 `calendar +agenda --help`：均通过。没有执行真实写操作。

## 验证边界与交付状态

没有修改或运行 App 界面，本次无视觉验收；没有操作用户已安装插件、升级运行中的应用或触发真实 CLI 写入。最低系统版本兼容性未在 macOS 14 实机验证。当前二进制为 ad-hoc 签名，未做 Developer ID 签名与公证。

独立仓库已分别本地提交：Orca `10b3183`（`refactor: 将 Orca 插件迁移为 Swift 原生入口`）、飞书 `cbf4525`（`refactor: 将飞书插件迁移为 Swift 原生入口`），工作区干净；两个插件已推送到各自 `origin/main`，未创建 Release。两个仓库新增 `__pycache__/` 忽略规则，主仓库构建产物复用现有 `.gitignore`。此前主仓库的 Agent/API v2 宿主迁移尚未提交；用户随后明确要求全部推送，因此与插件改动一并提交。README 双语与插件指南已同步。
