# 设置输入框对比度修正

浅色设置输入框此前只有 12% 白色填充，边框额外淡化至 2% 黑色，与相邻原生按钮的明度差距明显。共享输入表面改为 45% 白色填充和 8% 黑色描边，覆盖文本、密码、搜索和下拉选择器；暗色填充、28pt 高度、圆角和编辑行为保持不变。

## 已执行验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- `python3 App/Tests/run-settings-regression.py --settings-chrome -AppleLanguages '(zh-Hans)'`：通过。运行工作区已有的设置回归，检查浅、深色下激活、失焦及恢复焦点时的控件高度和对齐，保存六张窗口截图。
- 实际查看新生成的 `build/settings-chrome-light-active.png` 和 `build/settings-chrome-dark-inactive.png`：浅色输入底色已接近右侧按钮，暗色保持原有层次。按钮仍使用原生玻璃，输入框为半透明填充，两者不承诺逐像素相同。

未安装或发布正式版；未在旧版 macOS 实机验证。日志、截图和构建产物沿用已有 `build/` 忽略规则。

README: unchanged，本次仅校正视觉对比度，不改变使用方式或构建流程。AGENTS.md: unchanged，无持久规则变化。设计系统同步输入表面的色值。任务开始前已有设置失焦修正、回归、README 和设计文档修改，本次提交仅包含输入框对比度相关代码、设计文档段落和本记录。
