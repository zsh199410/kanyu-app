// C10 专旺格定量判定（口径 v1.0，2026-11-09）— App 侧
// 与 app/zhuanwang.py 同规则：条件 1 一行独旺成势（三会／三合全 或 占比 ≥55%）；
// 条件 2 旺气得令通根（月令本气＝旺行 或 月令本气生旺行，且本气根 ≥1）；
// 条件 3 无强逆之星（逆星只取克星官杀；强逆＝透干且本气根／有效库根；
// 弱逆＝透干无根／藏而有根／仅余气弱根；无逆＝全无；局支化掉）。
// 财星、食伤不入判定（财星只作喜忌备注；食伤泄秀为喜）。
// 升格断语 2026-11-09 主代理批准接线（C10 §七）：`verdictLine` 供 InterpretModule 调用。
import Foundation

struct ZhuanwangResult {
    let wangWx: String
    let wangPct: Double
    let dayWx: String
    let cond1: Bool
    let cond1Via: String
    let cond2: Bool
    let cond2DeLing: Bool
    let cond2Roots: Int
    let cond3: String?
    let cond3Tou: Bool
    let cond3BenRoot: Bool
    let cond3WeakRoot: Bool
    let cond3KuRoot: Bool
    let cond3TouStem: Character?
    let cond3TouPos: String?
    let cond3KuBranch: Character?
    let juName: String
    let verdict: String
    let reasons: [String]
    let notes: [String]
}

enum Zhuanwang {
    // 三会方局：旺行 -> 各支（土为四季土方局辰戌丑未四支；土无三合局）
    static let sanHui: [String: [Character]] = [
        "木": ["寅", "卯", "辰"], "火": ["巳", "午", "未"],
        "土": ["辰", "戌", "丑", "未"],
        "金": ["申", "酉", "戌"], "水": ["亥", "子", "丑"]]
    // 墓库：逆星之行 -> 库支（土逆星四库皆为库）
    static let ku: [String: [Character]] = [
        "木": ["未"], "火": ["戌"], "金": ["丑"], "水": ["辰"],
        "土": ["辰", "戌", "丑", "未"]]
    // 克行：克旺行之行（官杀行）
    static let keWang: [String: String] = [
        "木": "金", "火": "水", "土": "木", "金": "火", "水": "土"]
    // 印行：生旺行之行（sheng 的逆映射）
    static let yinOf: [String: String] = [
        "木": "水", "火": "木", "土": "火", "金": "土", "水": "金"]

    static func wx(_ s: Character) -> String { BaziTables.wx[s]!.0 }

    static func stemsOfWx(_ wx: String) -> [Character] {
        Array("甲乙丙丁戊己庚辛壬癸").filter { BaziTables.wx[$0]!.0 == wx }
    }

    static func juBranches(_ branches: [Character], wangWx: String) -> Set<Character> {
        var out = Set<Character>()
        if let hui = sanHui[wangWx], hui.allSatisfy({ branches.contains($0) }) {
            out.formUnion(hui)
        }
        for g in BaziTables.sanHeGroups where g.wx == wangWx
            && g.members.allSatisfy({ branches.contains($0) }) {
            out.formUnion(g.members)
        }
        return out
    }

    static func wangRoots(_ branches: [Character], wangWx: String) -> Int {
        branches.filter { wx(BaziTables.cangGan[$0]![0]) == wangWx }.count
    }

    static func niGrade(pillars: [String], niWx: String, juSet: Set<Character>)
        -> (grade: String, tou: Bool, benRoot: Bool, weakRoot: Bool, kuRoot: Bool,
            touStem: Character?, touPos: String?, kuBranch: Character?) {
        let niStems = stemsOfWx(niWx)
        let stems = pillars.map { $0.first! }
        let branches = pillars.map { $0.last! }
        let tou = stems.contains { niStems.contains($0) }
        var touStem: Character? = nil
        var touPos: String? = nil
        let posNames = ["年干", "月干", "日干", "时干"]
        for (i, s) in stems.enumerated() where niStems.contains(s) {
            touStem = s
            touPos = posNames[i]
            break
        }
        var benRoot = false
        var weakRoot = false
        var kuRoot = false
        var kuBranch: Character? = nil
        for b in branches where !juSet.contains(b) {
            let cg = BaziTables.cangGan[b]!
            if niStems.contains(cg[0]) {
                benRoot = true
            } else if cg.dropFirst().contains(where: { niStems.contains($0) }) {
                weakRoot = true
                if (ku[niWx] ?? []).contains(b) {
                    kuRoot = true
                    if kuBranch == nil {
                        kuBranch = b
                    }
                }
            }
        }
        let grade: String
        if tou && (benRoot || kuRoot) {
            grade = "强逆"
        } else if tou || benRoot || weakRoot {
            grade = "弱逆"
        } else {
            grade = "无逆"
        }
        return (grade, tou, benRoot, weakRoot, kuRoot, touStem, touPos, kuBranch)
    }

