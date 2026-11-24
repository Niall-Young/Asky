# 欢迎引导视觉与交互优化验证

2026-11-24，完成 `App/Sources/OnboardingWindow.swift` 及中英本地化文案重构，并通过以下验证：

- **本地化语法检查**：`plutil -lint App/Resources/zh-Hans.lproj/Localizable.strings App/Resources/en.lproj/Localizable.strings` 均返回 `OK`。
- **KulaCore 单元测试**：使用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 运行 `cd Packages/KulaCore && swift test`，全部通过。
- **Debug 构建**：运行 `xcodegen generate` 与 `xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`，构建与签名成功。
- **实机视觉与交互验收**：启动 `build/DerivedData/Build/Products/Debug/Asky.app --args --show-onboarding`，确认窗口尺寸为 `520 × 520`（移除空工具栏多余高度，顶部安全区对齐），依次走通欢迎页、开启常用权限、设置快捷键、配置 AI 助手全部 4 页并截图核验：
  - 原生 Liquid Glass 玻璃底板与柔和顶部环境光生效，左上角仅保留关闭按钮；
  - 欢迎页展示 App 图标柔光托盘、标题/副标题、三项核心能力卡片（快速搜索、剪贴板历史、原生 AI 助手）、主按钮「开始设置」与轻量次按钮「跳过」；
  - 权限、快捷键、AI 配置三步共用统一页头、14pt 圆角卡片、28pt 语义图标槽与底部 3 步进度指示器及操作栏；
  - 去除 AI 配置报错提示末尾中文句号，符合 `docs/design-system.md` 文案规范。
