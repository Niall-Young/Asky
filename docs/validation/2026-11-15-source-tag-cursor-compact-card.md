# 来源标签光标与紧凑预览卡片

## 改动

- 来源附件复用同一 glyph 命中逻辑处理悬停和光标；tag 显示箭头，正文保留原生文字光标。
- 预览卡片条目接入现有 actionArrowCursor，保留原来的链接操作。
- 卡片宽度从 380 改为 300 pt；左右内边距 20 → 12 pt，上下 20 → 10 pt；文字间距 8 → 4 pt，分隔线两侧间距 16 → 10 pt；玻璃与内容圆角同步由 16 → 12 pt。
- 仍为独立玻璃窗口，窗口尺寸等于卡片尺寸，保留原生阴影与多来源内部滚动。

## 实际验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- `Packages/KulaCore` 下执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：62 项通过。
- `python3 App/Tests/run-agent-reply-regression.py --sources-preview`：通过；覆盖来源分组、悬停/点击展开、长列表滚动和浅色/深色定位。新增截图同款 Kimi 文案的紧凑尺寸检查。
- 使用同一次编译出的 `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --action-cursor-preview`：通过。真实 AppKit 事件循环与鼠标移动验证正文 → tag → 卡片 → 正文的光标切换，既有按钮点击与选区操作回归也通过。
- 已检查 `build/source-card-kimi-light.png` 与 `build/source-card-kimi-dark.png`：卡片 300 × 59 pt，同款标题完整显示、无截断。
- `git diff --check`：通过。

## 交付边界

已验证新构建的原生回归窗口，未替换用户安装版本或在用户原聊天记录上复验。Debug 应用位于 `build/DerivedData/Build/Products/Debug/Asky.app`。

README 中英文同步更新来源卡片行为、尺寸及现有来源回归命令。构建、日志和截图沿用 `.gitignore` 的 `build/` 规则，无新增忽略项。
