# 智能配置分组拆分

日期：2026-11-16

## 变更

- 侧栏新增独立“智能配置”分组，依次包含模型配置、MCP、数据管理、数据来源。
- 模型配置仅保留供应商、模型与能力检查；MCP 使用独立页面；数据管理承接对话历史和记忆。
- 数据来源从“工具”分组移入“智能配置”，来源授权逻辑未修改。
- 沿用现有设置样式和已打包的 MingCute 图标；同步中英文标题及 README 导航路径。

## 实际验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，Swift Testing 共 369 项测试。
- `python3 App/Tests/check-localization.py`：通过，175 个 Swift 源文件的语言键与格式参数检查。
- `python3 App/Tests/run-settings-regression.py`：通过。覆盖所有设置页明暗模式窗口、标题切换、MCP 来源复选框、最小窗口尺寸，以及既有设置原生交互回归。
- 在以上脚本生成的同一回归应用运行 `build/SettingsRegression.app/Contents/MacOS/SettingsRegression --conversation-retention -AppleLanguages '(zh-Hans)'`：通过。数据管理页的保留期限选择、旧数据默认值、持久化、即时清理及记忆保留均正常。
- 人工查看本次原生窗口截图：英文模型配置和数据管理浅色页、MCP 和数据来源深色页、中文数据管理浅色页。新分组、页面内容及图标正常；侧栏沿用滚动容器，底部“其他”可滚动访问。

## 产物与边界

- 构建日志、回归日志与窗口截图位于 `build/`，沿用现有忽略规则，不提交。
- 原生回归使用临时数据目录，没有清理用户真实对话或修改真实来源授权。
- 最新 Debug 应用已构建；现有 Debug 进程未退出重启，不能视为已运行新二进制。没有更新 `/Applications` 安装包或发布 Release。
- 本次没有验证真实外部 MCP 客户端连接或模型网络请求；对应逻辑未修改。
