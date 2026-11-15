# 引用文本序号验证

日期：2026-11-15

## 行为

- 输入区、发送后的消息及恢复历史均按当前消息内的引用顺序显示「引用的文本 1」「引用的文本 2」等名称；英文对应 Quoted text 1、Quoted text 2。
- 移除后按剩余顺序连续编号，文件和图片不占用引用序号。
- 提交给模型的引用上下文使用相同序号并保留来源消息 ID，历史数据结构不变。

## 已执行

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。既有引用持久化测试增加两段引用的顺序编号及移除首段后的重新编号断言。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- `python3 App/Tests/run-agent-reply-regression.py --selection-preview`：通过，覆盖真实选区菜单添加、去重、输入焦点、发送失败保留及发送后历史恢复。
- 查看新编译原生窗口截图 `build/selection-draft.png`、`build/selection-sent.png`：输入区和历史恢复后的卡片均完整显示「引用的文本 1」，图标及卡片布局保持原样。
- `git diff --check`：通过。截图与构建产物沿用已有 `build/` 忽略规则。

## 验证范围

本轮原生截图覆盖单段引用；多段引用的顺序与删除后重新编号由上下文单测和 UI 枚举代码检查覆盖，未单独执行多卡片 UI 点击回归。原生预览使用测试会话和缺失凭证验证发送失败分支，未请求真实模型，未替换已安装的应用。
