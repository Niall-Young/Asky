# 网页来源卡片字号调整

## 改动

- [ChatSourcePreview.swift](../../App/Sources/ChatSourcePreview.swift)：
  - 为 `ChatSourcePreview` 增加字号与图标尺寸常量：`titleFontSize = 14`、`metaFontSize = 12`、`faviconSize = 13`。
  - 卡片标题由 15 pt 调整为 14 pt，与聊天正文及结果主文本字号保持一致；站点名称与发布日期由 13 pt 同步调整为 12 pt；站点图标由 14×14 pt（回退地球图标 13 pt）微调为 13×13 pt（回退地球图标 12 pt），保持与 12 pt 站点文案的视觉比例。
- [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)：
  - 在 `--sources-preview` 回归中新增 `ChatSourcePreview.titleFontSize == 14` 与 `ChatSourcePreview.metaFontSize == 12` 断言。

## 实际验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过。
- `(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)`：83 项测试（15 个套件）全部通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --sources-preview`：通过（输出 `Source tags, +N grouping, hover/click lists, long-list scrolling and light/dark positioning passed`）。
- 视觉检查新构建窗口导出的 `build/source-card-list-light.png`、`build/source-card-list-dark.png` 与 `build/source-card-kimi-light.png`：14 pt 标题、12 pt 站点名/日期与 13 pt 图标在浅色与深色玻璃表面下层次清晰、无裁切或重叠。

## 交付边界

本次仅调整多来源弹出卡片 `ChatSourcePreview` 的字号与图标比例，不改动行内来源胶囊标签与交互逻辑；已验证新构建 Debug 产物及真实原生回归窗口，未替换用户已安装版本。构建产物与回归截图沿用 `.gitignore` 中的 `build/` 规则。
