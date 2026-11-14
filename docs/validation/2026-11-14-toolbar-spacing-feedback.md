# 对话窗口右上按钮间距与局部高亮

- 两个原生按钮从各 36 × 36 pt 改为 48 × 36 pt，共用 96 × 36 pt Clear 玻璃胶囊；图标仍为 18 pt。中心距从 36 pt 增至 48 pt，每侧外留白增加 6 pt。
- 悬停与按下分别记录按钮索引，高亮裁剪到对应左半或右半；保留胶囊整体按压回弹与减少动态效果设置。
- `xcodegen generate`、README 中的 Debug `xcodebuild` 与 `Packages/KulaCore` 的 `swift test` 均实际通过。日志位于忽略的 `build/toolbar-build.log` 和 `build/toolbar-core-tests.log`。
- 通过原生界面工具查看新 Debug 窗口，确认加宽布局，并点击置顶确认状态切换为“取消置顶”。实际运行路径为 `build/DerivedData/Build/Products/Debug/Asky.app`。
- 按住期间截图未完成：日常 Debug 应用验证被其他操作修改/重启中断；独立预览的截图只取得松开后的状态，未据此宣称按下高亮实测通过。点击关闭后界面读取超时，因此不将关闭结果记为通过。左右按下、悬停的动态观感仍需人工确认。
- 临时独立预览复用实际 App 源码和临时数据，经修正事件循环后已成功接入界面工具，并验证加宽布局和置顶状态切换。所有临时程序与构建产物沿用现有 `build/` 忽略规则。
- README 中英文已同步尺寸和局部高亮行为；AGENTS.md 无新增持久规范，保持不变。
