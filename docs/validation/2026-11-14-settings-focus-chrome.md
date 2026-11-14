# 设置失焦样式与控件高度修正

2026-11-14，macOS 27.0.1。

## 原因与修正

- 原生按钮为 regular、14pt 字号时 intrinsic height 为 25pt，输入框为 28pt。原生按钮改用 large 并将实际视图高度固定为 28pt，与输入框居中对齐。
- 只在 `updateNSView` 中设置尺寸仍会被 SwiftUI 的 regular 控件环境覆盖。窗口失焦时曾实测出现分段控件退回小圆角、按钮可见高度改变。按钮及分段控件现在从 SwiftUI 宿主显式传入 `.controlSize(.large)`；分段控件增加轻量 View 包装以统一这一环境。
- 设置背景此前在非活跃状态将额外染色从 25% 增至 55%，另将中性色层减半。移除这两处分支，固定自定义染色，保留原生材质本身的非活跃反馈。截图捕获仍受系统合成影响，不承诺不同状态逐像素相同。

## 已执行验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/SettingsCapsuleDerivedData build`：通过（最终包装修正后再次构建）。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，336 项 Swift Testing 测试。
- `ASKY_DERIVED_DATA="$PWD/build/SettingsCapsuleDerivedData" python3 build/SettingsChromeFinalSnapshot/App/Tests/run-settings-regression.py --settings-chrome -AppleLanguages '(zh-Hans)'`：最终通过。源码和回归产物位于忽略的独立快照目录，避免并行源码和构建产物改写。
- 新的 `--settings-chrome` 回归在浅、深色分别执行激活、失去 key、恢复 key 三个状态；检查原生按钮与分段控件始终保持 large、按钮实际高度 28pt、按钮与编辑字段中心对齐；捕获六张窗口截图，位于快照下 `build/settings-chrome-{light,dark}-{active,inactive,restored}.png`。
- 初次测试在桌面其他应用抢占焦点时遇到 key-window 断言失败；测试在开始与恢复检查前显式请求 key 状态，最终运行通过。此前仅检查视图外框高度的版本未发现原生控件尺寸被覆盖，现已增加实际 `controlSize` 断言。
- 打开最终快照的 `SettingsRegression.app --preview --commands`，通过 Computer Use 发送系统截图快捷键 `⌘⇧4` 并用 Esc 退出；观察期间分段胶囊及按钮轮廓保留。没有保存屏幕截图文件，独立预览保留在指令页。

未安装或发布正式版，未重新执行完整插件、聊天表单回归，未在 macOS 14/15 实机验证。

README: updated，中英文同步按钮高度及失焦行为。AGENTS.md: unchanged，没有引入新的架构或工具流程。源码快照和构建产物沿用现有 `build/` 忽略规则。其他任务已有暂存内容（含共享 README 和设计文档），本次不改写其索引，不创建混合提交。
