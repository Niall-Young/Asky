# 对话顶部拖动区域光标

## 闪烁问题的后续修复

用户确认首版仍会在移动鼠标时于箭头和 I-beam 之间闪烁。下方首版记录仅说明当时执行的检查，不能作为问题已解决的证据。

原因：`ActionArrowCursor` 原来在主队列异步设置箭头；被覆盖的 `ChatSelectableTextView` / `ChatSourceTextView` 仍在当前 `cursorUpdate` / `mouseMoved` 事件中先设置 I-beam。等待后检查最终光标会漏掉这个瞬态。

后续实现让原生正文处理光标事件前同步查询同一窗口的可见箭头区域；命中时直接设置箭头并跳过 NSTextView 的正文光标处理。被覆盖的来源标签也不会启动悬停预览。正文未被覆盖时仍走原生处理，现有拖动手势及按钮事件不变。

新增 `--header-cursor-preview` 使用真实 `AgentWindowController` 和长回复，将正文滚到顶部下方，逐次直接派发 120 组 `cursorUpdate` / `mouseMoved`，在同一调用栈中检查光标，再检查未被覆盖的正文恢复 I-beam。

- 修改正文处理前，该检查在 `cursorUpdate` 的瞬态 I-beam 断言失败，复现首版缺陷：`build/header-cursor-before.log`。
- 修改后通过：`build/header-cursor-after.log`。
- 同一编译产物加 `--preview-macos14` 通过：`build/header-cursor-macos14.log`。这是当前系统上的兼容代码路径，不是真实 macOS 14 机器。
- 原有 `--action-cursor-preview` 通过：`build/header-cursor-flicker-actions.log`，覆盖正文恢复、操作按钮点击、选择菜单与来源悬停。
- `xcodegen generate`、README 的 Debug `xcodebuild`、KulaCore `swift test` 均通过：`build/header-cursor-flicker-build.log`、`build/header-cursor-flicker-core.log`。
- 通过 CUA 退出旧 Debug 并重新打开新构建，查看实际聊天窗口。截图不含光标，因此不将截图视为连续鼠标移动无闪烁的视觉验证；本次证据为能让旧代码失败、新代码通过的同步事件回归。
- README: updated，中英文同步增加顶部光标回归及兼容分支命令；本地构建和日志继续由既有 `build/` 规则忽略。

## 首版记录（未解决闪烁）

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
