# 审批模式入口取消按压缩放并调轻菜单按下高亮

## 改动

- `App/Sources/AgentView.swift`：`ApprovalModePicker` 改用 `.buttonStyle(.plain)` 与 `.actionArrowCursor()`，移除 `GlassPressObserverStyle` 与 `glassPointerFeedback`，点击触发器不再产生缩放与回弹效果，同时保留原位呈现、箭头光标与辅助功能标签。
- `App/Sources/GlassPointerFeedback.swift`：`GlassPointerFeedback` 增加 `pressedOpacity` 参数（默认 `0.16` 保持独立玻璃按钮不变），`GlassRowButtonStyle` 将菜单行按下提亮由 `0.16` 调轻至 `0.085`（悬停保持 `0.055`），避免菜单点击时出现过重的亮灰底块。
- `App/Tests/ApprovalMenuRegression.swift`：补充触发器按住无缩放像素差分断言与菜单行按压亮度区间断言（`hover + 0.01 < pressDelta < 0.115`）。
- `docs/design-system.md`：同步记录审批入口点击不缩放及 `GlassRowButtonStyle` 悬停/按下提亮比例。

## 已运行验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：`BUILD SUCCEEDED`。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore`：通过（所有 Swift Testing 与 XCTest 用例均 0 失败）。
- 非激活玻璃预览窗口（无焦点 `NSPanel`，加载最新构建产物与真实 `nativeGlassBackground`、`GlassRowButtonStyle().pressedOpacity`）：在深色与浅色外观下分别截取渲染画面并人工目视核对。深色按下亮度增量 `0.0980`（原截图约 `0.166–0.171`），浅色按下亮度增量 `0.0941`，视觉柔和通透且与未按行区分清晰。

## 未完成 / 边界

- `python3 App/Tests/run-agent-reply-regression.py --approval-menu-hover`：因工作区存在与本任务无关的 `App/Tests/AgentReplyRegression.swift` 在途编译错误，未能直接运行整套脚本；独立编译运行 `ApprovalMenuRegression.swift` 时，因交互窗口在用户当前输入期间被输入法候选条遮挡触发区，未重复抢占焦点重跑交互指针回归。
- 降低透明度、增强对比度、减少动态效果及旧系统材质回退本轮未单独实机验证。
