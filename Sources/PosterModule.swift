import SwiftUI
import UIKit

// MARK: - 命盘海报 v5（新增定版「宋纸青黛版」为首推样式，严格对齐《模板规范-2026-10-29.md》，同时保留宣纸浅色版与墨金版）

private let pBg0 = Color(red: 0.05, green: 0.07, blue: 0.10)
private let pBg1 = Color(red: 0.10, green: 0.13, blue: 0.18)
private let pGold = Color(red: 0.78, green: 0.64, blue: 0.36)
private let pGoldHi = Color(red: 0.90, green: 0.79, blue: 0.52)
private let pPaper = Color(red: 0.968, green: 0.949, blue: 0.906) // #F7F2E7 宋纸
private let pSub = Color(red: 0.478, green: 0.447, blue: 0.408)   // #7A7268 次级
private let pCin = Color(red: 0.604, green: 0.165, blue: 0.133)   // #9A2A22 故宫红
private let pTeal = Color(red: 0.153, green: 0.306, blue: 0.361)  // #274E5C 青黛

// MARK: - 海报版本：宋纸青黛版（定版规范） / 宣纸浅色版 / 墨金版
enum PosterStyle: String, CaseIterable {
    case songQingdai = "宋纸青黛版"
    case yuceDan = "传统预测单版"
    case xuanPaper = "宣纸朱砂版"
    case inkGold = "玄夜墨金版"
}

private struct PosterPalette {
    let bg0: Color
    let bg1: Color
    let main: Color
    let sub: Color
    let accent: Color
    let accentHi: Color
    let card: Color
    let cardStroke: Color
    let track: Color
}

private extension PosterStyle {
    var palette: PosterPalette {
        switch self {
        case .songQingdai, .yuceDan:
            let ink = Color(red: 0.18, green: 0.165, blue: 0.15)
            let cardBg = Color(red: 0.992, green: 0.984, blue: 0.961) // #FDFBF5
            let line = Color(red: 0.886, green: 0.851, blue: 0.769)   // #E2D9C4
            return PosterPalette(bg0: pPaper, bg1: cardBg, main: ink, sub: pSub,
                                 accent: pTeal, accentHi: pCin,
                                 card: cardBg, cardStroke: line, track: Color.black.opacity(0.07))
        case .inkGold:
            return PosterPalette(bg0: pBg0, bg1: pBg1, main: pPaper, sub: Color(red: 0.66, green: 0.62, blue: 0.54),
                                 accent: pGold, accentHi: pGoldHi,
                                 card: Color.white.opacity(0.04), cardStroke: pGold.opacity(0.28), track: Color.white.opacity(0.08))
        case .xuanPaper:
            let ink = Color(red: 0.18, green: 0.16, blue: 0.13)
            let inkSub = Color(red: 0.46, green: 0.42, blue: 0.35)
            let paperHi = Color(red: 0.97, green: 0.95, blue: 0.88)
            return PosterPalette(bg0: pPaper, bg1: paperHi, main: ink, sub: inkSub, accent: pCin, accentHi: pCin,
                                 card: Color.white.opacity(0.55), cardStroke: pCin.opacity(0.35), track: Color.black.opacity(0.08))
        }
    }
}

// 降饱和宋韵五行色（对齐《模板规范-2026-10-29.md》）
private let wxColor: [String: Color] = [
    "木": Color(red: 0.357, green: 0.498, blue: 0.306), // #5B7F4E
    "火": Color(red: 0.710, green: 0.314, blue: 0.184), // #B5502F
    "土": Color(red: 0.643, green: 0.471, blue: 0.392), // #A47864
    "金": Color(red: 0.557, green: 0.545, blue: 0.510), // #8E8B82
    "水": Color(red: 0.290, green: 0.420, blue: 0.518), // #4A6B84
]

private func posterCharColor(_ ch: Character, fallback: Color) -> Color {
    let el = KyV2.element(ofChar: ch)
    return wxColor[el] ?? fallback
}

struct BaguaRingView: View {
    let size: CGFloat
    var accent: Color = pGold
    var accentHi: Color = pGoldHi
    private let grams = ["☰", "☱", "☲", "☳", "☴", "☵", "☶", "☷"]
    var body: some View {
        ZStack {
            Circle().stroke(accent.opacity(0.55), lineWidth: 1)
            Circle().stroke(accent.opacity(0.30), lineWidth: 1).padding(size * 0.085)
            ForEach(0..<8, id: \.self) { i in
                Text(grams[i])
                    .font(.system(size: size * 0.115))
                    .foregroundStyle(accentHi)
                    .frame(width: size, height: size, alignment: .top)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
            Text("☯").font(.system(size: size * 0.44)).foregroundStyle(accent)
        }
        .frame(width: size, height: size)
    }
}

// 宋式远山线描装饰带（用于宋纸青黛版，替代道教八卦太极符）
private struct SongMountainHeaderView: View {
    var accent: Color
    var body: some View {
        Canvas { ctx, size in
            let w = size.width; let h = size.height
            for (idx, alpha) in [(0, 0.08), (1, 0.14), (2, 0.22)] {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: h))
                for x in stride(from: 0.0, through: Double(w), by: 8.0) {
                    let y = Double(h) - (14.0 + Double(idx) * 10.0)
                        - sin(x / 58.0 + Double(idx) * 1.7) * (12.0 - Double(idx) * 2.0)
                        - cos(x / 26.0 + Double(idx)) * 5.0
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                p.addLine(to: CGPoint(x: w, y: h))
                p.closeSubpath()
                ctx.fill(p, with: .color(accent.opacity(alpha)))
            }
        }
        .frame(height: 54)
    }
}

struct PosterView: View {
    let chart: BaziChart
    let name: String
    var style: PosterStyle = .songQingdai

    private var items: [InterpretItem] { InterpretEngine.interpret(chart: chart) }
    private var headline: String { items.first(where: { $0.title == "命局风景" })?.conclusion ?? "" }
    private var gejuLine: String { items.first(where: { $0.title == "月令格局（候选）" })?.conclusion ?? "" }
    private var yunLine: String { items.first(where: { $0.title == "岁运要点" })?.conclusion ?? "" }
    private var pal: PosterPalette { style.palette }

    var body: some View {
        if style == .yuceDan {
            YucedanPosterLayout(chart: chart, name: name, pal: pal)
        } else {
            standardPosterView
        }
    }