    // 成局名：三会取「支串＋方位」（巳午未南方），三合取「支串＋行局」（寅午戌火局）；无局返回 ""。
    static func juName(_ branches: [Character], wangWx: String) -> String {
        if let hui = sanHui[wangWx], hui.allSatisfy({ branches.contains($0) }) {
            if wangWx == "土" {
                return "辰戌丑未"
            }
            let dir = ["木": "东方", "火": "南方", "金": "西方", "水": "北方"][wangWx]!
            return hui.map { String($0) }.joined() + dir
        }
        for g in BaziTables.sanHeGroups where g.wx == wangWx
            && g.members.allSatisfy({ branches.contains($0) }) {
            return g.display + wangWx + "局"
        }
        return ""
    }

    static func check(pillars: [String], dayStem: Character) -> ZhuanwangResult {
        let order = ["木", "火", "土", "金", "水"]
        let pct = BaziTables.wuxingPercents(pillars: pillars)
        let wangIdx = pct.enumerated().max(by: { $0.element < $1.element })!.offset
        let wangWx = order[wangIdx]
        let wangPct = (pct[wangIdx] * 10).rounded() / 10
        let dayWx = wx(dayStem)
        let branches = pillars.map { $0.last! }
        let juSet = juBranches(branches, wangWx: wangWx)
        let ju = juName(branches, wangWx: wangWx)

        let cond1a = !juSet.isEmpty
        let cond1b = wangPct >= 55.0
        let cond1 = cond1a || cond1b
        let cond1Via = cond1a ? "三会/三合" : (cond1b ? "占比≥55%" : "无")

        let monthBenWx = wx(BaziTables.cangGan[branches[1]]![0])
        // 得令：月令本气＝旺行（当令）或月令本气生旺行（长生，印生；
        // 朱祖夏构成 (b)「生扶专旺五行」，失败例月令寅木生火为证）。
        let cond2a = monthBenWx == wangWx || BaziTables.sheng[monthBenWx] == wangWx
        let roots = wangRoots(branches, wangWx: wangWx)
        let cond2b = roots >= 1
        let cond2 = cond2a && cond2b

        var reasons: [String] = []
        if wangWx != dayWx {
            return ZhuanwangResult(wangWx: wangWx, wangPct: wangPct, dayWx: dayWx,
                cond1: cond1, cond1Via: cond1Via, cond2: cond2, cond2DeLing: cond2a,
                cond2Roots: roots, cond3: nil, cond3Tou: false, cond3BenRoot: false,
                cond3WeakRoot: false, cond3KuRoot: false,
                cond3TouStem: nil, cond3TouPos: nil, cond3KuBranch: nil,
                juName: ju,
                verdict: "非专旺（从势候选）",
                reasons: ["旺行\(wangWx)≠日主行\(dayWx)，从势分型另立项"], notes: [])
        }

        let niWx = keWang[wangWx]!
        let ni = niGrade(pillars: pillars, niWx: niWx, juSet: juSet)
        let verdict: String
        if !cond1 {
            verdict = "非专旺候选"
            reasons.append("条件1不成立：一行独旺成势未达成（无三会/三合局，占比\(wangPct)%<55%）")
        } else if !cond2 {
            verdict = "非专旺候选"
            if !cond2a {
                reasons.append("条件2不成立：月令本气\(monthBenWx)≠旺行\(wangWx)，不得令")
            }
            if !cond2b {
                reasons.append("条件2不成立：旺行无本气根")
            }
        } else if ni.grade == "无逆" {
            verdict = "真成"
        } else if ni.grade == "弱逆" {
            verdict = "假成"
            reasons.append("条件3弱逆：克星\(niWx)\(ni.tou ? "透干无根" : "藏而有根/仅余气弱根")，不真")
        } else {
            verdict = "不成"
            reasons.append("条件3强逆：克星\(niWx)透干且有\(ni.benRoot ? "本气根" : "有效库根")，破格")
        }

        // 喜忌备注（不入 verdict）：财星、食伤
        let caiWx = BaziTables.ke[dayWx]!
        let caiStems = stemsOfWx(caiWx)
        let caiTou = pillars.map { $0.first! }.contains { caiStems.contains($0) }
        let caiHidden = pillars.contains { p in
            BaziTables.cangGan[p.last!]!.contains { caiStems.contains($0) } }
        let shiWx = BaziTables.sheng[dayWx]!
        let shiStems = stemsOfWx(shiWx)
        let shiPresent = pillars.map { $0.first! }.contains { shiStems.contains($0) }
            || pillars.contains { p in
                BaziTables.cangGan[p.last!]!.contains { shiStems.contains($0) } }
        var notes: [String] = []
        if caiTou || caiHidden {
            notes.append("逢财\(caiTou ? "透干" : "藏干")须有食伤通关")
        }
        if shiPresent {
            notes.append("食伤泄秀为喜，非破格")
        }
        return ZhuanwangResult(wangWx: wangWx, wangPct: wangPct, dayWx: dayWx,
            cond1: cond1, cond1Via: cond1Via, cond2: cond2, cond2DeLing: cond2a,
            cond2Roots: roots, cond3: ni.grade, cond3Tou: ni.tou,
            cond3BenRoot: ni.benRoot, cond3WeakRoot: ni.weakRoot, cond3KuRoot: ni.kuRoot,
            cond3TouStem: ni.touStem, cond3TouPos: ni.touPos, cond3KuBranch: ni.kuBranch,
            juName: ju,
            verdict: verdict, reasons: reasons, notes: notes)
    }

