# 聊天玻璃白块修复

## 现象与定位

用户提供的 Asky 截图中，输入框内部接近纯白，与窗口底色分离；参考 ChatGPT iOS 截图主要依靠玻璃边缘与柔和明暗过渡区分控件。

`ComposerTextEditor` 的 NSTextView 和 NSScrollView 均已设置 `drawsBackground = false`，没有发现编辑器白底。原输入框和右上按钮组使用 Clear 玻璃，玻璃效果整体不透明度为 0.85。

在本机建立独立原生对照窗口：白色背景窗口上放置 Regular NSGlassEffectView，再分别展示现有 Clear 85%、直接 Clear、直接 Regular。浅色活跃窗口的屏幕合成截图显示：两种 Clear 的内部均明显提白；直接 Regular 保留柔和灰色过渡和边缘。因此不能将问题归因于 0.85 不透明度本身。深色活跃窗口在相同白色背景上，Regular 同样比 Clear 的边缘和内部提亮更柔和。这是本机渲染对照结论，不推断 ChatGPT 私有实现或承诺不同系统逐像素一致。

## 修改

- 聊天输入框与右上置顶/关闭按钮组改用默认原生 Regular 玻璃，去掉这两处效果透明度覆盖。
- 复用既有 `NativeGlassBackground`，其辅助功能与旧系统回退保持原样。
- 未修改头像、启动器与剪贴板操作按钮材质；未添加自绘底色、阴影或界面说明。
- 同步中英文 README 和设计系统中的当前材质说明。

## 实际验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。首次未指定 DEVELOPER_DIR 时由于 Command Line Tools 找不到 XCTest 而失败；指定完整 Xcode 后重跑成功。
- `python3 App/Tests/run-agent-reply-regression.py --window-glass`：通过，包含回复、历史与表单生命周期检查，以及聊天原生 Regular 外壳、浅色/深色截图和程序化尺寸调整检查。
- 查看新构建回归窗口的浅色、深色截图；单独查看活跃玻璃对照窗口的浅色、深色屏幕合成截图。
- 重启当前 Debug Asky，确认进程来自 `build/DerivedData/Build/Products/Debug/Asky.app/Contents/MacOS/Asky`，新进程启动时间晚于本次构建。实际聊天窗口显示既有历史，消息输入控件正常出现并获得焦点；通过屏幕区域截图核对新材质。

本机观察到按窗口捕获的透明玻璃 PNG 与完整屏幕合成颜色不同，因此最终颜色判断采用屏幕区域捕获。完整聊天窗口的自动截图主要覆盖非活跃状态；活跃状态的材质对照由独立原生窗口验证。未执行真实 AI 发送、未修改用户草稿、未打包或发布正式安装包，macOS 14/15 未实机测试。

本地截图和日志位于既有忽略目录 `build/`：`glass-probe-active.png`、`glass-probe-active-dark.png`、`glass-fix-actual.png`、`agent-window-glass-*.png`、`glass-fix-*.log`。对照程序及构建产物复用既有 `build/` 忽略规则，不加入提交。
