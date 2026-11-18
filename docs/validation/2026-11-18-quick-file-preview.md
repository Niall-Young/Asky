# 快速搜索与剪贴板文件预览

2026-11-18 在 macOS 27.0.1、Xcode SDK 27.2 上验证。

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build
(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)
python3 App/Tests/run-launcher-window-regression.py --file-preview --system-keys --capture
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --image-gallery
```

- Debug 构建、KulaCore 测试与聊天图片栏解析回归通过。
- 原生回归用独立临时数据打开真实搜索和剪贴板界面，验证 PNG、旧版剪贴板 `.img` 原图和大写扩展名 `.MD`。浅色、深色截图核对了标题、列表、代码块、本地插图及等比图片。
- 系统按键测试在启用 macOS 输入法切换快捷键且已有辅助功能权限时进行。两处都能用 `Ctrl + 空格` 打开预览，输入法保持在当前选项。长按重复事件保留预览，再按一次或按 `Esc` 可返回来源窗口，原查询与选中项保留。
- 文件批次和普通文本文件不打开预览。更改剪贴板预览键后，新组合键可用；隐藏来源面板会关闭预览。
- 快捷键验收使用独立原生回归进程。旧版 macOS、发布版及辅助功能授权流程未做实机验收。

## 快速搜索的「更多」菜单

- Debug 构建和 KulaCore 测试通过。用 `python3 App/Tests/run-launcher-window-regression.py --file-preview --capture` 通过浅色与深色原生窗口回归。
- 确认图片和 Markdown 将「快速预览」列为首项，普通文本和名称以 `.md` 结尾的目录不显示该项。在菜单首项按回车打开原有预览，快捷键标签随设置更新。
- 额外的系统按键注入检查通过了启动器步骤，随后在剪贴板步骤出现失败。本次菜单入口通过常规原生窗口回归验收。

## 剪贴板历史的「更多」菜单

- Debug 构建和 KulaCore 测试通过。用 `python3 App/Tests/run-launcher-window-regression.py --file-preview --clipboard-only --capture` 通过浅色与深色剪贴板原生回归并核对截图。
- 图片和单个 Markdown 文件将「快速预览」列为首项，右侧随设置更新快捷键。普通文本、多文件记录和名称以 `.md` 结尾的目录不显示该项。
- 在首项按回车打开图片，点击首项打开 Markdown。原生回归还验证了预览快捷键的打开、关闭和重新绑定。
- 组合回归在启动器焦点步骤中断，本轮以剪贴板专项回归验收。
