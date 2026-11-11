# V6 导出与专业仪器视觉实施规范

定稿方向：纸上有秩序，仪器有精度，玻璃只服务导航。所有结论、计算、宫位、年份与可信度均读取既有模型，不在视觉层重新推导。本文件为源码核查后的实施规格，未宣称完成截图验收、真机性能测试或全部变体落地。

## 1. 已核实的代码与边界

| 面向 | 实际源码/组件 | 当前状况 | V6 改动位置 |
| --- | --- | --- | --- |
| 八字/预测单长图 | `Sources/PosterModule.swift`：`PosterStyle`、`PosterPalette`、`PosterView`、`YucedanPosterLayout`、细盘表 | 样式枚举只有 `songQingdai` / `yuceDan`；两者共用一套浅色调色；画布 540pt，高度随内容；渲染 scale 2 | 调色、布局、装饰与渲染分发；不改任何结论生成函数 |
| 海报编辑/保存 | `Sources/PosterEditorModule.swift`：`PosterAccent`、`PosterEditorView`；`PosterPhotoSaver` | 标题/副标/强调色可编辑；`ImageRenderer` 在 MainActor；相册结果有文案 | 变体、预览、字号/长名字溢出和导出状态；保持本地保存及权限行为 |
| 紫微/合参长图 | `ZiweiPosterView`、`ZiweiMiniCell`、`ZiweiCenterFlyLines`、`HeCanPosterView` 及各 sheet | 已有十二宫/中央飞线与合参布局；部分宫格使用固定 107×92pt；海报总宽仍为 540pt | 重排宫格/续页详批，继承实际宫位及四化；不重算安星或飞化 |
| PDF | `Sources/ReportModule.swift`：`ReportBuilder.makePDF`、`paginate`、`drawCover`、`drawTOC`、`drawFooter` | A4 595×842pt；48pt 页边距；封面 1、目录 1、正文若干页；章节与条目目录共用分页结果 | 只改渲染、排版与分页；保留 `lines()` 内容、档位、内容哈希和引擎口径 |
| 报告历史 | `Sources/ReportCenterView.swift`：`ReportHistory.scan`、文件名解析 | 扫描 `命书-*.pdf`、`poster-*.png`、`ziwei-poster-*.png`、`hecan-poster-*.png` | 新变体须继续被识别；旧后缀及旧文件必须继续可读 |
| 户型压盘 | `Sources/FloorPlanOverlayView.swift`：`FloorPlanOverlayView`、`palaceOverlayCell` | 压盘区域 310pt 高；九宫约 290×290pt；导图、中心拖拽与 0.55 初始透明度；状态目前以视图内 @State 为主 | 工具栏、仪器配色、交互反馈、视觉变换与状态呈现；不改坐向或飞星算法 |
| 罗盘 | `Sources/CompassModule.swift`：`CompassStandaloneView`、`dial(size:)`、`lockCard`、水平仪/采样反馈 | 已有恒深 `Ky.instBg`、Canvas 刻度、缩放/旋转手势、真磁北和来源显示 | 仪器层次、读数层级、点击热区、低频触感；不改 Resolver、采样收据、校正与锁定门控 |

**Web 核查**：`kanyu-app` 主分支与 `origin/design/v6-oriental-precision-20261111` 均未找到 HTML/CSS/JS/TS/React/Vue/package.json 或 Web 目录。账号公开/授权可见仓库清单（`gh repo list zsh199410 --limit 50 --json name,description`）仅见 `kanyu-app`、`BaZiMingLi-iOS`、`openwrt-n305-builder`、`pxxl-node`、`hdhd`；没有可确认的三术 Web 仓库。`InsightModels.swift` 的注释提到 Web 端字段与历史文件名，不能据此断定那些文件存在于当前仓库。因此 Web 的色彩/CSS/组件规范只能作为待接入合同，不得写成已修改了真实 Web 页面。

## 2. 1080px 长图几何合同

所有基础长图以 **540pt 逻辑宽 × scale 2 = 1080px** 输出；预览尺寸与导出逻辑尺寸分离。高度由内容自然测量，不设固定总高度，不用 `lineLimit` 裁掉结论。

| 坐标项 | pt | 导出 px | 规则 |
| --- | ---: | ---: | --- |
| 画布宽 | 540 | 1080 | 禁止各变体独立改宽 |
| 外框离画布边 | 12 | 24 | 外框横向范围 x=12…528 |
| 内框离画布边 | 18 | 36 | 内框横向范围 x=18…522 |
| 主内容离画布边 | 32 | 64 | 正文横向范围 x=32…508 |
| 内容距内框最小空白 | 14 | **28** | 满足用户提出的至少 28px；注意 28px 是 14pt，不是 28pt |
| 主内容最大宽 | 476 | 952 | `540 - 2×32` |
| 内容上下安全边距 | 36 | 72 | 从内框至首/末字至少 18pt； footer/印章计入内容高度 |
| 模块间距 | 14 / 20 | 28 / 40 | 同章子块 14，章节切换 20 |
| 细盘标签列＋尾距 | 44＋6 | 88＋12 | 共 50pt；不挤占四柱文本区 |
| 四柱每列 | **106.5** | **213** | `(476 - 50)/4`，四列与标签合计正好 476pt |

