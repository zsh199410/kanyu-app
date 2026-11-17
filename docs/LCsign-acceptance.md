# LCsign 真机兼容性验收（PR #84）

用户当前使用 LCsign，优先采用 iOS 系统分享面板，不猜测第三方 URL Scheme。

## 验收步骤
1. 先在测试清单中提供由用户批准、已核验 SHA256 的未签名 IPA；不得将 GitHub Artifact 外层 ZIP 当成 IPA。
2. iPhone 上进入「版本更新」，下载后选择「分享 IPA 至签名工具」。
3. 在系统分享面板检查 LCsign 是否显示为可接收目标。若显示，选择并确认 LCsign 能导入原始 IPA；如果不显示，尝试「存储到文件」后从 LCsign 文件导入入口选择该 IPA。
4. 对比 LCsign 接收文件的字节数和 SHA256（如果 LCsign 不提供校验，至少核对源文件哈希及导入成功），记录 iOS 版本、LCsign 版本、截图、失败提示。
5. 只有用户明确批准签名后才进入签名和安装；检查证书/描述文件适配和 App 原有数据是否保留。不得把导入成功写成安装成功。

## 禁止事项
- 不预设 LCsign 的 URL Scheme、Universal Link 或分享扩展一定存在。
- 不在应用中收集、上传或缓存 P12、mobileprovision 或证书密码。
- 不强制更新、不自动安装、不跳过 SHA256 校验。
- 未经真机验证，状态必须保持 BLOCKED。

负责人：GPT 实现与审查；Muse 仅协助提供 Mac/iPhone 运行、LCsign 导入结果和原始证据。
