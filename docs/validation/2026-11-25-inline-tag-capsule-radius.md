# 行内 Tag 胶囊圆角调整

## 改动

- 在 `App/Sources/InlineTagAttachment.swift` 调整行内 Tag 几何常量：
  - 外壳圆角 `cornerRadius` 由 `7 pt` 调整为 `(pillHeight - 1) / 2`（`10.5 pt`，即 `21 pt` 可视底板的完整胶囊圆角），与 `22 pt` AI 输入框（约 `12 pt` 内缩，同心半径 `10 pt`）及 `21.5 pt` 用户气泡外圆角保持协调。
  - 图片缩略图圆角 `thumbCornerRadius` 由 `4 pt` 调整为 `thumbSize / 2`（`8 pt` 圆形），`thumbLeadingPadding` 由 `3 pt` 调整为 `2.5 pt`，与 `21 pt` 胶囊左端保持上下左一致的 `2.5 pt` 同心留白。
  - 图标左侧内距 `iconLeadingPadding` 由 `6 pt` 调整为 `7.5 pt`，尾部内距 `trailingPadding` 由 `7.5 pt` 调整为 `9 pt`，避免文字与图标贴近胶囊圆弧。
- 同步更新 `docs/design-system.md` 中行内 Tag 的圆角与内距规范。

## 已执行

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（91 tests in 16 suites passed）。
- `xcodegen generate`：成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：构建成功（`** BUILD SUCCEEDED **`）。
- `python3 App/Tests/run-agent-reply-regression.py --composer-inline-tag-styles`（并输出实际窗口渲染图核对浅色／深色与悬停态）：通过（`Composer inline tag styles regression passed`）。
- `python3 App/Tests/run-agent-reply-regression.py --inline-tag-alignment`：通过（`Inline tag alignment passed: leadingRect=(0.0, 0.0, 113.0, 27.2), midRect=(140.78210116731518, 0.0, 152.00000000000003, 27.2), soloRect=(0.0, 0.0, 144.0, 22.0)`）。
- 视觉检查实际渲染图（浅色正常态、深色悬停态）：输入框与用户气泡内的回复、图片、文件、粘贴文本与划词引用 Tag 均呈完整胶囊形态，圆形图片缩略图与胶囊左端同心，悬停 `✕` 替换图标与右侧文字留白均衡、无裁切。
