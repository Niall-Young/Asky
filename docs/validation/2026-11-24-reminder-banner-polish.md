# 提醒卡片布局与样式优化

- 变更文件：`App/Sources/ReminderBanner.swift`
- 调整内容：
  - 移除标题行内多余的分类图标底板，保留顶部左侧 Asky 应用图标，使标题、元数据与正文统一全宽左对齐，消除双图标上下堆叠与中文末尾两字孤行换行
  - 区分多行正文的元数据首行（12.5 pt medium）与说明正文（13 pt regular，2.5 pt 行距），收敛信息块内部间距（标题与元数据 3 pt、元数据与正文 4 pt），同时将头部到正文拉开至 10 pt、正文到操作区拉开至 18 pt（内距顶 14 / 底 14 / 左右 16 pt），形成清晰的三段视觉分组
  - 将悬停关闭按钮常驻于顶部右侧 `ZStack` 并复用静态 `closeIcon`，悬停时仅在右上角槽位切换透明度与命中状态，避免整卡触发 `withAnimation` 与 `NSViewRepresentable` 重建导致的图标闪烁；补齐按钮悬停高亮、按压缩放与箭头指针反馈
  - 将操作按钮主按钮调整为随浅/深色外观自适应的高对比单色胶囊，次按钮保留低对比半透明胶囊与细描边
  - 将展开态卡片间距增至 10 pt，按浅/深色外观柔化卡片投影，退场动画改用 `easeOut(duration: 0.22)`
- 验证：
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build` 通过
  - `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` 全部通过
  - 启动 `build/DerivedData/Build/Products/Debug/Asky.app/Contents/MacOS/Asky --test-banner` 并截取真实窗口检查（浅色 `build/reminder-redesign/preview.png`、深色 `build/reminder-redesign/preview-v2.png`、间距调整后 `build/reminder-redesign/preview-v3.png`，均位于已忽略目录），确认双卡片排版、三段间距节奏与按钮对比度正常
