# 玻璃容器内行的悬停/按压反馈统一（2026-11-19）

## 变更
- 新增 `GlassRowButtonStyle`（`App/Sources/GlassPointerFeedback.swift`）：悬停与按下只做白色 `plusLighter` 提亮，不缩放。`glassPointerFeedback` 新增 `scales` 参数。
- 审批模式菜单行与网页来源卡片行改用该样式；来源行不再使用灰色 `kInteractionHover` 底板和按压放大。
- 审批模式菜单玻璃取消 `interactive`，点击时整块菜单不再缩放。

## 已运行检查
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：BUILD SUCCEEDED。

## 未运行
- 未在新构建的实际窗口中目视确认悬停与按压效果，需要人工检查。
