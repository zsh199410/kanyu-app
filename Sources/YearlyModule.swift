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
                    .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
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
