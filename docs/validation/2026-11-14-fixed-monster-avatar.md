# 固定小怪物头像

2026-11-14

按用户要求撤回几何头像配置：删除配置页、六形状/六配色目录、状态表情与眨眼、SceneKit 渲染、持久化读写、相关本地化与专用回归。AgentModel 恢复到该功能实施前的内容，保留原有单对话改动。

顶部只保留固定的 SwiftUI 小怪物：圆润轮廓、豆豆眼、闭嘴微笑和 Asky 名字，无点击配置、配饰或复杂细节。

实际验证：

- `xcodegen generate`：通过
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过
- `git diff --check`：通过
- 已退出旧进程并启动本次 Debug 构建，通过 Computer Use 观察实际窗口：左上角为固定小怪物与 Asky，辅助功能树中不再有配置按钮

README: updated — 中英文同步固定头像及无配置入口，移除专用配置回归命令
AGENTS.md: unchanged — 未改变原生 App 与构建边界

保留工作区原有未提交改动，未自动提交混合内容。构建与工程产物继续由现有忽略规则排除。
