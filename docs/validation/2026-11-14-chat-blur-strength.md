# 顶部渐进模糊强度调整

- 根据用户实图反馈，将最大模糊半径从 18 pt 调低为 6 pt，保留 64 pt 范围和既有渐进遮罩。
- README 中英文与设计系统同步半径值。
- 使用实际 ProgressiveHeaderBlurView 叠在重复文字上的原生 AppKit 窗口检查；300 pt 放大测试截图 `/tmp/asky-progressive-check.png` 中，可辨文字覆盖范围增加，模糊向下逐渐减弱。素材位于临时目录，不入库。
- `xcodegen generate` 已执行；README 的 Debug `xcodebuild` 通过。
- `Packages/KulaCore` 的 `swift test` 通过，43 项 Swift Testing 测试通过。
- 没有覆盖已安装应用，用户真实历史消息的滚动观感仍待确认。
- AGENTS.md: unchanged，本次仅调整视觉参数，无新增持久规则。
