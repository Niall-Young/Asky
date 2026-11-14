# 自然消息流与长回答阅读位置

## 修改

- 删除当前轮接近一屏的最小高度；气泡按实际内容高度连续排列，短消息不再把本轮问题顶到窗口顶部。
- 新用户消息和等待气泡跟随正常底部；完整回答出现后，滚动目标取正常底部与回答起点之间较靠上的位置。长回答的气泡顶部停在工具栏下方 12 pt，正文另保留既有 14 pt 内距，用户问题允许被推上去。
- 短会话首次打开仍从顶部排列。历史重开沿用相同规则。手动滚动会停止自动定位，主动回到底部仍一次到达末尾。
- 继续使用实际原生文本与视口尺寸计算，兼容当前 SwiftUI 滚动分支和 macOS 14 分支。

## 已执行且通过

- `xcodegen generate`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`
- `(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)`
- `python3 App/Tests/run-agent-reply-regression.py --bottom-push`：固定 560 × 680 窗口，连续短消息共享一屏，历史溢出后发送新消息到正常底部，超长用户问题可被推上去，长回答开头可见，七行短回答完整显示且底部无额外整轮占位。
- 随后复用上述脚本刚编译的 `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression`，依次执行并通过：
  - `--reading-scroll`
  - `--reading-scroll --scroll-history`
  - `--restored-transcript`
  - `--restored-transcript --restored-long-reply`
  - `--bottom-push --preview-macos14`
  - `--restored-transcript --restored-long-reply --preview-macos14`
- 历史短回复恢复位于自然底部；长回复冷打开和连续两次关闭重开均保留回答起点；手动阅读后不抢回位置，回到底部三次点击检查的底部差值均为 0 pt。
- 已查看实际原生回归窗口导出的 `build/bottom-push-{before,after,completed,short}.png`，确认短消息连续布局、长回复从开头阅读、短回复保留前文且不留整屏空白。

已重新启动 `build/DerivedData/Build/Products/Debug/Asky.app --show-agent`；完整进程路径与启动时间确认晚于本次二进制构建时间。

## 验证范围与文档

回归使用临时会话与实际 App 界面，没有向真实模型发送测试问题。macOS 14 仅在当前系统强制走兼容分支，未在 macOS 14 真机运行。窗口截图采用原生离屏缓存，玻璃合成表现不作为本次滚动验收依据。

README 中英文、PRD 与设计系统同步消息流规则；AGENTS.md 无新增边界或命令，保持不变。构建、截图与工程使用既有忽略规则，没有新增忽略项。
