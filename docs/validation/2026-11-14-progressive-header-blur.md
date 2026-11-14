# 顶部渐进背景模糊与 Clear 玻璃一致性

- 头像与右侧胶囊统一使用 `nativeGlassBackground(clear: true, glassOpacity: 0.35)`；之前头像直接使用完整 `.clear`，导致折射强度不同。头像菜单继续沿用 Regular。
- 顶部 96 pt 背景采样层使用可变半径模糊：顶部 18 pt，向下渐进至零。无颜色填充、透明度渐隐或正文截图；正文不经过整层滤镜，输入区、按钮和头像保持清晰。
- 降低透明度时隐藏该装饰层，不阻断交互。

## 验证

- `xcodegen generate`：通过。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：通过。
- Packages/KulaCore 中 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- 用实际新编译组件建立条纹原生窗口，确认模糊只覆盖局部，其余条纹保持清晰。
- 重启并检查 `build/DerivedData/Build/Products/Debug/Asky.app` 实际聊天窗口：顶部强到弱的模糊生效，正文恢复清晰，头像与胶囊使用一致的玻璃参数。中途实现验证过滚动及头像菜单；最终画面验证后用户正在操作应用，未继续干扰交互，也未提交消息或修改用户草稿。
- 构建和临时预览均在现有忽略目录 build/；未改忽略规则。

## 实现与范围

`CABackdropLayer` 与 `CAFilter(variableBlur)` 是动态获取的系统未公开合成接口。当前系统实测可用；类或滤镜不可用时不添加此装饰。未验证其他 macOS 版本，也未对系统未来变更或 App Store 审核做保证。

尝试过公开的 Core Image 背景滤镜和整层正文滤镜：前者无法采样 SwiftUI 后方内容，后者影响正文清晰度；自定义组合滤镜产生白屏。最终实现已移除这些尝试，不改变正文宿主结构。

README 中英文和设计规范同步；AGENTS.md 的开发命令、架构边界与指南未变。
