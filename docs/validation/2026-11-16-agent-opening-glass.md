# AI 对话窗口打开时的玻璃亮度变化

## 修复

- 原显示顺序先 `orderFrontRegardless`，再异步激活并取得 key 焦点，可能先暴露原生玻璃的未激活外观。
- AI 窗口通过 `afterActivation` 选择新的显示路径：新打开的窗口先以零透明度参与窗口排序，应用激活、窗口取得 key 焦点并完成布局绘制后，直接恢复原透明度。
- 明确打开 AI 窗口时使用 `activate(ignoringOtherApps: true)`；单纯依赖协作式 `activate()` 的试验无法保证激活成功。普通窗口仍使用原有激活方式。
- AI 窗口关闭默认出现动画；授权交接、关闭及后续显示请求会清理未完成的透明窗口，恢复原透明度。

## 已执行的检查

- `xcodegen generate`：通过。
- README 中的 Debug `xcodebuild`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `python3 App/Tests/run-agent-reply-regression.py --window-presentation`：通过。使用真实 AI 窗口覆盖浅色/深色、未激活应用首次打开、取得焦点前保持透明、激活后恢复透明度、关闭重开和重复显示。以禁止激活的测试进程及迟到通知覆盖授权交接、关闭取消；不操作真实系统授权弹窗。
- 使用该命令编译的 `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --window-glass`：通过原生 Regular 玻璃、无染色、浅深色及尺寸适配检查，关联对话回归也通过。
- `codesign --verify --deep --strict build/DerivedData/Build/Products/Debug/Asky.app`：通过。
- 重启工作区 Debug 副本并传入 `--show-agent`，确认运行路径；通过原生窗口截图确认新版对话窗口、历史内容和输入框正常显示。
- `git diff --check`：通过。

## 验证范围

回归断言验证了焦点、显示及透明度顺序；稳定截图不能证明每一帧的 WindowServer 玻璃合成亮度。未做逐帧屏幕录像，也未验证安装包升级后首开。没有生成或发布 Release。

README 中英文测试命令均已补充 `--window-presentation`。构建日志、诊断程序和截图保存在既有 `build/` 忽略目录内。
