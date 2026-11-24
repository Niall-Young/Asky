# Asky 原生界面与设计系统

更新日期：2026 年 10 月 10 日。状态：已核对变量、聚焦搜索与 AI 对话节点，启动器与对话样式已实现，完整视觉与辅助功能验收仍待完成。

界面使用 SwiftUI 与 AppKit 原生组件，应用用户定义的变量和文字 Styles，并使用系统 Liquid Glass。产品流程以 [PRD](PRD.md) 为准；窗口规格按下述已提供的屏幕设计与原型默认值区分。

## 设计来源与检查结果

来源：[Asky Figma，node 6:12](https://www.figma.com/design/tmVnTyCb2sz5egNQ7We9Sw/KulaHere?node-id=6-12)。

2026 年 10 月 9 日只读检查：node 6:12 为名为 Button 的 PAGE，子节点为 0。文件级数据有 6 个变量集合、106 个变量、24 个文字 Styles，0 个本地 Paint Styles、0 个本地 Effect Styles。没有可从该目标直接复刻的屏幕、组件几何或玻璃效果规范；页面名 Button 不能视为一个已设计按钮组件。

| 集合 | 数量 | 模式与作用 |
| --- | --- | --- |
| Palette | 32 | Default；基础色及透明度阶梯 |
| Typography | 21 | English / Chinese；字体、字重、字号与两种行高 |
| Border | 3 | Default；0 / 1 / 2 |
| Radius | 10 | Default；0、4、8、12、16、24、32、40、48、99999 |
| Opacity | 1 | Default；disabled = 30 |
| Colors | 40 | Light / Dark；语义颜色与别名，2026-10-10 更新 |

后续指定的[聚焦搜索 Field，node 22:348](https://www.figma.com/design/tmVnTyCb2sz5egNQ7We9Sw/KulaHere?node-id=22-348)为启动器收起状态的设计依据：720 × 60、左 24 / 右 20 留白、12 间距、17 pt `magnifyingglass`（21 × 22 图标槽）、16/400/Default 输入和 “Search” 提示。此节点替代之前的输入区尺寸与玻璃处理。搜索总宽度后续按用户要求调整为 640 pt（包含空状态右侧按钮），剪贴板列表宽度同为 640 pt，共用 `WindowMetrics.launcherWidth`；AI 窗口按后续要求独立为 560 pt，使用 `WindowMetrics.agentWidth`。

[UI 页 22:293](https://www.figma.com/design/tmVnTyCb2sz5egNQ7We9Sw/KulaHere?node-id=22-293)中的新聊天 43:1071、AI 对话 42:760、历史记录 38:653 是对话界面的设计依据：720 × 640、32 圆角、70% 语义背景与原生 Regular Liquid Glass、1 pt border。顶部采用 64 pt 高、左右 16 pt 内距的浮动工具栏，不显示会话标题和分割线；右侧常驻置顶与关闭，不再提供独立历史入口；使用原生 `NSButton`，不绘制独立边框或高光底板；右侧置顶与电源符号关闭按钮共用 72 × 36 pt 胶囊，无内部竖分割线；图标统一为 18 pt，按钮组使用原生 Regular 材质，不额外调整效果透明度，保留系统明暗过渡与玻璃边缘，不降低图标不透明度；按钮组交互由 `GlassPointerFeedback` 驱动：悬停仅提亮整块胶囊，按下等比鼓起，释放短促回弹；不增加内部边框、分隔线或方块高亮。保持原始静止尺寸和玻璃强度，减少动态效果时关闭缩放；顶部不再提供更多菜单；设置保留既有快捷键和附件菜单入口；正文左右 32 pt，用户气泡 16 圆角与 12/10 内距，正文和工具行使用 14/400/Default。工具行保留 8 pt 图文间距，示例搜索图标按实际工具替换。底部外距 12 pt；输入区后续收紧为 16 pt 普通圆角、最小 28 pt 文字区域、8 pt 行间距、顶部 10 / 底部 8 pt 留白，空态总高 82 pt；文本左右 12 pt、操作行左右 8 pt。输入区使用原生 Regular 玻璃，不额外调整效果透明度，避免浅色背景上的突兀白块，不降低文字或按钮的不透明度，不叠加 kInput 底色；附件与发送按钮均为 28 pt 圆形，附件按钮使用无底板的加号图标。置顶与关闭常驻；置顶按钮切换填充图标和可访问状态；空状态显示 24/500 问候。历史消息在持续时间线中分页浏览，隐藏滚动条，不再保留历史页、历史搜索框及其快捷键；设置可从附件菜单进入。Figma 壁纸属于桌面展示背景，不作为 App 资产。窗口阴影由 AppKit 提供，光学效果由系统实现，不声称逐项复刻 Figma 滤镜。见[新对话样式验证](validation/2026-10-10-ai-chat-refresh.md)。


2026-11-14 头像配置：顶部左侧默认显示原蓝色微笑小怪物，不显示名字。30 pt 图形区域居中放入 36 × 36 pt 圆形 Clear 玻璃，与右侧按钮组同高，保留 85% 整体玻璃透明度。点击后在同一 `GlassEffectContainer` 中向右下展开为 260 × 340 pt、18 pt 圆角的 Regular 玻璃配置面板；持续复用玻璃表面，前景采用 identity 玻璃分层。顶部为 80 pt 实时预览，下方是「造型」「表情」「颜色」三组横排选项，选项等分当前组宽度，高 42 pt、11 pt 圆角，选中态使用中性描边与轻填充。造型包括原小怪物、正圆、圆齿、软糖、幽灵，表情包括微笑、墨镜、眨眼、困困，保留蓝、黄、紫、绿、粉五色。原小怪物微笑继续使用原始 `AgentAvatar` 资产，其余表情使用同轮廓无表情底图 `AgentAvatarBody` 与独立表情层组合，并以原图 alpha 遮罩保留外形。正圆、圆齿、三角与幽灵均使用参照原小怪物生成的透明底材质图片，保持浅蓝柔软纹理、左上光照与边缘体积感，不再使用平面矢量轮廓或纯色渐变代替。圆齿以八个圆钝外齿替代原方形，三角采用更宽的圆角与微凸侧边；眨眼的闭眼尖端朝脸部内侧。透明留白通过各造型的显示比例校准，不使用 SceneKit。造型选项保留当前表情，表情选项按当前造型与颜色渲染，所有缩略图均与对应选中结果一致。各项即时预览并写入现有偏好，选择后面板保持展开，点外部或 Esc 收起；不显示名字输入、保存按钮或制作说明。旧偏好缺少造型与表情时使用原小怪物和微笑；所有原有颜色原样保留。方向键左右切换选项，上下或 Tab 切换组，Return 或空格选中，Esc 仅收起面板。保持原有 response 0.28 s / dampingFraction 0.58 的展开弹簧；减少动态效果时直接切换。布局和命中区域使用实际面板尺寸，收起仍为 36 × 36 pt。

2026-11-14 按用户提供的 IM 参考图覆盖对话正文规则：正文左右外距统一为 12 pt，与输入区和历史列表对齐。用户消息靠右、Agent 回复靠左，均使用 16 pt 圆角及水平 18 pt 内距；用户气泡垂直内距为 12 pt（2026-11-15 微调），Agent 回复垂直内距保持 14 pt；用户气泡在中性底上轻微叠加当前头像配色，Agent 回复保持中性色；Agent 气泡右侧至少留 40 pt，复制、回复与完成时间保留在气泡下方。回复位于复制右侧，使用同版本 MingCute `corner_down_left` 回转箭头、14 pt 图形、28 pt 点击区域及 `AgentIconButtonStyle`，语义弱图标色与复制一致，悬停提示「回复消息」。复制与回复独立组成间距 0 pt 的按钮组，完成时间 label 位于组外，与按钮组间距 16 pt。Markdown 各级标题统一使用 14 pt 常规正文，不再有独立标题字号或字重。AI 正文与用户消息共用 22 pt Default 行高；原生内联文本不另加容器上下留白。表单直接排在回复气泡内，不再叠加独立卡片、边框与 16 pt 内距。聊天表单的文本、选择与日期控件共用 24 pt 高、6 pt 圆角的输入表面，浅色采用与设置输入表面一致的 12% 白色轻填充；日期保留原生月历弹层，时间和时长只保留组件选择器，不叠加日程弹窗的大块底板。样式通过表单作用域覆盖，设置页和日程弹窗继续使用原有表面。等待期间只显示一个含三点的气泡：三点错峰连续缩放、变透明并轻微上下浮动，等待气泡与最终回复共用左上锚点，以约 0.32 秒的弹簧尺寸变化和文字淡入衔接。减少动态效果时使用静态三点和短淡入，不移动或缩放。完整回答在本轮结束后一次呈现。复制图标与气泡正文的 18 pt 左内距对齐，不使用越出气泡的负向偏移。工具调用、过程说明、耗时及其展开入口不显示，历史会话同样适用。停止、权限、错误和操作确认沿用现有流程。

用户与 Agent 的纯文字气泡均按内容宽度收缩，正文可用宽度只作为上限；短回复保留既有内距，长回复到达上限后换行。文本宽度按实际富文本字形测量，包含粗体、emoji 与内联附件。

2026-11-24 连续同侧气泡链接样式：同一说话方连续出现多条聊天气泡时（Agent 侧含工具前置说明、分条回复、原生结果卡片与紧随前置说明的等待气泡；用户侧含连续多条用户消息），相邻气泡垂直间距收紧为 4 pt，并在外侧（Agent 左侧、用户右侧）相接角使用 4 pt 圆角、其余外角保持 16 pt 圆角（首条收紧底角、中间条收紧顶底双角、末条收紧顶角）；单条独立气泡保持四角 16 pt 全圆角。通知、错误以及带表情回应、权限入口或旧版气泡上方附件卡片的消息不与相邻气泡强行合并。不同说话方之间的轮次间距统一为 20 pt。

2026-11-24 气泡表情回应样式与切换动效：去掉原有胶囊底板与白边描边容器，AI 对用户消息的表情回应（左下角）与用户对 AI 回复的表情回应（右下角）共用 `ChatReactionBadge`，直接以 18 pt emoji（24×24 pt 槽位，轻微悬浮阴影）跨气泡底边悬挂（横向外探 4 pt、纵向外探 12 pt，内侧仍完全位于底部留白内不遮挡正文）；可点击移除的用户表情保留悬停轻放大（1.12×）与按压缩放（0.88×）反馈。当用户将已有表情更换为另一个表情时，触发专属切换小动画：旧表情先斜向上剥离并微模糊淡出（160 ms），新表情紧随其后反向轻倾并经弹簧弹入落位（response 0.34 s / dampingFraction 0.48），同时背后绽放一圈随当前头像配色的柔和扩散环与 6 枚微光点（340 ms）；历史恢复与初始加载保持静止，开启减少动态效果时退化为短淡入淡出。

2026-11-15 时间线的「加载更早的消息」「加载更新的消息」共用居中胶囊按钮：12 pt medium 次要文字、28 pt 高、左右 14 pt 内距与中性底色，复用聊天图标按钮的悬停和按压反馈。按钮与相邻消息保留 16 pt 间距；任务运行时禁用并降至 30% 不透明度，翻页继续保持当前阅读位置。

2026-11-14 对话阅读位置：固定 560 × 680 pt 窗口中，消息按实际高度连续排列，当前轮不设最小屏高，不用空白把问题顶到顶部。新用户消息和等待气泡自然把旧消息往上推；短回答完整显示在正常底部。长回答最多上推到气泡顶部位于工具栏下方 12 pt，后续内容由用户向下滚动阅读；用户问题可移出可视区域。首次短对话保持顶部排列。打开历史同样按短回答到底部、长回答从开头阅读处理。用户开始手动滚动后停止自动定位；回到底部按钮仍可主动跳到末尾。

2026-11-14 用户消息采用中性底加轻微宠物色染色：蓝、黄、紫、绿、粉各有对应色相，深色叠加 12%、浅色叠加 8%，不使用大面积不透明彩色填充。文字沿用随深浅外观变化的语义色，Agent 回复、表单与等待气泡保持既有中性表面。切换头像颜色时，已有用户消息同步更新，不为每条消息另存颜色。

2026-11-14 文字选区与引用：同一段 Markdown 回复共享连续选区，支持跨段落、无序/有序列表与嵌套列表正向或反向拖选；列表标记与首行对齐并参与选区，复制和引用按阅读顺序拼接，单击空白处清空整组选区。聊天原生文本选区使用当前头像色 45% 透明度，保留文字原色。拖选结束后，在选区旁显示独立窗口承载的横向液态玻璃胶囊菜单，圆角始终为实际高度的一半，13 pt 文字，包含「复制」与「添加到对话」，点击别处、滚动、Esc 或窗口失焦后关闭。引用复用 ComposerAttachmentCard 上传文件标签的 52 pt 高度、12 pt 圆角、44 pt 图标容器与原有间距；使用文档图标，名称为「引用的文本 1」「引用的文本 2」等连续序号，每条消息从 1 开始，移除后重新编号；输入区、发送后的消息与恢复的历史使用一致顺序，不显示原文、摘要或大小。与文件和图片共用横向附件行，输入区保留悬停移除按钮，发送后标签不提供移除按钮。引用与文件标签的正方形图标底座使用 6% 中性色（浅色用深色、深色用白色），保留 8 pt 圆角并移除描边；减少透明度时保留原有语义背景。外层卡片底色与悬停反馈保持不变。使用共享玻璃封装，不自绘阴影。按用户最新反馈，选区菜单关闭额外系统窗口投影，保留原生玻璃边缘；「添加到对话」复用同版本 MingCute chat_2 圆形气泡。2026-11-15 按用户最新反馈，复制和添加到对话仅保留连续玻璃上的悬停侧向提亮：悬停侧最多 4% 中性加色提亮，经 40% / 60% 位置衰减至另一侧透明。不按按钮边界绘制小底板或局部光斑，保留一体玻璃形状；按压时窗口、玻璃和内容均保持原尺寸。点击空白处、滚动或失焦会清除原生文字选区，Esc 同时清除选区并关闭菜单但不关闭聊天窗口；点击原文本内部保留原生重新选择行为。点击完成后立即关闭菜单并清除选区，不等待缩放、回弹或淡出；拖出按钮后松开仍取消操作并保留选区。减少动态效果时同时关闭悬停明暗的过渡动画。

2026-11-15 整条消息回复与文字选区引用区分展示：回复预览卡片保留原附件标签的左图右文布局、52 pt 高、12 pt 圆角、44 pt 图标底座及移除按钮；图标使用 24 pt MingCute `chat_1`。卡片宽 304 pt，文字区域宽 224 pt、高 44 pt，沿用 14 pt 标签文字，最多两行、尾部省略，直接展示原回答的纯文本预览，不展示「引用的文本」标题。Markdown 转为可读文字，表单使用标题，完整内容仍保存并随提问提交。输入区与发送后的历史标签共用样式。文字选区引用保留原有文档图标和编号标签。

2026-11-16 已发送的整条消息回复卡片可点击，以约 0.22 秒先快后慢的滚动定位到原回答，气泡顶部保持在 64 pt 工具栏下方 12 pt；长回答从开头显示，短回答受实际内容边界限制。原回复不在当前历史页时只加载其前后各最多 40 条消息；不改变当前会话或输入草稿，回到底部仍恢复最新页。手动滚动立即停止动画与定位修正；系统开启减少动态效果时直接定位；生成中的回复不因跨页跳转被移出当前窗口。原回复已清理时保留引用预览，并反馈原回复不可用。文字选区引用和输入区卡片保留原交互。

2026-11-23 统一输入区与用户消息的行内 Tag 体系：图片、文件附件、粘贴的长文本（单次粘贴 ≥ 300 字或 ≥ 6 行时自动折叠，⌘⇧V 保留纯文本粘贴）、划词引用与整条消息回复不再在输入框上方占用 52 pt 大卡片区，而是统一经由原生 `NSTextAttachment` 以 22 pt 高、6 pt 圆角、最大宽 188 pt、12.5 pt 常规字体的轻量行内胶囊融入提示词正文，支持光标穿梭、Backspace 删除、⌘Z 撤销与中文输入法混排。各类型通过左侧 13 pt 线性图标（图片使用 16 × 16 pt 圆角缩略图）与简洁文案区分：文件与图片使用中间截断，划词引用直接显示引号包裹的节选开头，回复消息使用回转箭头加纯文本预览，粘贴长文本显示字数摘要。输入区内的行内 Tag 悬停时在左侧图标位直接显示 `✕` 删除图标（图片缩略图叠加半透明暗遮罩与白色 `✕`），点击即可移除并支持 ⌘Z 撤销，也可直接用 Backspace 删除；文件与图片不再弹出点击 Popover，点击粘贴文本、划词引用与回复消息仍弹出轻量 `NSPopover`，支持预览全文、复制、移除，粘贴文本支持一键「展开到输入框」，回复消息支持「查看原回复」。发送后，带行内 Tag 的用户消息在气泡内原位渲染相同样式的行内 Tag，点击回复 Tag 继续沿用原回答滚动定位，文件与图片不弹 Popover；底层通过有序 `MessageSegment` 与 `MessagePastedText` 持久化并在发送给模型时按原位生成编号锚点，历史旧消息保持既有卡片样式向后兼容。

2026-11-14 输入框发送按钮的圆形底色同步使用当前 Agent 配色，复用头像与用户气泡的五色色板；浅色和深色外观均使用深色图标，禁用时仅将底色降至 30%，运行中的停止按钮沿用同一配色。

后续 Figma 变更先核对来源，再更新附录与原生映射；不要在文件中自动创建组件或改写用户变量。本稿附录为设计数据快照，不是自动生成的生产源码。

## 原生映射规则

2026-11-16 聊天输入框的原生滚动区域距玻璃左右边缘 4 pt，文字容器内部再留 8 pt，文字仍保持原有 12 pt 留白；溢出时滚动条比此前向右移 8 pt。输入框高度上限、字号与底部按钮布局保持不变。

2026-11-16 「完全访问」常驻状态在亮暗模式下均采用橙黄色：浅色 `#AD690B`、深色 `#E8AD52`，由 Theme 层 `FullAccessTint` 根据外观解析；浅色下加深以保持清晰。输入区按钮和审批菜单项的图标、文字、选中标记共用此样式；通用错误红保持原值。

| 设计数据 | 原生应用方式 |
| --- | --- |
| Palette / Colors | 统一 Theme 层解析语义角色与当前外观，控件不散落硬编码颜色 |
| Typography | 用文字角色映射 SwiftUI Font / AppKit 字体属性；按内容语言使用 English / Chinese 家族与自然回退 |
| Border | 以设计基准值映射原生 pt，在目标显示 scale 下检查清晰度 |
| Radius | 有限值用于相应内容形状；radius99999 映射 Capsule，不创建巨大的圆角数值 |
| Opacity | disabled 30 是百分比，原生归一化为 0.3；同时设置真实禁用状态 |
| Styles | 保留“字号 / 字重 / Default 或 Paragraph”的来源关系；不要把行高当文字框固定高度 |

语义颜色先递归解析别名，再按模式取得基础值；原生代码名可规范化，但维护明确映射。源名称 backgroundDisbled 保留原拼写，代码可映射到 backgroundDisabled；Overlay、Input 与 InteractionHover 的大写同样在来源记录中保留，原生分别映射为 overlay、input、interactionHover，不偷偷改写 Figma。

2026-10-10 只读复核 Colors 与 Palette：Colors 共 40 项，文件变量总数为 107，Palette 未变。backgroundPrimarySubtle 与 backgroundNeutral 的 Light / Dark 透明度从 4% 调为 6%，Input 从 4% 调为 8%；新增 InteractionHover（Light = Palette/black6，Dark = Palette/white8）。此变量绑定于 Spotlight item 悬停变体 38:459 / 38:460 和 Session history 悬停变体 43:1134，原生结果行和历史行按鼠标悬停使用，键盘选择仍使用原有选择语义。见[颜色同步验证](validation/2026-10-10-colors.md)。

行高是设计目标。SwiftUI 的 lineSpacing 不直接等于总行高，应核对字体度量、基线、中英混排与原生控件内部排版；不能为了完全相等的数字裁切文字。字号与行高在正常大小下按源值应用，并保持系统文本放大与辅助功能可用。

当前没有 Spacing 变量集合。首轮沿用原生控件内距与布局习惯；若需要独立空间 token，应作为新的设计决定记录，不能宣称已从 Figma 导出。

## 文案规范

- 中文文案的末尾一律不加句号（。），适用于设置、对话框、错误提示、空状态、通知、菜单项等所有用户可见的中文文案；句子中间的句号仍可保留
- 中文与英文混排时，末尾标点按整句正文语言决定；纯英文文案沿用英文标点习惯
- 修改本地化键时同步更新 `en.lproj` 与 `zh-Hans.lproj`，中文显示值必须去掉末尾句号

## 界面结构与窗口默认值

AppKit NSPanel 承载快捷入口，普通层级的透明 NSWindow 承载 AI 对话，保留键盘操作、焦点和原工作应用的切换体验。SwiftUI 管理内容；确需原生窗口、选区、快捷键或特定控件能力时使用 AppKit 适配。

| 区域 | 原型默认值与行为 |
| --- | --- |
| Launcher | 宽 640 pt，输入区高 60 pt，高度随结果变化，最大 540 pt |
| Agent | 固定 560 × 680 pt，不可拖拽缩放；外壳统一为 26 pt 普通圆角，玻璃、内容与窗口框架同步裁剪 |
| 输入 | 16/400/Default（node 22:348） |
| 结果主文本 | 14/400/Default |
| 次要说明与快捷键 | 12/400/Default |
| 按钮文字 | 14/500/Default |
| 对话正文 | 14/400/Default（node 43:1052） |

Launcher 收起尺寸与输入文字来自 node 22:348；Agent 初始尺寸来自 node 43:1072 / 38:654，其余尺寸与角色仍为当前实施方案的建议默认值。应在多显示器、长文本、辅助功能放大与真实任务中验证，不能把其余建议归因于空 Figma 页面。

启动器收起时使用 `radius99999` 对应的 Capsule，展开结果、状态或终端时使用 `radius32` 连续圆角。输入区左侧留白 24 pt、右侧 20 pt，搜索图标为 17 pt（21 × 22 槽），与文字间距为 12 pt，来自 node 22:348；结果列表左右留白 12 pt、上下 10 pt，行内左右留白 12 pt，使图标左侧继续对齐。结果布局仍为实施值，不属于 Figma Spacing 变量。见[聚焦搜索验证](validation/2026-10-09-figma-search.md)。

2026-10-17 按用户提供的 Tinycast 截图调整搜索密度，覆盖上文启动器的历史尺寸：输入区高 52 pt、输入字号 16 pt；结果改为 38 pt 单行、24 pt 图标、14 pt 名称与右对齐的 12 pt 类型。分组标题高 30 pt，列表预算为八行（304 pt，分组标题共用预算）。结果行不显示路径或副标题；应用显示“应用”，文件优先显示格式扩展名，目录显示系统类型，其余显示来源类型。路径复制与访达定位保留。2026-10-18 搜索框右侧恢复常驻的 MingCute 放大镜（17 pt，19×24 pt 布局槽），使用语义弱图标色，不提供 Button、悬停、点击、tooltip 或辅助功能操作；删除固定与筛选入口，分类搜索统一通过互斥的命令模式进入。输入前后保持右侧图标与文字区宽度稳定，搜索框始终保持 640 pt 宽，见[静态搜索图标验证](validation/2026-10-18-static-search-icon.md)；收起与展开时 SwiftUI 裁剪、原生玻璃和内容层统一使用 26 pt 圆弧半径，避免高度变化后端部被拉伸。系统阴影结构保持一致。

交互区至少覆盖输入、可选择结果、附件预览、工具进度、澄清、确认、实际结果、历史与记忆管理。确认界面显示具体目标和变更；“正在启动 AI”立即反馈，但不是承诺 Pi 已经在某个时限内启动。

## 原生组件使用

| 需求 | 首选原生能力 | 保留的行为 |
| --- | --- | --- |
| 输入、搜索与多行任务 | SwiftUI TextField / TextEditor，必要时 NSTextView 适配 | 选区、输入法、粘贴、键盘与辅助功能 |
| 动作、选择与开关 | Button、Toggle、Picker、Menu | 原生语义、焦点、禁用与快捷键 |
| 结果与历史 | 原生列表或有界分页滚动区域 | 稳定目标标识、键盘选择、按需加载 |
| 进度与状态 | ProgressView 与结构化工具结果 | 停止、拒绝、错误与待核实可区分 |
| 附件与来源 | 原生预览、文件或目标打开入口 | 缩略图、查看原件与可追溯来源 |

聊天与启动器动作按钮使用 `GlassPointerFeedback.swift`，这是用户明确允许、参考 2026-11-14 iOS 录屏定制的反馈，不称为 macOS 原生动画。悬停不缩放，玻璃表面以同形状的加色叠层柔和提亮；按住时 100 ms 等比鼓起（比例增量 min(0.06, 3 / 最长边 pt)，避免长胶囊挤占相邻控件），释放采用 response 0.34 s / damping 0.42 的弹簧回落。禁用时无反馈，减少动态效果时仅保留明暗变化。玻璃和图标一起变形，静止时不增加底板、边框、分隔线或留白；头像菜单继续使用独立的玻璃尺寸弹簧过渡。普通附件/复制图标沿用既有悬停形状，不新增玻璃底板。设置按钮保留系统反馈，不叠加这套自定义动画。按钮动作不等待动画结束。

Theme、ButtonStyle、LabelStyle 或 ViewModifier 只负责样式映射，不重写控件固有行为。不能把可点击文字当按钮、颜色当唯一状态或失去原生输入法行为。功能图标统一使用 [MingCute Icons](https://github.com/mingcute-design/mingcute-icons) 的线性 SVG，选中或运行状态按需采用同库填充版本。图标作为本地矢量模板资产打包，通过 `MingCute` 共享映射供 SwiftUI 和 AppKit 使用，大小显式指定，颜色继承语义前景色。设置侧栏与旧功能资产也使用同库图形。AI 思考过程中的工具调用图标槽统一为 16×16 pt，包括加载、应用、插件与通用图标；日历等工具保留对应 App 的图标，失败状态使用 MingCute `warning` 圆形感叹号，错误详情与行文字对齐。可展开错误的箭头紧跟工具调用 label，不使用圆形或胶囊按钮；点击文字与箭头整体展开/收起。联网搜索使用 MingCute 搜索图标，记忆调用使用 MingCute brain。所有插件（包括 Orca、飞书）统一使用 MingCute tool 图标，工具调用中为 16×16 pt，插件设置保留 36 pt 图标槽；不再加载品牌应用图标或插件自定义图标作为界面标识。自动审批使用用户提供的 `hand_line`（源文件 `App/Artwork/approval-hand.svg`），按钮与审批菜单共享同一映射。聊天与代码块复制采用用户提供的 `copy_2_line`（`App/Artwork/copy.svg`）。Asky 品牌标识、真实应用/网站标识、用户自选图标与内容缩略图保留原始来源。Asky 自有工具入口（链接、书签、换算、标签页、计算器、退出）必须复用 `LauncherFunctionIcon`：使用本地 MingCute 线性矢量模板叠加纯色底板，白色图形 16×16 pt、底板 20×20 pt、外层图标槽 24×24 pt；底板统一裁切 5 pt 普通圆弧圆角（`.circular`），不得使用连续圆角或超椭圆。图形居中，不单独缩放或偏移，不叠加渐变、高光或阴影，不使用预合成 PNG 作为自有工具图标。搜索结果、输入模式与指令设置必须共用相同组件与映射；网站搜索指令与工具共用 `LauncherIconTile.cornerRadius` 的 5 pt 普通圆弧，工具底板直接以固定圆弧路径填色绘制。背景色集中由 `ToolIconPalette` 维护：橙 #FF9A02、青蓝 #0091FF、蓝 #2D68FF、紫 #7D40FF、红 #FF0000、绿 #28A745、青绿 #009E9A、粉 #E34F8C、靛蓝 #5856D6。书签与文件使用橙色，退出使用红色，换算与计算器使用青蓝色，链接使用青绿色，标签页使用紫色，窗口使用靛蓝色，应用使用蓝色，快捷方式使用绿色，快捷指令使用粉色。不得在入口中散落色值或使用透明度变体。对应 MingCute 图形为 link、bookmark、transfer、layout_4_line（资源名 `layout_4`）、counter_2、power。AI 入口保留原有 `Agent` 品牌图片与 20 pt 显示尺寸，禁止替换为 MingCute 图形或套用工具色板背景。新增自有工具沿用同一组件与几何，只增加语义图形并从共享色板中选择；真实应用、网站品牌 Logo、国旗及内容缩略图保留原始来源，不套用自有工具的白色模板规则。资源版本、完整替换映射见 `scripts/mingcute-icons.json`，Apache-2.0 许可随应用打包在 `App/Resources/ThirdParty/MingCute/`。

### Dialog 与 Alert

设置中的添加插件、插件配置、添加／编辑别名使用共享 `SettingsDialog`，挂载在整个设置窗口的内容根视图上，横向与纵向居中均包含侧栏，窗口缩放后保持居中。弹窗显示时拦截背后页面及侧栏的鼠标操作，取消或 Esc 后移除并恢复输入焦点。表面通过 `nativeGlassBackground` 使用原生 Regular 玻璃与 16 pt 圆角，不额外叠加不透明底色、自绘描边或阴影；降低透明度／增强对比度与旧系统沿用共享组件回退；内距 24 pt，插件弹窗宽 440 pt，别名弹窗宽 480 pt，插件配置宽 520 pt。插件仓库字段采用标签在上、输入在下的单列表单，不再嵌套卡片底板；按用户要求不显示输入框下方的信任仓库说明，仅在输入无效时显示错误反馈。

应用内提示、错误、安装与更新确认、工具执行确认统一使用 macOS 原生 `NSAlert`，经 `AppDialog` 创建与呈现。有所属窗口时使用 `beginSheetModal` 的原生 sheet；不手动设置应用图标，让 AppKit 省略重复的品牌区并提供紧凑布局。仅启动失败等没有所属窗口的情况回退到独立 alert。外壳、圆角、材质、阴影、文字排版和按钮布局均交给 AppKit，随系统版本和外观设置呈现；不按参考图自绘一套固定外观，也不套用启动器的玻璃窗口结构。

按钮尺寸与排列使用系统默认值（当前系统中两个简短按钮横排、三个按钮纵排），不手动改写按钮 frame。主要操作使用默认按钮，取消或拒绝保留 Escape 行为；确认正文用一段自然语言说明具体目标、变更和必要影响，不展示字段列表、工具名、原始参数或“操作详情”展开入口。系统权限提示、打开与保存面板继续使用对应的系统界面。

## 启动器悬浮操作区

结果底部左侧展示选中项的主要操作，右侧仅在存在附加动作时显示「更多 ⌘K」；没有可用动作时允许两侧都为空。底部操作按钮使用原生 Clear 玻璃胶囊，以 85% 整体透明度柔化高光并保留大部分折射；文字与快捷键保持完整不透明度；展开后的更多菜单保留 Regular 材质。搜索和剪贴板列表底部的左侧操作仅显示文字与快捷键，不显示文字左侧图标。它们叠放在结果区域内，不增加固定分隔栏；列表底边使用 alpha 渐隐，让滚动内容在控件下方消退，末尾预留滚动空间，使最后一条结果能完整露出。

启动器与剪贴板列表的“更多”与按钮共用各自主窗口内的玻璃表面：macOS 26+ 开启液态玻璃时，使用 `GlassEffectContainer`、相同 `glassEffectID` 与 `.matchedGeometry` 从按钮原位向左上方展开菜单，关闭时缩回，展开与收回均采用 180 ms 的 smooth 过渡；不再弹出独立子窗口。菜单与按钮的右下角对齐，覆盖结果、不改变外壳尺寸；菜单过高时内部滚动。旧系统或关闭液态玻璃时使用既有材质回退；减少动态效果时立即切换。`⌘K` 切换菜单，`↑` / `↓` 在菜单中选择，`Return` 执行，`Escape` 只关闭菜单；关闭后保持输入框焦点、搜索词与原结果选择。输入改变或选中目标变化时关闭旧菜单，避免将动作应用到其他结果。文件与应用的「在访达中显示」直接置于左侧操作区、紧随主操作，不在更多菜单重复；「复制路径」保留在更多菜单，两者沿用用户配置快捷键；链接与标签页提供「复制链接」。计算结果只显示复制操作，汇率保持只读。实际检查见[悬浮操作区验证](validation/2026-10-17-launcher-actions.md)与[更多按钮变形验证](validation/2026-10-18-launcher-more-morph.md)。

搜索结果首次出现时，列表在最终位置以 180 ms ease-out 淡入，不做纵向位移；后续查询、结果批次和键盘选择不重复列表入场。玻璃外壳首次出现结果或进入搜索模式时，沿固定搜索框顶边向下展开至固定高度（52 pt 输入区 + 1 pt 分隔线 + 380 pt 结果区，共 433 pt；小屏按可用空间限制），使用显示链路驱动的无回弹弹簧（response 0.18、damping 1）。同一次展示期间，结果变多或变少、异步加载与模式内查询变化都保持该高度；普通搜索完全清空（含仅空白字符）时沿相同弹簧收回单行，途中再次输入可转向展开。sw 等搜索模式的空查询保持展开，退出模式回到空的普通搜索时收起。列表在固定结果区滚动，操作区保持底部位置。窗口顶边锚点和每帧高度统一对齐到整数 pt，避免 AppKit 分别取整坐标与尺寸导致顶边跳动；隐藏立即停止动画，卸载结果与重内容，保留原生玻璃外壳和搜索输入框；重新打开恢复单行输入与焦点。系统“减少动态效果”开启时，窗口直接调整尺寸，列表仅 100 ms 淡入。

审批模式收起入口仅显示图标与文字，不绘制玻璃底板、描边或悬停填充。展开菜单为 220 × 86 pt 的原生 Regular 玻璃（非 interactive，点击时整块菜单不缩放），14 pt 圆角；每行只保留图标、名称与选中勾，不显示二级说明。菜单通过入口锚点挂载到聊天窗口顶层，不嵌在输入框玻璃内，避免上方菜单行超出输入框后失去悬停追踪。入口始终保持原位，点击后在上方 8 pt 弹出独立菜单，仅做 120 ms 淡入淡出，不从按钮变形；菜单行整行可点击，使用共享的 `GlassRowButtonStyle`：悬停与按下仅做白色玻璃提亮（与文字选区操作菜单一致），不缩放、不回弹，不绘制普通灰色悬停底板；网页来源卡片的来源行使用同一样式。减少动态效果时立即显示或关闭，降低透明度、增强对比度及旧系统沿用既有材质回退。

## Liquid Glass

macOS 14/15 的兼容表面使用 `NSVisualEffectView` 的 `underWindowBackground` 材质与 `behindWindow` 模式，叠加现有 `background` 变量（浅色白 60%、深色黑 60%）及 1pt `border` 描边。设置侧栏与内容区同步适配；按钮降级为原生 bordered / borderedProminent。用户已接受系统控制的背景模糊半径，不要求精确 120px。辅助功能模式保持不透明背景与高对比描边。

macOS 14 的设置使用原生分组 `Form`，保留全部设置项；15+ 保留现有自定义分组卡片。14 的聊天滚动使用 `ScrollViewReader` 与 AppKit 滚动区域通知，保留初始底部与回到底部按钮；仅发送新问题时定位到底部，回答出现或更新时保持阅读位置，15+ 同样适用；标题栏空隙通过 AppKit `performDrag` 拖动窗口。

macOS 26+ 使用原生液态玻璃；源码构建最低支持 macOS 14。SwiftUI 的 glassEffect、GlassEffectContainer 与原生玻璃按钮样式，以及 AppKit NSGlassEffectView 是实施候选；具体组合与 SDK 可用性在 M0 编译和视觉验证。[Apple SwiftUI Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)、[Apple NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)

玻璃控件统一使用 `NativeGlassBackground`，整窗背景通过 `windowSurfaceBackground` 仅绘制回退、由 `WindowSurface.glassContentView` 提供原生玻璃：macOS 26+ 普通模式仅使用原生 `.glassEffect(.regular, in:)`，不叠加 `background` 的黑白填充或自制渐变描边；原生材质负责磨砂、光学边缘和背景适配。按钮可使用 Regular 的 interactive 变体。整窗表面采用 Spotlight 式窗口结构：启动器外壳、AI 对话、筛选菜单、剪贴板主窗口和完整预览各自是一个窗口，窗口帧恰好等于玻璃外形，由 AppKit `NSGlassEffectView` 填满（显式 `.regular`、`tintColor = nil`）并开启 `hasShadow`，阴影由窗口服务器按可见外形生成；`NSGlassEffectView` 与内容层都按同一圆角裁剪，否则玻璃在窗口角落留下的微弱 alpha 会让系统阴影呈方角黑边。启动器与剪贴板列表的“更多”均在各自主窗口内由按钮原位变形展开；启动器的固定与筛选是搜索框内部的普通图标按钮，共用外壳玻璃，只绘制悬停和按下反馈，不创建按钮窗口或执行分离动画。筛选与更多菜单的非 key 玻璃和 key 外壳的材质差由 `InactiveGlassTintView` 补偿：深色用 5% 白色透明叠层；浅色改用 5% `.plusLighter` 加色叠层，因为普通白色叠层在亮背景接近饱和、补不上约 12 级的暗差。补偿必须在窗口 alpha 入场动画开始前启用：加色叠层在窗口 alpha 动画期间不会被合成，动画中途才启用会等到落定才出现，形成约 12 级的亮度突跳。见[浅色模式非 key 玻璃提亮](validation/2026-10-18-inactive-glass-light-mode.md)。提示条是不透明的独立表面。不使用透明留白画布与自绘阴影（前者被描出偏下黑框，后者曾让浅色玻璃变深）。降低透明度或增强对比度时由 SwiftUI 绘制不透明回退表面。见[Spotlight 式浮动表面](validation/2026-10-16-spotlight-surfaces.md)、[原生窗口阴影](validation/2026-10-14-native-window-shadow.md)与[启动器黑框](validation/2026-10-16-launcher-shadow-outline.md)。

2026-11-15 聊天滚动区铺满整个窗口，输入框在底部叠放，不再将正文与输入区分成上下两个布局区域。正文可连续滚动至输入框玻璃后方；底部复用顶部的渐进模糊并反转蒙版，范围严格等于输入框实测高度（含底边距），从输入框顶部的 0 pt 向窗口底边增至 6 pt，不向输入框上方延伸，不叠加颜色，位于输入框控件下方且不接收交互；降低透明度时隐藏这层装饰。输入框保留原生 Regular 材质、16 pt 圆角与左右/底部 12 pt 留白。消息末尾预留输入框实测高度（含底边距）加 13 pt，随多行输入和附件变化；回到底部按钮位于输入框上方 8 pt，最后一条消息可完整滚至输入框上方。

阅读区不使用 Clear 材质，避免背景文字直接折射进正文；聊天输入区与右上按钮组使用原生 Regular 玻璃，不再叠加效果透明度，保留原生边缘与柔和明暗过渡，避免浅色背景上的整块提白；附件和发送按钮为 28 pt。降低透明度或增强对比度时关闭玻璃，改用不透明语义背景和清晰边框。剪贴板主窗口统一使用列表视图，移除显示方式设置；旧版卡片配置自动忽略。窗口复用搜索框的 `LauncherLayout.shellCornerRadius`（当前 26 pt）普通圆角，SwiftUI 背景裁剪与 AppKit 玻璃、内容及窗口框架层同步使用相同半径和 circular 曲线。剪贴板列表的顶部栏复用主搜索输入区的 52 pt 高度、左 28 / 右 22 pt 留白与两侧内缩 28 pt 的底部分割线；不显示搜索图标，固定按钮位于输入行右侧，移除筛选按钮与菜单；所有输入均作为普通搜索词，不提供类型筛选或类型指令；输入框与固定按钮共享窗口玻璃，不再给输入框叠加独立胶囊玻璃。主搜索和剪贴板右侧图标共用 19 × 24 pt 布局槽与 17 pt 图标，图标中心距窗口右缘均为 31.5 pt；剪贴板按钮保留 28 × 28 pt 点击范围，输入行高度统一为 52 pt。固定为纯图标按钮，普通状态无玻璃底板或边框，仅在悬停和按下时绘制反馈；列表中间竖分割线距内容区顶部 12 pt，底部避开悬浮操作区并额外留白 12 pt。其他内容卡片保留原有内容层。原生材质随背景变化，不承诺固定黑白表面或 Figma 光学参数的逐项等价。验证见[原生玻璃统一记录](validation/2026-10-11-native-glass.md)。

设置窗口以 [Figma node 61:164](https://www.figma.com/design/tmVnTyCb2sz5egNQ7We9Sw/Asky?node-id=61-164) 为模板：900 × 700 初始尺寸（容纳全部侧栏分组并保留 16 pt 底部留白，默认尺寸不出现多余微幅滚动）、220pt 侧栏、32pt 外圆角、16/500 页标题、14/400 正文、14/500 分组标题、12pt 卡片圆角。设置卡片内的单元格标题与辅助说明统一为 14 pt（标题 14/400/Default，辅助说明 14/400/Default 并使用次要文字色）；仅分组页脚、状态提示等外围说明保持 12 pt。整窗共享一层背景，使用 AppKit 原生 Regular 玻璃、固定 25% 明暗语义背景染色与固定中性色层；窗口失焦不额外切换染色浓度，保留环境色并保证卡片层次，避免侧栏与内容区各自加材质。浅色设置卡片保留 70% 背景色；暗色卡片使用 6% 白色提亮层，避免与整窗玻璃产生过大的明暗差，侧栏选中态使用 `backgroundSelected`；按钮在 macOS 26+ 标准透明度与对比度下使用原生玻璃胶囊样式，使用 large 尺寸并将实际视图高度与输入框统一为 28pt；兼容模式保留原生默认样式；文本框和下拉选择器共用 `settingsInputSurface` 的底色、圆角和边框，下拉只保留原生菜单交互，避免同一表单出现两套填充。输入框与密码框保持原生编辑行为，使用低对比半透明背景、28pt 高度、14pt 胶囊圆角与聚焦描边，避免暗色系统输入背景呈现为突兀黑块。降低透明度或增强对比度时改用不透明语义背景。设置页的搜索框与分类切换同处一行；搜索框同样为 28pt 高度与 14pt 圆角；分类切换使用原生 NSSegmentedControl 胶囊样式、large 控件尺寸（当前系统为 28pt 高）与中性选中底色，不使用蓝色强调填充；指令和插件页共用这一控件；按钮及分段控件在 SwiftUI 宿主显式设置 `.controlSize(.large)`，避免窗口活跃状态更新时被默认 regular 环境覆盖。行内图标操作的悬停底板也使用胶囊轮廓。

设置页的文本框、密码框、搜索框、下拉选择器及内嵌列表（排除项、备忘录文件夹）共用输入表面：浅色使用 45% 白色填充，让底色接近相邻原生按钮的明度；暗色继续使用 6% 白色。保留现有尺寸、圆角及焦点反馈；浅色未聚焦描边使用 8% 黑色，取消额外淡化，暗色描边不变。

- 浮动入口外壳、导航、工具栏与关键操作适合玻璃；使用系统协调的效果容器，避免各层独立叠加。
- 对话正文、长文本与结果内容保持清晰阅读层。
- background 等语义变量用于需要的内容与控件角色，不把一层自定义不透明背景覆盖在系统玻璃上。
- 选中、悬停、焦点和禁用需要可辨识；品牌颜色叠加不能破坏系统玻璃的光学表现。
- 不通过截取桌面、持续抓取壁纸或自制大图模糊模拟原生效果。
- 系统减少透明度、提高对比度或减少动态效果时使用系统适配，必要时降低装饰效果并保持文字可读。

## 视觉与辅助功能验收

检查 Light / Dark、浅色和深色壁纸、复杂壁纸、多显示器与不同 scale；核对焦点环、键盘顺序、VoiceOver 标签、禁用状态、文本放大、减少透明度和减少动态效果。

红色、绿色与低透明度角色尤其应检查小文字对比度。不能只凭 token 数值认定可读；状态同时有图标或文案，需要高对比适配时保持语义并记录具体设计处理。

页面隐藏后停止不必要动画，卸载重内容，玻璃视图和图片资源不持续积累。相关验证见 [资源生命周期](resource-lifecycle.md) 与 [实施与验证](implementation-and-validation.md)。

## 设计数据附录

颜色以 8-bit sRGB 十六进制与透明度百分比表示，透明度已按原始浮点值归一显示。别名仍按“集合 / 变量名称”记录，保留 Light / Dark 的关系，不只保存一次解析后的结果。数字是 Figma 设计值；Opacity 百分比、Capsule 与原生排版换算遵循上文规则。

### Palette 变量

| 源名称 | Default |
| --- | --- |
| black100 | #0E0F11 / 100% |
| black90 | #0E0F11 / 90% |
| black80 | #0E0F11 / 80% |
| black70 | #0E0F11 / 70% |
| black60 | #0E0F11 / 60% |
| black50 | #0E0F11 / 50% |
| black40 | #0E0F11 / 40% |
| black30 | #0E0F11 / 30% |
| black20 | #0E0F11 / 20% |
| black10 | #0E0F11 / 10% |
| black8 | #0E0F11 / 8% |
| black6 | #0E0F11 / 6% |
| black4 | #0E0F11 / 4% |
| black2 | #0E0F11 / 2% |
| black0 | #0E0F11 / 0% |
| white100 | #FFFFFF / 100% |
| white90 | #FFFFFF / 90% |
| white80 | #FFFFFF / 80% |
| white70 | #FFFFFF / 70% |
| white60 | #FFFFFF / 60% |
| white50 | #FFFFFF / 50% |
| white40 | #FFFFFF / 40% |
| white30 | #FFFFFF / 30% |
| white20 | #FFFFFF / 20% |
| white10 | #FFFFFF / 10% |
| white8 | #FFFFFF / 8% |
| white6 | #FFFFFF / 6% |
| white4 | #FFFFFF / 4% |
| white2 | #FFFFFF / 2% |
| white0 | #FFFFFF / 0% |
| red | #FF0730 / 100% |
| green | #28EEA5 / 100% |

### Typography 变量

| 源名称 | English | Chinese |
| --- | --- | --- |
| fontFamily | SF Pro | PingFang SC |
| fontWeightRegular | 400 | 400 |
| fontWeightMedium | 500 | 500 |
| fontSize12 | 12 | 12 |
| lineHeight12 | 20 | 20 |
| fontSize14 | 14 | 14 |
| lineHeight14 | 22 | 22 |
| fontSize16 | 16 | 16 |
| lineHeight16 | 24 | 24 |
| fontSize18 | 18 | 18 |
| lineHeight18 | 26 | 26 |
| fontSize20 | 20 | 20 |
| lineHeight20 | 28 | 28 |
| fontSize24 | 24 | 24 |
| lineHeight24 | 32 | 32 |
| lineHeightParagraph12 | 24 | 24 |
| lineHeightParagraph14 | 28 | 28 |
| lineHeightParagraph16 | 32 | 32 |
| lineHeightParagraph18 | 36 | 36 |
| lineHeightParagraph20 | 40 | 40 |
| lineHeightParagraph24 | 48 | 48 |

### Border 变量

| 源名称 | Default |
| --- | --- |
| borderWidth0 | 0 |
| borderWidth1 | 1 |
| borderWidth2 | 2 |

### Radius 变量

| 源名称 | Default |
| --- | --- |
| radius0 | 0 |
| radius4 | 4 |
| radius8 | 8 |
| radius12 | 12 |
| radius16 | 16 |
| radius24 | 24 |
| radius32 | 32 |
| radius40 | 40 |
| radius48 | 48 |
| radius99999 | 99999 |

### Opacity 变量

| 源名称 | Default |
| --- | --- |
| disabled | 30 |

### Colors 变量

| 源名称 | Light | Dark |
| --- | --- | --- |
| text | Palette/black90 | Palette/white90 |
| textSubtle | Palette/black70 | Palette/white70 |
| textSubtlest | Palette/black50 | Palette/white50 |
| textDisabled | Palette/black30 | Palette/white30 |
| textInverted | Palette/white100 | Palette/black100 |
| textPrimary | Palette/black90 | Palette/white90 |
| textNegative | Palette/red | Palette/red |
| textPositive | Palette/green | Palette/green |
| textSelected | Colors/textPrimary | Colors/textPrimary |
| icon | Palette/black80 | Palette/white80 |
| iconSubtle | Palette/black60 | Palette/white60 |
| iconSubtlest | Palette/black50 | Palette/white50 |
| iconDisabled | Palette/black30 | Palette/white30 |
| iconInverted | Palette/white100 | Palette/black100 |
| iconPrimary | Palette/black80 | Palette/white80 |
| iconNegative | Palette/red | Palette/red |
| iconPositive | Palette/green | Palette/green |
| iconSelected | Colors/iconPrimary | Colors/iconPrimary |
| border | Palette/black8 | Palette/white8 |
| borderIntense | Palette/black10 | Palette/white10 |
| borderPrimary | Palette/black20 | Palette/white20 |
| borderNegative | Palette/red | Palette/red |
| borderPositive | Palette/green | Palette/green |
| borderSelected | Colors/borderPrimary | Colors/borderPrimary |
| borderFocused | Colors/borderPrimary | Colors/borderPrimary |
| background | Palette/white60 | Palette/black60 |
| backgroundDisbled | Palette/black2 | Palette/white2 |
| backgroundPrimary | Palette/black100 | Palette/white100 |
| backgroundPrimaryHover | Palette/black80 | Palette/white80 |
| backgroundPrimarySubtle | Palette/black6 | Palette/white6 |
| backgroundNegative | Palette/red | Palette/red |
| backgroundPositive | Palette/green | Palette/green |
| backgroundNeutral | Palette/black6 | Palette/white6 |
| backgroundNeutralHover | Palette/black8 | Palette/white8 |
| backgroundNeutralIntense | Palette/black20 | Palette/white20 |
| backgroundSelected | Colors/backgroundPrimarySubtle | Colors/backgroundPrimarySubtle |
| backgroundSelectedIntense | Colors/backgroundPrimary | Colors/backgroundPrimary |
| Overlay | Palette/black20 | Palette/black60 |
| Input | Palette/black8 | Palette/white8 |
| InteractionHover | Palette/black6 | Palette/white8 |

### 文字 Styles 完整表

所有 24 个 Styles 绑定 fontFamily、fontSize、fontWeight 和 lineHeight 变量。字体解析值在读取时为 English 模式，Chinese 由 Typography 模式决定。

| Style 源名称 | 字号 | 字重绑定 | 行高绑定 | 基准行高 |
| --- | --- | --- | --- | --- |
| 12/400/Default | 12 | fontWeightRegular | lineHeight12 | 20 |
| 12/400/Paragraph | 12 | fontWeightRegular | lineHeightParagraph12 | 24 |
| 12/500/Default | 12 | fontWeightMedium | lineHeight12 | 20 |
| 12/500/Paragraph | 12 | fontWeightMedium | lineHeightParagraph12 | 24 |
| 14/400/Default | 14 | fontWeightRegular | lineHeight14 | 22 |
| 14/400/Paragraph | 14 | fontWeightRegular | lineHeightParagraph14 | 28 |
| 14/500/Default | 14 | fontWeightMedium | lineHeight14 | 22 |
| 14/500/Paragraph | 14 | fontWeightMedium | lineHeightParagraph14 | 28 |
| 16/400/Default | 16 | fontWeightRegular | lineHeight16 | 24 |
| 16/400/Paragraph | 16 | fontWeightRegular | lineHeightParagraph16 | 32 |
| 16/500/Default | 16 | fontWeightMedium | lineHeight16 | 24 |
| 16/500/Paragraph | 16 | fontWeightMedium | lineHeightParagraph16 | 32 |
| 18/400/Default | 18 | fontWeightRegular | lineHeight18 | 26 |
| 18/400/Paragraph | 18 | fontWeightRegular | lineHeightParagraph18 | 36 |
| 18/500/Default | 18 | fontWeightMedium | lineHeight18 | 26 |
| 18/500/Paragraph | 18 | fontWeightMedium | lineHeightParagraph18 | 36 |
| 20/400/Default | 20 | fontWeightRegular | lineHeight20 | 28 |
| 20/400/Paragraph | 20 | fontWeightRegular | lineHeightParagraph20 | 40 |
| 20/500/Default | 20 | fontWeightMedium | lineHeight20 | 28 |
| 20/500/Paragraph | 20 | fontWeightMedium | lineHeightParagraph20 | 40 |
| 24/400/Default | 24 | fontWeightRegular | lineHeight24 | 32 |
| 24/400/Paragraph | 24 | fontWeightRegular | lineHeightParagraph24 | 48 |
| 24/500/Default | 24 | fontWeightMedium | lineHeight24 | 32 |
| 24/500/Paragraph | 24 | fontWeightMedium | lineHeightParagraph24 | 48 |

### AI 回复图片

图片栏与前后文案的间距统一为 14 pt；移除图片前单独的“照片”“图片”等通用小标题，保留正文与有实际含义的标题。

独立照片使用单排方形缩略图，超出宽度时横向滚动，不换行，并按当前滚动位置显示左右切换箭头。缩略图为 220 × 220 pt，间距 8 pt；缩略图等比填满并以 12 pt 圆角裁剪。下载与来源分别固定在图片左下、右下，来源使用 MingCute link 图标，内缩 8 pt；按钮为 32 pt 原生 interactive Regular 玻璃圆形，MingCute 图标为 16 pt。来源只保留点击跳转入口，不显示额外文字。下载成功显示勾号 1.2 秒后恢复下载图标。

点击图片打开可复用的独立预览窗口：初始 680 × 560 pt，原生红绿灯、可缩放，整窗通过 `WindowSurface.glassContentView` 使用 Regular 玻璃与原生阴影。图片等比完整显示，保留边距及顶部窗口控制区；兼容与辅助功能沿用既有表面回退。

快速搜索与剪贴板历史的键盘预览共用该玻璃与图片布局。预览位于来源面板上方，标题显示文件名或剪贴板图片名称。Markdown 保留标题、列表、代码块等文档排版，正文区域独立滚动。
