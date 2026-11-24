# 设置页更多操作图标的明暗配色

在独立的临时数据目录中添加 Figma 别名 `fig`，用原生 `SettingsWindow` 显示别名页。修复前，暗色窗口中三点图标的中心像素为 RGB(19, 25, 33)，接近素材原色。

修复后，在同一窗口依次切换暗色、浅色和暗色，用 `screencapture -l` 截图。暗色下图标中心像素为 RGB(169, 170, 170)，周围背景为 RGB(54, 55, 55)。浅色下中心像素为 RGB(80, 81, 82)，周围背景为 RGB(169, 169, 169)。已目视检查两张别名行截图。

`xcodegen generate`、Asky Debug 的 `xcodebuild` 构建及 KulaCore 的 `swift test` 均通过。
