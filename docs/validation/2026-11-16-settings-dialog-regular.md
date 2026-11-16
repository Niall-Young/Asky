# 设置表单弹窗恢复 Regular 玻璃

## 范围

- 修正上一次擅自替换玻璃材质的问题。添加插件、添加／编辑别名与插件配置全部使用共享 SettingsDialog 的原生 Regular 玻璃，不叠加实色底板、自绘描边或额外阴影。
- 保留完整设置窗口居中、16 pt 圆角、24 pt 内距与既有表单宽度；插件配置从原生 sheet 迁入同一窗口级呈现容器，保留保存、取消和错误反馈，并支持关闭按钮与 Esc。
- 按用户要求移除添加插件输入框下方的信任仓库说明。
- 原生系统确认框、系统权限和文件选择面板继续由 AppKit 提供。

## 运行实例核对

用户再次提供的右侧居中别名弹窗来自 `/Applications/Asky.app` 的旧实例（PID 48783，窗口 8485）；同时核对的 Debug 实例（PID 50605，窗口 8434）已显示完整窗口居中的 Regular 玻璃别名弹窗。前一轮留下多个同名实例，使交付结果混淆。后续展示必须核对进程完整路径与当前窗口，不能仅打开一个 Debug 副本就认定用户看到的是新版。

## 验证

- `xcodegen generate` 与 README 的 Debug `xcodebuild`：通过。
- 核心 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`：通过。
- 实际 Debug 插件添加窗口：已查看截图，确认 Regular 玻璃、全窗口居中及说明文字移除；实际 Debug 别名添加窗口：已查看截图，确认共享材质与居中位置。
- 首次附加原生回归曾受另一处并行构建覆盖 `.o` 产物影响，改用 `build/DialogsVerificationDerivedData` 快照隔离验证；一次菜单测试因 SwiftUI 延迟创建原生菜单未能获取菜单项，改为实际配置编辑器的独立原生窗口验证。

- `ASKY_DERIVED_DATA=$PWD/build/DialogsVerificationDerivedData python3 App/Tests/run-settings-regression.py --plugin-tabs`：通过，包含添加插件、别名与插件配置的全窗口居中、取消清理，以及既有插件搜索和分类回归。插件配置使用实际编辑器与共享呈现器、隔离测试数据，未验证真实插件配置写入。
- 最终通过 Computer Use 在最新 Debug（PID 53393）逐一打开添加／编辑别名，查看真实截图，确认完整窗口居中、Regular 材质和取消关闭；没有修改已有别名。最终留在添加别名窗口供用户查看。
- `git diff --check`：通过。

日志、截图、验证 DerivedData 均沿用已有 `build/` 忽略规则，不提交构建产物。没有执行真实插件安装或配置保存。
