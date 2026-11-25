# 全局液态玻璃确认与提示弹窗统一验证（2026-11-25）

## 变更范围

- [AppDialog.swift](../../Packages/KulaCore/Sources/ToolService/AppDialog.swift)：新增 `AppDialogPresenting` 协议与 `AppDialog.presenter` 注入点，使应用内所有经 `AppDialog.present` / `AppDialog.dismiss` 的提示与确认弹窗（含 `ToolService` 内部提示）统一走宿主液态玻璃呈现器，保留无宿主环境时的原生回退。
- [AppDialogPresenter.swift](../../App/Sources/AppDialogPresenter.swift)：新增共享液态玻璃弹窗卡片 `AppDialogCard`、间距令牌 `AppDialogLayout`、圆形玻璃关闭按钮 `AppDialogCloseButton`、胶囊操作按钮 `AppDialogActionButton` 与全局呈现器 `AppDialogPresenter`：
  - 放大并统一弹窗间距：标准宽 `360 pt`（长正文或三按钮自动放宽至 `400 pt`）、内距 `22 / 20 / 22 pt`、标题与正文间距 `14 pt`、正文与操作区间距 `26 pt`（无正文 `24 pt`）、双按钮间距 `12 pt`、正文行距 `5 pt`。
  - 有足够尺寸的可见所属窗口时，经窗口内容容器（兼容普通窗口与 `NSGlassEffectView`）挂载全窗居中覆盖层，支持弹簧入场与淡出退场、焦点暂停与恢复、`Esc` / 外部点击取消、`Return` 确认、`Tab` 焦点切换、箭头光标保护与窗口关闭清理；无可见窗口或窗口过小时自动以 Spotlight 式独立液态玻璃面板居中呈现。
- [ChatDeleteConfirmDialog.swift](../../App/Sources/ChatDeleteConfirmDialog.swift)：复用共享 `AppDialogCard` 与 `AppDialogLayout`，同步放大对话消息删除确认弹窗的留白与间距，保持既有辅助功能标识与交互语义不变。
- [AppDialogModifier.swift](../../App/Sources/AppDialogModifier.swift)、[AppModel.swift](../../App/Sources/AppModel.swift)、[AskyApp.swift](../../App/Sources/AskyApp.swift)、[SettingsExclusionList.swift](../../App/Sources/SettingsExclusionList.swift)、[ConfirmationCenter.swift](../../App/Sources/ConfirmationCenter.swift)、[AgentView.swift](../../App/Sources/AgentView.swift)、[LauncherView.swift](../../App/Sources/LauncherView.swift)、[ChatShareCard.swift](../../App/Sources/ChatShareCard.swift)：
  - 安装 `AppDialogPresenter` 为全局 `AppDialog.presenter`，`.appDialog` 支持 `destructive` 角色并绑定触发视图所在窗口。
  - 为「清空对话历史？」、「删除这一项？」、日程删除与遗忘记忆确认补齐红色破坏性操作样式；将 `AgentView` 中残留的系统 `.alert("原回复已不可用")` 统一迁至 `.appDialog`。
  - 在启动器失焦／外部点击与分享卡片自动关闭逻辑中识别活动中的 `AppDialogPresenter` 覆盖层，避免确认过程中误关宿主窗口。
- [SettingsRegression.swift](../../App/Tests/SettingsRegression.swift)、[QuitAskyRegression.swift](../../App/Tests/QuitAskyRegression.swift)、[ClipboardRegression.swift](../../App/Tests/ClipboardRegression.swift)、[ApplicationLanguageRegression.swift](../../App/Tests/ApplicationLanguageRegression.swift)：更新弹窗回归断言以验证液态玻璃覆盖层与真实按钮交互，并新增设置页「清空对话历史？」亮／暗模式居中与破坏性按钮回归。
- [design-system.md](../design-system.md)：更新 `Dialog 与 Alert` 规范。

## 实际执行与结果

1. `KulaCore` 单元测试：
   - 命令：`cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
   - 结果：通过（退出码 0）。
2. Xcode 工程生成与 Debug 构建：
   - 命令：`xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`
   - 结果：通过（`BUILD SUCCEEDED`，本次修改文件零新增告警）。
3. 对话消息删除确认弹窗回归与视觉核查：
   - 命令：`python3 App/Tests/run-agent-reply-regression.py --delete-dialog-preview`
   - 结果：通过（`Delete confirmation dialog regression passed in light and dark`）。
   - 核查实际窗口截图 `build/delete-dialog-light.png` 与 `build/delete-dialog-dark.png`：标题、正文、按钮与外边距留白明显更舒展，单行正文无孤字换行，亮暗双模式液态玻璃层次清晰。
4. 设置页「清空对话历史？」回归与视觉核查（中英文、亮暗模式）：
   - 命令：`python3 App/Tests/run-settings-regression.py --app-dialogs` 与 `python3 App/Tests/run-settings-regression.py --app-dialogs -AppleLanguages "(zh-Hans)"`
   - 结果：通过（`Settings clear-history Liquid Glass dialog regression passed in light and dark`）。
   - 核查实际窗口截图 `build/settings-clear-history-light.png` 与 `build/settings-clear-history-dark.png`：弹窗包含侧栏整体居中，中文副标题单行完整显示，取消与红色清空按钮等宽且对比清晰，取消保留历史、确认清空生效。
5. 启动器退出确认回归与视觉核查：
   - 命令：`python3 App/Tests/run-quit-asky-regression.py`
   - 结果：通过（`Quit Asky native regression passed`）。
   - 核查 `build/quit-asky-alert-NSAppearanceNameAqua.png` 与 `build/quit-asky-alert-NSAppearanceNameDarkAqua.png`：启动器内液态玻璃居中显示，单色主操作按钮在亮暗模式下清晰可读。
6. 剪贴板清空全部历史回归与视觉核查：
   - 命令：`python3 App/Tests/run-clipboard-regression.py --clear-all`
   - 结果：通过（`Clipboard Clear All: list confirmation, cancel, filtered >100 history, pinned items, assets and original files passed`）。
   - 核查 `build/clipboard-clear-all-list.png`：剪贴板面板内液态玻璃居中显示，红色「清空全部」与中性「取消」按钮比例与间距一致。
7. 覆盖层光标回归：
   - 命令：`python3 App/Tests/run-agent-reply-regression.py --action-cursor-preview`
   - 结果：通过（`Action cursor passed: overlays, selection actions, source tags/cards and return to text`）。
