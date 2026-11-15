# 整条消息回复预览

## 变更

- 保留卡片左图右文布局、52 pt 高度、圆角与移除操作；宽度加到 304 pt，右侧 224 pt 文字区域最多两行并尾部省略。
- 卡片使用项目固定版本 MingCute `chat_1` 带横线聊天图标，Markdown 预览转为可读文字，原生表单预览使用标题，发送仍保留完整原文。
- `MessageQuote.kind` 区分文字选区和整条消息回复。回复类型随消息保存与恢复；旧记录没有此字段时按文字选区引用解码，保持原编号标签样式。
- 回复按钮本身的回转箭头与紧凑间距由并行任务提交 `596b586` 提供，本次保留，回归点击位置同步到当前布局。

## 已运行检查

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过，日志 `build/reply-preview-build.log`。
- 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，日志 `build/reply-preview-core-tests.log`，包含回复类型持久化、旧引用兼容解码及模型上下文全文测试。
- `python3 App/Tests/run-agent-reply-regression.py --selection-preview`：通过，日志 `build/reply-preview-ui-tests.log`。覆盖实际回复按钮点击、全文引用、回复类型、去重、保留草稿、聚焦，以及原有文字选择、发送和历史恢复路径。
- 已查看 `build/selection-whole-reply-NSAppearanceNameAqua.png` 与 `build/selection-whole-reply-NSAppearanceNameDarkAqua.png`，确认左右顺序、横线聊天图标、两行文字与省略效果。外观切换后等待 700 ms 再截图，避免记录过渡帧。
- `git diff --check`：通过。下载的图标源压缩包、构建输出、日志与截图沿用已有 `build/` 忽略规则。

## 范围

验证新构建的原生回归窗口及本地持久化；未调用真实模型服务、替换已安装应用或发布版本。
