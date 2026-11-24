# 分享弹窗操作按钮文案变化布局抖动修复验证（2026-11-24）

## 问题与变更

- 问题：分享预览弹窗底部四个圆形操作按钮（`ShareCircleActionButton`）原先未固定槽位宽度，点击「复制图片」后文案切换为更短的「已复制」（或点击「保存图片」切换为更长的「已保存图片」，以及英文环境下的 `Copy image` → `Copied` / `Save image` → `Image saved`）时，按钮自身宽度变化，导致整行居中 `HStack` 发生横向位移。
- 变更：[ChatShareCard.swift](../../App/Sources/ChatShareCard.swift) 为 `ShareCircleActionButton` 增加固定槽位宽度 `slotWidth = 76`，按钮行改用 `HStack(spacing: 4)`（四枚按钮中心距固定 80 pt、总宽固定 316 pt），并为标签文本补充 `.fixedSize(horizontal: true, vertical: false)` 避免单行截断。

## 实际执行与结果

1. `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`
   - 结果：通过（`Asky` 与 `asky-mcp` 全部构建成功）。
2. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
   - 结果：通过（15 个套件共 83 项测试全部通过）。
3. `python3 App/Tests/run-agent-reply-regression.py --share-and-user-reply`
   - 结果：通过（亮/暗双模式分享卡片与分享预览窗口回归通过）。
4. 视觉核查 `build/share-preview-window.png`（暗色）与 `build/share-preview-long.png`（亮色）
   - 结果：通过。四枚圆形操作按钮间距均匀且水平居中对齐。
5. SwiftUI 布局尺寸校验（中英文默认/已复制/已保存图片/深浅色切换共 7 组状态）
   - 结果：通过。全部状态整行尺寸严格保持 `316.0 × 69.0 pt`，无横向或纵向位移。
