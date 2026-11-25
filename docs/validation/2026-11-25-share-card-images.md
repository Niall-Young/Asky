# 分享卡片图片导出修复验证

日期：2026 年 11 月 25 日

## 问题原因

分享预览窗口（`ChatSharePreviewSheet`）内的 `ChatShareCardContent` 未指定自定义图片提供器，默认回落到 MarkdownUI 的异步网络加载 `DefaultImageProvider`（`NetworkImage`）。在实时窗口预览中，异步请求完成后图片会显示；但点击复制图片、保存图片或系统分享时，`ChatShareCardRenderer.renderPNG` 通过 `SwiftUI.ImageRenderer` 做单帧同步快照，不会等待异步图片加载，导致导出的 PNG 中所有配图消失并留下空白段落间隙。

## 变更范围

- 分享卡片图片预加载与同步渲染（[ChatShareCard.swift](../../App/Sources/ChatShareCard.swift)）：
  - 新增 `ChatShareCardContent.imageURLs(in:)`，忽略围栏代码块和行内代码，提取分享卡片中的远端图片地址。
  - 在 `ChatShareCardContent` 中复用 `ChatImageGalleryContent.parts(_:)` 拆分正文与独立配图区块，并接入 `ShareCardImageGrid`（单图保持自然纵横比并限制最大高度，多图按 2/3 列等宽圆角方格排版）以及自定义 `ShareCardMarkdownImageProvider` / `ShareCardInlineImageProvider`，全部通过 `ToolService` 的 `ChatImageService.shared` 读取与缓存，不再使用 `NetworkImage`。
  - 新增 `ChatShareCardRenderer.loadImages(...)` 与 `renderPNGLoadingImages(...)` 并发预加载并离线解码 `CGImage`，支持 `ImageRenderer` 同步绘制。
  - 在 `ChatSharePreviewSheet` 中打开预览或切换分享范围时预加载图片并在预览与导出间复用；若用户点击复制、保存或系统分享时尚未加载完成，会先等待图片就绪再导出 PNG。
- 回归测试（[AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)）：在 `shareAndUserReplyRegression` 中新增图片 URL 提取、单图与三图网格导出 PNG 高度及像素采样验证，以及加载失败时无空白破图回退检查。

## 已执行验证

1. 工程生成与 Debug 构建：
   ```sh
   xcodegen generate
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build
   ```
   结果：构建成功（`Asky` 与 `asky-mcp` 全部通过，`ChatShareCard.swift` 零警告）。

2. 原生界面回归与视觉核查：
   ```sh
   python3 App/Tests/run-agent-reply-regression.py --share-and-user-reply
   python3 App/Tests/run-agent-reply-regression.py --image-gallery
   ```
   结果：全部通过。
   - `Share card light: 1200x788 (1384627 bytes)`
   - `Share card dark: 1200x788 (1415208 bytes)`
   - `Share card single-image: 1200x1472 (teal samples: 41735)`
   - `Share card multi-image: 1200x764 (samples: teal=5700, coral=5680, amber=5680)`
   - 实际检查 `build/share-card-single-image.png`、`build/share-card-multi-image.png`、`build/share-card-light.png` 与 `build/share-preview-window.png`，确认单图、三图网格和纯文字卡片的圆角边框、间距与代码块保护均符合预期。

3. 核心包自动化测试：
   ```sh
   (cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
   ```
   结果：全部通过（Swift Testing 全部 12 个测试目标共 445 个用例与 XCTest 12 个用例均 0 失败）。

## 未覆盖范围

- 真实公网远端图片在慢网速或超时场景下的分享窗口等待交互，以及正文行内小图（非独立段落图片）的 `ImageRenderer` 导出，仍以日常真机使用为准。
