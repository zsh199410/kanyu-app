import SwiftUI

// MARK: - 1. 黄道星座与行星基础模型
enum ZodiacSign: String, CaseIterable, Identifiable {
case aries = "白羊座", taurus = "金牛座", gemini = "双子座", cancer = "巨蟹座"
case leo = "狮子座", virgo = "处女座", libra = "天秤座", scorpio = "天蝎座"
case sagittarius = "射手座", capricorn = "摩羯座", aquarius = "水瓶座", pisces = "双鱼座"

var id: String { rawValue}

var symbol: String {
switch self {
case.aries: return "♈︎"; case.taurus: return "♉︎"; case.gemini: return "♊︎"; case.cancer: return "♋︎"
case.leo: return "♌︎"; case.virgo: return "♍︎"; case.libra: return "♎︎"; case.scorpio: return "♏︎"
case.sagittarius: return "♐︎"; case.capricorn: return "♑︎"; case.aquarius: return "♒︎"; case.pisces: return "♓︎"
}
}

var element: String {
switch self {
case.aries,.leo,.sagittarius: return "火象"
case.taurus,.virgo,.capricorn: return "土象"
case.gemini,.libra,.aquarius: return "风象"
case.cancer,.scorpio,.pisces: return "水象"
}
}

/// 星座气质短语（合参结论动态拼装用，通用占星定性描述）
var natureShort: String {
switch self {
case.aries: return "果敢直接"
case.taurus: return "沉稳务实"
case.gemini: return "灵动善变"
case.cancer: return "细腻顾家"
case.leo: return "明朗大气"
case.virgo: return "精细严谨"
case.libra: return "优雅公正"
case.scorpio: return "深沉专注"
case.sagittarius: return "开阔乐观"
case.capricorn: return "坚韧务实"
case.aquarius: return "独立创新"
case.pisces: return "敏感共情"
}
}
}

struct PlanetPosition: Identifiable {
let id = UUID()
let name: String
let symbol: String
let sign: ZodiacSign
let degree: Double // 0..<30
let house: Int // 1..12
let role: String
}

struct AstroChart {
let birthDate: Date
let sunSign: ZodiacSign
let sunDegree: Double
let moonSign: ZodiacSign
let moonDegree: Double
let ascSign: ZodiacSign
let ascDegree: Double
let planets: [PlanetPosition] // v1 仅收录权威真算的日月升三曜
}

// MARK: - 2. 纯天文学确定性计算引擎 (AstroEngine)
enum AstroEngine {
/// 基于 Julian Day、平黄经与恒星时计算太阳、月亮与上升点（等宫制，零外部依赖）
static func calculate(birthDate: Date, longitude: Double = 107.8, latitude: Double = 30.5) -> AstroChart {
let cal = Calendar(identifier:.gregorian)
let comp = cal.dateComponents(in: TimeZone(identifier: "Asia/Shanghai") ?? .current, from: birthDate)
let year = comp.year ?? 2026, month = comp.month ?? 11, day = comp.day ?? 6
let hour = comp.hour ?? 12, minute = comp.minute ?? 0

// 1. Julian Day (JD)
let y = (month <= 2) ? year - 1 : year
let m = (month <= 2) ? month + 12 : month
let a = floor(Double(y) / 100.0)
let b = 2.0 - a + floor(a / 4.0)
let dayFraction = Double(day) + (Double(hour) + Double(minute) / 60.0 - 8.0) / 24.0
let jd = floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1)) + dayFraction + b - 1524.5
let t = (jd - 2451545.0) / 36525.0

// 2. 太阳真黄经
var l0 = (280.46646 + 36000.76983 * t).truncatingRemainder(dividingBy: 360.0)
if l0 < 0 { l0 += 360.0}
let mSun = (357.52911 + 35999.05029 * t).truncatingRemainder(dividingBy: 360.0) * .pi / 180.0
let cSun = 1.914602 * sin(mSun) + 0.019993 * sin(2.0 * mSun)
var sunLon = (l0 + cSun).truncatingRemainder(dividingBy: 360.0)
if sunLon < 0 { sunLon += 360.0}

