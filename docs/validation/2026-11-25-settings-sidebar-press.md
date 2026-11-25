# 设置侧栏菜单点击无颜色闪动

## 改动

- 在 `App/Sources/SettingsWindow.swift` 中新增静态按钮样式 `SettingsSidebarButtonStyle`（直接返回 `configuration.label`，不响应按压态变暗），将 `SettingsSidebar` 侧栏菜单项从 `.buttonStyle(.plain)` 切换为 `.buttonStyle(SettingsSidebarButtonStyle())`。
- 保留原 `Button` 结构、点击切换逻辑、`.contentShape(Rectangle())` 以及辅助功能标签与选中特征（`.accessibilityLabel` / `.isSelected`）。

## 已执行

- 独立按压探针（macOS 27.0.1）：确认 SwiftUI `.buttonStyle(.plain)` 在 `leftMouseDown` 期间会对未选中项（`changedPixels=2185, maxDelta=39`）与已选中项（`changedPixels=26440, maxDelta=55`）施加明显变暗/泛白高亮，而静态 `ButtonStyle` 在按压期间像素变化为 `0`。
- `(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)`：通过（91 tests in 16 suites passed）。
- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData-sidebar-press -skipPackageUpdates build`：构建成功（`** BUILD SUCCEEDED **`）。
- 基于新构建产物运行真实 `SettingsWindow` 侧栏按压检查（浅色与深色模式，分别按压已选中项“系统权限”与未选中项“通用”“模型配置”）：
  - 浅色与深色所有测试项在 `leftMouseDown` 期间侧栏像素差异均为 `changedPixels=0, maxDelta=0`。
  - `leftMouseUp` 正常切换对应设置页，并已人工查看浅色、深色按压中与松开后的实际窗口截图。

## 边界

- 仅移除设置窗口左侧导航菜单（`SettingsSidebar`）的点击按压变色闪动，未改动其他页面中的 `.buttonStyle(.plain)` 按钮。
- 验证完成后已清理临时构建目录 `build/DerivedData-sidebar-press`。
