# 原位液态玻璃头像配色菜单

## 最终行为

点击左上角 36 pt 头像，直接在原位向右下方变形成 184 × 252 pt 配色菜单；显示蓝、黄、紫、绿、粉五种对应头像与颜色名，当前颜色带勾，无独立色点。默认蓝色，选择保存在现有 `SettingsPreferences` 中，旧偏好缺少字段时回退蓝色。复用同一透明底生图资产，以 SwiftUI hueRotation 保持形象一致。

头像与菜单使用同一个 `GlassEffectContainer`、namespace 与 `glassEffectID`；原生 `.glassEffectTransition(.matchedGeometry)` 处理玻璃形态变化，弹簧 response 0.36 s、dampingFraction 0.58。菜单在原头像所在窗口内变形，沿用启动器原位菜单的实现方式，以便系统在同一玻璃容器内匹配形态。减少动态效果时不做弹簧过渡。

已移除逐帧缩放 NSPanel 和替换 rootView 的实现。最终不创建头像菜单子窗口，不使用自绘阴影或透明外围画布。原生 API 依据：[Apple matchedGeometry](https://developer.apple.com/documentation/swiftui/glasseffecttransition/matchedgeometry)。

## 实际运行

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：最终原生过渡版本 BUILD SUCCEEDED。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：最终版本通过。
- `plutil -lint App/Resources/en.lproj/Localizable.strings App/Resources/zh-Hans.lproj/Localizable.strings`：均 OK。
- `git diff --check`：通过。
- 新构建实际窗口：默认蓝色，五种头像可见，无色点；菜单覆盖头像原位，原生菜单可访问性树包含五个颜色按钮；点击黄色后菜单收回，头像值变为黄色。最终窗口当前为蓝色。
- 同一偏好接入在本次交互验证中已检查黄、紫、绿、粉切换及方向键/Return；选择绿色后退出并重启 Debug 进程，仍为绿色。最终修改仅替换菜单呈现，保存逻辑未变。
- Esc 和点外部的收起逻辑已实现。本轮原生版本的 Esc 检查因用户同时操作窗口被 Computer Use 中断，未记为通过。未执行帧率测量；静态截图只能验证布局，不能证明主观动画流畅度。
- 未替换 `/Applications/Asky.app`，未打包或发布。

README: updated — 中英文同步五色选择、原位变形和持久化
AGENTS.md: unchanged — 无新增跨任务通用规则

工作区已有大量未提交改动，头像 Swift 文件此前已未跟踪，相关 AgentModel、AgentView、翻译、README、设计系统已有改动。本次完整实现无法与既有未提交内容形成独立提交，因此不提交混合内容。保留所有原有改动，构建产物沿用现有 `build/`、`Asky.xcodeproj/` 忽略规则，无新增忽略规则。
