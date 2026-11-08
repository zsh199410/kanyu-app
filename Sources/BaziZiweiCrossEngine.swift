import SwiftUI

/// 八字＋紫微双术合参交叉印证引擎（build-97）
/// 八字定大势（五行旺衰／大运走向），紫微定场景（十二宫位人事／星曜四化）。
/// 四大维度各出八字信号＋紫微信号：同频（同向）／分歧（反向）＋综合裁决。
/// 裁决规则（写死在引擎里，不编第三术）：同频→两术同向，结论加一档；
/// 分歧→以八字大势定方向、紫微场景定节奏与提醒，不强行调和。
enum BaziZiweiCrossEngine {
    /// 裁决种类：同频相催（两术同向，结论加一档）／互补制化（方向与场景分层，不强行调和）／分期应验（底子与应期分两期）
    enum Kind: String {
        case tongPin = "同频相催"
        case huBu = "互补制化"
        case fenQi = "分期应验"
    }
    struct Verdict {
        let title: String
        let bazi: String
        let ziwei: String
        let verdict: String
        let kind: Kind
    }

    static let wxN = ["木", "火", "土", "金", "水"]

    static func verdicts(bazi: BaziChart, ziwei: ZiweiChart) -> [Verdict] {
        [career(bazi: bazi, ziwei: ziwei), wealth(bazi: bazi, ziwei: ziwei),
         love(bazi: bazi, ziwei: ziwei), health(bazi: bazi, ziwei: ziwei)]
    }

    // MARK: - 共用取数
    private static func palace(_ ch: ZiweiChart, _ name: String) -> ZiweiPalace {
        ch.palaces.first { $0.name == name }!
    }
    private static func starLine(_ p: ZiweiPalace) -> String {
        p.majors.isEmpty ? "无主星（借对宫）" : p.majors.map { $0.star }.joined(separator: "、")
    }
    private static func hua(_ p: ZiweiPalace, _ kind: String) -> [String] {
        (p.majors + p.minors).filter { $0.mutagen == kind }.map { $0.star }
    }
    private static func count(_ bazi: BaziChart, _ names: [String]) -> Int {
        var n = 0
        for ss in bazi.stemShiShen where names.contains(ss) { n += 1 }
        for row in bazi.hideShiShen { for ss in row where names.contains(ss) { n += 1 } }
        return n
    }
    private static func hasRoot(_ bazi: BaziChart, _ names: [String]) -> Bool {
        let day = bazi.rizhu.first!
        for p in bazi.pillars {
            let cg = BaziTables.cangGan[p.last!]!
            if let f = cg.first, names.contains(BaziTables.shiShen(day: day, stem: f)) { return true }
        }
        return false
    }
    private static func dayWx(_ bazi: BaziChart) -> Int {
        wxN.firstIndex(of: BaziTables.wx[bazi.rizhu.first!]?.0 ?? "") ?? 2
    }
    /// 比劫破耗防范期（近十二年内前两处：冲财库／冲日支／流年干比劫夺财）
    private static func poHaoYears(_ bazi: BaziChart) -> [String] {
        let ku = BaziTables.caiKuBranch(dayWx: dayWx(bazi))
        var out: [String] = []
        let nowY = Calendar.current.component(.year, from: Date())
        for y in nowY...(nowY + 11) {
            let gz = YearEngine.report(chart: bazi, year: y).gz
            let yb = gz.last!
            var reasons: [String] = []
            if BaziTables.relationFull(yb, ku)?.0 == "冲" { reasons.append("冲财库\(ku)") }
            if BaziTables.relationFull(yb, bazi.dayPillar.last!)?.0 == "冲" { reasons.append("冲日支") }
            let yss = BaziTables.shiShen(day: bazi.rizhu.first!, stem: gz.first!)
            if yss == "比肩" || yss == "劫财" { reasons.append("流年干比劫夺财") }
            if !reasons.isEmpty { out.append("\(y)年\(gz)（\(reasons.joined(separator: "、"))）") }
            if out.count >= 2 { break }
        }
        return out
    }

