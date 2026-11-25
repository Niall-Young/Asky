# 回复图标替换为 MingCute share_forward

- 从固定版本 MingCute（`ca98bb55513a22ff0dab713aaf7870b512944653`）导入原文件 `assets/svg/core/regular/system/share_forward.svg` 到 [App/Assets.xcassets/MingCute-share_forward.imageset/icon.svg](../../App/Assets.xcassets/MingCute-share_forward.imageset/icon.svg)，保持矢量模板配置并移除不再使用的 `MingCute-corner_down_left.imageset`。
- 同步更新 [scripts/mingcute-icons.json](../../scripts/mingcute-icons.json)、[App/Sources/MingCute.swift](../../App/Sources/MingCute.swift) 以及三处回复入口图标：
  - AI 气泡悬停操作栏回复按钮（[App/Sources/AgentView.swift](../../App/Sources/AgentView.swift)）
  - 用户气泡更多菜单「回复」项（[App/Sources/ChatBubbleMenu.swift](../../App/Sources/ChatBubbleMenu.swift)）
  - 输入区与已发送用户消息的行内回复 Tag（[App/Sources/InlineTagAttachment.swift](../../App/Sources/InlineTagAttachment.swift)）
- 同步更新 [docs/design-system.md](../design-system.md) 中的回复图标说明。

## 验证

- `scripts/mingcute-icons.json` 与 `App/Sources/MingCute.swift` 符号表一致性校验：通过（80 个符号全部匹配且 SVG 存在）。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过（`BUILD SUCCEEDED`）。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（15 suites / 83 tests passed）。
- `python3 App/Tests/run-agent-reply-regression.py --bubble-menu-preview`：通过；已查看新生成的 `build/bubble-menu-assistant-more-{light,dark}.png` 与 `build/bubble-menu-user-more-{light,dark}.png`，确认浅深模式下 AI 气泡悬停栏与用户更多菜单的回复图标均正确显示为 14 pt MingCute `share_forward` 模板图标。
- `python3 App/Tests/run-agent-reply-regression.py --composer-inline-tag-styles`：通过。
- `python3 App/Tests/run-agent-reply-regression.py --share-and-user-reply`：通过。
