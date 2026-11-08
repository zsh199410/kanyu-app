// Kanyu Insight 内容模型收敛（G18，第 1 批）
//
// 纯收敛，不改行为、不改存储、不改文案：把两端已有的事实 dict／结构体管线
// 收为五个命名模型，供后续 G1（三档报告）与 G9（Web 报告中心）挂字段。
// 本文件只定义模型，现有调用链一处不动（零行为变化）。
// 口径：本文件不含任何断语文本；C 类（寿数／落病名／确定性断语／改命转运功效宣称）0 命中。
//
// 对齐来源：
// AnalysisSection ← InterpretItem（InterpretModule.swift:7–11，三字段 title／conclusion／links）
// ＋ Web analyze() items {id, title, conclusion, facts, source}（bazi_rules.py:1588–1591）
// ChartData ← BaziChart（BaziModule.swift:11–36）
// ＋ Web chart dict（paipan.py:225–241）
// ReportDocument ← ReportBuilder.lines（ReportModule.swift:7–68）的 6 章结构
// （四柱细盘／大运／逐年直断／解盘维度摘要／双术合参·交叉印证／紫微摘要）
// PosterTemplate ← PosterStyle（PosterModule.swift，2 种：宋纸青黛／尊享预测单）
// ＋ Web 3 款白名单 qingdai／yucedan／hecan（main.py /api/poster）
// ＋ 文件名后缀 -song／-yucedan（PosterModule.swift 各海报 sheet 的 render）
// ExportManager ← ReportCenterView.swift:29–32 前缀扫描
// ＋ ReportModule.swift:99「命书-人名.pdf」
// ＋ PosterModule.swift:1498／1915／2240 文件名拼法
// ＋ Web /api/poster Content-Disposition「kanyu-款式-人物 id.png」（main.py:936）
import Foundation

/// 命盘数据：四柱＋日主＋大运干支＋五行占比＋旬空＋起运。
/// 与 BaziChart 同字段一一对应；五行占比顺序为木火土金水。
struct ChartData {
let pillars: [String]
let rizhu: String
let dayunGanZhi: [String]
let wuxingPercents: [Double]
let xunKong: String
let qiyunYear: Int
let qiyunDirection: String

init(chart: BaziChart) {
pillars = chart.pillars
rizhu = chart.rizhu
dayunGanZhi = chart.dayunGanZhi
wuxingPercents = chart.wuxingPercents
xunKong = chart.xunKong
qiyunYear = chart.qiyunYear
qiyunDirection = chart.qiyunDirection
}
}

/// 解读条目：InterpretItem 的三字段原样保留，另补 Web 端同款 id／facts／source 字段。
/// App 侧 InterpretItem 本无 id／facts／source，由 App 构造时三者留空；
/// Web 侧 analyze() 的 items 五键齐全，跨端对齐时逐项填入，不另起口径。
struct AnalysisSection {
let id: String
let title: String
let conclusion: String
let facts: String
let source: String
let links: [(label: String, text: String)]

init(
id: String = "",
title: String,
conclusion: String,
facts: String = "",
source: String = "",
links: [(label: String, text: String)] = []
) {
self.id = id
self.title = title
self.conclusion = conclusion
self.facts = facts
self.source = source
self.links = links
}

init(item: InterpretItem, id: String = "") {
self.id = id
title = item.title
conclusion = item.conclusion
facts = ""
source = ""
links = item.links
}
}

/// 报告文档：ReportBuilder.lines 的平铺行按切为章节的结构化形态。
/// headerLines 为首章之前的行（命书标题／生辰／四柱／胎元行）；chapters 只含章。
/// footerNote 由调用方传入（ReportBuilder.lines 末尾的口径声明行在切分后归入末章行内）。
struct ReportDocument {
struct Chapter {
let title: String
let lines: [String]
}

let title: String
let personName: String
let headerLines: [String]
let chapters: [Chapter]
let sections: [AnalysisSection]
let footerNote: String

init(
title: String,
personName: String,
headerLines: [String] = [],
chapters: [Chapter] = [],
sections: [AnalysisSection] = [],
footerNote: String = ""
) {
self.title = title
self.personName = personName
self.headerLines = headerLines
self.chapters = chapters
self.sections = sections
self.footerNote = footerNote
}

static func fromLines(
_ lines: [String],
title: String,
personName: String,
sections: [AnalysisSection] = [],
footerNote: String = ""
) -> ReportDocument {
var header: [String] = []
var chapters: [Chapter] = []
var currentTitle = ""
var currentLines: [String] = []
var inChapter = false
for line in lines {
if line.hasPrefix("") {
if inChapter {
chapters.append(Chapter(title: currentTitle, lines: currentLines))
}
currentTitle = String(line.dropFirst().dropLast())
currentLines = []
inChapter = true
} else if inChapter {
currentLines.append(line)
} else {
header.append(line)
}
}
if inChapter {
chapters.append(Chapter(title: currentTitle, lines: currentLines))
}
return ReportDocument(
title: title,
personName: personName,
headerLines: header,
chapters: chapters,
sections: sections,
footerNote: footerNote
)
}
}

/// 海报模板：PosterStyle 的 2 种各对应一个 Web 款式 id 与一个文件名后缀。
/// 两端款式对照：songQingdai↔qingdai、yuceDan↔yucedan；
/// Web 的 hecan 款在 App 侧无 PosterStyle 对应 case（合参海报在 App 侧为独立渲染），故不硬凑。
struct PosterTemplate {
let style: PosterStyle
let webStyleId: String
let fileSuffix: String

var name: String { style.rawValue}

init(style: PosterStyle) {
self.style = style
switch style {
case.songQingdai:
webStyleId = "qingdai"
fileSuffix = "-song"
case.yuceDan:
webStyleId = "yucedan"
fileSuffix = "-yucedan"
}
}

static let all: [PosterTemplate] = PosterStyle.allCases.map { PosterTemplate(style: $0)}
}

/// 导出管理：只收敛已有的文件名拼法与前缀扫描，不新增存储、不改扫描行为。
/// 文件名拼法与 ReportModule.swift:99、PosterModule.swift:1498／1915／2240 逐字一致；
/// kind(of:) 与 ReportCenterView.swift:29–32 的前缀扫描同序同义。
enum ExportManager {
enum Kind: String {
case report
case poster
case ziweiPoster
case hecanPoster
case unknown
}

static let reportPrefix = "命书-"
static let posterPrefix = "poster-"
static let ziweiPosterPrefix = "ziwei-poster-"
static let hecanPosterPrefix = "hecan-poster-"

static func kind(of fileName: String) -> Kind {
if fileName.hasPrefix(reportPrefix) {
return.report
}
if fileName.hasPrefix(ziweiPosterPrefix) {
return.ziweiPoster
}
if fileName.hasPrefix(hecanPosterPrefix) {
return.hecanPoster
}
if fileName.hasPrefix(posterPrefix) {
return.poster
}
return.unknown
}

static func fileName(kind: Kind, personName: String, suffix: String = "") -> String {
var name = personName
if name.isEmpty {
name = "chart"
}
switch kind {
case.report:
return reportPrefix + name + ".pdf"
case.poster:
return posterPrefix + name + suffix + ".png"
case.ziweiPoster:
return ziweiPosterPrefix + name + suffix + ".png"
case.hecanPoster:
return hecanPosterPrefix + name + suffix + ".png"
case.unknown:
return name
}
}
}
