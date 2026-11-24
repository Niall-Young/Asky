# 2026-11-24 用户气泡左侧悬停操作栏验证

## 变更范围

- 将用户消息气泡的复制、回复消息操作由气泡下方（`UserMessageActionRow`）改为气泡左侧悬停浮现（`UserSideActionBar`，宽 58 pt、高 28 pt、按钮间距 2 pt，与气泡间距 8 pt），与 AI 气泡右侧悬停操作栏保持对称。
- 提取共享的 `bubbleSideActionCenterY(in:barHeight:visibleInsets:)`，让短用户消息垂直居中、长用户消息在滚动时随视口可见区自适应居中，保持 `0.14s` 淡入淡出且尊重系统“减少动态效果”。
- 保留用户气泡左下角 `<asky-reaction>` 表情贴纸位置，并在有贴纸时在气泡下方补齐 `26 - AgentLayout.userMessageVerticalInset`（14 pt）底部留白，避免移除底部操作栏后贴纸与下方 AI 气泡重叠，同时不影响左侧操作栏围绕气泡本体垂直居中。
- 更新 `App/Tests/AgentReactionRegression.swift` 中 `--user-bubble-hover` 的指针目标坐标至气泡左侧复制按钮区域，并适配 `0.14s` 淡入淡出动画等待时间。

## 实际执行检查

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过（`** BUILD SUCCEEDED **`）。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --reactions-preview`：通过（三种表情回应模式、完成态呈现、历史恢复、取消与目标隔离全部通过）。
- `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --user-bubble-hover`：通过（72 次原生指针悬停/移入左侧复制按钮/移出过渡，覆盖短消息、emoji、长换行消息与浅色/深色模式，气泡像素与 AI 回复位置全程稳定）。
- 已查看新构建窗口渲染截图 `build/user-bubble-hover-0-light-{0,1,2}.png`、`build/user-bubble-hover-0-dark-1.png`、`build/user-bubble-hover-2-light-1.png`、`build/user-bubble-hover-2-dark-0.png`，确认左侧操作栏位置、悬停反馈、长消息居中及表情贴纸间距正常。截图产物沿用现有 `build/` 忽略规则。
