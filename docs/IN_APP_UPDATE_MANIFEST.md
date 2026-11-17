# 三术合参应用内更新中心（独立分支）

## 状态
- 已实现 SwiftUI 更新页面、HTTPS 清单查询、Build 比较、IPA SHA256 校验、系统分享面板。
- 尚未挂入 App 导航；不能声称用户已可在 App 内使用。后续需在稳定的“设置”入口增加 NavigationLink，避免触碰既有 UI/QA 门禁。
- 未运行 Xcode 编译、XCTest、模拟器或真机测试；正式发布清单未配置。
- 不读取或存储签名证书；不执行 IPA 安装；仅导出供用户选择签名工具。
- 本实现仅校验 IPA ZIP 起始字节和 SHA256，**不**独立验证 ZIP CRC、Info.plist 或签名；这些仍由发布流水线执行。
- 当前版本清单只适用于可信 HTTPS 服务端。生产环境应采用可信受控域名，并进一步考虑清单签名或受控发布源以防服务器被篡改后同时替换 IPA 与哈希。

## 清单示例（仅示意，不是真实版本）
```json
{
  "version": "4.7.0",
  "build": 510,
  "minimumIOS": "17.0",
  "notes": "修复人物归属和正式海报导出",
  "ipaURL": "https://updates.example.invalid/kanyu-4.7.0-510.ipa",
  "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "channel": "release"
}
```

发布端只在同一 SHA 的 P0 CI、正式动态导出、签名与真机验收通过且获得用户发布许可后更新 release 清单。beta 清单与 release 清单必须独立隔离；当前页面未提供自动弹窗，不得宣称已实现。

## 接入步骤
1. 在独立分支选择稳定的设置页面入口，增加 `NavigationLink { KanyuUpdateCenterView(manifestURL: URL(string: "https://实际受控域名/manifest.json")!) } label: { Text("版本更新") }`，不要在旧 PR 分支操作。
2. 增加单独的更新提示状态机：首次启动不强制弹窗；仅 release 版本且用户未忽略时提示；提供“稍后再说”。
3. 运行 Xcode 编译、manifest JSON 测试、下载失败/哈希不符/HTTP 失败测试、UI 分享验收和真机文件导入验证。
4. 不得把 GitHub Actions 未签名 Artifact ZIP 直接当 IPA 下载地址；必须由发布端提供真实 IPA 的 HTTPS 直链。
