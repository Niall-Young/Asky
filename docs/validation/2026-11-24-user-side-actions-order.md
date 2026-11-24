# 2026-11-24 用户气泡左侧操作按钮顺序修正验证

## 变更范围

- 调整 `App/Sources/AgentView.swift` 中 `UserSideActionBar` 的两个按钮顺序，由 `[复制, 更多]` 改为 `[更多, 复制]`，使“更多（`...`）”位于外侧（左）、“复制”紧贴用户气泡（右），与 AI 气泡右侧操作栏外侧放置“更多”的布局保持对称。
- 同步更新 `App/Tests/AgentReactionRegression.swift` 中 `--user-bubble-hover`（复制按钮目标坐标 `textFrame.minX - 40`）与 `--bubble-menu-preview`（用户更多按钮目标坐标 `userFrame.minX - 18 - 8 - 44`）的指针坐标与注释。

## 实际执行检查

- `(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)`：通过。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过。
- `python3 App/Tests/run-agent-reply-regression.py --bubble-menu-preview`：运行完成（退出码 0），截图产物位于 `build/`（已被 `.gitignore` 忽略）。
- `python3 App/Tests/run-agent-reply-regression.py --user-bubble-hover`：样本 0 浅色/深色共 24 次悬停过渡全部通过，并在 `build/user-bubble-hover-0-light-1.png`、`build/user-bubble-hover-0-dark-1.png` 实际窗口渲染截图中目视确认用户气泡左侧按钮顺序已更新为 `[更多 (...), 复制]` 且复制按钮悬停反馈正常；样本 1 浅色第 1 步因测试窗口失去前台焦点（`key=false`）中断，未记为全量通过。
