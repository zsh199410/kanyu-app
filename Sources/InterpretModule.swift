// 解盘 · 初断（规则层）：排盘之后的第一层解读，全部结论走依据链（结论←规则←盘面事实）。
// 定位写死：这是结构化初断——命局风景/月令格局候选/扶抑调候喜忌/十神分布/岁运要点；
// 工作室级的直断逐年（回测校准过的那套）仍以正式报告为准，App 内不冒充。
import SwiftUI

struct InterpretItem {
    let title: String
    let conclusion: String
    let links: [(label: String, text: String)]
}

enum InterpretEngine {
    private static let wxNames = ["木", "火", "土", "金", "水"]
    private static func wxIndex(of stem: Character) -> Int {
        switch stem { case "甲", "乙": return 0; case "丙", "丁": return 1
        case "戊", "己": return 2; case "庚", "辛": return 3; default: return 4 }
    }
    static func interpret(chart ch: BaziChart) -> [InterpretItem] {
        var items: [InterpretItem] = []
        let pct = ch.wuxingPercents
        let dayStem = ch.rizhu.first!
        let dayWx = wxIndex(of: dayStem)
        // 1 命局风景（五行分布直读）
        let order = pct.indices.sorted { pct[$0] > pct[$1] }
        let strong = order.first!; let weak = order.last!
        items.append(InterpretItem(
            title: "命局风景",
            conclusion: "五行里\(wxNames[strong])最重（\(Int(pct[strong].rounded()))%）、\(wxNames[weak])最轻（\(Int(pct[weak].rounded()))%）；日主\(ch.rizhu)属\(wxNames[dayWx])，力量排第 \(order.firstIndex(of: dayWx)! + 1)。",
            links: [("盘面", "五行占比 木\(Int(pct[0].rounded())) 火\(Int(pct[1].rounded())) 土\(Int(pct[2].rounded())) 金\(Int(pct[3].rounded())) 水\(Int(pct[4].rounded()))"),
                    ("口径", "占比为盘面计法（天干＋藏干加权），只说明分布，不直接等于强弱结论")]))
        // 2 月令格局候选（本气十神，透干校验）
        let monthBranch = ch.monthPillar.last!
        let benQi = BaziTables.cangGan[monthBranch]!.first!
        let benQiSS = BaziTables.shiShen(day: dayStem, stem: benQi)
        let touGan = ch.stemShiShen[1] == benQiSS
        items.append(InterpretItem(
            title: "月令格局（候选）",
            conclusion: "月令\(monthBranch)本气\(benQi)对日主为\(benQiSS)，先按\(benQiSS)格候选看。\(touGan ? "月干透出同气，格象较明。" : "本气未透干，格象要结合透藏与岁运再定，此处只作候选。")",
            links: [("盘面", "月柱 \(ch.monthPillar)，本气 \(benQi)；月干十神 \(ch.stemShiShen[1])"),
                    ("法则", "《子平真诠》：格以月令本气为纲，透干则格明")]))
        // 3 扶抑＋调候喜忌（初判）
        let shengWo = (dayWx + 4) % 5  // 生我者：木←水 火←木 土←火 金←土 水←金
        let tongDang = pct[dayWx] + pct[shengWo]
        let level = tongDang >= 55 ? "偏强" : (tongDang <= 40 ? "偏弱" : "中和")
        let xiText: String
        switch level {
        case "偏强": xiText = "扶抑上喜克、泄、耗——\(wxNames[(dayWx + 1) % 5])（食伤）\(wxNames[(dayWx + 2) % 5])（财）\(wxNames[(dayWx + 3) % 5])（官杀）方向可用，忌再添\(wxNames[shengWo])\(wxNames[dayWx])。"
        case "偏弱": xiText = "扶抑上喜生扶——\(wxNames[shengWo])（印）与\(wxNames[dayWx])（比劫）为援，忌克泄耗再压。"
        default: xiText = "同党异党接近，贵在流通：哪一行堵住就疏哪一行，不预设固定喜忌。"
        }
        var tiaoHou = ""
        if ["亥", "子", "丑"].contains(monthBranch) { tiaoHou = "生于寒月，调候另喜火暖局。" }
        if ["巳", "午", "未"].contains(monthBranch) { tiaoHou = "生于热月，调候另喜水润局。" }
        items.append(InterpretItem(
            title: "喜忌（扶抑初判）",
            conclusion: "日主\(level)：同党（\(wxNames[dayWx])＋印\(wxNames[shengWo])）约占 \(Int(tongDang.rounded()))%。\(xiText)\(tiaoHou)",
            links: [("盘面", "日主 \(ch.rizhu)（\(wxNames[dayWx])），月令 \(monthBranch)"),
                    ("法则", "扶抑取用为初判框架；《穷通宝鉴》调候优先于扶抑，两条冲突时以调候为先")]))
        // 4 十神分布看点
        let groups: [(String, [String], String)] = [
            ("官杀", ["正官", "七杀"], "规矩与压力成势：对秩序、名分、责任敏感，行事有框线感。"),
            ("印星", ["正印", "偏印"], "印星成势：重学习、凭靠与安全感，遇事先找依据和退路。"),
            ("财星", ["正财", "偏财"], "财星成势：对资源与结果敏感，行事重实效，钱与机会的嗅觉靠前。"),
            ("食伤", ["食神", "伤官"], "食伤成势：表达与手艺成势，靠输出吃饭，不喜被管束。"),
            ("比劫", ["比肩", "劫财"], "比劫成势：自我与同辈成势，主见强，合作与分账要先立规矩。"),
        ]
        var counts: [String: Int] = [:]
        for ss in ch.stemShiShen where ss != "日主" { counts[ss, default: 0] += 1 }
        for row in ch.hideShiShen { for ss in row { counts[ss, default: 0] += 1 } }
        let scored = groups.map { g -> (String, Int, String) in
            (g.0, g.1.reduce(0) { $0 + (counts[$1] ?? 0) }, g.2)
        }.sorted { $0.1 > $1.1 }
        if let top = scored.first, top.1 > 0 {
            items.append(InterpretItem(
                title: "十神看点",
                conclusion: top.2,
                links: [("盘面", "透干＋藏干合计：\(scored.map { "\($0.0) \($0.1)" }.joined(separator: " · "))"),
                        ("口径", "分布只定势的主次，具体事件要回到宫位与岁运引动，不单凭分布断事")]))
        }
        // 5 岁运要点（当前大运＋本年流年与日支关系）
        let nowYear = Calendar.current.component(.year, from: Date())
        var curIdx: Int? = nil
        for i in ch.dayunGanZhi.indices where nowYear >= ch.dayunStartYear(i) && nowYear <= ch.dayunStartYear(i) + 9 { curIdx = i }
        var yunText: String; var yunFacts: String
        if let i = curIdx {
            let gz = ch.dayunGanZhi[i]
            let ss = BaziTables.shiShen(day: dayStem, stem: gz.first!)
            yunText = "现行\(gz)大运（\(ch.dayunStartYear(i))–\(ch.dayunStartYear(i) + 9)），运干对日主为\(ss)——这十年的主课题先按\(ss)看。"
            yunFacts = "大运 \(gz)，起运 \(ch.qiyunDate)"
        } else {
            yunText = "尚未起运或已出已排大运范围，按童限与流年看。"
            yunFacts = "起运 \(ch.qiyunDate)"
        }
        let ln = BaziChart.yearGanZhi(nowYear)
        let dayBranch = ch.dayPillar.last!
        let lnBranch = ln.last!
        let chongPairs: [Character: Character] = ["子": "午", "午": "子", "丑": "未", "未": "丑", "寅": "申", "申": "寅",
                                                   "卯": "酉", "酉": "卯", "辰": "戌", "戌": "辰", "巳": "亥", "亥": "巳"]
        let hePairs: [Character: Character] = ["子": "丑", "丑": "子", "寅": "亥", "亥": "寅", "卯": "戌", "戌": "卯",
                                               "辰": "酉", "酉": "辰", "巳": "申", "申": "巳", "午": "未", "未": "午"]
        var relText = "与日支\(dayBranch)无直接冲合，属平流年。"
        if chongPairs[dayBranch] == lnBranch { relText = "流年\(lnBranch)冲日支\(dayBranch)：今年动象落在根基、居所与亲密关系一线，宜主动求变、忌被动挨冲。" }
        if hePairs[dayBranch] == lnBranch { relText = "流年\(lnBranch)合日支\(dayBranch)：今年牵合之象落在自身与亲密关系一线，合作、缔约、关系推进的信号强。" }
        items.append(InterpretItem(
            title: "岁运要点",
            conclusion: "\(yunText) \(nowYear) 年流年\(ln)：\(relText)",
            links: [("盘面", yunFacts), ("法则", "应期看引动：冲合落到哪一宫，哪一线的事先动")]))
        return items
    }
}

struct InterpretView: View {
    let chart: BaziChart
    let name: String
    var body: some View {
        let items = InterpretEngine.interpret(chart: chart)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(items.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(items[i].title)
                            .font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
                        EvidenceChainView(conclusion: items[i].conclusion, links: items[i].links)
                    }
                    .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Text("初断（规则层）：以上为盘面结构化初读，每条附依据链可复核。正式命书的直断与逐年（经回测校准）以工作室报告为准，后续版本逐步并入。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle(name.isEmpty ? "解盘 · 初断" : "解盘 · \(name)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
