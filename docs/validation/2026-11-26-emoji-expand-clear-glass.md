# 2026-11-26 气泡表情选择器展开按钮 Clear 液态玻璃验证

## 变更摘要

- `App/Sources/ChatBubbleMenu.swift`：`ChatEmojiExpandButton` 的 28 × 28 pt 圆形 `+` 展开按钮移除原有的半透明灰底板（`discFill`），改为原生 Clear 液态玻璃（`.nativeGlassBackground(in: Circle(), clear: true)`），保留悬停 `.plusLighter` 提亮、展开态轻底色与自定义已选表情的主题色高亮描边，并继续兼容降低透明度/增强对比度及旧系统材质回退。
- `docs/design-system.md`：同步记录气泡表情快捷胶囊 `+` 展开按钮采用 28 × 28 pt 圆形原生 Clear 液态玻璃。

## 实际运行的检查

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --bubble-menu-preview`：通过（浅色/深色模式下快捷胶囊、展开面板及高速滚轮回归均通过）。
- 人工核对原生窗口截图：
  - `build/bubble-menu-emoji-light.png`、`build/bubble-menu-emoji-dark.png`：确认快捷胶囊右侧圆形 `+` 按钮呈现清晰的 Clear 液态玻璃折射与光学边缘。
  - `build/bubble-menu-emoji-expanded-above-light.png`、`build/bubble-menu-emoji-expanded-above-dark.png`：确认展开态下保持 Clear 玻璃边缘并具备清晰的选中态区分。
- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug build`：通过。