    // MARK: - 事业
    private static func career(bazi: BaziChart, ziwei: ZiweiChart) -> Verdict {
        let guan = count(bazi, ["正官", "七杀"])
        let yin = count(bazi, ["正印", "偏印"])
        let shi = count(bazi, ["食神", "伤官"])
        let cai = count(bazi, ["正财", "偏财"])
        let guanP = palace(ziwei, "官禄")
        let mingP = ziwei.palaces[ziwei.mingGong]
        let gz = guanP.majors.map { $0.star }
        let stable: Set<String> = ["紫微", "天府", "太阳", "天机", "天梁", "太阴", "文昌", "文曲", "左辅", "右弼"]
        let pioneer: Set<String> = ["破军", "七杀", "贪狼", "武曲", "廉贞"]
        let zwStable = !Set(gz).intersection(stable).isEmpty
        let zwPioneer = !Set(gz).intersection(pioneer).isEmpty
        let baziStrong = guan >= 3 || (guan >= 1 && yin >= 2)
        let baziPioneer = shi >= 3 && cai >= 1
        // 建禄／阳刃／月劫：月令本气为比肩／劫财（身强自立，宜专业技术与自主创业）
        let monthBenQi = BaziTables.cangGan[bazi.monthPillar.last!]!.first!
        let monthBenQiSS = BaziTables.shiShen(day: bazi.rizhu.first!, stem: monthBenQi)
        let jianLu = monthBenQiSS == "比肩" || monthBenQiSS == "劫财"
        let geName = monthBenQiSS == "比肩" ? "建禄格" : (BaziTables.wx[bazi.rizhu.first!]?.1 == 1 ? "阳刃格" : "月劫格")
        let huaQuan = hua(guanP, "权"), huaLu = hua(guanP, "禄")
        let bSig = "官杀\(guan) · 印\(yin) · 食伤\(shi) · 财\(cai)；禄刃\(jianLu ? "见" : "不见")"
        let zSig = "官禄坐\(starLine(guanP))；化权\(huaQuan.isEmpty ? "无" : huaQuan.joined(separator: "、"))／化禄\(huaLu.isEmpty ? "无" : huaLu.joined(separator: "、"))；命宫坐\(starLine(mingP))"
        if baziStrong && zwStable {
            return Verdict(title: "事业", bazi: bSig, ziwei: zSig,
                verdict: "同频相催：体制／管理线。八字官印成势、紫微官禄坐稳星，两术都指向平台与秩序——体制、大机构、纪律性强的行业是主场，越规范越出成绩。",
                kind: .tongPin)
        }
        if baziPioneer && zwPioneer {
            return Verdict(title: "事业", bazi: bSig, ziwei: zSig,
                verdict: "同频相催：创业／开拓线。八字食伤生财、紫微官禄坐开拓星，两术都指向自己干——技术、手艺、产品变现是主场，自由度越高越强。",
                kind: .tongPin)
        }
        if jianLu && (zwPioneer || !huaQuan.isEmpty || !huaLu.isEmpty) {
            return Verdict(title: "事业", bazi: bSig, ziwei: zSig,
                verdict: "同频相催：自主创业／专业技术线。八字\(geName)（月令本气\(monthBenQiSS)）、紫微官禄见化权／化禄或开拓星，两术都指向自立——专业技术、自主创业是主场，靠本事吃饭。",
                kind: .tongPin)
        }
        let dir = baziStrong ? "官印成势" : (baziPioneer ? "食伤生财" : (jianLu ? "建禄自立" : "无单一主星压场"))
        let rhythm = zwStable ? "稳星在官禄，节奏宜稳扎稳打" : (zwPioneer ? "开拓星在官禄，节奏宜快攻快守" : "官禄星曜平常，节奏宜随运走")
        return Verdict(title: "事业", bazi: bSig, ziwei: zSig,
            verdict: "互补制化：以八字大势定方向、紫微场景定节奏。八字\(dir)，紫微官禄坐\(starLine(guanP))——方向按八字走，紫微只作场景提醒：\(rhythm)。",
            kind: .huBu)
    }

