// 解盘 · 初断（规则层）：排盘之后的第一层解读，全部结论走依据链（结论←规则←盘面事实）。
// 定位写死：这是结构化初断——命局风景/月令格局候选/扶抑调候喜忌/十神分布/岁运要点；
// 工作室级的直断逐年（回测校准过的那套）仍以正式报告为准，App 内不冒充。
import SwiftUI
import AVFoundation

struct InterpretItem {
    let title: String
    let conclusion: String
    let links: [(label: String, text: String)]
}

/// 解盘验真打标：每条断语一键标「已应验／待回验」，沉淀个人准确率；随备份导出。
enum VerifyStore {
    private static let key = "kanyu.verifyMarks.v1"
    static func mark(for title: String) -> Bool? {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Bool])?[title]
    }
    static func set(_ title: String, _ value: Bool) {
        var d = (UserDefaults.standard.dictionary(forKey: key) as? [String: Bool]) ?? [:]
        d[title] = value
        UserDefaults.standard.set(d, forKey: key)
    }
    static func verifiedCount(titles: [String]) -> Int {
        titles.filter { mark(for: $0) == true }.count
    }
    static func pendingCount(titles: [String]) -> Int {
        titles.filter { mark(for: $0) == false }.count
    }
    /// 个人准确率：已应验 /（已应验＋待回验）；未打标时为 nil
    static func accuracy(titles: [String]) -> Double? {
        let v = verifiedCount(titles: titles)
        let p = pendingCount(titles: titles)
        guard v + p > 0 else { return nil }
        return Double(v) / Double(v + p)
    }
}

enum InterpretEngine {
    private static let wxNames = ["木", "火", "土", "金", "水"]
    private static func wxIndex(of stem: Character) -> Int {
        switch stem { case "甲", "乙": return 0; case "丙", "丁": return 1
        case "戊", "己": return 2; case "庚", "辛": return 3; default: return 4 }
    }

    // 扶抑分档（喜忌条、C8、预测单的唯一来源）：同党＝日主行＋印行
    static func fuYi(chart ch: BaziChart) -> (level: String, shengWo: Int, tongDang: Double) {
        let dayWx = wxIndex(of: ch.rizhu.first!)
        let shengWo = (dayWx + 4) % 5  // 生我者：木←水 火←木 土←火 金←土 水←金
        let tongDang = ch.wuxingPercents[dayWx] + ch.wuxingPercents[shengWo]
        let level = tongDang >= 55 ? "偏强" : (tongDang <= 40 ? "偏弱" : "中和")
        return (level, shengWo, tongDang)
    }

    // 调候喜用元素（按提及顺序）：穷通精选查表命中则取表述所指五行，否则寒月[火]、热月[水]
    static func tiaoHouWx(chart ch: BaziChart) -> [Int] {
        let dayStem = ch.rizhu.first!
        let monthBranch = ch.monthPillar.last!
        if let hit = tiaoHouTable[dayStem]?[monthBranch] {
            var out: [Int] = []
            for c in hit where "甲乙丙丁戊己庚辛壬癸".contains(c) {
                let w = wxIndex(of: c)
                if !out.contains(w) { out.append(w) }
            }
            return out
        }
        if ["亥", "子", "丑"].contains(monthBranch) { return [1] }
        if ["巳", "午", "未"].contains(monthBranch) { return [4] }
        return []
    }

    /// 预测单喜忌（本工作室定论）：扶抑初判＋调候优先。
    /// 规则：调候喜用（查表＞寒热粗筛）直接入喜；扶抑喜用中与调候冲突者（寒月金水、热月火土）剔除；
    /// 扶抑忌用中被调候点名者、及调候喜用所生之行，不入忌；其余为中性（可用）。
    /// 例·周囿廷（己未日、子月、偏强）：调候[火木]、冲突[金水] → 喜[火木]、忌[金水]、中性[土]，与案例档定论一致。
    static func posterXiJi(chart ch: BaziChart) -> (xi: [Int], ji: [Int], neutral: [Int], level: String, tongDang: Double, tiaoHou: [Int]) {
        let dayWx = wxIndex(of: ch.rizhu.first!)
        let (level, shengWo, tongDang) = fuYi(chart: ch)
        let th = tiaoHouWx(chart: ch)
        if level == "中和" { return ([], [], [0, 1, 2, 3, 4], level, tongDang, th) }
        let monthBranch = ch.monthPillar.last!
        var conflict: Set<Int> = []
        if ["亥", "子", "丑"].contains(monthBranch) { conflict = [3, 4] }
        else if ["巳", "午", "未"].contains(monthBranch) { conflict = [1, 2] }
        conflict.subtract(th)
        let fuYiXi: Set<Int> = level == "偏强" ? [(dayWx + 1) % 5, (dayWx + 2) % 5, (dayWx + 3) % 5] : [shengWo, dayWx]
        let fuYiJi: Set<Int> = level == "偏强" ? [shengWo, dayWx] : [(dayWx + 1) % 5, (dayWx + 2) % 5, (dayWx + 3) % 5]
        let generated: Set<Int> = Set(th.map { ($0 + 1) % 5 })  // 生：木→火 火→土 土→金 金→水 水→木
        let xi = Set(th).union(fuYiXi.subtracting(conflict))
        let ji = conflict.union(fuYiJi.subtracting(th).subtracting(generated))
        let neutral = Set([0, 1, 2, 3, 4]).subtracting(xi).subtracting(ji)
        return (xi.sorted(), ji.sorted(), neutral.sorted(), level, tongDang, th)
    }

    /// 大运逐运喜忌（与预测单同口径：调候优先；中和盘标中性）
    static func dayunMark(chart ch: BaziChart, index i: Int) -> String {
        guard i < ch.dayunGanZhi.count else { return "中性" }
        let xj = posterXiJi(chart: ch)
        if xj.level == "中和" { return "中性" }
        let w = wxIndex(of: ch.dayunGanZhi[i].first!)
        if xj.xi.contains(w) { return "喜" }
        if xj.ji.contains(w) { return "忌" }
        return "中性"
    }

    /// 取解盘条目结论（按标题顺序回退），供海报与速览卡共用；调用方先算一次 interpret() 再传 items
    static func conclusion(items: [InterpretItem], titles: String...) -> String {
        for t in titles {
            if let c = items.first(where: { $0.title == t })?.conclusion, !c.isEmpty { return c }
        }
        return ""
    }

    // MARK: - 解盘三段式（build-95）
    /// 核心总纲 5 条不参与三段（本身已是总纲层）；三段只用于 23 维
    static let coreTitles: Set<String> = ["命局风景", "月令格局（候选）", "喜忌（扶抑初判）", "十神分布", "岁运要点"]
    /// 每维的关键行：财→财星、官→官星、印→印星、食伤→食伤、日主→比劫；喜用类维取喜用首行
    static func keyWxIndex(chart ch: BaziChart, title: String) -> Int {
        let dayWx = wxIndex(of: ch.rizhu.first!)
        let xiFirst = posterXiJi(chart: ch).xi.first
        switch title {
        case "学业文书", "父母缘分", "置业田宅", "贵人与人际", "六亲情境深读", "中老年守年":
            return (dayWx + 4) % 5  // 印
        case "事业方向", "工作形态", "名声声誉":
            return (dayWx + 3) % 5  // 官
        case "财运形态", "财富量级蓄水池":
            return (dayWx + 2) % 5  // 财
        case "婚姻感情":
            return ch.gender == "M" ? (dayWx + 2) % 5 : (dayWx + 3) % 5  // 男财女官
        case "子女缘分":
            return ch.gender == "M" ? (dayWx + 3) % 5 : (dayWx + 1) % 5  // 男官女食伤
        case "出行迁移", "晚年光景":
            return (dayWx + 1) % 5  // 食伤
        case "幸运颜色与数字", "适合方位", "行业赛道深断":
            return xiFirst ?? dayWx  // 喜用首行；中和盘回落日主
        default:
            return dayWx  // 性格性情、兄弟姐妹、健康倾向、注意事项、如何化解等：日主（比劫）
        }
    }
    /// 现行大运下标（今年所在运；未起运取 0，超出取末运）
    static func currentDayunIndex(chart ch: BaziChart) -> Int {
        if ch.dayunGanZhi.isEmpty { return 0 }
        let nowYear = Calendar.current.component(.year, from: Date())
        var di = 0
        for i in ch.dayunGanZhi.indices where ch.dayunStartYear(i) <= nowYear { di = i }
        return di
    }
    /// 【岁运引动】句：现行大运干支＋十神＋喜忌标，＋未来三步运里关键行当令情况（运干或运支本气为该行）
    static func yunHint(chart ch: BaziChart, title: String) -> String {
        if ch.dayunGanZhi.isEmpty { return "未起运：岁运引动待起运后看。" }
        let wxN = ["木", "火", "土", "金", "水"]
        let keyWx = keyWxIndex(chart: ch, title: title)
        let ci = currentDayunIndex(chart: ch)
        let gz = ch.dayunGanZhi[ci]
        let start = ch.dayunStartYear(ci)
        let ss = BaziTables.shiShen(day: ch.rizhu.first!, stem: gz.first!)
        let mark = dayunMark(chart: ch, index: ci)
        let markText = mark == "喜" ? "调候喜用" : (mark == "忌" ? "调候所忌" : "中性")
        var hits: [String] = []
        if ci + 1 < ch.dayunGanZhi.count {
            for j in (ci + 1)...min(ci + 3, ch.dayunGanZhi.count - 1) {
                let gj = ch.dayunGanZhi[j]
                let stemWx = wxIndex(of: gj.first!)
                let branchBen = BaziTables.cangGan[gj.last!]!.first!
                let branchWx = wxIndex(of: branchBen)
                if stemWx == keyWx || branchWx == keyWx {
                    hits.append("\(gj)运（\(ch.dayunStartYear(j))–\(ch.dayunStartYear(j) + 9)）\(dayunMark(chart: ch, index: j))")
                }
            }
        }
        let hitText = hits.isEmpty
            ? "未来三步运里\(wxN[keyWx])行未直接当令，靠流年引动"
            : "未来三步运里\(wxN[keyWx])行当令的有：\(hits.joined(separator: "、"))"
        return "现行\(gz)运（\(start)–\(start + 9)），运干\(gz.first!)为\(ss)，\(markText)。\(hitText)。"
    }
    /// 【现实避坑指南】：风险类维取「如何化解（破局调理）」，其余取「注意事项」（均为引擎已有结论，不另编）
    static func guideHint(items: [InterpretItem], title: String) -> String {
        if title == "注意事项" { return conclusion(items: items, titles: "如何化解（破局调理）") }
        if title == "如何化解（破局调理）" { return conclusion(items: items, titles: "注意事项") }
        let riskTitles: Set<String> = ["财运形态", "婚姻感情", "子女缘分", "健康倾向", "工作形态", "事业方向", "置业田宅", "中老年守年", "晚年光景", "兄弟姐妹"]
        if riskTitles.contains(title) {
            return conclusion(items: items, titles: "如何化解（破局调理）")
        }
        return conclusion(items: items, titles: "注意事项")
    }
    /// 未来三年流年直断（海报七节与速览卡共用）：逐年干支＋流年干支十神＋所在大运喜忌＋流年支与原局最强牵动＋行事指南
    static func nextThreeYears(chart ch: BaziChart) -> [(year: Int, ganzhi: String, stemSS: String, branchSS: String, mark: String, note: String)] {
        let nowYear = Calendar.current.component(.year, from: Date())
        let day = ch.rizhu.first!
        return (0..<3).map { k in
            let y = nowYear + k
            let gz = BaziChart.yearGanZhi(y)
            let stemSS = BaziTables.shiShen(day: day, stem: gz.first!)
            let branchSS = BaziTables.shiShen(day: day, stem: BaziTables.cangGan[gz.last!]!.first!)
            let di = ch.dayunGanZhi.isEmpty ? 0 : max(0, min(ch.dayunGanZhi.count - 1, (y - ch.qiyunYear) / 10))
            let mark = ch.dayunGanZhi.isEmpty ? "中性" : dayunMark(chart: ch, index: di)
            let yb = gz.last!
            var best = 0; var bestName = ""; var bestPillar = ""
            for p in ch.pillars {
                if let r = BaziTables.relationFull(p.last!, yb), r.1 > best { best = r.1; bestName = r.0; bestPillar = p }
            }
            let rel = best > 0 ? "流年\(yb)与原局\(bestPillar)支\(bestName)" : "与原局四支无刑冲合会牵动"
            let guide = mark == "喜" ? "喜用当令，宜进取" : (mark == "忌" ? "忌神当道，宜守成" : "平运可用，宜稳进")
            let note = "流年干\(stemSS)、支\(branchSS)；\(rel)；\(mark)（\(guide)）"
            return (y, gz, stemSS, branchSS, mark, note)
        }
    }
    // 穷通调候精选查表（2026-10-31 批次二）：只收有把握的寒月／热月格子，共 19 格；
    // 未入表的格子一律回落寒热粗筛并标注层级，不许凭记忆补填。表述为通说要点，非原文照录。
    private static let tiaoHouTable: [Character: [Character: String]] = [
        "甲": ["寅": "先丙后癸", "子": "丙火解冻为先，癸水滋润次之"],
        "乙": ["子": "丙火解冻为先"],
        "丙": ["午": "壬水为先，庚金发源次之"],
        "丁": ["子": "甲木为先，庚金次之", "亥": "甲木为先，庚金次之", "午": "壬水为先，庚金次之"],
        "戊": ["子": "丙火为先，甲木次之", "亥": "丙火为先，甲木次之"],
        "己": ["子": "丙火为先，甲木次之", "亥": "丙火为先，甲木次之"],
        "庚": ["巳": "壬水为先", "子": "丁火为先，甲木次之"],
        "辛": ["子": "丙火为先，壬水次之", "午": "壬水为先，己土次之"],
        "壬": ["子": "丙火为先，戊土次之", "亥": "丙火为先，戊土次之"],
        "癸": ["子": "丙火解冻为先", "午": "庚金发源为先"],
    ]

