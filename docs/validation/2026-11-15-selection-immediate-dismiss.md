# 选区菜单即时关闭验证

日期：2026-11-15

## 改动

- 「复制」「添加到对话」保留原有悬停侧向提亮；按压不再改变窗口或内容尺寸。
- 去掉按压弹簧和 220 ms 关闭延迟；复制成功即关闭，添加引用在关闭菜单后立即执行。
- 拖出按钮后松开仍取消操作，保留选区。
- README 中英文与设计系统同步新行为。

## 实际验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，共 369 项 Swift Testing 测试。
- `python3 App/Tests/run-agent-reply-regression.py --selection-preview`：通过。新编译原生窗口覆盖 5 种配色及浅/深色外观；按住添加按钮 140 ms 后窗口尺寸不变，松开事件返回时菜单已不可见；复制按钮拖出取消、Esc、空白点击、公式源码、引用去重、输入区焦点、发送失败保留与历史恢复均通过。
- 检查回归生成的 `build/selection-pressed-menu.png`，菜单尺寸及布局正常。
- `git diff --check`：通过。

## 验证边界与环境

- 没有执行复制成功路径，以免覆盖用户剪贴板；其关闭分支已移除延迟并直接调用 `close()`。
- 没有单独实测系统减少动态效果开关；尺寸动画已取消，悬停过渡仍遵循已有开关。
- 初次测试未指定 Xcode 时因 Command Line Tools 缺少 XCTest 失败；按 README 指定 `DEVELOPER_DIR` 后通过。构建期间出现的私有光标类型访问错误已修正，最终构建及原生回归均通过。
- 正常退出请求最初返回“用户已取消”，随后检查确认旧进程已退出；未强制终止。已通过 README 的 `open -n build/DerivedData/Build/Products/Debug/Asky.app --args --show-agent` 启动新构建，并核对运行路径。
- 生成工程、编译产物及截图复用现有 `.gitignore` 中 `Asky.xcodeproj/`、`build/` 规则，无新增忽略项。
