# AI 输入框发送按钮跟随 Agent 配色

- 将五色 RGB 提取为 `AgentAvatarColor.tint`，用户气泡继续使用原有浅色 8%、深色 12% 透明度。
- 发送及停止按钮的圆形底色绑定 `model.avatarColor.tint`，禁用时保留 30% 底色；图标使用 80% 黑色以适配浅色配色。
- 通过：`cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`（43 tests / 10 suites）。
- 通过：`xcodegen generate`。
- 通过：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`。
- 未验证：实际窗口中五色切换、深浅外观与禁用态视觉效果；未替换或重启正在运行的 App。
- README 中英文与设计系统已同步；AGENTS.md 无需修改，未改变命令、边界与开发约定。
- 工作区原有的对话滚动修改及回归测试修改保留，不包含在本次提交中。
