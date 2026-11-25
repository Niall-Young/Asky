# AI 对话复制消息复用剪贴板 Toast 验证

日期：2026 年 11 月 25 日

## 变更范围

- 对话提示状态管理（[AgentModel.swift](../../App/Sources/AgentModel.swift)）：新增 `toast` 状态、`toastDuration`（3 秒）以及 `showToast(_:duration:)` / `clearToast()`，支持重复复制时重置 3 秒自动消失计时。
- 对话窗口 Toast 呈现与复制触发（[AgentView.swift](../../App/Sources/AgentView.swift)）：在助手消息（含 `toolNarration`）的 `assistantContextActions.copy` 复制成功后调用 `model.showToast(NSLocalizedString("已复制", comment: ""))`；在 `AgentView` 顶层叠加复用剪贴板的 `ClipboardStatusToast`，水平居中显示于窗口内距顶部 48 pt 处，不拦截鼠标事件，支持系统“减少动态效果”并在关闭或重新打开窗口时清理残留状态。
- 原生回归与视觉验证（[AgentReactionRegression.swift](../../App/Tests/AgentReactionRegression.swift)、[AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)）：新增 `--copy-toast-preview` 回归用例，实际点击助手气泡「更多操作」菜单中的「复制」按钮，验证剪贴板内容、浅色与深色模式下的 Toast 位置（距顶 48 pt、水平居中、位于窗口内）、3 秒自动消失与重复复制重置计时。

## 已执行验证

1. 工程生成与 Debug 构建：
   ```sh
   xcodegen generate
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build
   ```
   结果：构建成功。

2. 原生界面回归与视觉验证：
   ```sh
   python3 App/Tests/run-agent-reply-regression.py --copy-toast-preview
   ```
   结果：全部通过。实测浅色与深色模式几何均为 `topOffset=48.0pt`、`centerDrift=0.0pt`、`size=(94.0, 35.0)`，重复复制重置 3 秒计时并在 3 秒后自动消失；实际查看生成的 `build/agent-copy-toast-light.png` 与 `build/agent-copy-toast-dark.png`，确认复用的 `ClipboardStatusToast`（对勾图标 + 「已复制」）在窗口内居中清晰呈现且不遮挡顶栏控件。

3. 核心包自动化测试：
   ```sh
   (cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
   ```
   结果：全部通过（83 tests in 15 suites）。

## 未覆盖范围

- 系统开启“减少动态效果”与英文界面切换下的实时动效观感，已按代码路径适配 `.opacity` 过渡与既有 `"已复制"` 本地化键，可结合日常使用进一步观察。
