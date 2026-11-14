# 恢复内置屏幕取色

日期：2026-11-14。用户明确撤回屏幕取色插件拆分，继续使用原来的主应用原生功能。

## 恢复范围

- 恢复 ToolService 内的 `ScreenColorPicker.swift`、颜色转换与剪贴板测试，以及启动器原有 `colorPicker` 指令、默认 `co`、自定义触发词、取色分组和 MingCute 图标。
- 撤回取色插件官方目录条目、设置安装入口、拆分引入的 `dismissLauncher` 执行分支与专用回归；停止取色插件公证和分发。
- README 中英文、PRD 和插件指南恢复内置取色说明。头像、气泡、设置控件及其验证改动保留。
- 原生取色在主应用进程中调用 `NSColorSampler`，系统读写仍由 ToolService 处理；不运行独立取色可执行文件。

## 实际检查

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`（在 `Packages/KulaCore`）：通过，包含 sRGB 转换、P3 色彩空间转换及独立剪贴板回读测试。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/ColorPickerSigningDerivedData build`：通过。
- 使用该 DerivedData 运行 `python3 App/Tests/run-launcher-window-regression.py --color-picker`：通过；验证 `co`、大小写、中文名称、自定义触发词、分类作用域和剪贴板颜色预览。
- 新 Debug app 的 `codesign --verify --deep --strict` 通过，开发者团队 `V8GVW783CK`。
- 已启动独立构建的 Debug app，并确认过其运行进程。随后并行任务重启了常规 Debug app；最终运行路径为 `/Users/niallyoung/orca/Asky/build/DerivedData/Build/Products/Debug/Asky.app/Contents/MacOS/Asky`，该包签名校验通过，二进制包含内置 `pickScreenColor` 与 `screenColorHex` 实现。
- 对照 HEAD 检查原生实现、资源与取色文档已恢复，仅选择性撤回混合文件中的取色相关修改；其他任务的暂存内容保留。此次回退的拆分代码原先未提交，因此源码恢复后与 HEAD 相同。

## 验证边界

未自动唤起真实取色放大镜，未复测实际点击取色与 Esc；以上通过结果不代表已完成真实屏幕取色交互验收。旧独立插件目录保留，但不在官方目录、主应用实现或构建包的调用路径中；没有删除远端仓库或进行发布。

README: updated，恢复原有中英文内置取色说明。AGENTS.md: unchanged，沿用既有 ToolService、构建与验证规则。
