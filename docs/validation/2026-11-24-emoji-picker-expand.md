# 聊天表情选择器支持点击展开全部 Emoji 验证（2026-11-24）

## 变更范围

- [ChatEmojiCatalog.swift](../../App/Sources/ChatEmojiCatalog.swift)：拆出 `ChatUserReactionCatalog`，保留原有 6 枚快捷表情（`👍` `❤️` `😂` `🎉` `😮` `🙏`），新增 8 个分类（笑脸和人物、手势与动作、爱心与符号、动物与自然、食物与饮品、活动与运动、旅行与地点、物品与工具）共 600+ 枚去重且全部通过 `AgentReactionReply.isEmoji` 校验的标准 Emoji。
- [ChatBubbleMenu.swift](../../App/Sources/ChatBubbleMenu.swift)：
  - 快捷表情胶囊右侧新增圆形 `+` 展开按钮（复用 MingCute `plus` 图标，当已选表情不在快捷栏内时给出主题色轻高亮提示）。
  - 点击 `+` 在快捷胶囊上方 8 pt（顶部空间不足时自动向下翻转）弹出 306 × 310 pt、18 pt 圆角的原生液态玻璃完整表情面板（`ChatEmojiFullPickerView`），顶部 8 枚分类图标与下方 8 列滚动表情网格一一对齐；支持点击分类图标平滑跳转、滚动同步高亮当前分类、已选表情展示主题色圆角边框与右上角对勾角标，点击任意表情即时切换并关闭弹层。
  - 更新本地事件监听：在完整表情面板内滚轮滚动不会误关闭弹层；点击外部、滚动外部对话或按 Esc 仍立即关闭。
- [en.lproj/Localizable.strings](../../App/Resources/en.lproj/Localizable.strings)、[zh-Hans.lproj/Localizable.strings](../../App/Resources/zh-Hans.lproj/Localizable.strings)：补充展开/收起按钮与 8 个表情分类的中英文文案。
- [AgentReactionRegression.swift](../../App/Tests/AgentReactionRegression.swift)：在 `--reactions-preview` 中校验全部 8 个分类及每枚表情的有效性与唯一性、非快捷表情的持久化与切换；在 `--bubble-menu-preview` 中补充展开向下/向上布局、面板内滚动不关闭、点击分类切换、点击展开网格内表情更新回应以及浅色/深色模式实际窗口截图验收。

## 已运行验证

1. `KulaCore` 单元测试：
   - 命令：`(cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test)`
   - 结果：全部通过。
2. 应用工程生成与 Debug 构建：
   - 命令：`xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`
   - 结果：构建通过（`** BUILD SUCCEEDED **`）。
3. 原生回归与实际窗口视觉验收：
   - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 App/Tests/run-agent-reply-regression.py --reactions-preview`：通过（含全量 8 分类表情合法性、无重复、非快捷表情持久化与清除断言）。
   - `./build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --bubble-menu-preview`：通过（含面板内滚轮滚动保持展开、点击分类切换、点击网格内表情更新回应断言），并人工核查实际窗口浅色与深色截图：
     - `build/bubble-menu-emoji-light.png`、`build/bubble-menu-emoji-dark.png`（快捷胶囊含 `+` 按钮）
     - `build/bubble-menu-emoji-expanded-above-light.png`、`build/bubble-menu-emoji-expanded-above-dark.png`（快捷胶囊上方展开完整面板、分类栏对齐、选中框与右上角对勾角标）
     - `build/bubble-menu-emoji-expanded-below-dark.png`（顶部气泡空间受限时自动向下展开不越界）
     - `build/bubble-menu-emoji-expanded-category-light.png`、`build/bubble-menu-emoji-expanded-category-dark.png`（点击分类跳转后标题留白与底部圆角裁剪一致）
