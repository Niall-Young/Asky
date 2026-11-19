# 系统提示词编辑框展开式高度（2026-11-19）

## 问题

设置 › 智能体 › 系统提示词的编辑框固定 176pt 高度，内部 `NSScrollView` 自带滚动条；默认窗口尺寸下内容只超出一点，出现滚动条却几乎无法滚动，并与外层设置页滚动冲突。

## 修改

- `SettingsMultilineTextEditor` 通过 `sizeThatFits` 按当前宽度排版全文，高度等于文本高度（不低于 `minHeight`，提示词编辑器为 176pt）。
- 内部滚动视图关闭竖向滚动条与回弹，滚轮事件转交给外层设置页（`SettingsPassthroughScrollView`）。
- 输入后把光标所在区域滚入可见范围，由外层页面跟随。

## 验证（实际运行）

- `xcodegen generate` + Debug `xcodebuild` 构建：BUILD SUCCEEDED。
- `python3 App/Tests/run-settings-regression.py --agent-prompt`：通过；新增断言编辑器无自身滚动条，且内容区高度不小于全文排版高度（默认提示词测得 587pt = 全文高度）。快照 `build/settings-agent-expanded-{light,dark}.png` 显示编辑框完整展开，由设置页整体滚动。
- `python3 App/Tests/run-settings-regression.py`：通过。
