# 三术合参 iOS · 宋纸青黛画报 & 命书 PDF 自主排版方案

版本：2026-11-12 / 研究版 r1。独立分支 design/ios-poster-pdf-layout-20261112，从 main@66ed1d4 派生。此文件只覆盖 iOS App 的版式与文件分享体验，**Web、NAS、PR #25、G14 v1.3 全部冻结**。

## 一、外部调研与决策

1. **Apple UIKit UIGraphicsPDFRenderer**：既有 PDF 使用该框架是合理底座；支持多页输出、保存文件、文内链接等，不需要换成 HTML 截屏生成 PDF。长文宜使用 TextKit 或 Core Text 排版。来源：https://developer.apple.com/documentation/uikit/uigraphicspdfrenderer
2. **PDFKit PDFView**：有现成的缩放、文字选择、页面导航与复制能力；应建立原生文件预览，而不是另写不支持选中文本的 PDF 缩略屏。来源：https://developer.apple.com/documentation/pdfkit/pdfview
3. **Apple HIG Activity Views + SwiftUI ShareLink**：系统分享菜单是 iOS 的首选文件导出入口；文件已生成才启用分享，而不发一个尚未落盘的 URL。来源：https://developer.apple.com/design/human-interface-guidelines/activity-views 和 https://developer.apple.com/documentation/swiftui/sharelink
4. **Apple 无障碍与 Dynamic Type**：App 内列表、预览控件应支持最大字号和 VoiceOver；PDF 作为固定版式文件另需文字可选择、阅读顺序与结构可访问性专项验证。来源：https://developer.apple.com/design/human-interface-guidelines/accessibility
5. **PDF Association PDF/UA**：可访问 PDF 不等于“能复制文字”；正确语义标签、标题层级、阅读顺序等也重要。现有 UIGraphicsPDFRenderer 没有经验证的结构标签支持，**不得宣传已达到 PDF/UA-1/2**。来源：https://pdfa.org/resource/tagged-pdf-q-a/
6. **视觉参考**：古籍编排重版心、识别性章题与低噪声装饰，现代信息图重层次、解释与数据可追踪。仅借鉴“版面纪律”，不复制特定现代作品的画面、纹理或插画。参考：湖北省图书馆国家珍贵古籍展（https://www.library.hb.cn/resource/zxzl/202411/t20241127_14625.shtml）、西安美院石鼓信息可视化（https://xafa.meishu.org.cn/arts/2005-113066.html）。

## 二、从当前源码确认的事实，避免旧规格误判