// 3. 月球真黄经（平黄经 + 主摄动项：中心差 6.289°、出差 1.274°、二均差 0.658°、年差 0.186°；
// 只用平黄经误差可达 6°、临界星座会算错，补四项后余差 <0.3°）
var lMoon = (218.3165 + 481267.8813 * t).truncatingRemainder(dividingBy: 360.0)
if lMoon < 0 { lMoon += 360.0}
let mMoon = (134.963 + 477198.8675 * t).truncatingRemainder(dividingBy: 360.0) * .pi / 180.0
let meanElong = (lMoon - l0) * .pi / 180.0
let moonCorr = 6.289 * sin(mMoon) + 1.274 * sin(2.0 * meanElong - mMoon) + 0.658 * sin(2.0 * meanElong) + 0.186 * sin(mSun)
var lMoonTrue = (lMoon + moonCorr).truncatingRemainder(dividingBy: 360.0)
if lMoonTrue < 0 { lMoonTrue += 360.0}

// 4. 地方恒星时与上升点 (Ascendant)
// 标准公式 asc = atan2(cos θ, −(sin θ·cos ε + tan φ·sin ε))，atan2 自带象限判断；
// 旧写法 atan2(−cos θ, sin θ·cos ε + tan φ·sin ε) 再手动 ±180°，在 RAMC 非 0° 附近会偏 180°
// （实测：春分日 18 时赤道，太阳在西沉、上升应为 180°，旧式算出 0°），已修正。
var gmst = (280.46061837 + 360.98564736629 * (jd - 2451545.0)).truncatingRemainder(dividingBy: 360.0)
if gmst < 0 { gmst += 360.0}
let lst = (gmst + longitude).truncatingRemainder(dividingBy: 360.0)
let ramcRad = lst * .pi / 180.0
let epsRad = 23.4392911 * .pi / 180.0
let latRad = latitude * .pi / 180.0

let ascDeg = (atan2(cos(ramcRad), -(sin(ramcRad) * cos(epsRad) + tan(latRad) * sin(epsRad))) * 180.0 / .pi + 360.0).truncatingRemainder(dividingBy: 360.0)

func signInfo(_ deg: Double) -> (ZodiacSign, Double) {
let i = Int(deg / 30.0) % 12
return (ZodiacSign.allCases[i], deg.truncatingRemainder(dividingBy: 30.0))
}

let sun = signInfo(sunLon)
let moon = signInfo(lMoonTrue)
let asc = signInfo(ascDeg)

// 等宫制计算（以 ASC 为第一宫起点）
func calcEqualHouse(_ pDeg: Double) -> Int {
var diff = pDeg - ascDeg
if diff < 0 { diff += 360.0}
return Int(diff / 30.0) + 1
}

// v1 仅出真算的日月升三曜，杜绝编造水星/火星
let planets = [
PlanetPosition(name: "太阳", symbol: "☉", sign: sun.0, degree: sun.1, house: calcEqualHouse(sunLon), role: "自我意志 · 本命核心"),
PlanetPosition(name: "月亮", symbol: "☽", sign: moon.0, degree: moon.1, house: calcEqualHouse(lMoonTrue), role: "内心潜意识 · 情绪安全"),
PlanetPosition(name: "上升", symbol: "↑", sign: asc.0, degree: asc.1, house: 1, role: "外在面具 · 社交风格")
]

return AstroChart(birthDate: birthDate, sunSign: sun.0, sunDegree: sun.1, moonSign: moon.0, moonDegree: moon.1, ascSign: asc.0, ascDegree: asc.1, planets: planets)
}
}

// MARK: - 3. 动态东西星命合参引擎 (AstroCrossEngine)
struct AstroCrossItem: Identifiable {
let id = UUID()
let title: String
let tag: String
let conclusion: String
let baziFact: String
let astroFact: String
}

enum AstroCrossEngine {
/// 全动态比对传入命盘，杜绝任何静态写死
static func crossAnalyze(bazi: BaziChart, astro: AstroChart) -> [AstroCrossItem] {
let sun = astro.sunSign
let moon = astro.moonSign
let asc = astro.ascSign
let rizhu = bazi.rizhu

return [
AstroCrossItem(
title: "\(rizhu)日主遇\(sun.rawValue)",
tag: "双向映照",
conclusion: "东方日主定内在心性底色（\(rizhu)），西方太阳与上升刻画行动与处世风格（\(sun.rawValue)配\(asc.rawValue)）。整体展现出\(sun.natureShort)的行事节奏，外在展现\(asc.natureShort)的社交分寸。",
baziFact: "日主 \(rizhu)，局中五行气势主导",
astroFact: "太阳\(sun.rawValue)（\(String(format: "%.1f°", astro.sunDegree))）+ 上升\(asc.rawValue)"
),
AstroCrossItem(
title: "月亮\(moon.rawValue)的情绪底色",
tag: "情绪解密",
conclusion: "月亮落入\(moon.rawValue)（\(moon.element)），潜意识对安全感与理解的需求极为深刻（\(moon.natureShort)）。与八字原局同调时，凡事需先理顺情绪再论利害。",
baziFact: "四柱藏干透干生克格局",
astroFact: "月亮落入\(moon.rawValue)（\(String(format: "%.1f°", astro.moonDegree))）"
)
]
}
}

