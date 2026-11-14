# 圆润造型与眨眼修正

日期：2026-11-14

- 原方形替换为八个圆钝外齿围成的圆形；三角重新生成为宽圆角、微凸侧边，保留原小怪物的柔软纹理与立体光照。
- 删除旧方形图片资源，加入 `AgentAvatarGear`。圆齿继续使用旧偏好值 `square`，已选中的造型无需丢弃或重新选择。
- 右侧闭眼由朝外的 `>` 镜像为朝内的 `<`，所有造型与缩略图共用此表情层。

## 实际验证

- `xcodegen generate` 通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/AvatarDerivedData build` 通过。
- `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` 通过，359 项 Swift Testing 测试。
- `codesign --verify --deep --strict build/AvatarDerivedData/Build/Products/Debug/Asky.app` 通过。
- 正常退出旧 Debug 应用，启动新构建的 `--show-agent` 调试入口；进程路径确认使用 `AvatarDerivedData` 产物。
- CUA 在实际 Asky 对话中检查紫色圆润三角、圆齿及朝内眨眼。顶部预览、造型行和表情行一致；方形选项已替换为「圆齿」。
- 检查后恢复原来的软糖／困困／紫色组合，输入草稿未修改或发送。
- 未单独重验其他外观或辅助功能设置；此次修改未增加新交互。构建产物继续由既有 `build/` 忽略规则覆盖。
