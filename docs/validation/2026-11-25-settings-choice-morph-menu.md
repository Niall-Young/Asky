# 2026-11-25 设置页液态玻璃变形选择菜单验证

## 变更范围

- 新增 [SettingsChoiceMenu.swift](../../App/Sources/SettingsChoiceMenu.swift)：实现 `SettingsChoice` 原位变形液态玻璃选择菜单组件（`SettingsChoiceLayout`、`SettingsChoiceMenuPlacement`、`SettingsChoiceTriggerLabel`、`SettingsChoiceTriggerButtonStyle`、`SettingsChoiceRowButtonStyle`、`SettingsChoiceAnchorView`、`SettingsChoiceOverlay`、`SettingsChoicePresenter`）。
- 更新 [SettingsStyle.swift](../../App/Sources/SettingsStyle.swift)：将 `SettingsChoice` 由 `NSPopUpButton` 替换为 `28 pt` 原生 Regular 液态玻璃胶囊按钮，点击后在 `NSWindow.contentView` 顶层原位变形展开为 AI 对话风格液态玻璃菜单，保持原有 `SettingsChoice` 调用签名不变（覆盖全部设置页及设置弹窗选择项）。
- 更新 [SettingsRegression.swift](../../App/Tests/SettingsRegression.swift)：适配现有 4 项设置回归用例到 `SettingsChoiceAnchorView`，并新增 `--choice-menu` 回归模式验证零 `NSPopUpButton`、顶层覆盖层挂载、展开/选中/关闭生命周期及浅深色窗口实拍截图。
- 更新 [design-system.md](../design-system.md)：记录 `SettingsChoice` 液态玻璃按钮与原位变形菜单规范。

## 实际运行的检查

1. **Xcode 工程生成与 App 构建**
   - `xcodegen generate`：通过。
   - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：**BUILD SUCCEEDED**。
2. **核心单测**
   - `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：**PASSED**（16 suites，91 tests 全部通过）。
3. **设置选择菜单专项回归与实际窗口视觉验收**
   - `python3 App/Tests/run-settings-regression.py --choice-menu`：**PASSED**（`Settings choice menu: morphing glass overlay, zero NSPopUpButton, selection, close and light/dark renders passed`）。
   - 使用 `screencapture` 截取新构建窗口并人工核验浅色 / 深色渲染（`build/settings-choice-data-closed-light.png`、`build/settings-choice-data-closed-dark.png`、`build/settings-choice-data-open-light.png`、`build/settings-choice-data-open-dark.png`、`build/settings-choice-general-open-light.png`、`build/settings-choice-terminal-open-dark.png`）：
     - 首轮截图发现两处问题并已修复复验：
       1. `SettingsWindow` 的 `.unified` 工具栏顶部安全区导致顶层 `NSHostingView` 菜单整体下移约 `52 pt` → 为覆盖层设置 `hostingView.safeAreaRegions = []` 并在 SwiftUI 根容器加 `.ignoresSafeArea()`，复验对齐精确。
       2. 行内 `HStack(spacing: 8)` 在 `Spacer(minLength: 12)` 两侧多计 `16 pt` 导致「Follow System」「System Terminal」出现省略号 → 改为 `HStack(spacing: 0)` 显式间距、文本 `.layoutPriority(1)` 并同步精确宽度计算，复验全部标题完整显示。
4. **既有设置回归用例**
   - 使用新编译产物 `build/SettingsRegression.app/Contents/MacOS/SettingsRegression` 运行：
     - `--agent-prompt`：**PASSED**（首次运行因窗口聚焦时外部杂散输入触发 `editor.string.isEmpty` 前置断言，立即重跑通过）。
     - `--conversation-retention`：**PASSED**。
     - `--clipboard-retention`：**PASSED**。
     - `--navigation-settings`：**PASSED**。
5. **本地化脚本**
   - `python3 App/Tests/check-localization.py`：退出码 1，报错为既有无关的重复 key `剪贴板历史`（`en.lproj` 与 `zh-Hans.lproj`），本次改动未涉及本地化字符串文件。

## 未覆盖边界

- macOS 14 / 15 实机旧材质回退、`减少透明度`、`增强对比度` 与 `减少动态效果` 的实机视觉与交互尚未在目标系统实机验收，当前仅通过代码路径与 macOS 26 本机常规外观验证。
