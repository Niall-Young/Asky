# 关于 Asky 页面信息层级优化验证

日期：2026-11-25

## 变更摘要

- 重构 [AboutSettings.swift](../../App/Sources/AboutSettings.swift) 的三段式信息层级：
  1. 顶部品牌卡片保留 Asky 图标、名称与一句话定位说明（“搜索、剪贴板与 AI，一个快捷键呼出”），移除与下方仓库入口重复的 `GitHub` 按钮。
  2. “软件更新”卡片首行以“当前版本 X.Y.Z（Build）”作为主标题（保留 `.textSelection(.enabled)`），次行展示更新状态（未检查、检查中、已是最新、发现新版本、下载中、已就绪待静默更新、安装中、失败提示），右侧保留“查看发布说明”与主操作按钮，将版本号与更新操作直接关联。
  3. 独立“开源项目”分组承载 [StarRepositoryRow.swift](../../App/Sources/StarRepositoryRow.swift)，并将其唯一仓库操作按钮（“查看仓库” / “去点 Star”）统一加上 `GitHubMark` 图标。
- 同步更新中英文本地化文件（[zh-Hans](../../App/Resources/zh-Hans.lproj/Localizable.strings) 与 [en](../../App/Resources/en.lproj/Localizable.strings)），英文按钮标题统一使用 Title Case（`View Repository`），中文文案无多余末尾句号。
- 新增独立回归入口 [AboutSettingsRegression.swift](../../App/Tests/AboutSettingsRegression.swift)，并在 [run-settings-regression.py](../../App/Tests/run-settings-regression.py) 中接入 `--about-page` 与构建版本信息拷贝。

## 已执行验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/AboutDerivedData build`：通过（`** BUILD SUCCEEDED **`）。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（91 tests in 16 suites passed）。
- `ASKY_DERIVED_DATA=build/AboutDerivedData python3 App/Tests/run-settings-regression.py --about-page`（英文）与 `-AppleLanguages '(zh-Hans)'`（简体中文）：通过（`About page hierarchy regression passed in light and dark`），断言移除重复 `GitHub` 按钮、页面仅保留唯一带图标仓库按钮、“软件更新”位于“开源项目”上方。
- 实窗截图视觉检查（浅色 / 深色 × 中文 / 英文）：确认三张卡片层次清晰、Logo 与 Star 图标列对齐、版本号与更新状态同属“软件更新”首行且无重复按钮。
- `AGENTS.md` 与 `README.md`：无新增构建命令、架构边界或使用路径变更，保持不变。
