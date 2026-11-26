# 行内 Tag 字号与正文基线对齐调整

## 改动

- 在 [InlineTagAttachment.swift](../../App/Sources/InlineTagAttachment.swift) 将行内 Tag 的 `labelFont` 从 `12.5 pt` 调整为 `14 pt`（常规字重），与输入区（`ComposerTextView.bodyFont`）及用户消息气泡正文（`UserInlineNativeText`）保持一致。
- 将 `pillYOffset` 直接基于 `labelFont` 计算（`-6.0 pt`），并将 Tag 内文字绘制基线 `baselineY` 锁定为 `-Self.pillYOffset`（`6.0 pt`），确保行内 Tag 文案与相邻 14 pt 正文处于同一基线。
- 同步更新 [design-system.md](../design-system.md) 中行内 Tag 的字号与基线规范。

## 已执行

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `xcodegen generate`：成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：构建成功（`** BUILD SUCCEEDED **`）。
- `python3 App/Tests/run-agent-reply-regression.py --composer-inline-tag-styles`：通过。
- `python3 App/Tests/run-agent-reply-regression.py --inline-tag-alignment`：通过（`Inline tag alignment passed: leadingRect=(0.0, 0.0, 122.0, 27.2), midRect=(149.7821011673152, 0.0, 164.0, 27.2), soloRect=(0.0, 0.0, 156.0, 22.0)`）。
- 视觉检查实际渲染截图：行内 Tag 文案与相邻 14 pt 正文字号一致、基线齐平，胶囊内边距与截断显示正常。
