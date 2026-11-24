# AI 默认快捷键调整验证

- AI 空白新对话默认快捷键改为 `Control + Command + 空格`（`⌃⌘ Space`，`kVK_Space` + `controlKey | cmdKey`）。
- 启动器保持 `Option + Space`（`⌥ Space`），剪贴板历史保持 `Control + Shift + C`（`⌃⇧ C`）。
- 新建配置、旧配置缺少 AI 快捷键字段及设置中的“恢复默认”使用新值；已保存的快捷键保持不变。
- `README.md` 中英文快捷键表已同步更新。

## 实际运行的检查

- `(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)`：通过（83 个 Swift Testing 用例与 XCTest 全部通过）。
- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`：`BUILD SUCCEEDED`。
- `python3 App/Tests/run-settings-regression.py --local-shortcuts`：通过，验证 `SettingsPreferences` 缺省解码得到 `kVK_Space`、`controlKey | cmdKey`、`⌃⌘ Space` 及菜单栏 `menuKeyEquivalent == " "`、`modifierFlags == [.control, .command]`，并检查生成的浅色/深色设置窗口快照（`build/shortcut-edit-light.png`、`build/shortcut-edit-dark.png`），确认“打开 AI 对话”显示 `⌃⌘ Space`。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc App/Sources/HotKey.swift App/Tests/HotKeyRegression.swift -o build/hotkey-regression && build/hotkey-regression`：通过。

## 验证边界

- 未在实际运行的 Asky 窗口中验证 `⌃⌘ Space` 全局快捷键触发及与 macOS 系统“表情符号与符号”快捷键的占用情况。
- `python3 App/Tests/run-settings-regression.py` 因工作区并发编辑其他无关源文件在编译阶段中断，未计为通过。

## 文档维护

- `README.md`：updated，同步中英文“常用入口 / Common Shortcuts”中的 AI 默认快捷键。
- `AGENTS.md`：unchanged，本次不改变架构边界、开发命令或持久协作规范。