    // C2 格局成败核查（2026-11-07，学习日志第 49 轮回灌）：
    // 来源：《子平正法》之十六〈论用神格局成败救应〉（后学陈氏，新浪博客，现代博客对《子平真诠》〈论用神成败救应〉的逐格展开，非典籍原文）。
    // 只查十神见否（透干＋藏干）；合、冲、刑与身旺量级未入本查，未见忌字不等于全格无破。
    // 输出三档：格有成象／成中有败／有败有救，并点名在局的忌字与救字。
    private static func chengBaiCheck(chart ch: BaziChart, benQiSS: String) -> String {
        let posNames = ["年", "月", "日", "时"]
        func whereIs(_ ss: String) -> String {
            if let i = ch.stemShiShen.firstIndex(of: ss) {
                return "透于\(posNames[i])干"
            }
            for i in 0..<4 {
                if let j = ch.hideShiShen[i].firstIndex(of: ss) {
                    return "藏于\(posNames[i])支\(ch.hideGan[i][j])"
                }
            }
            return "在局"
        }
        func present(_ ss: String) -> Bool {
            return ch.stemShiShen.contains(ss) || ch.hideShiShen.flatMap { $0 }.contains(ss)
        }
        func found(_ names: [String]) -> [String] {
            return names.filter { present($0) }
        }
        func describe(_ names: [String]) -> String {
            return names.map { "\($0)（\(whereIs($0))）" }.joined(separator: "、")
        }
        // 伤官格：忌形态为「生财带煞」（财与煞同现）；救形态「生财透杀而杀逢合」涉及合化，本查不判定
        if benQiSS == "伤官" {
            let cai = found(["正财", "偏财"])
            let sha = found(["七杀"])
            if cai.isEmpty || sha.isEmpty {
                return "格有成象：本查常见形态内未见「生财带煞」（财与七杀须同现才计忌）。"
            }
            return "成中有败：生财带煞——\(describe(cai))与\(describe(sha))同现；救形态「生财透杀而杀逢合」涉及合化，本查不判定。"
        }
        // 羊刃格：忌形态为「无官煞」与「透官被伤」；救为重印护官杀；「透杀被合」涉及合化，本查不判定
        if benQiSS == "劫财" {
            let guan = found(["正官"])
            let sha = found(["七杀"])
            let shang = found(["伤官"])
            let yin = found(["正印", "偏印"])
            if guan.isEmpty && sha.isEmpty {
                return "成中有败：刃格无官煞（正官、七杀皆未在局）；救形态「重印护官杀」须先有官杀可护，本查未见救字。"
            }
            if !guan.isEmpty && !shang.isEmpty {
                if yin.isEmpty {
                    return "成中有败：透官被伤——\(describe(shang))坏官，未见印星护官。"
                }
                return "有败有救：透官被伤——\(describe(shang))坏官，\(describe(yin))在局可护官。"
            }
            return "格有成象：官杀在局，本查常见形态内未见「透官被伤」；「透杀被合」涉及合化，本查不判定。"
        }
        // 建禄格：忌形态为「无财官透煞印」；救形态「伤被合／煞被合」涉及合化，本查不判定
        if benQiSS == "比肩" {
            let caiGuan = found(["正财", "偏财", "正官"])
            let shaYin = found(["七杀", "正印", "偏印"])
            if caiGuan.isEmpty && !shaYin.isEmpty {
                return "成中有败：无财官而透煞印——\(describe(shaYin))在局；救形态「用官遇伤而伤被合／用财带煞而煞被合」涉及合化，本查不判定。"
            }
            return "格有成象：本查常见形态内未见「无财官透煞印」。"
        }
        // 其余七格：按附录逐格忌／救表查十神见否
        let table: [String: (ji: [String], jiu: [String])] = [
            "正官": (["伤官"], ["正印", "偏印"]),
            "正财": (["比肩", "劫财", "七杀"], ["食神", "伤官", "正官"]),
            "偏财": (["比肩", "劫财", "七杀"], ["食神", "伤官", "正官"]),
            "正印": (["正财", "偏财"], ["比肩", "劫财"]),
            "偏印": (["正财", "偏财"], ["比肩", "劫财"]),
            "食神": (["偏印"], ["七杀"]),
            "七杀": (["正财", "偏财", "正印", "偏印"], ["食神", "伤官"]),
        ]
        guard let entry = table[benQiSS] else {
            return "本查未覆盖该格。"
        }
        let jiFound = found(entry.ji)
        let jiuFound = found(entry.jiu)
        if jiFound.isEmpty {
            return "格有成象：本查常见形态内未见忌字。"
        }
        if jiuFound.isEmpty {
            return "成中有败：忌字\(describe(jiFound))在局坏格，未见救字。"
        }
        if benQiSS == "食神" {
            return "有败有救：忌字\(describe(jiFound))在局，\(describe(jiuFound))在局可就杀成格（格转煞格，另按煞格看）。"
        }
        return "有败有救：忌字\(describe(jiFound))在局，救字\(describe(jiuFound))在局。"
    }

