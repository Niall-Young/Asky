# AI 回复图片栏与独立预览

日期：2026-11-17。环境：macOS 27.0.1，Xcode SDK 27.2，Debug 原生 App。

## 改动

- 连续独立图片与相邻来源标记组合为单排 220 × 220 pt 缩略图，8 pt 图间距，超宽横向滚动；左右按钮按实际滚动位置更新，200 ms 切换，减少动态效果时直接定位。
- 图片栏与前后文案统一间隔 14 pt。只移除紧邻图片的“照片”“图片”等通用标题；正常标题、正文引用、代码与嵌套内容保持为 Markdown。
- 左下下载，右下 MingCute link 来源按钮；两者均为 16 pt 图标、32 pt 原生 interactive Regular 玻璃圆形。下载成功显示勾号 1.2 秒后恢复。
- 点击缩略图打开独立 Regular 玻璃预览窗口，保留原生红绿灯，等比完整显示横图与竖图。通过既有 WindowPresentation 激活，关闭时释放图片视图，再次打开复用窗口。
- 原图下载、网络图片加载与来源 URL 跳转均复用 ToolService。聊天记录只改变展示，不重写存储内容。

## 已执行

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build
(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --image-gallery
```

- Debug 构建成功；核心 388 项测试通过。
- 图片解析回归通过：连续图片与不同来源配对、来源整段包含在链接内、来源后括号说明、来源引用式链接、无 alt 文本、多图同一行、保留普通链接与多来源正文、保留围栏/缩进代码与列表、保留公式地址、仅隐藏通用图片标题。
- 实际 Debug 历史消息的两张照片已重新渲染为同一行；无“照片”标题和来源段落，按钮位置、link 图标与上下间距经截图核对。
- 点击来源实际在默认 Chrome 打开对应人物页；验证用新标签已关闭。
- 点击下载观察到“已保存到下载文件夹”状态，随后恢复“下载图片”。
- 实际横图、竖图均打开独立预览窗口；观察到原生红绿灯，图片完整适配。关闭后再次打开另一张图成功。
- 用 `--image-gallery --preview` 的四图专用窗口验证：起点只显示右箭头，第一次右移出现左箭头，继续到最右隐藏右箭头；再连续左移回第一张，右箭头恢复、左箭头隐藏。该窗口只使用测试图片序列，不写入用户聊天记录，验收后已关闭。
- 最终 Debug 已重新启动，运行路径为 `build/DerivedData/Build/Products/Debug/Asky.app/Contents/MacOS/Asky`，保留原输入草稿。

## 验证范围

本次确认箭头的完整双向切换。自动化水平手势未产生可辨认位移，未将触控板手势记为实测通过。macOS 14 的坐标偏移回退、降低透明度与增强对比度未在对应环境复验；沿用现有材质回退。图片加载仍取决于外部图片链接。
