import SwiftUI
import UIKit
import Photos

// MARK: - 命盘海报 v5（定版「宋纸青黛版」为唯一款式，严格对齐《模板规范-2026-10-29.md》）

private let pPaper = Color(red: 0.968, green: 0.949, blue: 0.906) // #F7F2E7 宋纸
private let pSub = Color(red: 0.478, green: 0.447, blue: 0.408)   // #7A7268 次级
private let pCin = Color(red: 0.604, green: 0.165, blue: 0.133)   // #9A2A22 故宫红
private let pTeal = Color(red: 0.153, green: 0.306, blue: 0.361)  // #274E5C 青黛

// MARK: - 海报版本：只留一款——宋纸青黛版（定版规范），做到极致；尊享预测单为独立长图产品（不占款式位）
enum PosterStyle: String, CaseIterable {
    case songQingdai = "宋纸青黛版"
    case yuceDan = "尊享预测单"
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
        }
    }
}

// MARK: - 导出后缀（internal：PosterEditorModule 共用）
// 只留宋纸青黛一款：三视图均已解包为无条件宋式版式；尊享预测单走独立布局分支，不进 standardPosterView。
extension PosterStyle {
    var fileSuffix: String {
        switch self {
        case .songQingdai: return "-song"
        case .yuceDan: return "-yucedan"
        }
    }
}

// MARK: - 保存图片到相册（4 个海报导出点共用）
// PHPhotoLibrary 回调在任意队列，状态一律回主线程再写；成功／失败都给一句话，绝不静默失败。
// 权限：Info.plist 须配 NSPhotoLibraryAddUsageDescription（仅写入相册）。
struct PosterPhotoSaver {
    static func save(_ image: UIImage, completion: @escaping (String) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    completion("已存入相册")
                } else if let error = error {
                    completion("保存失败：\(error.localizedDescription)")
                } else {
                    completion("保存失败：未知原因，请检查相册权限后重试")
                }
            }
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

/// 竖排短题（中文竖排：字形不旋转，逐字自上而下；只用于宋纸版眉题短句。全文竖排不做：长文逐字排版拖垮渲染且须手写断栏，见本轮汇报）
private struct VerticalText: View {
    let text: String
    var fontSize: CGFloat = 13
    var color: Color = pTeal
    var spacing: CGFloat = 5
    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(.system(size: fontSize, weight: .medium, design: .serif))
                    .foregroundStyle(color)
            }
        }
    }
}

/// 海报统一品牌印章（P3 第 1 项）：全站海报共用同一枚朱砂印章——42×42、朱砂底、白字「三术合参」两行；
/// 替代此前三处 42×42 与预测单 40×40 描边章各自为政的写法，印文一字不动。
private struct PosterSealView: View {
    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 1) {
                Text("三")
                Text("术")
            }
            HStack(spacing: 1) {
                Text("合")
                Text("参")
            }
        }
        .font(.system(size: 14, weight: .bold, design: .serif))
        .foregroundStyle(.white)
        .frame(width: 42, height: 42)
        .background(pCin)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// 海报统一品牌落款条（P3 第 1 项）：印章＋品牌行「三术合参 · 堪舆命理院 谨制」＋各款副标＋日期；
/// 全站同一结构、同一品牌行；副标与日期各款原文保留，底留白统一 42pt（P3 第 6 项）。
private struct PosterBrandFooter: View {
    let pal: PosterPalette
    let subtitle: String
    var body: some View {
        HStack(alignment: .bottom) {
            PosterSealView()
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("三术合参 · 堪舆命理院 谨制")
                    .font(.system(size: 12, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
                Text(subtitle)
                    .font(.system(size: 11, design: .serif)).foregroundStyle(pal.accent)
                Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 10)).foregroundStyle(pal.sub.opacity(0.8))
            }
        }
        .padding(.horizontal, 48).padding(.bottom, 42)
    }
}

/// 五行雷达大图（五边形：木火土金水顺时针；按占比归一化，最大者满半径；供墨金版海报用）
private struct WuxingRadarView: View {
    let pcts: [Double]
    let accent: Color
    let track: Color
    let size: CGFloat
    private let names = ["木", "火", "土", "金", "水"]
    private func point(_ i: Int, scale: CGFloat) -> CGPoint {
        let a = (-90.0 + Double(i) * 72.0) * Double.pi / 180.0
        let r = size / 2 * 0.78 * scale
        return CGPoint(x: size / 2 + r * CGFloat(cos(a)), y: size / 2 + r * CGFloat(sin(a)))
    }
    var body: some View {
        let maxV = max(pcts.max() ?? 1, 1)
        return ZStack {
            Path { p in
                for i in 0..<5 { let q = point(i, scale: 1.0); if i == 0 { p.move(to: q) } else { p.addLine(to: q) } }
                p.closeSubpath()
            }.stroke(track, lineWidth: 0.8)
            Path { p in
                for i in 0..<5 { let q = point(i, scale: 0.5); if i == 0 { p.move(to: q) } else { p.addLine(to: q) } }
                p.closeSubpath()
            }.stroke(track.opacity(0.5), lineWidth: 0.5)
            Path { p in
                for i in 0..<5 { p.move(to: CGPoint(x: size / 2, y: size / 2)); p.addLine(to: point(i, scale: 1.0)) }
            }.stroke(track.opacity(0.35), lineWidth: 0.5)
            Path { p in
                for i in 0..<5 { let q = point(i, scale: CGFloat(pcts[i] / maxV)); if i == 0 { p.move(to: q) } else { p.addLine(to: q) } }
                p.closeSubpath()
            }.fill(accent.opacity(0.18))
            Path { p in
                for i in 0..<5 { let q = point(i, scale: CGFloat(pcts[i] / maxV)); if i == 0 { p.move(to: q) } else { p.addLine(to: q) } }
                p.closeSubpath()
            }.stroke(accent, lineWidth: 1.2)
            ForEach(0..<5, id: \.self) { i in
                Text("\(names[i])\(Int(pcts[i].rounded()))%")
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .foregroundStyle(accent)
                    .position(point(i, scale: 1.22))
            }
        }
        .frame(width: size, height: size)
    }
}

struct PosterView: View {
    let chart: BaziChart
    let name: String
    var style: PosterStyle = .songQingdai
    /// G13 编辑器覆盖项（默认 nil＝不覆盖，走既有渲染）：标题文案／落款副标／强调色。
    var titleOverride: String? = nil
    var subtitleOverride: String? = nil
    var accentOverride: Color? = nil

    private var items: [InterpretItem] { InterpretEngine.interpret(chart: chart) }
    private var headline: String { items.first(where: { $0.title == "命局风景" })?.conclusion ?? "" }
    private var gejuLine: String { items.first(where: { $0.title == "月令格局（候选）" })?.conclusion ?? "" }
    private var yunLine: String { items.first(where: { $0.title == "岁运要点" })?.conclusion ?? "" }
    private var pal: PosterPalette {
        let base = style.palette
        guard let accent = accentOverride else { return base }
        return PosterPalette(bg0: base.bg0, bg1: base.bg1, main: base.main, sub: base.sub, accent: accent, accentHi: base.accentHi, card: base.card, cardStroke: base.cardStroke, track: base.track)
    }
    /// 编辑器标题：有覆盖且非空时用覆盖文案，否则用人物名。
    private var displayName: String {
        if let t = titleOverride, !t.isEmpty { return t }
        return name
    }
    /// 编辑器落款副标：有覆盖且非空时用覆盖文案，否则用既有副标。
    private var displaySubtitle: String {
        if let s = subtitleOverride, !s.isEmpty { return s }
        return "据五典而断 · 盘面为据 · 宋纸雅集"
    }

