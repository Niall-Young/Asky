# 启动器与 AI 保留原生玻璃折射

## 修正

底部操作按钮继续使用原生 Clear 材质，但移除 `glassOpacity: 0.6`，使用默认完整强度。此前的 60% 实际为整层玻璃透明度，会同时淡化折射与高光，不是独立底色强度。原生 Clear 材质自身保持透明观感；主操作、访达操作、更多和复用同样式的剪贴板按钮同步修改。

AI 头像的原生变形玻璃表面也移除静止时 60% 透明度；右上角置顶/关闭按钮组与输入框移除 `glassOpacity: 0.60`，使用完整 Clear 玻璃。头像展开后的 Regular 菜单保持原实现。

README 中英文与设计系统同步修正文案。没有修改共享玻璃实现、窗口背景或展开后的菜单材质。

## 已执行

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，43 项 Swift Testing 测试。
- AI 三处调整后重新运行上述构建与 KulaCore 测试，均通过。
- 退出旧的 Debug 进程并通过 `open -n build/DerivedData/Build/Products/Debug/Asky.app --args --show-agent` 打开新构建的 AI 窗口，确认实际运行路径为 `build/DerivedData/Build/Products/Debug/Asky.app/Contents/MacOS/Asky`。
- 本次未重新运行此前失败的操作区快捷键回归，未声称菜单交互通过；新版本的折射观感交由用户在实际背景下确认。
- README 检查完成并同步两种语言；AGENTS.md 无新增命令、边界或持久规则变化，保持不变。构建产物沿用既有 `build/` 忽略规则。
