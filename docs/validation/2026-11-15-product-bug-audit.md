# 当前产品明显问题检查

后续修复与验证见 [产品检查问题修复](2026-11-15-product-bug-fixes.md)。以下保留检查时的原始结果。

- 源码基线：`05e66559b3e1fce0e630ab1b755508ac6ebcb5a7`，开始时工作区干净
- 环境：macOS 27.0.1（26A434），Apple Silicon，Xcode SDK macOS 27.2
- 范围：当前源码构建、核心测试、启动器、设置、剪贴板、聊天与历史分页；原生窗口使用重新编译的回归程序和独立临时数据库
- 本次只检查并记录，没有修改产品实现或正式回归脚本
- 本地证据：`build/product-audit-2026-11-15/`（已有 Git 忽略规则）

## 已确认的问题

### P2：恢复默认指令绕过重名校验，会把搜索导向另一个网站

实际设置窗口复现：

1. 设置 → 指令 → 内置指令，把 Google 的 `go` 改为 `g2`，回车保存
2. 把 YouTube 的 `yt` 改为 `go`，回车保存
3. 点击 Google 行的“恢复默认”

实际结果：Google 和 YouTube 同时显示 `go`，没有错误提示。回读该测试进程的临时 SQLite，恢复前为 `{"go":"g2","yt":"go"}`，恢复后为 `{"yt":"go"}`；Google 因没有覆盖值而重新使用默认 `go`，冲突会持久保存。

以当前 `Keywords.swift` 编译独立路由探针，`go cats` 在恢复前匹配 YouTube，恢复后匹配 Google。没有实际打开网站或发送网络请求。

原因：`App/Sources/CommandSettings.swift:174` 的 `reset()` 直接删除覆盖值，没有经过 `save()` 使用的 `commandKeywordProblem` 校验；`Packages/KulaCore/Sources/DirectActions/Keywords.swift:95` 只匹配第一个同名指令。

建议：恢复默认也执行完整冲突检查，遇到已占用默认词时保留现有配置并显示冲突原因。验收需覆盖网页指令、分类指令和别名之间的冲突。

证据：`command-reset-conflict.png`、`keyword-routing.log`、`keyword-probe.swift`。

### P3：英文 MCP 撤销按钮错误显示为 Undo

在实际英文设置窗口创建隔离测试实例后，右侧红色按钮显示 `Undo`。该按钮实际执行删除 MCP 实例，而不是撤销上一步操作；应按上下文使用 `Revoke` 或等价明确文案。

依据：`App/Resources/en.lproj/Localizable.strings:136` 将“撤销”统一译为 `Undo`；`App/Sources/SettingsView.swift:802` 的对应动作调用实例删除。此次未点击该删除按钮。

证据：`mcp-controls-after-scroll.png`。

## 检查结果

| 检查 | 结果与范围 |
| --- | --- |
| `Packages/KulaCore` 的 `swift test` | 通过：360 个 Swift Testing 测试及 5 个 XCTest 测试；不同 test target 的汇总分别记录在日志中 |
| `xcodegen generate` + README 的 Debug `xcodebuild` | 通过 |
| 启动器默认原生回归 | 通过：明暗模式、原生滚动、输入焦点、结果更新、窗口几何 |
| 启动器 `--command-entry` | 通过：网页指令、Return/Space、大小写、自定义触发词、Backspace |
| 启动器 `--shell-lifecycle` | 通过：每种外观 100 次会话、滚动视图释放、取消、输入法标记文本 |
| 剪贴板默认回归 | 通过：选择、搜索、固定状态、外观 |
| 剪贴板 `--pagination` | 通过：165 条记录、选择稳定、后一次查询优先、隐藏取消搜索 |
| 聊天默认回归 | 通过：表情、表单生命周期、完整回答、历史恢复、取消、附件、连续时间线 |
| 聊天 `--paging` | 通过：双向分页、最新消息跳转、120 条内存上限 |
| 聊天 `--bottom-push` | 通过：短/长回复自然排列、固定窗口、等待气泡 |
| 聊天 `--prefill-preview` | 通过：预填、修改/清空、重开、提交快照、无自动提交 |
| 设置 `--navigation-settings` | 通过：通用、搜索、剪贴板，以及指令路由/设置持久化检查 |
| 本地化检查 | 失败：4 处历史工具错误字符串未本地化，见下文 |

## 回归失败的归因

不能把这些失败直接当作用户正常操作必然触发的产品故障：

1. **`--alias-routing`**：失败于直接写入 `sc` 快捷指令别名后要求它排第一。当前 `sc` 是内置分类指令，`AliasEditor.validationError` 会拒绝用户从界面创建同名别名。此测试构造了当前 UI 不接受的配置。上面的“恢复默认”缺陷是另一条已实际复现的有效入口。
2. **完整设置回归**：失败于 MCP 复选框检查。当前使用 `LazyVGrid`，离屏时尚未生成复选框；测试只在 macOS 14 兼容分支滚动到下方。实际滚动到页面底部后，calendar、reminders、notes、contacts、chrome、shortcuts、messages 七个控件均正常出现，布局未见断裂。证据见 MCP 截图。完整原始套件仍记为失败。
3. **聊天 `--scroll-stability`**：原始脚本失败于点击“加载更新的消息”。固定坐标仍按旧布局取窗口底部上方 62 pt；当前悬浮输入框使按钮位于约 y=525 pt，旧点击落入输入区域。原始截图 `scroll-newer-button.png` 可直接核对。仅在忽略目录复制诊断脚本，把两个点击分别改到当前“加载更新的消息”和“回到底部”的可见中心 y=525/562 pt，其余断言完全保留，复测通过：三次更早分页、120 条上限、阅读位置、相邻更新页和回到最新消息。这个诊断证明当前布局下功能可操作，不代表原始回归脚本已经修好。

本地化检查的四处问题位于 `HistoryTools.swift:21/24/30` 和 `ToolService.swift:244`，是直接使用中文的历史工具错误文本。已通过检查脚本和源码确认；没有把这些内部工具错误等同于四个用户可见 UI 故障。

## 验证边界

- 已构建主应用，但交互验收使用实际产品组件组成的隔离原生回归窗口，没有启动日常安装版或修改其设置、聊天历史
- 没有调用真实模型 API，未验证真实网络故障、长期 Agent 任务与付费模型兼容性
- 未完整验收 macOS 14/15 实机、正式安装/自动更新、真实跨应用粘贴和文件拖放、系统日历/备忘录写入、多屏窗口移动
- 测试程序部分场景会短暂使用系统剪贴板及输入事件；这不等同于真实第三方应用端到端验收
- 没有检查个人 Chrome 书签内容
- README 保持不变：本次仅新增验证记录，未改变产品功能、开发命令或安装流程
