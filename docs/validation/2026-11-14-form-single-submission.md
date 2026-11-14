# 原生表单一次提交与历史恢复

## 行为

- 未提交表单不因后续用户/助理消息或重开历史而失效；删除所属历史时一起删除。未提交字段草稿仍遵循现有规则，仅保留在当前打开会话中。
- 提交时以单个 SQLite 事务保存用户回复和原始表单的字段快照。空答案字典也表示已提交，重复提交在模型和存储层都被拒绝。
- 提交后全部控件只读，原选择与自填内容保留，提交按钮可见且禁用。请求失败、重开原始历史分段或删除后续回复都不会解锁。
- 保存失败回滚，不消费表单。输入框草稿和待发送附件不随表单发送。

## 已执行检查

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：346 项测试通过，包括新增事务回滚、重复提交、磁盘重开、空答案和删除后续回复回归。
- `xcodegen generate`，随后按 README 的 `xcodebuild` Debug 命令构建：通过。
- 原生窗口回归 `run-agent-reply-regression.py --forms-preview --custom-preview`：通过。检查原生输入、自填切换、未提交生命周期、提交后答案不可覆盖、历史恢复、请求失败后的单次提交、删除后续回复后的锁定，以及实际 NSButton 禁用状态和 NSTextField 原答案显示。
- 检查新构建回归窗口的实际截图：原选择与自填答案可见，全部字段及「提交回复」按钮禁用，无新增解释性页面文案。
- `git diff --check`：通过。

首次原生回归编译期间，另一个正在进行的聊天布局任务修改了同一测试文件，Swift 报 input file was modified during the build。后续将当前 App 源码及测试复制到被忽略的 `build/form-submission-verification/`，使用 `ASKY_DERIVED_DATA` 指向已构建的 Debug 依赖，在稳定快照中重新编译并运行通过；未覆盖其他任务的源码或暂存内容。截图位于 `build/form-submission-verification/build/form-submitted-readonly.png`。

## 验证边界

测试使用隔离数据及缺失的测试凭证，确认请求失败后也不会重复提交；未发送真实模型请求。未安装替换日常使用的应用，也未发布版本。新版提交会保存结构化答案；旧版历史此前没有保存字段快照，本次没有从普通文字回复猜测或迁移旧答案。

README 已同步中英文行为；AGENTS.md 未变更，现有模块边界与检查命令仍适用。构建产物、快照和截图沿用现有忽略规则。
