// 逐年直断（P2b，2026-10-30）：生成规则已按《P2b 规则对齐稿》锁定——
// 每年四查（干支定性/引动分级 冲＞刑＞穿＞合＞破·伏吟/岁运叠加/喜忌称重），
// 重断门槛 ≥2 项强引动；六亲生死类断语 App 层硬禁（对齐稿二条）；
// 验收锚点：一家三口 2026 三个前瞻登记点，原型已验同向（午冲子/日柱自刑/换官运）。
import SwiftUI

enum YearEngine {
    struct YearReport {
        let year: Int; let gz: String; let level: String  // 关口级/主线/参考/平年
        let lines: [String]
    }
    private static let palaces = ["长辈根基", "平台与日常秩序", "自身与配偶", "子女与晚景"]
    private static let relText = ["冲": "变动冲撞", "刑": "纠缠损耗", "穿": "暗损误会",
                                  "合": "牵合缔结", "破": "破耗不和", "伏吟": "重复回响"]
    private static let ssText = ["正财": "财务与务实收获", "偏财": "机会财与人脉钱",
        "正官": "职位责任与名分", "七杀": "压力竞争与硬仗", "正印": "学习文书与贵人凭靠",
        "偏印": "专长钻研与非标机会", "食神": "输出享受与手艺变现", "伤官": "表达突破与不服管",
        "比肩": "同辈并行与独立扛事", "劫财": "合作分账与破耗风险"]

    static func dayunIndex(chart ch: BaziChart, year: Int) -> Int? {
        for i in ch.dayunGanZhi.indices where year >= ch.dayunStartYear(i) && year <= ch.dayunStartYear(i) + 9 {
            return i
        }
        return nil
    }

    static func report(chart ch: BaziChart, year: Int) -> YearReport {
        let gz = BaziChart.yearGanZhi(year)
        let dayStem = ch.rizhu.first!
        var lines: [String] = []
        // 查一＋查二：引动（取最强一条，另有 ≥穿 级的异宫引动再补一条）
        var hits: [(palace: Int, name: String, rank: Int, branch: Character)] = []
        for i in ch.pillars.indices {
            if let r = BaziTables.relationFull(gz.last!, ch.pillars[i].last!) {
                hits.append((i, r.0, r.1, ch.pillars[i].last!))
            }
        }
        hits.sort { $0.rank > $1.rank }
        let strong = hits.filter { $0.rank >= 3 }.count
        if let top = hits.first {
            var t = "流年\(gz.last!)\(top.name)\(top.branch)（\(palaces[top.palace])）：\(relText[top.name] ?? "")一线先动"
            if gz.last! == top.branch && top.name == "刑" { t += "（伏吟兼自刑）" }
            if gz.last! == top.branch && top.name == "伏吟" { t += "：自家事重复回响，忌原地打转" }
            lines.append(t + "。")
            if let second = hits.dropFirst().first(where: { $0.rank >= 3 && $0.palace != top.palace }) {
                lines.append("又\(second.name)\(second.branch)（\(palaces[second.palace])），引动不止一处。")
            }
        }
        // 查三：岁运叠加（换运/起运单列）
        var isTurn = false
        for i in ch.dayunGanZhi.indices where ch.dayunStartYear(i) == year {
            let ss = BaziTables.shiShen(day: dayStem, stem: ch.dayunGanZhi[i].first!)
            lines.append("\(i == 0 ? "起运" : "换运")之年：\(ch.dayunGanZhi[i])运开场，运干为\(ss)——\(ssText[ss] ?? "")成新十年的主课题，身份与平台易有调整。")
            isTurn = true
        }
        // 查一（干定性）
        let stemSS = BaziTables.shiShen(day: dayStem, stem: gz.first!)
        lines.append("流年天干为\(stemSS)：主\(ssText[stemSS] ?? "")。")
        // 平年兜底
        if hits.isEmpty && !isTurn {
            if let di = dayunIndex(chart: ch, year: year) {
                let dgz = ch.dayunGanZhi[di]
                let dss = BaziTables.shiShen(day: dayStem, stem: dgz.first!)
                lines.insert("无强引动：按\(dgz)运（\(dss)）的背景过日子，不必强求变化。", at: 0)
            } else {
                lines.insert("无强引动：尚在童限，按流年本身看。", at: 0)
            }
        }
        // 定级（重断门槛：强引动 ≥2，或冲/自刑落在日柱）
        let gate = strong >= 2 || (hits.first.map { $0.rank >= 5 && $0.palace == 2 } ?? false)
            || (hits.first.map { $0.name == "刑" && $0.palace == 2 && gz.last! == $0.branch } ?? false)
        let level = gate ? "关口级"
            : (hits.first.map { $0.rank >= 4 } ?? false) || isTurn ? "主线"
            : hits.isEmpty ? "平年" : "参考"
        return YearReport(year: year, gz: gz, level: level, lines: lines)
    }
}