    // MARK: - 财运
    private static func wealth(bazi: BaziChart, ziwei: ZiweiChart) -> Verdict {
        let cai = count(bazi, ["正财", "偏财"])
        let root = hasRoot(bazi, ["正财", "偏财"])
        let guan = count(bazi, ["正官", "七杀"])
        let shi = count(bazi, ["食神", "伤官"])
        let ku = BaziTables.caiKuBranch(dayWx: dayWx(bazi))
        let kuN = bazi.pillars.filter { $0.last! == ku }.count
        let caiP = palace(ziwei, "财帛")
        let tianP = palace(ziwei, "田宅")
        let luCai = hua(caiP, "禄"), luTian = hua(tianP, "禄"), jiCai = hua(caiP, "忌")
        let luHit = !luCai.isEmpty || !luTian.isEmpty
        let caiStars = Set(caiP.majors.map { $0.star })
        let goodStars: Set<String> = ["武曲", "太阴", "天府", "紫微"]
        // 赚钱模式：工资型（官印＋财有根）／经营型（食伤生财＋财旺）／守成型（余）
        let leiXing = (guan >= 2 && cai >= 1 && root) ? "工资型" : ((shi >= 2 && cai >= 2) ? "经营型" : "守成型")
        let poHao = poHaoYears(bazi)
        let poHaoText = poHao.isEmpty ? "近十二年无典型破耗年份。" : "比劫破耗防范期：\(poHao.joined(separator: "；"))——这些年份忌借贷担保与冲动置产。"
        let bSig = "财星\(cai)个，财库\(ku)支见\(kuN)处，财\(root ? "有根" : "无根")"
        let zSig = "财帛坐\(starLine(caiP))；化禄\(luHit ? "在财帛／田宅" : "无")；化忌\(jiCai.isEmpty ? "无" : "在财帛")"
        if cai >= 2 && root && (luHit || !caiStars.intersection(goodStars).isEmpty) {
            return Verdict(title: "财运", bazi: bSig, ziwei: zSig,
                verdict: "同频相催：正财稳进。八字财星有根、紫微财帛见禄星或稳星，两术都指向钱路正、进得出——正业收入是主干，偏财是点缀。赚钱模式：\(leiXing)。\(poHaoText)",
                kind: .tongPin)
        }
        if cai <= 1 && !root && !jiCai.isEmpty {
            return Verdict(title: "财运", bazi: bSig, ziwei: zSig,
                verdict: "同频相催：守成为主。八字财星弱而无根、紫微化忌在财帛，两术都提示财路偏紧——守成为主，忌借贷担保与冲动置产。赚钱模式：\(leiXing)。\(poHaoText)",
                kind: .tongPin)
        }
        if root && !jiCai.isEmpty {
            return Verdict(title: "财运", bazi: bSig, ziwei: zSig,
                verdict: "分期应验：量级在、时机须等。八字财星有根（量级不差），紫微化忌在财帛（当前财路有漏）——财路分两期：先守后进，等化忌引动的年份过去再放量。赚钱模式：\(leiXing)。\(poHaoText)",
                kind: .fenQi)
        }
        return Verdict(title: "财运", bazi: bSig, ziwei: zSig,
            verdict: "互补制化：以八字定财的量级、以紫微定财的场景。八字财星\(cai)个\(root ? "有根" : "无根")、财库见\(kuN)处；紫微财帛\(luHit ? "见化禄" : "无化禄")\(jiCai.isEmpty ? "" : "、化忌在财帛须防漏财")——量级按八字看，场景按紫微防。赚钱模式：\(leiXing)。\(poHaoText)",
            kind: .huBu)
    }

