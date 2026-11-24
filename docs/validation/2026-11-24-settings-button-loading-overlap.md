# 修复 SettingsButton 加载与完成态文字重叠

## 问题与修复

- 在 macOS 26 的 `.glass` 胶囊按钮及禁用状态下，`SettingsPushButton` 通过 `NSColor.clear` 隐藏 `attributedTitle` 会被系统按钮绘制忽略，导致底层原标题（如“保存并检查”）与上层 `overlay` 状态文字（如“检查中…”）或图标重叠；带图标的加载按钮也未清掉原生 `image`。
- 在 [SettingsStyle.swift](../../App/Sources/SettingsStyle.swift) 中改为：
  - `isLoading` 且存在 `loadingTitle` 时，直接将 `NSButton` 的标题切换为 `loadingTitle` 并清掉图标，不再叠加 SwiftUI 文本 overlay；
  - `isComplete` 或无 `loadingTitle` 的加载态时，真正清空 `NSButton.title`、`attributedTitle` 与 `image`，仅由 `overlay` 显示勾号或 `ProgressView`；
  - `sizeThatFits` 通过复用的测量用 `NSButton` 保留原标签与图标的基准宽度（并在 `loadingTitle` 更宽时取较大值），避免按钮切换状态时抖动或裁切。
- 在 [SettingsRegression.swift](../../App/Tests/SettingsRegression.swift) 新增 `--button-states` 原生窗口回归，断言加载态、完成态与图标加载态的原生 `NSButton.title` / `image` 及宽度保持，并导出浅深色截图供视觉核验。

## 实际验证

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-settings-regression.py --button-states`：通过；查看 `build/settings-button-states-light.png` 与 `build/settings-button-states-dark.png`，确认“检查中…”、“保存中…”、完成勾号与图标旋转加载均无文字/图标重叠。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-settings-regression.py --model-check-only`：通过。

README: unchanged — 仅修复按钮加载/完成态样式重叠缺陷，不改变功能范围、使用流程或开发命令。
AGENTS.md: unchanged — 未引入或变更持久性协作规则与架构边界。
