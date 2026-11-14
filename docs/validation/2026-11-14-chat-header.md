# 对话顶部简化

## 改动

- 标题从居中 18 pt 改为左对齐 13 pt / 500，长标题单行尾部截断
- 顶部从 56 pt 收紧为 48 pt，移除正文上方分割线
- 常驻新对话与更多入口；历史、置顶、设置、关闭收进原生菜单
- 顶部按钮使用 16 pt 图标与 28 pt 点击区域，无常驻玻璃圆底板；置顶时标题旁显示状态图标
- 历史页保留返回按钮与搜索框，沿用已有快捷键配置和窗口拖动实现

## 实际检查

- `xcodegen generate` 成功
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build` 成功
- 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`，331 项 Swift Testing 测试通过
- 使用隔离临时数据和真实 `AgentWindowController` / `AgentView` 渲染 560 × 560 pt 窗口，检查长标题、浅色和深色截图；截图位于本地忽略目录 `build/chat-header-task/header-light.png` 与 `header-dark.png`
- 预览编译首次遇到共享 `Resources.o` 被并行构建修改，复制对象文件到独立目录后预览编译与截图成功
- UI 自动化无法取得预览进程（`procNotFound`），未实测菜单点击、历史返回、置顶、关闭、快捷键和拖动；不将截图或构建视为交互验收
- 未替换已安装的应用，未发布

## 文档与范围

- README 中英文同步顶部布局与入口位置；设计系统同步当前顶部规范
- AGENTS.md 无需更新：没有新的构建命令、架构边界或项目级约束
- 构建日志、临时预览与截图复用现有 `build/` 忽略规则
