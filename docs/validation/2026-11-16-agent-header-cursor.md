# 对话顶部拖动区域光标

## 修改

- `AgentView.header` 在现有拖动手势之后应用 `actionArrowCursor()`，让顶部 64 pt 区域覆盖下层可选正文的 I-beam 光标。
- 复用现有原生光标区域处理，不改变命中测试、拖动手势、头像、按钮或正文选择逻辑。

## 验证

- `xcodegen generate`：通过。
- README 中的 Debug `xcodebuild` 命令：通过；日志 `build/header-cursor-build.log`。
- `Packages/KulaCore` 的 `swift test`：通过（XCTest 3 项及 Swift Testing 62 项）；日志 `build/header-cursor-core-tests.log`。
- `python3 App/Tests/run-agent-reply-regression.py --action-cursor-preview`：首次运行在正文 I-beam 断言处失败；当时旧版聊天窗口仍置顶，且验证期间进行了其他界面操作。未将本次结果记为通过，也未确定失败原因。
- 重新打开 Debug 后，在没有其他自动界面操作的情况下直接运行同次编译产物 `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --action-cursor-preview`：通过。覆盖正文/操作控件之间光标切换、选择菜单、来源标签及返回正文；日志 `build/header-cursor-regression-retry.log`。
- 退出旧进程，启动最新 `build/DerivedData/Build/Products/Debug/Asky.app --show-agent`，核实新进程 PID 57958。通过 CUA 查看实际对话窗口，执行顶部区域拖动后界面正常，未出现正文选区。
- 限制：现有回归验证共享光标处理，不直接断言完整 Agent 顶部区域；CUA 截图不包含光标，未独立截取顶部实际光标或测量拖动位移；未运行 macOS 14 兼容模式。

## 文档与产物

- README: unchanged。仅修正顶部光标，不改变使用方式、功能或构建命令。
- 构建及回归产物沿用现有 `.gitignore` 的 `build/` 规则。
