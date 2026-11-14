# 剪贴板分页与旧历史入口移除

日期：2026-11-14。

## 变更

- 移除 Agent 左上角旧历史按钮、历史搜索页、专用输入组件、相关样式、文案和历史快捷键设置。保留持续时间线及原有每批 40 条、120 条内存窗口的消息分页；不删除已有聊天数据。
- 隐藏现代及兼容对话滚动容器、剪贴板列表的滚动条。
- 剪贴板首批与追加每批 40 条，滚动末尾或键盘接近末尾继续读取。数据库使用时间和 ID 游标，每次扫描至多 128 行；新捕获不移动旧页边界。过滤失效原始文件后再限制结果数量。
- 输入防抖 150 ms；后台读取及匹配，关键词变化或隐藏窗口会取消工作，代次检查阻止过期结果回写。普通刷新保留选中项；成功删除立即更新列表，再后台补齐。
- 定时刷新在数据库未变时跳过扫描，每 3 秒重新检查外部文件可用性。启动器剪贴板检索也复用有界扫描，移除原来的 Int.max 全量查询。
- 原生剪贴板回归脚本显式选择与 Debug 构建一致的 macOS SDK，现有回归等待异步结果。

## 实际检查

以下均已实际执行并通过：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build
python3 App/Tests/run-clipboard-regression.py --pagination
python3 App/Tests/run-agent-reply-regression.py --reading-scroll
build/ClipboardRegression.app/Contents/MacOS/ClipboardRegression --delete-shortcut
build/ClipboardRegression.app/Contents/MacOS/ClipboardRegression --availability
git diff --check
```

核心新增回归覆盖相同时间戳的 165 条记录、分页期间插入新记录后不重复不漏项、取消查询不返回旧页。原生分页回归覆盖首批 40 条、完整读取 165 条、追加保持选择、最新关键词胜出和隐藏窗口取消。对话原生窗口断言滚动条隐藏、旧历史按钮不存在、长回答保持阅读位置且手动滚动可用。删除快捷键与文件失效/恢复、复制竞态、监控过滤回归通过。

回归过程中修正了初次脚本默认 SDK 与构建 SDK 不一致的问题。一次编译因测试期间源码仍在修改而中止，固定源码后重跑通过。剪贴板相关原生用例共享系统剪贴板，并行执行曾产生选择项断言失败；改为顺序执行后通过。

## 验证边界与工作区

未做万条历史的延迟/内存基准，也未在真实 macOS 14 系统验证兼容路径。原生窗口回归不等于所有真实应用粘贴验收；未发布 Release。

README 中英文及设计说明同步。AGENTS.md 无需变更：沿用现有 ToolService 边界与构建、测试命令。构建和回归产物由既有 build/ 忽略规则覆盖，无新增忽略规则。

任务开始时已有持续对话及界面改动，且与本任务在 AgentView、AgentModel、ClipboardWindow、README 等文件重叠；未将这些已有改动混入提交，本次变更保留为未提交状态。