    static func interpret(chart ch: BaziChart) -> [InterpretItem] {
        var items: [InterpretItem] = []
        let pct = ch.wuxingPercents
        let dayStem = ch.rizhu.first!
        let dayWx = wxIndex(of: dayStem)
        // 1 命局风景（五行分布直读）
        let order = pct.indices.sorted { pct[$0] > pct[$1] }
        let strong = order.first!; let weak = order.last!
        // C7 气势通关（近似口径：两行占比均 ≥20% 判相战，通关行看干支有无该行之干；只做金木、水火两组典型）
        var tongGuan = ""
        let allStems = ch.pillars.map { String($0.first!) } + ch.hideGan.flatMap { $0 }
        if pct[3] >= 20 && pct[0] >= 20 {
            tongGuan = allStems.contains { ["壬", "癸"].contains($0) } ? "金木相战而水在局中通关（金生水、水生木），气尚流通。" : "金木相战而局中无水通关，纠结在金与木两气之间。"
        }
        if pct[4] >= 20 && pct[1] >= 20 {
            tongGuan += allStems.contains { ["甲", "乙"].contains($0) } ? "水火相战而木在局中通关（水生木、木生火），气尚流通。" : "水火相战而局中无木通关，纠结在水与火两气之间。"
        }
        items.append(InterpretItem(
            title: "命局风景",
            conclusion: "五行里\(wxNames[strong])最重（\(Int(pct[strong].rounded()))%）、\(wxNames[weak])最轻（\(Int(pct[weak].rounded()))%）；日主\(ch.rizhu)属\(wxNames[dayWx])，力量排第 \(order.firstIndex(of: dayWx)! + 1)。\(tongGuan)",
            links: [("盘面", "五行占比 木\(Int(pct[0].rounded())) 火\(Int(pct[1].rounded())) 土\(Int(pct[2].rounded())) 金\(Int(pct[3].rounded())) 水\(Int(pct[4].rounded()))"),
                    ("口径", "占比为盘面计法（天干＋藏干加权），只说明分布，不直接等于强弱结论；气势通关为本应用近似口径（两行占比均 ≥20% 判相战），出《滴天髓》气势与通关")]))
        // 2 月令格局候选（本气十神，透干校验）
        let monthBranch = ch.monthPillar.last!
        let benQi = BaziTables.cangGan[monthBranch]!.first!
        let benQiSS = BaziTables.shiShen(day: dayStem, stem: benQi)
        let touIdx = ch.stemShiShen.firstIndex(of: benQiSS)
        let geName = benQiSS == "比肩" ? "建禄格" : (benQiSS == "劫财" ? "羊刃格" : "\(benQiSS)格")
        let chengBai = chengBaiCheck(chart: ch, benQiSS: benQiSS)
        items.append(InterpretItem(
            title: "月令格局（候选）",
            conclusion: "月令\(monthBranch)本气\(benQi)对日主为\(benQiSS)，先按\(geName)候选看。\(touIdx != nil ? "本气已透于\(["年", "月", "日", "时"][touIdx!])干，格象较明。" : "本气未透干，格象要结合透藏与岁运再定，此处只作候选。")成败核查：\(chengBai)",
            links: [("盘面", "月柱 \(ch.monthPillar)，本气 \(benQi)（\(benQiSS)）；四柱透干查 \(touIdx != nil ? "见透" : "未透")"),
                    ("法则", "《子平真诠》：格以月令本气为纲，透干则格明；月令为比劫不立十神格，取建禄／羊刃"),
                    ("成败核查", "《子平正法》之十六成败救应四态核查清单（现代博客展开，非典籍原文）；只查十神见否（透干＋藏干），合／冲／刑与身旺量级未入本查，未见忌字不等于全格无破")]))
        // 3 扶抑＋调候喜忌（初判）
        let (level, shengWo, tongDang) = fuYi(chart: ch)
        let xiText: String
        switch level {
        case "偏强": xiText = "扶抑上喜克、泄、耗——\(wxNames[(dayWx + 1) % 5])（食伤）\(wxNames[(dayWx + 2) % 5])（财）\(wxNames[(dayWx + 3) % 5])（官杀）方向可用，忌再添\(wxNames[shengWo])\(wxNames[dayWx])。"
        case "偏弱": xiText = "扶抑上喜生扶——\(wxNames[shengWo])（印）与\(wxNames[dayWx])（比劫）为援，忌克泄耗再压。"
        default: xiText = "同党异党接近，贵在流通：哪一行堵住就疏哪一行，不预设固定喜忌。"
        }
        var tiaoHou = ""
        var tiaoHouLevel = "调候未入精选查表（本盘日主×月支不在 19 格内），以下只作寒热粗筛"
        if let hit = tiaoHouTable[dayStem]?[monthBranch] {
            tiaoHou = "调候查表（《穷通宝鉴》通说）：\(dayStem)日主生于\(monthBranch)月，\(hit)。"
            tiaoHouLevel = "调候查表已命中（《穷通宝鉴》通说精选格，层级：典籍）；查表只覆盖 19 格，未入表者回落粗筛"
        } else if ["亥", "子", "丑"].contains(monthBranch) { tiaoHou = "生于寒月，寒热大方向上另喜火暖局（这是穷通调候的粗筛，层级：粗筛，未入精选查表）。" }
        else if ["巳", "午", "未"].contains(monthBranch) { tiaoHou = "生于热月，寒热大方向上另喜水润局（这是穷通调候的粗筛，层级：粗筛，未入精选查表）。" }
        else { tiaoHouLevel = "调候未入精选查表，且非寒月／热月，粗筛亦无寒热方向可标" }
        var special = ""
        if let m = pct.max(), m >= 55 {
            special = " 注意：\(wxNames[pct.firstIndex(of: m)!])一行独旺（\(Int(m.rounded()))%），疑似专旺／从势候选盘——这类盘的喜忌要顺气势另断，上面的扶抑口径只作参考，不要照单全收。"
        }
        items.append(InterpretItem(
            title: "喜忌（扶抑初判）",
            conclusion: "日主\(level)：同党（\(wxNames[dayWx])＋印\(wxNames[shengWo])）约占 \(Int(tongDang.rounded()))%。\(xiText)\(tiaoHou)\(special)",
            links: [("盘面", "日主 \(ch.rizhu)（\(wxNames[dayWx])），月令 \(monthBranch)"),
                    ("法则", "扶抑取用为初判框架（出徐乐吾演绎，只作参照）；强弱分档线（同党 ≥55% 偏强、≤40% 偏弱）为本应用计法，非典籍原有分界；调候优先于扶抑，冲突时以调候为先"),
                    ("调候", tiaoHouLevel)]))
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
            var topText = top.2
            let yinC = (counts["正印"] ?? 0) + (counts["偏印"] ?? 0)
            let shiC = (counts["食神"] ?? 0) + (counts["伤官"] ?? 0)
            let biC = (counts["比肩"] ?? 0) + (counts["劫财"] ?? 0)
            let touS = Set(ch.stemShiShen)
            if top.0 == "食伤" && yinC >= 2 && (touS.contains("正印") || touS.contains("偏印")) {
                topText = "食伤成势而印星透干制化：表达与手艺是本钱，但性子被印收着——外表守规矩、内里有主见（伤官配印式），不按伤官裸奔的「不服管」读。"
            } else if top.0 == "官杀" && shiC >= 2 && (touS.contains("食神") || touS.contains("伤官")) {
                topText = "官杀成势而食伤透干制化：压力是常态，但有技术与表达作出口，属化压为能，不是纯挨压。"
            } else if top.0 == "财星" && biC >= 2 && (touS.contains("比肩") || touS.contains("劫财")) {
                topText = "财星成势而比劫透干同在：对资源与结果敏感，但钱容易经同辈与合伙之手进出，财权要握在自己手里。"
            }
            items.append(InterpretItem(
                title: "十神看点",
                conclusion: topText,
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
        if chongPairs[dayBranch] == lnBranch { relText = "流年\(lnBranch)冲日支\(dayBranch)：先动自身——身体、迁居、行程一线先有动象，其次才及亲密关系；宜主动求变、忌被动挨冲。" }
        if hePairs[dayBranch] == lnBranch { relText = "流年\(lnBranch)合日支\(dayBranch)：牵合之象，多应关系靠近、意向达成；是否落到缔约，还要看流年干与大运是否同推。" }
        // C8 大运逐运喜忌标记（运干五行，扶抑初判叠加调候优先，与喜忌条同口径；中和盘标中性）
        let yunMarks = ch.dayunGanZhi.indices.map { i -> String in
            let gz = ch.dayunGanZhi[i]
            let ss = BaziTables.shiShen(day: dayStem, stem: gz.first!)
            let mark = dayunMark(chart: ch, index: i)
            return "\(gz)（\(ch.dayunStartYear(i))起，运干\(ss)，喜忌\(mark)）"
        }.joined(separator: "、")
        items.append(InterpretItem(
            title: "岁运要点",
            conclusion: "\(yunText) \(nowYear) 年流年\(ln)：\(relText)逐运喜忌（调候优先）：\(yunMarks)。",
            links: [("盘面", yunFacts), ("法则", "应期看引动：冲合落到哪一宫，哪一线的事先动；逐运标记看运干五行：扶抑初判叠加调候优先（寒月去金水、热月去火土），中和盘标中性，不升格为定论")]))
        return items + dimensions(ch)
    }
}

// MARK: - 术语释义气泡（build-95：点十神／长生／核心术语弹出白话释义；释义取自本系统知识库表达层，不另编断语）
enum TermGlossary {
    static let texts: [String: String] = [
        // 十神（十种关系语言，见 knowledge/类象表.md「十神五关系一句话」）
        "正官": "克我的力量里最讲规矩的一种：责任、名声、体制内的位置。得位得用为贵，不得制为压。",
        "七杀": "克我最烈的一种：压力、挑战、魄力。化之为权，不化为压；有制化才可用。",
        "正印": "生我的力量：学习、庇护、长辈、证照、靠山。印旺主稳，印弱主靠自己。",
        "偏印": "生我但偏一路：偏门才智、谋略、冷门学问；也主孤僻、想得多。",
        "比肩": "与我同类的力量：自己、同辈、朋友。帮身也分财，合作先分账。",
        "劫财": "与我同类但偏争的一路：争财夺利的同辈，钱经同辈之手进出时要先立规矩。",
        "食神": "我生的温和输出：才华、表达、福气、口福。主顺、主享受、主把本事变现。",
        "伤官": "我生的锋利输出：主见、才华、不服管。见印收敛成内秀，无制则锋芒外露。",
        "正财": "我克的正财：正业收入、稳定可控的钱。财要身能任，任不起反为累。",
        "偏财": "我克的偏财：流动的钱、机会与投机。来得快去得也快，看得懂才取。",
        "日主": "我，日干。整张盘以日主为中心：其余干支按生克关系定十神，再论强弱喜忌。",
        // 长生十二宫（只作日主根气辅助参量，不单独断事；见 knowledge/长生十二宫.md）
        "长生": "十二宫之首：日主刚得生气，根气初萌。只作根气强弱的参考，不单独断事。",
        "沐浴": "气渐盛而未稳，像刚出浴——易动摇，须防桃花与反复。",
        "冠带": "气渐成：宜立业、宜穿戴整齐见人，凡事讲体面。",
        "临官": "气正旺，如官临任：得禄、有位置，是日主最得力的状态之一。",
        "帝旺": "气最旺：盛极。旺到顶反而要防过头，须有泄有制才稳。",
        "衰": "气渐退：由旺转弱，宜收不宜扩。",
        "病": "气弱：根气不足，宜养不宜争。",
        "死": "气尽：根气断档，须靠岁运补救。",
        "墓": "气入库收藏：收而不发，待冲开才动。",
        "绝": "气断：根气全无，须靠岁运引动。",
        "胎": "气初孕：新气在孕育，未成形，宜等。",
        "养": "气受养：渐长渐养，宜积累。",
        // 核心术语
        "喜用神": "让命局平衡的关键力量（扶正）。喜用不是吉凶判决，是「加水让咖啡顺口」的那个动作。",
        "忌神": "让命局更失衡的力量，宜避、宜制、宜泄。",
        "调候": "先看月令寒暖燥湿取用：寒要暖、热要凉、燥要润、湿要燥。调候在格局之前。",
        "格局": "月令定格：以月令主星看命局的骨架（官、财、印、食神、七杀皆可为格）。",
        "身强身弱": "日主得不得令、得不得地、得不得势的称重，不是数票。强弱只为取用，不是结论。",
        "旬空": "旬中空亡的两支：力量落空，逢冲填实才动。",
        "大运": "十年一换的运程：每步十年，看运干支与原局的生克引动。",
        "流年": "一年一换的太岁：流年干支与原局、大运三层叠加看应期。",
        "纳音": "年柱干支的纳音五行，如覆灯火命、长流水命。是年命的别名，不参与生克取用。",
        "胎元": "受胎之月所落之柱：先天禀赋的底色。",
        "命宫": "命主之宫：命盘的落点，随盘输出。",
        "身宫": "身主之宫：身体与晚运的落点，随盘输出。",
        "神煞": "吉凶神煞（如天乙、文昌、桃花）：只作参考，先格局后神煞。",
        "三合": "三支成局：申子辰合水、亥卯未合木、寅午戌合火、巳酉丑合金；中神不在，局不成。",
        "六合": "两支相合：子丑、寅亥、卯戌、辰酉、巳申、午未；合中有生有克，非全吉。",
        "六冲": "两支相冲：子午、丑未、寅申、卯酉、辰戌、巳亥；冲是克的动态，主变动。",
        "相刑": "三刑：寅巳申、丑戌未、子卯（无礼），加辰午酉亥自刑；主上下不相合。",
        "穿害": "六害又称穿：子未、丑午、寅巳、卯辰、申亥、酉戌；主侵损阻抑。",
        "六破": "六破：子酉、丑辰、寅亥、卯午、巳申、未戌；主破散，破中有生有合。",
        "伏吟": "同字重现：干支伏吟主同类事反复、动象加倍。",
        "通关": "两气相战时，中间一行调和：如金木战而水通关。",
        "扶抑": "扶弱抑强：取用神的基本法，扶日主所弱、抑日主所强。"
    ]
    static func text(for term: String) -> String {
        texts[term] ?? "本术语暂无释义。"
    }
}

struct TermButton: View {
    let term: String
    let display: String
    @State private var show = false
    var body: some View {
        Button(display) { show = true }
            .buttonStyle(.plain)
            .popover(isPresented: $show) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(term).font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                    Text(TermGlossary.text(for: term)).font(.callout).foregroundStyle(Ky.ink)
                    Text("释义取自本系统知识库表达层（十神五关系／长生查法／刑冲合会表），不作断语。")
                        .font(.caption2).foregroundStyle(Ky.sub)
                }
                .padding(16)
                .frame(maxWidth: 320)
                .presentationCompactAdaptation(.popover)
            }
    }
}

struct InterpretView: View {
    let chart: BaziChart
    let name: String
    @StateObject private var speaker = Speaker()
    @State private var selectedCategory = 0
    @State private var searchQuery = ""
    @State private var showGlossary = false
    @State private var verifyTick = 0

    private static let categories: [(String, Set<String>)] = [
        ("全部", []),
        ("核心总纲", ["命局风景", "月令格局（候选）", "喜忌（扶抑初判）", "十神分布", "岁运要点"]),
        ("性格事业", ["性格底色", "事业方向", "工作形态", "学业与文凭", "学业文书", "财运形态", "置业田宅", "名声声誉", "行业赛道深断", "财富量级蓄水池"]),
        ("婚恋六亲", ["婚姻感情", "子女", "子女缘分", "父母缘分", "兄弟同辈", "兄弟姐妹", "贵人与人际", "出行迁移", "六亲情境深读"]),
        ("身心守年", ["健康倾向", "中老年守年", "晚年光景"]),
        ("破局调理", ["幸运颜色与数字", "适合方位", "注意事项", "如何化解（破局调理）"])
    ]

    private func categoryTag(for title: String) -> (String, Color) {
        for (idx, cat) in Self.categories.enumerated() where idx > 0 && cat.1.contains(title) {
            switch idx {
            case 1: return ("核心总纲", Ky.qingdai)
            case 2: return ("性格事业", Ky.gold)
            case 3: return ("婚恋六亲", Ky.cinnabar)
            case 4: return ("身心守年", Ky.jade)
            default: return ("破局调理", Ky.qingdai)
            }
        }
        return ("详批", Ky.qingdai)
    }

