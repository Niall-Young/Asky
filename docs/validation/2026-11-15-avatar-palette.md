# 头像黄色与色块一致性修复

- 原因：头像通过蓝色资产的 `hueRotation` 近似换色，颜色选项直接使用固定 sRGB 色板；两者没有共用最终底色，黄色呈灰褐色。
- 修复：黄色、紫色、绿色、粉色直接以 `AgentAvatarColor.tint` 为底色，原图去色后以 Overlay 混合保留明暗与纹理；黄色底色为 `#F1CB62`。独立表情层保留深蓝色，不随身体换色。默认蓝色素材和原始蓝色微笑小怪物保持原样。
- 明暗纹理使身体高光与阴影不会每个像素都等于纯色色块；主体配色现在来自色块本身。

## 实际验证

- `xcodegen generate`：成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：成功。
- 在 `Packages/KulaCore` 执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：退出码 0，所有测试通过。
- 原生预览直接编译当前 `AgentMonsterAvatar.swift`、玻璃组件和图标组件，使用新构建的资产目录。展开实际 `AgentAvatarPicker`，检查黄色圆齿墨镜组合与四种表情缩略图；同时对照五色 × 五造型与色块。黄色不再偏灰褐，表情、轮廓与纹理可见。
- 临时驱动和截图：`build/avatar-color/run.py`、`build/avatar-color/Preview.swift`、`build/avatar-color/preview.png`。复用已有 `build/` 忽略规则，不提交构建产物。
- 本轮未安装或重启用户正在运行的 Asky。
- README: unchanged。本次为既有颜色选择的显示修复，使用流程、命令与能力无变化；未修改其他任务正在编辑的 README。
