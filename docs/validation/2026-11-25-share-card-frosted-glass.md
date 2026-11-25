# 分享卡片磨砂玻璃通透度与边缘还原验证

日期：2026 年 11 月 25 日

## 问题原因

1. 分享预览弹窗（[`ChatSharePreviewSheet`](../../App/Sources/ChatShareCard.swift)）中的预览卡片改用了 `.nativeGlassBackground(in: cardShape)`（原生液态玻璃），在浅色模式下表面偏白、不透明度偏高，遮挡了底层风景的背景模糊层次，同时四周带有明显的液态玻璃折射亮边，失去原先磨砂玻璃的观感。
2. 分享卡片导出视图（[`ChatShareCardView`](../../App/Sources/ChatShareCard.swift)）中的 `glassTint` 与对角 `glassSheen` / `glassBorder` 高光叠加后偏厚偏亮，也偏向液态玻璃边缘风格。

## 变更范围

- 分享卡片预览与导出视图（[ChatShareCard.swift](../../App/Sources/ChatShareCard.swift)）：
  - 提取统一的 `ShareCardFrostedGlassStyle`，降低浅色/深色底色不透明度（浅色 `0.28`、深色 `0.26`），改用轻柔的纵向漫反射光泽与柔和磨砂玻璃细描边（去除对角高反差液态玻璃亮边）。
  - 将 `ShareCardBackdropCache` 模糊半径调整为 `22`（饱和度 `1.32`、对比度 `1.04`），让背景风景色彩与轮廓透过磨砂玻璃更清晰自然。
  - 将 `ChatSharePreviewSheet` 预览卡片恢复为与导出卡片一致的对齐模糊背景 + `ShareCardFrostedGlassStyle` 磨砂玻璃实现，并保留顶部关闭按钮、范围切换与底部圆形操作按钮的原生玻璃样式。

## 已执行验证

1. 工程生成与 Debug 构建：
   ```sh
   xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build
   ```
   结果：构建成功（`** BUILD SUCCEEDED **`）。

2. 分享卡片回归与渲染结果核查：
   ```sh
   python3 App/Tests/run-agent-reply-regression.py --share-and-user-reply
   ```
   结果：全部通过（退出码 0）。
   - 检查重新生成的 `build/share-card-light.png` 与 `build/share-card-dark.png`：浅色与深色卡片均呈现通透自然的磨砂玻璃质感，背景模糊层次清晰，正文可读性稳定，边缘无液态玻璃折射亮边。

3. 核心包自动化测试：
   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
   ```
   （工作目录 `Packages/KulaCore`）
   结果：16 个测试套件共 91 项测试全部通过（退出码 0）。
