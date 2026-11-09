// G14 多流派对照 · 做功层确定性实现（预注册协议 v1.2）— App 侧
// 与 app/zuogong.py 同规则（R1–R7）：宾主/体用/功链判定/穿破检测/应事映射/
// 应期节点/六步对照组。BaziChart＋BaziTables 口径。
// 不读答案键，不做网络请求，不碰凭据。只新增文件，不改现有文件。
// 对照展示（并列对照 UI）待后续接线，本文件只做规则＋判断生成。
// v1.2 修正：⑤J2 门槛改口径（十神角色匹配或宫位引动，修正③作废）；
// ⑥J1 落实度按信号强度加权（直冲 2 分、其他 1 分，≥3 不落实）；
// ⑦R5.2 补充表（宫位引动映射）。v1.1 修正①②④保留。
import Foundation

struct ZuogongChain {
    let kind: String
    let gongShen: String
    let yongShen: String
    let gongStem: Character
    let yongStem: Character
    let gongPos: Int
    let yongPos: Int
    let weak: Bool
}

struct ZuogongPoSignal {
    let kind: String
    let target: String
    let description: String
    // v1.1 修正①去重键：支信号 src=来源支、tgt=目标支；干信号 src=来源干、tgt=""。
    let src: String
    let tgt: String
}

struct ZuogongJudgment {
    let eventClass: String
    let person: String
    let year: Int
    let basis: String
    let luoshi: String
    let source: String
}

enum Zuogong {
    // 规则版本（与 app/zuogong.py RULES_VERSION 同步；协议 v1.2）
    static let rulesVersion = "1.2"
    // R2 体用
    static let tiShishen: Set<String> = ["比肩", "劫财", "正印", "偏印", "食神"]
    static let yongShishen: Set<String> = ["正财", "偏财", "正官", "七杀", "伤官"]
    static let pillarNames = ["年柱", "月柱", "日柱", "时柱"]
    static let palaces = ["长辈根基", "平台与日常秩序", "自身与配偶", "子女与晚景"]

    // R5 功链 → 事件类（合用按合化干十神另定）
    static let chainEvent: [String: String] = [
        "食伤制杀": "事业/名声", "印制食伤": "学业/声名", "财制印": "财",
        "化用": "体制/名分", "食伤生财": "财", "比劫取财": "财",
    ]
    // R5.2 流年引动之星 →（事件类，应人），男命口径（本批 12 例全为男命）
    static let liunianStarEvent: [String: (String, String)] = [
        "正财": ("婚", "配偶"), "偏财": ("婚", "配偶"),
        "食神": ("子女", "子女"), "伤官": ("子女", "子女"),
        "正印": ("学业/声名", "本人"), "偏印": ("学业/声名", "本人"),
        "正官": ("事业/名声", "本人"), "七杀": ("事业/名声", "本人"),
        "比肩": ("破耗", "同辈"), "劫财": ("破耗", "同辈"),
    ]
    // R7 对照组：地支关系 → 事件类；宫位 → 应人；item 07 分流 → 事件类
    static let relationEvent: [String: String] = [
        "冲": "变动/迁徙", "刑": "破耗", "穿": "暗损",
        "合": "婚", "破": "破耗", "伏吟": "守年/平年",
    ]
    static let palacePerson: [Int: String] = [0: "父母/长辈", 1: "本人", 2: "配偶", 3: "子女"]
    static let item07Event: [String: String] = [
        "官印相生": "体制/名分", "食伤生财": "财", "财官相生": "财",
        "杀印相生": "事业/名声", "比劫夺财": "破耗", "无单一组合": "守年/平年",
    ]

    // MARK: - 基础 helper

    static func wx(_ s: Character) -> String { BaziTables.wx[s]!.0 }
    static func ke(_ a: Character, _ b: Character) -> Bool { BaziTables.ke[wx(a)] == wx(b) }
    static func sheng(_ a: Character, _ b: Character) -> Bool { BaziTables.sheng[wx(a)] == wx(b) }

