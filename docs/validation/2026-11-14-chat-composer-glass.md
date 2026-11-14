# 对话窗口与玻璃输入框

## 调整

- AI 窗口独立固定宽 560 pt，初始高 560 pt、最小高 480 pt，保持原纵向调整行为。
- 输入区普通圆角从 24 缩至 16 pt；空态文字区最小 28 pt、行间距 8 pt、顶部 10 / 底部 8 pt，空态输入区总高 82 pt（原 116 pt）。
- 文本横向内距 12 pt，操作行横向内距 8 pt；外距仍为 12 pt。附件卡片保留删除按钮所需的顶部空间。
- 输入区复用 NativeGlassBackground 的 Clear 玻璃，以 35% 不透明度单独合成玻璃层以减弱边缘高光和折射，文字与按钮保持原不透明度，移除 kInput 填充；保留辅助功能及旧系统材质回退。附件按钮使用无底板的加号图标，与发送按钮同为 28 × 28 pt 点击区域，发送按钮保留圆形底板。

## 已运行

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- 首次直接运行 `swift test` 因默认工具链缺少 Testing 模块失败；按项目规范指定 Xcode 后重跑。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，323 个测试。

- 最终 Clear 玻璃、28 pt 按钮及柔化玻璃高光版本再次执行 Debug 构建与 KulaCore 测试：通过。

## 原生窗口检查

- 既有 `run-agent-reply-regression.py --preview` 首次编译时遇到共享构建目录中的 MCPLink.o 被并发改写；复制产物至独立的 `build/ChatStyleDerivedData` 后重试。
- 既有预览入口随后在历史会话检查 `AgentReplyRegression.swift:414` 的前置断言处退出，未进入 UI；本次没有修改或将该回归记为通过。
- 使用 `build/ChatStylePreview.swift` 临时启动器加载真实 AgentWindowController、AgentView、ComposerTextEditor，使用临时 AppModel 数据目录，不发送模型请求。
- 通过 Orca accessibility 与窗口截图确认实际窗体 560 × 560 pt；空态输入区 82 pt 高，28 pt 附件与发送按钮布局尺寸一致，Clear 玻璃与 16 pt 普通圆角正常显示。
- 初版窗口填入单行文字，发送按钮由禁用转为可用；填入 10 行文字后文字区域自增高并出现滚动条，操作行完整保留；清空后恢复紧凑高度。
- 初版窗口使用用户提供的 PNG 作为附件检查缩略图状态，图片与输入区、底部操作行无重叠。
- 截图保存在忽略目录 `build/chat-style-validation/`（初版 empty、long、attachment，以及最终柔化 Clear 玻璃 empty-final 截图）；预览包也在 `build/` 下，未加入版本控制。
- 本次未验证旧系统、降低透明度、增强对比度、真实模型发送或已安装正式包；原生材质回退继续使用已有组件。

## 文档与作用域

- README 中英文同步窗口宽度、输入区圆角和按钮尺寸；设计系统同步当前指标。
- AGENTS.md 保持不变：本次沿用已有原生玻璃、构建和系统调用边界，无新增持久开发约束。
- 工作区已有运行时迁移与来源预览改动保留；本次不发布或安装正式包。
