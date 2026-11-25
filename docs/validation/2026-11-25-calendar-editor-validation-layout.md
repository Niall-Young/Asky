# 新建日程弹窗表单间距、字段下方校验与无句号报错验证

日期：2026-11-25。针对 [MessageCalendarEditor.swift](../../App/Sources/MessageCalendarEditor.swift) 完成以下改动与验证：

- **移除底部带边框报错条**：删除位于 `ScrollView` 与底部分割线之间的红色边框报错横幅，提交级报错改为以纯红色文案显示在表单下方，与设置弹窗报错风格一致。
- **拉开表单间距并改在字段下方校验**：表单项间距由 `12 pt` 调整为 `18 pt`（标签与控件间距 `8 pt`）；`CalendarFormField` 支持 `error` 槽位，将「请填写日程标题」「须晚于当前时间」「须晚于开始时间」移至对应输入框下方展示，标签右侧仅保留正常态时长提示。
- **中文报错去除末尾句号**：在 `displayedError` 中自动去除中文末尾句号 `。`，并为新增键 `请填写日程标题` 补齐中英文文案（[zh-Hans](../../App/Resources/zh-Hans.lproj/Localizable.strings)、[en](../../App/Resources/en.lproj/Localizable.strings)）。

## 实际执行结果

- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：成功（`BUILD SUCCEEDED`）。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：全部通过（0 失败）。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-calendar-editor-regression.py`：通过。
- `python3 App/Tests/check-localization.py`：新增键 `请填写日程标题` 无缺失告警（仅存仓库既有重复键 `剪贴板历史`）。
- 视觉验收：重新截取并检查了空标题/过早开始时间、结束早于开始、提交失败叠加校验、待核实锁定态等窗口截图，确认字段下方报错、表单间距及无末尾句号均符合预期。
