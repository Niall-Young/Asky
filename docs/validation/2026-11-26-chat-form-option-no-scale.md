# AI 表单单选与多选点击取消缩放动效验证

日期：2026-11-26。移除 AI 对话表单（`asky-form`）中单选与多选选项行的点击缩放回弹动效：

- [ChatFormView.swift](../../App/Sources/ChatFormView.swift)：
  - 移除 `ChatFormOptionButtonStyle` 按下态的 `.scaleEffect(pressed && !reduceMotion ? 0.992 : 1)`，保留轻柔的不透明度按压反馈（`opacity 0.92`）。
  - 移除 `ChatFormOptionRow.trailingIndicator` 单选勾选徽章的 `.scaleEffect(selected || reduceMotion ? 1 : 0.82)`，仅保留淡入淡出过渡。

## 实际执行结果

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：全部通过。
- `xcodegen generate` + `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：成功（`BUILD SUCCEEDED`）。
- `python3 App/Tests/run-agent-reply-regression.py --forms-only --radio-preview`：通过（表单生命周期、单字段即时提交、单选/多选明暗与窄窗渲染回归均通过）。

本次未调用真实模型，也未在 macOS 14/15 实机验证。
