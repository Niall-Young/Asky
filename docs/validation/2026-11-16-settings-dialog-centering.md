# 设置弹窗全窗口居中与轻量表面

## 变更

- 添加插件与添加／编辑别名改用共享 SettingsDialog，挂载到设置窗口 contentView，居中范围包含侧栏。
- 使用 16 pt 圆角、24 pt 内距、细描边与轻阴影，取消玻璃叠加大投影。插件弹窗收窄到 440 pt，仓库输入改为单列并移除嵌套卡片。
- 浮层拦截侧栏及页面鼠标操作；Tab / Shift-Tab 在当前可用控件间循环，取消与 Esc 移除浮层并恢复原输入焦点。
- 原生 NSAlert、插件配置 sheet 和系统文件选择面板不变。

## 实际验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。最初未指定 DEVELOPER_DIR 时因 Command Line Tools 环境缺少 XCTest 失败，切换 Xcode 后重跑成功。
- `python3 App/Tests/run-settings-regression.py --plugin-tabs`：通过。使用隔离临时数据与实际 SettingsWindow，检查插件弹窗在默认、1080×760、820×560 三种尺寸下相对完整内容区居中；检查侧栏点击拦截、输入后安装按钮启用、Tab 焦点不越界、取消与 Esc 关闭、原搜索框焦点恢复，以及别名弹窗居中与取消清理。
- 查看新回归构建的浅色与深色真实窗口截图：`build/plugin-tabs-zh-Hans-add-dialog-light.png`、`build/plugin-tabs-zh-Hans-add-dialog-dark.png`。已确认弹窗在完整设置窗口中央，表单无嵌套卡片，阴影收敛。截图使用插件测试数据，没有安装或执行插件。
- `git diff --check`：通过。

## 验证边界

- 未在 macOS 14/15 实机或 VoiceOver 中验收；未执行真实插件安装。
- 本地 Debug App 已完成构建；尝试退出旧实例返回取消，随后 Computer Use 两次连接超时。现场存在多个 Asky 实例，因此没有将“用户当前窗口已刷新为新界面”记为通过，也没有强制结束进程。视觉验证来自新编译的独立原生回归窗口。
- 构建保留既有控件并发隔离警告与模拟器版本提示，macOS App 构建成功。
- 日志、截图及回归 App 均位于既有忽略规则 `build/` 下，不纳入提交。
