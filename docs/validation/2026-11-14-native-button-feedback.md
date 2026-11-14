# 原生按钮点击反馈修复

## 原因与修改

共享 `LiquidGlassInteraction.swift` 把按下缩放设为 1.08、悬停缩放设为 1.015，并添加阻尼 0.45 的弹簧动画。这是应用自定义反馈；设置原生玻璃按钮和部分 interactive 玻璃表面也套用了它。

移除该实现及所有调用。SettingsButton、快捷键录制与聊天工具栏改用 NSButton 原生跟踪；普通图标按钮改用 SwiftUI plain 样式。保留原生玻璃材质、interactive 效果、菜单展开动画及现有悬停高亮。发送按钮以按下透明度反馈替代已移除的缩放。

Apple 原生按钮样式参考：[PrimitiveButtonStyle](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle)。

## 实际检查

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`（Packages/KulaCore）：通过，Swift Testing 43 tests / 10 suites。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。首次构建发现快捷键 Recorder 仍继承旧类，补齐清理后重建通过。
- `python3 App/Tests/run-settings-regression.py --preview`：成功编译并启动新预览，进程为本工作区 `build/SettingsRegression.app/Contents/MacOS/SettingsRegression`。
- 在该预览的 Keyboard Shortcuts 页面按住快捷键按钮 350 ms 后释放，进入录制状态；Esc 取消后恢复原快捷键；截图确认原生玻璃按钮外观保留。
- 全量源码搜索：没有遗留 liquidGlassInteraction、LiquidGlassPlainButtonStyle、LiquidGlassPressButton 或 onPressChanged 转发。
- `git diff --check`：通过。

## 验证范围与交付

未逐帧量化动画曲线，未穷举所有按钮、深浅色和旧系统组合。设置脚本仅运行 preview 分支，不宣称完整设置回归通过。未替换已安装的 Asky。

构建有现有 SDK 弃用提示和 iOSSimulator 版本提示，不影响 macOS 构建。构建与预览产物沿用已有 build/ 忽略规则。

README 与 AGENTS.md 无需调整：本次恢复控件反馈，没有改变使用方式、开发命令或模块边界。工作区已有大量未提交改动，其中已有未跟踪的 AgentMonsterAvatar.swift 也使用了旧缩放；本次对其作了必要清理，无法在不纳入原有整个文件的情况下独立提交完整修复，故保留所有改动且不创建混合提交。
