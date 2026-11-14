# Asky 开发与发布 / Development and Releases

[中文](#中文) | [English](#english) · [README](../README.md)

<a id="中文"></a>
## 中文

### 回归检查

以下命令均从仓库根目录运行。先构建 MCP Bridge，再运行核心包测试：

```sh
(cd MCPBridge && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build)
(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
```

完成[README](../README.md) 中的 Debug 构建后，可运行原生回归检查。部分交互检查需要系统输入事件权限：

```sh
python3 App/Tests/run-launcher-window-regression.py
python3 App/Tests/run-launcher-window-regression.py --bottom-clearance
python3 App/Tests/run-launcher-window-regression.py --compact-results
python3 App/Tests/run-launcher-window-regression.py --result-motion
python3 App/Tests/run-launcher-window-regression.py --fixed-expanded
python3 App/Tests/run-launcher-window-regression.py --app-opening
python3 App/Tests/run-launcher-window-regression.py --first-presentation
python3 App/Tests/run-launcher-window-regression.py --shell-lifecycle
python3 App/Tests/run-launcher-window-regression.py --accessories
python3 App/Tests/run-launcher-window-regression.py --command-icons
python3 App/Tests/run-launcher-terminal-regression.py
python3 App/Tests/run-launcher-calculation-regression.py
python3 App/Tests/run-launcher-window-regression.py --ai-routing
python3 App/Tests/run-launcher-window-regression.py --system-app-names
python3 App/Tests/run-launcher-window-regression.py --alias-routing
python3 App/Tests/run-launcher-window-regression.py --bookmarks
python3 App/Tests/run-launcher-window-regression.py --plugins
python3 App/Tests/run-clipboard-regression.py
python3 App/Tests/run-clipboard-regression.py --pagination
python3 App/Tests/run-clipboard-regression.py --paste-target
python3 App/Tests/run-clipboard-regression.py --drag-paste-target
python3 App/Tests/run-clipboard-regression.py --drag-paste-target --list-drag --pinned-drag
python3 App/Tests/run-clipboard-regression.py --hover-delay
python3 App/Tests/run-clipboard-regression.py --hover-mouse
python3 App/Tests/run-clipboard-regression.py --settings-shortcut
python3 App/Tests/run-clipboard-regression.py --drag
python3 App/Tests/run-clipboard-regression.py --files
python3 App/Tests/run-clipboard-regression.py --chat-images
python3 App/Tests/run-clipboard-regression.py --drag-preview
python3 App/Tests/run-settings-regression.py
python3 App/Tests/run-settings-regression.py --conversation-retention
python3 App/Tests/run-settings-regression.py --permissions-only
python3 App/Tests/run-settings-regression.py --preview-legacy-material
python3 App/Tests/run-settings-regression.py --plugins-only -AppleLanguages "(en)"
python3 App/Tests/run-settings-regression.py --plugin-tabs -AppleLanguages "(zh-Hans)"
python3 App/Tests/run-settings-regression.py --plugin-tabs -AppleLanguages "(en)"
python3 App/Tests/check-localization.py
python3 App/Tests/run-application-language-regression.py -AppleLanguages "(en)"
python3 App/Tests/run-application-language-regression.py -AppleLanguages "(zh-Hans)"
python3 App/Tests/run-agent-reply-regression.py
python3 App/Tests/run-agent-reply-regression.py --reply-activity-preview
python3 App/Tests/run-agent-reply-regression.py --forms-preview --time-preview
python3 App/Tests/run-agent-reply-regression.py --forms-preview --components-preview
python3 App/Tests/run-agent-reply-regression.py --forms-preview --radio-preview
python3 App/Tests/run-application-termination-regression.py
```

Debug 主应用可用 `open -n build/DerivedData/Build/Products/Debug/Asky.app --args --test-clipboard` 打开固定的正式剪贴板面板，用于跨应用拖放验收；可通过 `ASKY_CLIPBOARD_TEST_QUERY` 环境变量筛选测试卡片。该模式只记录拖拽类型、数量及接受结果，不记录内容或路径。验证前退出其他 Asky 实例，尤其是 `/Applications/Asky.app` 的旧版本，避免快捷键竞争及误测旧面板。

使用 `open -n build/DerivedData/Build/Products/Debug/Asky.app --args --test-confirmations` 依次预览飞书插件、日历、信息和外部 MCP 的共用系统确认弹窗。每项确认或取消后进入下一项，随后预览插件安装、应用更新与错误提示，完成后退出；不启动 AI 或执行真实工具。

应用内确认和提示共用带 Asky 图标的原生系统弹窗。操作确认默认展示自然语言动作与关键内容，工具名和完整参数放在可展开的“操作详情”中；系统权限窗口与文件选择器保持系统样式。

AI 对话框发送按钮旁可切换全局审批模式，修改后对所有对话持续生效。默认“自动审批”：查询和明确要求的创建直接执行，修改、删除、发送等风险操作弹窗确认，AI 自行推断的写入只作为建议。“完全访问权限”下 AI 的所有工具调用直接执行、不再询问。该模式只影响 Asky 内的 AI 对话；启动器和外部 MCP 调用始终按原规则确认，数据来源开关和系统授权检查也照常生效。

剪贴板 `--drag-paste-target` 使用独立进程中拒绝原生拖放的编辑器，回读补粘贴结果，并检查 Esc 取消和非输入区域不改写剪贴板。`--chat-images` 检查图片与文件名混合载荷、临时图片文件、缩略图和原图再次复制。`--files` 检查文件监听、整组复制和真实鼠标文件拖放，并回读接收文件的内容；`--drag` 检查真实鼠标拖放与未固定面板关闭；`--drag-preview` 保留带测试卡片的未固定面板供人工拖放。`--external-drag` 使用单条 `AskyDragProbe` 测试文本，通过 `ASKY_CLIPBOARD_TARGET_BUNDLE` 激活指定的已运行应用，并按 `ASKY_CLIPBOARD_DROP_POINT=x,y`（Quartz 屏幕坐标）执行真实拖放；测试仅置入草稿，不发送消息，结果需在应用中回读并清理。设置 `ASKY_CLIPBOARD_DROP_POINT=x,y` 也可将 `--drag` 目标改为外部输入框，搭配 `ASKY_CLIPBOARD_DRAG_IMAGE=1` 拖第二张图片卡片；外部目标内容需另行回读确认。

启动器 `--bottom-clearance` 专项检查列表滚动、键盘首尾导航与最后一项的底部留白，覆盖亮暗模式；不运行系统事件投递与异步搜索时序检查。

并行构建时，启动器与设置回归脚本支持用 `ASKY_DERIVED_DATA` 指定独立的 DerivedData 目录，默认使用 `build/DerivedData`。启动器同时隔离回归产物；设置脚本兼容旧变量 `KULAHERE_DERIVED_DATA`。

原生输入框与快捷键的独立检查：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc App/Sources/LauncherSearchField.swift App/Sources/EditMenu.swift App/Tests/LauncherSearchFieldRegression.swift -o build/launcher-input-regression
build/launcher-input-regression
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc App/Sources/HotKey.swift App/Tests/HotKeyRegression.swift -o build/hotkey-regression
build/hotkey-regression
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library -swift-version 6 App/Sources/OutsideClickDismissal.swift App/Tests/OutsideClickDismissalRegression.swift -o build/outside-click-regression
build/outside-click-regression
```

检查结果按实际运行情况记录在 `docs/validation/`。自动化检查与真实系统权限、模型和界面验收分别记录。

### 启动器首帧诊断

先按 README 构建 Debug App，再运行：

```sh
python3 App/Tests/run-launcher-presentation-diagnostic.py --output build/launcher-presentation/current
```

默认浅色、深色各启动 20 个独立进程；每个进程展示、隐藏再展示一次。`--runs` 调整每种外观的次数，`--app` 指定 Debug App 路径。录制先于进程启动，固定录制屏幕并裁切启动器及其左下区域，请求 60 fps，不录音；ScreenCaptureKit 会省略未变化的帧，需结合 MP4 的实际时间戳和 `*-recording.log` 的最大帧间隔判断盲区，不能视为恒定 60 fps 的合成追踪。

脚本在启动前拒绝不含隔离入口的普通/Release App。诊断入口 `--diagnose-launcher --diagnostic-root <绝对路径>` 仅在 Debug 存在；脚本传入 `--diagnostic-screen` 固定显示器，`--diagnostic-dark` 选择深色。它调用真实启动器与玻璃代码，但跳过常规服务初始化，使用空搜索源、临时数据、不启动 AI、更新或申请搜索权限，并忽略失焦关闭以防录制期间其他窗口打断。日志只含单调时钟、事件、窗口类型、标识和几何，不记录搜索词或窗口标题。录像会包含裁切区域的桌面内容，仅供本地检查。

前半组使用原构建，后半组使用复制到新路径的同一 Debug bundle；这验证独立进程与路径替换，不代表正式更新器、签名安装或真实数据迁移。退出码和窗口快照不能证明不存在早期闪块，必须查看连续帧。`--shell-lifecycle` 检查 100 次会话的外壳/输入身份、结果滚动视图卸载、取消、跨屏与模拟组合输入；物理中文输入法仍需单独检查。

### 本地化资源

App 界面资源位于 `App/Resources`；核心错误、工具说明及确定性提醒通过 `Contracts/CoreLocalization` 读取 SwiftPM 资源包 `KulaCore_Contracts.bundle` 中的 `Core.strings`。两个语言必须同步添加键，并保留格式参数与用户内容。固定错误不要直接拼接中文字符串。

原生 App 按启动时选中的语言读取资源；设置改动仍在重启后生效。独立 MCP Bridge 使用自己的启动语言或系统语言。Xcode 与 SwiftPM 自动打包共享资源，原生回归脚本通过 `regression_resources.py` 复制相同资源包。测试不得用中文内容来判断流程是否结束。

确认请求的内部字段标记、输入别名、持久化字段和用户内容保持原有契约，展示层负责翻译。第三方原始错误作为参数保留。

### 发布打包

版本变更与发布结果见 [0.1.0 发布记录](validation/2026-10-14-release-0.1.0.md)。以下路径为该版本的打包示例；发布新版本时替换版本号、构建号及目录。

先运行本指南中的测试，使用 `xcodebuild` 的 `Release` 配置构建到 `build/Release010DerivedData`。Agent 随原生应用编译，不再准备 Node 或 npm 依赖目录。提交源码后，在干净工作区运行：

```sh
python3 scripts/package-release.py --version 0.1.0 --build 24 \
  --derived-data build/Release010DerivedData
```

Debug、Release 构建与打包默认使用 `Developer ID Application: Niall Young (V8GVW783CK)`，Team ID 为 `V8GVW783CK`。需在钥匙串中安装证书及私钥；跨机器应安全迁移同一身份，私钥备份不得进入仓库或安装包。`scripts/signing.py` 的本机重签名默认也使用同一正式身份。从旧自签名版本切换到正式签名后，系统权限可能需要重新授权；签名检查不能替代真实权限验收。

首次公证前，在本机终端执行下列命令，并在隐藏输入提示中输入 Apple App 专用密码（不是 Apple 账户登录密码）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun notarytool store-credentials Asky \
  --apple-id YOUR_APPLE_ID --team-id V8GVW783CK
```

凭据保存在钥匙串，不写入源码。随后使用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 scripts/package-release.py ...` 执行上面的打包参数。可通过 `--signing-identity` 指定其他 Developer ID Application 证书名称或 SHA-1，通过 `--notary-profile` 指定其他钥匙串配置。缺少有效证书、私钥或公证凭据时直接失败；发布不再接受自签名或 ad-hoc 身份。

脚本先检查应用包不含旧 Node / Pi 资源，为原生应用和 MCP Bridge 签名并附安全时间戳，再提交应用 ZIP 公证、确认 Accepted、为应用装订并验证票据，然后生成更新 ZIP。DMG 完成 Finder 布局后单独签名、公证、装订并验证；两种产物的 SHA-256 都在最终内容完成后计算。公证回执与详细日志保存在 `build/release-<version>-{app,dmg}-notarization*.json`。输出位于 `build/releases/<version>/`；不执行 GitHub 发布或本机安装，每次打包需要新的 staging 目录。DMG 使用 `scripts/dmg/background.tiff` 的 Retina 背景与 `scripts/dmg/layout.applescript` 的固定图标布局，终端需获准自动化 Finder。

### Homebrew 安装源

本仓库同时作为自定义 tap，通过 README 中带显式仓库 URL 的 `brew tap` 命令添加；不依赖独立的 `homebrew-asky` 仓库。`Casks/asky.rb` 固定正式 DMG 的版本和 SHA-256。每次 GitHub Release 公开后，核对远端 DMG 的 SHA-256 与对应 `.sha256` 文件，再更新这两个字段并提交、推送；不要使用 `sha256 :no_check` 或指向可变的 latest 下载地址。发布前运行：

```sh
brew style Casks/asky.rb
brew audit --cask niall-young/asky/asky
```

`audit` 使用已添加的 tap 中的文件；验证未推送改动时，先将待验证版本放入独立的本地 tap。应用有内置更新，因此 Cask 声明 `auto_updates true`，主动通过 brew 升级需使用 `--greedy`。普通卸载仅移除应用，不清除用户数据。

### 短信日程配置回归

先按 README 完成 Debug 构建，再执行 `python3 App/Tests/run-calendar-editor-regression.py`。默认检查标题、时间、日历选择和字段传递；`--preview` 打开实际分组弹窗，使用示例日历且不写入真实日程；另加 `--preview-error` 模拟首次冲突，检查窗口保留输入并允许重试。日期行展开月历与数字小时、分钟下拉框，创建直接经 ToolService 保存，不再交接 ICS 或打开日历应用。

### 通知预览

Debug 参数 `--test-notification` 现在是 `--test-banner` 的兼容别名，均预览 Asky 自绘卡片，不再发送系统通知或请求通知权限；Release 不响应这两个参数。

Debug 版本可用 `open -n build/DerivedData/Build/Products/Debug/Asky.app --args --test-banner`，或菜单栏 › 预览提醒卡片，查看 Asky 自绘的提醒卡片：右上角浮层，不抢焦点。新卡片以 8pt 间隔向下排列，约 4 秒后折叠成层叠，只显示最前一张；点击露出的边缘可重新展开，逐张处理。悬停时暂停折叠和自动消失。它不进通知中心，也不创建日程。

---

<a id="english"></a>
## English

### Regression Checks

Run these commands from the repository root. Build the MCP Bridge before running core package tests:

```sh
(cd MCPBridge && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build)
(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
```

After the Debug build in [README](../README.md), run native regression checks. Some interaction checks require system input event permissions:

```sh
python3 App/Tests/run-launcher-window-regression.py
python3 App/Tests/run-launcher-window-regression.py --bottom-clearance
python3 App/Tests/run-launcher-window-regression.py --compact-results
python3 App/Tests/run-launcher-window-regression.py --result-motion
python3 App/Tests/run-launcher-window-regression.py --fixed-expanded
python3 App/Tests/run-launcher-window-regression.py --app-opening
python3 App/Tests/run-launcher-window-regression.py --first-presentation
python3 App/Tests/run-launcher-window-regression.py --shell-lifecycle
python3 App/Tests/run-launcher-window-regression.py --accessories
python3 App/Tests/run-launcher-window-regression.py --command-icons
python3 App/Tests/run-launcher-terminal-regression.py
python3 App/Tests/run-launcher-calculation-regression.py
python3 App/Tests/run-launcher-window-regression.py --ai-routing
python3 App/Tests/run-launcher-window-regression.py --system-app-names
python3 App/Tests/run-launcher-window-regression.py --alias-routing
python3 App/Tests/run-launcher-window-regression.py --bookmarks
python3 App/Tests/run-launcher-window-regression.py --plugins
python3 App/Tests/run-clipboard-regression.py
python3 App/Tests/run-clipboard-regression.py --pagination
python3 App/Tests/run-clipboard-regression.py --paste-target
python3 App/Tests/run-clipboard-regression.py --drag-paste-target
python3 App/Tests/run-clipboard-regression.py --drag-paste-target --list-drag --pinned-drag
python3 App/Tests/run-clipboard-regression.py --hover-delay
python3 App/Tests/run-clipboard-regression.py --hover-mouse
python3 App/Tests/run-clipboard-regression.py --settings-shortcut
python3 App/Tests/run-clipboard-regression.py --drag
python3 App/Tests/run-clipboard-regression.py --files
python3 App/Tests/run-clipboard-regression.py --chat-images
python3 App/Tests/run-clipboard-regression.py --drag-preview
python3 App/Tests/run-settings-regression.py
python3 App/Tests/run-settings-regression.py --conversation-retention
python3 App/Tests/run-settings-regression.py --permissions-only
python3 App/Tests/run-settings-regression.py --preview-legacy-material
python3 App/Tests/run-settings-regression.py --plugins-only -AppleLanguages "(en)"
python3 App/Tests/run-settings-regression.py --plugin-tabs -AppleLanguages "(zh-Hans)"
python3 App/Tests/run-settings-regression.py --plugin-tabs -AppleLanguages "(en)"
python3 App/Tests/check-localization.py
python3 App/Tests/run-application-language-regression.py -AppleLanguages "(en)"
python3 App/Tests/run-application-language-regression.py -AppleLanguages "(zh-Hans)"
python3 App/Tests/run-agent-reply-regression.py
python3 App/Tests/run-agent-reply-regression.py --reply-activity-preview
python3 App/Tests/run-agent-reply-regression.py --forms-preview --time-preview
python3 App/Tests/run-agent-reply-regression.py --forms-preview --components-preview
python3 App/Tests/run-agent-reply-regression.py --forms-preview --radio-preview
python3 App/Tests/run-application-termination-regression.py
```

In the Debug app, `open -n build/DerivedData/Build/Products/Debug/Asky.app --args --test-clipboard` opens the pinned production clipboard panel for cross-app drag acceptance testing. Set `ASKY_CLIPBOARD_TEST_QUERY` to filter test cards. This mode logs only the dragged kind, item count, and acceptance result, with no contents or paths. Quit other Asky instances first, especially older copies of `/Applications/Asky.app`, to avoid hotkey conflicts and testing the wrong panel.

Use `open -n build/DerivedData/Build/Products/Debug/Asky.app --args --test-confirmations` to preview the shared system confirmation dialog for the Lark plugin, Calendar, Messages, and external MCP in sequence. Approving or cancelling advances to the next preview, followed by plugin installation, app update, and error alerts. The app exits after the last one. This mode does not start AI or execute real tools.

App-owned confirmations and alerts share native system dialogs with the Asky icon. Operation confirmations show readable actions and key content, with tool names and full arguments in expandable operation details. System permission dialogs and file pickers keep their system presentation.

Clipboard `--chat-images` checks mixed image/filename payloads, temporary image files, thumbnails, and copying the original image again. `--files` checks file monitoring, multi-file copying, real mouse dragging, and received file contents; `--drag` checks a real mouse drop and unpinned panel dismissal; `--drag-preview` keeps an unpinned panel with test cards open for manual drops. Set `ASKY_CLIPBOARD_DROP_POINT=x,y` to target an external input at screen coordinates, and add `ASKY_CLIPBOARD_DRAG_IMAGE=1` to drag the second image card. Read back external destination contents separately to confirm the result.

Launcher `--bottom-clearance` checks list scrolling, keyboard navigation at both ends, and the final row's bottom clearance in light and dark modes. It skips system event delivery and asynchronous search timing checks.

For concurrent builds, the launcher and settings regression scripts accept `ASKY_DERIVED_DATA` to select an isolated DerivedData directory, defaulting to `build/DerivedData`. Launcher regression artifacts are isolated as well; the settings script also supports the legacy `KULAHERE_DERIVED_DATA` variable.

Standalone checks for native input fields and hotkeys:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc App/Sources/LauncherSearchField.swift App/Sources/EditMenu.swift App/Tests/LauncherSearchFieldRegression.swift -o build/launcher-input-regression
build/launcher-input-regression
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc App/Sources/HotKey.swift App/Tests/HotKeyRegression.swift -o build/hotkey-regression
build/hotkey-regression
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -parse-as-library -swift-version 6 App/Sources/OutsideClickDismissal.swift App/Tests/OutsideClickDismissalRegression.swift -o build/outside-click-regression
build/outside-click-regression
```

Record only checks actually executed in `docs/validation/`. Track automated checks separately from acceptance testing of real system permissions, models, and interfaces.

### Launcher First-Presentation Diagnostic

Build the Debug app with the README command, then run:

```sh
python3 App/Tests/run-launcher-presentation-diagnostic.py --output build/launcher-presentation/current
```

By default, 20 independent processes run in each of light and dark appearance. Each shows, hides, and reopens the launcher. `--runs` changes the count per appearance; `--app` selects a Debug app. Recording starts before launch, pins the display, crops the launcher and its lower-left surround, requests 60 fps, and captures no audio. ScreenCaptureKit may omit unchanged frames: inspect the MP4 timestamps and maximum frame gap in `*-recording.log` rather than treating this as constant 60 fps compositor tracing.

The script rejects ordinary/Release apps without the isolated entry before launching them. The `--diagnose-launcher --diagnostic-root <absolute-path>` entry exists only in Debug. The runner passes `--diagnostic-screen` to pin the display and `--diagnostic-dark` for dark appearance. It exercises the actual launcher and native glass while skipping normal service initialization, using empty search providers and temporary data. It starts no AI or updater, requests no search permissions, and ignores blur dismissal so other windows cannot interrupt recording. Logs contain monotonic time, events, window types, identifiers and geometry, without queries or window titles. Videos contain desktop content within the crop and are intended for local inspection.

The first half uses the original build; the second half uses the same Debug bundle copied to a new path. This covers separate processes and path replacement, not the production updater, signed installation, or real-data migration. Exit codes and window snapshots cannot rule out early flashes; inspect consecutive frames. `--shell-lifecycle` covers 100 sessions of shell/input identity, result scroll-view unloading, cancellation, screens, and simulated marked text; physical IME input needs separate verification.

### Localization Resources

App interface resources live in `App/Resources`. Core errors, tool descriptions and deterministic reminders use `Contracts/CoreLocalization` to read `Core.strings` from the SwiftPM `KulaCore_Contracts.bundle`. Add keys in both languages, preserving format arguments and user content. Do not concatenate fixed Chinese error text directly.

The native app uses the language selected at launch; changes in Settings still take effect after restarting. The standalone MCP Bridge uses its launch or system language. Xcode and SwiftPM package the shared resources automatically, and native regression scripts copy the same bundle through `regression_resources.py`. Tests must not use Chinese wording to decide when a flow has finished.

Internal confirmation field markers, input aliases, persisted fields and user content retain their existing contracts; the presentation layer translates them. Raw third-party errors remain format arguments.

### Release Packaging

See the [0.1.0 release record](validation/2026-10-14-release-0.1.0.md) for changes and results. The paths below are examples for that version; replace the version, build number, and directories for a new release.

Run the tests in this guide and build with the `Release` configuration of `xcodebuild` into `build/Release010DerivedData`. The Agent is compiled into the native app; no Node distribution or npm dependency directory is required. Commit the source changes, then run from a clean working tree:

```sh
python3 scripts/package-release.py --version 0.1.0 --build 24 \
  --derived-data build/Release010DerivedData
```

Debug and Release builds and packages default to `Developer ID Application: Niall Young (V8GVW783CK)`, with Team ID `V8GVW783CK`. Install both the certificate and private key in Keychain. Securely migrate the same identity between build machines; keep private-key backups out of the repository and installers. Local re-signing through `scripts/signing.py` also defaults to the same identity. Switching from self-signed builds to Developer ID may require granting system permissions again. Signature checks do not replace real permission acceptance tests.

Before the first notarization, run this command in a local terminal and enter an Apple app-specific password at the hidden prompt (not your Apple Account login password):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun notarytool store-credentials Asky \
  --apple-id YOUR_APPLE_ID --team-id V8GVW783CK
```

Credentials stay in Keychain, outside source control. Then run the packaging arguments above with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 scripts/package-release.py ...`. Override the Developer ID Application certificate name or SHA-1 with `--signing-identity`, and the Keychain profile with `--notary-profile`. Missing certificates, private keys, or notarization credentials fail immediately. Release packaging no longer accepts self-signed or ad-hoc identities.

The script rejects retired Node / Pi resources and signs the native app and MCP Bridge with secure timestamps. It submits an app ZIP for notarization, requires Accepted, staples and validates the app ticket, and only then creates the updater ZIP. After the Finder layout, it separately signs, notarizes, staples, and validates the DMG. Both SHA-256 checksums are computed from the final artifacts. Receipts and detailed logs are saved as `build/release-<version>-{app,dmg}-notarization*.json`. Outputs go to `build/releases/<version>/`. The script does not publish to GitHub or install locally, and each run needs a new staging directory. DMGs use the Retina background in `scripts/dmg/background.tiff` and fixed icon layout in `scripts/dmg/layout.applescript`; allow terminal automation of Finder.

### Homebrew Tap

This repository also serves as a custom tap, added with the explicit repository URL in the README's `brew tap` command; no separate `homebrew-asky` repository is required. `Casks/asky.rb` pins the official DMG version and SHA-256. After each GitHub Release becomes public, verify the remote DMG against its `.sha256` file, then update both fields, commit, and push. Do not use `sha256 :no_check` or a mutable latest download URL. Before publishing, run:

```sh
brew style Casks/asky.rb
brew audit --cask niall-young/asky/asky
```

`audit` reads the file in the installed tap. To validate unpublished changes, first place the candidate in a separate local tap. Since the app has a built-in updater, the cask declares `auto_updates true`; explicit brew upgrades require `--greedy`. Normal uninstall removes the app and preserves user data.

### Message Calendar Editor Regression

After the README Debug build, run `python3 App/Tests/run-calendar-editor-regression.py` to check title, date, calendar selection, and field forwarding. Add `--preview` to open the actual grouped editor with sample calendars and no real event writes; also add `--preview-error` to simulate an initial conflict and check editing and retrying. The date row opens a calendar with numeric hour and minute menus. Creation saves through ToolService without ICS handoff or launching Calendar.

### Notification Preview

In Debug, `--test-notification` is now a compatibility alias for `--test-banner`. Both preview Asky’s own cards without sending system notifications or requesting notification permission. Release ignores both arguments.

In Debug, run `open -n build/DerivedData/Build/Products/Debug/Asky.app --args --test-banner`, or use menu bar › 预览提醒卡片, to preview Asky’s self-drawn reminder cards: top-right floating panels that never take focus. New cards line up with 8 pt gaps, then fold into a layered stack after about 4 seconds so only the front card shows; click the peeking edges to unfold and handle them one by one. Hovering pauses folding and auto-dismiss. They do not appear in Notification Center and create no calendar items.

`--drag-paste-target` uses a separate-process editor that rejects native drops, reads back the pasted result, and checks that Escape cancellation and non-input drops leave the clipboard unchanged.

`--external-drag` uses a single `AskyDragProbe` record. Set `ASKY_CLIPBOARD_TARGET_BUNDLE` to an already running app and `ASKY_CLIPBOARD_DROP_POINT=x,y` to the editor’s Quartz screen coordinates. It only inserts a draft; read back and remove that text in the destination before claiming success.

拖放回归的 `--list-drag` 使用左侧列表条目作为源；`--pinned-drag` 额外检查固定窗口补粘贴后仍显示且不持有键盘焦点。真实应用验收应包括空输入框，不能只用被图片或长文本撑高的编辑器。

For drag regressions, `--list-drag` uses a left-hand list row; `--pinned-drag` additionally checks that the retained panel stays visible without keeping keyboard focus. Live acceptance must include an empty composer, rather than only editors expanded by an image or long draft.