    // MARK: - 婚姻
    private static func love(bazi: BaziChart, ziwei: ZiweiChart) -> Verdict {
        let names = bazi.gender == "M" ? ["正财", "偏财"] : ["正官", "七杀"]
        let spouse = count(bazi, names)
        let root = hasRoot(bazi, names)
        let fuP = palace(ziwei, "夫妻")
        let jiFu = hua(fuP, "忌")
        let hong = fuP.minors.contains { $0.star == "红鸾" || $0.star == "天喜" }
        // 孤辰／寡宿（八字神煞）与配偶宫坐支牵动（日支与年月时支最强牵动）
        let shenSha = Set(BaziTables.shenSha(bazi).flatMap { $0 })
        let guChen = shenSha.contains("孤辰"), guaSu = shenSha.contains("寡宿")
        let guNote = (guChen || guaSu) ? "另带\(guChen ? "孤辰" : "")\(guChen && guaSu ? "／" : "")\(guaSu ? "寡宿" : "")，婚缘宜晚、相处宜留空间。" : ""
        var dayRel = ""
        var bestW = 0
        for (i, p) in bazi.pillars.enumerated() where i != 2 {
            if let r = BaziTables.relationFull(p.last!, bazi.dayPillar.last!), r.1 > bestW {
                bestW = r.1
                dayRel = "\(["年", "月", "时"][i == 3 ? 2 : i])支\(p.last!)与日支\(r.0)"
            }
        }
        let bSig = "配偶星\(spouse)个，\(root ? "有根" : "无根")；日支\(bazi.dayPillar.last!)\(dayRel.isEmpty ? "" : "（\(dayRel)）")；孤辰／寡宿\(guChen || guaSu ? "见" : "不见")"
        let zSig = "夫妻坐\(starLine(fuP))；红鸾／天喜\(hong ? "见" : "不见")；化忌\(jiFu.isEmpty ? "无" : "在夫妻宫")"
        if spouse >= 1 && root && jiFu.isEmpty {
            return Verdict(title: "婚姻", bazi: bSig, ziwei: zSig,
                verdict: "同频相催：婚缘顺（早婚倾向）。八字配偶星有根、紫微夫妻宫无化忌，两术都指向婚缘信号清晰——遇到对的人推进即可，不必自我怀疑。\(guNote)",
                kind: .tongPin)
        }
        if spouse == 0 && !jiFu.isEmpty {
            return Verdict(title: "婚姻", bazi: bSig, ziwei: zSig,
                verdict: "同频相催：晚婚／慎婚（晚婚倾向）。八字配偶星不入原局、紫微化忌在夫妻宫，两术都提示婚缘须等——晚一点反而稳，定性比开始更重要。\(guNote)",
                kind: .tongPin)
        }
        if spouse >= 1 && root && !jiFu.isEmpty {
            return Verdict(title: "婚姻", bazi: bSig, ziwei: zSig,
                verdict: "分期应验：底子在、应期须等（底子早、应期晚）。八字配偶星有根（底子不差），紫微化忌在夫妻宫（当前婚缘有反复）——婚缘分两期：底子按八字看，应期须等运年引动（应期口径见解盘婚姻感情）。\(guNote)",
                kind: .fenQi)
        }
        return Verdict(title: "婚姻", bazi: bSig, ziwei: zSig,
            verdict: "互补制化：以八字定婚缘的底子、以紫微定婚缘的场景。八字配偶星\(spouse)个\(root ? "有根" : "无根")；紫微夫妻宫\(jiFu.isEmpty ? "无化忌" : "化忌在夫妻宫，须防反复")——底子按八字看，场景按紫微防。\(guNote)",
            kind: .huBu)
    }

