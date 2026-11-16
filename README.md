<div align="center">

<img src="App/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" alt="Asky" width="128" height="128" />

# Asky

macOS 原生效率入口，连接本地搜索、剪贴板与按需 AI 助手。<br />
A native macOS launcher for local search, clipboard history, and an on-demand AI assistant.

[![macOS](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](project.yml)
[![Swift](https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift&logoColor=white)](Packages/KulaCore/Package.swift)
[![MCP](https://img.shields.io/badge/MCP-Bridge-6A1B9A)](docs/native-tools-and-mcp.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[🌐 官方网站 / Website](https://asky.niallspace.workers.dev/) · [📖 使用教程 / Docs](https://asky.niallspace.workers.dev/docs) · [📦 立即下载 / Releases](https://github.com/Niall-Young/Asky/releases)

[中文](#中文) | [English](#english)

<img src="docs/assets/launcher.png" alt="Asky launcher" width="800" />

</div>

---

<a id="中文"></a>
## 中文

Asky 是使用 SwiftUI 与 AppKit 构建的 macOS 原生效率入口。本地搜索和剪贴板历史可离线使用，AI 助手按需唤起。

### 核心功能

- **快速搜索**：查找应用、本地文件、Chrome 标签页与书签、应用窗口；支持分类过滤、文件夹浏览、计算与换算、屏幕取色、网页搜索和终端命令。
- **剪贴板历史**：记录文本、富文本、图片与文件，按关键词或来源应用检索；支持颜色预览、自动粘贴、拖拽和自定义保留期限。
- **AI 助手**：Swift 原生 Agent，支持兼容 OpenAI 的模型服务、联网检索、本地 Markdown 记忆和持续对话；可发送附件、引用消息，并在对话中填写原生表单。
- **系统与扩展**：按授权访问日历、提醒事项、备忘录、通讯录和地图；短信以草稿交给用户发送。支持 MCP 和 GitHub 插件，包括[飞书](https://github.com/Niall-Young/asky-plugin-lark)与 [Orca](https://github.com/Niall-Young/asky-plugin-orca)。
- **原生体验与隐私**：适配系统外观和“减少动态效果”，macOS 26+ 支持液态玻璃；不向作者服务器上传用户数据，API Key 存于系统钥匙串。使用模型或外部工具时的数据处理见[隐私政策](PRIVACY.md)。

联网检索直接调用 Parallel / Exa 的免 Key 远程工具，返回较长摘录并支持按 URL 读取公开网页正文；不启动浏览器、不安装组件，也不使用作者的付费账号。免费接口有服务端限流，触限会明确报告，不转付费。详见[网页搜索与页面读取](docs/native-tools-and-mcp.md#agent-公开网页搜索)。

### 安装与配置

需要 **macOS 14+、Apple Silicon**。

```sh
brew tap niall-young/asky https://github.com/Niall-Young/Asky.git
brew install --cask niall-young/asky/asky
```

也可从 [Releases](https://github.com/Niall-Young/Asky/releases) 下载 DMG，将 `Asky.app` 拖入“应用程序”。应用内自动更新默认开启，可在“设置 › 关于 Asky › 软件更新”中管理。

- **权限**：自动粘贴和窗口搜索需要辅助功能权限；日历、备忘录等在首次使用时申请授权。
- **AI 配置**：在“设置 › 智能配置 › 模型配置”填写 API Key，或配置兼容 OpenAI 的 Base URL 与模型名。
- **运行环境**：Agent 不依赖 Node.js 或 Pi；旧版 JavaScript 插件需要本机 Node.js 22+，详情见[插件开发](docs/plugins.md)。

### 常用入口

| 功能 | 触发方式 / 快捷键 |
| --- | --- |
| 快速搜索 | 菜单栏图标 / 自定义全局快捷键，`Return` 打开结果 |
| 剪贴板历史 | `Ctrl + Shift + C`；`Return` 粘贴，`⌘ Return` 仅复制 |
| AI 对话 | `Ctrl + Shift + /` |
| 分类检索 | `app ` / `file ` / `ql ` / `sc `（应用 / 文件 / 快捷方式 / 快捷指令） |
| 文件夹浏览 | 选中文件夹后按 `Tab` |
| 窗口搜索 / 屏幕取色 / 计算历史 | `sw` / `co` / `calc` 后回车 |
| 网页搜索 / 终端命令 | `go 关键词`、`yt 关键词` / `> pwd` |
| 操作菜单 / 设置 | `⌘K` / `⌘,`（窗口获焦时） |

触发词可在“设置 › 指令”中自定义。更多操作与配置见[使用教程](https://asky.niallspace.workers.dev/docs)。

### 开发与构建

需要带有 **Swift 6.2+** 的 Xcode 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。在仓库根目录执行：

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Asky.app
```

核心检查：

```sh
(cd MCPBridge && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build)
(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
```

UI 回归、Debug 预览、`scripts/package-release.py` 签名与打包流程见[开发与发布指南](docs/development.md)。macOS 14/15 实机验收尚待完成，具体测试范围以[验证记录](docs/validation/)为准。

| 目录 | 职责 |
| --- | --- |
| `App/` | SwiftUI / AppKit 界面与交互 |
| `Packages/KulaCore/` | 核心逻辑、原生 Agent 与统一系统访问入口 `ToolService` |
| `MCPBridge/` | 原生 MCP 桥接服务 |
| `PluginSupport/` | 旧版 JavaScript 插件兼容脚本 |

[文档索引](docs/README.md) · [产品需求](docs/PRD.md) · [系统架构](docs/framework.md) · [设计规范](docs/design-system.md) · [插件开发](docs/plugins.md)

### 许可证

本项目采用 [MIT 许可证](LICENSE)，第三方依赖遵循各自的许可证。

[English](#english) · [返回顶部](#asky)

---

<a id="english"></a>
## English

Asky is a native macOS launcher built with SwiftUI and AppKit. Local search and clipboard history work offline; the AI assistant runs on demand.

### Features

- **Quick search**: Find apps, local files, Chrome tabs and bookmarks, and app windows. Includes category filters, folder browsing, calculations and conversions, a color picker, web search, and terminal commands.
- **Clipboard history**: Save text, rich text, images, and files. Search by keyword or source app, preview colors, paste or drag items, and choose a retention period.
- **AI assistant**: A native Swift Agent with OpenAI-compatible model support, web search, local Markdown memory, and continuous conversation. Send attachments, quote messages, and fill out native forms in chat.
- **System integration and extensions**: Authorized access to Calendar, Reminders, Notes, Contacts, and Maps. Messages are handed off as drafts for the user to send. Supports MCP and GitHub plugins, including [Feishu](https://github.com/Niall-Young/asky-plugin-lark) and [Orca](https://github.com/Niall-Young/asky-plugin-orca).
- **Native experience and privacy**: Supports system appearance and Reduce Motion, with Liquid Glass on macOS 26+. No user data is uploaded to author servers; API keys stay in Keychain. See the [Privacy Policy](PRIVACY.md) for data handling when using models or external tools.

Web search calls the anonymous Parallel / Exa remote tools, with longer excerpts and public page reading by URL. It needs no browser, extra installation, or developer-paid account. Free endpoints have provider rate limits; failures are reported without switching to paid access. See [web search and page reading](docs/native-tools-and-mcp.md#agent-公开网页搜索).

### Installation and Setup

Requires **macOS 14+ and Apple Silicon**.

```sh
brew tap niall-young/asky https://github.com/Niall-Young/Asky.git
brew install --cask niall-young/asky/asky
```

Or download the DMG from [Releases](https://github.com/Niall-Young/Asky/releases) and drag `Asky.app` into Applications. In-app automatic updates are enabled by default; manage them in Settings › About Asky › Software Update.

- **Permissions**: Automatic pasting and window search require Accessibility access. Calendar, Notes, and other system integrations request authorization on first use.
- **AI setup**: Enter your API key or an OpenAI-compatible Base URL and model name in Settings › AI Settings › Model Configuration.
- **Runtime**: The Agent requires neither Node.js nor Pi. Legacy JavaScript plugins need local Node.js 22+; see the [plugin guide](docs/plugins.md).

### Common Shortcuts

| Feature | Trigger / Shortcut |
| --- | --- |
| Quick search | Menu bar icon / custom global hotkey; `Return` to open a result |
| Clipboard history | `Ctrl + Shift + C`; `Return` to paste, `⌘ Return` to copy |
| AI conversation | `Ctrl + Shift + /` |
| Category search | `app ` / `file ` / `ql ` / `sc ` (apps / files / quick links / shortcuts) |
| Folder browsing | Select a folder and press `Tab` |
| Window search / color picker / calculation history | `sw` / `co` / `calc`, then Return |
| Web search / terminal command | `go keyword`, `yt keyword` / `> pwd` |
| Action menu / Settings | `⌘K` / `⌘,` (when the window is focused) |

Customize triggers in Settings › Commands. See the [User Guide](https://asky.niallspace.workers.dev/docs) for more actions and configuration.

### Development

Requires Xcode with **Swift 6.2+** and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Run from the repository root:

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Asky.app
```

Core checks:

```sh
(cd MCPBridge && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build)
(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
```

See the [Development and Release Guide](docs/development.md) for UI regressions, Debug previews, and signing and packaging with `scripts/package-release.py`. Testing on macOS 14/15 hardware is still pending; consult the [validation records](docs/validation/) for test coverage.

| Directory | Responsibility |
| --- | --- |
| `App/` | SwiftUI / AppKit interface and interactions |
| `Packages/KulaCore/` | Core logic, native Agent, and unified system access through `ToolService` |
| `MCPBridge/` | Native MCP bridge |
| `PluginSupport/` | Legacy JavaScript plugin compatibility scripts |

[Docs index](docs/README.md) · [Product requirements](docs/PRD.md) · [Architecture](docs/framework.md) · [Design system](docs/design-system.md) · [Plugins](docs/plugins.md)

### License

Distributed under the [MIT License](LICENSE). Third-party dependencies retain their respective licenses.

[中文](#中文) · [Back to top](#asky)
