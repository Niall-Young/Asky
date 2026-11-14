# 对话保留期限与完整清理

日期：2026-11-14。

## 行为

- 设置 › 智能配置 › 对话历史 › 保留时间：7 天、30 天（默认）、90 天、永久。旧设置缺失字段或字段无效时按 30 天处理，不重置其他设置。
- 期限按会话最后活动时间计算；启动时、运行期间每天及修改期限后检查。正在运行的会话和仍有工具调用的会话跳过；维护期间阻止提交新任务，避免删除与写入交错。
- 到期和手动删除共用 ToolService 清理服务，删除消息、全文索引、会话附件元数据、工具执行记录、来源、活动、待提炼队列及提炼游标；清理原生会话快照和受管理目录内的旧 Pi 日志。
- 附件仅删除 Asky 自有且没有其他会话或草稿引用的文件；外部原文件及越过目录边界的符号链接目标不删除，空的自有附件子目录回收。
- 文件删除任务与数据库删除一起入事务，失败任务持久化重试。失败在设置中显示；手动删除失败同时反馈错误。旧版遗留的无引用文件及孤儿会话来源、执行记录经过至少 24 小时宽限后回收。
- 已删除会话的原生界面和运行时路径缓存同步更新；当前草稿附件保留。
- 不修改 `Memory/`、整理副本、已有结构化记忆和记忆来源关系。清理不启动模型，不因删除历史触发提炼或整理。

## 实际检查

| 检查 | 结果 |
| --- | --- |
| `xcodegen generate` | 通过 |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/HistoryDerivedData -clonedSourcePackagesDirPath build/DerivedData/SourcePackages build` | 最终通过 |
| `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path /tmp/asky-history-xcode-tests --jobs 4` | 最终通过，13 个测试产品共 330 项测试 |
| `ASKY_DERIVED_DATA=…/build/HistoryDerivedData DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-settings-regression.py --conversation-retention` | 通过；为保留并行工作，使用 App 源码和测试的临时快照，编译增加 whole-module-optimization，运行实际原生设置窗口 |
| 同一新编译原生回归程序加 `-AppleLanguages '(zh-Hans)'` | 通过，中文选择、设置持久化、自动清理、手动删除及清理后的界面状态均通过 |
| 中英文本地化资源 `plutil -lint` | 通过 |
| 本任务文件 `git diff --check` | 通过 |

核心测试直接断言原生快照、旧日志、自有附件和空目录已从磁盘移除，数据库中的对话、索引、执行与提炼数据已移除；共享附件、外部原文件、当前草稿、运行中工具对应会话继续保留。文件异常状态恢复后，重新打开数据库能继续处理删除任务。旧版孤儿元数据和文件回收也已覆盖。

记忆验证同时比较 `Memory/MEMORY.md`、主题文件的原始字节，以及旧结构化记忆和来源关系；自动到期与手动删除均未改动已有记忆。原生回归核对默认值、旧设置解码、无效设置回退、真实下拉菜单切换、缩短期限立即清理、重开设置保留选择、当前历史界面清空及手动删除。检查了中英文浅色、深色实际窗口截图：`build/settings-conversation-history-{light,dark}.png` 和 `build/settings-conversation-history-zh-{light,dark}.png`。

测试曾发现 macOS 临时目录别名导致文件范围判断和草稿保护失效，统一路径匹配后回归通过。一轮原生回归与应用构建同时运行导致链接对象被刷新，应用构建完成后重跑通过。

## 交付边界

检查全部使用临时测试数据；未清理用户当前业务目录，未替换已安装版或发布。SQLite 删除后的空闲页可复用，不承诺数据库立即缩小或底层安全擦除。

README 中英文、PRD、数据生命周期、开发命令与隐私说明已同步。AGENTS.md 对本任务无需更新：模块边界与主开发命令不变。构建与截图使用已有 `build/` 忽略规则。工作区仍有先前历史修复和原生运行时迁移等改动，本任务与这些改动共用 Schema、AgentModel、AppModel 和文档，未创建混合提交。
