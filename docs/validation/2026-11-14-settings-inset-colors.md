# 设置内嵌列表颜色同步

内嵌列表仍使用 `.quaternary.opacity(0.5)`，未随输入框更新。`SettingsInsetBox` 改为复用 `settingsInputChrome`，让排除项和授权备忘录文件夹列表使用输入框的底色及边框，保留 8pt 圆角和原有布局。

## 已执行验证

- `xcodegen generate`：通过。
- README 中的 Debug `xcodebuild` 命令：通过，日志 `build/settings-inset-build.log`。
- `Packages/KulaCore` 中执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，43 tests，日志 `build/settings-inset-core-test.log`。
- `python3 App/Tests/run-settings-regression.py --settings-chrome -AppleLanguages '(zh-Hans)'`：未通过，首次在窗口 key 状态断言失败；再次运行已编译回归在恢复 key 状态断言失败。未记为通过。
- 使用新编译的 `SettingsRegression.app --preview` 打开剪贴板页面，实际检查内嵌列表已经出现共享输入表面的描边及填充。仅完成当前外观视觉检查，未完成浅深色与失焦状态的完整验收。
- `git diff --check`：通过。

README: unchanged，仅同步已有控件颜色，使用方式与开发命令不变。
AGENTS.md: unchanged，无架构、工作流或持久规则变化。
日志和预览产物沿用现有 build/ 忽略规则。保留其他任务对 AgentView、SettingsView 和 AgentReplyRegression 的修改。未安装或发布正式版。
