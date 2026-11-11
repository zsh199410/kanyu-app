# 三术合参 DesignSystem V6 · Oriental Precision
基线 main: 1ae6503994940414ab31afb4906cb7b32d291d82。设计规范版本 V6.0，尚未通过 Xcode 编译或视觉截图验收。

## 原则
宋纸青黛（日间）与玄夜精仪（夜间）；保持系统 Dynamic Type、VoiceOver、Reduce Motion、44pt 最小触达。避免实时列表高斯模糊。专业罗盘可强制深色，但文字对比必须测试。五行色需配文字/图形双编码，不以颜色推断可靠性。禁用未经来源支持的“预测准确率”或“能量百分比”。

## 精确 Token
浅：背景 #F6F1E6，卡 #FCFBF7，正文 #2B2723，主操作 #1F4959，朱砂 #9A2A22，雅金 #9E782F。
深：背景 #111317，卡 #1A1D23，正文 #F2EBDD，主操作 #6CA2B8，金 #D1AC53。
页边 20pt，卡距 15pt，卡内 16pt，连续圆角 18pt，按钮 14pt/52pt，最小触达 44pt；描边目标 0.7pt，实际按设备像素对齐。标题 serif 28pt、卡标题 serif 19pt、正文 16pt、辅助 14pt；数字 monospacedDigit，不得用千分位格式化年份。按压 0.985、180ms；转场 280–360ms；Reduce Motion 禁止位移动画。

## P0–P5 分阶段（每阶段独立可回滚 PR）
P0 基线与安全：逐项核查 PR #40、数据恢复、人物隔离、Swift 6 告警；保存原始 iPhone 截图（浅/深/大字号）、Web 断点截图、可访问性树和性能基线；不合并失败 CI。绝不改底层排盘算法、Tests 或金标准 JSON。
P1 Token 与组件：接入 Sources/DesignSystemV6.swift，新增 V6ThemeEnvironment、V6Card、V6PrimaryButton、V6SectionHeader、V6StatusBadge；替换界面局部硬编码色，不改变存储键或业务状态。Web 增加 app/static/design-tokens-v6.css（路径需核对现有 Web 构建系统），通过 CSS variables 实现同语义 token。
P2 首页与人物：从 Sources/KanyuApp.swift 的首页视图提取 UI 容器；命主卡、历法卡、四大入口、最近使用、全部工具；空档案保留真实建档门禁，禁止以 Date() 伪造出生时间。所谓五维气运没有可追溯计算来源时不显示分数。
P3 专业盘：八字细盘 bottom sheet、紫微宫位选中与三方四正、奇门九宫；交互只读既有引擎结果，禁止 UI 自行推断流派、宫位、吉凶；缺少规则原文不生成伪古籍引文。解释统一为结论—本盘事实—规则—白话—适用范围—回验。
P4 堪舆/罗盘：CompassModule.swift 的深色精密仪器皮肤、精度/磁偏角来源可见、锁定门禁保留；户型图层使用 transform/opacity；无定位、无效校正或低水平磁场显示明确降级，不以视觉效果遮蔽风险。
P5 海报/PDF：PosterModule.swift、PosterEditorModule.swift、PalmModule.swift 与实际报告导出路径逐项确认后实施；1080px 宽长图、至少 28px 安全边距、长文本测量与分页、图片失败和写盘失败可见；PDF 自动目录/章节页眉页脚，版本和来源脚注；不伪造防伪认证。

## 页面与失败态验收
首页：无命主/切换/删除/恢复；个人中心：取消建档不写入；八字/紫微/奇门：不同流派与不确定性可见；罗盘：权限拒绝/非有限输入/校正变化/低磁场；报告：长文本/缺图/存储满/分享失败；Web：320/375/430/768/1024/1440px。
每个新增组件必须具备正常、加载、空、错误、禁用和成功反馈（适用时），VoiceOver 标签、Dynamic Type、Reduce Motion 验证。
P1 起每批需真实 XCTest、XCUITest、设备 Release、产物 SHA/CRC 与截图人工审查；无匹配 SHA 的产物不得交付 IPA。目标 120Hz 不等于已达成；必须使用 Instruments 测量滚动掉帧、内存与 GPU。
## 回滚
每批独立分支、独立提交；git revert <commit>；不改 Tests 和金标准 JSON，不执行破坏性数据迁移，不覆盖用户资料。设计 token 本次仅新增文件，尚未接入构建/运行，不宣称已经改变 App 外观。
