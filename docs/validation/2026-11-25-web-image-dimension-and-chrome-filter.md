# 网页配图真实像素校验、HTML 清壳与维基百科 REST 通道验证

日期：2026-11-25

## 问题根因

1. 商业站点（如携程景点页）HTML 顶部混有空 `alt` 的页面 UI 箭头图标（例如 URL 含 `_W_2048_1536.png` 但真实尺寸仅 `32 × 32`、775 字节的右箭头 `>` PNG）以及评分徽章 `gs-dianping-score-5.png`。
2. `WebPageImageService` 原实现直接正则扫描未清洗的整页 HTML `<img>`，只检查显式 `width`/`height` 属性和 `.svg`/`.ico`，且未探测真实像素宽高。
3. `ChatImageService.availableImages` 发布前虽然已下载并用 `CGImageSource` 解码，但未拦截小图标与极端长宽比图片，导致 32×32 图标在 220×220 展示卡片中被拉伸成马赛克箭头。

## 修复内容

- [ChatImageService.swift](../../Packages/KulaCore/Sources/ToolService/ChatImageService.swift)：新增 `ImageDimensions`、`isAcceptableIllustration(width:height:)`（短边 `>= 120`、长边 `>= 180`、面积 `>= 28,000` 且长宽比 `<= 4:1`）、`illustrationDimensions(from:)` 与并发探测 `probeIllustrations(_:budget:maxConcurrent:)`；在 `availableImages(_:)` 发布前校验中复用真实像素门槛，并缓存已解码缩略图与原始宽高。
- [WebPageImageService.swift](../../Packages/KulaCore/Sources/ToolService/WebPageImageService.swift)：
  - 对 `*.wikipedia.org/wiki/...` 条目优先走公开 Wikipedia REST `summary` + `media-list` 接口，提取带图注的实景图并按文件名去重；
  - 扫描普通 HTML `<img>` 前剥离 `<nav>`、`<footer>`、`<aside>`、`<button>`、`<svg>`、`<template>`、`<form>` 壳层，过滤 `aria-hidden`、`role=presentation/none`、内联小尺寸/隐藏样式、UI 图标类名及常见 UI 图标路径（同步覆盖 `WebPageImages`）；优先排列带 `alt` 的正文图与带标题的 `og:image`/`twitter:image`；
  - 返回候选前经 `ChatImageService.shared.probeIllustrations` 并发探测真实宽高，剔除小图标/失效图并附带真实 `width`/`height`。
- [WebReadPageTool.swift](../../Packages/KulaCore/Sources/Adapters/WebReadPageTool.swift)、[NativeAgentPrompt.swift](../../Packages/KulaCore/Sources/AgentHost/NativeAgentPrompt.swift) 与 [Core.strings](../../Packages/KulaCore/Sources/Contracts/Resources/zh-Hans.lproj/Core.strings) / [Core.strings](../../Packages/KulaCore/Sources/Contracts/Resources/en.lproj/Core.strings)：将真实 `width`/`height` 传给模型并引导优先选择带准确 `alt` 且尺寸清晰的正文/封面实拍图。
- [native-tools-and-mcp.md](../native-tools-and-mcp.md)：同步更新公开网页配图候选提取、Wikipedia REST 通道、真实像素探测与发布前拦截说明。

## 验证结果

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（全部 XCTest 与 Swift Testing 83 tests in 15 suites 通过，含 `ChatImageTests`、`WebPageImageServiceTests`、`WebPageImagesTests` 新增用例）。
- `ASKY_LIVE_WEB_IMAGES=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter livePhotoReadThroughToolService`：通过（读取 `https://en.wikipedia.org/wiki/Capybara` 返回 8 个候选并经 `ChatImageService` 解码水豚照片）。
- `ASKY_LIVE_WEB_IMAGES=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter liveQiandaohuWikipediaAndCtripExcludeTinyArrowIcons`：通过（维基百科千岛湖首图为 `1280x851` 且 `alt=千岛湖（浙江水庫）`；携程千岛湖页面已完全排除 `32x32` 的 `25t0e12000gkhucin9310` 箭头图与 `gs-dianping-score-5.png` 评分图标，其余返回候选均为 `180x180`–`300x300` 实拍图）。
- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：`BUILD SUCCEEDED`。
