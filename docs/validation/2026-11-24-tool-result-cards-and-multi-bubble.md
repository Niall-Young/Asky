# 能力专属原生结果卡片与多条消息验证记录

- 日期：2026-11-24
- 范围：
  - `Packages/KulaCore/Sources/Contracts/ToolResultCard.swift`、`AgentMessageSplit.swift`
  - `Packages/KulaCore/Sources/Adapters/EventKitTools.swift`、`PeopleAndHandoffTools.swift`
  - `Packages/KulaCore/Sources/ToolService/ToolResultCardActions.swift`
  - `Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift`、`NativeRuntime.swift`
  - `Packages/KulaCore/Sources/LocalStore/Repositories.swift`
  - `App/Sources/AgentModel.swift`、`AgentView.swift`、`ToolResultCardView.swift`

## 已执行检查

1. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
   - 结果：通过（含新增 `AgentMessageSplit`、`ToolResultCard`、`ToolResultCardStorage` 套件及既有全部测试套件）。
2. `xcodegen generate`
   - 结果：通过。
3. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`
   - 结果：`** BUILD SUCCEEDED **`。

## 未覆盖项

- 真实模型对话下的实时多条消息视觉效果与点击卡片跳转各 macOS 原生应用的实机手工验收尚未运行。
