# Interline iPhone 测试包

## 当前产物

- `Interline-unsigned.ipa`：iPhoneOS / arm64 真机版本，最低系统 iOS 27。
- `BUILD-INFO.json`：对应的提交、版本、构建号、平台和 SHA-256。
- 另一个 Actions artifact 提供 `.xcarchive`，便于持有签名身份的开发者后续签名导出。

**此 IPA 没有 Apple 签名，不能在 iPhone 上直接点击安装。** GitHub 授权不包含 Apple 开发者身份，也不能替代 Apple 签名。

## 只有 iPhone 时

需要持有 Apple Developer Program 账号的开发者完成分发。可选：

1. TestFlight：开发者在 App Store Connect 建立应用，使用有效签名上传并完成处理/适用的测试审核，再提供测试邀请。仅生成 IPA 不会自动产生 TestFlight 邀请。
2. 注册设备测试：开发者将测试 iPhone 的 UDID 加入设备列表，使用与 `com.interline.app` 匹配、包含该设备的描述文件和证书签名，再通过受支持的分发方式安装。

不要把 Apple 账号密码、双重验证码或证书私钥提交到源码。自动签名所需凭据应在分发方案确定后，通过 GitHub Actions Secrets 等安全配置方式提供。

## 有 Mac 时的替代方法

安装 Xcode 27 和 XcodeGen，执行 `xcodegen generate`。打开生成的工程，在 Xcode 的 Apple Accounts 中登录自己的 Apple 账号，在 app target 的 Signing & Capabilities 中选择对应 Team，连接 iPhone 并运行。按系统提示启用开发者模式。个人账号可用于个人设备开发测试，具体限制以 Apple 当前规则为准。

项目默认允许自动签名；云端未签名构建通过命令行显式关闭签名。使用自己的 Team 时，如 App ID 被占用，需要选择自己可用的唯一 bundle ID。

## 验证范围

云端检查包括 Release 真机归档、arm64 架构、iPhoneOS 平台、IPA ZIP 完整性与最低系统版本。没有证书时无法验证签名、手机安装或真机运行。原生阅读器回归测试由独立的 iOS 27 Build and Reader Tests 工作流执行。

Apple 官方说明：
- https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices
- https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices
