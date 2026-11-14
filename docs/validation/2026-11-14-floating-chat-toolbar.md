# 对话顶部浮动工具栏

## 最终行为

- 移除顶部会话标题，保留向下渐隐的原生材质背景；正文与历史列表为浮动工具栏预留 64 pt 首屏空间，滚动后可从其下方经过
- 左侧为 36 × 36 pt 历史按钮，按用户要求使用双横线菜单图标；历史页切换为返回箭头
- 右侧为 108 × 36 pt 连体按钮组：新对话、置顶、电源符号关闭；移除更多菜单及全部内部竖分割线
- 两侧复用输入框的 Clear 玻璃与 35% 玻璃背景强度，图标保持 18 pt、不降低不透明度
- 按钮使用原生 NSButton，保留既有快捷键、原生可访问名称与禁用状态；关闭只调用既有窗口关闭动作
- 双横线图标的源 SVG、模板资产与共享图标映射一并维护；电源图标复用已有 MingCute 资产
- Debug 支持 `--show-agent` 直接显示 AI 窗口，不发送模型请求，避免 UI 检查依赖全局热键

## 实际验证

- `xcodegen generate` 成功
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build` 成功
- 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`，331 项 Swift Testing 测试通过
- 从本次构建复制到本地忽略目录 `build/chat-header-glass/Asky.app`，以 `--show-agent` 运行；避免与其他任务使用主 Debug 路径的预览进程混淆
- 实际窗口截图确认左侧双横线、右侧新建/置顶/电源关闭三个图标，无标题、无竖线、无更多菜单；按钮组与输入框均为低强度 Clear 玻璃
- 同一轮原生 NSButton 实现已实际点击验证置顶切换、历史页进入和返回；最终关闭入口完成可访问树与外观检查，未额外点击关闭
- 最终版本未验证深色、macOS 14 回退、降低透明度、增强对比度与全部自定义快捷键；不据构建通过宣称这些检查通过
- 本次检查没有提交模型请求；没有发布或替换正式安装版

## 文档与范围

- README 中英文同步当前按钮和 Debug 打开命令；设计系统同步尺寸、玻璃强度、入口及双横线图标
- AGENTS.md 无需修改：沿用现有 AppKit、ToolService 和原生回归边界；可选 Debug 入口记录在已有开发文档入口中
- 预览程序、截图、日志与独立 Debug 副本复用 `build/` 忽略规则；其他任务的未提交改动保留