    static func hePartner(_ s: Character) -> Character? {
        let table: [Character: Character] = ["甲": "己", "己": "甲", "乙": "庚", "庚": "乙",
                                              "丙": "辛", "辛": "丙", "丁": "壬", "壬": "丁",
                                              "戊": "癸", "癸": "戊"]
        return table[s]
    }

    static func huaGan(day: Character, partner: Character) -> Character? {
        let tg = BaziTables.TG
        let key = String([day, partner].sorted { tg.firstIndex(of: $0)! < tg.firstIndex(of: $1)! })
        let table: [String: Character] = ["甲己": "戊", "乙庚": "庚", "丙辛": "壬", "丁壬": "甲", "戊癸": "丙"]
        return table[key]
    }

    static func hasRoot(_ stem: Character, pillars: [String]) -> Bool {
        let branches = pillars.map { $0.last! }
        for b in branches where BaziTables.cangGan[b]![0] == stem { return true }
        for p in pillars where p.first! == stem && BaziTables.cangGan[p.last!]!.contains(stem) { return true }
        return false
    }

    static func firstPair(_ a: [(Character, Int)], _ b: [(Character, Int)],
                          rel: (Character, Character) -> Bool) -> (Character, Int, Character, Int)? {
        for (aStem, aPos) in a {
            for (bStem, bPos) in b where rel(aStem, bStem) {
                return (aStem, aPos, bStem, bPos)
            }
        }
        return nil
    }

    static func dayunOfYear(_ ch: BaziChart, year: Int) -> String? {
        if year < ch.qiyunYear { return nil }
        for i in ch.dayunGanZhi.indices where year >= ch.dayunStartYear(i) && year <= ch.dayunStartYear(i) + 9 {
            return ch.dayunGanZhi[i]
        }
        return nil
    }

    // MARK: - R3 功链判定

    static func detectChains(_ ch: BaziChart) -> [ZuogongChain] {
        let dayStem = ch.rizhu.first!
        let pillars = ch.pillars
        let stems = pillars.map { $0.first! }
        let branches = pillars.map { $0.last! }
        let stemSS = ch.stemShiShen
        func touStars(_ names: Set<String>) -> [(Character, Int)] {
            var out: [(Character, Int)] = []
            for i in [0, 1, 3] where names.contains(stemSS[i]) { out.append((stems[i], i)) }
            return out
        }
        func benqiStars(_ names: Set<String>) -> [(Character, Int)] {
            var out: [(Character, Int)] = []
            for i in 0..<4 {
                let g = BaziTables.cangGan[branches[i]]![0]
                if names.contains(BaziTables.shiShen(day: dayStem, stem: g)) { out.append((g, i)) }
            }
            return out
        }
        let monthBenqi = BaziTables.cangGan[branches[1]]![0]
        let monthBenqiSS = BaziTables.shiShen(day: dayStem, stem: monthBenqi)
        func monthBenqiStar(_ names: Set<String>) -> [(Character, Int)] {
            names.contains(monthBenqiSS) ? [(monthBenqi, 1)] : []
        }
        var chains: [ZuogongChain] = []
        func add(_ kind: String, _ pair: (Character, Int, Character, Int)?) {
            guard let pair else { return }
            let weak = !(hasRoot(pair.0, pillars: pillars) && hasRoot(pair.2, pillars: pillars))
            chains.append(ZuogongChain(
                kind: kind,
                gongShen: BaziTables.shiShen(day: dayStem, stem: pair.0),
                yongShen: BaziTables.shiShen(day: dayStem, stem: pair.2),
                gongStem: pair.0, yongStem: pair.2,
                gongPos: pair.1, yongPos: pair.3, weak: weak))
        }
        // P1 食伤制杀
        add("食伤制杀", firstPair(
            touStars(["食神", "伤官"]) + monthBenqiStar(["食神", "伤官"]),
            touStars(["正官", "七杀"]) + monthBenqiStar(["正官", "七杀"]),
            rel: ke))
        // P2 印制食伤
        add("印制食伤", firstPair(touStars(["正印", "偏印"]), touStars(["食神", "伤官"]), rel: ke))
        // P3 财制印
        add("财制印", firstPair(touStars(["正财", "偏财"]), touStars(["正印", "偏印"]), rel: ke))
        // P4 合用：日干与透干成天干五合，合化干为用类
        if let partner = hePartner(dayStem) {
            for i in [0, 1, 3] where stems[i] == partner {
                if let hg = huaGan(day: dayStem, partner: partner),
                   yongShishen.contains(BaziTables.shiShen(day: dayStem, stem: hg)) {
                    add("合用", (hg, 2, hg, i))
                }
                break
            }
        }
        // P5 化用
        add("化用", firstPair(touStars(["正官", "七杀"]), touStars(["正印", "偏印"]), rel: sheng))
        // P6 食伤生财
        add("食伤生财", firstPair(
            touStars(["食神", "伤官"]) + benqiStars(["食神", "伤官"]),
            touStars(["正财", "偏财"]) + monthBenqiStar(["正财", "偏财"]),
            rel: sheng))
        // P7 比劫取财
        add("比劫取财", firstPair(
            touStars(["比肩", "劫财"]),
            touStars(["正财", "偏财"]) + monthBenqiStar(["正财", "偏财"]),
            rel: ke))
        return chains
    }

