# 2026-11-25 设置页下拉选择液态玻璃形变动画修复验证

## 根因定位

1. **首帧未提交即展开**：`SettingsChoicePresenter.present()` 每次新建 `SettingsChoiceOverlay`（`NSHostingView`）后，在 `.onAppear` 中通过 `DispatchQueue.main.async` 设置 `model.isExpanded = true`；该回调在当前 `CATransaction` 首次提交到窗口服务器前即执行，导致收起态胶囊从未被绘制，展开直接跳变。
2. **`if/else` 分支切换未形成连续液态玻璃形变**：原先依赖 `if model.isExpanded` 在两个包装过 `.nativeGlassBackground` 的视图之间用 `.glassEffectID` + `.glassEffectTransition(.matchedGeometry)` 切换，在新建覆盖层中实测展开 `65 ms` 与收回 `70 ms` 中间帧均已瞬间完成，无形变过程。

## 变更范围

- 更新 [SettingsChoiceMenu.swift](../../App/Sources/SettingsChoiceMenu.swift)：
  - `SettingsChoiceOverlayView` 改为与 `AgentAvatarPicker` 一致的单一连续原生液态玻璃表面（`GlassEffectContainer` 内保持同一 `RoundedRectangle(cornerRadius: 14)` `.glassEffect(.regular, in:)` 表面；28 pt 收起高度时半径 14 pt 与胶囊完全一致），通过弹簧动画连续形变宽高，前景内容置于 `.overlay` + `.clipShape` + `.glassEffect(.identity)` 内平滑淡入淡出。
  - `SettingsChoicePresenter.present()` 先执行 `layoutSubtreeIfNeeded()`、`displayIfNeeded()` 与 `CATransaction.flush()` 提交收起态首帧，延迟一帧（`16 ms`）后再以 `withAnimation(.spring(response: 0.28, dampingFraction: 0.72))` 展开；关闭时以 `withAnimation(.spring(response: 0.22, dampingFraction: 0.86))` 缩回并在动画完成后移除覆盖层；降低透明度、增强对比度、旧系统与减少动态效果沿用对应回退路径。
- 更新 [SettingsRegression.swift](../../App/Tests/SettingsRegression.swift)：将 `--choice-menu` 等待窗口调整至匹配新的展开/收回动画时长（`380 ms` / `360 ms`）。

## 实际运行的检查

1. **核心单元测试**
   - `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：**PASSED**（16 suites / 91 tests，0 failures）。
2. **主工程构建**
   - `xcodegen generate`：**PASSED**。
   - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/ChoiceMorphDerivedData -skipPackageUpdates build`：**BUILD SUCCEEDED**。
3. **设置选择菜单回归与中间帧视觉核验**
   - 使用隔离源码快照与 `build/ChoiceMorphDerivedData` 编译并运行 `SettingsRegression --choice-menu`：**PASSED**（`Settings choice menu: morphing glass overlay, zero NSPopUpButton, selection, close and light/dark renders passed`）。
   - 实拍对比 `65 ms` 展开中间帧（`build/settings-choice-data-opening-mid-light.png`）与 `70 ms` 收回中间帧（`build/settings-choice-data-closing-mid-light.png`），确认液态玻璃表面在展开与收回过程中均可见连续的尺寸形变与内容淡入淡出。

## 未覆盖边界

- macOS 14 / 15 旧材质、`减少透明度`、`增强对比度` 与 `减少动态效果` 仅核对代码路径，未在对应系统或辅助功能开关下实机截屏验证。
