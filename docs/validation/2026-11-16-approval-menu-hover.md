# 审批菜单上下两行悬停一致性

## 问题与修复

上一版将整个菜单放在输入框内部的按钮 overlay 中，菜单上行伸出输入框玻璃的范围，原生悬停追踪与显示范围不一致。上次只检查了下行点击，没有覆盖上行悬停。

菜单改由入口的 bounds anchor 定位，挂在 AgentView 窗口顶层。入口仍无背景、保持原位；菜单仍独立弹出，不变形。两行继续共用 GlassPointerFeedback，不增加灰色底板。

## 验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore`：通过，62 项 Swift Testing、3 项 XCTest。
- `python3 App/Tests/run-agent-reply-regression.py --approval-menu-hover`：通过。
- `git diff --check`：通过。

专项回归使用实际 AgentView、独立临时 AppModel 和稳定背景窗口，通过系统鼠标事件打开菜单、移入两行、移出及点击。浅色上/下行空白区域的平均亮度增量分别为 0.0453 / 0.0444，深色为 0.0540 / 0.0529；移出后均恢复到初始亮度（误差小于 0.006）。在临时设置中完成完全访问与自动审批两项切换，不更改用户的审批设置。已人工查看上行浅色、下行深色截图，确认对应行单独提亮。

最初的测试尝试未通过：NSView 缓存截图不包含系统合成玻璃；窗口截图未能可靠反映菜单；应用内投递的点击也没有稳定打开菜单。最终改为系统鼠标点击、稳定背景与屏幕区域截图，并核对真实指针坐标后才记录通过。测试结束关闭测试窗口并恢复鼠标位置。

截图 `build/approval-hover-*.png` 和测试程序沿用现有 `build/` 忽略规则；日志位于 `/tmp/asky-approval-hover-*.log`。README 中英文测试命令均已同步。旧系统和辅助功能回退本轮未单独验证。
