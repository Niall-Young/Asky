# 来源标签文字基线

## 改动

- 来源标签原先先将文字居中画入图片，再以固定 `y = -5` 放入正文，图片内文字基线与正文不一致，导致标签文字偏高。
- 使用 CoreText 测量和绘制标签，返回实际绘制基线；行内附件以该基线的负值定位，使标签文字与正文共用基线，并计入中文等回退字体的度量。
- 保留 13 pt 标签字体、24 pt 胶囊高度、来源分组及交互。

## 已运行

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- 在 `Packages/KulaCore` 运行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `PYTHONDONTWRITEBYTECODE=1 python3 App/Tests/run-agent-reply-regression.py --sources-preview`：通过；涵盖来源分组、悬停、点击、长列表滚动及浅深色定位。
- 检查本次编译的原生回归窗口截图 `build/sources-light.png` 与 `build/sources-dark.png`：标签文字与相邻正文对齐，胶囊完整；浅色列表及深色换行场景均正常。
- `git diff --check`：通过。

## 范围与交付

- 截图使用已有来源预览样例，并非用户截图中的原会话；未替换已安装应用，未发布版本。
- README 无需修改：本次仅修正文字对齐，不改变使用方式、命令或功能范围。
- 构建、日志、回归程序及截图沿用现有 `build/` 忽略规则，生成工程和应用配置也由现有规则忽略。
