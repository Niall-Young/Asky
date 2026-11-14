<div align="center">

<img src="App/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" alt="Asky" width="128" height="128" />

# Asky

macOS 原生效率入口，连接本地搜索、剪贴板与按需 AI 助手。<br />
A native macOS launcher for local search, clipboard history, and an on-demand AI assistant.

[![macOS](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](project.yml)
[![Swift](https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift&logoColor=white)](Packages/KulaCore/Package.swift)
[![MCP](https://img.shields.io/badge/MCP-Bridge-6A1B9A)](docs/native-tools-and-mcp.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[🌐 官方网站 / Website](https://asky.niallyoung2002.workers.dev/) · [📖 使用教程 / Docs](https://asky.niallyoung2002.workers.dev/docs) · [📦 立即下载 / Releases](https://github.com/Niall-Young/Asky/releases)

[中文](#中文) | [English](#english)

<img src="docs/assets/launcher.png" alt="Asky launcher" width="800" />

</div>

---

<a id="中文"></a>
## 中文

Asky 是使用 SwiftUI 与 AppKit 构建的 macOS 原生效率入口。本地全局搜索与剪贴板历史可完全独立离线使用，AI 助手按需唤起，兼具极致轻量的系统体验与强大的扩展能力。

🌐 **官方网站**：[https://asky.niallyoung2002.workers.dev/](https://asky.niallyoung2002.workers.dev/)  
📖 **使用教程**：[功能指南与操作手册](https://asky.niallyoung2002.workers.dev/docs)

### ✨ 核心功能

- 🔍 **全局快速搜索**
  - **全能检索**：秒级检索应用程序、本地文件、Chrome 标签页与书签，以及当前运行的应用窗口（`sw`）。
  - **分类过滤与下钻**：支持 `app `（应用）、`file `（文件）、`ql `（快捷方式）、`sc `（快捷指令）专属分类过滤；选中文件夹按 `Tab` 可直接下钻浏览或检索子目录。
  - **即时计算与换算**：支持数学表达式计算、单位换算与实时汇率换算；输入 `calc` 查看计算历史并支持一键回填算式。
  - **屏幕取色器**：输入 `co` 快速调用 macOS 原生取色工具，点击即复制大写 sRGB 十六进制色值。
  - **快捷指令与终端**：集成网页搜索指令（`go`、`yt`、`x` 等预设）与终端命令执行（`> 命令`），支持系统终端、iTerm2、Ghostty 1.3+、Otty 1.2+ 和 Kero。

- 📋 **强大的剪贴板历史**
  - **多类型支持**：完整记录文本、富文本、图片与文件历史，支持关键词与来源应用组合检索。列表每批加载 40 条，滚动或键盘接近末尾继续加载；搜索在后台分批读取，输入防抖并取消旧查询，隐藏滚动条。
  - **智能颜色预览**：自动识别 `#RGB`、`rgb()`、`hsl()`、`oklch()` 等颜色代码并显示直观的圆形色盘预览。
  - **无缝粘贴体验**：`Return` 自动粘贴到目标应用（需辅助功能权限），`⌘ Return` 仅复制并保留窗口；支持文件与图片的平滑拖拽。
  - **灵活历史管理**：支持自定义保留期限（8 小时 ~ 30 天）与自动清理，支持快捷键 `⌘⌫` 单条删除或 `⌘K` 菜单清空历史。

- 🤖 **按需 AI 助手与本地记忆**
  - **图片附件**：对话消息中的多张图片默认堆叠收起，悬停展开、移开收起；展开后可横向滚动。聚焦后按 Return 或空格切换展开，Esc 收起；遵循系统“减少动态效果”。单张图片、文件附件和输入区保留原有布局。
  - **Asky 形象**：对话左上角显示小怪物头像，默认蓝色；点击头像会在原位置变形成液态玻璃菜单，可切换蓝、黄、紫、绿、粉五种配色，选择会保留。输入框发送按钮同步使用当前头像配色。圆形头像容器与右侧按钮组同为 36 pt 高。用户消息在中性底上轻微叠加头像配色，文字跟随深浅外观；切换颜色时已有用户消息同步更新，Asky 回复与等待气泡保持中性色。
  - **紧凑对话窗口**：固定 560 pt 宽、26 pt 普通圆角，默认高 560 pt，可纵向调整至最低 480 pt；紧凑玻璃输入框采用 16 pt 圆角，附件与发送按钮均为 28 pt。顶部不显示会话标题，顶部 64 pt 内的背景模糊半径由 6 pt 向下渐进到零，不叠加颜色；右侧为无分割线的连体胶囊按钮组，常驻置顶和电源符号关闭按钮；头像与按钮组统一使用原生 Clear 玻璃和 35% 背景强度，并提供悬停柔和提亮、按下整体膨胀和松手回弹；开启“减少动态效果”时不缩放。
  - **液态按钮交互**：聊天与启动器操作按钮采用参考 iOS 录屏定制的按压膨胀和松手回弹，保持原有静止外观；玻璃表面悬停时柔和提亮；启动器与剪贴板底部操作按钮使用 Clear 玻璃和 60% 背景强度，文字与快捷键保持完整不透明度。该交互不是 macOS 系统自带动画。设置按钮采用 28 pt 原生胶囊样式，单行输入、密码、下拉与搜索框统一为 28 pt 高度和胶囊圆角，指令与插件分类使用中性选中态的原生分段控件；窗口失焦时保持控件尺寸，不再额外加深背景染色；减少动态效果时关闭定制缩放。
  - **Swift 原生 Agent**：模型请求、工具循环、会话恢复和上下文压缩均由 Swift 执行。对话采用左右气泡，仅在本轮结束后展示完整回答；等待期间显示三点加载气泡，隐藏工具调用与过程说明。回答出现或更新时保持阅读位置，仅发送新问题时定位到底部，也可手动回到底部。回复保留原生表单、复制和完成时间，Markdown 标题使用普通正文样式；无需 Node / Pi 辅助进程，支持 OpenAI-compatible Chat Completions。
  - **持续对话**：各入口和重启后接入同一时间线，旧消息在时间线中每批加载 40 条，内存窗口最多保留 120 条；不再提供单独的历史对话页面和快捷键，滚动条隐藏；新请求按需读取保留的历史，清空聊天后保留长期记忆。
  - **对话历史**：新保存的会话保留工具调用状态、错误、回复分组与耗时，支持分页恢复；旧会话未保存的工具展示记录不会自动补回。在“设置 › 智能配置 › 对话历史”选择保留 7 天、30 天（默认）、90 天或永久；按用户提交轮次的时间清理，启动时、每天及修改期限后检查。到期或手动删除会清理会话、执行记录、索引及无引用的自有附件，已保存记忆独立保留，失败文件自动重试。
  - **原生交互表单**：AI 回复完成后一次显示原生单选按钮组、下拉单选、多选、文本输入、日期及按需显示时、分、秒的时间/时长控件，AI 澄清需求或确认方案时可同时提供预设选项与「自己填写」，选择或自填后点击「提交回复」自动发送到同一会话并继续处理。控件复用设置页组件，日期选择复用创建日程弹窗的月历。
  - **本地记忆与上下文**：基于本地 Markdown 存储用户偏好与记忆，支持长上下文智能压缩与网络实时检索。
  - **网页来源预览**：网页来源在对应段落末尾合并为“来源名称 +N”标签；悬停或点击展开来源列表，显示来源名称、标题和可获取的发布日期，点击条目打开原文。来源较多时可在卡片内滚动。
  - **本地数学公式排版**：原生支持行内与独立 LaTeX 公式（`$…$`、`$$…$$`）排版。
  - **日程与路线规划**：集成系统 MapKit 能力，对比驾车、公交与步行耗时，自动为日程计算含缓冲时间的建议出发时间。

- 🧩 **系统生态与扩展**
  - **macOS 系统集成**：按授权安全访问系统日历、提醒事项、备忘录与通讯录。
  - **MCP 协议支持**：内置 MCP（Model Context Protocol）桥接，可无缝连接外部工具生态。
  - **可信插件体系**：支持用户主动安装 GitHub 插件；设置中按 AI 插件和功能插件分 Tab 查看，并可跨分类搜索名称与命令；插件可提供无需 AI 的启动器命令与动态搜索结果，支持复制和打开链接，详见[插件开发](docs/plugins.md)。官方提供 [飞书插件](https://github.com/Niall-Young/asky-plugin-lark) 与 [Orca 插件](https://github.com/Niall-Young/asky-plugin-orca)。

- 🎨 **纯正 macOS 原生体验与隐私优先**
  - **现代视觉语言**：采用 AppKit 原生 Regular 玻璃与液态视觉质感，窗口平滑展开后保持固定高度，结果变化不再伸缩，完全清空普通搜索时收回单行输入，空查询搜索模式保持展开；严格适配系统“减少动态效果”。
  - **背景交互**：点击搜索框外部时收起窗口，原始点击继续交给背景应用；背景滚动与拖动不受遮罩拦截。
  - **严格隐私保护**：不向作者服务器上传任何用户数据；API 密钥安全存放在 macOS 系统钥匙串中，数据完全归用户所有。详见[隐私政策](PRIVACY.md)。

---

### ⌨️ 快捷键与常用入口

| 功能 | 触发方式 / 快捷键 | 说明 |
| :--- | :--- | :--- |
| **快速搜索** | 菜单栏图标 / 自定义全局快捷键 | 键入关键词，方向键选择，`Return` 打开 |
| **剪贴板历史** | `Ctrl + Shift + C` | 浏览历史记录，`Return` 粘贴，`⌘ Return` 仅复制 |
| **打开 AI 对话** | `Ctrl + Shift + /` | 唤出按需 AI 对话界面 |
| **分类检索** | `file ` / `app ` / `ql ` / `sc ` | 仅搜索指定分类（文件/应用/快捷方式/快捷指令），`Esc` 退出 |
| **文件夹浏览** | 选中文件夹按 `Tab` | 在搜索框内直接浏览或搜索该文件夹目录内容 |
| **窗口搜索** | `sw ` 或 `sw` 后回车 | 检索应用通过辅助功能暴露的窗口并一键切换聚焦；`⌘K` 菜单提供“关闭窗口”，固定在最下方；多屏时可用“切换到上一块屏幕 / 下一块屏幕”（`⇧ ←` / `⇧ →`），横排从左到右、竖排从上到下并循环；单屏或选中的窗口处于系统全屏时隐藏这两项；屏幕切换快捷键可在“设置 › 快捷键 › 启动器”配置 |
| **屏幕取色** | `co` 后回车 | 开启屏幕取色放大镜，点击后自动复制色值到剪贴板 |
| **计算历史** | `calc` 后回车 | 浏览最近 200 条计算结果，回车回填算式继续编辑 |
| **网页指令** | `go 关键词`、`yt 关键词` 等 | 输入指令后按空格或回车进入，输入关键词后回车打开搜索结果 |
| **终端执行** | `> pwd` | 直接在启动器中执行 Shell 命令 |
| **项操作菜单** | `⌘K` | 打开当前项的更多操作菜单（如展示文件简介 `⌘I`、复制文件名 `⌘⇧.` 等） |
| **打开设置** | `⌘,`（窗口获焦时） | 呼出 Asky 设置面板 |

*完整快捷键配置与高级技巧见[使用教程](https://asky.niallyoung2002.workers.dev/docs)。*

---

### 📦 安装与配置

#### Homebrew

```sh
brew tap niall-young/asky https://github.com/Niall-Young/Asky.git
brew install --cask niall-young/asky/asky
```

支持 macOS 14+、Apple Silicon，使用与手动下载相同的正式安装包。应用内自动更新默认开启；也可运行 `brew update && brew upgrade --cask --greedy niall-young/asky/asky` 更新，或运行 `brew uninstall --cask niall-young/asky/asky` 卸载应用。卸载保留个人数据与设置。

#### 下载安装
- 前往 [GitHub Releases](https://github.com/Niall-Young/Asky/releases) 或 [官方网站](https://asky.niallyoung2002.workers.dev/) 下载最新 DMG 安装包（支持 macOS 14+，Apple Silicon）。
- 打开 DMG，将 `Asky.app` 拖入“应用程序”目录即可。Agent 已使用 Swift 原生运行时，安装包不再携带 Node.js 或 Pi。Orca、飞书插件执行器与 Text Tools 聚焦搜索示例使用 API v2 Swift 原生入口，无需 Node；CLI 自身环境由用户准备。旧版 JavaScript 插件另需本机 Node.js 22+。
- 应用默认开启静默自动更新，可在“设置 › 关于 Asky › 软件更新”中管理。

#### 权限与 AI 配置
- **系统权限**：自动粘贴与窗口搜索功能需要 macOS **辅助功能**（Accessibility）权限；访问日历、备忘录等需在首次使用时授权。
- **智能配置**：在“设置 › 智能配置”中填入对应模型服务商的 API Key，或自定义兼容 OpenAI 协议的 Base URL 及模型名。API 密钥安全存放在 macOS 系统钥匙串中。

---

### 🛠️ 开发与构建

当前源码最低支持 macOS 14，功能与 macOS 15 保持一致，均使用原生背景模糊材质；macOS 26+ 可使用液态玻璃。14 的设置使用原生分组表单，15+ 保留自定义卡片。macOS 14/15 实机验收尚待完成。0.2.10 起的正式安装包与 Homebrew Cask 支持 macOS 14。

登录时启动的开关以 macOS 实际状态为准；若需要批准，在“设置 › 通用”点击“打开登录项设置…”完成授权，返回后会刷新状态。已有安装保留系统选择，关闭后不会自动重新开启。

#### 环境要求
- 目标运行系统：macOS 14+ (Apple Silicon)
- Xcode 16+ / Swift 6.2+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

应用图标源文件为 `App/Branding/AskyNative.icon`，使用 Xcode 附带的 Icon Composer 编辑。修改后同步导出的 `AppIcon.appiconset`、`AskyLogo.imageset` 和 `App/Branding` 中的 PNG / ICNS 兼容资源。

#### 构建与运行
在仓库根目录执行：

```sh
# 1. 生成 Xcode 工程
xcodegen generate

# 2. 编译并启动 Debug 版本
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Asky.app
# 直接打开 AI 窗口，不发送请求
open -n build/DerivedData/Build/Products/Debug/Asky.app --args --show-agent
```

#### 运行测试
```sh
# 核心测试套件
(cd MCPBridge && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build)
(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
# 气泡对话与等待状态回归（先完成 Debug 构建）
python3 App/Tests/run-agent-reply-regression.py --reply-activity-preview
python3 App/Tests/run-agent-reply-regression.py --reading-scroll
python3 App/Tests/run-agent-reply-regression.py --forms-preview --custom-preview
```

启动器首帧诊断使用隔离数据，录制独立 Debug 进程的首次打开与再次打开；需要屏幕录制权限。输出保存在 `build/`，不操作日常安装和数据：

```sh
python3 App/Tests/run-launcher-presentation-diagnostic.py --output build/launcher-presentation/current
```

录制请求 60 fps，实际交付帧率以输出文件与日志为准；复制 Debug 应用路径的检查不等同于正式安装更新验证。详细覆盖见[开发指南](docs/development.md)。

> [!NOTE]
> 完整的 UI 自动化回归脚本、Debug 交互预览参数以及 Developer ID 签名与公证打包流程，详见[开发与发布指南](docs/development.md)。

---

### 📂 代码结构与文档

| 目录 | 职责说明 |
| :--- | :--- |
| `App/` | 基于 SwiftUI 与 AppKit 的原生客户端界面与交互实现 |
| `Packages/KulaCore/` | 核心业务模型与统一系统访问入口 `ToolService` |
| `PluginSupport/` | 旧版 JavaScript 插件兼容脚本；Agent 本身位于 KulaCore 的 AgentHost |
| `MCPBridge/` | Model Context Protocol 原生桥接服务 |

- [文档索引](docs/README.md) · [产品需求 (PRD)](docs/PRD.md) · [系统架构](docs/framework.md) · [设计规范](docs/design-system.md) · [插件开发](docs/plugins.md) · [隐私政策](PRIVACY.md)

---

### 📄 许可证

本项目采用 [MIT 许可证](LICENSE)。第三方依赖项遵循其各自的开源协议。

[English](#english) · [返回顶部](#asky)

---

<a id="english"></a>
## English

Asky is a native macOS efficiency launcher built with SwiftUI and AppKit. Local global search and clipboard history work completely offline without relying on AI, while the AI assistant runs on-demand—delivering both lightweight performance and extensive expandability.

🌐 **Website**: [https://asky.niallyoung2002.workers.dev/](https://asky.niallyoung2002.workers.dev/)  
📖 **Documentation**: [User Guide & Manual](https://asky.niallyoung2002.workers.dev/docs)

### ✨ Key Features

- 🔍 **Global Fast Search**
  - **Continuous conversation**: All entry points resume one timeline, including after restart. Older messages load in batches of 40, with at most 120 items in the in-memory window. The separate history browser and its shortcut are removed, and scrollbars are hidden. Each request uses retained history as needed; clearing chat history preserves long-term memory.
  - **Comprehensive Retrieval**: Instantly search applications, local files, Chrome tabs and bookmarks, and active application windows (`sw`).
  - **Category Filtering & Deep Dive**: Use dedicated filters like `app `, `file `, `ql ` (quick links), and `sc ` (shortcuts). Press `Tab` on any folder to browse or search its subdirectories directly.
  - **Instant Calculations & Conversions**: Support for mathematical formulas, unit conversions, and live currency rates. Enter `calc` to view calculation history and restore expressions with one click.
  - **Screen Color Picker**: Enter `co` to launch macOS's native color sampler; click to copy the sRGB uppercase hex value.
  - **Web Commands & Terminal**: Quick web search presets (`go`, `yt`, `x`, etc.) and terminal command execution (`> command`) with Terminal, iTerm2, Ghostty 1.3+, Otty 1.2+, and Kero.

- 📋 **Robust Clipboard History**
  - **Multi-Type Support**: Records text, rich text, images, and files with combined keyword and source app search. The list loads 40 entries per page, fetching more near the end via scrolling or keyboard navigation. Search reads bounded batches in the background, debounces typing and cancels stale queries; scrollbars are hidden.
  - **Smart Color Previews**: Automatically detects `#RGB`, `rgb()`, `hsl()`, `oklch()`, and other CSS color formats, rendering circular color previews.
  - **Seamless Pasting**: Press `Return` to paste into the active target app (requires Accessibility permission); `⌘ Return` copies while keeping the panel open. Supports smooth drag-and-drop for files and images.
  - **Flexible Retention**: Configure history retention (8 hours to 30 days) with automatic cleanup. Delete single entries with `⌘⌫` or clear all via the More menu (`⌘K`).

- 🤖 **On-Demand AI Assistant & Local Memory**
  - **Image Attachments**: Multiple images in a message form a compact stack that opens on hover and closes when the pointer leaves. Expanded stacks scroll horizontally. When focused, Return or Space toggles expansion and Escape collapses it; system Reduce Motion is respected. Single images, files, and composer attachments retain their existing layout.
  - **Asky Avatar**: The monster avatar defaults to blue. Click it to morph the avatar into a Liquid Glass menu in place and choose blue, yellow, purple, green, or pink; the choice is saved. The composer send button follows the selected avatar color. Its 36 pt glass circle matches the height of the toolbar controls. User message bubbles add a subtle avatar-color tint over a neutral fill, with text adapting to the appearance; changing the color also updates existing user messages. Asky reply and typing bubbles stay neutral.
  - **Compact Chat Window**: Fixed at 560 pt wide with 26 pt circular corners, a default height of 560 pt and a minimum adjustable height of 480 pt; the compact glass composer uses 16 pt corners and matching 28 pt attachment and send buttons. The title-free header progressively blurs the top 64 pt from a 6 pt radius down to zero without a color overlay, with a joined capsule group without dividers for Pin and a power-symbol Close button on the right; the avatar and toolbar group use native Clear glass at 35% background opacity, with soft hover illumination, uniform press expansion and a spring release; Reduce Motion disables scaling.
  - **Liquid Button Interaction**: Chat and launcher action buttons use custom press expansion and spring release based on an iOS recording, preserving their resting appearance. Glass surfaces brighten softly on hover; launcher and clipboard footer buttons use Clear glass at 60% background opacity, with fully opaque labels and shortcut keys. This motion is custom, not a built-in macOS animation. Settings use 28 pt native capsule buttons, 28 pt capsule text, password, dropdown and search fields, and native segmented category controls with a neutral selection. Controls retain their size when the window loses focus, without extra background tint. Reduce Motion disables custom scaling.
  - **Native Swift Agent**: Swift handles model requests, tool loops, session recovery, and context compaction without a Node / Pi helper. Chat uses left/right message bubbles and shows the complete answer after the turn finishes, with a three-dot typing bubble while waiting. Replies preserve the reading position when they appear or update; sending a new question scrolls to the bottom, with a manual return-to-bottom button available. Tool calls and progress narration are hidden; native forms, copy actions, and completion times remain, and Markdown headings use body typography; supports OpenAI-compatible Chat Completions.
  - **Conversation History**: Newly saved conversations retain tool statuses, errors, response groups, and elapsed time across paginated reloads. Tool display records missing from older conversations are not backfilled. Settings › AI Settings › Conversation History offers 7, 30 (default), or 90 days, or forever, based on each user turn’s submission time. Cleanup runs at startup, daily, and after retention changes. Expiry and manual deletion remove sessions, execution records, indexes, and unreferenced managed attachments while preserving saved memory; failed file removals are retried.
  - **Native Interactive Forms**: Completed AI replies display structured form controls (text fields, native radio groups, dropdowns, checkboxes, date pickers and configurable hour/minute/second time or duration controls) directly in chat, which submit straight back into the conversation. Clarification and plan choices can offer both suggested answers and “Write my own”; Submit Reply sends the active answer as a message in the same conversation so the assistant can continue. Controls reuse the Settings components; date selection uses the calendar from the event creation dialog.
  - **Local Memory & Context**: Stores user preferences and context in local Markdown files with automatic context compaction and web search.
  - **Web Source Previews**: Web sources are grouped into a source-name tag with a +N count at the end of each paragraph. Hover or click to expand a list of source names, titles, and available publication dates; click a row to open the original. Longer lists scroll within the card.
  - **Native LaTeX Rendering**: Renders inline and block LaTeX formulas (`$…$`, `$$…$$`) locally.
  - **Smart Travel & Calendar Planning**: Built-in MapKit support to compare driving, transit, and walking times, suggesting arrival-buffered departure times for your day.

- 🧩 **System Integration & Extensibility**
  - **macOS Native Access**: Authorized access to system Calendars, Reminders, Notes, and Contacts.
  - **MCP Protocol**: Built-in Model Context Protocol bridge for broad compatibility with external tooling ecosystems.
  - **Trusted Plugin System**: Install plugins from GitHub on demand. Settings separates AI and function plugins into tabs, with search across categories, names, and commands. Plugins can provide launcher commands and dynamic search results without AI, with copy and open-link actions; see the [plugin guide](docs/plugins.md). Official integrations include [Feishu](https://github.com/Niall-Young/asky-plugin-lark) and [Orca](https://github.com/Niall-Young/asky-plugin-orca).

- 🎨 **Pure macOS Native Experience & Privacy First**
  - **Modern Interface**: Built with AppKit Regular Liquid Glass. Once expanded, the panel keeps a fixed height as results change. Clearing root search collapses it to the single input row; an empty query inside a search mode stays expanded. Supports smooth expansion and Reduce Motion.
  - **Background Interaction**: Clicking outside the launcher dismisses it while delivering the original click to the background app. Background scrolling and dragging remain available.
  - **Privacy First**: Zero telemetry sent to author servers. Sensitive credentials and API keys are stored securely in the macOS Keychain. See [Privacy Policy](PRIVACY.md).

---

### ⌨️ Shortcuts & Key Entries

| Feature | Trigger / Shortcut | Description |
| :--- | :--- | :--- |
| **Quick Search** | Menu bar icon / Global hotkey | Type keywords, navigate with arrow keys, press `Return` to open |
| **Clipboard History** | `Ctrl + Shift + C` | Browse history, `Return` to paste, `⌘ Return` to copy |
| **New AI Chat** | `Ctrl + Shift + /` | Open the on-demand AI conversation panel |
| **Category Search** | `file ` / `app ` / `ql ` / `sc ` | Filter results by category (files/apps/quick links/shortcuts); `Esc` to exit |
| **Folder Browse** | Select folder + `Tab` | Browse or search folder contents directly in launcher |
| **Window Search** | `sw ` or `sw` + Return | Find and focus application windows exposed through Accessibility; `⌘K` offers Close Window, always last; with multiple displays, Move to Previous/Next Display (`⇧ ←` / `⇧ →`) cycles left to right for horizontal layouts and top to bottom for vertical layouts; both actions are hidden with a single display or when the selected window is in native full screen; display shortcuts are configurable in Settings › Shortcuts › Launcher |
| **Color Picker** | `co` + Return | Open screen color sampler and copy hex value to clipboard |
| **Calculation History** | `calc` + Return | View last 200 calculations and restore expressions |
| **Web Commands** | `go keyword`, `yt keyword`, etc. | Press Space or Return after a command to enter it, then type a query and press Return to search |
| **Terminal** | `> pwd` | Execute shell commands directly from the search bar |
| **Action Menu** | `⌘K` | Open context menu (Show Get Info `⌘I`, Copy filename `⌘⇧.`, etc.) |
| **Settings** | `⌘,` (when window is focused) | Open Asky Settings |

*See the [User Guide](https://asky.niallyoung2002.workers.dev/docs) for advanced configuration and full shortcut listings.*

---

### 📦 Installation & Setup

#### Homebrew

```sh
brew tap niall-young/asky https://github.com/Niall-Young/Asky.git
brew install --cask niall-young/asky/asky
```

Requires macOS 14+ and Apple Silicon. Homebrew uses the same official package as the manual download. In-app automatic updates are enabled by default. You can also run `brew update && brew upgrade --cask --greedy niall-young/asky/asky` to update, or `brew uninstall --cask niall-young/asky/asky` to uninstall the app. Uninstalling preserves personal data and settings.

#### Download & Install
- Download the latest DMG release from [GitHub Releases](https://github.com/Niall-Young/Asky/releases) or the [Official Website](https://asky.niallyoung2002.workers.dev/) (macOS 14+, Apple Silicon).
- Open the DMG and drag `Asky.app` into Applications. The Agent runs natively in Swift; the app no longer bundles Node.js or Pi. The Orca and Lark plugin runners and the Text Tools launcher example use native Swift API v2 executables without Node; users supply the CLI environment. Legacy JavaScript plugins require local Node.js 22+.
- In-app automatic updates are enabled by default; configure in Settings › About Asky › Software Update.

#### Permissions & AI Configuration
- **Permissions**: Automatic pasting and window search require macOS **Accessibility** access. Calendar and Notes access require user authorization on first use.
- **Model Setup**: Go to Settings › Model Settings to configure your API Key or custom OpenAI-compatible endpoint. Keys are stored safely in the macOS Keychain.

---

### 🛠️ Development & Building

Current source targets macOS 14 with the same features and native background blur as macOS 15; macOS 26+ can use Liquid Glass. Settings use a native grouped form on 14 and retain custom cards on 15+. Testing on macOS 14/15 hardware is still pending. Official packages and the Homebrew Cask support macOS 14 starting with 0.2.10.

Launch at login reflects the actual macOS status. If approval is required, choose “Open Login Items Settings…” in Settings › General; the status refreshes when you return. Existing installations preserve the system choice and do not automatically re-enable a disabled login item.

#### Prerequisites
- Target runtime: macOS 14+ (Apple Silicon)
- Xcode 16+ / Swift 6.2+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

The app icon source is `App/Branding/AskyNative.icon`, edited with Icon Composer bundled with Xcode. After changes, synchronize the exported `AppIcon.appiconset`, `AskyLogo.imageset`, and PNG / ICNS compatibility assets in `App/Branding`.

#### Build & Run
Run from the repository root:

```sh
# 1. Generate Xcode project
xcodegen generate

# 2. Build and launch Debug app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Asky.app
# Open the AI window directly without sending a request
open -n build/DerivedData/Build/Products/Debug/Asky.app --args --show-agent
```

#### Running Tests
```sh
# Core test suites
(cd MCPBridge && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build)
(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
# Bubble conversation and waiting-state regression (build Debug first)
python3 App/Tests/run-agent-reply-regression.py --reply-activity-preview
python3 App/Tests/run-agent-reply-regression.py --reading-scroll
python3 App/Tests/run-agent-reply-regression.py --forms-preview --custom-preview
```

The launcher presentation diagnostic uses isolated data and records first and repeat presentation in separate Debug processes. Screen Recording access is required. Outputs stay in `build/`; the installed app and everyday data are untouched:

```sh
python3 App/Tests/run-launcher-presentation-diagnostic.py --output build/launcher-presentation/current
```

Recording requests 60 fps; inspect the output files and logs for delivered cadence. Testing a copied Debug bundle is not production update-installation verification. See the [development guide](docs/development.md) for coverage.

> [!NOTE]
> For UI automation regression scripts, Debug interactive preview arguments, and Developer ID code-signing and packaging, see the [Development and Release Guide](docs/development.md).

---

### 📂 Codebase & Docs

| Directory | Responsibility |
| :--- | :--- |
| `App/` | Native macOS user interface and interactions (SwiftUI & AppKit) |
| `Packages/KulaCore/` | Core business logic and unified system access through `ToolService` |
| `PluginSupport/` | Legacy JavaScript plugin shim; the native Agent lives in KulaCore AgentHost |
| `MCPBridge/` | Native Model Context Protocol bridge |

- [Docs Index](docs/README.md) · [Product Requirements (PRD)](docs/PRD.md) · [Architecture](docs/framework.md) · [Design System](docs/design-system.md) · [Plugins](docs/plugins.md) · [Privacy](PRIVACY.md)

---

### 📄 License

Distributed under the [MIT License](LICENSE). Third-party dependencies retain their respective licenses.

[中文](#中文) · [Back to top](#asky)