- \`PosterModule.swift\` 的画报宽 540pt × 2 = 1080px；PosterEditor 使用 ImageRenderer 与稳态写盘，ReportCenter 有图片/PDF 历史入口；**不换掉既有导出管线**。
- \`PosterStyle\` 仍保留 songQingdai/yuceDan/zhusha/xuanye 四个历史 enum，\`PosterEditorView\` 的 Picker 当前遍历 \`allCases\`。这与用户“仅宋纸青黛一种可选海报”的产品要求冲突。整改时只收敛可见款式入口，尊享预测单独立产品，**旧 enum/后缀保留用于历史文件兼容**。
- \`ReportModule.swift\` 已使用 CoreText 的 \`CTFramesetterCreateFrame\` / \`layoutFragments\` 对超长段落做可见范围拆分，标题与首段有部分防孤立策略。**旧 EXPORT-SPEC 里“整段为不可拆原子”的描述已过时，不能推倒重写**。
- PDF A4 595×842pt，48pt 外边距、499pt 正文宽；当前第 2 页固定为目录，正文页码 = 相对正文页码 + 2；\`drawFooter\` 位于 y=812。
- \`drawTOCItemCell\` 对标题实测高，却以 **16pt 固定行距**移动 y；长标题可能压到下一行。目录本身也固定一页，随着章节数增多可能溢出。这是待真正构造长条目样例验证的具体排版风险。
- \`ReportCenterView\` 目前以人员**姓名**过滤和分组，同名人物可能混在一起，且生成的 PDF/PNG 不包含在人物 ZIP 备份中。此问题由数据可靠性工作流跟进，不能以重排 UI 暗中迁移原数据。
- 现有完整报告文本、内容 hash、tier、engineVersion、文件名约定、历史后缀及 golden JSON 原样保留。

## 三、唯一海报款式：宋纸青黛精装长卷

**画布合同**
| 字段 | 定稿 | 说明 |
| --- | ---: | --- |
| 逻辑画布 | 540pt | 全部 PNG 宽一致 |
| 输出倍数 | 2 | 1080px，无损 PNG |
| 版心左右 | 32pt | 实际内容宽 476pt |
| 内框 | inset 17.5pt, stroke 0.5pt | 内沿 x≈18pt |
| 内容对内框距离 | 14pt = 28px | 不允许压边框 |
| 页首/页尾安全区 | ≥36pt | 包含章题与版本印鉴 |
| 章际距 | 20pt | 同章子块 12–14pt |
| 标题 / 章题 | 26–30 / 18pt | 中文衬线，无描边发光 |
| 核心结论 / 正文 / 依据 | 17 / 14 / 11.5pt | 增高不截字 |

**阅读顺序**：品牌与低噪声宋山线描 → 人物姓名/生辰/经度/时区收据 → 四柱或实测盘面 → 先看结论（大白话）→ 原始详细解读 → 已有时段与行动提醒 → 依据分级/原文出处核实状态 → 版本、生成时间和内容指纹。

**视觉规则**：宋纸 #F6F1E6 / 内容底 #FCFBF7 / 主墨 #2B2723 / 界面青黛 #1F4959。旧海报历史青黛 #274E5C 的取舍作为设计评审问题，不在这一纯概念 PR 里改生产 Tokens。朱砂 #9A2A22 **只用于少量字章/警戒，不是第二套海报皮肤**。传统式线描不压字，不复制特定文物作品。长姓名允许换行，五行/星曜图例必须颜色+文字双编码，未提供字段不补造数据。

**长卷与性能**：只固定宽，段落自然增高；预估 \`pixels.width × pixels.height × 4\` RGBA 内存并留多缓冲余量，超过实际设备安全阈值时降级为按章连续多 PNG 或 PDF，保留原全部内容，不静默截断。不以固定 8000px 当绝对上限。ImageRenderer 始终在 MainActor，状态显示准备/渲染/写盘/成功/失败/取消/重试。

## 四、PDF：A4 册页式专业命书

**版心**：A4 595×842pt，正文左右 x=48…547；上 y=48，下 y=794；页脚 y=812。正文无大幅背景纹理，打印可读；章题 18pt，次级 14pt，正文 12–12.5pt，来源 10–10.5pt；中英数字等宽/字号稳定。标题和首段至少同页；单条超过页高，保留现有 CoreText 拆分，优先修复目录自适应和超长条目。

**产品结构**
1. 封面：产品名、当前命主、输入收据、档位、生成日期、内容 hash 简码、口径版本；没有真实机构认证文案。
2. **第 2 页必须是目录首页**：保留当前测试合同；先核对正文页和页码，再排目录。若目录多于一页，目录可继续向后续页扩展，但需统一修正正文绝对页偏移且保证原有第 2 页目录断言。
3. 正文：每章“本章一语概览 → 结果全文 → 盘面事实 → 传统解释/来源等级 → 实际适用范围”。大白话层可以增加，不替换或改写已有报告全文/哈希输入。
4. 附录：术语、演算输入、可追溯版本及章节来源；“用户已应验”与已核来源不能混写。
5. 页脚：简版与完整版保持档位一致的页码与版本， PDF 文本可搜索、可选择。

**禁止**：把 PDF 压成一张张 PNG；改动报告正文字符串、时间/年柱、流派算法、已有 PDF 测试断言、engineVersion/contentHash 生成逻辑；删旧历史文件。PDF/UA 必须由专门工具检测语义结构后才能宣称符合。

## 五、导出与下载 UX（仅 iPhone App）

- 结果页右上角及底部同一操作入口：“预览”→ “保存到文件/分享”（系统分享面板），图片另保留“存储到照片”。保持本地数据不上传。
- 预览显示格式、尺寸/页数、预计大小、人物、生成时间、档位，保存时先写成可复用持久文件再触发 \`ShareLink(item: URL)\`；不再使用模糊的“下载中”描述本地导出。
- 后台/权限/空间不足时显示失败原因与重试，失败不清空上一次已验证文件；重复点击对当前生成请求去重，不回用不同人物的缓存。
- 生成成功后可在报告中心按文件类型筛选与预览。涉及真正的人物 UUID 归属和历史文件迁移时交给工作流 B 单独设计/验收，不在视觉 PR 混改。
- 不设置强制水印、二维码、随机评分、付费推广标记。

## 六、分阶段落地与门禁

**本 PR 仅研究 + DEBUG 样张，代码尚未接入真实导出。** 后续建议拆三批：
- A：单款海报的视觉度量/内容结构 + 真实 1080px 导出回归（只改与 PR #53 不重叠的部分；等待 PR #53 稳定后再决定 PosterEditor 改动）。
- B：PDF 目录自适应、字体、章节边界 + 4/14/26/极端长段真实 PDFKit 验证，原文哈希不变；单独 Draft PR。
- C：iOS Preview/ShareLink/存文件的状态与历史兼容，人物 ID 归属门禁交由数据工作流负责。

每次提交都需：精确 SHA 的 Xcode 原生 Release + 原有 XCTests/UITests + 11 项历史 PNG + 三档 PDF 文字/页边距/目录/CRC/SHA256 + iPhone 深浅、VoiceOver 和超长姓名截图；新增极端样本不弱化旧断言。

**目前未验证**：DEBUG 样张是否可编译、实际 PDF/PNG 视觉输出、目录极端页数、系统文件分享、真实设备缓存/签名安装、PDF/UA 标签、同名人物隔离与备份；此工作不代表“导出升级完成”。
