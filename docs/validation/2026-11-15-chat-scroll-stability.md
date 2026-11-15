# AI 对话滚动与双向分页修复

日期：2026-11-15。环境：macOS 27.0.1，Xcode SDK 27.2，Debug 原生窗口，隔离测试数据。

## 原因与修复

- 历史区使用 `LazyVStack`，最新一轮放在另一棵 `VStack` 中。原生长文本滚动时会重新估算历史高度，新一轮也会改变旧气泡的视图归属。修复前原生测试在仅滚动、不修改消息时触发“列表总高度变化”断言。
- 统一使用稳定消息分组标识的一棵非惰性列表；数据仍每批 40 条、最多 120 条，不加载全部历史。
- 旧实现向前翻页超出 120 条会移除尾部消息，但没有向后恢复路径。新增保留工具记录的向后分页、加载更新消息按钮，以及恢复最新页的回到底部操作。
- 翻页记录可见消息分组与相对位置，重新布局后恢复；用户主动滚动立即取消位置恢复。新旧 macOS 界面分支使用相同规则。
- 分页游标从当前窗口边界的已保存消息取得，避免实时裁剪后继续使用过期游标。响应运行中禁用历史翻页，避免移除正在使用的回复及其索引。

## 实际运行结果

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore`：360 项通过。新增同时间戳排序、双向分页无遗漏/重复和工具记录保留测试。
- `xcodegen generate` 与 README 中 Debug `xcodebuild`：通过，最终日志 `build/scroll-fix-build-final.log`。
- 原生 `--scroll-stability`：通过。160 条不同高度消息，反复滚到顶部/中间/底部，列表总高度保持 12018 pt；正文可见、滚动位置不跳变。实际鼠标点击连续加载三页、保持阅读位置、加载较新消息、回到最新页均通过。
- `--scroll-stability --preview-macos14`：同一回归通过，覆盖兼容分支；不代表 macOS 14 真机验收。
- `--paging`：单会话与持续时间线均逐页找回全部消息；120 条上限、去重、最新页恢复、活动回复保护与实时裁剪后的旧页读取通过。
- `--reading-scroll`、`--reading-scroll --scroll-history`：通过，手动阅读位置及多次回到底部行为正常。
- `--bottom-push`：通过，短对话自然排列、等待气泡、长回复阅读起点、短回复完整可见及固定窗口尺寸正常。
- `--restored-transcript` 与 `--restored-transcript --restored-long-reply`：通过，分别冷启动与关闭重开三次；短回复底部间隙均为 0，长回复保持阅读起点。
- 检查原生截图 `build/scroll-newer-button.png` 与 `build/bottom-push-short.png`，消息和操作入口可见。

## 测试执行与边界

工作区有其他并行修改，两次原生测试编译被 Swift 的“源文件在编译中修改”检查终止，未记为通过。最终将 App Swift 源码复制到忽略的 `build/scroll-regression-source/`，使用现有回归 runner 的同等编译参数及 Debug 产品构建独立原生测试包 `build/scroll-regression-artifacts/AgentReplyRegression.app`。最终 `AgentModel.swift`、`AgentView.swift` 与测试副本逐字节一致。

新回归的常规复跑入口已同步至 README：

```sh
python3 App/Tests/run-agent-reply-regression.py --scroll-stability
python3 App/Tests/run-agent-reply-regression.py --paging
```

最终固定测试包另外运行上述 reading-scroll、bottom-push、restored-transcript 组合，日志在 `build/scroll-final-*.log`；兼容分支日志为 `build/scroll-stability-legacy.log`。构建、测试包、日志和截图复用已有 `build/` 忽略规则。

本次没有替换已安装的 Asky，没有发布 GitHub Release，也没有使用真实模型请求或真实用户历史。真实触控板惯性滚动、macOS 14/15 真机与极端单条超长消息的性能仍不在本次验证范围。
