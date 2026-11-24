# 欢迎引导权限图标统一验证

2026-11-24，将 `App/Sources/OnboardingWindow.swift` 中「开启常用权限」页的三项图标（辅助功能、Chrome 书签、登录时启动）由自定义渐变 SVG（`Onboarding-accessibility`、`Onboarding-bookmarks`、`Onboarding-launch`）改为复用 `ToolIconPalette` 纯色圆角底板（蓝 `#2D68FF`、橙 `#FF9A02`、绿 `#28A745`）+ `LauncherIconClip(radius: 8)` 32×32 pt 容器 + 18×18 pt 白色 MingCute 线性矢量图标（`accessibility`、`bookmark`、`power`），并移除三组废弃 `.imageset` 资产。

## 执行检查

1. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate`：通过。
2. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过（`BUILD SUCCEEDED`）。
3. `codesign --verify --deep --strict build/DerivedData/Build/Products/Debug/Asky.app`：通过。
4. 启动 `build/DerivedData/Build/Products/Debug/Asky.app/Contents/MacOS/Asky --show-onboarding`，点击「开始设置」进入「开启常用权限」页，通过 `orca computer get-app-state` 截取实际暗色模式窗口并检查：三项 32×32 pt 纯色圆角底板与 18×18 pt 白色 MingCute 线性图标渲染清晰、对齐准确，与卡片及全站工具图标视觉统一。
