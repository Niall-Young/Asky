# AI 回复气泡跟随宠物配色

## 改动

- AI 回复和三点等待气泡跟随当前宠物颜色，支持蓝、黄、紫、绿、粉；已有回复随选择同步更新。
- 用户气泡保留中性色，文字保持既有语义颜色；布局、表单输入表面和气泡内距不变。
- 每种配色提供深浅外观底色，常规为 90% 不透明度，降低透明度或增强对比度时使用不透明填充。
- README 中英文及设计系统已同步；AGENTS.md 无新增命令、边界或持久规则，保持不变。

## 已执行

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（318 个 Swift Testing 测试及 2 个 XCTest 测试）。
- `python3 App/Tests/run-agent-reply-regression.py --window-glass`：气泡完整回复、等待状态、历史恢复及原生玻璃深浅外观与尺寸检查通过。
- 使用该脚本新编译的 `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --scroll-preview`，经原生 UI 逐一选择五种宠物颜色：确认左侧已有 AI 回复同步变色、右侧用户消息保持灰色。
- `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --preview-macos14 --macos14-checks`：兼容分支深浅外观与滚动检查通过；人工查看生成的浅色和深色截图，蓝色 AI 气泡与灰色用户气泡区分清晰。
- `git diff --check`：通过。

日志、截图和预览构建均保存在已忽略的 `build/` 下，沿用现有忽略规则。未验证正式安装包、真实 macOS 14 系统、辅助功能开关的实际系统交互及全部五色的浅色玻璃实景；未发布或替换日常安装。
