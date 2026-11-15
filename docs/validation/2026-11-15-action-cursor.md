# 聊天操作光标修复

## 问题与修改

正文的原生 NSTextView 光标更新与 SwiftUI 悬停事件叠加时，回到底部按钮和选区浮动操作仍可能显示文本光标。仅声明 SwiftUI pointerStyle 或在悬停开始设置一次箭头，无法稳定覆盖后续原生更新。

在共用 `GlassPointerFeedback` 中加入不接管点击的原生光标区域：按按钮 bounds 与 visibleRect 的交集限定范围；在鼠标事件派发完成后合并处理，根据当前鼠标所在的本应用窗口与可见动作区域设置箭头。离开动作后让实际命中的原生视图恢复其光标。窗口移除与布局更新也重新解析当前位置；无全局事件监听、轮询或 cursor push/pop 堆栈。

回到底部按钮的现代与兼容分支、选区菜单及共用该反馈的操作均使用这一路径。没有修改布局、玻璃外观、动作或文案。

## 实际验证

环境：macOS 27.0.1，当前源码的 Debug 构建与原生 AppKit 回归窗口。

- `xcodegen generate`：成功。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build`：成功，日志 `build/cursor-build.log`。
- 在 `Packages/KulaCore` 运行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：53 项测试、12 个套件通过，日志 `/tmp/asky-cursor-core-tests.log`。
- `python3 App/Tests/run-agent-reply-regression.py --action-cursor-preview` 编译真实聊天组件及回归程序；最终同一程序以 `build/AgentReplyRegression.app/Contents/MacOS/AgentReplyRegression --action-cursor-preview` 复跑通过，日志 `build/cursor-rerun.log`。断言覆盖正文与叠加按钮的三次往返、箭头与 I-beam 切换、按钮点击一次、非 key 选区菜单的两个操作、返回正文及悬停不触发引用、不破坏选区。
- 同一回归程序运行 `--selection-preview`：通过五种配色的浅/深色选区、公式源码、真实引用动作、拖出取消、输入区焦点、去重及发送/历史恢复，日志 `build/cursor-selection.log`。
- `git diff --check`：通过。生成的工程、编译输出、探索程序与日志沿用 `.gitignore` 的现有规则，没有新增忽略项。

鼠标回归使用真实系统鼠标移动，运行期间需保持鼠标空闲。开发过程中对不稳定实现的失败断言未计为通过；最终完整回归以上述复跑日志为准。

## 范围与交付

README 中英测试命令已同步。没有在 macOS 14 真机或多显示器环境验证；没有打包发布，也没有重启正在运行的 Asky。最新本地 Debug bundle 已生成，正在运行的旧进程需重启后加载此次修改。
