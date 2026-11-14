# 选区菜单侧向光照与取消选择

日期：2026-11-14。

## 交互与参考

读取用户提供的 `ScreenRecording_11-14-2026 22-29-37_1.MP4`（4.78 秒），提取右上角连体胶囊的左右按压帧。参考行为是按下侧逐渐提亮、经整块玻璃向另一侧自然衰减，并轻微向当前操作一侧扩张；没有按钮内部的小光斑或分割底板。视频没有展示文字选区取消。

选区菜单据此使用连续的中性侧向光照，左右分别追踪按压与悬停，移除统一高亮和按钮内部光斑；保留原有原生玻璃、无额外窗口阴影、按压与释放动画。按压时最大宽度增量仍为 3 pt，向当前操作一侧扩张。实现是 macOS 现有玻璃上的交互适配，不声称复现 iOS 的完整光学渲染。

点击文字区域外的空白处或按 Esc 时，关闭菜单并清除 NSTextView 的真实选区；Esc 不关闭聊天窗口。点击原文本内部保留原生重新选择，键盘快捷键不会在处理前被清空范围。操作执行后的菜单关闭同样清除选区。

## 已执行

- `xcodegen generate`、README 的 Debug `xcodebuild`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `python3 App/Tests/run-agent-reply-regression.py --selection-preview`：最终代码通过。覆盖浅深色、当前头像配色、空白点击清除真实选区、Esc 清除但保留窗口、拖出复制按钮取消操作、按压窗口扩张、释放反馈、添加引用与输入焦点、发送保存及历史恢复。
- 查看最终 `build/selection-dark-left-light.png`、`build/selection-pressed-menu.png`：左/右光照连续衰减，未出现按钮范围内的矩形光斑。视频抽帧存放于 `/tmp/asky-chatgpt-reference/`；未提交用户录屏或图片。
- `git diff --check`：通过；截图和编译输出沿用现有 `build/` 忽略规则。

README 中英文及设计系统只同步本次行为。AGENTS.md 无需更改，现有窗口、系统操作和构建规则继续适用。保留工作区其他未完成改动；本轮只提交选区菜单、对应回归和文档中的相关段落。