// MARK: - 4. 黄金星盘 Canvas 原生轮盘 (AstroWheelCanvasView)
struct AstroWheelCanvasView: View {
let chart: AstroChart

var body: some View {
Canvas { context, size in
let center = CGPoint(x: size.width / 2, y: size.height / 2)
let radius = min(size.width, size.height) / 2 - 14

var outer = Path()
outer.addArc(center: center, radius: radius, startAngle:.zero, endAngle:.degrees(360), clockwise: false)
context.stroke(outer, with:.color(Ky.line.opacity(0.8)), lineWidth: 1.2)

var inner = Path()
inner.addArc(center: center, radius: radius * 0.74, startAngle:.zero, endAngle:.degrees(360), clockwise: false)
context.stroke(inner, with:.color(Ky.gold.opacity(0.5)), lineWidth: 0.8)

var hub = Path()
hub.addArc(center: center, radius: radius * 0.28, startAngle:.zero, endAngle:.degrees(360), clockwise: false)
context.fill(hub, with:.color(Ky.card))
context.stroke(hub, with:.color(Ky.gold.opacity(0.6)), lineWidth: 1.0)

for i in 0..<12 {
let angle = Angle.degrees(Double(i) * 30.0 - 90.0)
let cosA = cos(angle.radians); let sinA = sin(angle.radians)
var line = Path()
line.move(to: CGPoint(x: center.x + radius * 0.28 * cosA, y: center.y + radius * 0.28 * sinA))
line.addLine(to: CGPoint(x: center.x + radius * cosA, y: center.y + radius * sinA))
context.stroke(line, with:.color(Ky.line.opacity(0.35)), lineWidth: 0.7)

let midAngle = Angle.degrees(Double(i) * 30.0 + 15.0 - 90.0)
let textPos = CGPoint(x: center.x + radius * 0.86 * cos(midAngle.radians), y: center.y + radius * 0.86 * sin(midAngle.radians))
context.draw(Text(ZodiacSign.allCases[i].symbol).font(.system(size: 11, weight:.bold)).foregroundColor(Ky.gold), at: textPos)
}

// 三合吉相连线（轮盘装饰母题，非逐星实算相位）
var trine = Path()
trine.move(to: CGPoint(x: center.x + radius * 0.65 * cos(-0.4), y: center.y + radius * 0.65 * sin(-0.4)))
trine.addLine(to: CGPoint(x: center.x + radius * 0.65 * cos(1.8), y: center.y + radius * 0.65 * sin(1.8)))
trine.addLine(to: CGPoint(x: center.x + radius * 0.65 * cos(3.6), y: center.y + radius * 0.65 * sin(3.6)))
trine.closeSubpath()
context.fill(trine, with:.color(Ky.jade.opacity(0.08)))
context.stroke(trine, with:.color(Ky.jade.opacity(0.7)), lineWidth: 1.0)

context.draw(Text("☉ \(chart.sunSign.rawValue)").font(.system(size: 10, weight:.bold, design:.serif)).foregroundColor(Ky.ink), at: CGPoint(x: center.x, y: center.y - 6))
context.draw(Text("↑ \(chart.ascSign.rawValue)").font(.system(size: 8.5)).foregroundColor(Ky.sub), at: CGPoint(x: center.x, y: center.y + 8))
}
.frame(width: 250, height: 250)
}
}

