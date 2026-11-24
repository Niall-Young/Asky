# 2026-11-24 AI 回复右键菜单与原生结果卡片排版调整验证

## 变更范围

- 将 AI 回复气泡（含工具前置说明气泡）的复制、回复消息、分享回复统一移入气泡右键菜单（同时覆盖 `NSTextView` 文本区与气泡留白区），移除气泡下方常驻操作栏与时间戳。
- 移除 `ToolResultCardView` 底部辅助小字（`footnote`）渲染，且所有原生结果卡片构建器不再输出辅助脚注（备忘录卡片将摘要归入正文区 `title`）。
- 调整 `ToolResultCardView` 中主标题（`headline`）与下方内容（`title`）的字重和色彩层级：联系人/主标题保持 16pt Semibold 主色，下方正文改为 14pt Regular 柔和色（大字号时间标题场景正文保持 14pt Regular 主色）。

## 实际执行检查

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（含 `ToolResultCardTests.messagesDraftCard` 断言 `footnote == nil`）。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过（`** BUILD SUCCEEDED **`）。
