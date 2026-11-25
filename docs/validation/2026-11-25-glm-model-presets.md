# GLM（智谱）预设模型更新验证

日期：2026-11-25。

## 变更

- 在 `App/Sources/ModelProviderPreset.swift` 中将 `glm`（`https://open.bigmodel.cn/api/paas/v4`）的模型列表从 `["glm-5.3"]` 更新为 `["glm-5.3-flash", "glm-5.3-flashx", "glm-5.3", "glm-5.4"]`：
  - 默认选项改为 `glm-5.3-flash`（标准 API 已开放，原生多模态，单价为 `glm-5.3` 的十分之一）。
  - 保留 `glm-5.3`，已保存 `glm-5.3` 的现有用户仍匹配 `glm` 预设，不强制升级也不退回自定义。
  - 补充 `glm-5.3-flashx`（标准 API 已开放高速版）与 `glm-5.4`（非默认；截至 2026-11-25 智谱官方文档说明 `glm-5.4` 已向 GLM Coding Plan 开放，标准 API 待安全评估完成后开放，暂不设为默认；Coding Plan 独立端点 `https://open.bigmodel.cn/api/coding/paas/v4` 沿用“完全自定义（OpenAI 兼容）”配置）。
- 在 `App/Tests/ModelProviderRegression.swift` 增加 `glm` 预设默认模型、可选列表与已有 `glm-5.3` 配置保留断言。

## 实际检查

通过：

1. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library -swift-version 6 App/Sources/ModelProviderPreset.swift App/Tests/ModelProviderRegression.swift -o build/model-provider-regression && build/model-provider-regression`：通过。
2. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/KulaCore`：13 个测试运行组共 477 项 Swift Testing 测试全部通过。
3. `xcodegen generate` 与 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：构建成功（`BUILD SUCCEEDED`）。
4. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-settings-regression.py`：原生设置回归通过，并核对新生成的 `build/settings-light-model.png`、`build/settings-dark-model.png` 模型页布局完整无截断。

未验证：未使用真实智谱 API Key 发起在线请求，不宣称线上模型响应或账号权限已端到端验收；本次未打包替换 `/Applications/Asky.app`。

## 文档与 Git

- `AGENTS.md` 无变化：沿用既有 App 与测试边界，未新增模块、工具或规则。
- `README.md` 无变化：不列举具体服务商模型版本号，安装与开发命令无变动。