屏幕卡片 0.7pt hairline 与海报像素边框分开管理：海报细线建议 0.5pt（2× 导出为 1px），强调外框 1pt（2px）；主 App 卡片继续服从全局 0.7pt。边框使用 inset/strokeBorder 或向内描边，不能让描边半宽侵出安全区。

### 当前源码实际检查

- `PosterView` 的框线有 `.padding(22)`；预测单多数正文使用 `.padding(.horizontal, 32)`。仅看 x 差值，22pt 内框与 32pt 正文之间只有 10pt=20px，**不足新合同要求的 28px**。这属于几何预算不一致，不是已确认每张图都发生视觉压线。
- 专业细盘当前标签 44pt＋尾距 6pt＋四列各 108pt，合计 **482pt**。采用新内容宽 476pt 后会超预算 6pt；必须同步改列宽至 106.5pt，不能只收紧外边距。
- 标准海报部分内容为 444pt、五行轨道 364pt；预测单大量固定 32pt 边距；紫微小宫格固定 107×92pt。应先引入单一 `PosterMetrics`，逐一换算，不做全仓盲目替换 `.padding(32)`。
- 现有 `Tests/PosterLayoutTests.swift` 只验证既有四种布局输出宽为 1080px、图高大于宽，并不证明所有字都不压线、所有极长姓名都可读。用户要求本轮不改 Tests，应保留并运行这些现有检查，再另留导出图片人工/工具测量证据。

建议新增纯视觉度量 `Sources/PosterMetrics.swift`：`canvasWidth=540`、`renderScale=2`、`contentInset=32`、`contentWidth=476`、`outerFrameInset=12`、`innerFrameInset=18`、`detailLabelWidth=44`、`detailLabelGap=6`、`detailColumnWidth=106.5`。不在此文件出现任何排盘或打分公式。

## 3. 海报矩阵与稳定命名

样式选择、内容组合与资料档位分开：同一组 `BaziChart`/`ZiweiChart`/既有解释数组，只改变 palette 与版式。主题不影响结论、五行占比、四化、年份、内容指纹。

| 产品 | 定稿视觉与阅读顺序 | 预计实现对象 | 输出标识 |
| --- | --- | --- | --- |
| 宋纸青黛 | 册页抬头→人物/输入收据→四柱→五行→核心结论→详批→依据与版本印鉴；竖排仅用于品牌和短章题，长段落横排 | 现有 `PosterView` 作为内容骨架，抽出 `PosterHeader` / `PosterSection` / `PosterFindingBadge` | **保留 `-song`** |
| 尊享预测单 | 太极小标→输入收据→细盘→五行/雷达摘要→详批→时间层→行动建议→依据/版本；长卷分节，不固定总高 | 保留 `YucedanPosterLayout` 分支，先替换统一 metrics，再分拆小视图 | **保留 `-yucedan`** |
| 宣纸朱砂 | 同一内容骨架；象牙/米白底、墨字；朱砂只用于标题、印鉴、重点；金色为边框与图例 | 扩展 `PosterStyle` 与 `PosterPalette`，复用标准结构 | 新增稳定 `-zhusha`，不改旧枚举 rawValue |
| 玄夜墨金 | 黑曜石底、墨玉分区、米白正文、香槟金路径、青黛数据；控色避免所有字都发金光 | 同一内容骨架的深色 palette；导出明确固定 dark 环境，不跟随当前手机主题 | 新增稳定 `-xuanye` |
| 紫微全景 | 十二宫完整方盘→图例/四化→三方四正摘要→按实际已有卡片的解释；宫格字太多则把深读放后续段落，不挤格 | `ZiweiPosterView`、`ZiweiMiniCell`、`ZiweiCenterFlyLines` | **保留 `ziwei-poster-` 前缀**；以真实选择的 style 添加上述后缀 |
| 双术/多术合参 | 同题对照卡→各术实际依据→一致/分歧/条件；只展示既有裁决，不把同源描述伪装独立验证 | `HeCanPosterView`，沿用 `BaziZiweiCrossEngine.verdicts` 的只读结果 | **保留 `hecan-poster-` 前缀** |
| 命书 PDF | 封面→输入/口径收据→目录→正文分章→依据/术语附录→版本说明 | `ReportBuilder` 绘制函数与布局器 | **保留 `命书-` 前缀、档位、日期和哈希后缀** |