    static func mainChain(_ ch: BaziChart) -> (main: ZuogongChain?, subs: [ZuogongChain], weak: [ZuogongChain]) {
        let all = detectChains(ch)
        let strong = all.filter { !$0.weak }
        let weak = all.filter { $0.weak }
        if !strong.isEmpty {
            return (strong[0], Array(strong.dropFirst().prefix(2)), weak)
        }
        // 修正案 B：全部命中链皆为弱功时，优先级最高的一条弱功链仍为主功链（带 weak 标记）
        if !weak.isEmpty {
            return (weak[0], Array(weak.dropFirst().prefix(2)), weak)
        }
        return (nil, [], weak)
    }

    static func chainEventClass(_ chain: ZuogongChain) -> String {
        if chain.kind == "合用" {
            if ["正财", "偏财"].contains(chain.yongShen) { return "婚" }
            if ["正官", "七杀"].contains(chain.yongShen) { return "体制/名分" }
            return "事业/名声"
        }
        return chainEvent[chain.kind] ?? "守年/平年"
    }

    static func personFor(_ eventClass: String) -> String {
        if eventClass == "婚" { return "配偶" }
        if eventClass == "子女" { return "子女" }
        return "本人"
    }

    // MARK: - v1.1 修正 helper

    static func poAppend(_ signals: inout [ZuogongPoSignal], seen: inout Set<String>,
                         kind: String, target: String, src: Character, tgt: Character,
                         description: String) {
        // v1.1 修正①：穿破信号按（来源，目标，关系）去重，首条保留。
        let key = "\(kind)|\(src)|\(tgt)"
        guard !seen.contains(key) else { return }
        seen.insert(key)
        signals.append(ZuogongPoSignal(kind: kind, target: target, description: description,
                                       src: String(src), tgt: String(tgt)))
    }

    static func poAppendStem(_ signals: inout [ZuogongPoSignal], seen: inout Set<String>,
                             kind: String, target: String, src: Character,
                             description: String) {
        // 干信号去重键：（关系，来源干，"")。
        let key = "\(kind)|\(src)|"
        guard !seen.contains(key) else { return }
        seen.insert(key)
        signals.append(ZuogongPoSignal(kind: kind, target: target, description: description,
                                       src: String(src), tgt: ""))
    }

    static func j3Classify(_ po: [ZuogongPoSignal]) -> String {
        // v1.1 修正②：J3 按穿破强度分级。
        // 人身：存在直冲日支/功神的穿/冲/刑信号，且独立信号 ≥2；否则破耗/守年。
        guard !po.isEmpty else { return "守年/平年" }
        let hard = po.filter { ["穿", "冲", "刑"].contains($0.kind) && ["日支", "功神"].contains($0.target) }
        if !hard.isEmpty && po.count >= 2 { return "人身" }
        return "破耗"
    }