    private var standardPosterView: some View {
        ZStack {
            LinearGradient(colors: [pal.bg1, pal.bg0], startPoint: .top, endPoint: .bottom)
            if style != .songQingdai {
                RadialGradient(colors: [pal.accent.opacity(0.14), .clear], center: .init(x: 0.5, y: 0.16), startRadius: 10, endRadius: 300)
                RoundedRectangle(cornerRadius: 10).stroke(pal.accent.opacity(0.55), lineWidth: 1.1).padding(18)
                RoundedRectangle(cornerRadius: 6).stroke(pal.accent.opacity(0.25), lineWidth: 0.7).padding(24)
            } else {
                // 宋式极简发丝外框＋底部远山意境
                RoundedRectangle(cornerRadius: 4).stroke(pal.cardStroke, lineWidth: 1.0).padding(22)
                VStack {
                    Spacer()
                    SongMountainHeaderView(accent: pal.accent)
                        .padding(.horizontal, 23).padding(.bottom, 23)
                }
            }

            VStack(spacing: 0) {
                if style == .songQingdai {
                    Text("子 平 五 典 · 命 盘 雅 集")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(4)
                        .foregroundStyle(pal.accent)
                        .padding(.top, 52)
                    Text(name.isEmpty ? "四柱命盘" : name)
                        .font(.system(size: 44, weight: .bold, design: .serif))
                        .foregroundStyle(pal.main)
                        .padding(.top, 16)
                } else {
                    BaguaRingView(size: 132, accent: pal.accent, accentHi: pal.accentHi).padding(.top, 42)
                    Text("三 术 合 参").font(.system(size: 14, design: .serif)).tracking(2).foregroundStyle(pal.accentHi).padding(.top, 12)
                    Text(name.isEmpty ? "命盘" : name)
                        .font(.system(size: 40, weight: .semibold, design: .serif)).foregroundStyle(pal.main).padding(.top, 18)
                }

                Text("日主 \(chart.rizhu) · 胎元 \(chart.taiYuan) · 命宫 \(chart.mingGong) · 身宫 \(chart.shenGong)")
                    .font(.system(size: 12)).foregroundStyle(pal.sub).padding(.top, 8)

                // 宋式菱形中缀发丝线
                HStack(spacing: 8) {
                    Rectangle().fill(pal.cardStroke).frame(width: 140, height: 0.8)
                    Rectangle().fill(pal.accent).frame(width: 5, height: 5).rotationEffect(.degrees(45))
                    Rectangle().fill(pal.cardStroke).frame(width: 140, height: 0.8)
                }.padding(.vertical, 18)

                // 四柱（干支按五行降饱和分色）
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { i in
                        let gz = Array(chart.pillars[i])
                        let sColor = style == .inkGold ? (i == 2 ? pal.accentHi : pal.main) : posterCharColor(gz[0], fallback: pal.main)
                        let bColor = style == .inkGold ? (i == 2 ? pal.accentHi : pal.main) : posterCharColor(gz[1], fallback: pal.main)
                        VStack(spacing: 5) {
                            Text(["年柱", "月柱", "日柱", "时柱"][i])
                                .font(.system(size: 10.5, weight: .medium)).foregroundStyle(pal.sub)
                            Text(String(gz[0]))
                                .font(.system(size: 34, weight: .bold, design: .serif))
                                .foregroundStyle(sColor)
                            Text(String(gz[1]))
                                .font(.system(size: 34, weight: .bold, design: .serif))
                                .foregroundStyle(bColor)
                            Text(i == 2 ? "日主" : chart.stemShiShen[i])
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(i == 2 ? pal.accentHi : pal.accent)
                            Text(chart.diShi[i])
                                .font(.system(size: 9.5))
                                .foregroundStyle(pal.sub)
                        }
                        .frame(width: 82, height: 144)
                        .background(pal.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(i == 2 ? pal.accentHi.opacity(0.65) : pal.cardStroke, lineWidth: i == 2 ? 1.2 : 0.8)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                // 五行力量横条
                VStack(spacing: 7) {
                    ForEach(Array(["木", "火", "土", "金", "水"].enumerated()), id: \.offset) { idx, e in
                        let v = chart.wuxingPercents[idx]
                        HStack(spacing: 8) {
                            Text(e)
                                .font(.system(size: 12, weight: .bold, design: .serif))
                                .foregroundStyle(wxColor[e] ?? pal.main)
                                .frame(width: 16)
                            // 海报画布固定 540 宽（横向留白 54×2），轨道宽定死 364，不用 GeometryReader 量尺寸
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(pal.track)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(wxColor[e] ?? pal.accent)
                                    .frame(width: max(3, 364 * CGFloat(min(v, 100)) / 100.0))
                            }
                            .frame(width: 364, height: 7)
                            Text("\(Int(v.rounded()))%")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(pal.sub)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
                .padding(.horizontal, 54).padding(.top, 22)

                // 核心结论白话摘录
                VStack(alignment: .leading, spacing: 10) {
                    if !headline.isEmpty {
                        Text(headline)
                            .font(.system(size: 13.5, design: .serif)).foregroundStyle(pal.main)
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }
                    if !gejuLine.isEmpty {
                        Text(gejuLine)
                            .font(.system(size: 12.5)).foregroundStyle(pal.accent)
                            .lineSpacing(3.5).fixedSize(horizontal: false, vertical: true)
                    }
                    if !yunLine.isEmpty {
                        Text(yunLine)
                            .font(.system(size: 11.5)).foregroundStyle(pal.sub)
                            .lineSpacing(3).lineLimit(3)
                    }
                }
                .padding(16)
                .frame(width: 444, alignment: .leading)
                .background(pal.card)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(pal.cardStroke, lineWidth: 0.8))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.top, 20)

                // 前六步大运时间轴
                HStack(spacing: 7) {
                    ForEach(0..<min(6, chart.dayunGanZhi.count), id: \.self) { i in
                        VStack(spacing: 3) {
                            Text(chart.dayunGanZhi[i])
                                .font(.system(size: 13, weight: .bold, design: .serif)).foregroundStyle(pal.main)
                            Text("\(chart.dayunStartYear(i))起")
                                .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(pal.sub)
                        }
                        .frame(width: 66, height: 46)
                        .background(pal.card)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(pal.cardStroke, lineWidth: 0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }.padding(.top, 18)

                Spacer()

                // 落款印章与出处声明
                HStack(alignment: .bottom) {
                    VStack(spacing: 1) {
                        HStack(spacing: 1) {
                            Text("三").font(.system(size: 14, weight: .bold, design: .serif))
                            Text("术").font(.system(size: 14, weight: .bold, design: .serif))
                        }
                        HStack(spacing: 1) {
                            Text("合").font(.system(size: 14, weight: .bold, design: .serif))
                            Text("参").font(.system(size: 14, weight: .bold, design: .serif))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(pCin)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("据五典而断 · 盘面为据 · 宋纸雅集")
                            .font(.system(size: 11, design: .serif)).foregroundStyle(pal.accent)
                        Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 10)).foregroundStyle(pal.sub.opacity(0.8))
                    }
                }
                .padding(.horizontal, 48).padding(.bottom, 42)
            }
        }
        .frame(width: 540, height: 960)
    }
}

// MARK: - 传统预测单海报布局（复刻易辰取名社经典预测单：太极八卦头 + 双行信息栏 + 四柱十神表格 + 大运喜忌列 + 十二支罗盘时轮 + 7大详析节 + 补五行建议清单；七节断语与喜忌行全部取自本机解盘引擎逐人现算，不写死）
struct YucedanPosterLayout: View {
let chart: BaziChart
let name: String
// pal 必须是 fileprivate：PosterPalette 是 private 类型，internal 属性/初始化器会编译不过
fileprivate let pal: PosterPalette

fileprivate init(chart: BaziChart, name: String, pal: PosterPalette) {
self.chart = chart
self.name = name
self.pal = pal
}

// MARK: - 数据（全部逐人现算；喜忌口径见 InterpretEngine.posterXiJi：扶抑初判＋调候优先）
private var items: [InterpretItem] { InterpretEngine.interpret(chart: chart)}
private func conclusion(_ titles: String...) -> String {
InterpretEngine.conclusion(items: items, titles: titles)
}
private var xj: (xi: [Int], ji: [Int], neutral: [Int], level: String, tongDang: Double, tiaoHou: [Int]) {
InterpretEngine.posterXiJi(chart: chart)
}
private static let wxNames = ["木", "火", "土", "金", "水"]
private static let numMap = ["木": "3、8", "火": "2、7", "土": "5、0", "金": "4、9", "水": "1、6"]
private static let colorMap = ["木": "绿、青", "火": "红", "土": "黄", "金": "白、金", "水": "黑、蓝"]
// 七·建议五项原文：易辰取名社手写单真迹措辞（cases/周囿廷-取名社预测单.jpg）；✓/× 按本工作室喜忌现算，栏目标明传统应用参考
private static let buTexts = [
"宜养花草、穿绿色衣服、佩戴或摆放木质工艺品，如绿檀、紫檀、黄花梨手串。",
"宜穿红色衣服，佩戴红色工艺品，如床头挂红色中国结。",
"宜穿黄色、咖啡色、灰色衣服，佩戴玉石类、翡翠、玛瑙，摆放石头工艺品。",
"宜穿白色衣服，佩戴金银饰品，摆放金属类工艺品。",
"宜养鱼，挂山水画，穿黑色、蓝色衣服，佩戴水晶、珍珠饰品，摆放水晶类工艺品。",
]
private static let birthFmt: DateFormatter = {
let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
return f
}()
private static let timeFmt: DateFormatter = {
let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
return f
}()
private static let dateFmt: DateFormatter = {
let f = DateFormatter(); f.dateFormat = "yyyy年M月d日"; f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
return f
}()

private func wxIdx(ofStem c: Character) -> Int {
switch c { case "甲", "乙": return 0; case "丙", "丁": return 1
case "戊", "己": return 2; case "庚", "辛": return 3; default: return 4}
}
private func wxIdx(ofBranch b: Character) -> Int {
switch b { case "寅", "卯": return 0; case "巳", "午": return 1
case "辰", "戌", "丑", "未": return 2; case "申", "酉": return 3; default: return 4}
}
/// 喜忌标记（二值，与真迹一致）：喜→✓红，忌→×红，中性（可用）→✓青黛；三者区分见喜忌横幅
private func markGlyph(_ w: Int) -> (String, Color) {
if xj.ji.contains(w) { return ("×", pal.accentHi)}
if xj.xi.contains(w) { return ("✓", pal.accentHi)}
return ("✓", pal.accent)
}
/// 大运标记：运干五行套 posterXiJi；中和盘全标中性
private func dayunGlyph(_ i: Int) -> (String, Color) {
let m = InterpretEngine.dayunMark(chart: chart, index: i)
if m == "喜" { return ("✓", pal.accentHi)}
if m == "忌" { return ("×", pal.accentHi)}
return ("～", pal.sub)
}
/// 流年地支轮：以出生年支为起点的下一个完整十二年轮（当前年份之后的首个该支年份起，连续 12 年）；
/// 每支标关联年份、周岁岁数与 ✓/×（地支五行套喜忌）。周囿廷：2036–2047，12–23 岁，与真迹 13–24 虚岁差一岁（口径：工作室标周岁）。
private var wheelYears: [(branch: Character, year: Int, age: Int, glyph: String, color: Color)] {
let nowYear = Calendar.current.component(.year, from: Date())
let birthBranch = chart.yearPillar.last!
var start = nowYear
while BaziChart.yearGanZhi(start).last!!= birthBranch { start += 1}
return (0..<12).map { k in
let y = start + k
let br = BaziChart.yearGanZhi(y).last!
let (g, c) = markGlyph(wxIdx(ofBranch: br))
return (br, y, y - chart.birthYear, g, c)
}
}
private var xiNums: String { xj.xi.compactMap { Self.numMap[Self.wxNames[$0]]}.joined(separator: "、")}
private var xiNames: String { xj.xi.map { Self.wxNames[$0]}.joined(separator: "、")}
private var jiNames: String { xj.ji.map { Self.wxNames[$0]}.joined(separator: "、")}
private var floors: String {
let base = xj.xi.flatMap { (Self.numMap[Self.wxNames[$0]]?? "").split(separator: "、").compactMap { Int($0)}}
let all = (base + base.map { $0 + 10}).sorted()
return all.map { String($0)}.joined(separator: "、") + " 层"
}

var body: some View {
ZStack {
pal.bg0
// 细线红黑边框
RoundedRectangle(cornerRadius: 6, style:.continuous)
.stroke(Color(red: 0.18, green: 0.165, blue: 0.15).opacity(0.8), lineWidth: 1.2)
.padding(14)
RoundedRectangle(cornerRadius: 4, style:.continuous)
.stroke(pal.accentHi.opacity(0.4), lineWidth: 0.6)
.padding(18)

VStack(spacing: 0) {
// 1. 顶部太极图与标题（复刻真迹题头）
HStack(spacing: 10) {
ZStack {
Circle().stroke(Color.black, lineWidth: 1.2)
Circle().trim(from: 0, to: 0.5).fill(Color.black)
Circle().fill(Color.black).frame(width: 13, height: 13).offset(x: -6.5)
Circle().fill(Color.white).frame(width: 13, height: 13).offset(x: 6.5)
Circle().fill(Color.white).frame(width: 4, height: 4).offset(x: -6.5)
Circle().fill(Color.black).frame(width: 4, height: 4).offset(x: 6.5)
}
.frame(width: 26, height: 26)

Text("易辰取名社八字预测单")
.font(.system(size: 20, weight:.bold, design:.serif))
.tracking(2)
.foregroundStyle(pal.main)
}
.padding(.top, 22)

// 2. 双行生辰收据（城市/经度/出生时刻/农历/前后两节/性别/姓名/年命）
VStack(spacing: 2) {
HStack(spacing: 0) {
Text("城市：\(receiptCity)")
Text("　经度：\(receiptLongitude)")
Spacer()
Text("出生：\(Self.birthFmt.string(from: chart.birthDate))\(trueSolarSuffix)")
}
HStack(spacing: 0) {
Text("农历：\(chart.lunarText.isEmpty? "—": chart.lunarText)")
Text("　上一节 \(chart.prevJieQiText.isEmpty? "—": chart.prevJieQiText)　下一节 \(chart.nextJieQiText.isEmpty? "—": chart.nextJieQiText)")
Spacer()
Text("\(chart.gender == "M"? "男（乾造）": "女（坤造）")　\(name.isEmpty? "命主": name)　\(chart.naYin.first?? "")命")
}
}
.font(.system(size: 9, weight:.medium, design:.serif))
.foregroundStyle(pal.sub)
.padding(.horizontal, 28)
.padding(.top, 8)

Rectangle().fill(pal.cardStroke).frame(height: 0.7).padding(.horizontal, 24).padding(.vertical, 6)

// 3. 核心排盘区：四柱纵表 + 大运序列 + 流年地支轮
HStack(alignment:.top, spacing: 6) {
// (A) 四柱：十神／干支大字／藏干十神／长生
VStack(spacing: 2) {
Text("")
.font(.system(size: 10, weight:.bold, design:.serif))
.foregroundStyle(pal.accent)
HStack(spacing: 3) {
ForEach(0..<4, id: \.self) { i in
let gz = Array(chart.pillars[i])
VStack(spacing: 1) {
Text(["年", "月", "日", "时"][i])
.font(.system(size: 8.5)).foregroundStyle(pal.sub)
Text(chart.stemShiShen[i])
.font(.system(size: 7.5, weight:.medium))
.foregroundStyle(i == 2? pal.accentHi: pal.accent)
Text(String(gz[0]))
.font(.system(size: 15, weight:.bold, design:.serif))
.foregroundStyle(posterCharColor(gz[0], fallback: pal.main))
Text(String(gz[1]))
.font(.system(size: 15, weight:.bold, design:.serif))
.foregroundStyle(posterCharColor(gz[1], fallback: pal.main))
Text(chart.hideShiShen[i].joined(separator: "·"))
.font(.system(size: 6.5)).foregroundStyle(pal.accentHi)
.lineLimit(2).multilineTextAlignment(.center)
Text(chart.diShi[i])
.font(.system(size: 7)).foregroundStyle(pal.sub)
}
.frame(width: 34)
.padding(.vertical, 3)
.background(pal.card)
.overlay(RoundedRectangle(cornerRadius: 4, style:.continuous).stroke(i == 2? pal.accentHi.opacity(0.8): pal.cardStroke, lineWidth: 0.6))
}
}
}

// (B) 大运：✓/×（调候优先口径）＋运干五行＋干支＋岁数区间
VStack(alignment:.leading, spacing: 2) {
Text("")
.font(.system(size: 10, weight:.bold, design:.serif))
.foregroundStyle(pal.accent)
VStack(alignment:.leading, spacing: 1.5) {
ForEach(0..<min(7, chart.dayunGanZhi.count), id: \.self) { i in
let gz = chart.dayunGanZhi[i]
let (g, c) = dayunGlyph(i)
let startAge = chart.dayunStartYear(i) - chart.birthYear
HStack(spacing: 3) {
Text(g).font(.system(size: 9, weight:.bold)).foregroundStyle(c).frame(width: 10)
Text(Self.wxNames[wxIdx(ofStem: gz.first!)])
.font(.system(size: 8)).foregroundStyle(pal.sub).frame(width: 10)
Text(gz)
.font(.system(size: 9.5, weight:.bold, design:.serif)).foregroundStyle(pal.main)
Text("\(startAge)~\(startAge + 9)岁")
.font(.system(size: 8, design:.monospaced)).foregroundStyle(pal.sub)
}
}
}
}
.frame(width: 108)

// (C) 流年地支轮：子北午南、顺时针环列；每支标年份、周岁与 ✓/×，盘心定向指针；红点＝原局四支
VStack(spacing: 2) {
Text("")
.font(.system(size: 10, weight:.bold, design:.serif))
.foregroundStyle(pal.accent)
ZStack {
Circle().stroke(pal.cardStroke, lineWidth: 0.8)
Circle().stroke(pal.cardStroke.opacity(0.5), lineWidth: 0.5).frame(width: 62, height: 62)
ForEach(wheelYears, id: \.branch) { w in
let order = Array("子丑寅卯辰巳午未申酉戌亥")
let pos = order.firstIndex(of: w.branch)?? 0
let angle = Double(pos) * 30.0 - 90.0
let rad = angle *.pi / 180.0
VStack(spacing: 0) {
Text(String(w.branch))
.font(.system(size: 9, weight:.bold, design:.serif))
.foregroundStyle(posterCharColor(w.branch, fallback: pal.main))
Text("\(w.year)")
.font(.system(size: 6, design:.monospaced)).foregroundStyle(pal.sub)
Text("\(w.age)岁 \(w.glyph)")
.font(.system(size: 6.5, weight:.bold)).foregroundStyle(w.color)
if chart.pillars.contains(where: { $0.last! == w.branch}) {
Circle().fill(pal.accentHi).frame(width: 3, height: 3)
}
}
.position(x: 58 + 44 * cos(rad), y: 58 + 44 * sin(rad))
}
// 盘心定向指针（指北/子）
Path { p in
p.move(to: CGPoint(x: 58, y: 38))
p.addLine(to: CGPoint(x: 63, y: 58))
p.addLine(to: CGPoint(x: 53, y: 58))
p.closeSubpath()
}
.fill(pal.accentHi)
Circle().fill(pal.main).frame(width: 5, height: 5)
}
.frame(width: 116, height: 116)
.drawingGroup()
}
}
.padding(.horizontal, 24)
.padding(.vertical, 4)

// 四季五行对照（真迹右侧栏，作一行点缀）
Text("四季五行：春木 · 夏火 · 秋金 · 冬水；农历三、九月土")
.font(.system(size: 8, design:.serif)).foregroundStyle(pal.sub)
.padding(.vertical, 3)

// 4. 喜忌神独立横幅（大字定调＋中性说明＋调候依据）
VStack(alignment:.leading, spacing: 2) {
HStack(spacing: 10) {
Text("喜用神：\(xiNames.isEmpty? "—": xiNames) ✓")
.font(.system(size: 11.5, weight:.bold, design:.serif)).foregroundStyle(pal.accentHi)
Text("忌神：\(jiNames.isEmpty? "—": jiNames) ×")
.font(.system(size: 11.5, weight:.bold, design:.serif)).foregroundStyle(pal.accentHi)
if!xj.neutral.isEmpty && xj.level!= "中和" {
Text("\(xj.neutral.map { Self.wxNames[$0]}.joined(separator: "、"))：中性（可用）")
.font(.system(size: 9, design:.serif)).foregroundStyle(pal.sub)
}
}
Text("依据：日主\(xj.level)（同党约\(Int(xj.tongDang.rounded()))%）\(xiJiBasis)")
.font(.system(size: 8.5, design:.serif)).foregroundStyle(pal.sub)
}
.padding(.horizontal, 28)
.padding(.vertical, 5)
.background(pal.card.opacity(0.8))

Rectangle().fill(pal.cardStroke).frame(height: 0.7).padding(.horizontal, 24).padding(.vertical, 4)

// 5. 七大实务断语（结构化分段，拒绝挤成一团；正文取自解盘引擎，逐人现算）
VStack(alignment:.leading, spacing: 5) {
yuceSection(num: "一", title: "性格", rows: [
("1. 气势底色", conclusion("命局风景")),
("2. 禀赋行事", conclusion("性格性情")),
])
yuceSection(num: "二", title: "事业", rows: [
("1. 选择", conclusion("行业赛道深断", "事业方向")),
("2. 方向", conclusion("适合方位", "事业方向")),
("3. 建议", conclusion("注意事项", "如何化解（破局调理）")),
])
yuceSection(num: "三", title: "财运", rows: [
("1. 财星源流", conclusion("财运形态")),
("2. 财库蓄水", conclusion("财富量级蓄水池")),
])
yuceSection(num: "四", title: "婚姻", rows: [
("1. 选择", conclusion("婚姻感情")),
("2. 方向", conclusion("六亲情境深读", "婚姻感情")),
("3. 建议", conclusion("注意事项", "婚姻感情")),
("4. 问题与解法", conclusion("如何化解（破局调理）", "注意事项")),
])
yuceSection(num: "五", title: "吉祥数", rows: [
("1. 手机尾号", xj.xi.isEmpty? "流通为要，不拘固定数": "宜含 \(xiNums)（\(xiNames)数）"),
("2. 楼层", xj.xi.isEmpty? "流通为要，不拘固定数": "宜选 \(floors)"),
("3. 颜色车色", conclusion("幸运颜色与数字")),
])
yuceSection(num: "六", title: "流年运势", rows: liunianStageRows)
yuceSection(num: "七", title: "建议", rows: buXingRows, note: "传统应用参考")
}
.padding(.horizontal, 28)
.padding(.vertical, 4)

Spacer(minLength: 0)

// 6. 底部落款：免责口径（本工作室）＋三术堂钤印＋落款日期
VStack(spacing: 3) {
Rectangle().fill(pal.cardStroke).frame(height: 0.7).padding(.horizontal, 24)
HStack(alignment:.bottom) {
Text("依据五典推演，仅供娱乐参考；断语可回测验证，不作医疗、寿数与具体事件定断。")
.font(.system(size: 8, design:.serif)).foregroundStyle(pal.sub)
.fixedSize(horizontal: false, vertical: true)
Spacer()
Text("三术堂　\(Self.dateFmt.string(from: Date()))")
.font(.system(size: 9, weight:.bold, design:.serif)).foregroundStyle(pal.main)
ZStack {
RoundedRectangle(cornerRadius: 3, style:.continuous)
.stroke(pal.accentHi, lineWidth: 1.2)
Text("吉")
.font(.system(size: 9, weight:.bold, design:.serif))
.foregroundStyle(pal.accentHi)
}
.frame(width: 16, height: 16)
}
.padding(.horizontal, 28)
}
.padding(.bottom, 22)
}
}
.frame(width: 540, height: 960)
}

// MARK: - 收据派生
private var receiptCity: String {
guard let lon = chart.longitude else { return "—"}
return BirthInputView.placeLabel(longitude: lon)?? "—"
}
private var receiptLongitude: String {
guard let lon = chart.longitude else { return "—"}
return String(format: "%.1f°", lon)
}
private var trueSolarSuffix: String {
guard let t = chart.trueSolarDate else { return ""}
return "（真太阳时 \(Self.timeFmt.string(from: t))）"
}
private var xiJiBasis: String {
if xj.level == "中和" { return "；同党异党接近，贵在流通，不预设固定喜忌"}
let thNames = xj.tiaoHou.map { Self.wxNames[$0]}.joined(separator: "、")
if thNames.isEmpty { return ""}
return "；调候喜\(thNames)（\(chart.monthPillar.last?? "—")月，调候优先）"
}
/// 六·流年运势分段：前 5 步大运为段，每段标岁数区间、运干十神、✓/× 与运势旺弱
private var liunianStageRows: [(String, String)] {
(0..<min(5, chart.dayunGanZhi.count)).map { i in
let gz = chart.dayunGanZhi[i]
let ss = BaziTables.shiShen(day: chart.rizhu.first!, stem: gz.first!)
let startAge = chart.dayunStartYear(i) - chart.birthYear
let (g, _) = dayunGlyph(i)
let mark = InterpretEngine.dayunMark(chart: chart, index: i)
let verdict = mark == "喜"? "运势旺": (mark == "忌"? "运势弱": "运势平")
let note = mark == "喜"? "喜用当令，宜进取": (mark == "忌"? "忌神当道，宜守成": "平运可用，宜稳进")
let markWord = mark == "中性" ? "中性" : (mark == "喜" ? "吉" : "忌")
return ("\(startAge)~\(startAge + 9)岁", "行\(gz)运（运干\(ss)）\(g)\(markWord)（\(verdict)），\(note)")
}
}
/// 七·补五行五项：真迹原文＋按喜忌打 ✓/×（中性按可用打 ✓）
private var buXingRows: [(String, String)] {
(0..<5).map { i in
let (g, _) = markGlyph(i)
return ("补\(Self.wxNames[i])大吉", "\(Self.buTexts[i]) \(g)")
}
}

private func yuceSection(num: String, title: String, rows: [(String, String)], note: String? = nil) -> some View {
VStack(alignment:.leading, spacing: 2) {
HStack(spacing: 6) {
Text("\(num)、\(title)")
.font(.system(size: 10, weight:.bold, design:.serif))
.foregroundStyle(pal.accent)
if let note {
Text(note).font(.system(size: 8)).foregroundStyle(pal.sub)
}
}
ForEach(rows.indices, id: \.self) { j in
(Text("\(rows[j].0)：").font(.system(size: 8.5, weight:.bold, design:.serif)).foregroundStyle(pal.accent)
+ Text(rows[j].1).font(.system(size: 8.5)).foregroundStyle(pal.main))
.lineSpacing(1.5)
.lineLimit(2)
.fixedSize(horizontal: false, vertical: true)
}
}
}
}

struct PosterSheetView: View {
    let chart: BaziChart
    let name: String
    @State private var fileURL: URL?
    @State private var previewImage: UIImage?
    @State private var style: PosterStyle = .songQingdai

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                Picker("海报版本", selection: $style) {
                    ForEach(PosterStyle.allCases, id: \.self) { s in Text(s.rawValue).tag(s) }
                }
                .pickerStyle(.segmented)
                .onChange(of: style) { _, _ in fileURL = nil; previewImage = nil }

                // 预览只展示缓存图片：海报矢量树绝不直接进 ScrollView（每帧重算 InterpretEngine.interpret 与 Canvas 重绘是粘滞主因之一）
                if let img = previewImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 540 * 0.62)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ky.line, lineWidth: 0.8))
                } else {
                    ProgressView("正在渲染海报…")
                        .frame(width: 540 * 0.62, height: 960 * 0.62)
                }

                if let u = fileURL {
                    ShareLink(item: u) {
                        Label("保存 / 分享高清命盘海报（1080×1920）", systemImage: "square.and.arrow.down")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(KyPrimaryButton())
                    Text("在系统分享菜单中点「存储图像」即可存入手机相册，或直接转发微信。")
                        .font(.caption).foregroundStyle(Ky.sub).multilineTextAlignment(.center)
                }
            }
            .padding(20)
        }
        .background(Ky.bg)
        .navigationTitle("命盘海报")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: style) { render() }
    }

    // 渲染放后台线程做（PosterView 是纯函数视图，无 @StateObject，可离主线程渲染）；前台只展示缓存图
    private func render() {
        let chart = chart, name = name, style = style
        Task.detached(priority: .userInitiated) {
            let renderer = ImageRenderer(content: PosterView(chart: chart, name: name, style: style))
            renderer.scale = 2.0
            guard let img = renderer.uiImage, let data = img.pngData() else { return }
            let suffix: String
            switch style {
            case .songQingdai: suffix = "-song"
            case .yuceDan: suffix = "-yucedan"
            case .xuanPaper: suffix = "-xuan"
            case .inkGold: suffix = "-ink"
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("poster-\(name.isEmpty ? "chart" : name)\(suffix).png")
            try? data.write(to: url, options: .atomic)
            await MainActor.run {
                guard self.style == style else { return }  // 切版后旧渲染结果直接丢弃，不覆盖新版预览
                previewImage = img
                fileURL = url
            }
        }
    }
}

