# 产品检查问题修复

对应 [产品检查报告](2026-11-15-product-bug-audit.md)。修复基线为 `5870d1a`，开始时工作区干净。

## 修复内容

- 指令“恢复默认”复用编辑时的重名校验。默认触发词被其他网页指令、分类指令、别名或终端占用时，保留当前配置和输入值并显示既有冲突提示；空闲默认词仍可正常恢复。
- MCP 撤销授权使用独立本地化键，英文显示 `Revoke`，中文仍为“撤销”；编辑菜单的 `Undo` 保持原义。
- 为历史工具的四条错误信息补齐共享中英文本地化，并通过 `CoreLocalization` 返回。
- 别名回归使用当前界面允许的 `daily`，保留大小写、优先级、延迟结果及持久化断言。
- MCP 设置回归在所有系统分支先滚动至底部，再检查惰性生成的七个复选框，保留尺寸和标签断言。
- 聊天分页回归按实际输入框位置计算底部两项操作的点击位置，保持原生鼠标事件与所有分页、消息上限、阅读位置、回到最新消息的断言。
- 完整设置回归后续暴露的权限页标题断言改用当前语言标题，避免英文环境误报。

## 已运行验证

环境：macOS 27.0.1，Apple Silicon，Xcode SDK macOS 27.2。

| 检查 | 结果 |
| --- | --- |
| `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` | 通过：360 个 Swift Testing 测试、5 个 XCTest 测试 |
| `xcodegen generate` 与 README 中 Debug 构建命令 | 通过 |
| `python3 App/Tests/check-localization.py` | 通过：173 个 Swift 文件，中英键、占位符、静态调用及错误字符串检查 |
| `python3 App/Tests/run-settings-regression.py --command-reset` | 通过：原生恢复按钮；五类冲突阻止、一类正常恢复；重开数据库读取设置；YouTube 路由保持 |
| 新编译的 `SettingsRegression --command-reset -AppleLanguages '(zh-Hans)'` | 通过：同样覆盖中文原生界面 |
| `python3 App/Tests/run-launcher-window-regression.py --alias-routing` | 通过：浅色和深色 |
| `python3 App/Tests/run-agent-reply-regression.py --scroll-stability` | 通过：原始正式脚本，无临时坐标补丁 |

本次回归窗口均使用独立临时数据库。已查看中英文冲突提示截图，以及英文 MCP 页的 `Revoke` 与七个复选框截图。

## 完整设置套件的剩余验证限制

新编译的完整 `SettingsRegression` 已越过原 MCP 失败点、明暗两轮所有设置页面、权限页切换与最小窗口尺寸断言，但在后续 `assertAuthorizationSurface` 中调用 `/usr/sbin/screencapture -l` 时失败：

```text
could not create image from window
Fatal error: authorization window capture failed
```

完整设置套件因此仍记为未通过，不把截图失败当作产品权限功能故障，也没有删除断言、跳过捕获或把它改记为通过。授权流程后续部分与卡片拖动未完成。本次没有修改系统屏幕录制权限，也没有重新安装日常使用的 Asky。

## 交付证据

- 新 Debug 应用：`build/DerivedData/Build/Products/Debug/Asky.app`
- 本地日志与截图：`build/product-bug-fixes-2026-11-15/`
- 截图：`command-reset-en.png`、`command-reset-zh.png`、`mcp-revoke-en.png`
- README 已同步中英文恢复默认的行为说明和专项回归命令；开发指南同步专项命令
- 产物使用已有 `build/`、`Asky.xcodeproj/`、`Packages/KulaCore/.build/` 忽略规则，不纳入源码提交

没有发布版本，也未重新验证真实模型联网、跨应用粘贴、正式安装更新或 macOS 14/15 实机。
