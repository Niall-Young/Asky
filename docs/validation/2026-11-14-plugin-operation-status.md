# 插件操作状态样式

## 修改

插件设置的操作状态使用一个 `HStack` 作为 `SettingsForm` 的单行内容，避免表单把加载器与操作名称拆成两行并插入分隔线。加载器使用 small 尺寸和 16 pt 布局槽，文字为 13 pt 语义次要文字，间距 8 pt。保留操作完成、错误原文和文本选择，长文本允许换行。

## 已运行

- `xcodegen generate`：成功
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：`BUILD SUCCEEDED`，日志在 `build/plugin-status-build.log`
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：13 个测试运行共 337 项通过，日志在 `build/plugin-status-core-tests.log`
- 使用既有 `run-settings-regression.py` 编译流程及 `SettingsRegression.swift --plugins-only`，通过 `build/PluginSettingsStatusPreview.swift` 临时源码副本仅替换 `busy/status` 初始值，渲染真实插件页与 `SettingsForm`。已查看中文浅色和深色原生视图快照，加载器与操作名称横向居中对齐，状态区没有内部横线，高度约 44 pt。处理中快照：`build/plugin-status-busy-light.png`、`build/plugin-status-busy-dark.png`
- 同一隔离可执行文件使用 `--status-result` 检查完成状态，加载器随 `busy = false` 消失，完成文字仍留在同一状态行
- `git diff --check`：通过

## 范围

只调整插件设置状态行；未执行真实插件安装、更新、回退或卸载，未替换 `/Applications/Asky.app`。渲染副本和快照均留在已忽略的 `build/`，不进入源码提交。未在 macOS 14/15 实机检查兼容布局。

README: unchanged — 状态行的视觉修正不改变使用方式、构建命令或插件能力

AGENTS.md: unchanged — 现有原生界面与验证规则已覆盖本次修改，没有新增持久规则
