# 对话历史设置单行布局

保留时间标签、期限选择框与清空对话历史按钮放在同一行，移除原来两行之间的分隔线。保留已有清空确认、禁用条件与错误反馈。

实际执行并通过：

- `xcodegen generate`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`
- 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- `python3 App/Tests/run-settings-regression.py --conversation-retention`
- `build/SettingsRegression.app/Contents/MacOS/SettingsRegression --conversation-retention -AppleLanguages '(zh-Hans)'`

检查新编译原生设置窗口的英文浅色、深色以及中文浅色截图，确认选择框与清空按钮同排且没有行间分隔线；截图输出位于已忽略的 `build/settings-conversation-history-{light,dark}.png`。回归同时验证期限选项、旧配置默认值、持久化和到期清理。未替换日常安装的应用。

README 与 AGENTS.md 无需修改：本次仅调整已有设置项排列，不改变使用方式、命令或架构边界。工作区已有的其他界面和测试改动保留，不纳入本次提交。