    /// 大运卡片下方补实：原局核心神煞（只取天乙／文昌／羊刃／驿马四项，逐人现算）
    private var coreShenShaLine: String {
        let all = BaziTables.shenSha(chart).flatMap { $0 }
        let want = ["天乙贵人", "文昌", "羊刃", "驿马"]
        let hit = want.filter { w in all.contains { $0.contains(w) } }
        return hit.isEmpty ? "天乙／文昌／羊刃／驿马未入原局" : hit.joined(separator: " · ")
    }
    /// 调候喜忌一句话精析（调候优先口径，与预测单长图同源）
    private var tiaoHouLine: String {
        let xj = InterpretEngine.posterXiJi(chart: chart)
        let n = ["木", "火", "土", "金", "水"]
        let th = xj.tiaoHou.map { n[$0] }.joined(separator: "、")
        let xi = xj.xi.map { n[$0] }.joined(separator: "、")
        let ji = xj.ji.map { n[$0] }.joined(separator: "、")
        if xj.xi.isEmpty { return "调候用神\(th.isEmpty ? "—" : th)为先；身\(xj.level)，流通为要，不拘固定喜忌" }
        return "调候用神\(th.isEmpty ? "—" : th)为先；喜\(xi) ✓，忌\(ji.isEmpty ? "无" : ji + " ×")（调候优先）"
    }
    /// 神煞全解行（四柱逐柱列出）
    private var shenShaFullLine: String {
        let all = BaziTables.shenSha(chart)
        let names = ["年柱", "月柱", "日柱", "时柱"]
        return all.enumerated().map { i, list in
            "\(names[i])：\(list.isEmpty ? "—" : list.joined(separator: "、"))"
        }.joined(separator: "；")
    }
    /// 十神分布条（原局四干＋全部藏干计数）
    private var shiShenBars: [(String, Int)] {
        let all = chart.stemShiShen + chart.hideShiShen.flatMap { $0 }
        var cnt: [String: Int] = [:]
        for s in all { cnt[s, default: 0] += 1 }
        let order = ["正官", "七杀", "正印", "偏印", "比肩", "劫财", "食神", "伤官", "正财", "偏财"]
        return order.compactMap { n in cnt[n].map { (n, $0) } }.filter { $0.1 > 0 }
    }
    /// 前六步大运详批行（起年＋干支＋十神主题）
    private var dayunDetailLines: [String] {
        (0..<min(6, chart.dayunGanZhi.count)).map { i in
            let gz = chart.dayunGanZhi[i]
            let stem = gz.first ?? "?"
            let ss = BaziTables.shiShen(day: chart.rizhu.first!, stem: stem)
            let theme = ["正官": "事业平台", "七杀": "事业平台", "正印": "学习积累", "偏印": "学习积累", "正财": "求财经营", "偏财": "求财经营", "食神": "输出变现", "伤官": "输出变现", "比肩": "合作竞争", "劫财": "合作竞争"][ss] ?? "稳进"
            return "\(chart.dayunStartYear(i))年起 \(gz)（\(ss)·\(theme)）"
        }
    }
    private static func stemWxIndex(_ s: Character) -> Int {
        switch s { case "甲", "乙": return 0; case "丙", "丁": return 1; case "戊", "己": return 2; case "庚", "辛": return 3; default: return 4 }
    }
    private static func branchWxIndex(_ b: Character) -> Int {
        switch b { case "寅", "卯": return 0; case "巳", "午": return 1; case "辰", "戌", "丑", "未": return 2; case "申", "酉": return 3; default: return 4 }
    }
    /// 流年吉凶速览（当年干支与喜忌的生克关系）
    private var liuNianLine: String {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        let gz = BaziChart.yearGanZhi(year)
        let chars = Array(gz)
        guard chars.count == 2 else { return "\(year)年\(gz)" }
        let xj = InterpretEngine.posterXiJi(chart: chart)
        let sWx = Self.stemWxIndex(chars[0])
        let bWx = Self.branchWxIndex(chars[1])
        if xj.xi.contains(sWx) || xj.xi.contains(bWx) { return "\(year)年\(gz)：流年干支生扶喜用神，吉。" }
        if xj.ji.contains(sWx) || xj.ji.contains(bWx) { return "\(year)年\(gz)：流年干支冲克忌神，宜守。" }
        return "\(year)年\(gz)：流年干支与喜忌无直接生克，平。"
    }
    /// 前 6 维详批（解盘 25 维顺序前六：性格性情／十神做功／学业文书／天赋能力／事业方向／工作形态）
    private var firstSixDims: [InterpretItem] {
        items.filter { !InterpretEngine.coreTitles.contains($0.title) }.prefix(6).map { $0 }
    }
    /// 十二步大运长表（起年＋干支＋十神＋主题＋喜忌；以实际步数为准）
    private var dayun12Lines: [String] {
        (0..<min(12, chart.dayunGanZhi.count)).map { i in
            let gz = chart.dayunGanZhi[i]
            let stem = gz.first ?? "?"
            let ss = BaziTables.shiShen(day: chart.rizhu.first!, stem: stem)
            let theme = ["正官": "事业平台", "七杀": "事业平台", "正印": "学习积累", "偏印": "学习积累", "正财": "求财经营", "偏财": "求财经营", "食神": "输出变现", "伤官": "输出变现", "比肩": "合作竞争", "劫财": "合作竞争"][ss] ?? "稳进"
            let mark = InterpretEngine.dayunMark(chart: chart, index: i)
            return "\(chart.dayunStartYear(i))年起 \(gz)（\(ss)·\(theme)\(mark == "中性" ? "" : "·\(mark)")）"
        }
    }
    /// 紫微斗数（与八字同盘：同一生辰、同一经度）
    private var zw: ZiweiChart { ZiweiEngine.cachedChart(clock: chart.birthDate, gender: chart.gender, longitude: chart.longitude) }
    /// 紫微三行（命宫身宫／生年四化／三方四正）
    private var zwRows: [(String, String)] {
        func palace(_ name: String) -> ZiweiPalace { zw.palaces.first { $0.name == name }! }
        func starLine(_ p: ZiweiPalace) -> String {
            p.majors.isEmpty ? "无主星（借对宫）" : p.majors.map { m in
                let b = ZiweiBrightness.of(m.star, branch: p.branch)
                return m.star + (b.isEmpty ? "" : "（\(b)）") + (m.mutagen.map { "化\($0)" } ?? "")
            }.joined(separator: "、")
        }
        let ming = zw.palaces[zw.mingGong]
        let shen = zw.palaces[zw.shenGong]
        var huaLines: [String] = []
        for p in zw.palaces {
            for m in (p.majors + p.minors) where m.mutagen != nil {
                huaLines.append("\(m.star)化\(m.mutagen!)入\(p.name)")
            }
        }
        let cai = palace("财帛"), guan = palace("官禄"), qian = palace("迁移"), fu = palace("夫妻")
        return [
            ("命宫身宫", "命宫\(ming.stem)\(ZiweiCore.DZ[ming.branch])坐\(starLine(ming))；身宫\(shen.name)\(shen.stem)\(ZiweiCore.DZ[shen.branch])坐\(starLine(shen))；\(zw.juName)"),
            ("生年四化", huaLines.isEmpty ? "—" : huaLines.joined(separator: "；")),
            ("三方四正", "财帛\(starLine(cai)) · 官禄\(starLine(guan)) · 迁移\(starLine(qian)) · 夫妻\(starLine(fu))"),
        ]
    }
    /// 五行气运一行（同党异党＋日主强弱定档＋五行占比）
    private var qiYunLine: String {
        let xj = InterpretEngine.posterXiJi(chart: chart)
        let wx = ["木", "火", "土", "金", "水"]
        let shares = (0..<5).map { "\(wx[$0])\(Int(chart.wuxingPercents[$0].rounded()))%" }.joined(separator: " · ")
        return "同党 \(Int(xj.tongDang.rounded()))% · 异党 \(Int((100 - xj.tongDang).rounded()))% · 日主身\(xj.level)；\(shares)"
    }

    var body: some View {
        if style == .yuceDan {
            YucedanPosterLayout(chart: chart, name: displayName, pal: pal)
        } else {
            standardPosterView
        }
    }

