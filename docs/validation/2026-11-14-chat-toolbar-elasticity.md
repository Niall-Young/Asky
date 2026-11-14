# 对话顶部按钮弹性反馈

## 改动

- 左侧圆形与右侧胶囊开启原生 Clear 玻璃的 `interactive` 反馈，保持 35% 背景强度与既有尺寸、图标和布局
- 原生 NSButton 子类仅观察真实 `mouseDown` 跟踪的开始与结束，沿用系统的点击动作、移出取消、键盘与辅助功能激活
- 按住时整个表面横向 1.045、纵向 0.93；松手以 response 0.28 / dampingFraction 0.45 的 SwiftUI 弹簧回弹，允许再次交互打断
- 悬停时横向 1.012、纵向 1.02 轻微放大；减少动态效果时缩放固定为 1
- 键盘与辅助功能直接激活动作不触发鼠标按压形变

## 已运行检查

- `xcodegen generate` 成功
- README 的 Debug `xcodebuild` 命令成功，日志位于本地 `build/chat-toolbar-elastic/build.log`
- 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`，331 项 Swift Testing 测试通过
- 从实际控件与修饰器源码生成隔离 AppKit / SwiftUI 检查窗口，复用真实 MingCute 资产和 NativeGlassBackground，不加载用户数据或模型
- 通过 CUA 坐标输入实际按住置顶按钮 900 ms、历史按钮 900 ms；可访问树确认动作生效
- ScreenCaptureKit 独立窗口录制成功：请求 60 fps，记录 1058 个完整帧，最大完整帧间隔约 22.8 ms；视频约 18.62 s
- 检查连续帧确认胶囊按下时变宽、变扁，松手后越过原位再回稳；右侧图标组的图像像素边界宽度范围为 171–182 px、高度为 28–30 px
- 视频、逐帧拼图和像素测量位于本地忽略目录 `build/chat-toolbar-elastic/`：`fixture-interaction.mp4`、`motion-verified.png`、`measured-frames.json`
- 先前桌面区域录制受到窗口遮挡和用户操作影响，不计为动画验证；改为独立窗口捕获后完成验证
- 已关闭隔离检查程序，并打开包含本次实现的 `build/chat-toolbar-elastic/Asky.app --show-agent` 实际 Debug 对话窗口

## 限制与维护

- 未实际切换系统减少动态效果、深色、增强对比度或 macOS 14 回退，不宣称这些状态已验收
- 本次检查未发送模型请求，未替换正式安装版或发布
- README 中英文同步交互行为，设计系统记录形变与回弹参数；AGENTS.md 无需更新，开发命令、模块边界和工程结构均未改变
- 录制与隔离程序沿用既有 `build/` 忽略规则；其他任务的未提交内容保留
