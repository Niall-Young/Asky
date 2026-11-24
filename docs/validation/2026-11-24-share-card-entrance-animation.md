# 分享卡片弹窗入场动画验证（2026-11-24）

## 变更范围

- [WindowPresentation.swift](../../App/Sources/WindowPresentation.swift)：为 `show(_:level:reveal:)` 增加可选 `reveal` 回调，让需要自定义入场动效的窗口在完成首次布局和绘制后再接管显现，不影响其余窗口既有行为。
- [ChatShareCard.swift](../../App/Sources/ChatShareCard.swift)：新增 `ShareWindowEntranceAnimator` 与 `ChatShareEntranceState`，在保持 Spotlight 式 `448 × 516` 窗口尺寸与原生阴影不变的前提下，实现窗口级 `CADisplayLink` 渐显（`160 ms` cubic ease-out）与轻缓上浮弹簧（`16 pt`，`response 0.30 / damping 0.88`），并与内部全出血背景轻缩放落位（`1.055 → 1.0`）、顶栏淡入、回复液态玻璃卡片缩放弹入（`0.94 → 1.0`）及底部四枚圆形操作按钮错峰进场（`30 ms` 间隔）同步；同时支持拖拽立即打断位移动效、亮暗切换平滑过渡，以及系统「减少动态效果」下的纯短淡入降级。
- [AgentReplyRegression.swift](../../App/Tests/AgentReplyRegression.swift)：在分享窗口回归用例中补充入场落位透明度、固定尺寸（`448 × 516`）、重开位置稳定性，以及入场中途关闭再重开无纵向漂移与透明卡死的断言。

## 实际执行与结果

1. `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData -skipPackageUpdates build`
   - 结果：通过（修改文件零新增告警）。
2. `python3 App/Tests/run-agent-reply-regression.py --share-and-user-reply`
   - 结果：通过（`Share card and user reply regression passed`，涵盖分享卡片 2× PNG 渲染、入场落位、打断重开不漂移、内部点击保留与外部点击/失焦自动关闭）。
3. `cd Packages/KulaCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
   - 结果：通过（全部测试通过，退出码 0）。
4. 视觉核查 `build/share-preview-window.png` 与 `build/share-preview-long.png`
   - 结果：通过（亮暗双模式落位清晰完整，无裁切、透明残留或位置偏移）。