新增 enum case 后必须同步所有 `switch`、palette、`fileSuffix`、编辑器选择器、紫微/合参渲染器和报告中心后缀解析。已有 rawValue/文件名不能重命名，旧图片与 PDF 不迁移、不删除。报告中心先保留所有既有识别逻辑，再增加新后缀，不以“换设计”为由让历史文件消失。

“防伪红印”定稿为**版本印鉴＋内容指纹**。现有内容哈希只帮助识别内容变化，不能标成官方认证、预测正确证明或密码学防伪。印章文字不冒用机构、奖项或大师认证。

### 视觉参数

- 海报名称 26–30pt 衬线，副题 12–14pt，章题 16pt，主结论 15–17pt，正文 12–13pt，依据/来源 10–11pt；关键数字全部等宽。适当提高正文后，允许卷长增加。
- 标准卡圆角 10–12pt（导出不必套 App 18pt），标签圆角 5–6pt；强调标签至少 22pt 高。✓/× 同时配“条件支持/条件不足”等文字，不能只有颜色。
- 关键徽章只使用已有有效字段。没有贵人属相、吉祥数字等依据时不凭视觉需要补造；空字段显示“未提供”或隐藏该块，不填零分/随机值。
- 星曜与五行双编码：颜色＋名称/元素字＋图例；星曜不使用同一套“能量高低”去替代亮度、四化、得失等不同字段。

## 4. 动态文本与大图导出

1. 容器只固定逻辑宽，不固定段落总高。正文 `fixedSize(horizontal:false,vertical:true)`；多行先排版再测高，不在长结论上使用缩小字号/省略号。
2. 姓名、关系、长干支解释分别测量；极长名称可分两行/三行，普通字段可增高。竖排章题不承担长姓名、年份或英文片段。
3. 十二宫小格先留宫名/地支和核心星曜，辅星长列表移至同宫续段，保留显式“详见本宫说明”。不能删除星曜或硬截显示来满足固定 92pt 高度。
4. 避免一张极长 SwiftUI 视图制造巨型位图；预览用降采样结果。导出前计算 `width×height×4` 的原始内存预算，预计超预算则提供自然分章的“多张长卷”或 PDF，而不是等到进程被杀。
5. 1080px 是确定的导出宽度；不承诺不受限制的单图总像素数。导出 UI 显示生成/失败/重试/完成，用户取消后停止后续章节。相册成功以 PhotoKit 回调为准。
6. `ImageRenderer` 创建、环境注入和读取 `uiImage` 必须在 MainActor；图片编码/写盘只有在确认数据可安全跨隔离边界后才转后台。不能为追求流畅再次使用后台 Task 操作 SwiftUI renderer。
7. PNG 导出背景是 palette 的实色，不依赖屏幕毛玻璃采样；屏幕“玻璃”不进入平面文档。可导出深色艺术版，但 PDF 正文默认采用适合打印的浅色。
8. 年份使用 `Text(verbatim: String(year)).monospacedDigit()` 或明确关闭 grouping 的格式；不得借修改年份算法解决显示逗号问题。

## 5. PDF 版式与可靠分页

- A4 保留 **595×842pt**；左右 48pt，上 48pt，下 48pt；正文宽 **499pt**，底部安全边界 y=794。页脚基线与正文至少间隔 16pt。
- 封面保留清楚的作品名、人物、输入收据、档位、生成日期和内容指纹；留白优先。背景装饰只用低对比线稿，不盖章压文字。
- 正文建议 12–12.5pt，行距 4pt，段间 6pt；章题 17–18pt，节题 13–14pt；正文不做透明度装饰，不用发光描边；数字等宽。
- 保留 `ReportBuilder.lines(for:tier:)` 现有全部原文、顺序和数据，不修改 `engineVersion`、取用条件、规则、可信度、内容哈希输入。样式文件另外保存 `layoutVersion`，不得冒称算法升级。
- 当前分页器以整条字符串为原子；如果单段高度超过一页，另起一页仍可能溢出。新排版器应使用 CoreText 的可见范围/行片段拆分长段落，按已测的字体和宽度分页，绘制阶段不得再次独立估算分页。
- 目录应预先测量自身页数：先得到正文相对页，再测目录页数，最后统一计算 `正文绝对页 = 封面页数 + 目录页数 + 正文相对页`。页数增长时目录可续页，不能永远假设目录只有一页。
- 既有 Tests 有固定契约：PDF 第 2 页是目录，专业/完整目录中可提取“详批条目”和首条标题；保持首个目录页含这些内容。不改 Tests 来适配一个漏目录的设计。
- `drawTOC` 与正文必须消费同一份布局结果。目录行支持点击跳转、书签可作为增量；页码必须先正确，再添加交互。
- 导出后真实用 PDFKit 打开，检查页数、目录、首末章、超长段落和最后页；只读核对不等于视觉验收。现有测试通过也不等于所有姓名和极端长内容通过。

