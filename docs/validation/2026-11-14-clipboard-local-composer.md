# 剪贴板向应用内 AI 输入框粘贴

## 原因与修复

`ClipboardPasteTarget.capture()` 原先仅接受外部进程，明确排除 Asky 自身。AI 输入框拥有焦点时无法成为历史面板的直接粘贴目标。

现在在历史面板取得焦点前，经 ToolService 捕获本进程的可编辑 `NSTextView` 与所属窗口的弱引用。粘贴恢复原窗口和编辑器，调用编辑器自身的 `paste`，沿用 Composer 的草稿绑定及附件处理；无需为应用内粘贴申请辅助功能权限。非输入焦点、已隐藏或释放的窗口、已不可编辑的输入框，以及复制后已变化的剪贴板不执行粘贴。外部应用沿用原有辅助功能路径。

## 已执行检查

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `codesign --verify --deep --strict build/DerivedData/Build/Products/Debug/Asky.app`：通过。

- 原生应用内回归 `--local-paste-target`：通过并复跑通过。使用实际 Composer 输入框和历史面板，验证光标处插入、草稿绑定、选区替换、保持面板开启、图片附件回调、剪贴板变化、只读编辑器与隐藏目标。
- 外部应用回归 `--paste-target`：通过。验证外部光标插入、保持面板开启及状态保留、仅复制、无输入焦点及剪贴板变化；旧夹具直接调用输入框 delegate 会读取过期的 `NSApp.currentEvent`，现改为投递实际 Return 事件。

回归编译显式设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 与 `SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`，避免 Command Line Tools SDK 与 Xcode 构建产物不匹配。工作区并行工作修改了共享产物和 App 源码，因此最终使用 `build/clipboard-local-products`、`build/clipboard-local-sources` 快照和 `build/clipboard-local-runner.py` 运行同一回归，编译启用 whole-module-optimization；这些快照、日志与测试应用均由现有 `build/` 规则忽略。

## 范围

测试使用隔离数据和实际 `ComposerTextEditor` / `ClipboardController` 组件，不向模型发送请求。图片检查验证 Composer 附件回调被调用，不代表模型端已接收图片。未替换 `/Applications/Asky.app`，未发布新版本。

README 已记载 Return 粘贴及 Command Return 仅复制；本次修复恢复既有行为，README 无需追加用法。AGENTS.md 的工具边界和验证要求未发生变化。
