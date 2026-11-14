# Asky 文档索引

**想学习如何使用 Asky？先读[使用教程](https://asky.niallyoung2002.workers.dev/docs)。** 本页其余内容主要面向产品与开发工作。

更新日期：2026 年 10 月 9 日。状态：V1 代码已按 M0–M4 实现，可以构建；自动化测试通过，DeepSeek 基础对话与历史重开已验证，见 [DeepSeek 验证记录](validation/2026-10-09-deepseek.md)。完整 UI、真实系统权限及其他模型能力验收尚未完成，见 [M0 验证记录](validation/2026-10-09-m0.md)。

Asky 首先提供不依赖 AI 的 macOS 效率入口，再通过按需运行的 Agent、本地记忆和情境提醒增强系统能力。本目录整理完整自用 V1 的产品要求、实现边界与验证方法。

## 阅读顺序与文档职责

先读 PRD 与框架，再按当前开发主题阅读专题；开始实施前检查验证文档中的 M0 门槛。

| 文档 | 权威内容 | 适用任务 |
| --- | --- | --- |
| [使用教程](https://asky.niallyoung2002.workers.dev/docs) | 安装、快捷键、日常场景、AI 配置、Markdown 记忆、权限与常见问题 | 首次使用及日常查阅 |
| [V1 产品需求](PRD.md) | 产品范围、用户行为、默认设置、交付与验收 | 判断做什么、是否符合 V1 |
| [产品框架与架构](framework.md) | 技术栈、模块、进程与主要接口 | 模块划分、进程边界、总体数据流 |
| [原生界面与设计系统](design-system.md) | Figma 变量、Styles、原生控件、Liquid Glass | 页面、窗口、组件与主题 |
| [Agent Runtime](agent-runtime.md) | Swift 原生循环、模型接入、任务、会话迁移与资源生命周期 | AI 集成、会话、原生通信 |
| [GitHub 插件](plugins.md) | 可信插件安装、独立官方仓库、插件 API 与 CLI 执行 | 插件管理、作者接口、Orca 交接 |
| [原生工具与 MCP](native-tools-and-mcp.md) | 系统适配器、工具契约、权限、执行与回读 | macOS 操作、MCP、敏感写入 |
| [数据、记忆与提醒](data-and-memory.md) | 数据归属、记忆文件与提炼整理、删除边界及提醒计划 | 数据存储、记忆、情境增强 |
| [隐私政策草案](../PRIVACY.md) | 不向作者上传、设备处理、第三方接收、保存与删除边界 | 对外隐私说明；发布前须补全主体与联系方式 |
| [资源生命周期与性能](resource-lifecycle.md) | 内存预算、分页、并发、释放与测量 | 常驻资源、性能、缓存 |
| [开发与发布](development.md) | 回归命令、Debug 预览、签名与打包操作 | 开发检查及 Release 打包 |
| [实施与验证](implementation-and-validation.md) | 阶段门槛、验收映射、风险与验证记录要求 | 开发顺序、自用验收 |

## 状态的含义

- **已确认要求**：用户明确要求或已接受的产品边界；表示实施必须满足，不表示功能已经实现。
- **建议默认值**：为了形成可执行设计而采用的初值，例如窗口尺寸、60 秒空闲退出、缓存预算；可根据原型测量调整。
- **待原型验证**：存在接口、权限、兼容性、性能或恢复风险，必须完成指定验证才可锁定；不能描述为已经可用。

产品行为以 PRD 为准。专题文档维护技术规则；其他文档引用它们，不复制完整规则。若出现矛盾，先按最新用户要求修订对应权威文档，再同步摘要与链接，不能让实现自行选择两套规则。

## 当前关键取舍

| 主题 | 当前取舍 | 状态与详细依据 |
| --- | --- | --- |
| 定位 | 完整自用 V1，效率入口优先，AI 为增强 | 已确认；[PRD](PRD.md) |
| 界面 | SwiftUI 与 AppKit 原生组件，使用用户 Figma 变量与 Styles，加入原生 Liquid Glass | 已确认；[设计系统](design-system.md) |
| Runtime | Swift 原生 Runtime，在主进程内按需运行，无 Node / Pi 依赖 | 已实现；验证范围见 [Agent](agent-runtime.md) |
| 运行方式 | 原生应用常驻，明确提交 AI 请求才创建 Swift Runtime | 已确认方向；空闲退出时长为默认值；[Agent](agent-runtime.md) |
| 扩展 | 仅加载内置能力与用户主动安装的可信 GitHub 插件，不建立 V1 插件商店 | 已确认方向；[Agent](agent-runtime.md) |
| 数据 | 本地持久化、最小上下文外发、来源权限继承 | 已确认；[数据](data-and-memory.md) |
| 性能 | 管理每类资源的归属、上限和释放，不以语言判断占用 | 已确认；预算待测量；[资源](resource-lifecycle.md) |

当前 Agent 已迁移为 Swift 原生实现。旧 Pi 会话按需导入；插件 API v2 无 Node 依赖，旧 JavaScript 插件兼容入口使用本机 Node。

原始构想见 [SwiftUI Agent构想](https://chatgpt.com/c/6ac7944a-fc58-83e8-ab44-cac56c1dd796)。本目录使用当前讨论的修正：仅 Chrome 标签页、剪贴板历史、Messages 人工发送、默认不后台唤醒模型，以及资源生命周期优先。
