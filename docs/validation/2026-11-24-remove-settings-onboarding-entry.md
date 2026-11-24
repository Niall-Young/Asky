# 移除设置页中的“欢迎引导”入口

## 改动摘要

- 在 [AboutSettings.swift](../../App/Sources/AboutSettings.swift) 中移除“关于 Asky”顶栏的“欢迎引导”按钮，仅保留 `GitHub` 按钮。
- 清理仅服务于该设置入口的回调与方法：移除 [AppModel.swift](../../App/Sources/AppModel.swift) 中的 `onOpenOnboarding` 与 `openOnboarding()`，移除 [AskyApp.swift](../../App/Sources/AskyApp.swift) 中对应的绑定并去掉 `openOnboarding()` 不再需要的 `@objc` 标记。首次启动引导与 Debug `--show-onboarding` 入口保持不变。
- 从 [en.lproj/Localizable.strings](../../App/Resources/en.lproj/Localizable.strings) 与 [zh-Hans.lproj/Localizable.strings](../../App/Resources/zh-Hans.lproj/Localizable.strings) 移除不再使用的 `"欢迎引导"` 文案键。
- 同步更新 [README.md](../../README.md) 中英文说明，去掉在“设置 › 关于 Asky › 欢迎引导”重新打开欢迎引导的描述。

## 实际验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（15 个 suite，83 项测试全部通过）。