// MARK: - 紫微命盘海报（方盘缩印＋命宫主星＋生年四化）

// 方盘缩印单宫（与 ZiweiBoardView 同支序：顶行巳午未申、中行辰卯/酉戌、底行寅丑子亥）
private struct ZiweiMiniCell: View {
    let p: ZiweiPalace
    let pal: PosterPalette
    let isMing: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(p.name)
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundStyle(isMing ? pCin : pal.main)
                Text("\(p.stem)\(ZiweiCore.DZ[p.branch])")
                    .font(.system(size: 8.5)).foregroundStyle(pal.sub)
                if p.isBody {
                    Text("身").font(.system(size: 8, weight: .bold)).foregroundStyle(pal.accentHi)
                }
                Spacer(minLength: 0)
                Text("\(p.decadal.first ?? 0)–\(p.decadal.last ?? 0)")
                    .font(.system(size: 8, design: .monospaced)).foregroundStyle(pal.sub)
            }
            if !p.majors.isEmpty {
                Text(p.majors.map { $0.star + ($0.mutagen.map { "化\($0)" } ?? "") }.joined(separator: "、"))
                    .font(.system(size: 10, weight: .semibold, design: .serif))
                    .foregroundStyle(pal.main).lineLimit(1)
            }
            if !p.minors.isEmpty {
                Text(p.minors.prefix(4).map { $0.star }.joined(separator: " "))
                    .font(.system(size: 8)).foregroundStyle(pal.sub).lineLimit(1)
            }
        }
        .padding(6)
        .frame(width: 107, height: 92, alignment: .topLeading)
        .background(pal.card)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isMing ? pCin.opacity(0.6) : pal.cardStroke, lineWidth: isMing ? 1.1 : 0.7)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// 方盘中央合并 2×2 天心宫：命宫主星＋五行局＋现行大限（虚岁落入哪步大限）
