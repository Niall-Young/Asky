# 气泡内轻量化表单与单项免提交优化验证

日期：2026-11-26。根据用户评审反馈完成以下 AI 对话气泡内表单（`asky-form`）轻量化收敛：

- **移除冗余表单标题**：
  - `ChatFormView` 不再渲染 `form.title`，避免与气泡正文重复；同时收紧纵向与控件间距（正文到表单 `12 pt`、字段间 `14 pt`、标签到控件与选项间 `6 pt`），多字段标签调整为轻量 `13 pt medium`。
  - `ChatForm.title` 改为可选，`ChatFormParser` 支持无 `{"title":...}` 头行直接输出字段 JSON，同时保持对历史带标题消息的完整兼容。
  - `ChatForm.reply` 不再在发送消息前拼入表单标题；单字段表单直接发送干净的答案文本（如 `页面加载缓慢`），多字段表单直接输出 `标签：答案` 行。
- **单字段表单免标签与免提交按钮**：
  - 当气泡已有正文且表单仅含 1 个字段时，自动隐藏字段标签（保留无障碍标签与输入框占位符；若无正文则回退显示字段标签）。
  - 单字段 `radio` 不显示提交按钮，点击预设选项后立即提交；若开启 `allowCustom: true`，点击「自己填写」展开输入框并支持回车或点击提交。
  - 单字段 `radio` 之外的所有表单（含单字段 `multi`、`text`、日期/时间类以及多字段表单）均保留提交按钮（单字段 `text` 同时支持回车提交）。
- **同步系统提示词**：
  - `NativeAgentPrompt` 更新为不再输出 `{"title":...}` 头行，引导模型在正文自然提问后直接附单字段或多字段 `asky-form`。

## 实际执行结果

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：全部通过。
- `App/Tests/ChatFormParserRegression.swift`：通过（含无标题单/多字段解析、流式逐字解析不泄漏 JSON、历史带标题兼容、单字段纯净回复与多字段无标题回复）。
- `xcodegen generate` + Debug `xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：成功（`BUILD SUCCEEDED`）。
- `python3 App/Tests/run-agent-reply-regression.py`：
  - `--forms-only`：通过（新增 `singleFieldFormRegression`，验证单字段 `radio` 无提交按钮且点击立即提交、单字段 `multi` 保留提交按钮且勾选不自动提交）。
  - `--forms-only --radio-preview`：通过。
  - `--forms-only --custom-preview`：通过。

## 已查看的实际窗口截图

- 单字段单选（无标题、无标签、无提交按钮）：[form-single-radio-light.png](../../build/form-single-radio-light.png)
- 单字段多选（初始无提交按钮 / 勾选后按需显示提交按钮）：[form-single-multi-initial-light.png](../../build/form-single-multi-initial-light.png)、[form-single-multi-selected-light.png](../../build/form-single-multi-selected-light.png)
- 多字段气泡内表单（无标题、轻量间距与标签）：[form-complete.png](../../build/form-complete.png)

本次未调用真实模型。