    // MARK: - 健康
    private static func health(bazi: BaziChart, ziwei: ZiweiChart) -> Verdict {
        let pct = bazi.wuxingPercents
        let weakest = pct.indices.min(by: { pct[$0] < pct[$1] })!
        let weakestWx = wxN[weakest]
        let organ = ["木": "肝胆、筋与眼睛", "火": "心与血脉", "土": "脾胃", "金": "肺与呼吸道", "水": "肾与泌尿"][weakestWx]!
        let weakFlag = pct[weakest] < 15
        let jiP = palace(ziwei, "疾厄")
        let shaStars: Set<String> = ["擎羊", "陀罗", "火星", "铃星", "地空", "地劫"]
        let shaHit = (jiP.majors + jiP.minors).map { $0.star }.filter { shaStars.contains($0) }
        let bSig = "最弱\(weakestWx)\(Int(pct[weakest].rounded()))%，\(organ)"
        let zSig = "疾厄坐\(starLine(jiP))；煞星\(shaHit.isEmpty ? "无" : shaHit.joined(separator: "、"))"
        if weakFlag == !shaHit.isEmpty {
            if weakFlag {
                return Verdict(title: "健康", bazi: bSig, ziwei: zSig,
                    verdict: "同频相催：\(weakestWx)行最弱（\(Int(pct[weakest].rounded()))%），\(organ)一线是相对薄弱处；紫微疾厄宫见\(shaHit.joined(separator: "、"))——两术都提示此处须防，保养重点放这里，作息与体检提前安排。（非西医疾病诊断）",
                    kind: .tongPin)
            }
            return Verdict(title: "健康", bazi: bSig, ziwei: zSig,
                verdict: "同频相催：八字五行分布均衡（最弱\(weakestWx)\(Int(pct[weakest].rounded()))%）、紫微疾厄宫无煞星——两术都提示平稳，按平常节奏保养即可。（非西医疾病诊断）",
                kind: .tongPin)
        }
        return Verdict(title: "健康", bazi: bSig, ziwei: zSig,
            verdict: "互补制化：以八字定薄弱部位、以紫微定提醒强度。八字最弱\(weakestWx)（\(Int(pct[weakest].rounded()))%），\(organ)一线须留意；紫微疾厄宫\(shaHit.isEmpty ? "无煞星，提醒降一档" : "见\(shaHit.joined(separator: "、"))，提醒加一档")。（非西医疾病诊断）",
            kind: .huBu)
    }
}

/// 双术合参卡片（八字＋紫微交叉印证，四维同频／分歧一览）
struct CrossCheckCard: View {
    let bazi: BaziChart
    let ziwei: ZiweiChart

    var body: some View {
        let vs = BaziZiweiCrossEngine.verdicts(bazi: bazi, ziwei: ziwei)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Ky.cinnabar)
                Text("双术合参 · 交叉印证").font(.headline)
                Spacer()
                Text("八字定大势 · 紫微定场景").font(.caption2).foregroundStyle(Ky.sub)
            }
            ForEach(vs, id: \.title) { v in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(v.title).font(.subheadline).fontWeight(.semibold)
                        Text(v.kind.rawValue)
                            .font(.caption2).fontWeight(.bold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(kindColor(v.kind).opacity(0.15))
                            .foregroundStyle(kindColor(v.kind))
                            .clipShape(Capsule())
                        Spacer()
                    }
                    Text(v.verdict).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Text("八字：\(v.bazi)").font(.caption).foregroundStyle(Ky.sub).fixedSize(horizontal: false, vertical: true)
                    Text("紫微：\(v.ziwei)").font(.caption).foregroundStyle(Ky.sub).fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Ky.card)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text("裁决规则：同频相催→两术同向，结论加一档；互补制化→以八字大势定方向、紫微场景定节奏与提醒；分期应验→底子与应期分两期，不强行调和。健康只给部位与代谢倾向，不作西医疾病诊断。")
                .font(.caption2).foregroundStyle(Ky.sub).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Ky.card.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func kindColor(_ k: BaziZiweiCrossEngine.Kind) -> Color {
        switch k { case .tongPin: return Color.green; case .huBu: return Color.orange; case .fenQi: return Color.blue }
    }
}
