# 设置控件胶囊样式

2026-11-14，在 macOS 27.0.1、Xcode 27.2 SDK 环境验证。

## 改动

- 单行输入、密码、下拉选择器与搜索框共用 28 pt 高度、14 pt 圆角；左右留白为 12 pt，保留原生编辑、菜单与聚焦反馈。
- 指令及插件分类使用原生 `NSSegmentedControl`，胶囊样式、large 尺寸和中性选中底色。尺寸在 `updateNSView` 中设置，避免 SwiftUI 的常规尺寸环境覆盖首次配置。
- 28 pt 行内图标操作的悬停区域采用胶囊轮廓。分组卡片仍按既有层级呈现。
- 分段控件回归改为驱动原生控件；截图使用窗口捕获，以包含系统原生绘制的表面。

## 实际执行

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- 最后一次尺寸修正后，用同一命令将 DerivedData 改为 `build/SettingsCapsuleDerivedData`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，13 个测试进程共 335 项 Swift Testing 测试。
- 指令原生回归 `--command-layout -AppleLanguages '(zh-Hans)'`：通过，覆盖分类切换、跨分类搜索、无匹配与编辑焦点。
- 输入原生回归 `--settings-focus -AppleLanguages '(zh-Hans)'`：通过，覆盖浅深色下的框内点击、切换输入、框外失焦与值保留。
- 打开本次源码快照编译的 `SettingsRegression.app --preview --commands`，通过 Computer Use 实际点击分类，并在通用页选择浅色、深色；检查指令、插件、搜索框、行内输入和下拉控件。原生胶囊及灰色选中态已确认，预览保留在指令页。预览使用临时数据目录。

## 隔离与限制

初次原生回归编译分别遇到共享 `Resources.o`、工作区 `MingCute.swift` 被并行任务改写。最终将 App 源码与构建产物复制到忽略的 `build/SettingsCapsuleFinalSnapshot`、`build/SettingsCapsuleFinalPluginSnapshot`、`build/SettingsCapsuleDerivedData` 后执行，使用 `ASKY_DERIVED_DATA` 选择独立产物。

插件完整回归 `--plugin-tabs -AppleLanguages '(zh-Hans)'` 未全部通过：分类切换、共享启停、搜索、空搜索、添加窗口及浅深色截图已执行，随后在并行新增的取色插件目录标识查找处超时（快照 `PluginSettingsRegression.swift:194`）。该新增断言与取色插件实现不属于本次改动，未将完整插件回归记为通过；Computer Use 已另外确认实际功能插件分类可切换并显示取色插件。

未做 macOS 14/15 实机验收，未打包 Release、安装或发布。共享组件也供聊天原生表单使用，本次没有重新执行整套聊天表单回归。

README: updated，中英文同步设置控件外观；AGENTS.md: unchanged，现有构建、边界与指南入口仍适用。所有测试快照、截图及构建产物沿用现有 `build/` 忽略规则。
