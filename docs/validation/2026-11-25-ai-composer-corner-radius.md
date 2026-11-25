# AI 输入框圆角调整

## 改动

- 在 `App/Sources/AgentView.swift` 的 `AgentLayout` 新增 `composerCornerRadius: CGFloat = 22`，将底部 `Composer` 原生玻璃容器圆角由 `16 pt` 调整为 `22 pt`（保持 `.circular` 曲线）。
  - 与底部 `8 pt` 内距的 `28 pt` 圆形附件／发送按钮保持严格同心（`14 + 8 = 22 pt`）。
  - 与上方 `21.5 pt` 气泡／卡片圆角及 `26 pt` 窗口圆角（`LauncherLayout.shellCornerRadius`）更协调。
  - 在多行滚动时顶部 `10 pt` 内距处圆角缩进为 `3.56 pt`（小于 `ComposerTextEditor` 外层 `4 pt` 水平留白与 `12 pt` 正文左缩进），不遮挡文字与滚动条。
- 同步更新 `docs/design-system.md` 中的 AI 输入框圆角说明。

## 已执行

- 基于 `HEAD` + 本次 `App/Sources/AgentView.swift` 改动建立隔离临时工作树（因主工作区同时存在其他未完成并行改动），执行：
  - `xcodegen generate`：成功。
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath /tmp/asky-composer-radius-dd -clonedSourcePackagesDirPath .../build/DerivedData/SourcePackages -skipPackageUpdates build`：构建成功（`** BUILD SUCCEEDED **`）。
  - `python3 App/Tests/run-agent-reply-regression.py --tool-result-cards --preview-legacy-material`：对比 `20 pt` 与 `22 pt` 的浅色、深色真实 `AgentWindow` 渲染图，确认 `22 pt` 围绕 `28 pt` 圆形按钮同心且与 `26 pt` 窗口外角、卡片圆角协调，无文字或控件裁切。
  - `AgentReplyRegression --reactions-preview`：通过（`Reaction regression passed`）。
  - `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（86 tests in 15 suites passed）。
  - 测试完成后已移除临时工作树与临时截图目录。

## 边界

- 本环境 `screencapture` 无录屏权限，屏幕截图回传黑图，实际视觉核对使用 AppKit 窗口位图渲染（含 `--preview-legacy-material` 精确轮廓）完成；未在主工作区混合其他并行未完成改动执行整仓 `xcodebuild`。
- `--bottom-push` 回归因仓库既有 `model.draft = ...` 与 `ComposerTextEditor` 内联标签编辑器不同步，在扩展高度断言（`AgentReplyRegression.swift:3143`）处失败，与本次圆角改动无关。
