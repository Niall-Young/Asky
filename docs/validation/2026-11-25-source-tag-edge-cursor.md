# 修复引用来源标签边缘光标来回切换

日期：2026-11-25

## 问题根因

1. `ChatInlineNativeText` 在 `NSTextView.linkTextAttributes` 中全局设置了 `.cursor: NSCursor.pointingHand`。AppKit 会将 `linkTextAttributes` 覆盖在带 `.link` 属性的字符之上，导致引用来源标签附件上的 `.cursor: NSCursor.arrow` 被覆盖为手型光标。
2. `ChatSourceTextView` 既在 `updateTrackingAreas()` 中叠加了重复的 `[.cursorUpdate, .mouseMoved]` `NSTrackingArea`，又在 `mouseMoved(with:)` 中先调用 `super.mouseMoved(with:)`（触发原生设置 `pointingHand` 或 `iBeam`），再把 `.mouseMoved` 事件传给 `cursorUpdate(with:)`（在标签内覆盖回 `arrow`，在标签外调用 `super.cursorUpdate(with:)` 触发 `-[NSEvent trackingArea]` 异常），造成标签内部与边缘临界区光标反复切换。

## 变更范围

- [ChatMarkdownView.swift](../../App/Sources/ChatMarkdownView.swift)：
  - 从 `view.linkTextAttributes` 移除 `.cursor`，改为仅在正文直达链接（`isDirectOpenableLink`）的属性串片段上设置 `.cursor: NSCursor.pointingHand`，让引用来源标签附件上的 `.cursor: NSCursor.arrow` 直接由 `NSTextView` 原生生效。
- [ChatSourcePreview.swift](../../App/Sources/ChatSourcePreview.swift)：
  - 移除 `ChatSourceTextView` 中冗余的 `sourceTrackingArea`、`updateTrackingAreas()`、`cursorUpdate(with:)` 与 `mouseMoved(with:)` 覆写，统一复用父类 `ChatSelectableTextView` 的 `ActionArrowCursor.applyIfCovered` 遮挡保护与 `NSTextView` 单一原生光标追踪路径。
- [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)：
  - 在 `sourcesPreview()` 中新增回归断言：验证 `linkTextAttributes` 不含 `.cursor`、正文直达链接保留 `pointingHand`，并对来源标签四条边缘以 `0.25 pt` 步进扫描 `cursorUpdate` 与 `mouseMoved`，确认四边均与 `source(at:)` 完全一致且每条边仅发生一次干净的 `iBeam ↔ arrow` 切换。

## 实际执行的检查

- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：通过（`** BUILD SUCCEEDED **`）。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（全部 Swift Testing 与 XCTest 套件通过，0 失败）。
- `PYTHONDONTWRITEBYTECODE=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --sources-preview`：通过（包含直达链接光标校验与来源标签四边 `0.25 pt` 光标切换扫描，并目视核对新生成的 `build/sources-light.png`）。
- `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --header-cursor-preview`：通过（120 组滚动正文遮挡区同步 `cursorUpdate`/`mouseMoved` 光标回归全部通过）。

## 维护门禁结论

- `AGENTS.md: unchanged` — 仅修复引用来源标签的光标冲突与重复追踪逻辑，不改变项目架构边界、开发命令或持久协作规范。
- `README: unchanged` — 内部 AppKit 光标缺陷修复，不改变 README 描述的功能入口或构建测试命令。
