# Agent 自然交流与防御性文案调整

日期：2026-11-15。

## 变更

- `NativeAgentPrompt` 允许自然表达关心、欣赏、幽默与有依据的看法，随语境使用口语、感叹和表情；倾诉不强制转成解决方案。
- 移除“只有摘要时明确内容范围”的一律披露要求。摘要足以支持具体事实时直接回答并引用；不足时继续核实，真实缺口影响任务时就近说明，全文分析不能用摘要冒充。
- 不例行转述工具 notice 或罗列能力限制。用户直接询问核实过程时如实回答，影响决策或操作的问题仍需说明。
- PRD、Agent Runtime 与 README 中英文同步上述规则。

## 已执行检查

| 检查 | 结果 |
| --- | --- |
| 在 `Packages/KulaCore` 运行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | 通过，退出码 0 |
| `xcodegen generate` | 通过 |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build` | 通过，BUILD SUCCEEDED |
| `git diff --check` | 通过 |
| README 中英文变更核对 | 交流语气、必要缺口说明规则一致；开发命令不变 |

构建有 AppIntents 元数据提取跳过警告（未依赖 AppIntents.framework），未阻止构建。测试输出有 sandbox_extension_consume 提示，测试通过。

## 验证边界

本次是提示词源码、核心回归与 Debug 构建验证；未调用真实模型做对话评估，未替换已安装应用或发布版本。提示词约束不等同于模型实际表达验收。

后续安装验证（同日，用户要求更新当前 Debug）：已将新 Debug 构建替换至原运行位置 `/Applications/Asky.app`，保持原 Developer ID 签名，并用 `--show-agent` 重新启动。已核对运行进程路径、安装后二进制与构建产物 SHA-256 一致，以及 `codesign --verify --deep --strict` 通过。旧应用备份在被忽略的 `build/debug-install-backups/before-tone-6caj_zgv/Asky.app`；个人数据未改动。退出时 AppleScript 返回 -128，源码确认是应用异步清理先返回 terminateCancel，进程随后自行退出，确认退出后才替换。真实模型对话交由用户试用。

后续试聊重点：具体事实查询不附阅读过程声明；缺少正文时不编造全文分析；好消息、挫折和闲聊能自然承接；直接追问读了什么时如实说明；工具失败不伪报成功。