    static func j2GateA(_ gateStem: Character, starSS: String, chain: ZuogongChain) -> Bool {
        // v1.2 修正⑤(a)：十神角色匹配。所选引动之星的十神 == 功神/用神十神，
        // 或所选之干生/克功神/用神之干（十神链指向功神/用神）。只算单向生克。
        if starSS == chain.gongShen || starSS == chain.yongShen { return true }
        for kw in [chain.gongStem, chain.yongStem] {
            if sheng(gateStem, kw) || ke(gateStem, kw) { return true }
        }
        return false
    }

    static func j2GateB(_ lz: Character, pillars: [String]) -> [(role: String, rel: String)] {
        // v1.2 修正⑤(b)：宫位引动。流年支与日支/时支有合/冲/刑/穿关系。
        // 返回 [(宫位, 关系名)]，无则 []。
        var hits: [(role: String, rel: String)] = []
        for (role, branch) in [("日支", pillars[2].last!), ("时支", pillars[3].last!)] {
            if let r = BaziTables.relationFull(lz, branch), ["合", "冲", "刑", "穿"].contains(r.0) {
                hits.append((role: role, rel: r.0))
            }
        }
        return hits
    }

    static func palaceEvent(_ starSS: String, fromLiunianStem: Bool,
                            gateBHits: [(role: String, rel: String)]) -> (String, String)? {
        // v1.2 修正⑦ R5.2 补充表：宫位引动映射。不适用时返回 nil，回落到 liunianStarEvent。
        // 流年干食伤透干且流年支引动时柱 → 子女类
        if fromLiunianStem && ["食神", "伤官"].contains(starSS)
            && gateBHits.contains(where: { $0.role == "时支" }) {
            return ("子女", "子女")
        }
        // 流年支合/冲日支 → 婚/配偶类
        if gateBHits.contains(where: { $0.role == "日支" && ["合", "冲"].contains($0.rel) }) {
            return ("婚", "配偶")
        }
        // 流年干财透干且流年支引动日支 → 婚/财类
        if fromLiunianStem && ["正财", "偏财"].contains(starSS)
            && gateBHits.contains(where: { $0.role == "日支" }) {
            return ("婚", "配偶")
        }
        return nil
    }

    // MARK: - R4 结构性穿破

    static func structuralPo(_ ch: BaziChart, chain: ZuogongChain?) -> [ZuogongPoSignal] {
        guard let chain else { return [] }
        let dayStem = ch.rizhu.first!
        let pillars = ch.pillars
        let stems = pillars.map { $0.first! }
        let branches = pillars.map { $0.last! }
        let stemSS = ch.stemShiShen
        var signals: [ZuogongPoSignal] = []
        var seen = Set<String>()
        for (role, stem, pos) in [("功神", chain.gongStem, chain.gongPos), ("用神", chain.yongStem, chain.yongPos)] {
            let b = branches[pos]
            for j in 0..<4 where j != pos {
                if let r = BaziTables.relationFull(b, branches[j]), r.0 == "穿" || r.0 == "冲" {
                    poAppend(&signals, seen: &seen, kind: r.0, target: role, src: b, tgt: branches[j],
                             description: "\(chain.kind)之\(role)\(stem)坐\(b)，与\(pillarNames[j])\(branches[j])成\(r.0)")
                }
            }
        }
        if chain.kind == "食伤制杀" {
            for i in [0, 1, 3] where ["正财", "偏财"].contains(stemSS[i]) && sheng(stems[i], chain.yongStem) {
                poAppendStem(&signals, seen: &seen, kind: "财党杀", target: "用神", src: stems[i],
                             description: "财星\(stems[i])透\(pillarNames[i])生助被制之杀\(chain.yongStem)，削弱制杀之功")
            }
        }
        if ["正财", "偏财"].contains(chain.yongShen) {
            for i in [0, 1, 3] where stemSS[i] == "劫财" {
                poAppendStem(&signals, seen: &seen, kind: "劫争财", target: "用神", src: stems[i],
                             description: "劫财\(stems[i])透\(pillarNames[i])，与财星争财")
            }
        }
        if ["食神", "伤官"].contains(chain.gongShen) {
            for i in [0, 1, 3] where ["正印", "偏印"].contains(stemSS[i]) && ke(stems[i], chain.gongStem) {
                poAppendStem(&signals, seen: &seen, kind: "印夺食", target: "功神", src: stems[i],
                             description: "印星\(stems[i])透\(pillarNames[i])克制功用之食伤\(chain.gongStem)")
            }
        }
        return signals
    }

