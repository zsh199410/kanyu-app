// C10 专旺格定量判定（口径 v1.0，2026-11-09）— App 侧
// 与 app/zhuanwang.py 同规则：条件 1 一行独旺成势（三会／三合全 或 占比 ≥55%）；
// 条件 2 旺气得令通根（月令本气＝旺行 或 月令本气生旺行，且本气根 ≥1）；
// 条件 3 无强逆之星（逆星只取克星官杀；强逆＝透干且本气根／有效库根；
// 弱逆＝透干无根／藏而有根／仅余气弱根；无逆＝全无；局支化掉）。
// 财星、食伤不入判定（财星只作喜忌备注；食伤泄秀为喜）。
// 隔离新模块，不接线，不改现有文件。
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
        -> (grade: String, tou: Bool, benRoot: Bool, weakRoot: Bool, kuRoot: Bool) {
        let niStems = stemsOfWx(niWx)
        let stems = pillars.map { $0.first! }
        let branches = pillars.map { $0.last! }
        let tou = stems.contains { niStems.contains($0) }
        var benRoot = false
        var weakRoot = false
        var kuRoot = false
        for b in branches where !juSet.contains(b) {
            let cg = BaziTables.cangGan[b]!
            if niStems.contains(cg[0]) {
                benRoot = true
            } else if cg.dropFirst().contains(where: { niStems.contains($0) }) {
                weakRoot = true
                if (ku[niWx] ?? []).contains(b) { kuRoot = true }
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
        return (grade, tou, benRoot, weakRoot, kuRoot)
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
            verdict: verdict, reasons: reasons, notes: notes)
    }
}
