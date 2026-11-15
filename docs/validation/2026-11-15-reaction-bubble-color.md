# 表情底座与气泡配色

- 表情底座复用用户气泡的中性底色与当前头像配色叠层，并使用 1 pt 白色内描边。
- 保留 26 pt 高度、15 pt emoji、水平 7 pt 留白及左下角偏移；未增加玻璃效果或交互。

## 实际验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`（`Packages/KulaCore`）：通过。首次未指定 Xcode 的运行因当前 Command Line Tools 缺少 XCTest 失败，改用完整 Xcode 后通过。
- `python3 App/Tests/run-agent-reply-regression.py --reactions-preview`：通过三种回应模式、完成状态、历史恢复、取消及目标隔离检查。
- 已查看新构建原生窗口截图 `build/reactions-1-light.png` 与 `build/reactions-1-dark.png`，确认底座跟随气泡配色、白色描边及原贴边位置。截图产物沿用现有 `build/` 忽略规则。
- 未替换已安装的应用，未发布版本。构建包含工作区已有的其他修改；本次提交只包含表情底座样式及对应文档。
