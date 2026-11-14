# 屏幕取色插件 Developer ID 签名检查

日期：2026-11-14。

状态：用户已撤回插件拆分，恢复主应用内置取色。本记录仅保留历史排查结果，不再继续取色插件的公证或分发。当前恢复验证见 [原生取色恢复记录](2026-11-14-native-color-picker-restored.md)。

## 改动范围

独立仓库 `../asky-plugin-color-picker` 的 `build.sh` 改用现有 Developer ID Application 证书 `Niall Young (V8GVW783CK)`，启用 hardened runtime 和安全时间戳，拒绝临时签名。重新构建了分发文件 `color-picker`，添加 `notarize.sh` 和中英文开发说明，公证凭据仍仅使用钥匙串配置 `Asky`。

## 实际结果

- `sh ./build.sh`：通过；`codesign --verify --strict --verbose=2 color-picker` 通过。签名团队为 `V8GVW783CK`，含 Apple 证书链、runtime 标记及安全时间戳。
- `sh ./test.sh`：通过，sRGB 转换检查完成。
- 签名后的程序通过标准输入接收只读 readback 请求，返回 `{"type":"result","value":null}`，正常退出；未打开取色放大镜，未写剪贴板。
- `sh -n build.sh notarize.sh`：通过。
- `sh ./notarize.sh`：Apple HTTP 403，团队有未签署或已过期的必需协议。没有获得公证 Accepted；错误保存在插件 `.build/notarization-submit.stderr.log`。
- `spctl --assess --type execute --verbose=4 color-picker`：拒绝，`source=Unnotarized Developer ID`。不能将签名检查通过描述为 Gatekeeper 放行。
- `xcodegen generate`：通过。常规 DerivedData 构建受其他任务的数据库锁阻断，改用 `build/ColorPickerSigningDerivedData` 完成 Debug 构建，通过。
- 常规 Debug app 深度严格签名校验通过；开发者团队为 `V8GVW783CK`。执行 `bash scripts/open-debug.sh` 后确认 Debug 进程运行路径为 `/Users/niallyoung/orca/Asky/build/DerivedData/Build/Products/Debug/Asky.app/Contents/MacOS/Asky`。

## 验证边界

取色插件仅修改了本地独立仓库；未推送或发布，也未安装到用户插件目录。取色点击、Esc 和系统弹窗是否消失未复测。整机卡死原因尚未确认。本次没有修改 Swift 源码。

Apple 协议由账户持有人处理后，需重新运行插件公证，确认 Accepted 和 Gatekeeper 检查通过，再分发及验证真实取色。

## 用户确认接受协议后的复查

用户确认已接受协议后，重新运行 `sh ./notarize.sh`，等待约一分钟再次提交，两次均仍返回同一条 HTTP 403（必需协议缺失或已过期）。`notarytool history --keychain-profile Asky --output-format json` 也返回同一错误，未能获得新的提交 ID，公证尚未进入文件分析阶段。

尝试查看开发者账户页面时，浏览器连接不可用，未能读取账户实际协议状态。尚无法区分状态同步延迟、其他待确认协议或团队选择问题；不能据此否定用户已经接受协议。需核对团队 `V8GVW783CK` 的账户协议状态，再继续公证。本轮未启动取色放大镜、未重新签名或发布文件。
