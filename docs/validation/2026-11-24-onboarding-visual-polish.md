# 欢迎引导视觉与交互优化验证

2026-11-24，根据实机反馈完成 `App/Sources/OnboardingWindow.swift` 二轮视觉打磨，并通过以下验证：

- **KulaCore 单元测试**：使用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 运行 `cd Packages/KulaCore && swift test`，全部通过。
- **Debug 构建**：运行 `xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`，构建与签名成功。
- **实机视觉与交互验收**：启动 `build/DerivedData/Build/Products/Debug/Asky.app --args --show-onboarding`，确认窗口尺寸精准保持 `600 × 460`，依次核验全部 4 页截图：
  - **窗口与圆角统一**：恢复 `.miniaturizable` 与 `toolbarStyle = .unified`，完整保留三颗原生红绿灯并与窗口外圆角同心；移除视图层硬编码圆角裁剪，由系统窗口与原生 `NSGlassEffectView` 统一管理外框圆角，内部卡片统一 16 pt 连续圆角、图标槽统一 8 pt 连续圆角。
  - **极简疏朗的欢迎首页**：移除堆砌文字的三行功能说明卡片，仅保留 92 pt App 图标与柔光层次、27 pt 标题、14.5 pt 副标题以及大方舒展的 40 pt 胶囊按钮（「跳过」与「开始设置」）。
  - **舒展统一的向导步骤页**：权限、快捷键、AI 助手三页均采用 48 pt 左右宽边距、精简文案、16 pt 圆角分组卡片及 38 pt 底部操作按钮，无拥挤或裁切。
