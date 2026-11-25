# 聊天输入框与顶部两处控件统一为 Regular 玻璃

## 改动

- [`App/Sources/AgentMonsterAvatar.swift`](../../App/Sources/AgentMonsterAvatar.swift)：
  - 左上角收起态头像（`AgentAvatarPicker`）由 `.clear` + `0.85` 透明度改为原生 `.regular` 玻璃（完整不透明度），与展开态配置面板共享 Regular 玻璃质感。
  - 兼容回退分支的 `trigger` 同步改为 `.nativeGlassBackground(in: Circle())`。
- [`App/Sources/AgentView.swift`](../../App/Sources/AgentView.swift)：
  - 右上角置顶／关闭按钮胶囊（`AgentView.header`）由 `.nativeGlassBackground(in: Capsule(), clear: true, glassOpacity: 0.85)` 改为 `.nativeGlassBackground(in: Capsule())`（原生 Regular 玻璃）。
  - 底部输入框容器（`Composer`）由 `.nativeGlassBackground(in: RoundedRectangle(cornerRadius: AgentLayout.composerCornerRadius, style: .circular), clear: true, glassOpacity: 0.85)` 改为 `.nativeGlassBackground(in: RoundedRectangle(cornerRadius: AgentLayout.composerCornerRadius, style: .circular))`（原生 Regular 玻璃）。
- [`docs/design-system.md`](../design-system.md)：同步更新收起态头像、右上按钮组与聊天输入框的 Regular 玻璃材质说明。

## 已执行验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过（`** BUILD SUCCEEDED **`）。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（91 tests in 16 suites passed）。
- 重启本机 Debug `Asky.app`（`build/DerivedData/Build/Products/Debug/Asky.app`），可在真实桌面窗口直接核对对话界面的三处 Regular 玻璃效果。

## 同步核对

- `README.md`: unchanged（README 不记录聊天局部控件的 Clear/Regular 子材质细节）。
- `AGENTS.md`: unchanged（无新增或变更的持久工程约束）。
