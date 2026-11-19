# 参与贡献 · Contributing to Asky

[中文](#中文) · [English](#english)

## 中文

### 反馈问题

先在 [Issues](https://github.com/Niall-Young/Asky/issues) 搜索是否已有相同反馈。报告问题时，请写明 Asky 和 macOS 版本、复现步骤，以及预期和实际看到的结果。建议新功能时，请描述你想用 Asky 完成什么，以及目前在哪一步遇到了困难。

### 提交改动

1. 在自己的 fork 中创建分支。开发环境和构建命令见 README 的[开发与构建](README.md#开发与构建)。
2. 修改 Swift 代码后，在 `Packages/KulaCore` 目录运行 `swift test`。修改 App 后，在仓库根目录运行 `xcodegen generate`，按 README 构建 Debug 版本，并在应用中验证改动。
3. 发起 pull request 时，说明改动解决的问题、如何验证以及实际结果。有相关 issue 时附上链接。界面改动可附截图或短录屏，方便对照。

## English

### Report a problem

Search the existing [issues](https://github.com/Niall-Young/Asky/issues) first. For a bug, include your Asky and macOS versions, the steps to reproduce it, what you expected, and what happened. For a feature request, describe what you want to do in Asky and where you get stuck today.

### Submit a change

1. Create a branch in your fork. The README’s [Development section](README.md#development) covers the tools you need and the build commands.
2. After changing Swift code, run `swift test` in `Packages/KulaCore`. For app changes, also run `xcodegen generate` from the repository root, build the Debug configuration as described in the README, and try the change in the app.
3. In your pull request, describe the problem you addressed, how you checked the change, and what you observed. Link any related issue. For interface changes, a screenshot or short recording can help reviewers see the result.
