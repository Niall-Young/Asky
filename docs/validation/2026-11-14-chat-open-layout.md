# 聊天窗口打开时的历史布局

## 问题与修复

- 打开窗口时先显示空模型，再恢复历史；首次定位只调用一次 `scrollTo`，晚到的 LazyVStack、原生公式和表单测量会改变内容高度，让可视区域停在错误位置。
- 在创建/显示窗口前恢复历史；现代分支的首次锚点设为底部，保留后续尺寸变化的顶部锚点。
- 首次定位使用已有的底部校正，并在尚未操作的历史页面中响应实际文档尺寸变化；手动滚动、提交新消息、收到新回复或视图消失时退出初始跟随，避免干扰阅读和四行回复预览。

## 实际验证

- 修复前新增的 `--restored-transcript` 回归失败：首次打开底部偏差 `166 pt`，无需任何点击即可复现定位错误。
- 修复后 `--restored-transcript`：40 条不同高度历史，冷打开和两次关闭重开均为 `gap=0`，最后回复与可视区域相交；手动滚动后不会被拉回底部。
- `--restored-transcript --restored-long-reply`：最后一条含 24 段文字、公式和表格，以上断言通过。
- `--restored-transcript --restored-long-reply --preview-macos14`：兼容分支通过；这是当前系统上的兼容分支验证，未在 macOS 14 真机运行。
- `--bottom-push`：短/长历史的新消息定位、长回复前四行、短回复全部露出通过。
- `--reading-scroll --scroll-history`：长历史阅读位置、三次回到底部和后续回复保持位置通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` 通过。
- `xcodegen generate`、README 中的 Debug `xcodebuild` 命令及 `codesign --verify --deep --strict` 通过。
- 实际 Debug 应用使用 `--show-agent` 两次冷启动，经原生窗口截图确认：未点击聊天内容或回到底部按钮，已有公式/表格历史直接显示并到达最新回复底部。最终运行路径为本仓库 `build/DerivedData/Build/Products/Debug/Asky.app`。

中间版本仅增加短时定位校正时，简单文字测试通过，但真实复杂历史仍停在错误位置，因此补上文档尺寸变化跟随后才完成验收。没有发送真实模型请求，也没有发布 Release。

## 维护

- README 中英文同步新增恢复历史的回归命令。
- AGENTS.md 无需改动：沿用现有 App 窗口、系统接口及验证边界。
- 构建、截图和日志沿用 `build/` 忽略规则。同期出现的表单状态持久化修改不属于本次修复，提交时按 hunk 隔离。
