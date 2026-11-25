# 时间段选择器顶栏样式与时间浮层弹出速度优化验证

日期：2026-11-25。针对时间段选择器上方切换样式及时间类弹出层弹出速度完成以下改动与验证：

- **时间段选择器上方切换样式调整**（[ChatFormView.swift](../../App/Sources/ChatFormView.swift)）：
  - 移除 `ChatFormRangeTabPill` 中可见的「开始」「结束」字段文案（保留为无障碍标签 `accessibilityLabel`），改为单行居中展示起止时间数值。
  - 将 `ChatFormRangeTabs` 中间的 `→` 箭头替换为短横线 `–`，并同步收紧 `ChatFormDateTimeRangePopover`、`ChatFormDateRangePopover`、`ChatFormTimeRangePopover` 的 `preferredSize` 高度以匹配单行顶栏。
- **时间类选择弹出层弹出速度优化**（[AnchoredPopoverMotion.swift](../../App/Sources/AnchoredPopoverMotion.swift)、[FormPickerOverlay.swift](../../App/Sources/FormPickerOverlay.swift)、[ChatForm.swift](../../App/Sources/ChatForm.swift)）：
  - 为 `FormPickerOverlayPresentation` 新增专用快速弹窗动效（展开 `spring(response: 0.15, dampingFraction: 0.90)` 从 `0.94` 缩放与 `4 pt` 方向位移淡入，收起 `100 ms` `easeOut` 缩回 `0.96`），同时保持气泡菜单与审批菜单既有动效不变。
  - 缓存 `ChatForm.date(_:)` 与 `ChatForm.dateString(_:)` 的线程安全 `DateFormatter`，避免月历弹出首帧重复创建 30+ 个 `DateFormatter` 实例。
  - 在 `FormPickerOverlayPresentation` 中对 `onGeometryChange` 增加 `> 1 pt` 差异阈值保护，避免首帧与 `preferredSize` 吻合时触发多余布局重算。
- 同步更新 [design-system.md](../design-system.md) 中的浮层动效与范围切换顶栏说明。

## 实际执行结果

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：全部通过（0 失败）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc App/Sources/ChatForm.swift App/Tests/ChatFormParserRegression.swift -o build/chat-form-parser-regression && build/chat-form-parser-regression`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --forms-only --time-preview`：通过（覆盖时间段浮层打开、切换结束时间、跨天点选与明暗截图；首轮因窗口失焦中断，复测完整通过）。
- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：成功（`BUILD SUCCEEDED`）。

## 已查看的实际窗口与浮层截图

- 深色模式时间段浮层：[form-range-popover-dark.png](../../build/form-range-popover-dark.png)
- 浅色模式时间段浮层：[form-range-popover-light.png](../../build/form-range-popover-light.png)