    // MARK: - R6 应期节点：逐年引动扫描

    struct YearScan {
        let gz: String
        let dayun: String?
        let isTurn: Bool
        let triggers: [String]
        let po: [ZuogongPoSignal]
        let luoshi: String
        let poScore: Int
    }

    static func yearScan(_ ch: BaziChart, year: Int, chain: ZuogongChain?) -> YearScan {
        let gz = BaziChart.yearGanZhi(year)
        let lg = gz.first!
        let lz = gz.last!
        let dgz = dayunOfYear(ch, year: year)
        let isTurn = ch.dayunGanZhi.indices.contains { abs(year - ch.dayunStartYear($0)) <= 1 }
        var triggers: [String] = []
        var po: [ZuogongPoSignal] = []
        if let chain {
            let dayStem = ch.rizhu.first!
            let pillars = ch.pillars
            let branches = pillars.map { $0.last! }
            let kwStems: [(Character, String)] = [(chain.gongStem, "功神"), (chain.yongStem, "用神")]
            let kwBranches: [(Character, String)] = [
                (branches[chain.gongPos], "功神坐支"), (branches[chain.yongPos], "用神坐支"),
                (branches[2], "日支"), (branches[1], "月令")]
            for (ks, krole) in kwStems {
                if lg == ks {
                    triggers.append("流年干\(lg)与\(krole)\(ks)同字")
                } else if hePartner(lg) == ks {
                    triggers.append("流年干\(lg)与\(krole)\(ks)五合")
                }
            }
            for (kb, kpos) in kwBranches {
                if let r = BaziTables.relationFull(lz, kb) {
                    triggers.append("流年支\(lz)\(r.0)\(kb)（\(kpos)）")
                }
            }
            if let dgz {
                let dg = dgz.first!
                let dz = dgz.last!
                for (ks, krole) in kwStems {
                    if dg == ks {
                        triggers.append("大运干\(dg)与\(krole)\(ks)同字")
                    } else if hePartner(dg) == ks {
                        triggers.append("大运干\(dg)与\(krole)\(ks)五合")
                    }
                }
                for (kb, kpos) in kwBranches {
                    if let r = BaziTables.relationFull(dz, kb) {
                        triggers.append("大运支\(dz)\(r.0)\(kb)（\(kpos)）")
                    }
                }
            }
            if isTurn { triggers.append("换运年（大运交接 ±1 年）") }
            let poTargets: [(String, Character)] = [
                ("功神", branches[chain.gongPos]), ("用神", branches[chain.yongPos]), ("日支", branches[2])]
            let dBranch: Character? = dgz.map { $0.last! }
            let sources: [(String, Character?)] = [("流年", lz), ("大运", dBranch)]
            var poSeen = Set<String>()
            for (srcName, srcBranch) in sources {
                guard let srcBranch else { continue }
                for (role, tb) in poTargets {
                    if let r = BaziTables.relationFull(srcBranch, tb), ["穿", "冲", "刑"].contains(r.0) {
                        poAppend(&po, seen: &poSeen, kind: r.0, target: role, src: srcBranch, tgt: tb,
                                 description: "\(srcName)支\(srcBranch)\(r.0)\(role)坐支")
                    }
                }
            }
            let dStem: Character? = dgz.map { $0.first! }
            let stemSources: [(String, Character?)] = [("流年", lg), ("大运", dStem)]
            for (srcName, srcStem) in stemSources {
                guard let srcStem else { continue }
                let srcSS = BaziTables.shiShen(day: dayStem, stem: srcStem)
                if chain.kind == "食伤制杀" && ["正财", "偏财"].contains(srcSS) && sheng(srcStem, chain.yongStem) {
                    poAppendStem(&po, seen: &poSeen, kind: "财党杀", target: "用神", src: srcStem,
                                 description: "\(srcName)干\(srcStem)（财）生助被制之杀\(chain.yongStem)")
                }
                if ["正财", "偏财"].contains(chain.yongShen) && srcSS == "劫财" {
                    poAppendStem(&po, seen: &poSeen, kind: "劫争财", target: "用神", src: srcStem,
                                 description: "\(srcName)干\(srcStem)（劫财）争财")
                }
                if ["食神", "伤官"].contains(chain.gongShen) && ["正印", "偏印"].contains(srcSS)
                    && ke(srcStem, chain.gongStem) {
                    poAppendStem(&po, seen: &poSeen, kind: "印夺食", target: "功神", src: srcStem,
                                 description: "\(srcName)干\(srcStem)（印）克制功用之食伤\(chain.gongStem)")
                }
            }
        }
        // v1.2 修正⑥：落实度按信号强度加权——直冲日支/功神的穿/冲/刑计 2 分，
        // 其他穿破信号计 1 分；0 落实，1–2 半落实，≥3 不落实。直冲口径与修正②一致。
        let hard = po.filter { ["穿", "冲", "刑"].contains($0.kind) && ["日支", "功神"].contains($0.target) }
        let poScore = 2 * hard.count + (po.count - hard.count)
        let luoshi = poScore == 0 ? "落实" : (poScore <= 2 ? "半落实" : "不落实")
        return YearScan(gz: gz, dayun: dgz, isTurn: isTurn, triggers: triggers, po: po, luoshi: luoshi, poScore: poScore)
    }

