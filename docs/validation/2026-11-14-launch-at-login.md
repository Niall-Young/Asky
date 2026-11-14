# 登录时启动：状态回读与本机诊断

## 实际发现

- 本机 `/Applications/Asky.app` 是 0.2.10（build 50），标识为 `app.kulahere.KulaHere`。
- macOS `loginwindow` 日志显示：2026-11-14 20:26:46 执行 `performAutolaunch`，目标为仓库的 `build/DerivedData/Build/Products/Debug/Asky.app`，随后有该应用的 check-in 记录。因此这次登录并非完全没有执行启动，而是启动了开发构建。
- Debug 与正式安装使用相同 bundle identifier。本次没有改动标识及签名策略；不能把状态反馈修复等同于解决多副本的 Launch Services 选择。
- 正式安装在 21:02:29 出现启动记录，21:03:01 正常进入 AppKit 退出流程；没有发现对应的 Asky 崩溃报告。不能据此判断退出由谁触发。
- 开始及结束诊断时，`sfltool dumpbtm` 的对应记录均显示 `enabled, allowed, notified`，URL 为 `/Applications/Asky.app`（系统仍显示旧名称 KulaHere）。当前路径不代表本次登录时的历史路径。

## 修复

- ToolService 保留 enabled、notRegistered、requiresApproval、notFound 和未知状态；注册或注销后回读，无法确认结果时报告错误。
- 已启用与等待批准时不重复注册；菜单栏开启操作遇到待批准状态时进入系统登录项设置。
- 通用设置开关仅在系统确认 enabled 时开启。待批准、找不到项目或未知状态提供对应反馈和系统设置入口。
- 页面出现、应用重新激活或窗口重新获得焦点时刷新状态。采用显式 Binding setter，程序更新状态不再触发第二次系统写入。
- 首次安装一次性注册及旧安装保留系统选择的策略不变。
- 中英文 README 与错误反馈同步。

Apple 对状态与注册行为的定义：[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)、[enabled](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/enabled)。注册完成与获准运行不能混为一谈。

## 检查

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，328 tests / 68 suites。新增 8 个测试方法覆盖状态映射、待批准、幂等、撤销待批准、缺失注册恢复、失败不反向写入及无有效回读结果。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- `python3 App/Tests/run-settings-regression.py --general-defaults`：通过，验证首次安装、仅注册一次、失败重试、重开及旧设置保留。
- 中英文 `Localizable.strings` 的 `plutil -lint`：通过。
- `git diff --check`：通过。

## 验证边界

没有注销或重启用户会话，没有切换真实登录项，没有覆盖 `/Applications/Asky.app`，没有发布新版本。未实测新版 UI 与系统批准页往返；自动化覆盖使用注入的系统状态。下一次真实登录及多副本情况下的系统选择仍需现场验证。

README: updated — 同步中英文登录项状态与审批恢复说明。

AGENTS.md: unchanged — 系统调用仍由 ToolService 管理，未新增构建入口或模块边界。
