# 设置“智能配置”分组侧栏图标更新验证（2026-11-25）

## 变更摘要

按要求将设置侧栏“智能配置”分组的四个图标统一更新为对应 MingCute 线性模板矢量资产：

- 模型配置（`Settings-model`）：保持 MingCute `ai`
- 智能体（`Settings-data`）：新增 `App/Artwork/bot-message-square.svg`（来自上游 MingCute Icons `9dc7d3ad074fb16477096a6a8109a6467d0e2fe3` 的 `bot_message_square`，Apache-2.0），替代原 `MingCute-brain`
- 数据来源（`Settings-sources`）：从 `layers` 替换为 MingCute `coin_2`
- MCP（`Settings-mcp`）：新增 `Settings-mcp` 使用 MingCute `mcp`，替代原 `MingCute-link`

同步简化 [SettingsWindow.swift](../../App/Sources/SettingsWindow.swift) 中的 `SettingsPage.iconAsset` 为 `"Settings-" + rawValue`，并在 [SettingsRegression.swift](../../App/Tests/SettingsRegression.swift) 中校验四项的资产映射及 `NSImage` 加载。

## 已执行检查

1. `python3 scripts/import-mingcute-icons.py <mingcute-checkout@ca98bb55>`：成功导入 78 个 MingCute 符号与 18 个设置/功能资产别名，更新 `App/Resources/ThirdParty/MingCute/NOTICE`。
2. `(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)`：通过。
3. `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：构建通过。
4. `python3 App/Tests/run-settings-regression.py --agent-prompt`：通过，新增四项 `SettingsPage.iconAsset` 及 `NSImage(named:)` 校验全部通过。
5. 人工检查新构建原生设置窗口的浅色与深色截图（`build/settings-agent-collapsed-light.png`、`build/settings-agent-collapsed-dark.png`）：四个侧栏图标顺序、线条粗细与选中/未选中模板着色均正常。
