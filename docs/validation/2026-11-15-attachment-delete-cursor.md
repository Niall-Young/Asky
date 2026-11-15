# 附件删除按钮光标修复

## 改动

- 引用、文件和图片共用的 `ComposerAttachmentCard` 删除按钮接入现有 `ActionArrowCursor`，仅在悬停或键盘聚焦使按钮可见时注册箭头区域。
- 光标区域跟随按钮原有尺寸和偏移；不修改卡片布局、颜色、点击动作或动画。

## 已运行

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：62 个测试通过。
- `python3 App/Tests/run-agent-reply-regression.py --action-cursor-preview`：通过。现有原生回归验证共享光标实现的文字/按钮切换、按钮点击、非关键选区菜单及回到文字区域的光标恢复；该回归不直接覆盖附件卡片的删除按钮。
- `git diff --check`：通过。

## 验证边界与文档

尚未在用户当前运行的 Asky 中手动复验附件删除按钮，也未替换安装版本。Debug 构建产物位于 `build/DerivedData/Build/Products/Debug/Asky.app`。

README 保持不变：本次为局部光标修复，使用方式、构建命令和功能范围不变。构建与原生回归产物沿用现有 `.gitignore` 规则，不新增忽略项。
