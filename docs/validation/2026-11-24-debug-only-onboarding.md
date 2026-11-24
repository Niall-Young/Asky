# 仅在 Debug 版本保留欢迎页面

## 改动摘要

- 在 [AskyApp.swift](../../App/Sources/AskyApp.swift) 中将 `onboardingWindow`、首次启动触发逻辑（`!model.preferences.hasCompletedOnboarding`）、`--show-onboarding`、`applicationShouldHandleReopen` 中的引导窗口置前、`isQuietForUpdate` 中的引导窗口可见性检查以及 `openOnboarding()` 全部收入 `#if DEBUG`，确保 Release 版本不会触发或展示欢迎页面。
- 在 [AskyApp.swift](../../App/Sources/AskyApp.swift) 的菜单栏 `#if DEBUG` 区域内新增 `"预览欢迎页面"` 菜单项，与 `"预览提醒卡片"` 并列，便于在 Debug 构建中随时预览欢迎页面。
- 在 [OnboardingWindow.swift](../../App/Sources/OnboardingWindow.swift) 外层包裹 `#if DEBUG ... #endif`，避免 Release 构建编入欢迎页面实现。
- 在 [en.lproj/Localizable.strings](../../App/Resources/en.lproj/Localizable.strings) 与 [zh-Hans.lproj/Localizable.strings](../../App/Resources/zh-Hans.lproj/Localizable.strings) 中补齐 `"预览欢迎页面"` 的中英文文案。
- 同步更新 [README.md](../../README.md) 中英文“安装与配置 / Installation and Setup”说明，移除正式版首次启动自动打开欢迎引导窗口的描述。

## 实际验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Release -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（15 个 suite，83 项测试全部通过）。
