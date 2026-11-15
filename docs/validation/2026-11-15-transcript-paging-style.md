# 时间线翻页按钮样式

- 问题：顶部「加载更早的消息」使用链接样式，父级 VStack 间距为 0，按钮与第一条消息直接相邻。
- 调整：上下翻页入口共用居中胶囊按钮，28 pt 高、12 pt medium 次要文字、左右 14 pt 内距与语义中性底色；与消息之间留出 16 pt。复用已有悬停和按压反馈，保留运行时禁用、阅读位置保持及分页逻辑。
- 既有原生滚动回归补充顶部截图，并按 28 pt 按钮高度更新底部点击坐标。

## 已执行

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，Swift Testing 62 项。
- `python3 App/Tests/run-agent-reply-regression.py --scroll-stability`：通过；反复滚动高度稳定，实际点击上下翻页按钮成功，向前加载后阅读位置保持，返回最新消息成功。
- 查看新编译原生窗口的 `build/scroll-older-button.png` 与 `build/scroll-newer-button.png`：深色下按钮居中、胶囊轮廓完整，上方入口与第一条消息之间有清晰留白。

## 验证范围

截图来自实际聊天视图的原生回归窗口，使用测试消息；缓存截图用于核对布局，不作为窗口玻璃合成效果的证据。本次未单独检查浅色、悬停或按压截图，未替换已安装版本。

README: unchanged — 此次仅调整已有翻页入口的样式与间距，不改变使用方式、构建命令或功能范围。构建与截图沿用现有 `build/` 忽略规则。
