# 对话导航栏头像优化

按用户截图移除左侧 Asky 可见名字；头像圆框改为 36 × 36 pt，与右侧按钮组高度一致，内部图片以 30 × 30 pt 适配。保留原有玻璃参数与非交互语义，Asky 辅助功能名称保留。

头像使用内置 image_gen 生图，透明底 PNG 已复制到 `App/Assets.xcassets/AgentAvatar.imageset/avatar.png`，1293 × 1217，包含 alpha。SwiftUI 通过资产目录加载，替换此前手绘 Shape。README 中英文与设计系统已同步。

## 生图提示词

Use case: stylized-concept. Asset type: transparent mascot avatar for a native macOS assistant, displayed at only 26 points inside a 34 point glass circle. Generate ONE beautifully designed tiny friendly blue creature, front facing, centered, isolated on truly transparent background. Compact rounded squishy pebble silhouette with two small rounded ear-like horns, soft powder-blue matte clay material, restrained dimensional shading and clean silhouette, two dark navy oval eyes and a tiny gentle closed smile. Charming, calm, refined, modern designer toy, elegant proportions, eyes readable at tiny size. The creature fills about 85 percent of the square canvas, symmetrical visual balance. No circle, no container, no pedestal, no ground shadow, no props, no hands, no text, no white border, no glossy plastic, no excessive detail. Deliver only the isolated character with alpha transparency.

提示词中的容器尺寸用于生成构图参考；接入时按实际右侧按钮高度统一为 36 pt，图片框为 30 pt，包含资产自身透明边距。

## 实际验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：BUILD SUCCEEDED。
- 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `git diff --check`：通过。
- 已结束此前 Debug 进程，从本次 `build/DerivedData/Build/Products/Debug/Asky.app` 以 `--show-agent` 启动。通过 Computer Use 查看实际窗口截图：没有可见 Asky 名字，新浅蓝头像清晰，左右玻璃容器同高、垂直居中。
- 未替换 `/Applications/Asky.app`，未打包或发布。

README: updated — 同步中英文头像说明
AGENTS.md: unchanged — 本次视觉调整无新增通用开发规则

工作区开始时已有大量未提交变更，且 `AgentMonsterAvatar.swift` 已是未跟踪文件。当前头像接入依赖这些既有变更，无法形成完整独立提交，因此保留修改、不提交混合内容。构建产物复用现有 `build/` 和 `Asky.xcodeproj/` 忽略规则，无新增忽略规则。
