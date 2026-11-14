# AI 表情回应验证

日期：2026-11-14。

## 实现范围

- AI 最终回复支持普通文字、仅一个 emoji、emoji 加文字三种形式。提示词引导感谢、夸奖等收尾消息使用合适表情，有实际问题、结果、错误或确认时继续给出文字。
- `<asky-reaction>…</asky-reaction>` 仅在完整最终回复的首行解析；普通正文、代码示例、非法或不完整标记保留为文字。支持肤色、旗帜和组合 emoji。
- 表情绑定本轮开始时的用户消息 ID，存入该消息的可选 presentation 字段；不另建空白 assistant 消息。保留原消息、引用和表单提交信息，旧记录无需迁移。
- 只在 completed 状态贴表情；取消、失败、待核实不贴。目标移出当前分页窗口仍更新原记录；目标不存在或存储失败时保留可见回复。

## 已执行

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，359 个 Swift Testing 用例及 3 个 XCTest 用例。包括三种格式、非法/引用标记、组合 emoji、保留表单正文、旧 presentation 解码及数据库重开恢复。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/ReactionDerivedData -clonedSourcePackagesDirPath build/DerivedData/SourcePackages -disableAutomaticPackageResolution build`：通过。
- 默认 `build/DerivedData` 的首次构建因其他构建占用 build.db 失败，随后改用上述独立目录。
- 首次原生回归编译因并行任务修改 `AgentReplyRegression.swift` 而中止；改用 `build/ReactionSnapshot` 中当前 App/Sources 与实际 `AgentReactionRegression.swift` 的副本，以及只调用该回归的入口，链接上述 Debug 构建产品。快照与生成物均由现有 `build/` 忽略规则覆盖。

## 原生回归

- `ASKY_DERIVED_DATA=/Users/niallyoung/orca/Asky/build/ReactionDerivedData python3 build/ReactionSnapshot/App/Tests/run-agent-reply-regression.py --reactions-preview`：通过。
- 实际 AgentModel 事件回归通过：三种回复、流式阶段不贴表情、仅表情不创建 assistant 记录、完成后结束等待、重开历史恢复、取消/失败/待核实不贴、目标缺失回退、125 次工具调用导致目标移出可见窗口后仍更新原用户消息。
- 已查看实际原生窗口的六张截图：`build/ReactionSnapshot/build/reactions-{0,1,2}-{light,dark}.png`。普通回答无表情标记；“你真棒”下方仅显示 😊，没有空白回复；带后续问题的用户消息下方显示 ❤️，同时有正常文字回答。浅色与深色无裁切或多余说明文案。
- `git diff --check`：通过。
- README 中英文能力说明与回归命令已同步；AGENTS.md 无新增架构或持久规则变化，保持不变。

## 验证边界

回归使用固定模型事件驱动实际 AgentModel、ConversationStore 和 SwiftUI/AppKit 窗口，不调用用户配置的远程模型；尚未验证不同模型在真实语境下选择三种形式的稳定性。本次不发布版本或替换已安装应用。
