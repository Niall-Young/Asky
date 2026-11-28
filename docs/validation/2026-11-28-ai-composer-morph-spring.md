# AI 输入框收起与展开弹簧动画调优验证（2026-11-28）

## 变更范围

- [AgentView.swift](../../App/Sources/AgentView.swift)：将 `ComposerMorphMotion.animation(isCompact:reduceMotion:)` 的弹簧参数由收起 `response: 0.38, dampingFraction: 0.80, blendDuration: 0.1` / 展开 `response: 0.34, dampingFraction: 0.76, blendDuration: 0.1` 调整为收起 `response: 0.25, dampingFraction: 0.64` / 展开 `response: 0.24, dampingFraction: 0.60`，加快形变响应并增强弹性回弹手感。
- [design-system.md](../design-system.md)：同步更新 2026-11-28 单行液态玻璃输入框变形弹簧参数记录。

## 实际执行验证

1. `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过。
2. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（91 tests in 16 suites passed）。
3. `python3 App/Tests/run-agent-reply-regression.py --composer-focus`：通过（`Composer focus regression passed: initial show, close+reopen, visible re-show, and quote focus verified`）。