struct YearByYearView: View {
    let chart: BaziChart
    let name: String
    private var years: [Int] {
        let now = Calendar.current.component(.year, from: Date())
        if now < chart.qiyunYear {
            return Array(chart.birthYear...(chart.qiyunYear + 9))
        }
        if let di = YearEngine.dayunIndex(chart: chart, year: now) {
            let start = chart.dayunStartYear(di)
            let end = min(start + 19, chart.dayunStartYear(chart.dayunGanZhi.count - 1) + 9)
            return Array(start...end)
        }
        return Array(now...(now + 9))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(years, id: \.self) { y in
                    let r = YearEngine.report(chart: chart, year: y)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("\(y) · \(r.gz)").font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
                            Text(r.level).font(.caption2).fontWeight(.semibold)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(r.level == "关口级" ? Ky.cinnabar.opacity(0.16)
                                            : r.level == "主线" ? Ky.gold.opacity(0.18) : Ky.bg)
                                .foregroundStyle(r.level == "关口级" ? Ky.cinnabar : Ky.ink)
                                .clipShape(Capsule())
                            Spacer()
                        }
                        ForEach(r.lines.indices, id: \.self) { i in
                            Text(r.lines[i]).font(.callout).foregroundStyle(Ky.ink)
                        }
                    }
                    .kyCard()
                }
                Text("口径：逐年四查规则生成（引动分级＋岁运叠加＋干支定性），重断须 ≥2 项强引动同现；健康只给倾向、六亲生死类断语不在 App 层出现——细断以正式报告为准。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle(name.isEmpty ? "逐年直断" : "逐年 · \(name)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 逐年全程（1 岁到老年）＋人生规划：每一年 = 干支解说（逐年四查）＋当年规划
struct LifePlanView: View {
    let chart: BaziChart
    let name: String
    private var years: [Int] { Array((chart.birthYear + 1)...(chart.birthYear + 88)) }
    private var reports: [YearEngine.YearReport] { years.map { YearEngine.report(chart: chart, year: $0) } }

    private struct Stage { let range: ClosedRange<Int>; let name: String; let theme: String }
    private var stages: [Stage] {
        var cnt: [String: Int] = [:]
        for ss in chart.stemShiShen where ss != "日主" { cnt[ss, default: 0] += 1 }
        for row in chart.hideShiShen { for ss in row { cnt[ss, default: 0] += 1 } }
        func g(_ ns: [String]) -> Int { ns.reduce(0) { $0 + (cnt[$1] ?? 0) } }
        let yin = g(["正印", "偏印"]), shi = g(["食神", "伤官"]), cai = g(["正财", "偏财"]), bi = g(["比肩", "劫财"])
        return [
            Stage(range: 1...6, name: "幼年 · 打底", theme: "以体质与性情养成为主。此阶段大运未开或初开，看护重点在先天最弱一行对应的身体一线，习惯比知识先行，规划由家长执行。"),
            Stage(range: 7...12, name: "小学 · 立规", theme: "学习习惯定型的六年。\(yin >= 2 ? "印星有靠，读书缘不差，适合早定阅读与积累的规矩。" : "印星不厚，更要靠规矩与环境托举：固定作息、固定书桌比报班重要。")"),
            Stage(range: 13...18, name: "中学 · 冲文书", theme: "升学关口集中在这六年。\(shi >= 2 ? "食伤透气，理解与表达是强项，选科往能输出的方向靠。" : "按部就班型更稳，把基础题的命中率练满，比攻难题划算。")考试年遇主线年优先全力，遇关口年先保健康与状态。"),
            Stage(range: 19...22, name: "青年 · 定方向", theme: "离家、深造或入行的分岔口。方向按解盘『事业方向』的喜用行业象选，城市按『适合方位』选；这四年选错的代价比慢一年大。"),
            Stage(range: 23...35, name: "壮年 · 成家立业", theme: "事业与婚姻的主战场。\(cai >= 2 ? "财星有根，正业与经营都有戏，" : "")大事排布看逐年：主线年推进（升职、创业、婚嫁、置业），关口年守成。\(bi >= 3 ? "合伙与借贷全程先立字据。" : "")"),
            Stage(range: 36...49, name: "中年 · 承载", theme: "上有老下有小、事业定型的十四年。重心从『冲』转到『稳』：现金流、健康、子女教育三条线并进，关口年不做杠杆与不可逆决定。"),
            Stage(range: 50...65, name: "中晚年 · 收成守成", theme: "收成的十六年：把前面积累变现为安稳——资产求稳、职位求传帮带、健康求规律。时柱所主的晚景从这阶段开始布局。"),
            Stage(range: 66...88, name: "晚年 · 安顿", theme: "以健康与陪伴为主的阶段。财务求稳不求增，居住与照护提前安排；逐年只看关口，关口年把体检与大事都提前办。"),
        ]
    }

    private func planText(level: String, age: Int) -> String {
        var base: String
        switch level {
        case "关口级": base = "守年规划：不启动不可逆的大事（借贷、担保、裸辞、大额投资先缓）；体检、保险、现金流垫厚；已在办的事求稳收尾，宁可慢一年。"
        case "主线": base = "进取规划：这是有强动象的主线年，适合主动办大事——主题看上面引动的宫位（升学／换岗／婚嫁／置业／得子），先定方案再动手，尽量年内办完。"
        case "参考": base = "小步规划：顺引动的那条线小幅推进，试错成本控制在可承受范围内，不梭哈、不借贷扩张。"
        default: base = "积累规划：平年最适合攒三样——本事（证书与技能）、钱（固定储蓄）、健康（作息与运动），把爆发留给主线年。"
        }
        if age <= 6 { base += "（幼年阶段由家长执行：以健康与习惯为主。）" }
        else if age >= 7 && age <= 18 { base += "（求学阶段：学业与状态优先，其余让路。）" }
        else if age >= 66 { base += "（晚年阶段：健康与陪伴优先，财务求稳。）" }
        return base
    }

    var body: some View {
        let reps = reports
        let stages = self.stages
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("从 1 岁到 88 岁，逐年按八字说清：每一年先给干支解说（流年怎么引动你的盘），再给当年的规划——哪年进取、哪年守成、哪年攒本钱，一年一条，照着排人生大事。")
                        .font(.callout).foregroundStyle(Ky.ink)
                    Text("阶段规划是总纲，逐年是细则；两者冲突时以逐年定级为准（关口年优先守）。")
                        .font(.caption).foregroundStyle(Ky.sub)
                }.kyCard()

                Text("人生八阶段 · 总规划").font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
                ForEach(stages.indices, id: \.self) { si in
                    let st = stages[si]
                    let keys = reps.filter { st.range.contains($0.year - chart.birthYear) && ($0.level == "关口级" || $0.level == "主线") }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(st.name).font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
                            Text("\(st.range.lowerBound)–\(st.range.upperBound) 岁").font(.caption2).foregroundStyle(Ky.sub)
                        }
                        Text(st.theme).font(.callout).foregroundStyle(Ky.ink)
                        if !keys.isEmpty {
                            Text("关键年：" + keys.map { "\($0.year)（\($0.year - chart.birthYear) 岁，\($0.level)）" }.joined(separator: "、"))
                                .font(.caption).foregroundStyle(Ky.cinnabar)
                        }
                    }.kyCard()
                }

                Text("逐年细则 · 1 岁到 88 岁").font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
                ForEach(reps.indices, id: \.self) { i in
                    let r = reps[i]
                    let age = r.year - chart.birthYear
                    let di = YearEngine.dayunIndex(chart: chart, year: r.year)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("\(r.year) · \(age) 岁 · \(r.gz)").font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
                            Text(r.level).font(.caption2).fontWeight(.semibold)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(r.level == "关口级" ? Ky.cinnabar.opacity(0.16) : r.level == "主线" ? Ky.gold.opacity(0.18) : Ky.bg)
                                .foregroundStyle(r.level == "关口级" ? Ky.cinnabar : Ky.ink)
                                .clipShape(Capsule())
                            Spacer()
                            Text(di.map { chart.dayunGanZhi[$0] + "运" } ?? "童限").font(.caption2).foregroundStyle(Ky.sub)
                        }
                        ForEach(r.lines.indices, id: \.self) { j in
                            Text(r.lines[j]).font(.callout).foregroundStyle(Ky.ink)
                        }
                        Text(planText(level: r.level, age: age)).font(.callout).foregroundStyle(Ky.gold)
                    }.kyCard()
                }
                Text("口径：逐年解说为四查规则生成（引动分级 冲＞刑＞穿＞合＞破·伏吟＋岁运叠加＋干支定性），规划按定级与人生阶段给出；健康只给倾向、六亲生死类断语不在 App 层出现。年龄按周岁计（生年为 0 岁）。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle(name.isEmpty ? "逐年全程规划" : "全程 · \(name)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
