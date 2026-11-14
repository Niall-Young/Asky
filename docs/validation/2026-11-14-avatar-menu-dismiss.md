# 头像菜单收起动画

## 改动

原头像的 60% Clear 玻璃实际绘制在背景层，外层是 identity 玻璃；菜单的 Regular 玻璃位于外层。两者的 glassEffectID 没有对应同一层可见玻璃，原生录屏复现了展开有过渡、Esc 关闭时突然消失。

改为在同一个 GlassEffectContainer 内持续保留一块原生玻璃，使用原有弹簧改变 36 × 36 / 184 × 252 的尺寸。圆角维持 18 pt，头像 Clear 强度维持 60%，菜单维持 interactive Regular。前景使用 identity 玻璃分层，避免原生玻璃将头像及菜单文字当作背景折射。原有减少动态效果与不透明材质回退继续保留。

## 实际检查

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- 在 `Packages/KulaCore` 运行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。初次未设置 DEVELOPER_DIR 时由 Command Line Tools 编译，因找不到 Testing 失败；切换完整 Xcode 后通过。
- 使用当前 AgentAvatarPicker、NativeGlassBackground、GlassPointerFeedback 与 Debug Theme 构建独立 NSHostingView 原生窗口。通过 NSEvent 触发打开和关闭，screencapture 录制窗口，ffmpeg 提取 30 fps 连续帧。实际检查 Esc、窗口内点空白、点击黄色选项、Return 四种关闭方式，均可见玻璃连续缩小后恢复圆形头像；点击黄色选项后头像变黄，前景文字保持清晰。
- 本地录屏：`build/avatar-motion/final-{esc,outside,select,return}.mov`；临时驱动：`build/avatar-motion/AvatarMotion.swift` 和 `build/avatar-motion/run.py`。均复用已有 `build/` 忽略规则，不加入源码。

未重启用户正在使用的 Asky，也未验证安装包、旧版系统、系统级减少动态效果开关或其他 App 内点击触发的全局监听路径。

README 已说明头像原位菜单，本次修复其既定收起行为，使用方式不变，未修改 README。AGENTS.md 无新的持久规则需要加入。
