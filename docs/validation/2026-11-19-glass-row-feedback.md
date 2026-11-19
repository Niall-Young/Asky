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

## 追加：局部光斑（2026-11-19 17:56）
- 用户反馈整行平铺提亮像“容器”，范围过大。`GlassRowButtonStyle` 改为跟随指针的径向光斑（固定半径 56 pt，悬停 0.08、按下 0.20，`plusLighter`，按行圆角裁剪），对齐顶部胶囊 `GlassCapsuleIllumination` 的局部提亮。
- 重新运行 `xcodegen generate` 与 Debug `xcodebuild`：BUILD SUCCEEDED。未在实际窗口目视确认。
