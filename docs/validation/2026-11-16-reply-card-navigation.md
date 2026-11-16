# 回复卡片定位原回复

## 行为

- 已发送消息中的整条回复预览卡片可点击，保留既有卡片外观；文字选区标签和输入区卡片的交互不变。
- 以约 0.22 秒先快后慢的快速滚动定位到原回答的开头：气泡顶部位于工具栏下方 12 pt，正文距视口顶部 90 pt；滚动受真实内容边界限制，不插入额外空白。
- 原回复在较早历史页或另一个时间线存储段时，按消息 ID 查询并加载前后各最多 40 条，保持当前会话、草稿及最多 120 条的窗口约束；支持返回最新消息。
- 重复点击仍可定位；手动滚动立即取消动画和后续布局修正；开启系统减少动态效果时直接定位。生成期间不允许跨页替换活动回复；原回复不可用时显示错误反馈并保留当前内容。

## 实际运行

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：369 项 Swift Testing、5 项 XCTest 通过。首次未指定 Xcode 工具链的运行因找不到 XCTest 失败，切换后通过。
- `python3 App/Tests/run-agent-reply-regression.py --reply-navigation`：通过。用真实窗口鼠标 down/up 点击已发送的卡片，覆盖跨存储段分页、长短回复顶部位置、重复定位、动画中间位置、动画中手动滚动接管、草稿保留、原生回到底部按钮、缺失消息和活动回复保护。
- 复用此次编译的 `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression`，分别运行 `--reply-navigation --preview-macos14`、`--reading-scroll`、`--paging`：全部通过。现有阅读回归的三次回到底部间隙均为 0 pt。
- 动画采样：普通分支在 100 ms 检查时偏移从 331.28 pt 过渡到 203.64 pt，兼容分支从 330.08 pt 过渡到 230.59 pt，随后均到达目标；两条路径的动画中断检查均通过。
- `python3 App/Tests/check-localization.py`：175 个 Swift 源文件的语言对齐、格式参数及静态键检查通过。
- 检查 `build/reply-navigation.png`：目标长回复从开头显示，正文位于工具栏下方；截图由原生窗口缓存生成，不用它判断系统玻璃合成效果。
- `codesign --verify --deep --strict build/DerivedData/Build/Products/Debug/Asky.app`：通过。重启本地 Debug 后核对 PID 62341，实际运行路径为当前仓库的 `build/DerivedData/Build/Products/Debug/Asky.app/Contents/MacOS/Asky --show-agent`。

## 范围

兼容分支在当前 macOS 强制运行，不代表 macOS 14 真机验收。未调用模型或发布 Release。README 中英文已同步行为与回归命令；日志、截图和构建产物沿用现有 `build/` 忽略规则。
