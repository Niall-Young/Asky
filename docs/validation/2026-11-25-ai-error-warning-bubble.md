# AI 对话故障文案与警告气泡验证（2026-11-25）

## 变更范围

- [NativeModelClient.swift](../../Packages/KulaCore/Sources/AgentHost/NativeModelClient.swift)：新增 `ModelFailureReason` 常见故障分类（HTTP 400/401/402/403/404/408/413/429/5xx、服务商错误体中的额度/上下文超长/内容安全/不支持视觉或工具、网络 `URLError`、流式中断/长度上限/空回复/工具参数异常等），统一输出自然语言文案与未知边界错误兜底文案。
- [NativeRuntime.swift](../../Packages/KulaCore/Sources/AgentHost/NativeRuntime.swift)、[AgentHost.swift](../../Packages/KulaCore/Sources/AgentHost/AgentHost.swift)、[AgentModel.swift](../../App/Sources/AgentModel.swift)：替换原有技术/代码化报错（如 `HTTP %d`、`AI 运行时已退出（%@）`、`运行时协议错误` 等）为自然语言提示；模型返回空回复时发出明确故障提示而非静默结束。
- [Tokens.swift](../../Packages/KulaCore/Sources/Theme/Tokens.swift)、[SwiftUITheme.swift](../../Packages/KulaCore/Sources/Theme/SwiftUITheme.swift)、[AgentView.swift](../../App/Sources/AgentView.swift)：新增亮暗自适应浅色透明橙色警告底色 Token `backgroundWarningSubtle`（浅色 `#AD690B` 10% 不透明度、深色 `#E8AD52` 14% 不透明度），对话错误气泡改用 `ThemeColor.kWarning` 警告色文字与图标配合 `ThemeColor.kBackgroundWarningSubtle` 背景。
- [Core.strings (zh-Hans)](../../Packages/KulaCore/Sources/Contracts/Resources/zh-Hans.lproj/Core.strings)、[Core.strings (en)](../../Packages/KulaCore/Sources/Contracts/Resources/en.lproj/Core.strings)、[Localizable.strings (zh-Hans)](../../App/Resources/zh-Hans.lproj/Localizable.strings)、[Localizable.strings (en)](../../App/Resources/en.lproj/Localizable.strings)：补齐全部新增中英文故障文案。
- [NativeRuntimeTests.swift](../../Packages/KulaCore/Tests/AgentHostTests/NativeRuntimeTests.swift)、[ThemeTests.swift](../../Packages/KulaCore/Tests/ThemeTests/ThemeTests.swift)：补充 HTTP/服务商错误体/网络错误/流式中断/未知兜底/空回复测试及警告背景色 Token 测试。

## 验证结果

- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过（Swift Testing 91/91 + XCTest 9/9）。
- `python3 App/Tests/check-localization.py`：本次新增全部中英文 key 匹配无缺失（仅报告仓库原有重复 key `剪贴板历史`）。
- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug build CODE_SIGNING_ALLOWED=NO`：`BUILD SUCCEEDED`。
