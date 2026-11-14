# 气泡留白、配色和宠物菜单点击修正

- 用户与 AI 气泡内距由水平 12 / 垂直 10 pt 增至 18 / 14 pt，复制图标同步对齐正文。
- 用户消息保留中性底，轻微叠加宠物色（深色 12%、浅色 8%）；AI 回复及等待气泡恢复中性色，所有正文保留自适应语义文字色。
- 原菜单展开后仍处于头像大小的父级布局内。改为全窗顶部叠层承载，展开时布局及命中尺寸均为 184 × 252 pt，收起时为 36 × 36 pt；保留既有玻璃变形。头像与菜单按钮不进入系统焦点代理循环，键盘导航沿用菜单自身的方向键 / Return / Esc 处理。
- AI Markdown 与用户纯文本统一为 14 pt 字号 / 22 pt Default 行高；原生内联文本取消额外的 2 pt 上下容器留白，保留段落间距。
- 历史表单原有结束状态与禁用规则不变。

已实际执行并通过：

1. `xcodegen generate`
2. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`
3. 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
4. `python3 App/Tests/run-agent-reply-regression.py --reply-activity-preview`
5. 用新编译的 `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --scroll-preview` 打开隔离数据原生聊天；使用屏幕坐标依次点击粉、绿、紫、黄、蓝，确认各行实际鼠标命中、菜单收起、头像与已有用户消息同步变色。此次未用辅助功能按钮动作代替鼠标验证。
6. `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --preview-macos14 --macos14-checks`：兼容分支深浅外观与滚动检查通过。
7. `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --math-preview`：公式和内联文本回归通过。
8. `git diff --check`

README 中英文及设计系统同步更新。AGENTS.md 无持久规则、命令或架构变化，保持不变。日志、截图与构建沿用现有 `build/` 忽略规则。未替换日常安装；真实 macOS 14 系统及辅助功能系统设置未实测。
