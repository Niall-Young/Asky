# AI 对话回到底部再次修复

## 提交与运行版本核对

- 上次修复已提交为 `9072dbc`，本次开始时工作区干净。运行进程为仓库 `build/DerivedData/Build/Products/Debug/Asky.app`，可执行文件构建时间为 21:05:31，进程启动时间为 21:05:35；不能将问题归因为未提交或仍运行修复前的构建。
- 上次只覆盖较短历史消息及单次点击，未覆盖长短消息交替、反复返回旧消息和窗口尺寸变化。

## 复现与修复

- 扩展 `--reading-scroll --scroll-history`：30 条长短交替的历史消息，加 70 段回答；返回旧消息后点击真实按钮，并直接比较 NSScrollView 文档底部和可见区域底部。
- 原代码在尺寸变化压力场景中，第三次点击后仍剩 `645.5` pt。仅补动画完成后的二次定位，以及仅反复定位原标记，均未消除失败。
- 底部标记原本属于 LazyVStack，其位置受到未显示消息高度估算的影响。现在保留消息懒加载，将底部标记和原有 13 pt 留白放到外层 VStack 的末尾，使目标不再属于懒加载行。
- 两个系统分支共用一次点击的有限校正：动画后从 NSScrollView 读取文档和视口的真实边界，将文档坐标转换到 clip view 坐标后对齐；连续三次到达底部即结束，最多 12 次。关闭窗口或用户开始滚动时取消，不为后续回复开启持续自动跟随。到底判断同时处理超出底部和内容不足一屏的情况。

## 实际验证

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`，工作目录 `Packages/KulaCore`：通过。
- `xcodegen generate`：通过。
- README 中的 Debug `xcodebuild` 命令：通过。
- 最终原生窗口回归使用产品固定的 560 pt 宽度，覆盖 480/600/800/900 pt 高度；每组连续点击 7 次，检查每次剩余距离不超过 1 pt。
- 诊断时还强制改变过窗口宽度；这突破了 `WindowMetrics` 中最小和最大宽度均为 560 pt 的实际约束。480 pt 的单回复压力场景出现过懒加载文档高度缩短至小于视口的情况，未将该场景记为通过；最终回归按产品允许的尺寸执行。
- 单条长回答、长历史各运行普通分支及 `--preview-macos14` 兼容分支，共四组全部通过，28 次点击剩余距离均为 `0.0` pt；点击前、点击后新回复出现时均保持阅读位置。日志为 `build/scroll-bottom-final-{single,modern,legacy-single,legacy}.log`。
- 兼容分支运行于 macOS 27.0.1，并非 macOS 14 真机验收。

App 构建改写了回归编译正在读取的 `ToolService.o`，首次最终回归因此被编译器拒绝。之后复制当时源码和 DerivedData 到 `build/ScrollBottomFinalSources`、`build/ScrollBottomFinalData`，用现有脚本及 `ASKY_DERIVED_DATA` 编译独立回归，避免共享构建产物被改写。日志、源码快照和构建产物均由现有 `build/` 忽略规则覆盖。

最终 Debug 可执行文件构建于 21:20:08，已重启并核对新进程（21:20:37，PID 49092，参数 `--show-agent`）来自该 Debug 应用。中间构建曾通过界面工具观察到真实对话窗口，但实际会话的滚动点击检查被窗口切换打断；最终构建启动后的界面工具连接又返回 `native pipe closed before response`。因此真实会话点击验收未记为通过。没有替换 `/Applications` 安装或发布新版本。

## 文档检查

- README: unchanged。恢复既有手动回到底部行为，不改变使用方式、产品承诺或开发命令。
- AGENTS.md: unchanged。作用域与指南入口已检查，未引入新的模块边界或长期规则。
