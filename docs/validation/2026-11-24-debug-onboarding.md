# Debug 欢迎引导验证

2026-11-24，以源码版本 `d6d5ec0` 执行 `xcodegen generate` 并构建 Debug，构建成功。构建产物位于 `build/DerivedData/Build/Products/Debug/Asky.app`，通过 `codesign --verify --deep --strict`。

重新启动该副本并传入 `--show-onboarding`。实际窗口显示“你好，欢迎使用 Asky”。点击“开始设置”后进入“开启常用权限”，辅助功能和 Chrome 书签均显示“已开启”。点击“上一步”回到欢迎首页。本次验证覆盖前两页的往返导航。
