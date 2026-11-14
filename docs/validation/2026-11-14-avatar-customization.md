# 紧凑头像配置验证

日期：2026-11-14

## 实现

- 顶部 36 pt 头像展开为 260 × 340 pt 玻璃面板，80 pt 预览与三组横向配置；五种造型、四种表情、五种颜色独立组合。
- 选择即时预览并写入现有 SettingsPreferences；点击外部或 Esc 收起。不含命名、上传、保存按钮或制作说明。
- 原小怪物微笑使用原图，其余表情使用无表情底图加覆盖层；其余四种造型使用参照原图生成的同材质透明底图，表情使用共享覆盖层；发送按钮、消息染色与选区沿用共享头像配色。
- 旧偏好缺省造型与表情为原小怪物／微笑；五种原有配色均原样保留。

## 验证状态

首轮实现错误地缩减了配色、移除了原头像，并让表情缩略图固定使用圆形。用户指出后恢复原头像与五色，将两组缩略图改为保留当前其他配置的组合预览。用户进一步指出新增造型的平面矢量材质不匹配，已重新生成四种同材质底图并删除矢量身体渲染。之前的验证不作为最终素材版本的验收依据。

## 最终版本已执行

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/AvatarDerivedData build`：通过。独立构建目录避免其他并行任务覆盖产物。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过，351 个 Swift Testing 测试。
- 原生预览沿用 README 的 `--avatar-preview` 入口。因其他任务持续修改共享源码，最终运行采用 `build/AvatarPreviewSource` 中的源码快照及 `ASKY_DERIVED_DATA` 指向上述独立产物。该快照成功编译并显示实际 AgentWindowController。进入窗口前的断言覆盖缺省设置解码、五色保留、造型/表情分别保存及同一磁盘目录重建 AppModel 后恢复。
- CUA 在新构建的原生窗口并排检查五种造型：原小怪物保留，新增正圆、方形、三角、幽灵均显示柔软纹理和立体边缘，不再出现平面纯色身体。
- 点击方形：顶部预览与整行表情均变为相同材质的方形。点击墨镜：造型行均保留墨镜。切换黄色：顶部、造型行与表情行统一切色，发送按钮同步更新。
- 恢复小怪物／微笑／蓝色，点击外部再打开，三组选中项保持一致；输入框既有草稿未被更改或发送。
- 新增透明底资产均保留 alpha；原 `AgentAvatar` 未修改。原生组件按透明边距校准图形大小，所有表情共用覆盖层。
- `git diff --check` 与新增本地化键唯一性检查通过。

## 范围与限制

最终材质在隔离数据的原生预览窗口中验证，未替换系统已安装 App。未单独验证浅色外观、VoiceOver 和系统减少透明度。中间版本的键盘测试曾被 CUA 服务超时中断；最终版本不据此声称键盘回归通过。预览与构建快照均在现有 `build/` 忽略规则下。
