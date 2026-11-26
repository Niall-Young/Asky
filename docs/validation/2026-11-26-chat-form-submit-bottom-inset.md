# 表单提交按钮下边距对齐右边距验证

日期：2026-11-26。调整对话气泡内表单提交按钮的底部间距，使有按钮场景下的按钮下边距与右边距一致（均为 `16 pt`）：

- 在 `ChatReplyView` 中为末尾分片透传 `isTrailingPart`。
- 在 `ChatFormView` 显示「提交回复」按钮且位于气泡末尾时，补充 `AgentLayout.messageHorizontalInset - AgentLayout.messageVerticalInset`（`4 pt`）的下边距，使按钮下边距由 `12 pt` 增至 `16 pt`，与气泡右边距对齐；无提交按钮的场景维持原有 `12 pt` 下边距不变。

## 实际执行结果

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate && xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`：成功（`BUILD SUCCEEDED`）。
- `python3 App/Tests/run-agent-reply-regression.py --forms-only`：通过（表单生命周期、单字段表单与原生表单 UI 回归全部通过）。

## 已查看的实际窗口截图

- 多字段带提交按钮表单：[form-complete.png](../../build/form-complete.png)
- 单字段多选带提交按钮表单：[form-single-multi-selected-light.png](../../build/form-single-multi-selected-light.png)
- 单字段单选无提交按钮表单：[form-single-radio-light.png](../../build/form-single-radio-light.png)
