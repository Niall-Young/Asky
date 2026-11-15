# 来源卡片按钮反馈

- 来源条目直接复用 `AgentIconButtonStyle(cornerRadius: 8)`：语义悬停底色、箭头光标和共用的按下放大/松开回弹反馈；减少动态效果设置沿用现有处理。
- 把原有留白分配到条目内边距与 4 pt 外边距，扩大点击区域并为按压效果保留空间。卡片仍为 300 pt 宽，文字总留白仍为左右 12 pt、上下 10 pt；多来源条目间隔不变。
- 点击仍由原来的 SwiftUI Link 打开原文。

## 实际验证

- `xcodegen generate` 与 README Debug `xcodebuild`：通过。
- `Packages/KulaCore` 下执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：62 项通过。
- `python3 App/Tests/run-agent-reply-regression.py --sources-preview`：通过，覆盖来源悬停/点击展开、分组、长列表滚动、浅色/深色定位和紧凑尺寸。已检查新生成的深色 Kimi 卡片截图，静态布局保持不变。
- 同次编译出的 `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --action-cursor-preview`：首次在既有正文光标断言失败，发生于新卡片用例之前；未改代码重跑通过，包括 tag/卡片/正文光标切换。未确定首次失败原因，不将首次运行记为通过。
- Debug 包 `codesign --verify --deep --strict`：通过。已结束旧 Debug 进程，从项目构建路径重新启动并携带 `--show-agent`；以新 PID 和进程路径确认。
- `git diff --check`：通过。

README: unchanged，本次复用已有按钮反馈，来源功能、卡片尺寸和命令不变。只提交来源卡片与本记录；任务开始已有的消息回复等改动保持原样。日志、截图与构建产物沿用 `build/` 忽略规则。未单独录制悬停/按压动画或在用户原会话中点击外链。
