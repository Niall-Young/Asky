# 设置输入表面浅色亮度修正

日期：2026-11-14

- 设置输入表面的浅色填充由 70% 白色改为语义 `input`（8% 黑色）；深色仍使用 `backgroundNeutral`（6% 白色）。文本、密码、搜索和下拉控件共享此修正。聊天表单的独立填充覆盖保持原样。
- 保留 28 pt 高度、14 pt 圆角、原生编辑和焦点边框。

## 实际验证

- `xcodegen generate`：通过。
- README 的 Debug `xcodebuild` 命令：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `python3 App/Tests/run-settings-regression.py --settings-chrome`：未通过；在恢复窗口后 `window.isKeyWindow` 断言失败（SettingsRegression.swift:1039），不计为输入样式验证通过。旧回归二进制另有既有布局断言失败，不用作修复前截图证据。
- 使用本轮新编译的 `build/SettingsRegression.app/Contents/MacOS/SettingsRegression --settings-focus`：通过浅色及深色输入框内点击、切换输入、外部失焦与值保留；截图 `build/settings-focus-light.png` / `build/settings-focus-dark.png`。
- 新编译的原生设置预览通过电脑界面切换至浅色、进入「终端」，目视确认触发指令、工作目录及终端下拉均为低对比中性填充，无原来的白色块。预览使用隔离数据。未替换 `/Applications` 中的正式安装包。

## 文档检查

- README: unchanged — 仅样式修正，既有构建、使用及安装说明仍适用。
- AGENTS.md: unchanged — 未引入新的架构或持久开发规则。
- 本地产物沿用已有 `build/` 忽略规则。
