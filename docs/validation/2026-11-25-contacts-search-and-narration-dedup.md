# 联系人模糊查找修复与工具前重复回复抑制

## 问题与根因

用户反馈两个对话体验问题：
1. **通讯录里明明有联系人（「老爸」），却查不到**：`ContactsBridge.search`（`Packages/KulaCore/Sources/Adapters/PeopleAndHandoffTools.swift`）此前仅使用 `CNContact.predicateForContacts(matchingName:)`。macOS Contacts 框架的该谓词只做词前缀匹配，导致按 `爸` 查找时无法命中 `老爸` / `老爸 Dad` / `张爸爸` 等非前缀包含的联系人，也未完整覆盖昵称与去空格拼接名。
2. **同一轮回复发出两条重复内容气泡**：在本地原生会话记录中，模型在调用 `contacts_search` 的同一轮里先输出了一整段提前下结论并反问用户的文字（`我在通讯录里没找到……你直接告诉我……`），`NativeRuntime` 无条件将其作为 `textDelta` 发出，前端在 `toolCall` 边界将其持久化为永久可见的 `toolNarration` 气泡；随后 `contacts_search` 返回空，模型又输出最终 `assistant` 气泡，界面上紧贴显示两条语义重复的回复。

## 改动内容

- **联系人模糊与多字段查找（`Packages/KulaCore/Sources/Adapters/PeopleAndHandoffTools.swift`）**：
  - 扩展 `ContactsBridge.keys` 拉取 `givenName`、`familyName`、`middleName`、`nickname` 及拼音字段（不拉取需受限权限的 `note` 字段）；`Person` 增加可选 `nickname` 字段（默认 `""` 保持兼容），并在 `fullName` 为空时依次回退 `nickname` 与 `organizationName`。
  - `ContactsBridge.search` 结合 `predicateForContacts(matchingName:)` 与 `CNContactFetchRequest` 统一联系人遍历，经可单测的纯函数 `ContactsBridge.match(query:in:predicateMatchedIDs:limit:)` 按相关性分级排序：精确匹配 > 前缀/词前缀/系统谓词命中 > 姓名与昵称子串命中（如 `爸` 命中 `老爸 Dad`）> 多词组合命中 > 组织/拼音命中 > 号码/邮箱子串命中，且大小写、重音、全半角与空格不敏感。
  - `ContactsSearchTool` 在结果中附带非空 `nickname`，同步更新工具摘要及中英文 `Core.strings`。
- **工具前旁白门控与提示词约束（`Packages/KulaCore/Sources/AgentHost/NativeRuntime.swift`、`NativeAgentPrompt.swift`）**：
  - 新增 `NativeRuntime.shouldEmitPreToolNarration(...)`：禁止在快速本地只读查询（`contacts`、`calendar`、`reminders`、`notes`、`messages`、`chrome`、`shortcuts`、`memory`、`clipboard` 的 `.read` 工具）前把模型文字发布为永久气泡；单轮最多保留一条简短过渡（单段、无代码块/表单围栏、≤140 字），仅用于耗时外部/插件查询、系统写入工具，或 `mid-run-followup` 首轮承接。
  - 更新 `NativeAgentPrompt`：明确将查通讯录等快速本地查询列为静默调用，禁止在调用工具的轮次提前下结论或向用户反问；用户提到具体称呼（如“老爸”）时直接按该词或核心字调用 `contacts_search`。
- **单元测试**：
  - 新增 `Packages/KulaCore/Tests/AdaptersTests/ContactsSearchTests.swift`，覆盖中文子串匹配、排序优先级、昵称/去空格/全半角/重音/多词/组织/拼音/号码邮箱匹配及 `CNMutableContact` 回退提取。
  - 在 `Packages/KulaCore/Tests/AgentHostTests/NativeRuntimeTests.swift` 新增 3 个用例，验证快速本地读抑制提前结论气泡、慢速/写入工具单次简短旁白与多段/表单过滤，以及 `mid-run-followup` 首轮承接保留。

## 实际验证

- `plutil -lint Packages/KulaCore/Sources/Contracts/Resources/en.lproj/Core.strings Packages/KulaCore/Sources/Contracts/Resources/zh-Hans.lproj/Core.strings`：两个文件均 `OK`。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`（工作目录 `Packages/KulaCore`）：退出码 0，全部测试目标通过，包含 `ContactsSearchTests` 及 `NativeRuntimeTests` 新增的 3 个用例。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates -quiet build`：退出码 0（构建通过）。

## 验证范围与说明

- 本次未触碰工作区中同期进行的其他功能改动（`App/` 下文件、`AgentHost.swift`、`WireProtocol.swift` 等）；因工作区存在并行编辑，未单独执行全量 `App/Tests/run-agent-reply-regression.py` 脚本。
- README: unchanged — 未新增或修改开发命令、配置项或对外能力入口。
- AGENTS.md: unchanged — 模块边界、ToolService 路径与构建规则无变更。
