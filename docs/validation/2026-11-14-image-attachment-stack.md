# 对话图片附件堆叠

- 对话消息的两张及以上图片采用 80 pt 卡片，收起时最多露出三张，超过三张显示总数；悬停展开，离开收起。展开区保持 100 pt 高，超过可用宽度时横向滚动。
- 键盘聚焦后 Return / 空格切换展开，Esc 收起，失焦清除键盘展开状态。系统减少动态效果关闭弹簧动画。
- 单张图片、文件附件及输入区不变。混合附件的图片与文件分别呈现。

## 已执行

- `xcodegen generate` 成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build` 成功。
- 在 `Packages/KulaCore` 运行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`，退出码 0；13 组运行共 331 项测试通过。
- 新构建二进制通过 `--test-image-attachments <image-path>` 在隔离的原生窗口显示三张与六张图片。同一张参考截图重复作为测试素材，未接入对话数据或发起模型请求。
- 原生窗口视觉确认默认堆叠、六张数量标记、Return 展开、Esc 收起；展开时多图内容超出可视区，未改变上下行位置。
- 临时副本位于 `/tmp/AskyAttachmentPreview.app`，使用独立 bundle ID，避免误验旧进程。

## 验证限制

- 当前 computer-use 没有独立的指针移动 API，drag 未触发可观察的 hover 切换。纯悬停移入/移出、触控板横向滚动、暗色和系统减少动态效果仍需手工检查，未记为通过。
- 未替换已运行的主应用；未在真实会话中发送附件。单张及混合附件仅完成代码检查。
- 工作区开始时已有其他对话与工具展示改动；构建和全量测试针对当前合并工作区执行。

README: updated — 中英同步图片堆叠与键盘操作。

AGENTS.md: unchanged — 沿用既有 App、ToolService 和构建边界，没有新增长期工程约束。
