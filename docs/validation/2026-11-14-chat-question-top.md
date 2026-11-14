# AI 新问题置顶与手动滚动接管

## 预期行为与实现

- 发送新问题后，将该问题对齐聊天区域顶部，即距消息视口顶部 64 pt、浮动工具栏下方的位置；回答出现在问题下面。编辑草稿不主动移动消息列表。
- 最新问题与本轮回复使用非懒加载容器，并预留至少一屏扣除工具栏和末尾间距后的高度，让短问题也有足够空间置顶；较早消息继续懒加载。
- 提交触发一次有限定位，等待输入框收起与会话动画结束后，以 NSScrollView 和问题锚点的真实坐标校正。回复出现或更新不启动定位。窗口关闭、用户开始滚动或点击回到底部时取消旧任务，允许用户接管。
- 保留手动回到底部按钮与原有动画、有限校正。
- TLS 报错未修改。

## 实际验证

- KulaCore：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` 通过，日志 `build/composer-core-tests.log`。
- `xcodegen generate` 与 README 的 Debug `xcodebuild` 命令通过，最终构建日志 `build/question-scroll-app-build.log`。
- 扩展现有 `--reading-scroll --scroll-history` 原生窗口回归，使用 30 条长短交替历史消息、70 段长回复，覆盖 560 pt 固定宽度及 480/600/800/900 pt 高度。
- 普通分支和 `--preview-macos14` 兼容分支均通过：每组 7 次手动回到底部，距离均为 0 pt；回复前后保留阅读位置；真实 NSTextView 输入不改变阅读位置；单行/多行草稿通过真实 `model.send()` 提交后，前三次问题锚点位置均为 64 pt；第四次在提交 80 ms 后触发 AppKit 开始滚动通知并向上滚动，等待后没有被拉回。
- 提交测试使用临时数据库、回环 API 地址和随机不存在的 credentialRef，没有使用真实模型凭据或发送远程请求。兼容分支运行于当前 macOS，并非 macOS 14 真机验收。
- 同时进行的头像修改曾使编译器拒绝输入文件在编译中变化。最终回归通过 `ASKY_DERIVED_DATA` 使用 `build/QuestionScrollSources` 和 `build/QuestionScrollData` 的独立快照，日志为 `build/question-scroll-{modern,legacy}.log`。这些产物均由现有 `build/` 忽略规则覆盖。
- 最终 Debug 可执行文件构建于 21:36:08，已重启并核对 21:36:23 启动的进程（PID 61515，参数 `--show-agent`）来自仓库 `build/DerivedData/Build/Products/Debug/Asky.app`。界面工具返回 `native pipe closed before response`，真实用户会话未作手动视觉验收；未替换 `/Applications` 安装或发布版本。

## 文档检查

- README: updated。中英文同步新问题置顶、用户滚动接管的行为。
- AGENTS.md: unchanged。检查了根级/App 作用域与指南入口；本次未引入模块边界、命令或长期规则变化。
