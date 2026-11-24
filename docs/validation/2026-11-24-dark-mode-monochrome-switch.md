# 暗色模式开关与黑白强调色对比度修复验证（2026-11-24）

## 问题与根因

- 暗色模式下，`SettingsPalette.monochromeTint(.dark)`（`sRGB 0.46, 0.47, 0.51`）、`CompatibleGlassButtonStyle` 的暗色主按钮染色与 `AccentColor.colorset` 暗色项（`0.431, 0.443, 0.478`）偏暗且略带蓝紫偏色。
- 在 macOS 原生 `NSSwitch`（`.toggleStyle(.switch)`）暗色渲染中，该灰紫色被进一步压低，开启态轨道仅约 RGB `(120, 122, 131)`，与关闭态 `(92, 92, 91)` 亮度差仅约 30 级，视觉上显得发淡且偏灰紫。

## 变更范围

- [`App/Sources/SettingsStyle.swift`](../../App/Sources/SettingsStyle.swift)：将 `SettingsPalette.monochromeTint(.dark)` 调整为纯中性亮白 `Color(.sRGB, white: 0.96, opacity: 1)`，浅色模式保持原有深墨色不变。
- [`App/Sources/NativeGlassBackground.swift`](../../App/Sources/NativeGlassBackground.swift)：`CompatibleGlassButtonStyle` 改为直接复用 `SettingsPalette.monochromeTint(scheme)`，消除重复色值定义。
- [`App/Assets.xcassets/AccentColor.colorset/Contents.json`](../../App/Assets.xcassets/AccentColor.colorset/Contents.json)：暗色外观同步更新为纯中性 `0.960 / 0.960 / 0.960`，与 SwiftUI 控件染色一致。

## 视觉对比与实测结果

- 保留原生 `.toggleStyle(.switch)`（`NSSwitch`）与液态玻璃开关交互，不重写控件行为。
- 实窗截图确认：暗色模式激活态下，开启开关轨道提升至系统原生单色上限的纯中性亮银白（无蓝紫偏色，相对关闭态亮度差提升约 3 倍），同时指令页复选框在暗色下自动反转为亮白底配深色勾选，与浅色模式黑底白勾对称；浅色模式开关与复选框保持不变。

## 实际运行的检查

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：全部通过（含 `ToolServiceTests`、`ContractsTests` 及 15 个 Swift Testing 套件共 83 项测试）。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO`：通过（`** BUILD SUCCEEDED **`）。
- `python3 App/Tests/run-settings-regression.py --settings-chrome`：通过，并检查了 `build/settings-chrome-dark-active.png` 与 `build/settings-chrome-light-active.png`。
- `python3 App/Tests/run-settings-regression.py --button-states`：通过。
- `python3 App/Tests/run-settings-regression.py --plugin-tabs`：通过。
- `python3 App/Tests/run-settings-regression.py --navigation-settings`：通过，并使用独立编译的 `SettingsRegression --preview --dark` 激活态实窗截图核对了「通用」页暗色模式开启/关闭开关对比效果。
