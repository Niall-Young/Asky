# AI 输入框退格崩溃验证

11 月 23 日 20:17 至 21:08 的五份 Asky 崩溃报告均记录了同一条调用链。AppKit 执行 `deleteBackward:` 后，`AgentModel.syncDraft(segments:)` 将刚删除的附件放入撤销缓存，随后从当前附件和缓存构建字典。同一附件 ID 出现两次，触发 Swift 运行时断言。引用和粘贴长文本也使用了相同的合并方式。

修复后三类标签按 ID 合并，当前草稿内的值优先。删除附件时保留其临时文件，撤销时可恢复原附件。

## 已执行的检查

- `python3 App/Tests/run-agent-reply-regression.py --composer-backspace` 通过。回归程序使用临时数据目录，在原生 Asky AI 窗口发送退格键事件。光标位于附件右侧时，按退格仅移除该附件，原文件仍可访问。撤销后，附件及各标签的顺序均恢复。整组选中附件、引用和长文本后，删除、撤销、重做和继续编辑普通文本均通过。
- KulaCore 的 `swift test` 通过。`xcodegen generate` 与 Asky 的签名 Debug 构建成功。
- 已从 `build/DerivedData/Build/Products/Debug/Asky.app` 重新启动本机 Debug，并核对新进程的路径。