## 6. 罗盘与压盘的仪器视觉合同

### 罗盘

`CompassStandaloneView` 维持恒深 `Ky.instBg`。刻度主线金、次刻度低亮灰金、当前北向朱砂；数字与真/磁北标签白字，高对比状态不只靠红绿。当前读数 36–44pt 等宽、山名 22pt、校正来源/精度 13–14pt，质量信息在首屏内。

玻璃仅用于浮动的模式/锁定控制条，表盘本身实色不透明。动态效果只旋转合成层或渐变透明度；保持现有 Canvas 计算，不在每次 heading 更新时重建装饰纹理。触感仅用于用户主动切换/拨盘越过离散刻度；设置节流与系统开关，不把物理传感器每帧噪声转成振动。

**禁止动的代码**：`CompassBearingResolver`、`CompassManualDeclinationInput`、`CompassSampleReceipt`、采样循环判定、`finishCollect` 收据计算、WMM 系数和坐向转换。视觉可显示状态，不能为了让按钮亮起来放松门控；不能对显示角度平滑后直接写回原始测量数据。

### 户型压盘

`FloorPlanOverlayView` 采用局部恒深面板/工具栏，保留导入图像原色；白纸底图与荧光细线可并存，不对照片整体反色。元运、坐向、玄空/八宅、实测来源作为固定可见的状态栏。透明度滑块以百分比等宽数字显示，触控高 44pt。

首批只整理 310pt 画布与 290pt overlay 的布局；后续将图纸和 overlay 放进可测量容器，保留同一坐标原点。中心十字 26pt 视觉尺寸可以保留，但拖动热区至少 44×44pt。手势时只做 `offset/scale/rotationEffect/opacity`，不要每帧触发重排盘。

新增 `viewRotation`、缩放、平移仅为**视图变换**，与实测 `sitDegree`、二十四山索引和元运输入分开。不能因为用户转图，就暗中修改罗盘锁定值。若保存视图状态，按案件/底图标识分隔，使用独立 UI 设置键，不能把另一个案件的立极点套到当前图。

**禁止动的代码**：`orientations` 的坐山/向山与宫位字段、`gridPalaces` 的宫序、`currentOri` 的测量映射、`FengshuiEngine.chart` / `youNian` 参数与算法。不以“视觉朝南”之名翻转九宫或坐向；“南上北下”必须清楚标注。

## 7. 与全局 P0–P5 的一致实施顺序

全局唯一执行顺序见 [EXECUTION-P0-P5.md](EXECUTION-P0-P5.md)：P0 冻结基线；P1 全局语义与组件；P2 首页/人物及导出入口；P3 专业盘与阅读；P4 仪器；P5 海报矩阵/PDF/历史兼容与交付。本文件第 2～5 节为 P5 的具体子任务，第 6 节为 P4。不要将导出子任务另设同名 P0～P5，避免两个路线冲突。

每批先 `git diff --check`，确认 Tests、UITests、Resources 与金标准 JSON 无修改；混合文件只允许展示/绘制片段。原样运行现有回归，不降低断言、不删除用例。1080px 宽度检查不能替代字形、边距、长段落和历史文件兼容的实际验证。性能目标 120Hz 需真机 Instruments 记录，Canvas/transform 不是满帧证明。

## 8. Web 待接入合同

当前只交付可移植视觉合同，不写虚构的 Web 文件名或称已重构在线站点：

- CSS tokens 对应 `--ky-bg`、`--ky-card`、`--ky-ink`、`--ky-action`、`--ky-hairline`、`--ky-radius:18px`、`--ky-inset:20px`、`--ky-gap:15px`、`--ky-card-inset:16px`。这里 px 是 CSS 逻辑像素，不与海报物理像素混用。
- 字体为系统中文衬线标题 + 无衬线正文，数字使用 `font-variant-numeric: tabular-nums`；年份用明确关闭 grouping 的 `Intl.NumberFormat` 或字符串，不修改日历算法。
- Web 的玻璃仅限导航/浮动工具条；支持 `prefers-reduced-motion`，不支持 `backdrop-filter` 或启用降低透明度时落为实色。导出 HTML 需要冻结主题、字体就绪和图像加载后再测量，不直接截一个未稳定的屏幕页面。
- 待确认真实仓库后再定位 router、theme、chart、poster、print/PDF 的实际文件，先建立映射表，再逐页接入；API 请求、字段名、盘面数组顺序、评分与后端规则一律不随视觉改版改变。
