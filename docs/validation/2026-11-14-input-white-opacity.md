# 输入框白色填充不透明度修正

日期：2026-11-14

本记录更正前一轮灰色填充方案（761ec81）。用户要求保留白色填充，降低不透明度。

- 设置输入框、密码框、搜索框和下拉框的浅色填充改为白色 12%，取代前一轮 8% 黑色；暗色保持原样。
- 移除聊天表单独立的 55% 白色填充，统一继承共享输入表面的 12% 白色填充；文本、下拉与日期控件同步生效。
- 尺寸、边框和编辑行为保持原样。

## 实际验证

- `xcodegen generate`：通过。
- README 的 Debug `xcodebuild` 命令：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- 已重启本地 Debug 应用，在实际浅色聊天窗口定位历史日程表单，确认「地点（可选）」和「备注（可选）」输入框保留轻微白色填充，原来的亮白块已消失。历史表单处于已结束的禁用状态；本检查不算可编辑表单交互验证。
- 未替换 `/Applications` 中的正式安装包。
- README: unchanged — 仅修正视觉填充，使用及开发命令不变。
- AGENTS.md: unchanged — 未产生新的持久开发规则。
- 本地产物沿用 `build/` 忽略规则。
