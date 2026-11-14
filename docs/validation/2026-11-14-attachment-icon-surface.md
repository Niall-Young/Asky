# 附件与引用图标底座

## 改动范围

- 仅调整 `ComposerAttachmentCard` 内 44 × 44 pt 正方形图标底座：普通透明度模式改用 3% 中性色填充，移除描边，保留 8 pt 圆角。
- 浅色用深色半透明填充，深色用白色半透明填充；开启减少透明度时沿用原有语义背景。
- 引用的 `textformat` 图标改为已有 MingCute `text.document` 文档图标。
- 外层卡片底色、悬停颜色、尺寸、间距和图片缩略图保持原样。
- README 中英文、PRD 与设计系统同步文档图标描述。AGENTS.md 无需变更，目录、开发命令和架构边界未改变。

## 实际验证

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：最终修改后通过。
- `python3 App/Tests/run-agent-reply-regression.py --selection-preview`：最终修改后通过。覆盖明暗模式五种头像色、真实选区菜单操作、引用去重、输入焦点、失败发送保留、发送及历史恢复。
- 查看最终源码重新编译运行的原生窗口截图 `build/selection-light.png`、`build/selection-dark.png`：文档图标已显示，正方形底座为轻微半透明填充，无原来的实色底和描边；外层卡片底色保留。
- `git diff --check`：通过。构建及截图复用既有 `build/` 忽略规则，Swift 缓存复用既有 `Packages/KulaCore/.build/` 忽略规则。

截图为本机回归窗口，未覆盖不同壁纸或减少透明度的实际显示效果。本轮未替换已安装 App、未打包或发布。

## 后续调整：提高底座辨识度

用户在 Debug 实际窗口中反馈 3% 底座过浅，因此仅将图标底座提高为 6% 中性色；外层卡片与图标保持不变。

- 重新执行 `swift test`、`xcodegen generate`、Debug `xcodebuild`：通过。
- 原生选区预览重新编译被并行构建中断：`Router.o was modified during the build`，本次不记为预览通过。Computer Use 读取实际窗口也超时，6% 效果尚未完成视觉复核。
- 已重启 `build/DerivedData/Build/Products/Debug/Asky.app`，供实际查看。
- README: unchanged，仅调整底座透明度，不影响使用说明。AGENTS.md: unchanged，开发命令和架构边界未改变。构建与截图沿用既有忽略规则。
