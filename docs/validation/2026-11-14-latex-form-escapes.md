# LaTeX 表单转义修复

## 原因与改动

截图对应回复的 `asky-form` 最后一行，在选项 JSON 字符串中直接包含 `\[...\]`。这是非法 JSON 转义，旧解析器因此将整个表单回退为 Markdown 代码块。已用同一条原始回复对照执行旧、新解析器：旧版无法识别表单，新版识别到完整的三个字段。

解析时先尝试标准 JSON；失败后仅补齐字符串内部非法反斜杠转义，再走原有解码、字段限制与答案校验。合法 JSON 转义、其他结构错误处理及存储原文保持不变。不会猜测已合法的 `\n`、`\t` 等转义是否原本想表达 LaTeX。模型提示补充 JSON 转义示例及正文公式分隔符规则。

## 已执行验证

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc App/Sources/ChatForm.swift App/Tests/ChatFormParserRegression.swift -o build/chat-form-parser-regression` 与生成的可执行文件：通过。包含截图结构、逐字符流式解析、合法引号/反斜杠/Unicode 混合转义、无效结构及字段回退、答案校验。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过；完整输出在 `build/latex-form-fix/core-tests.log`。
- `xcodegen generate` 与 README 的 Debug `xcodebuild` 命令：通过；日志在 `build/latex-form-fix/build.log`。
- 原生回归 `--latex-form-preview`：通过；隔离会话存储原文不变，重开后表单完整、可用，答案校验通过；生成并检查深浅色表单截图 `build/latex-form-{light,dark}.png`。
- 同一回归二进制的 `--math-preview`：通过；行内公式、独立公式、积分、求和、矩阵、分段式、错误公式回退，以及深浅色与窄窗口布局。已查看窄窗口截图 `build/math-dark-narrow.png`，公式正常排版。
- 使用 CUA 检查正在运行的 Debug Asky：截图对应的真实历史回复已显示三个原生字段，单选项及文本输入可用，必填项尚未选择时提交按钮禁用。没有替用户提交表单或发送模型请求。

首次原生回归编译时，另一个开发任务更新了共享 `ToolService.o`，编译器报输入文件被修改。随后将 Debug 产品及 module maps 复制到 `build/LatexFormVerification`，通过 `ASKY_DERIVED_DATA` 指向这份独立副本，重新编译并完成上述原生回归。所有产物由现有 `build/` 忽略规则覆盖。

## 范围与限制

未调用真实模型验证新提示词的生成质量，未发布安装包。本次提交仅包含转义修复、相关回归和文档；保留工作区中其他聊天布局、窗口尺寸及主题改动。AGENTS.md 无需更新：沿用现有模块边界和测试入口；README 已同步中英文兼容说明及回归命令。
