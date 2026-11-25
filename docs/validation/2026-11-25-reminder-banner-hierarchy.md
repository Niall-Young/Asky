# 提醒卡片文案间距与三层信息层级调整

- 变更文件：`App/Sources/ReminderBanner.swift`
- 调整内容：
  - 将卡片信息区各文案模块间间距统一调整为 `6 pt`（单段正文 `标题 ↔ 正文` 由 `3 pt` 调整为 `6 pt`；三层结构 `标题 ↔ 时间/地点元数据` 由 `3 pt` 调整为 `6 pt`、`时间/地点元数据 ↔ 说明正文` 由 `4 pt` 调整为 `6 pt`）
  - 强化三层结构的信息层级：时间/地点元数据首行调整为 `14 pt medium`、启用 `.monospacedDigit()` 并提升至 `kText` 92% 对比度；下方说明正文调整为 `12.5 pt regular` 与 `kTextSubtle` 84% 柔弱对比度，与标题（`15 pt semibold`）和元数据首行形成清晰的三级递减层级
- 验证：
  - `xcodegen generate` 与 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build` 通过
  - `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` 全部通过（86 tests in 15 suites）
  - 启动新构建 `build/DerivedData/Build/Products/Debug/Asky.app/Contents/MacOS/Asky --test-banner` 并截取真实窗口检查（`build/reminder-redesign/preview-v4.png`，位于已忽略目录），确认双卡片 `6 pt` 文案间距及三层卡片 `标题 → 14pt 时间地点 → 12.5pt 弱化说明` 层级清晰
