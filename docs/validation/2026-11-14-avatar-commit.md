# 头像配色菜单独立提交验证

## 提交范围

- 透明底小怪物头像资产及 36 pt 导航栏入口，不显示 Asky 名字。
- 蓝、黄、紫、绿、粉五种头像配色，默认蓝色；菜单只显示头像、颜色名和选中勾，无色点。
- 同一 GlassEffectContainer 与 glassEffectID 内的原生 matchedGeometry 过渡，以及 SwiftUI 弹簧回弹。
- 现有 SettingsPreferences 中的配色持久化和旧配置默认值、中英文文案及使用说明。

按用户要求从混合工作区中仅暂存头像相关差异。AgentView 仅替换左侧入口，AgentModel 仅增加配色偏好访问；持续对话、历史移除、气泡和全局按钮动效修改均留在工作区。没有把上述其他功能带入提交。

## 实际执行

暂存区经 `git checkout-index` 导出为独立副本，针对该副本执行以下命令，通过：

- `xcodegen generate`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath /tmp/asky-avatar-commit-derived -clonedSourcePackagesDirPath /Users/niallyoung/orca/Asky/build/DerivedData/SourcePackages build`：BUILD SUCCEEDED。
- `git diff --cached --check`：通过。

本轮为提交整理，没有新增运行时行为。此前已实际执行 KulaCore swift test，并在新构建实际窗口中检查原生玻璃菜单、五色显示、点击切换和偏好持久化。独立副本本轮只验证构建，没有再次执行窗口交互或测量帧率。

构建及导出副本均保留在项目外的临时目录；项目中的 `build/` 与 `Asky.xcodeproj/` 沿用现有忽略规则，无新增规则。

README: updated — 只暂存中英文头像入口与配色说明
AGENTS.md: unchanged — 本次提交整理不改变通用项目规则