    // MARK: - R6：逐年 3 条过程判断（做功组）

    static func judgments(_ ch: BaziChart, year: Int) -> [ZuogongJudgment] {
        let dayStem = ch.rizhu.first!
        let (main, subs, _) = mainChain(ch)
        let gz = BaziChart.yearGanZhi(year)
        let lg = gz.first!
        let lz = gz.last!
        let dgz = dayunOfYear(ch, year: year)
        var out: [ZuogongJudgment] = []
        // J1：主功链引动判断
        if let main {
            let scan = yearScan(ch, year: year, chain: main)
            if scan.luoshi == "不落实" {
                out.append(ZuogongJudgment(eventClass: "守年/平年", person: "本人", year: year,
                    basis: "主功链\(main.kind)穿破加权 \(scan.poScore) 分（\(scan.po.map { $0.description }.joined(separator: "；"))），不落实",
                    luoshi: "不落实", source: "zuogong"))
            } else if !scan.triggers.isEmpty {
                let ec = chainEventClass(main)
                let state = scan.luoshi == "落实" ? "落实" : "半落实（\(scan.po.map { $0.description }.joined(separator: "；"))）"
                let basis = "主功链\(main.kind)（\(main.gongShen)\(main.gongStem)→\(main.yongShen)\(main.yongStem)）\(state)；\(scan.triggers.joined(separator: "；"))"
                out.append(ZuogongJudgment(eventClass: ec, person: personFor(ec), year: year,
                    basis: basis, luoshi: scan.luoshi, source: "zuogong"))
            } else {
                out.append(ZuogongJudgment(eventClass: "守年/平年", person: "本人", year: year,
                    basis: "主功链\(main.kind)在\(year)年无引动", luoshi: "落实", source: "zuogong"))
            }
        } else {
            out.append(ZuogongJudgment(eventClass: "守年/平年", person: "本人", year: year,
                basis: "无功链可引动", luoshi: "落实", source: "zuogong"))
        }
        // J2：副功链引动判断，否则流年最强引动之星
        var j2: ZuogongJudgment? = nil
        for sub in subs {
            let scan = yearScan(ch, year: year, chain: sub)
            if !scan.triggers.isEmpty && scan.luoshi != "不落实" {
                let ec = chainEventClass(sub)
                let basis = "副功链\(sub.kind)（\(sub.gongShen)\(sub.gongStem)→\(sub.yongShen)\(sub.yongStem)）；\(scan.triggers.joined(separator: "；"))"
                j2 = ZuogongJudgment(eventClass: ec, person: personFor(ec), year: year,
                    basis: basis, luoshi: scan.luoshi, source: "zuogong")
                break
            }
        }
        if j2 == nil {
            // 流年最强引动之星：流年干十神 → 流年支本气十神 → 大运干十神。
            // v1.2 修正⑤：兜底须满足门槛二选一——(a) 十神角色匹配或 (b) 宫位引动；
            // 修正③作废。主功链不存在时门槛不适用（保持 v1.0 行为）。
            var starSS = BaziTables.shiShen(day: dayStem, stem: lg)
            var starSrc = "流年干\(lg)"
            var gateStem: Character? = lg
            var gateIsBranch = false
            if starSS == "日主" {
                let benqi = BaziTables.cangGan[lz]![0]
                starSS = BaziTables.shiShen(day: dayStem, stem: benqi)
                starSrc = "流年支\(lz)本气\(benqi)"
                gateStem = benqi
                gateIsBranch = true
            }
            if starSS == "日主", let dgz {
                starSS = BaziTables.shiShen(day: dayStem, stem: dgz.first!)
                starSrc = "大运干\(dgz.first!)"
                gateStem = dgz.first!
                gateIsBranch = false
            }
            if let main {
                let gateA = gateStem.map { j2GateA($0, starSS: starSS, chain: main) } ?? false
                let gateBHits = j2GateB(lz, pillars: ch.pillars)
                if !gateA && gateBHits.isEmpty {
                    j2 = ZuogongJudgment(eventClass: "守年/平年", person: "本人", year: year,
                        basis: "\(starSrc)与主功链关键字无十神角色匹配、无宫位引动（v1.2 门槛），不引动", luoshi: "落实", source: "zuogong")
                } else if let palace = palaceEvent(starSS, fromLiunianStem: !gateIsBranch && gateStem == lg, gateBHits: gateBHits) {
                    // v1.2 修正⑦：R5.2 补充表优先
                    j2 = ZuogongJudgment(eventClass: palace.0, person: palace.1, year: year,
                        basis: "\(starSrc)为\(starSS)，宫位引动\(gateBHits.map { "\(lz)\($0.rel)\($0.role)" }.joined(separator: "、"))，引动\(palace.0)", luoshi: "落实", source: "zuogong")
                } else if let mapped = liunianStarEvent[starSS] {
                    j2 = ZuogongJudgment(eventClass: mapped.0, person: mapped.1, year: year,
                        basis: "\(starSrc)为\(starSS)，引动\(mapped.0)", luoshi: "落实", source: "zuogong")
                } else {
                    j2 = ZuogongJudgment(eventClass: "守年/平年", person: "本人", year: year,
                        basis: "\(starSrc)为\(starSS)，无明确引动之星", luoshi: "落实", source: "zuogong")
                }
            } else if let mapped = liunianStarEvent[starSS] {
                j2 = ZuogongJudgment(eventClass: mapped.0, person: mapped.1, year: year,
                    basis: "\(starSrc)为\(starSS)，引动\(mapped.0)", luoshi: "落实", source: "zuogong")
            } else {
                j2 = ZuogongJudgment(eventClass: "守年/平年", person: "本人", year: year,
                    basis: "\(starSrc)为\(starSS)，无明确引动之星", luoshi: "落实", source: "zuogong")
            }
        }
        out.append(j2!)
        // J3：穿破/守年判断（主功链穿破信号；v1.1 修正②按强度分级）
        if let main {
            let scan = yearScan(ch, year: year, chain: main)
            if !scan.po.isEmpty {
                let cls = j3Classify(scan.po)
                if cls == "人身" {
                    out.append(ZuogongJudgment(eventClass: "人身", person: "本人", year: year,
                        basis: "主功链\(main.kind)穿破（直冲日支/功神＋≥2 独立信号）：\(scan.po.map { $0.description }.joined(separator: "；"))",
                        luoshi: scan.luoshi, source: "zuogong"))
                } else {
                    out.append(ZuogongJudgment(eventClass: "破耗", person: "本人", year: year,
                        basis: "主功链\(main.kind)穿破强度不足（断人身须直冲日支/功神且 ≥2 独立信号）：\(scan.po.map { $0.description }.joined(separator: "；"))",
                        luoshi: scan.luoshi, source: "zuogong"))
                }
            } else {
                out.append(ZuogongJudgment(eventClass: "守年/平年", person: "本人", year: year,
                    basis: "主功链\(main.kind)在\(year)年无穿破", luoshi: "落实", source: "zuogong"))
            }
        } else {
            out.append(ZuogongJudgment(eventClass: "守年/平年", person: "本人", year: year,
                basis: "无功链，无穿破可言", luoshi: "落实", source: "zuogong"))
        }
        return out
    }

