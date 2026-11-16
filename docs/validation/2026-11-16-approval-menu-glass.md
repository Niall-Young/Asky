# 审批菜单玻璃与精简文案

## 改动

- 删除两个权限选项下方的说明及中英文资源，只保留图标、名称、选中勾。
- 菜单收窄到 220 × 86 pt，使用 interactive Regular 玻璃；选项复用 `GlassPointerFeedback` 玻璃提亮与按压回弹，整行可点击，去掉普通灰色悬停底板。
- 根据后续反馈，收起按钮只显示图标与文字，不绘制背景、边框或悬停底板。
- 根据后续反馈，取消按钮变形；入口保持原位，菜单在上方 8 pt 独立弹出，仅做 120 ms 淡入淡出。
- 保留降低透明度、增强对比度、减少动态效果与旧系统回退。

## 已运行

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore`：通过，Swift Testing 62 项，XCTest 3 项。
- `git diff --check`：通过。
- 已检查 README；本次仅调整菜单外观及精简文案，功能、审批策略和开发命令不变，README 无需修改。

## 实机验证边界

已启动最新仓库 Debug（PID 51701，窗口 8531），通过进程路径确认构建身份。检查结果：

- 入口无背景，打开菜单后保持原位；上方独立显示两个权限选项，二级说明已移除。
- 通过真实坐标点击当前已选「完全访问权限」行右侧空白区域（窗口坐标 480, 600），辅助功能树确认两项菜单移除，原入口保留；整行点击与关闭通过。
- 未更改实际审批模式、发送消息或执行工具；未执行不同权限模式的往返切换。
- 最终悬停实现已改用共享 `GlassPointerFeedback`；工具未提供独立移入悬停操作，未将实时悬停光效记为实测通过。
- 未逐帧录制淡入淡出，未实机切换深色外观或辅助功能回退。中途的 Escape 核验出现过辅助功能读取错误，最终版本未单独重验该路径。

构建产物沿用现有 `build/` 忽略规则；日志写入系统临时目录。