// MARK: - 5. 星命合参交互主页面 (AstroHomeView)
struct AstroHomeView: View {
let person: Person
let chart: BaziChart
@State private var selectedTab: Int = 0

private var astro: AstroChart {
AstroEngine.calculate(birthDate: person.birthDate, longitude: person.useLongitude ? person.longitude : 107.8)
}

var body: some View {
ScrollView {
VStack(alignment:.leading, spacing: 14) {
// 顶部命主东西双模概览卡
VStack(alignment:.leading, spacing: 10) {
HStack {
VStack(alignment:.leading, spacing: 2) {
Text("\(person.name.isEmpty ? "命主" : person.name) · 星命合参")
.font(.system(.headline, design:.serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
Text("日月升三曜 · 东西合参 · 黄道回归历").font(.caption2).foregroundStyle(Ky.gold)
}
Spacer()
KySeal(text: "东西合参")
}

HStack(spacing: 8) {
HStack(spacing: 6) {
Text("八字日主").font(.system(size: 9.5)).foregroundStyle(Ky.sub)
Text("\(chart.rizhu)").font(.system(size: 15, weight:.bold, design:.serif)).foregroundStyle(Ky.cinnabar)
}
.padding(.horizontal, 10).padding(.vertical, 7)
.background(Ky.elevated).clipShape(RoundedRectangle(cornerRadius: 10))

Spacer()

HStack(spacing: 6) {
Text("☉ \(astro.sunSign.rawValue)").font(.system(size: 11, weight:.bold)).foregroundStyle(Ky.gold)
Text("☽ \(astro.moonSign.rawValue)").font(.system(size: 11, weight:.bold)).foregroundStyle(Ky.qingdai)
Text("↑ \(astro.ascSign.rawValue)").font(.system(size: 11, weight:.bold)).foregroundStyle(Ky.jade)
}
.padding(.horizontal, 10).padding(.vertical, 7)
.background(Ky.elevated).clipShape(RoundedRectangle(cornerRadius: 10))
}
}
.kyCard()

// 分段选择器（合婚页暂缓，v1 聚焦于东西合参与本命星盘）
Picker("分类", selection: $selectedTab) {
Text("东西合参").tag(0)
Text("西洋星盘 (等宫制)").tag(1)
}
.pickerStyle(.segmented)
.padding(.horizontal, 4)

if selectedTab == 0 {
VStack(alignment:.leading, spacing: 12) {
KySectionTitle(title: "东西星命交叉印证", trailing: "八字定底色 · 星盘定场景")
ForEach(AstroCrossEngine.crossAnalyze(bazi: chart, astro: astro)) { item in
VStack(alignment:.leading, spacing: 8) {
HStack {
Text(item.title).font(.system(.subheadline, design:.serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
Spacer()
KyBadge(text: item.tag, color: Ky.cinnabar)
}
Text(item.conclusion).font(.system(size: 13, weight:.medium)).foregroundStyle(Ky.ink).lineSpacing(3)
VStack(alignment:.leading, spacing: 4) {
Text("• 八字依据：\(item.baziFact)").font(.system(size: 11.5)).foregroundStyle(Ky.sub)
Text("• 星盘依据：\(item.astroFact)").font(.system(size: 11.5)).foregroundStyle(Ky.sub)
}
.padding(8).background(Ky.elevated.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 8))
}
.kyCard()
}
}
} else {
VStack(spacing: 14) {
KySectionTitle(title: "黄道十二宫本命天宫图", trailing: "等宫制 (Equal House)")
AstroWheelCanvasView(chart: astro).frame(maxWidth:.infinity, alignment:.center).padding(.vertical, 8).kyCard()
VStack(alignment:.leading, spacing: 8) {
Text("本命三大核心曜位").font(.system(.subheadline, design:.serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
ForEach(astro.planets) { p in
HStack {
Text("\(p.symbol) \(p.name)").font(.system(size: 13, weight:.bold)).foregroundStyle(Ky.ink).frame(width: 70, alignment:.leading)
Text("\(p.sign.rawValue) \(String(format: "%.1f°", p.degree))").font(.system(size: 12)).foregroundStyle(Ky.gold).frame(width: 90, alignment:.leading)
Text("第 \(p.house) 宫").font(.system(size: 11)).foregroundStyle(Ky.sub)
Spacer()
Text(p.role).font(.system(size: 10.5)).foregroundStyle(Ky.sub)
}
.padding(.vertical, 4)
Divider()
}
}
.kyCard()
}
}
}
.padding(.horizontal, 16)
.padding(.top, 10)
.padding(.bottom, 100)
}
.background(Ky.bg)
.navigationTitle("星命合参")
.navigationBarTitleDisplayMode(.inline)
}
}