    // MARK: - R7：六步对照组 3 条判断（引擎逐年四查，不改引擎）

    static func item07Branch(_ ch: BaziChart) -> String {
        for it in InterpretEngine.dimensions(ch) where it.title == "十神做功" {
            for name in ["官印相生", "食伤生财", "财官相生", "杀印相生", "比劫夺财"] where it.conclusion.hasPrefix(name) {
                return name
            }
            return "无单一组合"
        }
        return "无单一组合"
    }

    static func controlJudgments(_ ch: BaziChart, year: Int) -> [ZuogongJudgment] {
        let rep = YearEngine.report(chart: ch, year: year)
        var out: [ZuogongJudgment] = []
        // C1：关口判断
        if rep.level == "关口级" {
            out.append(ZuogongJudgment(eventClass: "人身", person: "本人", year: year,
                basis: "引擎逐年四查定级关口级", luoshi: "落实", source: "control"))
        } else {
            out.append(ZuogongJudgment(eventClass: "守年/平年", person: "本人", year: year,
                basis: "引擎逐年四查定级\(rep.level)，非关口", luoshi: "落实", source: "control"))
        }
        // C2：流年明细判断（最强引动）
        let gz = BaziChart.yearGanZhi(year)
        let lz = gz.last!
        var hits: [(palace: Int, name: String, rank: Int, branch: Character)] = []
        for i in ch.pillars.indices {
            if let r = BaziTables.relationFull(lz, ch.pillars[i].last!) {
                hits.append((i, r.0, r.1, ch.pillars[i].last!))
            }
        }
        hits.sort { $0.rank > $1.rank }
        if let top = hits.first {
            let ec = relationEvent[top.name] ?? "守年/平年"
            let person = palacePerson[top.palace] ?? "本人"
            out.append(ZuogongJudgment(eventClass: ec, person: person, year: year,
                basis: "流年\(lz)\(top.name)\(top.branch)（\(palaces[top.palace])）", luoshi: "落实", source: "control"))
        } else {
            out.append(ZuogongJudgment(eventClass: "守年/平年", person: "本人", year: year,
                basis: "引擎逐年四查：本年无强引动", luoshi: "落实", source: "control"))
        }
        // C3：格局判断（item 07 分流）
        let branch = item07Branch(ch)
        let ec = item07Event[branch] ?? "守年/平年"
        out.append(ZuogongJudgment(eventClass: ec, person: "本人", year: year,
            basis: "引擎 item 07 十神做功分流：\(branch)", luoshi: "落实", source: "control"))
        return out
    }
}
