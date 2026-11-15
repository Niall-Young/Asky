# 主动联网提示词修正

## 发现与改动

原系统提示词仅以“需要最新信息或用户要求联网搜索”概括触发条件，未明确推荐、软件用法、不确定事实等情况。运行时通过 `NativeAgentPrompt.system` 发送规则，模型调用设置为 `tool_choice: auto`，没有强制搜索判断。搜索工具本身通过 ToolService 提供，配置默认启用，但未读取或验证用户安装版的实际设置。

将联网规则提前到动态时间之后：可能变化的公开事实、推荐与比较、软件/API 用法、不确定事实必须先查；明确稳定知识与纯文本处理的例外、用户禁止联网的优先级、私人数据及 MapKit 的工具边界。要求结果匹配对象、版本与时间，引用真实来源，搜索失败不以训练知识冒充当前事实。同步中英文工具描述、README 和运行时文档。

## 实际验证

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：退出码 0，13 个测试运行汇总 359 项通过。默认运行中的真实搜索测试因环境变量未启用而提前返回，不视为联网证据。
- `cd Packages/KulaCore && ASKY_LIVE_WEB_SEARCH=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --skip-build --filter WebSearchTests`：5 项通过。通过 ToolService 实际请求 Bing，`Swift Apple documentation` 返回 5 条非空结果，包括 Apple Swift 文档；真实搜索约 1.5 秒。
- `plutil -lint`：中英文 `Core.strings` 通过。
- `git diff --check`：通过。

## 验证边界

没有调用用户配置的真实模型，没有完成原生对话中主动联网的行为验收；提示词约束不等于运行时强制执行。没有构建、替换或重启已安装 App，本次修正需后续构建安装后生效。未修改 App 界面与搜索实现。其他并行任务正在修改 App 与 LocalStore，均不纳入本次提交。测试缓存沿用已有 `.gitignore` 规则，日志位于 `/tmp/asky-web-policy-tests.log` 和 `/tmp/asky-web-policy-live.log`。
