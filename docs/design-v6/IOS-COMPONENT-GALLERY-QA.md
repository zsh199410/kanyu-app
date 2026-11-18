# iOS V6 Component Gallery / 视觉验收矩阵

基于 main 66ed1d4 的独立 UI/UX Draft 分支。仅 iOS，Web、NAS 冻结。

## 实际交付
- Sources/KanyuV6ComponentGallery.swift：开发模式中的真实 SwiftUI 组件画廊，使用现有 KanyuV6Card、PrimaryButton、Design Tokens，支持浅色与深色 Preview。
- 展示原生字体层级、默认/加载/成功/失败/禁用按钮状态、来源解释、动态字号与 Reduce Motion 状态。
- 不进入 Release 导航，也不修改 PR #53 活跃文件或任何引擎计算与金标准。

## 逐页验收
- 首页/导航/命主空状态：浅深 × 标准与最大字号、切人、可触达与 VoiceOver。
- 八字/紫微/奇门：盘面文字、叠层、选中态、时间收据、术语和滚动。
- 罗盘/户型压盘：权限、可靠性、放大与硬件数据分离。
- 解盘/报告：大白话→完整原文→来源依据；逐条语音、PDF、海报边界。
- 组件/全局：按钮六态、最小 44pt 热区、减少动态、减少透明度、错误恢复与高对比度。

## 设计令牌审计
现有 iOS V6 token 包含宋纸 #F6F1E6、界面青黛 #1F4959。历史海报青黛值 #274E5C 与界面 token 不同，暂保留差异并等待视觉统一评审；不得擅自增加海报款式或删除历史数据兼容代码。

## 证据与未验证
每个检查要记录页面 ID、设备/iOS、SHA、浅深色、字号、操作前后截图、VoiceOver、问题级别、修复提交、回归结果。尚未亲自运行 Xcode Preview、真实 iOS 编译、真机读屏和 Instruments。此分支只能标为设计资产准备完成，不能标整个 App UI/UX 验收通过。
