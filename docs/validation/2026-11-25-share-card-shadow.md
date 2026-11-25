# 分享卡片导出阴影减重验证

日期：2026 年 11 月 25 日

## 问题原因

[`ChatShareCardView`](../../App/Sources/ChatShareCard.swift) 在导出分享卡片 PNG 时存在两处导致阴影偏重的因素：

1. `.shadow(...)` 直接挂在带 `glassTint`、`glassSheen` 与 `strokeBorder(glassBorder, lineWidth: 1)` 叠层的背景容器上，未先 `.compositingGroup()` 合成，SwiftUI 会对圆角卡片主体与高亮描边分别投射阴影，边缘形成叠加暗边。
2. 原先参数为 `.black.opacity(isDark ? 0.42 : 0.18)`、`radius: 26`、`y: 12`，在浅色冰川背景上形成偏灰偏重的四周阴影光晕（顶部与底部边缘尤为明显）。

## 变更范围

- 分享卡片导出视图（[ChatShareCard.swift](../../App/Sources/ChatShareCard.swift)）：
  - 在 `ChatShareCardView` 的卡片背景叠层与描边后补齐 `.compositingGroup()`，确保仅按单一完整玻璃卡片轮廓投射一次阴影。
  - 将浅色模式阴影调整为冷色低透明度 `Color(red: 0.08, green: 0.14, blue: 0.24).opacity(0.08)`、`radius: 16`、`y: 6`；深色模式同步收轻为 `Color.black.opacity(0.24)`、`radius: 18`、`y: 8`。

## 已执行验证

1. 工程生成与 Debug 构建：
   ```sh
   xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build
   ```
   结果：构建成功（`** BUILD SUCCEEDED **`）。

2. 分享卡片原生回归与视觉核查：
   ```sh
   python3 App/Tests/run-agent-reply-regression.py --share-and-user-reply
   ```
   结果：全部通过（`Share card and user reply regression passed`）。
   - `Share card light: 1200x788 (1393405 bytes)`
   - `Share card dark: 1200x788 (1423153 bytes)`
   - `Share card single-image: 1200x1472 (teal samples: 41735)`
   - `Share card multi-image: 1200x764 (samples: teal=5700, coral=5679, amber=5680)`
   - 实际检查重新渲染的 `build/share-card-light.png`、`build/share-card-single-image.png` 与 `build/share-card-dark.png`，浅色卡片四周重灰光晕消失、顶部边缘干净通透，深色卡片底部层次自然轻盈。

3. 核心包自动化测试：
   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
   ```
   （工作目录 `Packages/KulaCore`）
   结果：全部通过（退出码 0）。
