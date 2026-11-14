# 对话顶部 Regular 玻璃

删除 AgentHeaderBackdrop 及其渐变蒙版。头像圆形与右侧胶囊通过 NativeGlassBackground 使用完整强度 Regular 玻璃，保留尺寸、操作与指针反馈。

## 验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- 在 Packages/KulaCore 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。首次未指定 Xcode 时缺少 Testing 模块，改用完整 Xcode 后通过。
- `python3 App/Tests/run-agent-reply-regression.py --forms-preview --custom-preview`：未通过，在 AgentReplyRegression.swift:285 的可编辑表单断言处退出；未将此脚本记为通过。
- 尝试打开新构建 App 检查实际效果，电脑控制工具返回 App quit，未完成实际窗口视觉验收。已有 form-complete.png 为旧产物，未作为本次验证依据。
- 构建与预览产物沿用现有 build/ 忽略规则。

README 中英文与设计系统已同步；AGENTS.md 无命令、边界或目录规则变化，无需修改。