    private var standardPosterView: some View {
        ZStack {
            LinearGradient(colors: [pal.bg1, pal.bg0], startPoint: .top, endPoint: .bottom)
                // 宋式极简发丝外框＋底部远山意境
                RoundedRectangle(cornerRadius: 4).stroke(pal.cardStroke, lineWidth: 1.0).padding(22)
                VStack {
                    Spacer()
                    SongMountainHeaderView(accent: pal.accent)
                        .padding(.horizontal, 23).padding(.bottom, 23)
                }

            VStack(spacing: 0) {
                    Text("子 平 五 典 · 命 盘 雅 集")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(4)
                        .foregroundStyle(pal.accent)
                        .padding(.top, 52)
                    Text(displayName.isEmpty ? "四柱命盘" : displayName)
                        .font(.system(size: 44, weight: .bold, design: .serif))
                        .foregroundStyle(pal.main)
                        .padding(.top, 16)

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
                        let sColor = posterCharColor(gz[0], fallback: pal.main)
                        let bColor = posterCharColor(gz[1], fallback: pal.main)
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
                            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
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
                            Text("\(String(chart.dayunStartYear(i)))起")
                                .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(pal.sub)
                        }
                        .frame(width: 66, height: 46)
                        .background(pal.card)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(pal.cardStroke, lineWidth: 0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }.padding(.top, 18)

                // 大运卡片下方：核心神煞＋调候喜忌一句话精析（补下半部留白，三款传统海报共用）
                VStack(alignment: .leading, spacing: 3) {
                    Text("核心神煞：\(coreShenShaLine)")
                        .font(.system(size: 10.5, design: .serif)).foregroundStyle(pal.main)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("调候精析：\(tiaoHouLine)")
                        .font(.system(size: 10.5, design: .serif)).foregroundStyle(pal.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 444, alignment: .leading)
                .padding(.top, 14)

                // —— 宋纸版专属区块（重古籍与大运详批）——
                    VStack(alignment: .leading, spacing: 6) {
                        Text("五典原句")
                            .font(.system(size: 12.5, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
                        Text("「能知旺衰之道，斯可以言命矣。」——《滴天髓》")
                            .font(.system(size: 11, design: .serif)).foregroundStyle(pal.main)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("「八字用神，专求月令。」——《子平真诠》")
                            .font(.system(size: 11, design: .serif)).foregroundStyle(pal.main)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("月令正格")
                            .font(.system(size: 12.5, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
                            .padding(.top, 4)
                        if !gejuLine.isEmpty {
                            Text(gejuLine)
                                .font(.system(size: 11)).foregroundStyle(pal.main)
                                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        }
                        Text("神煞：\(shenShaFullLine)")
                            .font(.system(size: 11, design: .serif)).foregroundStyle(pal.main)
                            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        Text("五行气运：\(qiYunLine)")
                            .font(.system(size: 11, design: .serif)).foregroundStyle(pal.sub)
                            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        Text("前六维详批")
                            .font(.system(size: 12.5, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
                            .padding(.top, 4)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                            ForEach(firstSixDims, id: \.title) { d in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(d.title).font(.system(size: 11, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
                                    Text(d.conclusion).font(.system(size: 10.5)).foregroundStyle(pal.main).lineSpacing(2.5).fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(8)
                                .background(pal.card)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        Text("前六步大运详批")
                            .font(.system(size: 12.5, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
                            .padding(.top, 4)
                        ForEach(dayunDetailLines, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 11)).foregroundStyle(pal.main)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let yun = items.first(where: { $0.title == "岁运要点" })?.conclusion, !yun.isEmpty {
                            Text(yun)
                                .font(.system(size: 11)).foregroundStyle(pal.sub)
                                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(width: 444, alignment: .leading)
                    .padding(.top, 14)

                Spacer()

                // 统一品牌落款（P3 第 1 项）：同一印章＋同一品牌行，副标与日期各款保留
                PosterBrandFooter(pal: pal, subtitle: displaySubtitle)
            }

            // 宋纸版右缘竖排题签（真竖排：中文单字直下；只用于眉题短句，全文不竖排）
                VerticalText(text: "子平五典", fontSize: 13, color: pal.accent, spacing: 5)
                    .position(x: 506, y: 110)
        }
        .frame(width: 540)
    }
}

// MARK: - 三术合参预测单海报布局（加长版长图：太极头＋生辰凭证＋四柱细盘＋五行雷达＋神煞全表＋紫微合参＋格局喜忌＋六维详批＋大运时轮＋破局指南＋防伪钤印；2026-11-06 起题头正名为三术合参，不再用旧社名；断语与喜忌全部取自本机解盘引擎逐人现算，不写死）
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
private func conclusion(_ t1: String, _ t2: String? = nil) -> String {
if let t2 { return InterpretEngine.conclusion(items: items, titles: t1, t2) }
return InterpretEngine.conclusion(items: items, titles: t1)
}
private var xj: (xi: [Int], ji: [Int], neutral: [Int], level: String, tongDang: Double, tiaoHou: [Int]) {
InterpretEngine.posterXiJi(chart: chart)
}
private static let wxNames = ["木", "火", "土", "金", "水"]
private static let numMap = ["木": "3、8", "火": "2、7", "土": "5、0", "金": "4、9", "水": "1、6"]
private static let colorMap = ["木": "绿、青", "火": "红", "土": "黄", "金": "白、金", "水": "黑、蓝"]
// 八·调理五项原文：用户提供的手写单真迹措辞（cases/周囿廷-取名社预测单.jpg）；✓/× 按本工作室喜忌现算，栏目标明传统应用参考
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
/// 喜忌标记（二值，与真迹一致）：喜→✓朱砂红，忌→×次级灰，中性（可用）→✓青黛；三者区分见喜忌横幅
private func markGlyph(_ w: Int) -> (String, Color) {
if xj.ji.contains(w) { return ("×", pal.sub)}
if xj.xi.contains(w) { return ("✓", pal.accentHi)}
return ("✓", pal.accent)
}
/// 大运标记：运干五行套 posterXiJi；中和盘全标中性
private func dayunGlyph(_ i: Int) -> (String, Color) {
let m = InterpretEngine.dayunMark(chart: chart, index: i)
if m == "喜" { return ("✓", pal.accentHi)}
if m == "忌" { return ("×", pal.sub)}
return ("—", pal.sub)
}
/// 流年地支轮：以出生年支为起点的下一个完整十二年轮（当前年份之后的首个该支年份起，连续 12 年）；
/// 每支标关联年份、周岁岁数与 ✓/×（地支五行套喜忌）。例：2024 年生人轮次 2036–2047，周岁 12–23，与真迹 13–24 虚岁差一岁（口径：工作室标周岁）。
private var wheelYears: [(branch: Character, year: Int, age: Int, glyph: String, color: Color)] {
let nowYear = Calendar.current.component(.year, from: Date())
let birthBranch = chart.yearPillar.last!
var start = nowYear
while BaziChart.yearGanZhi(start).last! != birthBranch { start += 1 }
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
let base = xj.xi.flatMap { (Self.numMap[Self.wxNames[$0]] ?? "").split(separator: "、").compactMap { Int($0)}}
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
// ① 尊享天头：太极双鱼＋三术合参尊享预测单
VStack(spacing: 3) {
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

Text("三术合参 · 四柱命理尊享预测单")
.font(.system(size: 20, weight:.bold, design:.serif))
.tracking(1)
.foregroundStyle(pal.main)
}
Text("五典正法 · 实务详批")
.font(.system(size: 11.5, weight:.semibold, design:.serif))
.tracking(4)
.foregroundStyle(pal.accent)
}
.padding(.top, 22)
Text("\(receiptCity) · \(receiptLongitude)E · \(chart.naYin.first ?? "")命")
.font(.system(size: 11.5, weight: .bold, design: .serif))
.foregroundStyle(pal.accent)
.padding(.top, 4)

// 2. 三行生辰收据（城市/经度/出生时刻/农历/前后两节/性别/姓名/年命/真太阳时校正量）
VStack(spacing: 2) {
HStack(spacing: 0) {
Text("城市：\(receiptCity)")
Text("　经度：\(receiptLongitude)")
Spacer()
Text("出生：\(Self.birthFmt.string(from: chart.birthDate))\(trueSolarSuffix)")
}
HStack(spacing: 0) {
Text("农历：\(chart.lunarText.isEmpty ? "—": chart.lunarText)")
Text("　上一节 \(chart.prevJieQiText.isEmpty ? "—": chart.prevJieQiText)　下一节 \(chart.nextJieQiText.isEmpty ? "—": chart.nextJieQiText)")
Spacer()
Text("\(chart.gender == "M" ? "男（乾造）": "女（坤造）")　\(name.isEmpty ? "命主" : name)　\(chart.naYin.first ?? "")命")
}
HStack(spacing: 0) {
Text("真太阳时校正：\(correctionText)")
Text("　年命：\(chart.naYin.first ?? "—")命")
Spacer()
Text("旬空：\(chart.xunKong.isEmpty ? "—": chart.xunKong)")
}
if !chart.nextJieQiGapText.isEmpty {
HStack(spacing: 0) {
Text("★ \(chart.nextJieQiGapText)")
.foregroundStyle(pal.accentHi)
Spacer()
}
}
}
.font(.system(size: 10, weight:.medium, design:.serif))
.foregroundStyle(pal.sub)
.padding(.horizontal, 32)
.padding(.top, 8)

Rectangle().fill(pal.cardStroke).frame(height: 0.7).padding(.horizontal, 24).padding(.vertical, 6)

// ② 四柱细盘（全宽表：宫位／十神／干支／藏干本中余／长生／纳音；旬空见收据行）
VStack(spacing: 0) {
Text("专业四柱细盘")
.font(.system(size: 12.5, weight:.bold, design:.serif))
.foregroundStyle(pal.accent)
.padding(.bottom, 4)
pillarTable
}
.padding(.horizontal, 32)
.padding(.vertical, 4)

// ③ 五行气运雷达（五行占比图谱＋同党异党量化比率＋日主强弱定档＋通关气势；P3：组头改走 V6 KyHomeSection 静态版式，标题文案不动）
KyHomeSection(title: "五行气运雷达", trailing: "") {
HStack(alignment:.top, spacing: 14) {
wuxingRadar
VStack(alignment:.leading, spacing: 3) {
Text("同党 \(Int(xj.tongDang.rounded()))% · 异党 \(Int((100 - xj.tongDang).rounded()))%")
.font(.system(size: 10.5, weight:.bold, design:.serif)).foregroundStyle(pal.main)
Text("日主强弱定档：身\(xj.level)（同党约\(Int(xj.tongDang.rounded()))%）")
.font(.system(size: 10.5, design:.serif)).foregroundStyle(pal.main)
Text(tongGuanText)
.font(.system(size: 10.5, design:.serif)).foregroundStyle(pal.main)
.fixedSize(horizontal: false, vertical: true)
.frame(maxWidth: .infinity, alignment: .leading)
.lineLimit(nil)
Text("五行占比：\(wxShareText)")
.font(.system(size: 10, design:.serif)).foregroundStyle(pal.sub)
.fixedSize(horizontal: false, vertical: true)
.frame(maxWidth: .infinity, alignment: .leading)
.lineLimit(nil)
}
}
}
.padding(.horizontal, 32)
.padding(.vertical, 4)

// 3b. 神煞全表（原局见到的全部神煞，按柱排列；太极贵人已入引擎）
VStack(alignment:.leading, spacing: 3) {
Text("神煞全表")
.font(.system(size: 12.5, weight:.bold, design:.serif))
.foregroundStyle(pal.accent)
ForEach(0..<4, id: \.self) { i in
HStack(alignment:.top, spacing: 6) {
Text(["年柱", "月柱", "日柱", "时柱"][i] + " " + chart.pillars[i])
.font(.system(size: 10, weight:.bold, design:.serif)).foregroundStyle(i == 2 ? pal.accentHi : pal.main).frame(width: 78, alignment:.leading)
Text(shenShaList[i].isEmpty ? "—" : shenShaList[i].joined(separator: "、"))
.font(.system(size: 10)).foregroundStyle(pal.main)
.fixedSize(horizontal: false, vertical: true)
.frame(maxWidth: .infinity, alignment: .leading)
.lineLimit(nil)
}
}
}
.padding(.horizontal, 32)
.padding(.vertical, 4)

// ⑤ 紫微斗数合参提炼（命宫身宫主星及庙旺＋生年四化＋三方四正核心星曜）
VStack(alignment:.leading, spacing: 3) {
Text("紫微斗数合参提炼")
.font(.system(size: 12.5, weight:.bold, design:.serif))
.foregroundStyle(pal.accent)
ForEach(ziweiRows, id: \.0) { row in
HStack(alignment:.top, spacing: 6) {
Text(row.0)
.font(.system(size: 10, weight:.bold, design:.serif)).foregroundStyle(pal.accent).frame(width: 62, alignment:.leading)
Text(row.1)
.font(.system(size: 10)).foregroundStyle(pal.main)
.fixedSize(horizontal: false, vertical: true)
.frame(maxWidth: .infinity, alignment: .leading)
.lineLimit(nil)
}
}
}
.padding(.horizontal, 32)
.padding(.vertical, 4)

// ④ 月令正格与调候精断（月令本气透藏考据＋穷通寒暖燥湿查表用神＋喜用忌神判标）
VStack(alignment:.leading, spacing: 5) {
Text("月令正格与调候精断")
.font(.system(size: 12.5, weight:.bold, design:.serif))
.foregroundStyle(pal.accent)
Text(yueLingText)
.font(.system(size: 10.5, design:.serif)).foregroundStyle(pal.main)
.fixedSize(horizontal: false, vertical: true)
.frame(maxWidth: .infinity, alignment: .leading)
.lineLimit(nil)
Text("调候用神（《穷通宝鉴》）：\(tiaoHouNames.isEmpty ? "—" : tiaoHouNames)（\(chart.monthPillar.last ?? "—")月，寒暖燥湿查表，调候优先）")
.font(.system(size: 10.5, design:.serif)).foregroundStyle(pal.main)
.fixedSize(horizontal: false, vertical: true)
.frame(maxWidth: .infinity, alignment: .leading)
.lineLimit(nil)
Text(conclusion("月令格局（候选）"))
.font(.system(size: 10.5, design:.serif)).foregroundStyle(pal.main)
.lineSpacing(2.0).fixedSize(horizontal: false, vertical: true)
.frame(maxWidth: .infinity, alignment: .leading)
.lineLimit(nil)
ForEach(Array(["木", "火", "土", "金", "水"].enumerated()), id: \.offset) { idx, e in
let v = chart.wuxingPercents[idx]
HStack(spacing: 8) {
Text(e)
.font(.system(size: 11, weight:.bold, design:.serif))
.foregroundStyle(wxColor[e] ?? pal.main)
.frame(width: 16)
ZStack(alignment:.leading) {
RoundedRectangle(cornerRadius: 3).fill(pal.track)
RoundedRectangle(cornerRadius: 3)
.fill(wxColor[e] ?? pal.accent)
.frame(width: max(3, 364 * CGFloat(min(v, 100)) / 100.0))
}
.frame(width: 364, height: 7)
Text("\(Int(v.rounded()))%")
.font(.system(size: 10.5, design:.monospaced))
.foregroundStyle(pal.sub)
.frame(width: 36, alignment:.trailing)
}
}
Text("四季五行：春木 · 夏火 · 秋金 · 冬水；农历三、九月土（个数分布仅供参考，强弱以月令格局为准）")
.font(.system(size: 9, design:.serif)).foregroundStyle(pal.sub)
// P3：喜用／忌神改走 V6 KyMetricCard 静态版式（标签、五行名、✓／× 标记原文保留；中性行仍为正文）
HStack(spacing: 10) {
KyMetricCard(label: "喜用神", value: xiNames.isEmpty ? "—" : xiNames, badgeText: "✓", tint: Ky.cinnabar)
KyMetricCard(label: "忌神", value: jiNames.isEmpty ? "—" : jiNames, badgeText: "×", tint: Ky.sub)
}
if !xj.neutral.isEmpty && xj.level != "中和" {
Text("\(xj.neutral.map { Self.wxNames[$0]}.joined(separator: "、"))：中性（可用）")
.font(.system(size: 10, design:.serif)).foregroundStyle(pal.sub)
}
Text("依据：日主\(xj.level)（同党约\(Int(xj.tongDang.rounded()))%）\(xiJiBasis)")
.font(.system(size: 10, design:.serif)).foregroundStyle(pal.sub)
}
.padding(.horizontal, 32)
.padding(.vertical, 5)
.background(pal.card.opacity(0.8))

Rectangle().fill(pal.cardStroke).frame(height: 0.7).padding(.horizontal, 24).padding(.vertical, 4)

// ⑥ 全维深度精选直断（六大精选板块；正文取自解盘引擎与实算，逐人现算；不设行数上限，禁止省略号截断）
VStack(alignment:.leading, spacing: 8) {
yuceSection(num: "一", title: "性格天赋", rows: [
("1. 日主五行底色", "\(chart.rizhu)日主，\(BaziTables.wx[chart.rizhu.first!]?.0 ?? "")行，身\(xj.level)（同党约\(Int(xj.tongDang.rounded()))%）"),
("2. 主导十神心性", "主导十神为\(BaziTables.dominantShiShen(chart: chart))——\(conclusion("性格性情"))"),
("3. 天赋取向", conclusion("天赋能力")),
("4. 十神做功", conclusion("十神做功")),
("5. 优点特长", conclusion("命局风景")),
("6. 盲点防范", conclusion("注意事项")),
])
yuceSection(num: "二", title: "学业考运", rows: [
("1. 学业文书", conclusion("学业文书")),
])
yuceSection(num: "三", title: "事业赛道", rows: [
("1. 适合行业", conclusion("行业赛道深断", "事业方向")),
("2. 五阶段路线", conclusion("事业方向")),
("3. 工作形态", conclusion("工作形态")),
("4. 发展方位", conclusion("适合方位", "事业方向")),
("5. 贵人指引", conclusion("贵人与人际")),
])
yuceSection(num: "四", title: "财富蓄水池", rows: [
("1. 财运源流", conclusion("财运形态")),
("2. 财气通门户", BaziTables.caiQiMenHu(chart: chart)),
("3. 真假财库", BaziTables.caiKuReport(chart: chart)),
("4. 资产沉淀", conclusion("财富量级蓄水池")),
])
yuceSection(num: "五", title: "婚恋感情", rows: [
("1. 配偶星与配偶宫", "配偶星\(peiOu.names.joined(separator: "／"))\(peiOu.present ? "入局" : "未入原局")；配偶宫日支\(chart.dayPillar.last!)本气\(peiOu.palace)"),
("2. 婚龄与伴侣", conclusion("婚姻感情")),
("3. 相处之道", conclusion("六亲情境深读", "婚姻感情")),
("4. 感情关口与解法", conclusion("婚姻感情")),
])
yuceSection(num: "六", title: "健康调理", rows: [
("1. 体质弱项", conclusion("健康倾向")),
("2. 注意事项", conclusion("注意事项")),
])
}
.padding(.horizontal, 32)
.padding(.vertical, 4)

Spacer(minLength: 0)

// ⑦ 终身大运流年推演（全 8 步大运＋起运岁数＋运干十神＋扶抑喜忌标记＋十年宏观课题；时轮并排）
HStack(alignment:.top, spacing: 12) {

// (B) 大运走势：✓/×（调候优先口径）＋运干十神＋干支＋岁数区间
VStack(alignment:.leading, spacing: 3) {
Text("终身大运")
.font(.system(size: 12.5, weight:.bold, design:.serif))
.foregroundStyle(pal.accent)
if !chart.dayunGanZhi.isEmpty {
Text("起运：\(String(chart.dayunStartYear(0))) 年（约 \(chart.dayunStartYear(0) - chart.birthYear) 岁）起 \(chart.dayunGanZhi[0])运")
.font(.system(size: 10, design:.serif)).foregroundStyle(pal.sub)
}
VStack(alignment:.leading, spacing: 2.5) {
ForEach(0..<min(8, chart.dayunGanZhi.count), id: \.self) { i in
let gz = chart.dayunGanZhi[i]
let (g, c) = dayunGlyph(i)
let startAge = chart.dayunStartYear(i) - chart.birthYear
let ss = BaziTables.shiShen(day: chart.rizhu.first!, stem: gz.first!)
HStack(spacing: 4) {
Text(g).font(.system(size: 11, weight:.bold)).foregroundStyle(c).frame(width: 13)
Text(gz)
.font(.system(size: 11.5, weight:.bold, design:.serif)).foregroundStyle(pal.main)
Text(ss)
.font(.system(size: 10)).foregroundStyle(pal.accent)
Text("\(startAge)~\(startAge + 10)岁")
.font(.system(size: 10, design:.monospaced)).foregroundStyle(pal.sub)
Text(dayunTheme(gz.first!))
.font(.system(size: 9.5)).foregroundStyle(pal.sub)
}
}
}
}
.frame(width: 218, alignment:.leading)

// (C) 十二地支罗盘时轮（放大：子北午南、顺时针环列；每支标年份、周岁与 ✓/×，盘心定向指针；红点＝原局四支）
VStack(spacing: 2) {
Text("十二地支罗盘时轮")
.font(.system(size: 12.5, weight:.bold, design:.serif))
.foregroundStyle(pal.accent)
ZStack {
Circle().stroke(pal.cardStroke, lineWidth: 0.8)
Circle().stroke(pal.cardStroke.opacity(0.5), lineWidth: 0.5).frame(width: 104, height: 104)
ForEach(wheelYears, id: \.branch) { w in
let order = Array("子丑寅卯辰巳午未申酉戌亥")
let pos = order.firstIndex(of: w.branch) ?? 0
let angle = Double(pos) * 30.0 - 90.0
let rad = angle * Double.pi / 180.0
VStack(spacing: 0) {
Text(String(w.branch))
.font(.system(size: 13, weight:.bold, design:.serif))
.foregroundStyle(posterCharColor(w.branch, fallback: pal.main))
Text("\(String(w.year))")
.font(.system(size: 9, design:.monospaced)).foregroundStyle(pal.sub)
Text("\(w.age)岁 \(w.glyph)")
.font(.system(size: 9.5, weight:.bold)).foregroundStyle(w.color)
if chart.pillars.contains(where: { $0.last! == w.branch}) {
Circle().fill(pal.accentHi).frame(width: 4, height: 4)
}
}
.position(x: 100 + 76 * cos(rad), y: 100 + 76 * sin(rad))
}
// 盘心定向指针（指北/子）
Path { p in
p.move(to: CGPoint(x: 100, y: 66))
p.addLine(to: CGPoint(x: 108, y: 100))
p.addLine(to: CGPoint(x: 92, y: 100))
p.closeSubpath()
}
.fill(pal.accentHi)
Circle().fill(pal.main).frame(width: 7, height: 7)
}
.frame(width: 200, height: 200)
.drawingGroup()
}
.frame(width: 230)
}
.padding(.horizontal, 24)
.padding(.vertical, 4)

// 未来三年流年直断（当年起连续三年，逐年顺逆动象与行事指南）
VStack(alignment:.leading, spacing: 3) {
Text("未来三年流年直断")
.font(.system(size: 12.5, weight:.bold, design:.serif))
.foregroundStyle(pal.accent)
ForEach(threeYearRows, id: \.0) { row in
HStack(alignment:.top, spacing: 6) {
Text(row.0)
.font(.system(size: 10, weight:.bold, design:.serif)).foregroundStyle(pal.main).frame(width: 78, alignment:.leading)
Text(row.1)
.font(.system(size: 10)).foregroundStyle(pal.main)
.fixedSize(horizontal: false, vertical: true)
.frame(maxWidth: .infinity, alignment: .leading)
.lineLimit(nil)
}
}
}
.padding(.horizontal, 32)
.padding(.vertical, 4)

// ⑧ 破局调理五行通关指南（生旺五行＋适宜方位＋吉祥数字＋幸运色彩＋贵人属相＋修心建议）
yuceSection(num: "七", title: "破局调理五行通关指南", rows: [
("1. 生旺五行", xj.xi.isEmpty ? "流通为要，不拘固定五行" : "喜用 \(xiNames)（✓）；忌 \(jiNames.isEmpty ? "无" : jiNames + "（×）")"),
("2. 适宜方位", conclusion("适合方位")),
("3. 吉祥数字", xj.xi.isEmpty ? "流通为要，不拘固定数" : "宜含 \(xiNums)（\(xiNames)数）；楼层宜选 \(floors)"),
("4. 幸运色彩", conclusion("幸运颜色与数字") + (jiNames.isEmpty ? "" : "；忌\(jiNames)色系（\(jiColors)）")),
("5. 贵人属相", guiRenShengXiao),
("6. 手机尾号吉数", xj.xi.isEmpty ? "流通为要，不拘固定数" : "宜含 \(xiNums)（\(xiNames)数）"),
("7. 修心建议", conclusion("如何化解（破局调理）")),
("8. 传统补五行", buXingInline),
], note: "传统应用参考", goldKeys: qiGoldKeys)
.padding(.horizontal, 32)

// ⑨ 防伪验真标识：官方落款＋副标＋篆体印鉴＋公农历时间戳＋防伪验真码
VStack(spacing: 4) {
Rectangle().fill(pal.cardStroke).frame(height: 0.7).padding(.horizontal, 24)
HStack(alignment:.bottom, spacing: 10) {
VStack(alignment:.leading, spacing: 2) {
Text("三术合参 · 堪舆命理院 谨制")
.font(.system(size: 12, weight:.bold, design:.serif)).foregroundStyle(pal.accent)
Text("据子平五典与天纪三合推演 · 传统命理研习参考")
.font(.system(size: 9, design:.serif)).foregroundStyle(pal.sub)
.fixedSize(horizontal: false, vertical: true)
Text("典籍依据：《滴天髓》《子平真诠》《穷通宝鉴》《三命通会》《渊海子平》")
.font(.system(size: 9, design:.serif)).foregroundStyle(pal.sub)
.fixedSize(horizontal: false, vertical: true)
Text("依据五典推演，仅供娱乐参考；断语可回测验证，不作医疗、寿数与具体事件定断。")
.font(.system(size: 9, design:.serif)).foregroundStyle(pal.sub)
.fixedSize(horizontal: false, vertical: true)
Text("防伪验真码：\(antiFakeCode)")
.font(.system(size: 9, weight:.bold, design:.monospaced)).foregroundStyle(pal.main)
}
Spacer()
VStack(alignment:.trailing, spacing: 2) {
Text("报告日期：\(Self.dateFmt.string(from: Date()))")
.font(.system(size: 10, weight:.bold, design:.serif)).foregroundStyle(pal.main)
Text(chart.lunarText.isEmpty ? "" : "农历：\(chart.lunarText)")
.font(.system(size: 9, design:.serif)).foregroundStyle(pal.sub)
}
// P3 第 1 项：预测单印章与另三款统一为同一枚朱砂印（原 40×40 描边章）
PosterSealView()
}
.padding(.horizontal, 32)
}
.padding(.bottom, 42)
}
}
// 加长版长图：只定宽 540，高随内容自适应（九大板块全量展开，约 3000pt；渲染 scale 2 → 1080 宽超清长图），禁止定死 960 裁切内容
.frame(width: 540)
}

// MARK: - 收据派生
private var receiptCity: String {
guard let lon = chart.longitude else { return "—"}
return BirthInputView.placeLabel(longitude: lon) ?? "—"
}
private var receiptLongitude: String {
guard let lon = chart.longitude else { return "—"}
return String(format: "%.1f°", lon)
}
private var trueSolarSuffix: String {
guard let t = chart.trueSolarDate else { return ""}
return "（真太阳时 \(Self.timeFmt.string(from: t))）"
}
/// 真太阳时校正量（实算：真太阳时 − 钟表时间，分钟；囿廷 −48 分钟）
private var correctionText: String {
guard let t = chart.trueSolarDate else { return "未校正" }
let m = Int((t.timeIntervalSince(chart.birthDate) / 60).rounded())
return "\(m >= 0 ? "+" : "")\(m)分钟"
}
private var xiJiBasis: String {
if xj.level == "中和" { return "；同党异党接近，贵在流通，不预设固定喜忌"}
let thNames = xj.tiaoHou.map { Self.wxNames[$0]}.joined(separator: "、")
if thNames.isEmpty { return ""}
return "；调候喜\(thNames)（\(chart.monthPillar.last ?? "—")月，调候优先）"
}
/// 神煞全表（按柱；太极贵人已入 BaziTables.shenSha）
private var shenShaList: [[String]] { BaziTables.shenSha(chart) }
/// 配偶星与配偶宫（男财女官；配偶宫＝日支本气十神）
private var peiOu: (names: [String], present: Bool, palace: String) { BaziTables.peiOuXing(chart: chart) }
/// 忌色（忌神五行对应色）
private var jiColors: String { xj.ji.compactMap { Self.colorMap[Self.wxNames[$0]] }.joined(separator: "、") }
/// 紫微斗数（与八字同盘：同一生辰、同一经度）
private var zw: ZiweiChart { ZiweiEngine.cachedChart(clock: chart.birthDate, gender: chart.gender, longitude: chart.longitude) }
/// 紫微三行（命宫身宫／生年四化／三方四正）
private var ziweiRows: [(String, String)] {
    func palace(_ name: String) -> ZiweiPalace { zw.palaces.first { $0.name == name }! }
    func starLine(_ p: ZiweiPalace) -> String {
        p.majors.isEmpty ? "无主星（借对宫）" : p.majors.map { m in
            let b = ZiweiBrightness.of(m.star, branch: p.branch)
            return m.star + (b.isEmpty ? "" : "（\(b)）") + (m.mutagen.map { "化\($0)" } ?? "")
        }.joined(separator: "、")
    }
    let ming = zw.palaces[zw.mingGong]
    let shen = zw.palaces[zw.shenGong]
    var huaLines: [String] = []
    for p in zw.palaces {
        for m in (p.majors + p.minors) where m.mutagen != nil {
            huaLines.append("\(m.star)化\(m.mutagen!)入\(p.name)")
        }
    }
    let cai = palace("财帛"), guan = palace("官禄"), qian = palace("迁移"), fu = palace("夫妻")
    return [
        ("命宫身宫", "命宫\(ming.stem)\(ZiweiCore.DZ[ming.branch])坐\(starLine(ming))；身宫\(shen.name)\(shen.stem)\(ZiweiCore.DZ[shen.branch])坐\(starLine(shen))；\(zw.juName)"),
        ("生年四化", huaLines.isEmpty ? "—" : huaLines.joined(separator: "；")),
        ("三方四正", "财帛\(starLine(cai)) · 官禄\(starLine(guan)) · 迁移\(starLine(qian)) · 夫妻\(starLine(fu))"),
    ]
}
/// 五行雷达（五边形：木火土金水顺时针；按占比归一化，最大者满半径）
private var wuxingRadar: some View {
    let pcts = chart.wuxingPercents
    let maxV = max(pcts.max() ?? 1, 1)
    return ZStack {
        Path { p in
            for i in 0..<5 { let q = radarPoint(i, scale: 1.0); if i == 0 { p.move(to: q) } else { p.addLine(to: q) } }
            p.closeSubpath()
        }.stroke(pal.cardStroke, lineWidth: 0.8)
        Path { p in
            for i in 0..<5 { let q = radarPoint(i, scale: 0.5); if i == 0 { p.move(to: q) } else { p.addLine(to: q) } }
            p.closeSubpath()
        }.stroke(pal.cardStroke.opacity(0.5), lineWidth: 0.5)
        Path { p in
            for i in 0..<5 { p.move(to: CGPoint(x: 75, y: 75)); p.addLine(to: radarPoint(i, scale: 1.0)) }
        }.stroke(pal.cardStroke.opacity(0.35), lineWidth: 0.5)
        Path { p in
            for i in 0..<5 {
                let q = radarPoint(i, scale: CGFloat(pcts[i] / maxV))
                if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            p.closeSubpath()
        }.fill(pal.accentHi.opacity(0.18))
        Path { p in
            for i in 0..<5 {
                let q = radarPoint(i, scale: CGFloat(pcts[i] / maxV))
                if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            p.closeSubpath()
        }.stroke(pal.accentHi, lineWidth: 1.2)
        ForEach(0..<5, id: \.self) { i in
            Text("\(Self.wxNames[i])\(Int(pcts[i].rounded()))%")
                .font(.system(size: 9, weight:.bold, design:.serif))
                .foregroundStyle(wxColor[Self.wxNames[i]] ?? pal.main)
                .position(radarPoint(i, scale: 1.18))
        }
    }
    .frame(width: 150, height: 150)
}
private func radarPoint(_ i: Int, scale: CGFloat) -> CGPoint {
    let a = (-90.0 + Double(i) * 72.0) * Double.pi / 180.0
    return CGPoint(x: 75 + 58 * scale * CGFloat(cos(a)), y: 75 + 58 * scale * CGFloat(sin(a)))
}
/// 通关气势：占比最高的两个五行，前者克后者时给出通关之神
private var tongGuanText: String {
    let order = chart.wuxingPercents.indices.sorted { chart.wuxingPercents[$0] > chart.wuxingPercents[$1] }
    let a = order[0], b = order[1]
    let ke: [Int: Int] = [0: 2, 2: 4, 4: 1, 1: 3, 3: 0]
    if ke[a] == b {
        let c = (a + 1) % 5
        return "气势：\(Self.wxNames[a])\(Self.wxNames[b])相战，以\(Self.wxNames[c])通关（\(Self.wxNames[a])生\(Self.wxNames[c])、\(Self.wxNames[c])生\(Self.wxNames[b])）"
    }
    return "气势：\(Self.wxNames[a])\(Self.wxNames[b])并旺流通，无强战克，通关不急。"
}
/// 五行占比一行
private var wxShareText: String {
    (0..<5).map { "\(Self.wxNames[$0])\(Int(chart.wuxingPercents[$0].rounded()))%" }.joined(separator: " · ")
}
/// 月令本气透藏考据：月支本气干及其十神，透干／藏支
private var yueLingText: String {
    let mb = chart.monthPillar.last!
    let benQi = BaziTables.cangGan[mb]!.first!
    let ss = BaziTables.shiShen(day: chart.rizhu.first!, stem: benQi)
    let tou = chart.pillars.contains { $0.first! == benQi }
    return "月令\(mb)支，本气\(benQi)（\(ss)）\(tou ? "透干" : "藏支")；月令格局见下。"
}
/// 调候用神（《穷通宝鉴》查表）
private var tiaoHouNames: String { xj.tiaoHou.map { Self.wxNames[$0] }.joined(separator: "、") }
/// 贵人属相（日支三合贵人，传统应用参考）
private var guiRenShengXiao: String {
    let sanHe: [Character: [String]] = ["申": ["猴", "鼠", "龙"], "子": ["猴", "鼠", "龙"], "辰": ["猴", "鼠", "龙"], "寅": ["虎", "马", "狗"], "午": ["虎", "马", "狗"], "戌": ["虎", "马", "狗"], "巳": ["蛇", "鸡", "牛"], "酉": ["蛇", "鸡", "牛"], "丑": ["蛇", "鸡", "牛"], "亥": ["猪", "兔", "羊"], "卯": ["猪", "兔", "羊"], "未": ["猪", "兔", "羊"]]
    let gx = sanHe[chart.dayPillar.last!] ?? []
    return gx.isEmpty ? "—" : "\(gx.joined(separator: "、"))（日支三合贵人，传统应用参考）"
}
/// 传统补五行一行（真迹五项原文＋现算 ✓/×）
private var buXingInline: String { buXingRows.map { "\($0.0)：\($0.1)" }.joined(separator: "；") }
/// 防伪验真码（由本盘干支＋生年生成，核对请认准三术合参）
private var antiFakeCode: String {
    let src = chart.pillars.joined() + String(chart.birthYear) + chart.lunarText
    var h = 0
    for s in src.unicodeScalars { h = (h * 31 + Int(s.value)) % 2176782336 }
    let chars = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    var code = ""
    var v = h
    for _ in 0..<6 { code.append(chars[v % 32]); v /= 32 }
    return "SSHC-\(code)"
}
/// 大运十年宏观课题（按运干十神取象）
private func dayunTheme(_ stem: Character) -> String {
    let ss = BaziTables.shiShen(day: chart.rizhu.first!, stem: stem)
    return ["正官": "事业平台", "七杀": "事业平台", "正印": "学习积累", "偏印": "学习积累", "正财": "求财经营", "偏财": "求财经营", "食神": "输出变现", "伤官": "输出变现", "比肩": "合作竞争", "劫财": "合作竞争"][ss] ?? "稳进"
}
/// 七·未来三年流年直断（当年起连续三年，干支＋十神＋大运喜忌＋牵动＋指南）
private var threeYearRows: [(String, String)] {
InterpretEngine.nextThreeYears(chart: chart).map { y in
("\(y.year) \(y.ganzhi)年", y.note)
}
}
/// 专业四柱细盘表（标签列 44＋尾距 6＋四柱各 108＝482，须小于画布 540 − 两侧 28 留白＝484，写 110 会向右击穿边框）
private var pillarTable: some View {
VStack(spacing: 0) {
pillarRow(label: "", cells: ["年柱", "月柱", "日柱", "时柱"], size: 10, weight: .bold, color: { _ in pal.accent })
pillarRow(label: "十神", cells: chart.stemShiShen, size: 9.5, weight: .medium, color: { i in i == 2 ? pal.accentHi : pal.accent })
pillarRow(label: "天干", cells: chart.pillars.map { String($0.first!) }, size: 20, weight: .bold, color: { i in posterCharColor(chart.pillars[i].first!, fallback: pal.main) })
pillarRow(label: "地支", cells: chart.pillars.map { String($0.last!) }, size: 20, weight: .bold, color: { i in posterCharColor(chart.pillars[i].last!, fallback: pal.main) })
pillarRow(label: "藏干", cells: cangGanCells, size: 8.5, weight: .regular, color: { _ in pal.main })
pillarRow(label: "长生", cells: chart.diShi, size: 9.5, weight: .regular, color: { _ in pal.sub })
pillarRow(label: "纳音", cells: chart.pillars.map { BaziTables.naYin($0) }, size: 9.5, weight: .regular, color: { _ in pal.main })
}
.background(pal.card.opacity(0.8))
.clipShape(RoundedRectangle(cornerRadius: 6, style:.continuous))
.overlay(RoundedRectangle(cornerRadius: 6, style:.continuous).stroke(pal.cardStroke, lineWidth: 0.6))
}
private func pillarRow(label: String, cells: [String], size: CGFloat, weight: Font.Weight, color: @escaping (Int) -> Color) -> some View {
HStack(spacing: 0) {
Text(label).font(.system(size: 9, weight:.medium)).foregroundStyle(pal.sub).frame(width: 44, alignment:.trailing).padding(.trailing, 6)
ForEach(0..<4, id: \.self) { i in
Text(cells[i]).font(.system(size: size, weight: weight)).foregroundStyle(color(i)).frame(width: 108).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.vertical, 2)
}
}
}
/// 藏干格：本气／中气／余气各配十神（藏干首位即本气，与 BaziTables.cangGan 同序）
private var cangGanCells: [String] {
(0..<4).map { i in
let br = chart.pillars[i].last!
let roles = ["本气", "中气", "余气"]
return zip(BaziTables.cangGan[br] ?? [], chart.hideShiShen[i]).enumerated().map { (j, pair) in
"\(pair.0)·\(roles[min(j, 2)])·\(pair.1)"
}.joined(separator: "\n")
}
}
/// 七·补五行五项：真迹原文＋按喜忌打 ✓/×（中性按可用打 ✓）
private var buXingRows: [(String, String)] {
(0..<5).map { i in
let (g, _) = markGlyph(i)
return ("补\(Self.wxNames[i])大吉", "\(Self.buTexts[i]) \(g)")
}
}

/// 七·金钥（核心提炼词高亮用：喜用五行字、吉祥数、方位词、幸运色字、贵人属相字）
private var qiGoldKeys: [String] {
var keys: [String] = []
keys += xj.xi.map { Self.wxNames[$0] }
keys += xiNums.split(separator: "、").map(String.init)
keys += ["北方", "南方", "东方", "西方", "中央"]
keys += xj.xi.flatMap { (Self.colorMap[Self.wxNames[$0]] ?? "").split(separator: "、").map(String.init) }
keys += ["虎", "马", "狗", "猴", "鼠", "龙", "蛇", "鸡", "牛", "猪", "兔", "羊"]
return keys
}

/// 正文富文本：✓ 朱砂红加粗、× 次级灰、goldKeys 雅金加粗，其余正文色
private func richBody(_ body: String, goldKeys: [String]) -> Text {
var out = Text("")
var rest = body
let keys = goldKeys + ["✓", "×"]
while !rest.isEmpty {
var best: (range: Range<String.Index>, key: String, kind: Int)? = nil
for k in keys where !k.isEmpty {
if let r = rest.range(of: k) {
if best == nil || r.lowerBound < best!.range.lowerBound { best = (r, k, k == "✓" ? 1 : (k == "×" ? 2 : 0)) }
}
}
guard let b = best else { out = out + Text(rest); break }
if b.range.lowerBound > rest.startIndex { out = out + Text(String(rest[..<b.range.lowerBound])) }
let styled: Text
if b.kind == 1 { styled = Text(b.key).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Ky.cinnabar) }
else if b.kind == 2 { styled = Text(b.key).font(.system(size: 10.5, weight: .bold)).foregroundStyle(pal.sub) }
else { styled = Text(b.key).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Ky.gold) }
out = out + styled
rest = String(rest[b.range.upperBound...])
}
return out.font(.system(size: 10.5)).foregroundStyle(pal.main)
}

private func yuceSection(num: String, title: String, rows: [(String, String)], note: String? = nil, goldKeys: [String] = []) -> some View {
VStack(alignment:.leading, spacing: 3) {
HStack(spacing: 6) {
Text(num)
.font(.system(size: 11, weight:.bold, design:.serif))
.foregroundStyle(Ky.cinnabar)
.padding(.horizontal, 7).padding(.vertical, 2)
.background(Ky.gold.opacity(0.16))
.clipShape(Capsule())
.overlay(Capsule().stroke(Ky.gold.opacity(0.45), lineWidth: 0.7))
Text(title)
.font(.system(size: 12.5, weight:.bold, design:.serif))
.foregroundStyle(Ky.cinnabar)
if let note {
Text(note).font(.system(size: 9)).foregroundStyle(pal.sub)
}
}
ForEach(rows.indices, id: \.self) { j in
HStack(alignment: .top, spacing: 6) {
Text(rows[j].0)
.font(.system(size: 10.5, weight:.bold, design:.serif))
.foregroundStyle(Ky.cinnabar)
.padding(.horizontal, 7).padding(.vertical, 2)
.background(Ky.cinnabar.opacity(0.12))
.clipShape(Capsule())
richBody(rows[j].1, goldKeys: goldKeys)
.lineSpacing(2.0)
.fixedSize(horizontal: false, vertical: true)
.frame(maxWidth: .infinity, alignment: .leading)
.lineLimit(nil)
}
.frame(maxWidth: 420, alignment: .leading)
}
}
.fixedSize(horizontal: false, vertical: true)
}
}

struct PosterSheetView: View {
    let chart: BaziChart
    let name: String
    @State private var fileURL: URL?
    @State private var previewImage: UIImage?
    @State private var style: PosterStyle = .songQingdai
    @State private var showEditor = false
    @State private var saveMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // 尊享预测单独立入口（不占款式位）：宋纸青黛与预测单长图二选一
                Button(style == .yuceDan ? "切换回宋纸青黛海报" : "切换到尊享预测单长图") {
                    style = style == .yuceDan ? .songQingdai : .yuceDan
                    fileURL = nil; previewImage = nil; saveMessage = nil
                }
                .buttonStyle(.bordered)

                // G13：海报编辑器入口（.sheet 弹出，禁 fullScreenCover）
                Button("打开海报编辑器（换字／换色）") { showEditor = true }
                    .buttonStyle(KyPrimaryButton())
                    .sheet(isPresented: $showEditor) { PosterEditorView(chart: chart, name: name) }

                // P3：导出规格以 V6 指标卡静态呈现（1080 宽 PNG、scale 2.0、540pt 画布）
                HStack(spacing: 10) {
                    KyMetricCard(label: "导出宽度", value: "1080 px", badgeText: "PNG")
                    KyMetricCard(label: "渲染倍率", value: "2.0×", badgeText: "540 pt")
                }

                // 预览只展示缓存图片：海报矢量树绝不直接进 ScrollView（每帧重算 InterpretEngine.interpret 与 Canvas 重绘是粘滞主因之一）
                if let img = previewImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ky.line, lineWidth: 0.8))
                } else {
                    ProgressView(style == .yuceDan ? "正在渲染 1080宽长图海报…" : "正在渲染海报…")
                        .frame(maxWidth: .infinity)
                }

                if fileURL != nil, let img = previewImage {
                    ShareLink(item: img, preview: SharePreview(style == .yuceDan ? "尊享预测单长图海报" : "命盘海报", image: img)) {
                        Label(style == .yuceDan ? "保存 / 分享高清长图海报（1080宽 · 自适应长图）" : "保存 / 分享高清命盘海报（1080宽 · 自适应长图）", systemImage: "square.and.arrow.down")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(KyPrimaryButton())
                    Button {
                        PosterPhotoSaver.save(img) { saveMessage = $0 }
                    } label: {
                        Label("保存到相册", systemImage: "photo.badge.plus")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(KyPrimaryButton())
                    if let saveMessage {
                        Text(saveMessage)
                            .font(.caption).foregroundStyle(Ky.sub).multilineTextAlignment(.center)
                    }
                    Text("分享单点「存储图像」可存入相册，或点「保存到相册」直接存入；也可以直接转发微信。")
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
            // P3：海报内含 V6 Ky 组件（预测单的 KyMetricCard／KyHomeSection）时，Ky token 须按浅色定版渲染，
            // 不随系统深色走；海报自有 palette 为固定色，不受此环境值影响。
            let renderer = ImageRenderer(content: PosterView(chart: chart, name: name, style: style).environment(\.colorScheme, .light))
            renderer.scale = 2.0
            guard let img = renderer.uiImage, let data = img.pngData() else { return }
            let suffix = style.fileSuffix
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
                    .foregroundStyle(pal.main).lineLimit(2)
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

/// 中央天心宫三方四正飞线（与 ZiweiBoardView 同式：三合虚线三角＋对宫虚线＋罗经圆；画在天心宫底纹层，文字在上。Canvas 在 ImageRenderer 渲染路径下可用，宋纸远山 Canvas 已在同路径使用）
private struct ZiweiCenterFlyLines: View {
    let chart: ZiweiChart
    let pal: PosterPalette
    /// 十二宫在 4×4 方盘中的（行，列），与 ZiweiBoardView.cellPos 同表
    private static let cellPos: [Int: (Int, Int)] = [
        5: (0, 0), 6: (0, 1), 7: (0, 2), 8: (0, 3),
        4: (1, 0), 9: (1, 3),
        3: (2, 0), 10: (2, 3),
        2: (3, 0), 1: (3, 1), 0: (3, 2), 11: (3, 3)
    ]
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) * 0.42
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(pal.accent.opacity(0.22)), lineWidth: 0.9)
            func dirPoint(_ branch: Int) -> CGPoint {
                guard let rc = Self.cellPos[branch] else { return c }
                let nx = (CGFloat(rc.1) - 1.5) / 1.5
                let ny = (CGFloat(rc.0) - 1.5) / 1.5
                return CGPoint(x: c.x + nx * (size.width * 0.46), y: c.y + ny * (size.height * 0.46))
            }
            let ming = chart.mingGong
            let p0 = dirPoint(ming)
            let pT1 = dirPoint((ming + 4) % 12)
            let pT2 = dirPoint((ming + 8) % 12)
            let pOpp = dirPoint((ming + 6) % 12)
            var triPath = Path()
            triPath.move(to: p0)
            triPath.addLine(to: pT1)
            triPath.addLine(to: pT2)
            triPath.closeSubpath()
            ctx.stroke(triPath, with: .color(pal.accent.opacity(0.32)), style: StrokeStyle(lineWidth: 1.1, dash: [4, 3]))
            var oppPath = Path()
            oppPath.move(to: p0)
            oppPath.addLine(to: pOpp)
            ctx.stroke(oppPath, with: .color(pal.accentHi.opacity(0.38)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
        }
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
        return ZStack {
            ZiweiCenterFlyLines(chart: chart, pal: pal)
            VStack(spacing: 5) {
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
    private var mingCard: (title: String, conclusion: String, facts: String, source: String)? {
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

    private var sanFangLine: String {
        ["命宫", "财帛", "官禄", "迁移"].compactMap { n in
            chart.palaces.first(where: { $0.name == n }).map { p in
                let stars = p.majors.map { $0.star }.joined(separator: "·")
                return "\(n)：\(stars.isEmpty ? "无主星" : stars)"
            }
        }.joined(separator: "；")
    }
    private var currentDecadePalace: ZiweiPalace? {
        let nowYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let age = chart.birthYear > 0 ? nowYear - chart.birthYear + 1 : 0
        return chart.palaces.first { p in
            guard let a = p.decadal.first, let b = p.decadal.last else { return false }
            return age > 0 && age >= a && age <= b
        }
    }
    private var daXianHuaLine: String {
        guard let dp = currentDecadePalace else { return "—" }
        return ZiweiCore.mutagens(ofStem: dp.stem).map { m in
            let target = ZiweiCore.palaceOf(chart, star: m.star)?.name ?? "—"
            return "\(m.star)化\(m.kind)入\(target)"
        }.joined(separator: "；")
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
                RoundedRectangle(cornerRadius: 4).stroke(pal.cardStroke, lineWidth: 1.0).padding(22)
                VStack {
                    Spacer()
                    SongMountainHeaderView(accent: pal.accent)
                        .padding(.horizontal, 23).padding(.bottom, 23)
                }

            VStack(spacing: 0) {
                    Text("紫 微 斗 数 · 命 盘 雅 集")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(4)
                        .foregroundStyle(pal.accent)
                        .padding(.top, 52)
                    Text(name.isEmpty ? "紫微命盘" : name)
                        .font(.system(size: 44, weight: .bold, design: .serif))
                        .foregroundStyle(pal.main)
                        .padding(.top, 16)

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
                            .lineSpacing(3.5).fixedSize(horizontal: false, vertical: true)
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

                // 命身宫三方四正（命／财／官／迁四宫主星）
                VStack(alignment: .leading, spacing: 4) {
                    Text("命身宫三方四正")
                        .font(.system(size: 12, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
                    Text(sanFangLine)
                        .font(.system(size: 11)).foregroundStyle(pal.main)
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 444, alignment: .leading)
                .padding(.top, 12)

                // 当步大限四化（按虚岁落入的大限宫干起四化）
                if let dp = currentDecadePalace {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当步大限四化 · \(dp.decadal.first ?? 0)–\(dp.decadal.last ?? 0) 岁走\(dp.name)")
                            .font(.system(size: 12, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
                        Text(daXianHuaLine)
                            .font(.system(size: 11)).foregroundStyle(pal.main)
                            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: 444, alignment: .leading)
                    .padding(.top, 10)
                }

                // 十二宫逐宫详批（宫名＋主星＋大限区间）
                VStack(alignment: .leading, spacing: 5) {
                    Text("十二宫逐宫详批")
                        .font(.system(size: 12, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4), spacing: 5) {
                        ForEach(chart.palaces, id: \.branch) { p in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.system(size: 9.5, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
                                Text(p.majors.map { $0.star }.joined(separator: "·").isEmpty ? "—" : p.majors.map { $0.star }.joined(separator: "·"))
                                    .font(.system(size: 9)).foregroundStyle(pal.main).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                Text("\(p.decadal.first ?? 0)–\(p.decadal.last ?? 0) 岁").font(.system(size: 8.5)).foregroundStyle(pal.sub)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(pal.card)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(pal.cardStroke, lineWidth: 0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(width: 444, alignment: .leading)
                .padding(.top, 10)

                Spacer()

                // 统一品牌落款（P3 第 1 项）：同一印章＋同一品牌行，副标与日期各款保留
                PosterBrandFooter(pal: pal, subtitle: "三合派天纪口径 · 方盘缩印 · 生年四化")
            }

            // 宋纸版右缘竖排题签（真竖排：中文单字直下；只用于眉题短句，全文不竖排）
                VerticalText(text: "紫微斗数", fontSize: 13, color: pal.accent, spacing: 5)
                    .position(x: 506, y: 110)
        }
        .frame(width: 540)
    }
}

struct ZiweiPosterSheetView: View {
    let chart: ZiweiChart
    let name: String
    @State private var fileURL: URL?
    @State private var style: PosterStyle = .songQingdai
    @State private var previewImage: UIImage?
    @State private var saveMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // P3：导出规格以 V6 指标卡静态呈现（1080 宽 PNG、scale 2.0、540pt 画布）
                HStack(spacing: 10) {
                    KyMetricCard(label: "导出宽度", value: "1080 px", badgeText: "PNG")
                    KyMetricCard(label: "渲染倍率", value: "2.0×", badgeText: "540 pt")
                }

                if let img = previewImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ky.line, lineWidth: 0.8))
                } else {
                    ProgressView("正在渲染 1080宽长图海报…")
                        .frame(maxWidth: .infinity)
                }

                if fileURL != nil, let img = previewImage {
                    ShareLink(item: img, preview: SharePreview("紫微命盘海报", image: img)) {
                        Label("保存 / 分享高清紫微命盘海报（1080宽 · 自适应长图）", systemImage: "square.and.arrow.down")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(KyPrimaryButton())
                    Button {
                        PosterPhotoSaver.save(img) { saveMessage = $0 }
                    } label: {
                        Label("保存到相册", systemImage: "photo.badge.plus")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(KyPrimaryButton())
                    if let saveMessage {
                        Text(saveMessage)
                            .font(.caption).foregroundStyle(Ky.sub).multilineTextAlignment(.center)
                    }
                    Text("分享单点「存储图像」可存入相册，或点「保存到相册」直接存入；也可以直接转发微信。")
                        .font(.caption).foregroundStyle(Ky.sub).multilineTextAlignment(.center)
                } else {
                    ProgressView("正在渲染 1080宽长图海报…")
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
            let suffix = style.fileSuffix
            previewImage = img
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
    private var pal: PosterPalette { style.palette }
    private var mingCard: (title: String, conclusion: String, facts: String, source: String)? {
        ZiweiReading.cards(chart: ziwei).first { $0.title == "命宫定型" }
    }
    private var zwCards: [(title: String, conclusion: String, facts: String, source: String)] {
        ZiweiReading.cards(chart: ziwei)
    }
    private func zwConclusion(_ title: String) -> String { zwCards.first { $0.title == title }?.conclusion ?? "" }
    private func baziConclusion(_ title: String) -> String { items.first(where: { $0.title == title })?.conclusion ?? "" }
    /// 紫微宫位气色：化禄／权／科为吉，化忌或六煞（擎羊／陀罗／火星／铃星／地空／地劫）为慎，吉凶参半为平
    private func ziweiTone(palaceName: String) -> Int {
        guard let p = ziwei.palaces.first(where: { $0.name == palaceName }) else { return 0 }
        let stars = p.majors + p.minors
        let hasJi = stars.contains { $0.mutagen == "忌" }
        let hasSha = p.minors.contains { ["擎羊", "陀罗", "火星", "铃星", "地空", "地劫"].contains($0.star) }
        let hasLu = stars.contains { ["禄", "权", "科"].contains($0.mutagen ?? "") }
        if hasJi || hasSha { return hasLu ? 0 : -1 }
        return hasLu ? 1 : 0
    }
    /// 八字维度气色：关键星（官／财／配偶星）五行套喜忌；健康维按身强弱定
    private func baziTone(dim: String) -> Int {
        let xj = InterpretEngine.posterXiJi(chart: bazi)
        if xj.level == "中和" { return 0 }
        let key: Int
        switch dim {
        case "事业": key = InterpretEngine.keyWxIndex(chart: bazi, title: "事业方向")
        case "财富": key = InterpretEngine.keyWxIndex(chart: bazi, title: "财运形态")
        case "婚恋": key = InterpretEngine.keyWxIndex(chart: bazi, title: "婚姻感情")
        default: return -1
        }
        if xj.xi.contains(key) { return 1 }
        if xj.ji.contains(key) { return -1 }
        return 0
    }
    /// 双术交叉裁决（规则裁决：两术气色同吉／同慎／一顺一逆／不同步；依据见卡内两行原文）
    private func crossVerdict(bazi b: Int, ziwei z: Int) -> String {
        if b == 1 && z == 1 { return "同频相催，宜主动推进。" }
        if b == -1 && z == -1 { return "分期应验，守成待时。" }
        if b == 1 || z == 1 { return "互补制化，顺者开路。" }
        return "分期应验，按大运大限。"
    }
    /// 四维交叉裁决卡（事业／财富／婚恋／健康：八字结论＋紫微结论＋裁决句）
    private var crossCards: [(dim: String, bazi: String, ziwei: String, verdict: String)] {
        let dims: [(String, String, String, String)] = [
            ("事业", "事业方向", "官禄事业", "官禄"),
            ("财富", "财运形态", "财帛赚钱", "财帛"),
            ("婚恋", "婚姻感情", "夫妻婚恋", "夫妻"),
            ("健康", "健康倾向", "疾厄体质", "疾厄"),
        ]
        return dims.map { d in
            let b = baziTone(dim: d.0)
            let z = ziweiTone(palaceName: d.3)
            return (d.0, baziConclusion(d.1), zwConclusion(d.2), crossVerdict(bazi: b, ziwei: z))
        }
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
                RoundedRectangle(cornerRadius: 4).stroke(pal.cardStroke, lineWidth: 1.0).padding(22)
                VStack {
                    Spacer()
                    SongMountainHeaderView(accent: pal.accent)
                        .padding(.horizontal, 23).padding(.bottom, 23)
                }

            VStack(spacing: 0) {
                    Text("三 术 合 参 · 一 页 要 点")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(4)
                        .foregroundStyle(pal.accent)
                        .padding(.top, 52)
                    Text(name.isEmpty ? "合参总览" : name)
                        .font(.system(size: 44, weight: .bold, design: .serif))
                        .foregroundStyle(pal.main)
                        .padding(.top, 16)

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
                        .frame(width: 82, height: 108)
                        .background(pal.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(i == 2 ? pal.accentHi.opacity(0.65) : pal.cardStroke, lineWidth: i == 2 ? 1.2 : 0.8)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                // 八字四柱 ⟷ 紫微方盘 左右并列
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("八字总断").font(.system(size: 12, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
                        if !headline.isEmpty {
                            Text(headline).font(.system(size: 11.5)).foregroundStyle(pal.main).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        }
                        if !gejuLine.isEmpty {
                            Text(gejuLine).font(.system(size: 11)).foregroundStyle(pal.accent).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(width: 217, alignment: .leading)
                    .background(pal.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(pal.cardStroke, lineWidth: 0.8))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("紫微方盘 · \(mingStars)").font(.system(size: 12, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
                        if let mc = mingCard {
                            Text(mc.conclusion).font(.system(size: 11.5)).foregroundStyle(pal.main).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        }
                        if !huaLine.isEmpty {
                            Text(huaLine).font(.system(size: 11)).foregroundStyle(pal.accent).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(width: 217, alignment: .leading)
                    .background(pal.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(pal.cardStroke, lineWidth: 0.8))
                }
                .padding(.top, 12)

                // 双术交叉印证（事业／财富／婚恋／健康四维裁决卡）
                VStack(alignment: .leading, spacing: 8) {
                    Text("双术交叉印证")
                        .font(.system(size: 13, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        ForEach(crossCards, id: \.dim) { c in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.dim).font(.system(size: 11.5, weight: .bold, design: .serif)).foregroundStyle(pal.accent)
                                Text("八字：" + c.bazi).font(.system(size: 10.5)).foregroundStyle(pal.main).lineSpacing(2.5).fixedSize(horizontal: false, vertical: true)
                                Text("紫微：" + c.ziwei).font(.system(size: 10.5)).foregroundStyle(pal.main).lineSpacing(2.5).fixedSize(horizontal: false, vertical: true)
                                Text(c.verdict).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Ky.gold).lineSpacing(2.5).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(10)
                            .background(pal.card)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(pal.cardStroke, lineWidth: 0.7))
                        }
                    }
                }
                .frame(width: 444, alignment: .leading)
                .padding(.top, 10)

                // 手相面相要点（只引已存测量摘要，无记录时明言未测，不编）
                sectionCard(title: "手相面相要点") {
                    if palmLines.isEmpty {
                        Text("尚未测量：在「手相面相」页测一张掌纹并按人保存后，这里会自动带上测量摘要。判读为娱乐参考。")
                            .font(.system(size: 12)).foregroundStyle(pal.sub).lineSpacing(3.5).fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(palmLines.prefix(2), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 12.5)).foregroundStyle(pal.main)
                                .lineSpacing(3.5).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 10)

                Spacer()

                // 统一品牌落款（P3 第 1 项）：同一印章＋同一品牌行，副标与日期各款保留；底留白由 36 统一为 42（P3 第 6 项）
                PosterBrandFooter(pal: pal, subtitle: "八字总断 · 紫微方盘 · 双术交叉印证 · 一页合参")
            }

            // 宋纸版右缘竖排题签（真竖排：中文单字直下；只用于眉题短句，全文不竖排）
                VerticalText(text: "三术合参", fontSize: 13, color: pal.accent, spacing: 5)
                    .position(x: 506, y: 110)
        }
        // 自适应高度（与预测单长图同款：只定宽 540，高随内容走；旧 960 定高在宋纸版留约 100pt 底白）
        .frame(width: 540)
    }
}

struct HeCanPosterSheetView: View {
    let bazi: BaziChart
    let ziwei: ZiweiChart
    let name: String
    var palmLines: [String] = []
    @State private var fileURL: URL?
    @State private var previewImage: UIImage?
    @State private var style: PosterStyle = .songQingdai
    @State private var saveMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // P3：导出规格以 V6 指标卡静态呈现（1080 宽 PNG、scale 2.0、540pt 画布）
                HStack(spacing: 10) {
                    KyMetricCard(label: "导出宽度", value: "1080 px", badgeText: "PNG")
                    KyMetricCard(label: "渲染倍率", value: "2.0×", badgeText: "540 pt")
                }

                // 预览只展示缓存图片（与命盘／紫微海报同款；旧 live 缩放预览依赖 960 定高，自适应高度后改走缓存图）
                if let img = previewImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ky.line, lineWidth: 0.8))
                } else {
                    ProgressView("正在渲染 1080宽长图海报…")
                        .frame(maxWidth: .infinity)
                }

                if fileURL != nil, let img = previewImage {
                    ShareLink(item: img, preview: SharePreview("合参海报", image: img)) {
                        Label("保存 / 分享高清合参海报（1080宽 · 自适应长图）", systemImage: "square.and.arrow.down")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(KyPrimaryButton())
                    Button {
                        PosterPhotoSaver.save(img) { saveMessage = $0 }
                    } label: {
                        Label("保存到相册", systemImage: "photo.badge.plus")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(KyPrimaryButton())
                    if let saveMessage {
                        Text(saveMessage)
                            .font(.caption).foregroundStyle(Ky.sub).multilineTextAlignment(.center)
                    }
                    Text("分享单点「存储图像」可存入相册，或点「保存到相册」直接存入；也可以直接转发微信。")
                        .font(.caption).foregroundStyle(Ky.sub).multilineTextAlignment(.center)
                } else {
                    ProgressView("正在渲染 1080宽长图海报…")
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
            let suffix = style.fileSuffix
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("hecan-poster-\(name.isEmpty ? "chart" : name)\(suffix).png")
            try? data.write(to: url, options: .atomic)
            previewImage = img
            fileURL = url
        }
    }
}
