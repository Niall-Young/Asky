<div align="center">

<img src="App/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" alt="Asky" width="128" height="128" />

# Asky

搜索、剪贴板与 AI，一个快捷键呼出。<br />
Search, clipboard, and AI in one native macOS launcher.

[![macOS](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](project.yml)
[![Swift](https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift&logoColor=white)](Packages/KulaCore/Package.swift)
[![MCP](https://img.shields.io/badge/MCP-Bridge-6A1B9A)](docs/native-tools-and-mcp.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Niall-Young/Asky?display_name=tag&color=6A1B9A)](https://github.com/Niall-Young/Asky/releases)

[🌐 官方网站 / Website](https://asky.niallspace.workers.dev/) · [📖 使用教程 / Docs](https://asky.niallspace.workers.dev/docs) · [📦 下载 / Releases](https://github.com/Niall-Young/Asky/releases) · [💬 Issues](https://github.com/Niall-Young/Asky/issues)

**[中文](#中文)** · **[English](#english)**

<img src="docs/assets/launcher.png" alt="Asky launcher" width="800" />

</div>

---

<a id="中文"></a>
## 中文

Asky 是用 SwiftUI 与 AppKit 构建的 macOS 原生效率入口。搜索与剪贴板历史完全在本地运行，不联网也能用；AI 助手只在需要时唤起。

[功能](#核心功能) · [安装](#安装与配置) · [快捷键](#常用入口) · [开发](#开发与构建)

### 核心功能

- **快速搜索**：查找应用、本地文件、Chrome 标签页与书签、应用窗口；支持分类过滤、文件夹浏览、计算与换算、屏幕取色、网页搜索和终端命令。
- **剪贴板历史**：记录文本、富文本、图片与文件，按关键词或来源应用检索；支持颜色预览、自动粘贴、拖拽和自定义保留期限。
- **AI 助手**：Swift 原生 Agent，支持兼容 OpenAI 的模型服务、联网检索、本地 Markdown 记忆和持续对话；可发送附件、回复与引用消息、自然分条回复、在对话中填写原生表单、展示 macOS 原生能力结果卡片并一键跳转对应应用，以及生成磨砂玻璃分享卡片。
- **系统与扩展**：按授权访问日历、提醒事项、备忘录、通讯录和地图；短信以草稿交给用户发送。支持 MCP 与 GitHub 插件，包括[飞书](https://github.com/Niall-Young/asky-plugin-lark)和 [Orca](https://github.com/Niall-Young/asky-plugin-orca)。
- **原生体验与隐私**：适配系统外观和“减少动态效果”，macOS 26+ 支持液态玻璃；不向作者服务器上传用户数据，API Key 存于系统钥匙串。使用模型或外部工具时的数据处理见[隐私政策](PRIVACY.md)。

<details>
<summary><b>联网检索与 AI 配图</b></summary>

联网检索直接调用 Parallel / Exa / Keenable 的免 Key 远程工具，无需浏览器、额外安装或作者的付费账号。Parallel 主用，其余来源轮换；失败与限流由运行时退避，相同请求合并并复用短期缓存。免费接口有服务端限流，失败会保留具体原因，不转付费。详见[网页搜索与页面读取](docs/native-tools-and-mcp.md#agent-公开网页搜索)。

AI 会按图片对理解的帮助主动配图，例如景点、人物、动植物介绍和外观比较；图片从公开网页提取并附来源，纯文字任务不装饰加图。回复前会核对图片来自实际工具结果或用户提供的地址，无来源或无法加载的图片会被移除。点击缩略图可打开独立玻璃预览窗口，支持下载原图或打开来源网页。是否配图仍取决于候选内容与模型选择，详见 [Agent Runtime](docs/agent-runtime.md)。

</details>

### 安装与配置

需要 **macOS 14+（Sonoma）** 与 **Apple Silicon**。

```sh
brew tap niall-young/asky https://github.com/Niall-Young/Asky.git
brew install --cask niall-young/asky/asky
```

也可从 [Releases](https://github.com/Niall-Young/Asky/releases) 下载 DMG，将 `Asky.app` 拖入“应用程序”。应用内自动更新默认开启，可在“设置 › 关于 Asky › 软件更新”中管理；更新前会核对 ZIP 的 SHA-256 校验文件和开发者团队签名。

启动后 Asky 常驻菜单栏，可按需在“设置”中完成基础配置：

1. 通过菜单栏图标或全局快捷键打开快速搜索、剪贴板历史与 AI 助手。
2. 按需在“设置 › 权限”中授予辅助功能权限；自动粘贴和窗口搜索需要该权限。
3. 在“设置 › 触发快捷键”中确认或录制全局快捷键；需要使用 AI 时，在“设置 › 智能配置 › 模型配置”填写 API Key，或配置兼容 OpenAI 的 Base URL 与模型名。

不配置模型也能使用搜索、剪贴板与预览。日历、提醒事项、备忘录等系统功能会在首次使用时申请授权。Agent 不依赖 Node.js 或 Pi；只有旧版 JavaScript 插件需要本机 Node.js 22+，详见[插件开发](docs/plugins.md)。

### 常用入口

| 功能 | 触发方式 / 快捷键 |
| --- | --- |
| 快速搜索 | 菜单栏图标 / 自定义全局快捷键，`Return` 打开结果 |
| 剪贴板历史 | `Ctrl + Shift + C`；`Return` 粘贴，`⌥ Return` 粘贴并保持窗口开启，`⌘ Return` 仅复制 |
| 快速预览 | 在快速搜索或剪贴板历史中选中图片、Markdown 或单个文本文件（如 CSV、JSON、配置文件和源码），按 `Ctrl + 空格`；再按一次或按 `Esc` 关闭 |
| AI 对话 | `Ctrl + Shift + /` |
| 分类检索 | `app ` / `file ` / `ql ` / `sc `（应用 / 文件 / 快捷方式 / 快捷指令） |
| 文件夹浏览 | 选中文件夹后按 `Tab` |
| 窗口搜索 / 屏幕取色 / 计算历史 | `sw` / `co` / `calc` 后回车 |
| 网页搜索 / 终端命令 | `go 关键词`、`yt 关键词` / `> pwd` |
| 操作菜单 / 设置 | `⌘K` / `⌘,`（窗口获焦时） |

触发词可在“设置 › 指令”中自定义。选中支持预览的项目时，“快速预览”会出现在“更多”（`⌘K`）菜单首项，并显示当前快捷键。

如果 macOS 已将 `Ctrl + 空格` 用于切换输入法，Asky 可在有预览可用时优先处理这组按键；也可在“设置 › 触发快捷键”中分别为“文件与应用”和“剪贴板历史”修改快捷键。更多操作与配置见[使用教程](https://asky.niallspace.workers.dev/docs)。

### 开发与构建

需要带有 **Swift 6.2+** 的 Xcode 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。在仓库根目录执行：

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Asky.app
```

若 Swift Package 解析因网络失败，可在 `xcodebuild` 命令后加 `-skipPackageUpdates`。

核心检查：

```sh
(cd MCPBridge && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build)
(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
```

图片栏解析回归：`python3 App/Tests/run-agent-reply-regression.py --image-gallery`（先构建 Debug）；加 `--preview` 可打开四张图片的轮播检查窗口。真实模型检查需显式启用，方法见[主动配图回归](docs/agent-runtime.md#主动配图的真实模型回归)和 [DeepSeek 输入缓存测试](docs/agent-runtime.md#deepseek-输入缓存)。

UI 回归、Debug 预览、签名与打包流程见[开发与发布指南](docs/development.md)。macOS 14/15 实机验收尚待完成，测试范围以[验证记录](docs/validation/)为准。

| 目录 | 职责 |
| --- | --- |
| `App/` | SwiftUI / AppKit 界面与交互 |
| `Packages/KulaCore/` | 核心逻辑、原生 Agent 与统一系统访问入口 `ToolService` |
| `MCPBridge/` | 原生 MCP 桥接服务 |
| `PluginSupport/` | 旧版 JavaScript 插件兼容脚本 |

[文档索引](docs/README.md) · [产品需求](docs/PRD.md) · [系统架构](docs/framework.md) · [设计规范](docs/design-system.md) · [插件开发](docs/plugins.md)

### 参与贡献

欢迎提交 Issue 和 Pull Request。反馈时请附上 Asky 与 macOS 版本、复现步骤及预期结果；提交改动前请先阅读[贡献指南](CONTRIBUTING.md)。

### 许可证

本项目采用 [MIT 许可证](LICENSE)，第三方依赖遵循各自的许可证。

[English](#english) · [返回顶部](#asky)

---

<a id="english"></a>
## English

Asky is a native macOS launcher built with SwiftUI and AppKit. Search and clipboard history run entirely on-device and work offline; the AI assistant starts only when you need it.

[Features](#features) · [Install](#installation-and-setup) · [Shortcuts](#common-shortcuts) · [Development](#development)

### Features

- **Quick search**: Find apps, local files, Chrome tabs and bookmarks, and app windows. Includes category filters, folder browsing, calculations and conversions, a color picker, web search, and terminal commands.
- **Clipboard history**: Save text, rich text, images, and files. Search by keyword or source app, preview colors, paste or drag items, and choose a retention period.
- **AI assistant**: A native Swift Agent with OpenAI-compatible model support, web search, local Markdown memory, and continuous conversation. Send attachments, reply to or quote messages, receive natural multi-bubble replies, fill out native forms in chat, view dedicated macOS capability result cards with one-click app handoff, and export frosted-glass share cards.
- **System integration and extensions**: Authorized access to Calendar, Reminders, Notes, Contacts, and Maps. Messages are handed off as drafts for the user to send. Supports MCP and GitHub plugins, including [Feishu](https://github.com/Niall-Young/asky-plugin-lark) and [Orca](https://github.com/Niall-Young/asky-plugin-orca).
- **Native experience and privacy**: Supports system appearance and Reduce Motion, with Liquid Glass on macOS 26+. No user data is uploaded to author servers; API keys stay in Keychain. See the [Privacy Policy](PRIVACY.md) for data handling when using models or external tools.

<details>
<summary><b>Web research and AI images</b></summary>

Web search calls the anonymous Parallel / Exa / Keenable remote tools, with no browser, extra installation, or developer-paid account required. Parallel is primary and the other providers rotate in; the runtime handles failure cooldowns, duplicate-request coalescing, and a short-lived cache. Free endpoints have provider rate limits, and failures retain diagnostics without switching to paid access. See [web search and page reading](docs/native-tools-and-mcp.md#agent-公开网页搜索).

The AI adds photos when they help explain places, people, animals, plants, or visual comparisons. Images are extracted from public pages with sources attached; text-only tasks get no decorative images. Before publishing, the runtime checks that each image comes from an actual tool result or a user-provided URL and removes unverified or unloadable photos. Clicking a thumbnail opens a dedicated glass preview window with options to download the original or open the source page. Relevance still depends on the available candidates and model selection; see [Agent Runtime](docs/agent-runtime.md).

</details>

### Installation and Setup

Requires **macOS 14+ (Sonoma)** and **Apple Silicon**.

```sh
brew tap niall-young/asky https://github.com/Niall-Young/Asky.git
brew install --cask niall-young/asky/asky
```

Or download the DMG from [Releases](https://github.com/Niall-Young/Asky/releases) and drag `Asky.app` into Applications. In-app automatic updates are enabled by default and can be managed in Settings › About Asky › Software Update; before installing, Asky verifies the ZIP against its SHA-256 checksum file and checks the developer team signature.

Once launched, Asky stays in the menu bar and you can finish initial setup in Settings as needed:

1. Open Quick Search, Clipboard History, and AI Assistant from the menu bar icon or global shortcuts.
2. Grant Accessibility access in Settings › Permissions when needed; automatic pasting and window search require it.
3. Confirm or record global shortcuts in Settings › Keyboard Shortcuts; to use AI, enter your API key in Settings › AI Settings › Model Configuration, or configure an OpenAI-compatible Base URL and model name.

Search, clipboard, and preview work without a model. Calendar, Reminders, Notes, and other system integrations request authorization on first use. The Agent requires neither Node.js nor Pi; only legacy JavaScript plugins need local Node.js 22+, as described in the [plugin guide](docs/plugins.md).

### Common Shortcuts

| Feature | Trigger / Shortcut |
| --- | --- |
| Quick search | Menu bar icon / custom global hotkey; `Return` to open a result |
| Clipboard history | `Ctrl + Shift + C`; `Return` to paste, `⌥ Return` to paste and keep window open, `⌘ Return` to copy |
| Quick preview | Select an image, Markdown document, or text file (such as CSV, JSON, configuration, or source code) in Quick Search or Clipboard History and press `Ctrl + Space`. Press it again or press `Esc` to close. |
| AI conversation | `Ctrl + Shift + /` |
| Category search | `app ` / `file ` / `ql ` / `sc ` (apps / files / quick links / shortcuts) |
| Folder browsing | Select a folder and press `Tab` |
| Window search / color picker / calculation history | `sw` / `co` / `calc`, then Return |
| Web search / terminal command | `go keyword`, `yt keyword` / `> pwd` |
| Action menu / Settings | `⌘K` / `⌘,` (when the window is focused) |

Customize triggers in Settings › Commands. For supported items, Quick Preview and its current shortcut appear at the top of the More menu (`⌘K`).

If macOS uses `Ctrl + Space` to switch input sources, Asky handles the shortcut first when a preview is available. You can also change Quick Preview for Files and Applications and Clipboard History in Settings › Keyboard Shortcuts. See the [User Guide](https://asky.niallspace.workers.dev/docs) for more actions and configuration.

### Development

Requires Xcode with **Swift 6.2+** and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Run from the repository root:

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Asky.app
```

If Swift Package resolution fails on the network, add `-skipPackageUpdates` to the `xcodebuild` command.

Core checks:

```sh
(cd MCPBridge && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build)
(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
```

Image strip parsing regression: `python3 App/Tests/run-agent-reply-regression.py --image-gallery` (build Debug first); add `--preview` to open a four-image carousel for interaction checks. Live-model tests are opt-in; see [image reply regression](docs/agent-runtime.md#主动配图的真实模型回归) and [DeepSeek input cache testing](docs/agent-runtime.md#deepseek-输入缓存).

See the [Development and Release Guide](docs/development.md) for UI regressions, Debug previews, and signing and packaging. Testing on macOS 14/15 hardware is still pending; consult the [validation records](docs/validation/) for current coverage.

| Directory | Responsibility |
| --- | --- |
| `App/` | SwiftUI / AppKit interface and interactions |
| `Packages/KulaCore/` | Core logic, native Agent, and unified system access through `ToolService` |
| `MCPBridge/` | Native MCP bridge |
| `PluginSupport/` | Legacy JavaScript plugin compatibility scripts |

[Docs index](docs/README.md) · [Product requirements](docs/PRD.md) · [Architecture](docs/framework.md) · [Design system](docs/design-system.md) · [Plugins](docs/plugins.md)

### Contributing

Issues and pull requests are welcome. Include your Asky and macOS versions, reproduction steps, and expected behavior when reporting a problem, and read the [contributing guide](CONTRIBUTING.md) before submitting a change.

### License

Distributed under the [MIT License](LICENSE). Third-party dependencies retain their respective licenses.

[中文](#中文) · [Back to top](#asky)
