# AI 回答引用回复按钮

## 变更

- AI 完整回答的复制按钮右侧增加回复图标，复用 MingCute `chat_2`、28 pt 点击区域和现有按钮样式。
- 点击调用现有 `addQuote`：引用全文并记录来源消息 ID，聚焦输入框，保留草稿；同一回答重复点击去重，不自动发送。
- 引用沿用现有可移除标签、发送上下文及历史保存路径；中英文辅助功能名称与悬停提示同步。

## 实际验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过，日志 `build/reply-button-build.log`。
- 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，日志 `build/reply-button-core-tests.log`。首次未指定 Xcode 路径时，Command Line Tools 环境因找不到 XCTest 失败；指定完整 Xcode 后通过。
- `python3 App/Tests/run-agent-reply-regression.py --selection-preview`：通过，日志 `build/reply-button-ui-tests.log`。新增原生窗口鼠标点击覆盖全文引用、来源 ID、重复点击去重、保留草稿、不自动发送、聚焦输入框。既有回归覆盖浅色/深色五种头像色、公式源码、引用菜单、发送失败保留、发送及历史恢复。
- 已查看新构建原生窗口截图 `build/selection-whole-reply.png`，确认回复与复制同行、引用标签和草稿可见。
- `git diff --check`：通过。构建、日志与截图复用现有 `build/` 忽略规则。

## 验证范围

通过本地原生回归窗口检查交互和持久化，未向真实模型服务发送请求，未替换已安装的应用或发布 Release。
