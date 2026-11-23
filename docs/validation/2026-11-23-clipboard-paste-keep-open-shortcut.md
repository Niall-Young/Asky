# 剪贴板“粘贴并保持窗口开启”快捷键

## 改动摘要

- 在 `LocalShortcutAction` 中新增可配置的 `.clipboardPasteKeepingOpen`（作用域 `clipboard`），默认快捷键为 `⌥ ↵`（`kVK_Return` + `optionKey`，兼容小键盘回车）。
- 剪贴板“更多”菜单中的“粘贴并保持窗口开启”行显示当前配置的快捷键标签（`LauncherActionKeyCap`），在剪贴板窗口中按下该快捷键且存在可用输入目标时直接执行粘贴并保持窗口开启。
- 在“设置 › 触发快捷键 › 剪贴板历史”中新增“粘贴并保持窗口开启”的快捷键录制与恢复默认行，并补齐中英文 `Localizable.strings` 文案。
- 同步更新 `ClipboardRegression.swift` 与 `LocalShortcutsRegression.swift` 中过期的 `ComposerTextEditor` 初始化参数，并补充新快捷键的回归断言。

## 已执行验证

1. `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build` — 通过（`BUILD SUCCEEDED`）。
2. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` — 通过（全部套件通过，0 失败）。
3. `python3 App/Tests/run-settings-regression.py --local-shortcuts` — 通过（验证默认 `⌥ ↵` 映射、改绑后旧快捷键失效、冲突校验与持久化）。
4. `python3 App/Tests/run-clipboard-regression.py --paste-target` — 通过（验证跨进程外部输入框下按下 `⌥ ↵` 在光标处粘贴且保持未固定剪贴板窗口开启、位置/搜索词/选中项不变）。
5. 已核对新构建原生窗口截图 `build/clipboard-keep-open-menu.png`：菜单中“粘贴并保持窗口开启”右侧正确渲染 `⌥ ↵` 键帽，与“复制到剪贴板 `⌘ ↵`”、“删除记录 `⌘ ⌫`”对齐一致。