    var body: some View {
        let allItems = InterpretEngine.interpret(chart: chart)
        let filteredIndices = allItems.indices.filter { idx in
            let item = allItems[idx]
            let matchCat = selectedCategory == 0 || Self.categories[selectedCategory].1.contains(item.title)
            let matchQuery = searchQuery.isEmpty
                || item.title.localizedCaseInsensitiveContains(searchQuery)
                || item.conclusion.localizedCaseInsensitiveContains(searchQuery)
            return matchCat && matchQuery
        }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                // 顶部总控栏：分类胶囊＋全文听书＋搜索
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(name.isEmpty ? "本盘" : name) · 30 条五典详批 · \(accuracyLine(titles: allItems.map { $0.title }))")
                                .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                            Text("日主 \(chart.rizhu) · 四柱 \(chart.pillars.joined(separator: " ")) · 每条附盘面与典籍依据")
                                .font(.caption2).foregroundStyle(Ky.sub)
                        }
                        Spacer()
                        Button { showGlossary = true } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "book.fill")
                                Text("术语")
                            }
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(Ky.elevated)
                            .foregroundStyle(Ky.qingdai)
                            .clipShape(Capsule())
                        }.buttonStyle(.plain)
                        Button {
                            let textToRead = filteredIndices.map { "\(allItems[$0].title)。\(allItems[$0].conclusion)" }.joined(separator: "。")
                            speaker.read(textToRead)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: speaker.speaking ? "stop.circle.fill" : "speaker.wave.2.circle.fill")
                                Text(speaker.speaking ? "停止" : "听本组")
                            }
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(speaker.speaking ? Ky.cinnabar : Ky.qingdai)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }

                    // 分类速选胶囊条（解决 28 张卡片一字长蛇阵盲滑痛点）
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(Self.categories.indices, id: \.self) { cIdx in
                                let active = selectedCategory == cIdx
                                let count = cIdx == 0 ? allItems.count : Self.categories[cIdx].1.count
                                Button {
                                    withAnimation(.easeInOut(duration: 0.16)) { selectedCategory = cIdx }
                                } label: {
                                    Text("\(Self.categories[cIdx].0) \(count)")
                                        .font(.caption).fontWeight(active ? .bold : .medium)
                                        .padding(.horizontal, 11).padding(.vertical, 6)
                                        .background(active ? Ky.qingdai : Ky.elevated)
                                        .foregroundStyle(active ? Color.white : Ky.ink)
                                        .clipShape(Capsule())
                                }.buttonStyle(.plain)
                            }
                        }
                    }

                    // 页内快速检索
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(Ky.sub)
                        TextField("搜维度或关键词（如：调候、财库、婚姻、甲减、守年）", text: $searchQuery)
                            .font(.caption)
                        if !searchQuery.isEmpty {
                            Button { searchQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(Ky.sub)
                            }
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Ky.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }.kyCard()

                if filteredIndices.isEmpty {
                    Text("没有匹配的解盘维度，请切换上方分类或清空搜索词。")
                        .font(.callout).foregroundStyle(Ky.sub)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                } else {
                    ForEach(filteredIndices, id: \.self) { i in
                        let tag = categoryTag(for: allItems[i].title)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text(String(format: "%02d", i + 1))
                                    .font(KyV2.tabular(11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 22)
                                    .background(tag.1)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text(allItems[i].title)
                                    .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                                KyBadge(text: tag.0, color: tag.1)
                                Spacer()
                                Button {
                                    speaker.read("\(allItems[i].title)。\(allItems[i].conclusion)")
                                } label: {
                                    Image(systemName: "speaker.wave.2")
                                        .font(.caption)
                                        .foregroundStyle(Ky.qingdai)
                                        .padding(6)
                                        .background(Ky.elevated)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("朗读\(allItems[i].title)")
                            }
                            if !InterpretEngine.coreTitles.contains(allItems[i].title) {
                                Text("【原局底牌】").font(.caption2).fontWeight(.bold).foregroundStyle(Ky.qingdai)
                            }
                            EvidenceChainView(conclusion: allItems[i].conclusion, links: allItems[i].links)
                            if !InterpretEngine.coreTitles.contains(allItems[i].title) {
                                threePartRows(chart: chart, item: allItems[i], allItems: allItems)
                            }
                            verificationFooter(item: allItems[i])
                        }
                        .kyCard()
                    }
                }

                Text("解盘纪律说明：以上 30 条（5 条总纲＋25 维）全部由本机确定性排盘数据推导，每条结论附「盘面事实＋典籍根据」可复核；健康只给部位与代谢倾向不落病名；守年只列强引动关口级年份。回测校准级的私人详批以工作室正式报告为准。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16).padding(.bottom, 100)
        }
        .background(Ky.bg)
        .onDisappear { speaker.stop() }
        .navigationTitle(name.isEmpty ? "30 条五典解盘" : "解盘 · \(name)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGlossary) { glossarySheet }
    }

    /// 个人准确率行（已应验／待回验／命中率；未打标时不显示命中率）
    private func accuracyLine(titles: [String]) -> String {
        let v = VerifyStore.verifiedCount(titles: titles)
        let p = VerifyStore.pendingCount(titles: titles)
        if let a = VerifyStore.accuracy(titles: titles) {
            return "已应验 \(v) 条 · 待回验 \(p) 条 · 命中率 \(Int((a * 100).rounded()))%"
        }
        return "已应验 \(v) 条 · 待回验 \(p) 条"
    }
    /// 验真依据链（实算值：前后交节时刻＋真太阳时校正量＋经度；节气据天文历算）
    private var verifyChain: String {
        let prev = chart.prevJieQiText.isEmpty ? "—" : chart.prevJieQiText
        let next = chart.nextJieQiText.isEmpty ? "—" : chart.nextJieQiText
        let lon = chart.longitude.map { String(format: "%.1f°", $0) } ?? "—"
        let corr: String
        if let t = chart.trueSolarDate {
            let m = Int((t.timeIntervalSince(chart.birthDate) / 60).rounded())
            corr = "\(m >= 0 ? "+" : "")\(m)分钟"
        } else { corr = "未校正" }
        return "上一节 \(prev) · 下一节 \(next)（天文历算实算值）· 真太阳时校正 \(corr)（经度 \(lon)）"
    }

    private func verificationFooter(item: InterpretItem) -> some View {
        let _ = verifyTick
        return VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 6) {
                Text("验真溯源").font(.caption2).fontWeight(.bold).foregroundStyle(Ky.gold)
                Text("紫金山天文台节气 · 真太阳时校正 · 五典卷目见上方「法则」").font(.caption2).foregroundStyle(Ky.sub)
            }
            Text("验真依据链：\(verifyChain)")
                .font(.caption2).foregroundStyle(Ky.sub).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("已应验") { VerifyStore.set(item.title, true); verifyTick += 1 }
                    .font(.caption2).fontWeight(.bold)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(VerifyStore.mark(for: item.title) == true ? Ky.jade : Ky.elevated)
                    .foregroundStyle(VerifyStore.mark(for: item.title) == true ? Color.white : Ky.ink)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                Button("待回验") { VerifyStore.set(item.title, false); verifyTick += 1 }
                    .font(.caption2).fontWeight(.bold)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(VerifyStore.mark(for: item.title) == false ? Ky.cinnabar : Ky.elevated)
                    .foregroundStyle(VerifyStore.mark(for: item.title) == false ? Color.white : Ky.ink)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                if let m = VerifyStore.mark(for: item.title) {
                    Text(m ? "已标：应验 ✓" : "已标：待回验").font(.caption2).foregroundStyle(m ? Ky.jade : Ky.cinnabar)
                }
                Spacer()
                Text("打标计入个人准确率").font(.caption2).foregroundStyle(Ky.sub)
            }
        }
        .padding(.top, 2)
    }

    private func threePartRows(chart: BaziChart, item: InterpretItem, allItems: [InterpretItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            threePartRow("【岁运引动】", InterpretEngine.yunHint(chart: chart, title: item.title))
            threePartRow("【现实避坑指南】", InterpretEngine.guideHint(items: allItems, title: item.title))
        }
        .padding(.top, 2)
    }
    private func threePartRow(_ label: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label).font(.caption2).fontWeight(.bold).foregroundStyle(Ky.gold).frame(width: 96, alignment: .leading)
            Text(text).font(.caption).foregroundStyle(Ky.ink)
        }
    }
    private var glossarySheet: some View {
        NavigationStack {
            List {
                ForEach(TermGlossary.texts.keys.sorted(), id: \.self) { term in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(term).font(.callout).fontWeight(.bold).foregroundStyle(Ky.ink)
                        Text(TermGlossary.texts[term] ?? "").font(.caption).foregroundStyle(Ky.sub)
                    }
                }
            }
            .navigationTitle("术语释义").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showGlossary = false } } }
        }
    }
}

// MARK: - 朗读（对标问真「听书」：解盘可听，系统语音离线合成）
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    @Published var speaking = false
    override init() {
        super.init()
        synth.delegate = self
    }
    func read(_ text: String) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate); speaking = false; return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = 0.48
        speaking = true
        synth.speak(u)
    }
    func stop() { synth.stopSpeaking(at: .immediate); speaking = false }
    // 朗读自然结束／被取消时复位 speaking（此前只在手动 stop 里复位，播完按钮会一直卡在「停止朗读」）
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.speaking = false }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.speaking = false }
    }
}