    // 升格断语行（C10 §七，2026-11-09 主代理批准接线）。
    // verdict 为真成／假成／不成时返回断语句；其余返回 ""（不写行）。
    // 真成行后附引擎的逢财备注（若有）；食伤泄秀已在模板内，不重复。
    static func verdictLine(pillars: [String], dayStem: Character) -> String {
        let r = check(pillars: pillars, dayStem: dayStem)
        switch r.verdict {
        case "真成":
            let ju = r.juName.isEmpty ? "占比\(Int(r.wangPct + 0.5))%" : r.juName
            let yin = yinOf[r.wangWx] ?? ""
            let ke = keWang[r.wangWx]!
            var s = "专旺格真成：\(r.wangWx)独旺成势（\(ju)），不见克星。用神取\(r.wangWx)，喜\(yin)相助、食伤泄秀，忌\(ke)克伐。"
            if let cai = r.notes.first(where: { $0.hasPrefix("逢财") }) {
                s += cai + "。"
            }
            return s
        case "假成":
            let ke = keWang[r.wangWx]!
            let touStem = r.cond3TouStem.map { String($0) } ?? ""
            let ni: String
            if r.cond3Tou {
                ni = "\(r.cond3TouPos ?? "")\(touStem)\(ke)虚浮无根"
            } else if r.cond3BenRoot {
                ni = "克星藏而有根"
            } else {
                ni = "克星仅余气弱根"
            }
            return "专旺格假成：\(r.wangWx)虽独旺成势，但\(ni)，格不纯粹。用神仍取\(r.wangWx)，须防\(ke)介入。"
        case "不成":
            let ke = keWang[r.wangWx]!
            let touStem = r.cond3TouStem.map { String($0) } ?? ""
            let ni: String
            if r.cond3Tou {
                if r.cond3KuRoot {
                    let kuBranch = r.cond3KuBranch.map { String($0) } ?? ""
                    ni = "\(r.cond3TouPos ?? "")\(touStem)\(ke)通根坐\(kuBranch)库"
                } else {
                    ni = "\(r.cond3TouPos ?? "")\(touStem)\(ke)透干有本气根"
                }
            } else if r.cond3BenRoot {
                ni = "克星藏干有本气根"
            } else {
                ni = "克星有根"
            }
            return "专旺格不成：\(r.wangWx)虽成势，\(ni)，克伐旺神，专旺破格。改按身旺论，不取专旺用神。"
        default:
            return ""
        }
    }
}