private struct ZiweiCenterCell: View {
    let chart: ZiweiChart
    let pal: PosterPalette
    var body: some View {
        let ming = chart.palaces[chart.mingGong]
        let stars = ming.majors.map { $0.star }.joined(separator: "、")
        let thisYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let age = chart.birthYear > 0 ? thisYear - chart.birthYear + 1 : 0
        let daxian = chart.palaces.first { p in
            age > 0 && age >= (p.decadal.first ?? 0) && age <= (p.decadal.last ?? 0)
        }
        return VStack(spacing: 5) {
            Text(chart.juName)
                .font(.system(size: 13, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
            Text(ming.majors.isEmpty ? "命宫无主星（借对宫）" : "命宫主星 \(stars)")
                .font(.system(size: 12, weight: .semibold, design: .serif)).foregroundStyle(pal.main)
                .multilineTextAlignment(.center)
            Text("命宫\(ming.stem)\(ZiweiCore.DZ[ming.branch]) · 身宫\(chart.palaces[chart.shenGong].name)")
                .font(.system(size: 10)).foregroundStyle(pal.sub)
            if let d = daxian {
                Text("现行大限 \(d.decadal.first ?? 0)–\(d.decadal.last ?? 0) 岁 · \(d.name)")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(pal.accent)
            }
            Text(chart.lunarText)
                .font(.system(size: 9)).foregroundStyle(pal.sub).multilineTextAlignment(.center)
        }
        .frame(width: 219, height: 189)
        .background(pal.card)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(pal.cardStroke, lineWidth: 0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ZiweiPosterView: View {
    let chart: ZiweiChart
    let name: String
    var style: PosterStyle = .songQingdai

    private var pal: PosterPalette { style.palette }
    private var mingCard: (title: String, conclusion: String, facts: String)? {
        ZiweiReading.cards(chart: chart).first { $0.title == "命宫定型" }
    }
    // 生年四化：全盘主星＋辅星带化者（年干四化表恰为 4 颗，不编不凑）
    private var huaItems: [(star: String, kind: String, palace: String)] {
        var out: [(star: String, kind: String, palace: String)] = []
        for p in chart.palaces {
            for m in p.majors where m.mutagen != nil { out.append((star: m.star, kind: m.mutagen!, palace: p.name)) }
            for s in p.minors where s.mutagen != nil { out.append((star: s.star, kind: s.mutagen!, palace: p.name)) }
        }
        return out
    }

    private var board: some View {
        let c = chart.palaces
        return VStack(spacing: 5) {
            HStack(spacing: 5) {
                ZiweiMiniCell(p: c[5], pal: pal, isMing: chart.mingGong == 5)
                ZiweiMiniCell(p: c[6], pal: pal, isMing: chart.mingGong == 6)
                ZiweiMiniCell(p: c[7], pal: pal, isMing: chart.mingGong == 7)
                ZiweiMiniCell(p: c[8], pal: pal, isMing: chart.mingGong == 8)
            }
            HStack(spacing: 5) {
                VStack(spacing: 5) {
                    ZiweiMiniCell(p: c[4], pal: pal, isMing: chart.mingGong == 4)
                    ZiweiMiniCell(p: c[3], pal: pal, isMing: chart.mingGong == 3)
                }
                ZiweiCenterCell(chart: chart, pal: pal)
                VStack(spacing: 5) {
                    ZiweiMiniCell(p: c[9], pal: pal, isMing: chart.mingGong == 9)
                    ZiweiMiniCell(p: c[10], pal: pal, isMing: chart.mingGong == 10)
                }
            }
            HStack(spacing: 5) {
                ZiweiMiniCell(p: c[2], pal: pal, isMing: chart.mingGong == 2)
                ZiweiMiniCell(p: c[1], pal: pal, isMing: chart.mingGong == 1)
                ZiweiMiniCell(p: c[0], pal: pal, isMing: chart.mingGong == 0)
                ZiweiMiniCell(p: c[11], pal: pal, isMing: chart.mingGong == 11)
            }
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [pal.bg1, pal.bg0], startPoint: .top, endPoint: .bottom)
            if style != .songQingdai {
                RadialGradient(colors: [pal.accent.opacity(0.14), .clear], center: .init(x: 0.5, y: 0.16), startRadius: 10, endRadius: 300)
                RoundedRectangle(cornerRadius: 10).stroke(pal.accent.opacity(0.55), lineWidth: 1.1).padding(18)
                RoundedRectangle(cornerRadius: 6).stroke(pal.accent.opacity(0.25), lineWidth: 0.7).padding(24)
            } else {
                RoundedRectangle(cornerRadius: 4).stroke(pal.cardStroke, lineWidth: 1.0).padding(22)
                VStack {
                    Spacer()
                    SongMountainHeaderView(accent: pal.accent)
                        .padding(.horizontal, 23).padding(.bottom, 23)
                }
            }

            VStack(spacing: 0) {
                if style == .songQingdai {
                    Text("紫 微 斗 数 · 命 盘 雅 集")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(4)
                        .foregroundStyle(pal.accent)
                        .padding(.top, 52)
                    Text(name.isEmpty ? "紫微命盘" : name)
                        .font(.system(size: 44, weight: .bold, design: .serif))
                        .foregroundStyle(pal.main)
                        .padding(.top, 16)
                } else {
                    BaguaRingView(size: 132, accent: pal.accent, accentHi: pal.accentHi).padding(.top, 42)
                    Text("三 术 合 参").font(.system(size: 14, design: .serif)).tracking(2).foregroundStyle(pal.accentHi).padding(.top, 12)
                    Text(name.isEmpty ? "紫微命盘" : name)
                        .font(.system(size: 40, weight: .semibold, design: .serif)).foregroundStyle(pal.main).padding(.top, 18)
                }

                Text("\(chart.juName) · \(chart.lunarText)")
                    .font(.system(size: 12)).foregroundStyle(pal.sub).padding(.top, 8)

                HStack(spacing: 8) {
                    Rectangle().fill(pal.cardStroke).frame(width: 140, height: 0.8)
                    Rectangle().fill(pal.accent).frame(width: 5, height: 5).rotationEffect(.degrees(45))
                    Rectangle().fill(pal.cardStroke).frame(width: 140, height: 0.8)
                }.padding(.vertical, 16)

                board

                // 命宫定型（取自 ZiweiReading 第一卡，不另编断语）
                if let mc = mingCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("命宫定型 · \(mc.facts)")
                            .font(.system(size: 12, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
                        Text(mc.conclusion)
                            .font(.system(size: 12.5)).foregroundStyle(pal.main)
                            .lineSpacing(3.5).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(width: 444, alignment: .leading)
                    .background(pal.card)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(pal.cardStroke, lineWidth: 0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 16)
                }

                // 生年四化
                VStack(alignment: .leading, spacing: 8) {
                    Text("生年四化 · 四化落哪宫，哪宫就是一生反复出题之处")
                        .font(.system(size: 12, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(huaItems, id: \.star) { h in
                            HStack(spacing: 4) {
                                Text(h.star).font(.system(size: 12, weight: .semibold, design: .serif)).foregroundStyle(pal.main)
                                Text("化\(h.kind)").font(.system(size: 12, weight: .bold)).foregroundStyle(h.kind == "忌" ? pCin : pal.accent)
                                Text("入\(h.palace)").font(.system(size: 12)).foregroundStyle(pal.sub)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(pal.card)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(pal.cardStroke, lineWidth: 0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
                .frame(width: 444, alignment: .leading)
                .padding(.top, 16)

                Spacer()

                HStack(alignment: .bottom) {
                    VStack(spacing: 1) {
                        HStack(spacing: 1) {
                            Text("三").font(.system(size: 14, weight: .bold, design: .serif))
                            Text("术").font(.system(size: 14, weight: .bold, design: .serif))
                        }
                        HStack(spacing: 1) {
                            Text("合").font(.system(size: 14, weight: .bold, design: .serif))
                            Text("参").font(.system(size: 14, weight: .bold, design: .serif))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(pCin)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("三合派天纪口径 · 方盘缩印 · 生年四化")
                            .font(.system(size: 11, design: .serif)).foregroundStyle(pal.accent)
                        Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 10)).foregroundStyle(pal.sub.opacity(0.8))
                    }
                }
                .padding(.horizontal, 48).padding(.bottom, 42)
            }
        }
        .frame(width: 540, height: 960)
    }
}

struct ZiweiPosterSheetView: View {
    let chart: ZiweiChart
    let name: String
    @State private var fileURL: URL?
    @State private var style: PosterStyle = .songQingdai

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                Picker("海报版本", selection: $style) {
                    ForEach(PosterStyle.allCases, id: \.self) { s in Text(s.rawValue).tag(s) }
                }
                .pickerStyle(.segmented)
                .onChange(of: style) { _, _ in fileURL = nil; render() }

                ZiweiPosterView(chart: chart, name: name, style: style)
                    .scaleEffect(0.62)
                    .frame(width: 540 * 0.62, height: 960 * 0.62)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)

                if let u = fileURL {
                    ShareLink(item: u) {
                        Label("保存 / 分享高清紫微命盘海报（1080×1920）", systemImage: "square.and.arrow.down")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(KyPrimaryButton())
                    Text("在系统分享菜单中点「存储图像」即可存入手机相册，或直接转发微信。")
                        .font(.caption).foregroundStyle(Ky.sub).multilineTextAlignment(.center)
                } else {
                    ProgressView("正在渲染 1080×1920 高清海报…")
                }
            }
            .padding(20)
        }
        .background(Ky.bg)
        .navigationTitle("紫微命盘海报")
        .navigationBarTitleDisplayMode(.inline)
        .task { render() }
    }

    private func render() {
        let renderer = ImageRenderer(content: ZiweiPosterView(chart: chart, name: name, style: style))
        renderer.scale = 2.0
        if let img = renderer.uiImage, let data = img.pngData() {
            let suffix: String
            switch style {
            case .songQingdai: suffix = "-song"
            case .yuceDan: suffix = "-yucedan"
            case .xuanPaper: suffix = "-xuan"
            case .inkGold: suffix = "-ink"
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ziwei-poster-\(name.isEmpty ? "chart" : name)\(suffix).png")
            try? data.write(to: url, options: .atomic)
            fileURL = url
        }
    }
}

// MARK: - 合参海报（一页三术要点：八字总断＋紫微命宫＋手相要点）

struct HeCanPosterView: View {
    let bazi: BaziChart
    let ziwei: ZiweiChart
    let name: String
    var palmLines: [String] = []
    var style: PosterStyle = .songQingdai

    private var items: [InterpretItem] { InterpretEngine.interpret(chart: bazi) }
    private var headline: String { items.first(where: { $0.title == "命局风景" })?.conclusion ?? "" }
    private var gejuLine: String { items.first(where: { $0.title == "月令格局（候选）" })?.conclusion ?? "" }
    private var yunLine: String { items.first(where: { $0.title == "岁运要点" })?.conclusion ?? "" }
    private var pal: PosterPalette { style.palette }
    private var mingCard: (title: String, conclusion: String, facts: String)? {
        ZiweiReading.cards(chart: ziwei).first { $0.title == "命宫定型" }
    }
    private var huaLine: String {
        var parts: [String] = []
        for p in ziwei.palaces {
            for m in p.majors where m.mutagen != nil { parts.append("\(m.star)化\(m.mutagen!)入\(p.name)") }
            for s in p.minors where s.mutagen != nil { parts.append("\(s.star)化\(s.mutagen!)入\(p.name)") }
        }
        return parts.joined(separator: " · ")
    }
    private var mingStars: String {
        let ming = ziwei.palaces[ziwei.mingGong]
        return ming.majors.isEmpty ? "无主星（借对宫）" : ming.majors.map { $0.star }.joined(separator: "、")
    }

    private func sectionCard(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
            content()
        }
        .padding(16)
        .frame(width: 444, alignment: .leading)
        .background(pal.card)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(pal.cardStroke, lineWidth: 0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [pal.bg1, pal.bg0], startPoint: .top, endPoint: .bottom)
            if style != .songQingdai {
                RadialGradient(colors: [pal.accent.opacity(0.14), .clear], center: .init(x: 0.5, y: 0.16), startRadius: 10, endRadius: 300)
                RoundedRectangle(cornerRadius: 10).stroke(pal.accent.opacity(0.55), lineWidth: 1.1).padding(18)
                RoundedRectangle(cornerRadius: 6).stroke(pal.accent.opacity(0.25), lineWidth: 0.7).padding(24)
            } else {
                RoundedRectangle(cornerRadius: 4).stroke(pal.cardStroke, lineWidth: 1.0).padding(22)
                VStack {
                    Spacer()
                    SongMountainHeaderView(accent: pal.accent)
                        .padding(.horizontal, 23).padding(.bottom, 23)
                }
            }

            VStack(spacing: 0) {
                if style == .songQingdai {
                    Text("三 术 合 参 · 一 页 要 点")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(4)
                        .foregroundStyle(pal.accent)
                        .padding(.top, 52)
                    Text(name.isEmpty ? "合参总览" : name)
                        .font(.system(size: 44, weight: .bold, design: .serif))
                        .foregroundStyle(pal.main)
                        .padding(.top, 16)
                } else {
                    BaguaRingView(size: 132, accent: pal.accent, accentHi: pal.accentHi).padding(.top, 42)
                    Text("三 术 合 参").font(.system(size: 14, design: .serif)).tracking(2).foregroundStyle(pal.accentHi).padding(.top, 12)
                    Text(name.isEmpty ? "合参总览" : name)
                        .font(.system(size: 40, weight: .semibold, design: .serif)).foregroundStyle(pal.main).padding(.top, 18)
                }

                Text("日主 \(bazi.rizhu) · \(ziwei.juName) · 命宫\(ziwei.palaces[ziwei.mingGong].stem)\(ZiweiCore.DZ[ziwei.mingGong])")
                    .font(.system(size: 12)).foregroundStyle(pal.sub).padding(.top, 8)

                HStack(spacing: 8) {
                    Rectangle().fill(pal.cardStroke).frame(width: 140, height: 0.8)
                    Rectangle().fill(pal.accent).frame(width: 5, height: 5).rotationEffect(.degrees(45))
                    Rectangle().fill(pal.cardStroke).frame(width: 140, height: 0.8)
                }.padding(.vertical, 16)

                // 四柱小字行（干支按五行分色，日柱描金边）
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { i in
                        let gz = Array(bazi.pillars[i])
                        VStack(spacing: 4) {
                            Text(["年柱", "月柱", "日柱", "时柱"][i])
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(pal.sub)
                            Text(String(gz[0]))
                                .font(.system(size: 28, weight: .bold, design: .serif))
                                .foregroundStyle(posterCharColor(gz[0], fallback: pal.main))
                            Text(String(gz[1]))
                                .font(.system(size: 28, weight: .bold, design: .serif))
                                .foregroundStyle(posterCharColor(gz[1], fallback: pal.main))
                            Text(i == 2 ? "日主" : bazi.stemShiShen[i])
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(i == 2 ? pal.accentHi : pal.accent)
                        }
                        .frame(width: 82, height: 122)
                        .background(pal.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(i == 2 ? pal.accentHi.opacity(0.65) : pal.cardStroke, lineWidth: i == 2 ? 1.2 : 0.8)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                // 八字总断
                sectionCard(title: "八字总断") {
                    if !headline.isEmpty {
                        Text(headline)
                            .font(.system(size: 13.5, design: .serif)).foregroundStyle(pal.main)
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }
                    if !gejuLine.isEmpty {
                        Text(gejuLine)
                            .font(.system(size: 12.5)).foregroundStyle(pal.accent)
                            .lineSpacing(3.5).fixedSize(horizontal: false, vertical: true)
                    }
                    if !yunLine.isEmpty {
                        Text(yunLine)
                            .font(.system(size: 11.5)).foregroundStyle(pal.sub)
                            .lineSpacing(3).lineLimit(2)
                    }
                }
                .padding(.top, 18)

                // 紫微命宫
                sectionCard(title: "紫微命宫 · \(mingStars)") {
                    if let mc = mingCard {
                        Text(mc.conclusion)
                            .font(.system(size: 12.5)).foregroundStyle(pal.main)
                            .lineSpacing(3.5).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                    if !huaLine.isEmpty {
                        Text(huaLine)
                            .font(.system(size: 11.5)).foregroundStyle(pal.accent)
                            .lineSpacing(3).lineLimit(2)
                    }
                }
                .padding(.top, 14)

                // 手相面相要点（只引已存测量摘要，无记录时明言未测，不编）
                sectionCard(title: "手相面相要点") {
                    if palmLines.isEmpty {
                        Text("尚未测量：在「手相面相」页测一张掌纹并按人保存后，这里会自动带上测量摘要。判读为娱乐参考。")
                            .font(.system(size: 12)).foregroundStyle(pal.sub).lineSpacing(3.5)
                    } else {
                        ForEach(palmLines, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 12.5)).foregroundStyle(pal.main)
                                .lineSpacing(3.5).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 14)

                Spacer()

                HStack(alignment: .bottom) {
                    VStack(spacing: 1) {
                        HStack(spacing: 1) {
                            Text("三").font(.system(size: 14, weight: .bold, design: .serif))
                            Text("术").font(.system(size: 14, weight: .bold, design: .serif))
                        }
                        HStack(spacing: 1) {
                            Text("合").font(.system(size: 14, weight: .bold, design: .serif))
                            Text("参").font(.system(size: 14, weight: .bold, design: .serif))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(pCin)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("八字总断 · 紫微命宫 · 手相要点 · 一页合参")
                            .font(.system(size: 11, design: .serif)).foregroundStyle(pal.accent)
                        Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 10)).foregroundStyle(pal.sub.opacity(0.8))
                    }
                }
                .padding(.horizontal, 48).padding(.bottom, 42)
            }
        }
        .frame(width: 540, height: 960)
    }
}

struct HeCanPosterSheetView: View {
    let bazi: BaziChart
    let ziwei: ZiweiChart
    let name: String
    var palmLines: [String] = []
    @State private var fileURL: URL?
    @State private var style: PosterStyle = .songQingdai

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                Picker("海报版本", selection: $style) {
                    ForEach(PosterStyle.allCases, id: \.self) { s in Text(s.rawValue).tag(s) }
                }
                .pickerStyle(.segmented)
                .onChange(of: style) { _, _ in fileURL = nil; render() }

                HeCanPosterView(bazi: bazi, ziwei: ziwei, name: name, palmLines: palmLines, style: style)
                    .scaleEffect(0.62)
                    .frame(width: 540 * 0.62, height: 960 * 0.62)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)

                if let u = fileURL {
                    ShareLink(item: u) {
                        Label("保存 / 分享高清合参海报（1080×1920）", systemImage: "square.and.arrow.down")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(KyPrimaryButton())
                    Text("在系统分享菜单中点「存储图像」即可存入手机相册，或直接转发微信。")
                        .font(.caption).foregroundStyle(Ky.sub).multilineTextAlignment(.center)
                } else {
                    ProgressView("正在渲染 1080×1920 高清海报…")
                }
            }
            .padding(20)
        }
        .background(Ky.bg)
        .navigationTitle("合参海报")
        .navigationBarTitleDisplayMode(.inline)
        .task { render() }
    }

    private func render() {
        let renderer = ImageRenderer(content: HeCanPosterView(bazi: bazi, ziwei: ziwei, name: name, palmLines: palmLines, style: style))
        renderer.scale = 2.0
        if let img = renderer.uiImage, let data = img.pngData() {
            let suffix: String
            switch style {
            case .songQingdai: suffix = "-song"
            case .yuceDan: suffix = "-yucedan"
            case .xuanPaper: suffix = "-xuan"
            case .inkGold: suffix = "-ink"
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("hecan-poster-\(name.isEmpty ? "chart" : name)\(suffix).png")
            try? data.write(to: url, options: .atomic)
            fileURL = url
        }
    }
}