// MARK: - 解盘全维度（每条：大白话结论＋依据链；标注所据法则与出处层级）
extension InterpretEngine {
    static func dimensions(_ ch: BaziChart) -> [InterpretItem] {
        var out: [InterpretItem] = []
        let dayStem = ch.rizhu.first!
        let pct = ch.wuxingPercents
        let wxN = ["木", "火", "土", "金", "水"]
        func wxIdx(_ c: Character) -> Int { ["甲", "乙"].contains(c) ? 0 : ["丙", "丁"].contains(c) ? 1 : ["戊", "己"].contains(c) ? 2 : ["庚", "辛"].contains(c) ? 3 : 4 }
        let dayWx = wxIdx(dayStem)
        // 十神计数（透＋藏）
        var cnt: [String: Int] = [:]
        for ss in ch.stemShiShen where ss != "日主" { cnt[ss, default: 0] += 1 }
        for row in ch.hideShiShen { for ss in row { cnt[ss, default: 0] += 1 } }
        func g(_ names: [String]) -> Int { names.reduce(0) { $0 + (cnt[$1] ?? 0) } }
        let guan = g(["正官", "七杀"]), yin = g(["正印", "偏印"]), cai = g(["正财", "偏财"])
        let shi = g(["食神", "伤官"]), bi = g(["比肩", "劫财"])
        let sha = Set(BaziTables.shenSha(ch).flatMap { $0 })
        let shengWo = (dayWx + 4) % 5
        let tong = pct[dayWx] + pct[shengWo]
        let level = tong >= 55 ? "偏强" : (tong <= 40 ? "偏弱" : "中和")
        let cntText = "官杀 \(guan) · 印 \(yin) · 财 \(cai) · 食伤 \(shi) · 比劫 \(bi)（透干＋藏干合计）"
        func item(_ t: String, _ c: String, _ fact: String, _ rule: String) -> InterpretItem {
            InterpretItem(title: t, conclusion: c, links: [("盘面", fact), ("根据", rule)])
        }
        // 根气判法（纪律 46②）：根＝四支本气藏有该十神之干；余气藏干只算弱根，不许拿计数冒充有根
        func rootInfo(_ names: [String]) -> (tou: Bool, rootIdx: [Int], weak: Int) {
            var stemSet = Set<Character>()
            for st in Array("甲乙丙丁戊己庚辛壬癸") where names.contains(BaziTables.shiShen(day: dayStem, stem: st)) { stemSet.insert(st) }
            var rIdx: [Int] = []; var wk = 0
            for (i, p) in ch.pillars.enumerated() {
                let cg = BaziTables.cangGan[p.last!]!
                if let f = cg.first, stemSet.contains(f) { rIdx.append(i) }
                else if cg.dropFirst().contains(where: { stemSet.contains($0) }) { wk += 1 }
            }
            return (names.contains { ch.stemShiShen.contains($0) }, rIdx, wk)
        }
        func rootText(_ r: (tou: Bool, rootIdx: [Int], weak: Int)) -> String {
            let cols = ["年", "月", "日", "时"]
            if !r.rootIdx.isEmpty { return r.tou ? "透干且有根（根在\(r.rootIdx.map { cols[$0] }.joined(separator: "、"))支本气）" : "藏而有根（根在\(r.rootIdx.map { cols[$0] }.joined(separator: "、"))支本气，未透干）" }
            if r.weak > 0 { return "仅余气弱根 \(r.weak) 处，根浅" }
            return "无根"
        }
        // 主导十神加权（纪律 43①近似口径：透干×2、藏本气×1、余气×0.5、月柱再×1.5）
        func groupScore(_ names: [String]) -> Double {
            var sc = 0.0
            for ss in ch.stemShiShen where names.contains(ss) { sc += 2 }
            for (pi, row) in ch.hideShiShen.enumerated() {
                for (ci, ss) in row.enumerated() where names.contains(ss) {
                    sc += (ci == 0 ? 1.0 : 0.5) * (pi == 1 ? 1.5 : 1.0)
                }
            }
            return sc
        }

        // 性格性情
        let natureWx = ["木": "仁厚向上、要生长空间，最烦被堵死", "火": "热情外放、反应快，最烦冷场和慢节奏", "土": "稳重务实、重承诺，最烦反复无常", "金": "利落果断、讲规矩，最烦拖泥带水", "水": "灵活善变通、想得多，最烦被框死"][wxN[dayWx]]!
        let dom = [("官杀", groupScore(["正官", "七杀"]), "骨子里自带一根弦：对规则和评价敏感，越有压力越成形"), ("印星", groupScore(["正印", "偏印"]), "先想后动，安全感来自有依据、有退路"), ("财星", groupScore(["正财", "偏财"]), "结果导向，凡事先问值不值、有没有用"), ("食伤", groupScore(["食神", "伤官"]), "表达欲和主见都强，服理不服管"), ("比劫", groupScore(["比肩", "劫财"]), "自我驱动力强，认定的事别人很难拉回")].max { $0.1 < $1.1 }!
        // 制化先行（回测纪律第 35 轮）：主导十神被制化时，先按制化定性，不许按裸象直读
        let touSet = Set(ch.stemShiShen)
        var domText = dom.2
        var zhiNote = ""
        if dom.0 == "食伤" && yin >= 2 && (touSet.contains("正印") || touSet.contains("偏印")) {
            domText = "有表达欲也有主见，但印星透干贴身收着——外面看着老实内敛、守规矩，锋芒藏在里面；真认死理时谁也拉不动，属伤官配印的内秀型，不是明面上的刺头"
            zhiNote = "；伤官虽最重，但印星透干制化，先按制化定性"
        } else if dom.0 == "官杀" && shi >= 2 && (touSet.contains("食神") || touSet.contains("伤官")) {
            domText = "压力感强，但盘里食伤透出作出口——越有压力越靠技术与表达破局，是化压为能的类型，不是纯挨压"
            zhiNote = "；官杀最重而食伤透干制化，先按制化定性"
        } else if dom.0 == "财星" && bi >= 2 && (touSet.contains("比肩") || touSet.contains("劫财")) {
            domText = "对钱与结果敏感，但比劫透干同在——钱容易经同辈与合伙之手进出，财权必须握在自己手里，分账先于交情"
            zhiNote = "；财星最重而比劫透干同夺，定性须带此戒"
        }
        // 内外向／思维／执行力（取象参考：主导十神＋日主五行）
        let neiWai = (dom.0 == "食伤" || dom.0 == "比劫" || dom.0 == "财星") ? "外向" : "内向"
        let siWei = yin >= 2 ? "系统逻辑型（印星主收纳归纳）" : (shi >= 2 ? "发散联想型（食伤主生发）" : (guan >= 2 ? "结构执行型（官杀主秩序）" : "直觉综合型"))
        let zhiXing = guan >= 2 ? "执行力强（官杀给目标与压力）" : (bi >= 2 ? "执行力靠自我驱动（比劫给冲劲）" : "执行力随兴趣走（对味才快）")
        out.append(item("性格性情",
            "盘里分量最重的是\(dom.0)——\(domText)。底色上，日主属\(wxN[dayWx])：\(natureWx)。内外向\(neiWai)：思维偏\(siWei)；\(zhiXing)。",
            "日主 \(ch.rizhu)（\(wxN[dayWx])）；\(cntText)\(zhiNote)；主导按加权定（透干×2、藏本气×1、余气×0.5、月柱×1.5）",
            "性格先全局后日主（纪律）：主导十神（含制化）定行为模式，日主五行（《滴天髓》干象）只作底色；伤官见印透先按制化，不按裸象直读（回测纪律）"))

        // 十神做功（哪组十神在干活：透干成链者为做功主体；只按透藏与制化定，不另编）
        var zuoGong = ""
        let guanTou = touSet.contains("正官") || touSet.contains("七杀")
        let yinTou = touSet.contains("正印") || touSet.contains("偏印")
        if guanTou && yinTou { zuoGong = "官印相生在做功：官星生印、印星护身，名分、平台、凭靠三者连成链——主战场在体制与专业资历里，越规范越出成绩。" }
        else if shi >= 2 && cai >= 1 { zuoGong = "食伤生财在做功：技术、表达、产品是变现的发动机，靠输出换钱是主业态；守成要靠制度，不靠感觉。" }
        else if cai >= 2 && guan >= 1 { zuoGong = "财官相生在做功：经营与名分互相抬轿，生意场与职场可以两条腿走，忌只押一边。" }
        else if (cnt["七杀"] ?? 0) >= 1 && yin >= 1 { zuoGong = "杀印相生在做功：压力被印星化掉，越压越能扛，适合在高压行业里拿结果；透支是底线。" }
        else if bi >= 3 && cai >= 1 { zuoGong = "比劫夺财在做功（偏负面）：同辈与合伙是钱财进出的主变量，财权与分账机制必须先立，忌先交情后算账。" }
        else { zuoGong = "没有单一十神组合压场做功：各路十神分力，成事靠组合——平台、手艺、机会三样至少占两样。" }
        out.append(item("十神做功", zuoGong,
            cntText + "；主导 \(dom.0)；官透 \(guanTou ? "见" : "不见")、印透 \(yinTou ? "见" : "不见")",
            "做功看透干成链与制化（《子平真诠》格局应用）；单星计数只作底数，不下做功定论"))

        // 学业文书（学历三查：印根气定底、财克印降档、大运补印升档；文昌学堂只作旁证）
        let yinR = rootInfo(["正印", "偏印"])
        var xueParts: [String] = []
        if !yinR.rootIdx.isEmpty { xueParts.append("印星有根，读书的底子在：吸收偏慢但扎实，适合长线积累的专业，文凭证书这类凭靠对你实打实加分") }
        else if yinR.weak > 0 || yin > 0 { xueParts.append("印星根浅：学习靠兴趣与压力驱动，方法对路比天赋重要，选应用型、技能型方向更容易出成绩") }
        else { xueParts.append("原局印星不现：先别按『读书不行』下结论——学历还要看下面两查（财有没有克印、求学运里有没有补印）") }
        if cai >= 2 && rootInfo(["正财", "偏财"]).tou { xueParts.append("但财星透干克印：读书期容易被现实与赚钱的事分心，环境要替学业挡干扰（这是降档项）") }
        var buYinNote = ""
        for i in ch.dayunGanZhi.indices {
            let st = ch.dayunStartYear(i)
            if st <= ch.birthYear + 22 && st + 9 >= ch.birthYear + 6 {
                let ss = BaziTables.shiShen(day: dayStem, stem: ch.dayunGanZhi[i].first!)
                if ss == "正印" || ss == "偏印" { buYinNote = "求学年段（6–22 岁）正走 \(ch.dayunGanZhi[i]) 运，运干为\(ss)——运里补印，学历上限要往上修，不许按原局印弱断低（这是升档项）"; break }
            }
        }
        if !buYinNote.isEmpty { xueParts.append(buYinNote) }
        if shi >= 2 && yin == 0 && buYinNote.isEmpty { xueParts.append("食伤有气而印不跟：理解与表达不差，弱在系统积累，靠考试技巧与输出型科目扬长") }
        var xue = xueParts.joined(separator: "；") + "。"
        if sha.contains("文昌") { xue += "盘带文昌，考试临场与文字关口有旁证助力。" }
        if sha.contains("学堂") { xue += "另带学堂，正统学业缘有旁证。" }
        // 文理倾向＋考证运（取象参考：印主文、食伤主技、财主商；考证窗口只列大运，不下年份定数）
        let wenLi = (yin >= 2 && guan >= 2) ? "文史哲教、政法管理一类（印官双见）" : (yin >= 2 ? "文史哲教一类（印星主文）" : (guan >= 2 ? "政法管理一类（官杀主权）" : (shi >= 2 ? "理工技艺一类（食伤主技）" : (cai >= 2 ? "商科财经一类（财星主商）" : "文理兼修，凭兴趣定"))))
        xue += "文理倾向：\(wenLi)。"
        var kaoNote = ""
        for i in ch.dayunGanZhi.indices {
            let st = ch.dayunStartYear(i)
            if st <= ch.birthYear + 40 && st + 9 >= ch.birthYear + 22 {
                let ss = BaziTables.shiShen(day: dayStem, stem: ch.dayunGanZhi[i].first!)
                if ss == "正印" || ss == "偏印" || ss == "正官" || ss == "七杀" { kaoNote = "考证运：\(ch.dayunGanZhi[i])运（\(st)起，\(st - ch.birthYear)~\(st - ch.birthYear + 10)岁）运干\(ss)，是拿证、评职称的窗口期\((ss == "正印" || ss == "偏印") ? "，深造（考研／读研）亦利" : "")"; break }
            }
        }
        if !kaoNote.isEmpty { xue += kaoNote + "。" }
        out.append(item("学业文书", xue,
            "印星根气：\(rootText(yinR))；财星计数 \(cai)；文昌\(sha.contains("文昌") ? "见" : "不见")、学堂\(sha.contains("学堂") ? "见" : "不见")",
            "学历三查（工作室纪律 27＋第 38 轮修正）：印星根气定底、财克印降档、大运补印升档并叠加时代基线；文昌学堂只作旁证（《三命通会》印绶论、神煞表）"))

        // 天赋能力（主导十神＋日主五行定天赋取向；天赋须岁运引动，不作定数与等级）
        let talent: String
        switch dom.0 {
        case "食伤": talent = "表达创造型天赋：理解快、表达强、动手欲旺，适合需要输出的领域（写作、设计、技术、教学表达）；弱在久坐积累，须配一个长线基本盘。"
        case "印星": talent = "学习研究型天赋：吸收扎实、记性好、耐得住冷板凳，适合研究、教育、医疗、技术权威路线；弱在变现慢，须配一个出口。"
        case "官杀": talent = "管理执行型天赋：对规则与目标敏感，执行力与抗压性强，适合带团队、做项目、走管理线；弱在弹性，须留一块自由地。"
        case "财星": talent = "经营交易型天赋：对价值与机会敏感，谈判、运营、生意场是主场；弱在守成，须配制度锁财。"
        default: talent = "竞争协作型天赋：自我驱动强、不服输，适合竞争性、开拓性事务；弱在单打独斗，须配互补型搭档。"
        }
        out.append(item("天赋能力", talent + "日主\(wxN[dayWx])的底色是\(natureWx)。",
            "主导十神 \(dom.0)；日主 \(ch.rizhu)（\(wxN[dayWx])）",
            "天赋取向按主导十神定（类象通说）；天赋只作取向，不作定数与等级"))

        // 事业方向
        let hangYe = ["木": "教育、文创、医药、园林纺织", "火": "能源、电子、餐饮、传媒娱乐", "土": "地产、建筑、农业、仓储", "金": "金融、机械、五金、法务军警", "水": "物流、贸易、旅游、水产航运"]
        let xiWx = level == "偏弱" ? wxN[shengWo] : wxN[(dayWx + 2) % 5]
        var career = ""
        if guan >= 3 { career = "官杀成势，事业主线在平台与秩序里：体制、大机构、纪律性强的行业，越规范的舞台越出成绩。" }
        else if shi >= 3 && cai >= 1 { career = "食伤生财，靠本事吃饭：技术、手艺、表达、产品——能把输出变成钱的路子最合你，自由度越高越强。" }
        else if cai >= 3 { career = "财星成势，事业围绕资源与经营转：生意、运营、客户与钱打交道的岗位是主场。" }
        else if yin >= 3 { career = "印星成势，事业靠专业与凭靠立身：研究、教育、医疗、技术权威路线，资历越老越值钱。" }
        else { career = "事业没有单一主星压场，走的是复合路：平台给框、手艺给底、机会给跳板，三样里至少占两样才稳。" }
        career += "行业象上多往喜用\(xiWx)靠：\(hangYe[xiWx]!)一类。"
        // C1 官印理会（《滴天髓》何知章）：官生印、印生身链通才称理会
        if (touSet.contains("正官") || touSet.contains("七杀")) && (touSet.contains("正印") || touSet.contains("偏印")) {
            career += "官印有理会：官星生印、印星护身的链条在透干上连通，平台给你的名分能落到实处。"
        }
        // 五阶段发展路线（前五步大运各标喜忌；体制内外与创业合伙只按十神结构定取向）
        let phaseNames = ["积累期", "起步期", "爆发期", "转型期", "守成期"]
        let stages = (0..<min(5, ch.dayunGanZhi.count)).map { i in
            let sa = ch.dayunStartYear(i) - ch.birthYear
            return "\(phaseNames[i])\(sa)~\(sa + 10)岁\(ch.dayunGanZhi[i])运\(dayunMark(chart: ch, index: i))"
        }
        career += "五阶段路线：\(stages.joined(separator: "；"))（喜运宜进取、忌运宜守成，中性运宜稳进）。"
        let tiZhi = guan >= 3 ? "体制内、大机构是主场" : (shi >= 3 && cai >= 1 ? "创业、自营、手艺变现是主场" : "体制内外皆可，凭平台与手艺两条腿走")
        career += tiZhi + "；" + (bi >= 3 ? "合伙须谨慎（比劫重，账目、分工、退出机制先立字据）" : "合伙可为，宜选互补型搭档") + "。"
        out.append(item("事业方向", career,
            cntText + "；身\(level)（扶抑初判），喜用先取\(xiWx)",
            "十神定事业形态（类象通说）；行业以喜用五行取象（五行类象通说，与调候无关）；官印理会出《滴天髓》何知章"))

        // 工作形态
        var form = ""
        if (touSet.contains("正官") || touSet.contains("七杀")) && (touSet.contains("正印") || touSet.contains("偏印")) { form = "官印相生型：官与印透干成链（官生印、印护身），适合在体系内一级级往上走，名分、职级、编制这类东西对你不是束缚，是台阶。" }
        else if guan >= 2 && yin >= 2 { form = "官印俱见型：压力与凭靠都有分量，但未成透干相生链——平台能借力，关键一步还得靠自己的输出补上，不必死等体系提拔。" }
        else if shi >= 2 && cai >= 2 { form = "自营手艺型：给人打工容易憋屈，自己接活、做产品、开工作室反而顺；早期可以先借平台练手。" }
        else if bi >= 3 { form = "合伙须谨慎型：同辈与合伙人是你的变量，合作可以，但账目、分工、退出机制必须白纸黑字在先。" }
        else { form = "灵活就业型：不挑体制内外，挑的是事情本身对不对味；对味时爆发力强，不对味时耗损明显。" }
        out.append(item("工作形态", form, cntText,
            "官印相生须官印透干成链才算结构，计数凑数只称俱见；食伤生财主自营；比劫重主合伙变量（《子平真诠》格局应用）"))

        // 财运
        var wealth = ""
        if cai == 0 { wealth = "财星不入局：不是没财，是钱不主动找你——财要靠食伤去生、靠岁运去引，年轻时先攒本事，财路后开。" }
        else if level == "偏弱" && cai >= 3 { wealth = "财多身弱：机会和钱的动静都不小，但自己兜不住——求财忌贪大，先练承载（身体、团队、现金流），能守住的才是你的财。" }
        else if level == "偏强" && cai >= 2 { wealth = "身强财旺：能扛财、能聚财，求财路子正大光明地走就行；偏财机会看得懂才取，看不懂的放过。" }
        else { wealth = "财星有根有度：正业收入是主干，偏财是点缀；钱的进出节奏平稳，败在人情与冲动，不败在没机会。" }
        let kuBranch: Character = ["未", "戌", "辰", "丑", "辰"][dayWx]
        let ku = ch.pillars.filter { $0.last! == kuBranch }.count
        wealth += ku > 0 ? "你的财库在\(kuBranch)支，盘里见 \(ku) 处——财有入库之象：攒钱靠制度（自动储蓄、不动产、定期），逢冲库之年财动大、进出都猛。" : "盘里不见你的财库（\(kuBranch)支），钱来钱去偏活，攒钱全靠规则外置（单独账户、固定转存）。"
        // C1 财气通门户（《滴天髓》何知章）：食伤生财链连通且财有根才算通，量级升一档；不通则不升档
        let caiR = rootInfo(["正财", "偏财"])
        if shi > 0 && cai > 0 && !caiR.rootIdx.isEmpty {
            wealth += "何知章「财气通门户」一查：食伤生财的链条连通、财又有根，量级往上看一档。"
        } else if shi > 0 && (cai == 0 || caiR.rootIdx.isEmpty) {
            wealth += "何知章「财气通门户」一查：食伤有气但财路未通（财不见或无根），量级先按现有档看，不宜高估。"
        }
        // 破耗年份预警（近十二年内前三处：冲财库／冲日支／流年干比劫夺财；只列类型与年份，不下定数）
        var poHao: [String] = []
        let nowY = Calendar.current.component(.year, from: Date())
        for y in nowY...(nowY + 11) {
            let gz = YearEngine.report(chart: ch, year: y).gz
            let yb = gz.last!
            var reasons: [String] = []
            if BaziTables.relationFull(yb, kuBranch)?.0 == "冲" { reasons.append("冲财库\(kuBranch)") }
            if BaziTables.relationFull(yb, ch.dayPillar.last!)?.0 == "冲" { reasons.append("冲日支") }
            let yss = BaziTables.shiShen(day: dayStem, stem: gz.first!)
            if yss == "比肩" || yss == "劫财" { reasons.append("流年干比劫夺财") }
            if !reasons.isEmpty { poHao.append("\(y)年\(gz)（\(reasons.joined(separator: "、"))）") }
            if poHao.count >= 3 { break }
        }
        if !poHao.isEmpty { wealth += "破耗年份预警：\(poHao.joined(separator: "；"))——这些年份钱财进出大，忌借贷担保与冲动置产。" }
        out.append(item("财运形态", wealth,
            "财星合计 \(cai)，日主\(level)（扶抑初判）；财库\(kuBranch)支见 \(ku) 处；财根气：\(rootText(caiR))",
            "财星量级看身与财的任受（扶抑通说）；财库随日主五行定（木未、火戌、土辰、水辰、金丑，《三命通会》墓库说）；财气通门户出《滴天髓》何知章"))

        // 婚姻感情
        let spouseNames = ch.gender == "M" ? ["正财", "偏财"] : ["正官", "七杀"]
        let spouse = g(spouseNames)
        var love = ""
        if spouse == 0 { love = "配偶星不入原局：感情不是没有，是不按常规时间表来——多半要靠岁运把配偶星引出来才成事，晚一点反而稳。" }
        else if spouse >= 3 { love = "配偶星成势：异性缘与婚缘信号都强，选择多，难的不是遇不到，是定下来——定性比开始更重要。" }
        else { love = "配偶星有根：婚缘信号清晰，节奏正常，遇到对的人推进即可，不必自我怀疑。" }
        let spouseR = rootInfo(spouseNames)
        if spouse > 0 && spouseR.tou && spouseR.rootIdx.isEmpty && spouseR.weak == 0 {
            love += "但配偶星只透无根：信号浮在表面，有缘无分的信息在前，要等运年补根才落得实。"
        }
        if spouse > 0 && !spouseR.tou {
            var spouseStems = Set<Character>()
            for st in Array("甲乙丙丁戊己庚辛壬癸") where spouseNames.contains(BaziTables.shiShen(day: dayStem, stem: st)) { spouseStems.insert(st) }
            let hostBranches = Set(ch.pillars.map { $0.last! }.filter { p in (BaziTables.cangGan[p] ?? []).contains { spouseStems.contains($0) } })
            if !hostBranches.isEmpty && hostBranches.isSubset(of: ["辰", "戌", "丑", "未"]) {
                love += "配偶星只藏于墓库之支：婚事要等冲库的运年才动得起来，早年急也急不出结果。"
            }
        }
        if ch.gender == "F" && (cnt["正官"] ?? 0) > 0 && (cnt["七杀"] ?? 0) > 0 {
            love += level == "偏弱" ? "另：女命官杀混杂而身偏弱——感情里压力多过选择，先立住自己再谈关系。" : "另：女命官杀混杂而身能任——感情线容易多线并行，定性要趁早，别拖着耗。"
        }
        // C9 婚姻应期提示：配偶星藏而不透者，给禄地／填实／冲库年份类型（只给类型，具体年份见逐年）
        if spouse > 0 && !spouseR.tou {
            var spStems = Set<Character>()
            for st in Array("甲乙丙丁戊己庚辛壬癸") where spouseNames.contains(BaziTables.shiShen(day: dayStem, stem: st)) { spStems.insert(st) }
            var cangB: [Character] = []
            for p in ch.pillars {
                let cg = BaziTables.cangGan[p.last!]!
                if let f = cg.first, spStems.contains(f), !cangB.contains(p.last!) { cangB.append(p.last!) }
            }
            if !cangB.isEmpty {
                let ruKu = cangB.allSatisfy { ["辰", "戌", "丑", "未"].contains($0) }
                love += "应期口径：配偶星藏在\(cangB.map { String($0) }.joined(separator: "、"))支，其禄地年、填实年\(ruKu ? "与冲库年" : "")是婚事易动的年份类型，具体年份见逐年。"
            }
        }
        let db = ch.dayPillar.last!
        var dayRels: [String] = []
        for (i, p) in ch.pillars.enumerated() where i != 2 {
            if let r = BaziTables.relationFull(p.last!, db) { dayRels.append("\(["年", "月", "日", "时"][i])支\(p.last!)与日支\(r.0)") }
        }
        love += dayRels.isEmpty ? "夫妻宫（日支）安静无冲合：婚姻主打一个稳，波动多来自外部节奏而非结构本身。" : "夫妻宫有牵动：\(dayRels.joined(separator: "、"))——关系里有动象，相处要留沟通的余地，忌冷战积压。"
        if sha.contains("桃花") { love += "带桃花，人缘魅力在线，已婚后更要立边界。" }
        // 相处模式＋配偶象义（取象参考，非典籍断法；应期口径见上 C9）
        let spWxIdx = ch.gender == "M" ? (dayWx + 2) % 5 : (dayWx + 3) % 5
        let spMode: String
        switch ch.hideShiShen[2].first ?? "" {
        case "正官", "七杀": spMode = "规矩守约型：相处讲分寸与承诺，忌翻旧账、忌冷战"
        case "正印", "偏印": spMode = "照顾包容型：相处靠体贴与退让，忌把付出当筹码"
        case "食神", "伤官": spMode = "表达直接型：有话直说、情绪外放，忌话赶话升级"
        case "正财", "偏财": spMode = "务实经营型：相处重过日子与分工，忌为钱伤情"
        case "比肩", "劫财": spMode = "朋友伙伴型：相处像队友、重平等与空间，忌互相较劲"
        default: spMode = "平稳相处型：按日支本气看不出强取向，沟通节奏最重要"
        }
        let spXiang = ["木": "仁厚上进，文教、园林、医药一类", "火": "热情明快，传媒、能源、餐饮一类", "土": "稳重务实，实业、地产、仓储一类", "金": "利落果断，金融、法务、军警一类", "水": "灵活善变，贸易、物流、旅游一类"][wxN[spWxIdx]]!
        love += "配偶象义：配偶星\(wxN[spWxIdx])行，伴侣偏\(spXiang)气质。相处模式：\(spMode)。"
        let qingGuan = spouse == 0 ? "感情观随缘：不强求、等运来" : (spouseR.rootIdx.isEmpty ? "感情观重感觉：先动心、后落地" : "感情观务实：重承诺、重过日子")
        love += "感情观：\(qingGuan)。"
        out.append(item("婚姻感情", love,
            "\(ch.gender == "M" ? "男命以财为配偶星" : "女命以官杀为配偶星")，合计 \(spouse)，根气：\(rootText(spouseR))；日支 \(db)",
            "配偶星定位（《三命通会》六亲论）；夫妻宫看日支冲合（通说）；藏星应期口径（禄地／填实／冲库年份类型）出纪律 43③、42③"))

        // 子女（男女分轨：《渊海子平》男以官杀为子、女以食伤为子；个数走三通道不下定数）
        let childNames = ch.gender == "M" ? ["正官", "七杀"] : ["食神", "伤官"]
        let childStar = g(childNames)
        let childR = rootInfo(childNames)
        var child = ""
        if childStar == 0 { child = "子女星不入原局：与子女的缘分偏「后发型」——多半要靠岁运把子女星引出来才成事（得子偏晚的信息），或孩子独立早、聚少离多；缘分不在早晚，在深浅。" }
        else if !childR.rootIdx.isEmpty { child = "子女星有根，子女缘分在正常偏厚的档位。个数不凭一星下定数：要合时柱状态与时代基线一起看，这里只给缘分倾向。" }
        else { child = "子女星见而根浅：缘分有信号但不算厚，得子的节奏多随岁运引动而定，不必为早晚焦虑。" }
        let timeSS = ch.stemShiShen[3]
        child += "时柱（子女宫）为\(ch.timePillar)，时干十神\(timeSS)。与子女的相处模式（取象参考，非典籍断法）：\(["食神": "子女孝顺贴心，晚景有口福与陪伴", "伤官": "子女有主见成就心强，你要学会放手", "正财": "子女务实顾家，晚年经济上得力", "偏财": "子女路子活、离家发展者多，得力在关键时刻", "正官": "子女守规矩有出息", "七杀": "子女个性硬、有冲劲，关系靠尊重维系", "正印": "子女体贴，晚景照护有靠", "偏印": "子女有专长怪才，沟通要找对频道", "比肩": "子女独立性强，像朋友多过像下属", "劫财": "子女花钱手松或竞争心强，早立财务规矩"][timeSS] ?? "平常相处")。"
        // C6 子女时柱通道：时柱被冲之运标子女宫动；子星藏支填实／冲开之运列添丁候选类型（运段级，不下定数）
        var childChan: [String] = []
        let timeBranch = ch.timePillar.last!
        var gongDong: [String] = []
        for i in ch.dayunGanZhi.indices {
            if BaziTables.relation(ch.dayunGanZhi[i].last!, timeBranch) == "冲" {
                gongDong.append("\(ch.dayunGanZhi[i])运（\(ch.dayunStartYear(i))起）")
            }
        }
        if !gongDong.isEmpty { childChan.append("子女宫动之运：\(gongDong.prefix(2).joined(separator: "、"))（运支冲时支）") }
        var childStems = Set<Character>()
        for st in Array("甲乙丙丁戊己庚辛壬癸") where childNames.contains(BaziTables.shiShen(day: dayStem, stem: st)) { childStems.insert(st) }
        var hostB: [Character] = []
        for p in ch.pillars {
            let cg = BaziTables.cangGan[p.last!]!
            if let f = cg.first, childStems.contains(f), !hostB.contains(p.last!) { hostB.append(p.last!) }
        }
        if !hostB.isEmpty {
            var tianShi: [String] = []
            for i in ch.dayunGanZhi.indices {
                let db2 = ch.dayunGanZhi[i].last!
                if hostB.contains(db2) { tianShi.append("\(ch.dayunGanZhi[i])运填实") }
                else if hostB.contains(where: { BaziTables.relation(db2, $0) == "冲" }) { tianShi.append("\(ch.dayunGanZhi[i])运冲开") }
            }
            if !tianShi.isEmpty { childChan.append("子星藏在\(hostB.map { String($0) }.joined(separator: "、"))支，添丁候选类型见 \(tianShi.prefix(2).joined(separator: "、"))（只给运段类型，具体年份见逐年）") }
            else { childChan.append("子星藏在\(hostB.map { String($0) }.joined(separator: "、"))支：该支填实、冲开之运年是添丁易动的年份类型，具体年份见逐年") }
        }
        if !childChan.isEmpty { child += "时柱通道：" + childChan.joined(separator: "；") + "。" }
        out.append(item("子女缘分", child,
            "子女星（\(ch.gender == "M" ? "男命官杀" : "女命食伤")）计数 \(childStar)，根气：\(rootText(childR))；时柱 \(ch.timePillar)",
            "子女星配属（《渊海子平》六亲配属）；个数须走子星＋时柱＋时代基线三通道（纪律 48③、50），单星不下定数；时柱通道已接（子女宫动／子星藏支填实冲开，运段级）"))

        // 父母（根气判读；情/境两层：根气宫位看助力之境，透藏看亲疏之情）
        let fatherR = rootInfo(["偏财"])
        let motherR = rootInfo(["正印", "偏印"])
        var par = "先看助力（境）："
        if !fatherR.rootIdx.isEmpty { par += "父星有根，父亲的助力落得到实处——给资源、给出路一类。" }
        else if fatherR.weak > 0 { par += "父星只有余气弱根：父亲给得出的是零碎支持与关键时刻的一把，成体系的资源托举谈不上。" }
        else { par += "父星无根：父亲这一线助力信号弱——多半是无力给，或给的方式间接。" }
        if !motherR.rootIdx.isEmpty { par += "母星有根，母亲是靠山之一，学业与人生关键处多有她的托举。" }
        else if motherR.weak > 0 { par += "母星只有弱根：母亲的托举偏零碎，成体系的扶持谈不上。" }
        else { par += "母星无根：母亲这一线要么缺位感强、要么由他人代行其职；自己成家后，安全感要靠自己建。" }
        par += "再看亲疏（情）："
        par += fatherR.tou ? "父星透干，父亲的存在感摆在明处，影响直接。" : "父星不透，父亲的影响偏暗线——表达少不等于情薄。"
        par += motherR.tou ? "母星透干，与母亲的连结明面而直接。" : "母星不透，与母亲的连结偏内敛，靠行动不靠言语。"
        out.append(item("父母缘分", par,
            "父星偏财：\(rootText(fatherR))；母星印：\(rootText(motherR))；年月柱 \(ch.yearPillar) \(ch.monthPillar)",
            "偏财看父、正印看母（《渊海子平》六亲配属）；六亲分情／境两层读（第 37 轮回测纪律）；只断助力与亲疏形态，不及生死"))

        // 兄弟姐妹
        var sib = ""
        if bi == 0 { sib = "比劫不现：手足缘薄，独生或与兄弟姐妹疏远的信息强；人生路上同辈助力少，靠自己。" }
        else if bi >= 4 { sib = "比劫成势：兄弟姐妹多或同辈圈子重——助力大，分账与边界也要清；手足是你一生的重要变量。" }
        else { sib = "比劫有根：手足缘分在正常档，同辈之间守望相助型；具体个数不凭一星下定数。" }
        sib += bi >= 3 ? "合作原则：可合作但须白纸黑字（分工、分账、退出机制先立）。" : "合作原则：宜选互补型搭档，分工清楚、账目分明。"
        out.append(item("兄弟姐妹", sib, "比劫合计 \(bi)；月柱 \(ch.monthPillar)",
            "比劫为手足星、月柱为兄弟宫（六亲通说）；只给缘分厚薄，不下个数定数"))

        // 健康
        let organ = ["木": "肝胆、筋与眼睛", "火": "心与血脉、神志睡眠", "土": "脾胃与肌肉", "金": "肺、呼吸道与皮肤", "水": "肾、泌尿与骨、耳"]
        let orderW = pct.indices.sorted { pct[$0] < pct[$1] }
        let weakest = wxN[orderW.first!], strongest = wxN[orderW.last!]
        var health = "五行最弱的是\(weakest)，\(organ[weakest]!)一线是相对薄弱处（按占比看，未叠加受克程度，作保养提醒），平时的保养重点放这里；最旺的是\(strongest)，过旺也会压人，\(organ[strongest]!)的负担同样要留意。"
        if shi >= 3 && cai >= 3 && level == "偏弱" { health += "另有食伤财连环泄身之象：代谢与内分泌的慢性消耗要早防，作息比补品重要。" }
        // C4 健康三查（工作室《健康与寿元》十神与健康；只给倾向，不落病名）
        var healthChecks: [String] = []
        if touSet.contains("偏印") && (cnt["食神"] ?? 0) > 0 {
            healthChecks.append("枭神夺食之象：偏印透干、食神在局，饮食、消化与表达一线要留意")
        }
        if (cnt["七杀"] ?? 0) >= 2 && !(touSet.contains("食神") || touSet.contains("伤官")) && !(touSet.contains("正印") || touSet.contains("偏印")) {
            healthChecks.append("七杀无制无化而旺之象：压力与急性伤损倾向一线要留意，运年引动时更须留神作息与安全")
        }
        var keYinYun: [String] = []
        for i in ch.dayunGanZhi.indices {
            let ss = BaziTables.shiShen(day: dayStem, stem: ch.dayunGanZhi[i].first!)
            if ss == "正财" || ss == "偏财" { keYinYun.append("\(ch.dayunGanZhi[i])运（\(ch.dayunStartYear(i))起）") }
        }
        if !keYinYun.isEmpty {
            healthChecks.append("印星受克之运段：\(keYinYun.prefix(2).joined(separator: "、"))运干为财克印，恢复力低谷的提醒放在这些年段")
        }
        if !healthChecks.isEmpty { health += "三查另见：" + healthChecks.joined(separator: "；") + "。" }
        // 调养防范期（忌神当令的大运段，只列前两步；只作提醒，不落病名）
        var fangFan: [String] = []
        for i in ch.dayunGanZhi.indices {
            if dayunMark(chart: ch, index: i) == "忌" { fangFan.append("\(ch.dayunGanZhi[i])运（\(ch.dayunStartYear(i) - ch.birthYear)岁起）") }
            if fangFan.count >= 2 { break }
        }
        if !fangFan.isEmpty { health += "调养防范期：\(fangFan.joined(separator: "、"))为忌神当令之运，作息、体检与慢性消耗要提前安排。" }
        // 节气养生（按最弱五行取象，非医疗建议）
        let yangSheng = ["木": "春季养肝（早睡、少怒、护眼）", "火": "夏季养心（午休、静心、少熬夜）", "土": "长夏养脾（规律饮食、少生冷）", "金": "秋季养肺（润燥、早睡、护呼吸道）", "水": "冬季养肾（藏精、保暖、少透支）"][weakest]!
        health += "节气养生：\(yangSheng)。"
        out.append(item("健康倾向", health,
            "五行占比 " + (0..<5).map { "\(wxN[$0])\(Int(pct[$0].rounded()))" }.joined(separator: " ") + "；日主\(level)",
            "五行配脏腑五窍（《素问》：肝开窍于目、心开窍于舌）；三查出工作室《健康与寿元》十神与健康（枭神夺食／杀旺攻身／印星受克之运）；只给部位倾向，不落病名"))

        // 寿元关口（守年）；高龄/历史命例（距今逾 92 年）改回看一生口径，不按当前年扫描
        let nowYY = Calendar.current.component(.year, from: Date())
        let isHistory = (nowYY - ch.birthYear) > 92
        var gates: [String] = []
        let scanLo = isHistory ? ch.birthYear + 40 : max(ch.birthYear + 40, nowYY)
        for y in scanLo...max(scanLo, ch.birthYear + 92) {
            let r = YearEngine.report(chart: ch, year: y)
            if r.level == "关口级" { gates.append("\(y) 年（\(r.gz)，\(y - ch.birthYear) 岁上下）") }
            if gates.count >= 4 { break }
        }
        let gateText: String
        if isHistory {
            gateText = gates.isEmpty
                ? "回看其一生（40 岁到 92 岁逐年扫）：没有出现关口级年份。（历史命例回看口径；此条是引动扫描，不作寿元断语）"
                : "回看其一生，关口级年份在：\(gates.joined(separator: "；"))。（历史命例回看口径，只作对照，不作预言）"
        } else {
            gateText = gates.isEmpty
                ? "从今年往后逐年扫到九十余岁，没有出现关口级年份——引动层面平稳，按平年节奏过即可。（此条是引动扫描，不作寿元断语）"
                : "逐年四查扫下来，这些年份定级最高（关口级：强引动集中，或冲／自刑落在日柱）：\(gates.joined(separator: "；"))。守年的过法三条：当年不冒进、不做不可逆的大决定、体检与作息提前安排。能扫出来就是为了避开，不是为了吓人。这里列的是引动最重的年份，不是寿数判断。"
        }
        out.append(item("中老年守年", gateText,
            "逐年四查定级扫描（关口级＝强引动 ≥2 项同现，或冲、自刑落在日柱）",
            "应期引动法；寿元专用断法须寿元星、大运地势等多类条件同现，不在 App 层冒充——此条只作守年提醒"))

        // 贵人人际
        var noble = sha.contains("天乙贵人")
            ? "带天乙贵人：这是命理里第一贵人星——你一生不缺关键时刻拉一把的人，贵人运在线，平时要经营、要惜福。"
            : "不带天乙贵人：贵人运不靠天给，靠事后口碑攒——把每件小事做漂亮，就是你的贵人制造机。"
        if yin >= 2 { noble += "印星又有根，长辈缘与师长缘双在线，遇事多问一句长辈不吃亏。" }
        // 贵人属相（日支三合贵人，传统应用参考）
        let sanHeXiao: [Character: [String]] = ["申": ["猴", "鼠", "龙"], "子": ["猴", "鼠", "龙"], "辰": ["猴", "鼠", "龙"], "寅": ["虎", "马", "狗"], "午": ["虎", "马", "狗"], "戌": ["虎", "马", "狗"], "巳": ["蛇", "鸡", "牛"], "酉": ["蛇", "鸡", "牛"], "丑": ["蛇", "鸡", "牛"], "亥": ["猪", "兔", "羊"], "卯": ["猪", "兔", "羊"], "未": ["猪", "兔", "羊"]]
        if let gx = sanHeXiao[ch.dayPillar.last!] { noble += "贵人属相：\(gx.joined(separator: "、"))（日支三合贵人，传统应用参考）。" }
        out.append(item("贵人与人际", noble,
            "贵人类神煞：\(sha.filter { $0.contains("贵人") || $0.contains("德") || $0 == "文昌" || $0 == "学堂" }.isEmpty ? "不见" : sha.filter { $0.contains("贵人") || $0.contains("德") || $0 == "文昌" || $0 == "学堂" }.sorted().joined(separator: "、"))；印星 \(yin)",
            "天乙贵人为贵人总星（《三命通会》神煞论）"))

        // 出行迁移
        var move = sha.contains("驿马")
            ? "带驿马：一生动象足——求学、工作、定居多有迁移变动，越动越活；适合把发展半径放大，不必困守出生地。（迁移大象紫微另有主断，此处只作八字旁证）"
            : "驿马不显：走动不是你命局的主线——迁与不迁看事业与岁运的实际需要，不必为迁徙本身纠结，更不是动不如守。"
        out.append(item("出行迁移", move,
            "驿马\(sha.contains("驿马") ? "见" : "不见")（按年支/日支三合查）",
            "驿马主走动迁移（神煞通说）"))

        // 置业田宅
        var home = ""
        if pct[2] >= 25 { home = "土气足，田宅缘厚：置业欲强、也置得下，不动产是你相对稳的资产形态，置业顺势即可，不必为置业压垮现金流。" }
        else if yin >= 2 { home = "印星主房产凭靠：置业多得长辈助力或政策红利，买房看文书与产权，手续齐全比价格更重要。" }
        else { home = "田宅不是你的强项宫：置业顺其自然，有闲钱再置，不必为买房压垮现金流；租房与置业的福气差不大。" }
        if motherR.rootIdx.contains(0) || motherR.rootIdx.contains(1) { home += "年月印星有根，置业一事多有长辈或家族助力之象。" }
        // 置业时机（只列大运窗口，不下年份定数）
        var zhiYeWin = ""
        for i in ch.dayunGanZhi.indices {
            let ss = BaziTables.shiShen(day: dayStem, stem: ch.dayunGanZhi[i].first!)
            if ss == "正印" || ss == "偏印" || ss == "正财" || ss == "偏财" { zhiYeWin = "置业窗口：\(ch.dayunGanZhi[i])运（\(ch.dayunStartYear(i))起）运干\(ss)，是置业、换房易动的运段"; break }
        }
        if !zhiYeWin.isEmpty { home += zhiYeWin + "。" }
        out.append(item("置业田宅", home,
            "土占比 \(Int(pct[2].rounded()))%，印星 \(yin)，财库\(kuBranch)支见 \(ku) 处",
            "土为田宅之象、印为房产文书（类象通说）"))

        // 名声
        var fame = ""
        if yin >= 2 && shi >= 2 { fame = "印与食伤俱全：这是著书立说、靠专业名声吃饭的配置——作品、口碑、职称就是你的名片，越老越响。" }
        else if guan >= 2 { fame = "名声来自职位与口碑：官星给名分，你的名气和平台绑定，平台越高名越大。" }
        else { fame = "名声不是主打项：你的福气在实利不在虚名，不必追流量与头衔，把事做成就是最好的名声。" }
        out.append(item("名声声誉", fame, cntText,
            "印主名誉凭靠、食伤主表达传播、官主名分（类象通说）"))

        // 晚年
        let timeDiShi = ch.diShi[3]
        var old = ""
        if ["帝旺", "临官", "长生", "冠带"].contains(timeDiShi) { old = "时柱得旺地（\(timeDiShi)）：晚景自身状态有底——精气神与自理能力不弱，是越老越稳的底子；子女与钱财另见子女、财运两条。" }
        else if ["墓", "绝", "胎"].contains(timeDiShi) { old = "时柱落\(timeDiShi)：晚年要提前布局——钱、房、健康、陪伴四样在中年就要安排好，不指望临时抱佛脚。" }
        else { old = "时柱落\(timeDiShi)：晚景平稳，无大起大落；保持手边有事做、有老友来往，就是最好的晚年。" }
        out.append(item("晚年光景", old,
            "时柱 \(ch.timePillar)，日主在时支处\(timeDiShi)地",
            "时柱为晚景宫，长生十二宫定地势（《三命通会》）"))

        // —— 本轮扩项：颜色数字/方位/注意事项/化解（层级标注从严）——
        let xiIdx: [Int]
        let jiIdx: Int
        switch level {
        case "偏弱": xiIdx = [shengWo, dayWx]; jiIdx = (dayWx + 2) % 5
        case "偏强": xiIdx = [(dayWx + 1) % 5, (dayWx + 2) % 5]; jiIdx = shengWo
        default: xiIdx = [orderW.first!]; jiIdx = orderW.last!
        }
        // 调候优先并入喜用序列：寒月（亥子丑）先补火、热月（巳午未）先补水
        var xiIdxTH = xiIdx
        let mb = ch.monthPillar.last!
        if ["亥", "子", "丑"].contains(mb) && !xiIdxTH.contains(1) { xiIdxTH.insert(1, at: 0) }
        if ["巳", "午", "未"].contains(mb) && !xiIdxTH.contains(4) { xiIdxTH.insert(4, at: 0) }
        let xiNames = xiIdxTH.map { wxN[$0] }.joined(separator: "、")
        let colorMap = ["木": "青、绿", "火": "红、紫", "土": "黄、棕", "金": "白、金", "水": "黑、蓝"]
        let numMap = ["木": "3、8", "火": "2、7", "土": "5、0（即 10）", "金": "4、9", "水": "1、6"]
        let dirMap = ["木": "东方", "火": "南方", "土": "中宫一带（及西南、东北）", "金": "西方", "水": "北方"]
        let xiColors = xiIdxTH.map { "\(wxN[$0])主\(colorMap[wxN[$0]]!)" }.joined(separator: "；")
        let xiNums = xiIdxTH.map { "\(wxN[$0])数 \(numMap[wxN[$0]]!)" }.joined(separator: "；")
        out.append(item("幸运颜色与数字",
            "日常多用这几色最合你：\(xiColors)。穿衣、手机壳、车色、家居点缀都可用，不必全身只穿一色，点缀到位即可。数字上 \(xiNums) 与你相合，选号、楼层、车牌尾数遇上可优先。反过来，\(wxN[jiIdx])色（\(colorMap[wxN[jiIdx]]!)）是你的忌向，大面积长期使用少一些。先把层级说清：这条是民间象征层的用法——图的是提醒与心安，不是典籍断法，别为它花高价买『开运物』。",
            "喜用五行 \(xiNames)；忌向 \(wxN[jiIdx])（身\(level)，扶抑初判口径，与喜忌条同源\(level == "中和" ? "；中和盘本无定忌，暂以最旺之行作过用提醒" : ""))",
            "数字出《周易·系辞》河图五行数（一六水、二七火、三八木、四九金、五十土）；颜色为五行配色通说；取用属民间象征层，标注使用"))

        // 适合方位
        let xiDirs = xiIdxTH.map { "\(wxN[$0])主\(dirMap[wxN[$0]]!)" }.joined(separator: "；")
        out.append(item("适合方位",
            "你的喜用方位：\(xiDirs)。落到生活里：求学、求职、定居选城市，先看出生地往哪个喜用方向走；书桌与办公位朝向、床头方向，也优先朝喜用方位。忌向是\(wxN[jiIdx])主\(dirMap[wxN[jiIdx]]!)，长期定居与重大发展尽量避开纯忌向。这条属流派应用层——取方位之势帮扶喜用；屋内具体的门床灶吉凶另有八宅与飞星法，在风水模块里按宅盘算，不拿这一条代替。",
            "喜用五行 \(xiNames)；日主 \(ch.rizhu)，身\(level)",
            "五行配方位（木东、火南、土中、金西、水北）为《尚书·洪范》以降通说；以喜用定方位属流派应用层"))

        // 注意事项
        var notes: [String] = []
        let groupVals = [("官杀", groupScore(["正官", "七杀"])), ("印星", groupScore(["正印", "偏印"])), ("财星", groupScore(["正财", "偏财"])), ("食伤", groupScore(["食神", "伤官"])), ("比劫", groupScore(["比肩", "劫财"]))]
        let topGroup = groupVals.max { $0.1 < $1.1 }!.0
        let excessText = ["官杀": "注意一：压力与评价是你的暗耗——忌在高压下硬扛到透支，该分出去的责任要分。",
                          "印星": "注意一：想得多、做得少是你的暗耗——忌无限准备，方案定了七成就先动起来。",
                          "财星": "注意一：钱与机会是你的暗耗——忌贪多求快、忌为人情破财，账要算在前面。",
                          "食伤": "注意一：嘴与锋芒是你的暗耗——忌话说太满、得罪人不自知，重要的话先过夜再说。",
                          "比劫": "注意一：合伙与冲动是你的暗耗——忌担保、忌共同账户，钱的事一律白纸黑字。"][topGroup]!
        notes.append(excessText)
        notes.append("注意二：\(weakest)弱是先天短板（\(organ[weakest]!)一线），这一项写进每年的固定体检单，别等有感觉了才查。")
        var nearGate: String? = nil
        for y in nowY...(nowY + 5) {
            let r = YearEngine.report(chart: ch, year: y)
            if r.level == "关口级" { nearGate = "\(y) 年（\(r.gz)）"; break }
        }
        if (nowY - ch.birthYear) > 92 { notes.append("注意三：命主属高龄／历史命例，关口年按其在世年份回看（见逐年全程页），此处不按当前年扫描。") }
        else if let ng = nearGate { notes.append("注意三：最近的关口年是 \(ng)，那年按守年过——不冒进、不做不可逆的大决定、体检提前安排。") }
        else { notes.append("注意三：近六年逐年扫下来没有关口级年份，节奏平稳，可以按主线年放心推进大事。") }
        if sha.contains("桃花") { notes.append("注意四：带桃花，人缘是双刃——已婚或有伴后，异性往来的边界要立在明处。") }
        if sha.contains("驿马") { notes.append("注意四：带驿马，一生动象多——出行与交通安全是常年课题，忌疲劳驾驶、忌赶夜路。") }
        out.append(item("注意事项", notes.joined(separator: ""),
            "主导十神组 \(topGroup)；最弱五行 \(weakest)；近六年关口扫描 \(nearGate ?? "无")；神煞 \(sha.sorted().joined(separator: "、"))",
            "过用之弊按主导十神取象（类象通说）；关口年按逐年四查定级；健康只给体检提醒、不落病名"))

        // 如何化解（破局五层，工作室定版口径）
        let branchWx: [Character: Int] = ["子": 4, "丑": 2, "寅": 0, "卯": 0, "辰": 2, "巳": 1, "午": 1, "未": 2, "申": 3, "酉": 3, "戌": 2, "亥": 4]
        let xiSet = Set(xiIdxTH)
        var buYun: [String] = []
        var daiYun: [String] = []
        for i in ch.dayunGanZhi.indices {
            let gz = ch.dayunGanZhi[i]
            let benQi = BaziTables.cangGan[gz.last!]!.first!
            if xiSet.contains(wxIdx(gz.first!)) || xiSet.contains(wxIdx(benQi)) {
                buYun.append("\(gz)运（\(ch.dayunStartYear(i))–\(ch.dayunStartYear(i) + 9)）")
            } else if xiSet.contains(branchWx[gz.last!]!) {
                daiYun.append("\(gz)运（\(ch.dayunStartYear(i))–\(ch.dayunStartYear(i) + 9)）")
            }
        }
        var buText: String
        if !buYun.isEmpty { buText = "补得到喜用\(xiNames)的大运是 \(buYun.prefix(2).joined(separator: "、"))（判据：运干或运支本气属喜用之行）——那是你命里的回血期，升学、创业、婚嫁、置业这类大事，优先压到这些十年里办。" }
        else if !daiYun.isEmpty { buText = "没有整步直补喜用\(xiNames)的大运；\(daiYun.prefix(1).joined(separator: "、"))只是支里带一点喜用之气，算借势小补——大事仍以守势积累为主，不必硬等。" }
        else {
            var yrs: [String] = []
            for y in nowY...(nowY + 10) {
                let gz = BaziChart.yearGanZhi(y)
                if xiSet.contains(wxIdx(gz.first!)) { yrs.append("\(y)（\(gz)）") }
                if yrs.count >= 3 { break }
            }
            buText = "大运里没有整步直补喜用\(xiNames)的，靠流年小补：\(yrs.isEmpty ? "近十年流年天干亦少见直补，以守势积累为主" : yrs.joined(separator: "、") + " 这几年天干带喜用，是借势推进的窗口")。"
        }
        var realRules: [String] = ["把\(organ[weakest]!)一线写进年度体检固定项"]
        if bi >= 3 { realRules.append("合伙与借贷一律先立字据再谈感情") }
        if level == "偏弱" && cai >= 3 { realRules.append("钱不贪大、杠杆不上，先练承载再谈扩张") }
        if shi >= 3 { realRules.append("重要表态与决定先过夜，次日再发") }
        realRules.append("关口年守三条：不冒进、不做不可逆决定、体检提前")
        let hua = "先说典籍的实话：命里的『病』，典籍只负责断出来，『药』不靠摆件求、靠岁运带来——人能用的典籍手段只有择时进退。【时间表】\(buText)【修身路】《了凡四训》的路子：改过、积善、谦德——命数之外，日用行为能改的那一半在这条路上，与任何物品无关。【借势路】行业、城市、方位往喜用\(xiNames)靠（见事业方向、适合方位），取其势帮扶。【象征路】颜色、数字、佩饰按喜用取（见幸运颜色与数字），这是民间象征层，图提醒与心安，别花高价买『开运物』。【现实路】真正落地的是这几条：\(realRules.joined(separator: "；"))。"
        out.append(item("如何化解（破局调理）", hua,
            "喜用 \(xiNames)；大运序列 \(ch.dayunGanZhi.joined(separator: " "))；最弱 \(weakest)；十神计数 \(cntText)",
            "破局五层法（工作室 2026-10-30 调研定版）：五典病药是诊断学不是治疗学，药靠原局与岁运；典籍伦理层出《了凡四训》；方位行业为流派应用层；颜色数字佩饰为民间象征层——五层分开标注，不混卖"))

        // 21 行业百神与赛道格局深断（细化事业方向：将五行与十神具体落地为现代实业/体制/研发三类赛道）
        var industryAdvice = ""
        if guan >= 2 && yin >= 2 {
            industryAdvice = "官印理会格：平台赋能型。极适合在公职管理、大型企事业单位、政策法规、医疗教育等体制与严规平台立身，以平台名分成就个人名声。"
        } else if shi >= 2 && cai >= 2 {
            industryAdvice = "食伤生财格：专业变现型。靠核心技术、表达创作、产品研发、独立手艺或非标市场机会变现，宜做领域专家或创作者，不喜条框束缚。"
        } else if cai >= 3 {
            industryAdvice = "财星成势格：商务运营型。极度适合供应链管理、贸易流通、资产配置、现金流运营等商务核心岗位，对数字与实效敏感。"
        } else {
            industryAdvice = "综合平衡型：业务骨干路线。适合在专业技术与协调管理交叉的复合岗位发展，凭口碑与作品逐级晋升。"
        }
        out.append(item("行业赛道深断", industryAdvice,
            "日主 \(ch.rizhu)，官杀 \(guan) · 印 \(yin) · 财 \(cai) · 食伤 \(shi)，最强五行 \(wxN[orderW.last!])",
            "《滴天髓》何知章：何知其人贵，官星有理会；何知其人富，财气通门户。十神配置定赛道形态"))

        // 22 财富量级与蓄水池机制（深析财气通门户、真假财库、大运引动）
        var wealthMechanism = ""
        let isTongMen = shi >= 1 && cai >= 1 && motherR.rootIdx.count >= 1
        let kuName = ["木": "未", "火": "戌", "土": "辰", "金": "丑", "水": "辰"][wxN[dayWx]] ?? ""
        let kuCount = ch.pillars.filter { $0.hasSuffix(kuName) }.count
        if isTongMen {
            wealthMechanism = "财气通门户：食伤透出生财、财星在局且本气通根，财富量级上限高。赚钱靠通道顺畅，属于源源不断型。"
        } else {
            wealthMechanism = "财星蓄势：虽未成典型财气通门户大格，但财星隐于原局；致富通道侧重大运与流年的引动，大运补财时爆发力强。"
        }
        if kuCount > 0 {
            wealthMechanism += " 财库有根：能赚亦能守，具备极佳的储蓄与资产沉淀能力；逢冲开财库之年常有大笔现金流变动与置业契机。"
        } else {
            wealthMechanism += " 钱财以周转流通为主，建议养成固定资产定投习惯，以房产或强制储蓄充当人造蓄水池。"
        }
        out.append(item("财富量级蓄水池", wealthMechanism,
            "财星 \(cai) 处，\(wxN[dayWx])库为「\(kuName)」（局见 \(kuCount) 处），通门户检验 \(isTongMen ? "达成" : "未成")",
            "《滴天髓》论财气通门户；三命通会墓库论：财有库，发则能存；库逢冲开，应在聚散"))

        // 23 六亲情境双层解析（情境分断：境遇聚散看星位，感情厚薄看印星贴身与生克）
        var qingJingText = ""
        if motherR.rootIdx.contains(1) || touSet.contains("正印") || touSet.contains("偏印") {
            qingJingText = "印星贴身且有根气：长辈缘分与情义极深，家族向心力强。即便年少因求学、工作与父母聚少离多（境遇层），内心依然孝敬亲近（情义层），遇大事能得长辈精神托举。"
        } else {
            qingJingText = "印星偏弱或居于支下：早年离家自立之象明显，长辈助力有限，全凭自身拼搏立身；六亲交往宜相敬如宾、保持独立边界，不过度依赖长辈资源。"
        }
        out.append(item("六亲情境深读", qingJingText,
            "父母宫月柱 \(ch.monthPillar)，印星 \(yin) 处（根在 \(motherR.rootIdx.map { ["年", "月", "日", "时"][$0] }.joined(separator: "、"))支）",
            "本系统回测纪律（全网学习第 37 轮）：六亲缘分分『情、境』两层——境遇看星弱宫位，情意看印星贴身与气势流通"))

        return out
    }
}
