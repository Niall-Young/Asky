# 提醒卡片布局与样式优化

- 变更文件：`App/Sources/ReminderBanner.swift`
- 调整内容：
  - 将 36×36 pt 高饱和蓝色渐变左侧图标重构为标题行内 22×22 pt 柔和语义色底板图标（日程蓝 / 出行青绿），正文与标题均全宽左对齐，消除左侧大面积空列及中文末尾两字孤行换行
  - 区分多行正文的元数据首行（12.5 pt medium）与说明正文（13 pt regular，2.5 pt 行距），收敛卡片垂直节奏与光学内距（顶 13 / 底 14 / 左右 16 pt）
  - 将悬停关闭按钮置入顶部右侧与时间标签同位切换，避免位置偏移；增加按钮悬停高亮、按压缩放与箭头指针反馈
  - 将操作按钮主按钮调整为随浅/深色外观自适应的高对比单色胶囊，次按钮保留低对比半透明胶囊与细描边
  - 将展开态卡片间距增至 10 pt，按浅/深色外观柔化卡片投影，退场动画改用 `easeOut(duration: 0.22)`
- 验证：
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build` 通过
  - `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` 全部通过
  - 启动 `build/DerivedData/Build/Products/Debug/Asky.app/Contents/MacOS/Asky --test-banner` 并截取真实窗口检查（产物位于已忽略的 `build/reminder-redesign/preview.png`），确认双卡片排版、单行正文、图标与按钮对比度正常
