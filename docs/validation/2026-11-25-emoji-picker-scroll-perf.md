# 聊天展开表情选择器滚动性能优化验证（2026-11-25）

## 优化范围

- [ChatEmojiGridScrollView.swift](../../App/Sources/ChatEmojiGridScrollView.swift)：
  - 用原生 AppKit `NSScrollView`（`EmojiGridNSScrollView` + `EmojiGridDocumentView`）替代原本嵌套在 `ScrollView` 中的 8 组 SwiftUI `LazyVGrid` 与 `GeometryReader` / `PreferenceKey` 逐帧上报，将 600+ 枚表情的布局、命中测试与分组同步收敛为静态预计算几何（`ChatEmojiGridLayout`）的 O(1)/O(log N) 运算。
  - 引入线程安全的 Retina 位图缓存（`ChatEmojiGlyphCache`）并在快捷表情胶囊出现时后台低优先级预热全量表情位图；文档视图启用 `wantsUpdateLayer = true` 避免分配整张长画布缓冲，仅按可见区域加 2 行预加载缓冲复用约 80～96 个 `CALayer`，实现零视图创建/销毁滚动。
  - 滚动期间自动屏蔽/清除单元格悬停残留，并在 `ChatEmojiPickerScrollState` 中隔离 `activeCategoryID`，切换高亮分类时仅重绘顶部 8 枚分类图标，不触发网格视图更新。
- [ChatBubbleMenu.swift](../../App/Sources/ChatBubbleMenu.swift)：
  - `ChatEmojiFullPickerView` 接入 `ChatEmojiGridScrollView` 与 `ChatEmojiCategoryTabBar`。
  - 将原本挂在 600+ 枚表情按钮及快捷栏子按钮上的 `.actionArrowCursor()` 收敛为面板级与快捷栏级单一 `ActionArrowCursor`，消除滚入/滚出视口时大量 `CursorView` 与 `NSTrackingArea` 的频繁拆建与全表扫描。
  - 快捷表情栏出现时触发 `ChatEmojiGlyphCache.shared.prewarmCatalog(scale:)` 后台预热。
- [AgentReactionRegression.swift](../../App/Tests/AgentReactionRegression.swift)：
  - 在 `--bubble-menu-preview` 中增加浅色与深色模式下的连续 24 帧滚轮高速滚动回归（验证原生 `NSScrollView` 持续推进超过 2000 pt、弹层不关闭并截取 `build/bubble-menu-emoji-expanded-scrolled-{light,dark}.png` 人工核验）。

## 已运行验证

1. 应用工程生成与 Debug 构建：
   - 命令：`xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`
   - 结果：构建通过（`** BUILD SUCCEEDED **`），新增与改动文件无编译警告。
2. `KulaCore` 单元测试：
   - 命令：`(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)`
   - 结果：全部通过。
3. 表情与气泡菜单原生回归及实际窗口视觉验收：
   - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --reactions-preview`：通过。
   - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --bubble-menu-preview`：通过；连续 24 次滚轮爆发滚动覆盖 2083 pt（浅色，0.247 s）与 2125 pt（深色，0.232 s），随后点击 `旅行与地点` 分类跳转并点击网格内表情正常更新消息回应。
   - 实际窗口截图人工检查通过：`build/bubble-menu-emoji-expanded-above-{light,dark}.png`、`build/bubble-menu-emoji-expanded-scrolled-{light,dark}.png`、`build/bubble-menu-emoji-expanded-category-{light,dark}.png`（液态玻璃背景、圆角裁剪、标题清晰度、表情居中、选中框与右上角对勾角标、滚轮滚动后顶部 `🍕 食物与饮品` 分类高亮同步均正常）。
