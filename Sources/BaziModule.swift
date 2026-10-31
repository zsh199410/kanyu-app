// 八字模块（综合 App 第一块新拼图，并入堪舆仓库 2026-10-30）
// 引擎：lunar-swift（6tail，与服务端 lunar-python 同谱系，MIT）＋自研真太阳时层。
// 口径钉死（八字线定版）：晚子时 sect=2 显式设置；月干/时干五虎遁/五鼠遁复算互校；
// 胎元/胎息/命宫/身宫随盘输出（对标问真三层盘面，金标准盘 12 例对拍守口径）。
// 细盘层（藏干/十神/长生/纳音/旬空）为查表自算移植，2026-10-30 已与 paipan.py 库输出
// 在 12 例金标准盘上逐项对拍全过（原型验证记录见 sanhe-app），不猜 lunar-swift 未核对的接口。
import SwiftUI
import LunarSwift
import UIKit

struct BaziChart {
    var yearPillar: String; var monthPillar: String; var dayPillar: String; var timePillar: String
    var rizhu: String
    var taiYuan: String; var taiXi: String; var mingGong: String; var shenGong: String
    var qiyunDirection: String; var qiyunDate: String
    var dayunGanZhi: [String]
    // 专业细盘（v2 双层密度下层）
    var stemShiShen: [String]      // 年/月/日/时 四干十神（日干位为「日主」）
    var hideGan: [[String]]        // 四支藏干（本气在前）
    var hideShiShen: [[String]]    // 藏干对应十神
    var diShi: [String]            // 长生十二宫：日干在四支的地势
    var naYin: [String]            // 四柱纳音
    var xunKong: String            // 日柱旬空
    var wuxingPercents: [Double]   // 五行占比（木火土金水）：天干各 1，藏干本气 1/中气 0.5/余气 0.3，归一化
    var birthYear: Int = 0
    var gender: String = "M"
    var siliText: String = ""
    var pillars: [String] { [yearPillar, monthPillar, dayPillar, timePillar] }
    var qiyunYear: Int { Int(qiyunDate.prefix(4)) ?? 0 }
    func dayunStartYear(_ i: Int) -> Int { qiyunYear + i * 10 }
    static func yearGanZhi(_ year: Int) -> String {
        let tg = Array("甲乙丙丁戊己庚辛壬癸"); let dz = Array("子丑寅卯辰巳午未申酉戌亥")
        let y60 = ((year - 4) % 60 + 60) % 60
        return String(tg[y60 % 10]) + String(dz[y60 % 12])
    }
}

// MARK: - 细盘查表层（与 paipan.py 同口径，原型对拍 12/12）
enum BaziTables {
    static let TG = Array("甲乙丙丁戊己庚辛壬癸")
    static let DZ = Array("子丑寅卯辰巳午未申酉戌亥")
    static let cangGan: [Character: [Character]] = [
        "子": ["癸"], "丑": ["己", "癸", "辛"], "寅": ["甲", "丙", "戊"], "卯": ["乙"],
        "辰": ["戊", "乙", "癸"], "巳": ["丙", "庚", "戊"], "午": ["丁", "己"],
        "未": ["己", "丁", "乙"], "申": ["庚", "壬", "戊"], "酉": ["辛"],
        "戌": ["戊", "辛", "丁"], "亥": ["壬", "甲"]]
    // 天干 → (五行, 阳=1/阴=0)
    static let wx: [Character: (String, Int)] = [
        "甲": ("木", 1), "乙": ("木", 0), "丙": ("火", 1), "丁": ("火", 0), "戊": ("土", 1),
        "己": ("土", 0), "庚": ("金", 1), "辛": ("金", 0), "壬": ("水", 1), "癸": ("水", 0)]
    static let sheng: [String: String] = ["木": "火", "火": "土", "土": "金", "金": "水", "水": "木"]
    static let ke: [String: String] = ["木": "土", "土": "水", "水": "火", "火": "金", "金": "木"]
    static func shiShen(day: Character, stem: Character) -> String {
        let (dw, dy) = wx[day]!; let (sw, sy) = wx[stem]!; let same = dy == sy
        if sw == dw { return same ? "比肩" : "劫财" }
        if sheng[dw] == sw { return same ? "食神" : "伤官" }
        if ke[dw] == sw { return same ? "偏财" : "正财" }
        if ke[sw] == dw { return same ? "七杀" : "正官" }
        return same ? "偏印" : "正印"
    }
    static let changShengStart: [Character: Character] = [
        "甲": "亥", "乙": "午", "丙": "寅", "丁": "酉", "戊": "寅",
        "己": "酉", "庚": "巳", "辛": "子", "壬": "申", "癸": "卯"]
    static let states = ["长生", "沐浴", "冠带", "临官", "帝旺", "衰", "病", "死", "墓", "绝", "胎", "养"]
    static func diShi(day: Character, branch: Character) -> String {
        let start = DZ.firstIndex(of: changShengStart[day]!)!
        var off = (DZ.firstIndex(of: branch)! - start + 12) % 12
        if wx[day]!.1 == 0 { off = (12 - off) % 12 }  // 阴干逆行
        return states[off]
    }
    // 神煞（通行表）：按日干/年支/日支/月支查到每柱地支上，返回柱序→神煞名
    static func shenSha(_ c: BaziChart) -> [[String]] {
        let stems = [c.yearPillar, c.monthPillar, c.dayPillar, c.timePillar].map { String($0.prefix(1)) }
        let brs = [c.yearPillar, c.monthPillar, c.dayPillar, c.timePillar].map { String($0.suffix(1)) }
        let ds = c.rizhu, yb = brs[0], db = brs[2], mb = brs[1]
        var out: [[String]] = [[], [], [], []]
        func add(_ name: String, _ branch: String) { for i in 0..<4 where brs[i] == branch { out[i].append(name) } }
        let tianyi: [String: [String]] = ["甲": ["丑", "未"], "戊": ["丑", "未"], "乙": ["子", "申"], "己": ["子", "申"], "丙": ["亥", "酉"], "丁": ["亥", "酉"], "壬": ["卯", "巳"], "癸": ["卯", "巳"], "庚": ["寅", "午"], "辛": ["寅", "午"]]
        tianyi[ds]?.forEach { add("天乙贵人", $0) }
        let stemBranch: [(String, [String: String])] = [
            ("文昌", ["甲": "巳", "乙": "午", "丙": "申", "丁": "酉", "戊": "申", "己": "酉", "庚": "亥", "辛": "子", "壬": "寅", "癸": "卯"]),
            ("学堂", ["甲": "亥", "乙": "午", "丙": "寅", "丁": "酉", "戊": "寅", "己": "酉", "庚": "巳", "辛": "子", "壬": "申", "癸": "卯"]),
            ("禄神", ["甲": "寅", "乙": "卯", "丙": "巳", "戊": "巳", "丁": "午", "己": "午", "庚": "申", "辛": "酉", "壬": "亥", "癸": "子"]),
            ("羊刃", ["甲": "卯", "乙": "辰", "丙": "午", "丁": "未", "戊": "午", "己": "未", "庚": "酉", "辛": "戌", "壬": "子", "癸": "丑"]),
            ("金舆", ["甲": "辰", "乙": "巳", "丙": "未", "丁": "申", "戊": "未", "己": "申", "庚": "戌", "辛": "亥", "壬": "丑", "癸": "寅"]),
        ]
        for (name, tab) in stemBranch { if let b = tab[ds] { add(name, b) } }
        // 三合组类（桃花/驿马/华盖/将星/劫煞/亡神）：年支、日支各查一次，去重
        let triads: [[String]: (tao: String, ma: String, hua: String, jiang: String, jie: String, wang: String)] = [
            ["申", "子", "辰"]: ("酉", "寅", "辰", "子", "巳", "亥"),
            ["寅", "午", "戌"]: ("卯", "申", "戌", "午", "亥", "巳"),
            ["巳", "酉", "丑"]: ("午", "亥", "丑", "酉", "寅", "申"),
            ["亥", "卯", "未"]: ("子", "巳", "未", "卯", "申", "寅"),
        ]
        var seen = Set<String>()
        for base in [yb, db] {
            for (members, v) in triads where members.contains(base) {
                for (n, b) in [("桃花", v.tao), ("驿马", v.ma), ("华盖", v.hua), ("将星", v.jiang), ("劫煞", v.jie), ("亡神", v.wang)] {
                    if seen.insert(n + b).inserted { add(n, b) }
                }
            }
        }
        // 红鸾/天喜（年支查）
        let hong: [String: String] = ["子": "卯", "丑": "寅", "寅": "丑", "卯": "子", "辰": "亥", "巳": "戌", "午": "酉", "未": "申", "申": "未", "酉": "午", "戌": "巳", "亥": "辰"]
        if let h = hong[yb], let hi = DZ.firstIndex(of: Character(h)) { add("红鸾", h); add("天喜", String(DZ[(hi + 6) % 12])) }
        // 孤辰/寡宿（年支组）
        let gu: [[String]: (String, String)] = [["亥", "子", "丑"]: ("寅", "戌"), ["寅", "卯", "辰"]: ("巳", "丑"), ["巳", "午", "未"]: ("申", "辰"), ["申", "酉", "戌"]: ("亥", "未")]
        for (members, v) in gu where members.contains(yb) { add("孤辰", v.0); add("寡宿", v.1) }
        // 月德（月支三合→天干，落在柱干）
        let yuede: [String: String] = ["寅": "丙", "午": "丙", "戌": "丙", "申": "壬", "子": "壬", "辰": "壬", "亥": "甲", "卯": "甲", "未": "甲", "巳": "庚", "酉": "庚", "丑": "庚"]
        if let g = yuede[mb] { for i in 0..<4 where stems[i] == g { out[i].append("月德贵人") } }
        // 天德（月支查：干/支混合表）
        let tiandeStem: [String: String] = ["寅": "丁", "辰": "壬", "巳": "辛", "未": "甲", "申": "癸", "戌": "丙", "亥": "乙", "子": "庚"]
        let tiandeBranch: [String: String] = ["卯": "申", "午": "亥", "酉": "寅", "丑": "巳"]
        if let g = tiandeStem[mb] { for i in 0..<4 where stems[i] == g { out[i].append("天德贵人") } }
        if let b = tiandeBranch[mb] { add("天德贵人", b) }
        return out
    }

    static let naYinTable = ["海中金", "炉中火", "大林木", "路旁土", "剑锋金", "山头火", "涧下水", "城头土",
        "白蜡金", "杨柳木", "泉中水", "屋上土", "霹雳火", "松柏木", "长流水", "沙中金", "山下火", "平地木",
        "壁上土", "金箔金", "覆灯火", "天河水", "大驿土", "钗钏金", "桑柘木", "大溪水", "沙中土", "天上火",
        "石榴木", "大海水"]
    static func gzIndex(_ gz: String) -> Int {
        let s = TG.firstIndex(of: gz.first!)!; let b = DZ.firstIndex(of: gz.last!)!
        for i in 0..<60 where i % 10 == s && i % 12 == b { return i }
        return 0
    }
    static func naYin(_ gz: String) -> String { naYinTable[gzIndex(gz) / 2] }
    static func xunKong(dayPillar: String) -> String {
        let i = gzIndex(dayPillar); let head = i - i % 10; let hb = head % 12
        var covered = Set<Int>(); for k in 0..<10 { covered.insert((hb + k) % 12) }
        return DZ.enumerated().filter { !covered.contains($0.offset) }.map { String($0.element) }.joined()
    }
    static func relationFull(_ a: Character, _ b: Character) -> (String, Int)? {
        if a == b {
            return ["辰", "午", "酉", "亥"].contains(a) ? ("刑", 4) : ("伏吟", 1)
        }
        let chong: [Character: Character] = ["子":"午","午":"子","丑":"未","未":"丑","寅":"申","申":"寅","卯":"酉","酉":"卯","辰":"戌","戌":"辰","巳":"亥","亥":"巳"]
        if chong[a] == b { return ("冲", 5) }
        let xingTriples: [Set<Character>] = [["寅","巳","申"], ["丑","戌","未"]]
        if xingTriples.contains(where: { $0.contains(a) && $0.contains(b) }) || (["子","卯"].contains(a) && ["子","卯"].contains(b)) {
            return ("刑", 4)
        }
        let chuan: [Character: Character] = ["子":"未","未":"子","丑":"午","午":"丑","寅":"巳","巳":"寅","卯":"辰","辰":"卯","申":"亥","亥":"申","酉":"戌","戌":"酉"]
        if chuan[a] == b { return ("穿", 3) }
        if relation(a, b) == "合" { return ("合", 2) }
        let po: [Character: Character] = ["子":"酉","酉":"子","卯":"午","午":"卯","辰":"丑","丑":"辰","戌":"未","未":"戌","寅":"亥","亥":"寅","巳":"申","申":"巳"]
        if po[a] == b { return ("破", 1) }
        return nil
    }
    static func relation(_ a: Character, _ b: Character) -> String? {
        let chong: [Character: Character] = ["子":"午","午":"子","丑":"未","未":"丑","寅":"申","申":"寅","卯":"酉","酉":"卯","辰":"戌","戌":"辰","巳":"亥","亥":"巳"]
        let he: [Character: Character] = ["子":"丑","丑":"子","寅":"亥","亥":"寅","卯":"戌","戌":"卯","辰":"酉","酉":"辰","巳":"申","申":"巳","午":"未","未":"午"]
        if chong[a] == b { return "冲" }
        if he[a] == b { return "合" }
        return nil
    }
    static func monthGanZhi(yearStem: Character, monthBranch: Character) -> String {
        let startMap: [Character: Int] = ["甲":2,"己":2,"乙":4,"庚":4,"丙":6,"辛":6,"丁":8,"壬":8,"戊":0,"癸":0]
        let off = (DZ.firstIndex(of: monthBranch)! - DZ.firstIndex(of: "寅")! + 12) % 12
        return String(TG[(startMap[yearStem]! + off) % 10]) + String(monthBranch)
    }
    static func timeGanZhi(dayStem: Character, hour: Int) -> String {
        let startMap: [Character: Int] = ["甲":0,"己":0,"乙":2,"庚":2,"丙":4,"辛":4,"丁":6,"壬":6,"戊":8,"癸":8]
        let branch = DZ[((hour + 1) / 2) % 12]
        return String(TG[(startMap[dayStem]! + DZ.firstIndex(of: branch)!) % 10]) + String(branch)
    }
    static func wuxingPercents(pillars: [String]) -> [Double] {
        let order = ["木", "火", "土", "金", "水"]
        var score: [String: Double] = [:]
        let weights = [1.0, 0.5, 0.3]
        for p in pillars {
            score[wx[p.first!]!.0, default: 0] += 1.0
            for (i, h) in cangGan[p.last!]!.enumerated() {
                score[wx[h]!.0, default: 0] += weights[min(i, 2)]
            }
        }
        let total = order.reduce(0) { $0 + (score[$1] ?? 0) }
        return order.map { (score[$0] ?? 0) / total * 100 }
    }
}

enum BaziEngine {
    private static let TG = Array("甲乙丙丁戊己庚辛壬癸")
    private static let DZ = Array("子丑寅卯辰巳午未申酉戌亥")
    private static func wuhu(yearStem: Character, monthBranch: Character) -> Character {
        let startMap: [Character: Int] = ["甲":2,"己":2,"乙":4,"庚":4,"丙":6,"辛":6,"丁":8,"壬":8,"戊":0,"癸":0]
        let off = (DZ.firstIndex(of: monthBranch)! - DZ.firstIndex(of: "寅")! + 12) % 12
        return TG[(startMap[yearStem]! + off) % 10]
    }
    private static func wushu(dayStem: Character, hourBranch: Character) -> Character {
        let startMap: [Character: Int] = ["甲":0,"己":0,"乙":2,"庚":2,"丙":4,"辛":4,"丁":6,"壬":6,"戊":8,"癸":8]
        return TG[(startMap[dayStem]! + DZ.firstIndex(of: hourBranch)!) % 10]
    }

    /// clock：出生钟表时间（按北京时间记录）；longitude 为 nil 时按钟表时间排
    /// 接口已按 lunar-swift 源码逐项核对（EightChar/Yun/DaYun/Solar 四个源文件，2026-10-30）：
    /// 属性式 year/month/day/time/taiYuan/taiXi/mingGong/shenGong；sect 为可写属性、默认 2；
    /// getYun(gender:sect:) 的运 sect 必须传 1——与服务端引擎默认一致（传 2 起运日差 2 天，金标准盘锁死）。
    static func paipan(clock: Date, gender: String, longitude: Double?) -> BaziChart {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let used = longitude.map { TrueSolarTime.corrected(clock: clock, longitude: $0, calendar: cal) } ?? clock
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: used)
        let solar = Solar.fromYmdHms(year: c.year!, month: c.month!, day: c.day!, hour: c.hour!, minute: c.minute!)
        let ec = solar.lunar.eightChar
        ec.sect = AppSettings.baziSect  // 晚子时归日口径（设置页可调，默认 2）
        let yg = ec.year; var mg = ec.month; let dg = ec.day; var tg = ec.time
        mg = String(wuhu(yearStem: yg.first!, monthBranch: mg.last!)) + String(mg.last!)
        let dayStemForTime: Character = c.hour! == 23 ? TG[(TG.firstIndex(of: dg.first!)! + 1) % 10] : dg.first!
        tg = String(wushu(dayStem: dayStemForTime, hourBranch: tg.last!)) + String(tg.last!)
        let yun = ec.getYun(gender: gender == "M" ? 1 : 0, sect: 1)
        let dayun = yun.getDaYun().dropFirst().map { $0.ganZhi }
        let ss = yun.startSolar
        let pillars = [yg, mg, dg, tg]
        let dayStem = dg.first!
        let hide = pillars.map { BaziTables.cangGan[$0.last!]! }
        var chart = BaziChart(yearPillar: yg, monthPillar: mg, dayPillar: dg, timePillar: tg,
                         rizhu: String(dayStem),
                         taiYuan: ec.taiYuan, taiXi: ec.taiXi,
                         mingGong: ec.mingGong, shenGong: ec.shenGong,
                         qiyunDirection: yun.forward ? "顺行" : "逆行",
                         qiyunDate: String(format: "%04d-%02d-%02d", ss.year, ss.month, ss.day),
                         dayunGanZhi: dayun,
                         stemShiShen: pillars.enumerated().map { i, p in
                             i == 2 ? "日主" : BaziTables.shiShen(day: dayStem, stem: p.first!) },
                         hideGan: hide.map { $0.map { String($0) } },
                         hideShiShen: hide.map { $0.map { BaziTables.shiShen(day: dayStem, stem: $0) } },
                         diShi: pillars.map { BaziTables.diShi(day: dayStem, branch: $0.last!) },
                         naYin: pillars.map { BaziTables.naYin($0) },
                         xunKong: BaziTables.xunKong(dayPillar: dg),
                         wuxingPercents: BaziTables.wuxingPercents(pillars: pillars),
                         birthYear: c.year!, gender: gender)
        chart.siliText = sili(lunar: solar.lunar, monthBranch: mg.last!, birth: solar)
        return chart
    }

    /// 人元司令分野（《子平真诠评注》表）：按生日距月令节气天数落段
    static func sili(lunar: Lunar, monthBranch: Character, birth: Solar) -> String {
        let segs: [Character: [(String, Int)]] = [
            "子": [("癸", 30)], "丑": [("己", 9), ("癸", 3), ("辛", 18)],
            "寅": [("戊", 7), ("丙", 7), ("甲", 16)], "卯": [("甲", 10), ("乙", 20)],
            "辰": [("乙", 9), ("癸", 3), ("戊", 18)], "巳": [("戊", 7), ("庚", 7), ("丙", 16)],
            "午": [("丙", 10), ("己", 9), ("丁", 11)], "未": [("乙", 9), ("丁", 3), ("己", 18)],
            "申": [("戊", 7), ("壬", 7), ("庚", 16)], "酉": [("庚", 10), ("辛", 20)],
            "戌": [("戊", 18), ("丁", 3), ("辛", 9)], "亥": [("戊", 7), ("甲", 7), ("壬", 16)],
        ]
        guard let seg = segs[monthBranch] else { return "" }
        let jq = lunar.prevJieQi.solar
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let d0 = cal.date(from: DateComponents(year: jq.year, month: jq.month, day: jq.day))!
        let d1 = cal.date(from: DateComponents(year: birth.year, month: birth.month, day: birth.day))!
        let days = cal.dateComponents([.day], from: d0, to: d1).day ?? 0
        var acc = 0; var cur = seg.last!
        for sg in seg { if days < acc + sg.1 { cur = sg; break }; acc += sg.1 }
        return "\(cur.0)司令（入节 \(days) 天）"
    }

    /// 任意公历日期的日柱（流日速查；晚子时 sect=2 与排盘同口径）
    static func dayPillar(for date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let solar = Solar.fromYmdHms(year: c.year!, month: c.month!, day: c.day!, hour: c.hour!, minute: c.minute!)
        let ec = solar.lunar.eightChar
        ec.sect = AppSettings.baziSect
        return ec.day
    }
}

// MARK: - 八字排盘页（v2 双层密度盘面：基本盘/专业细盘＋五行横条＋五级时间胶囊）

struct BaziHomeView: View {
    @State private var name = ""
    @State private var gender = "M"
    @State private var birth = Date()
    @State private var useLongitude = true
    @State private var longitudeText = "107.8"
    @State private var chart: BaziChart?
    @StateObject private var peopleStore = PeopleStore()
    @State private var chartSnapshot = ""
    @State private var savedTip = false
    private var inputSnapshot: String { "\(name)|\(gender)|\(birth.timeIntervalSince1970)|\(useLongitude)|\(longitudeText)" }
    private var isStale: Bool { chart != nil && chartSnapshot != inputSnapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                inputCard
                if let ch = chart { BaziResultView(chart: ch, name: name) }
                NavigationLink { CaliberSettingsView() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                        Text("排盘口径设置（晚子时归日等）").font(.caption)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2)
                    }.foregroundStyle(Ky.sub)
                }.buttonStyle(.plain)
                Text("口径：真太阳时＋晚子时归日（设置页可调，默认 sect=2）；细盘与金标准盘 12 例逐项对拍。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("八字排盘")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !peopleStore.people.isEmpty {
                Menu {
                    ForEach(peopleStore.people) { p in
                        Button("\(p.name)（\(p.gender == "M" ? "男" : "女")）") {
                            name = p.name; gender = p.gender; birth = p.birthDate
                            useLongitude = p.useLongitude; longitudeText = String(format: "%.1f", p.longitude)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.rectangle.stack").foregroundStyle(Ky.qingdai)
                        Text("选已有人物（免重填）").font(.subheadline).foregroundStyle(Ky.qingdai)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Ky.sub)
                    }
                }
            }
            TextField("姓名（可空）", text: $name)
            Picker("性别", selection: $gender) { Text("男").tag("M"); Text("女").tag("F") }
                .pickerStyle(.segmented)
            BirthInputView(clock: $birth, useLongitude: $useLongitude, longitudeText: $longitudeText)
            Button("排盘") {
                chart = BaziEngine.paipan(clock: birth, gender: gender,
                                          longitude: useLongitude ? Double(longitudeText) : nil)
                chartSnapshot = inputSnapshot; savedTip = false
            }.buttonStyle(KyPrimaryButton())
            if isStale {
                Text("输入已改动，下面是旧盘——点「排盘」刷新。").font(.caption).fontWeight(.semibold).foregroundStyle(Ky.cinnabar)
            }
            if chart != nil {
                HStack(spacing: 10) {
                    Button {
                        peopleStore.upsert(Person(name: name.isEmpty ? "未命名" : name, gender: gender,
                                                  birthEpoch: birth.timeIntervalSince1970,
                                                  useLongitude: useLongitude, longitude: Double(longitudeText) ?? 107.8))
                        savedTip = true
                    } label: { Label("存入人物档案", systemImage: "person.crop.circle.badge.plus").font(.subheadline) }
                    if savedTip { Text("已存，下次可直接选人").font(.caption).foregroundStyle(Ky.jade) }
                }
            }
            Text("家里人建议到「人物档案」建档，建一次，八字、手相、案件都直接调人。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }
}

// 盘面结果（录入页与人物详情共用同一块，保证两处长得一模一样）
struct BaziResultView: View {
    let chart: BaziChart
    let name: String
    @State private var proMode = false
    @State private var timeLevel = 0        // 0 大运 1 流年 2 流月 3 流日（流时并入流日速查）
    @State private var selectedDayun = 0
    private var safeDayun: Int { chart.dayunGanZhi.isEmpty ? 0 : min(selectedDayun, chart.dayunGanZhi.count - 1) }
    @State private var selectedYear: Int? = nil
    @State private var flowDate = Date()
    @State private var flowHour = 12
    @State private var copied = false
    @State private var detailPillar = 0
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            plateCard
            shichenCard()
            HStack(spacing: 8) {
                Button {
                    let dy = chart.dayunGanZhi.enumerated().map { "\(chart.dayunStartYear($0.offset)) \($0.element)" }.joined(separator: "、")
                    UIPasteboard.general.string = "\(name.isEmpty ? "命盘" : name)：\(chart.pillars.joined(separator: " "))｜日主 \(chart.rizhu) 命宫 \(chart.mingGong) 身宫 \(chart.shenGong)｜起运 \(chart.qiyunDate)（\(chart.qiyunDirection)）｜大运：\(dy)"
                    copied = true
                } label: { Label(copied ? "已复制" : "复制盘面文本", systemImage: copied ? "checkmark" : "doc.on.doc").font(.caption) }
                .foregroundStyle(Ky.qingdai)
                Spacer()
                Text("发给谁都能直接粘贴看盘").font(.caption2).foregroundStyle(Ky.sub)
            }
            wuxingCard
            timeCard
            infoCard
            interpretLink
            yearlyLink
            lifePlanLink
            NavigationLink { PosterSheetView(chart: chart, name: name) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "photo.artframe").foregroundStyle(Ky.cinnabar)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("命盘海报 · 下载分享").font(.system(.subheadline, design: .serif)).fontWeight(.semibold)
                        Text("道教墨金风海报，1080×1920 高清导出存相册或发微信").font(.caption2).foregroundStyle(Ky.sub)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Ky.sub)
                }
                .padding(12).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain).foregroundStyle(Ky.ink)
        }
        .sheet(isPresented: $showDetail) { pillarDetailView(detailPillar) }
    }

    private var plateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? "命盘" : name).font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
                    Text("日主 \(chart.rizhu) · 日柱旬空 \(chart.xunKong)")
                        .font(.caption).foregroundStyle(Ky.sub)
                }
                Spacer()
                Picker("密度", selection: $proMode) {
                    Text("基本盘").tag(false); Text("专业细盘").tag(true)
                }.pickerStyle(.segmented).frame(width: 176)
            }
            pillarButtons()
            Text("点任一柱，弹出该柱详情卡（藏干 / 十神 / 长生 / 纳音 / 神煞）。")
                .font(.caption2).foregroundStyle(Ky.sub)
            plateGrid(chart)
        }
        .kyCard()
    }

    // 四柱点击详情：柱按钮行（格子式点选，不改行式盘面排版）
    private func pillarButtons() -> some View {
        let names = ["年柱", "月柱", "日柱", "时柱"]
        return HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                Button { detailPillar = i; showDetail = true } label: {
                    VStack(spacing: 2) {
                        Text(names[i]).font(.caption2).foregroundStyle(Ky.sub)
                        Text(chart.pillars[i]).font(.system(.callout, design: .serif)).fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(Ky.bg).clipShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).foregroundStyle(Ky.ink)
            }
        }
    }

    // 四柱详情卡：全部取自本盘已有字段（藏干/十神/长生/纳音/神煞），不新增断法
    private func pillarDetailView(_ i: Int) -> some View {
        let idx = min(max(i, 0), 3)
        let names = ["年柱", "月柱", "日柱", "时柱"]
        let sha = BaziTables.shenSha(chart)[idx]
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(names[idx]) \(chart.pillars[idx])")
                        .font(.system(.title3, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                    Spacer()
                    Button("关闭") { showDetail = false }.font(.subheadline).foregroundStyle(Ky.qingdai)
                }
                Text("天干十神：\(chart.stemShiShen[idx])").font(.subheadline).foregroundStyle(Ky.ink)
                Text("藏干：\(chart.hideGan[idx].joined(separator: " "))").font(.subheadline).foregroundStyle(Ky.ink)
                Text("藏干十神：\(chart.hideShiShen[idx].joined(separator: " "))").font(.subheadline).foregroundStyle(Ky.ink)
                Text("长生十二宫：\(chart.diShi[idx])").font(.subheadline).foregroundStyle(Ky.ink)
                Text("纳音：\(chart.naYin[idx])").font(.subheadline).foregroundStyle(Ky.ink)
                Text("神煞：\(sha.isEmpty ? "无" : sha.joined(separator: "、"))").font(.subheadline).foregroundStyle(Ky.ink)
                if idx == 2 {
                    Text("日柱旬空：\(chart.xunKong)").font(.subheadline).foregroundStyle(Ky.ink)
                }
                Text("藏干按本气在前排列；神煞为通行查表，只作辅助参考，不单独定吉凶。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
    }

    // 十二时辰对照：同日日干下十二时辰的时柱并排（未知时辰定盘用）
    private func shichenCard() -> some View {
        let branches = BaziTables.DZ
        let hours = [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22]
        let ranges = ["23–1", "1–3", "3–5", "5–7", "7–9", "9–11", "11–13", "13–15", "15–17", "17–19", "19–21", "21–23"]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("十二时辰对照（同日时柱）").font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
                Spacer()
                Text("本盘时柱 \(chart.timePillar)").font(.caption).foregroundStyle(Ky.sub)
            }
            Text("同一日干下十二时辰的时柱并排看：时辰未知时先按此表看差别，定盘后再看解盘。")
                .font(.caption2).foregroundStyle(Ky.sub)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(0..<12, id: \.self) { i in
                    let tp = BaziTables.timeGanZhi(dayStem: chart.rizhu.first!, hour: hours[i])
                    let isCurrent = branches[i] == chart.timePillar.last!
                    VStack(spacing: 2) {
                        Text("\(String(branches[i]))时 \(ranges[i])").font(.caption2).foregroundStyle(Ky.sub)
                        Text(tp).font(.system(.callout, design: .serif)).fontWeight(.semibold)
                        Text(BaziTables.shiShen(day: chart.rizhu.first!, stem: tp.first!))
                            .font(.caption2).foregroundStyle(Ky.gold)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(isCurrent ? Ky.gold.opacity(0.18) : Ky.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Text("时干按五鼠遁自日干推；夜子时（23 点后）时干按次日日干推，以本盘时柱为准。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private var wuxingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("五行力量").font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
            WuxingBarsView(percents: chart.wuxingPercents)
            Text("计法：天干各 1，藏干本气 1 / 中气 0.5 / 余气 0.3，归一化。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("岁运").font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
                Spacer()
                Text("起运 \(chart.qiyunDirection) · \(chart.qiyunDate)").font(.caption).foregroundStyle(Ky.sub)
            }
            TimeCapsuleBar(levels: ["大运", "流年", "流月", "流日", "流时"],
                           enabled: [true, true, true, true, false], selection: $timeLevel)
            if timeLevel <= 1 { timeNavRow() }
            switch timeLevel {
            case 0: dayunLevel
            case 1: liunianLevel
            case 2: liuyueLevel
            default: liuriLevel
            }
        }
        .kyCard()
    }

    // 岁运导航：‹ › 步进＋回本命年（回到今年所在的运年）；按钮为主、手势为辅
    private func timeNavRow() -> some View {
        HStack(spacing: 8) {
            Button { stepTime(-1) } label: {
                Label("上一步", systemImage: "chevron.left").font(.caption)
            }.foregroundStyle(Ky.qingdai)
            Spacer()
            Button { backToCurrentYear() } label: {
                Label("回本命年", systemImage: "house").font(.caption)
            }.foregroundStyle(Ky.cinnabar)
            Spacer()
            Button { stepTime(1) } label: {
                Label("下一步", systemImage: "chevron.right").font(.caption)
            }.foregroundStyle(Ky.qingdai)
        }
    }

    private func stepTime(_ d: Int) {
        if chart.dayunGanZhi.isEmpty { return }
        if timeLevel == 0 {
            selectedDayun = min(max(selectedDayun + d, 0), chart.dayunGanZhi.count - 1)
        } else if timeLevel == 1 {
            let old = safeDayun
            let start = chart.dayunStartYear(old)
            let cur = selectedYear ?? start
            let y = cur + d
            if y < start && old > 0 {
                selectedDayun = old - 1
                selectedYear = chart.dayunStartYear(old - 1) + 9
            } else if y > start + 9 && old < chart.dayunGanZhi.count - 1 {
                selectedDayun = old + 1
                selectedYear = chart.dayunStartYear(old + 1)
            } else {
                selectedYear = min(max(y, start), start + 9)
            }
        }
    }

    private func backToCurrentYear() {
        if chart.dayunGanZhi.isEmpty { return }
        let nowYear = Calendar.current.component(.year, from: Date())
        let first = chart.dayunStartYear(0)
        let last = chart.dayunStartYear(chart.dayunGanZhi.count - 1) + 9
        let target = min(max(nowYear, first), last)
        var di = 0
        for i in chart.dayunGanZhi.indices where chart.dayunStartYear(i) <= target { di = i }
        selectedDayun = di
        selectedYear = target
        timeLevel = 1
    }

    private var dayunLevel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chart.dayunGanZhi.indices, id: \.self) { i in
                        Button { selectedDayun = i; selectedYear = chart.dayunStartYear(i); timeLevel = 1 } label: {
                            VStack(spacing: 2) {
                                Text(chart.dayunGanZhi[i]).font(.system(.callout, design: .serif)).fontWeight(.semibold)
                                Text("\(chart.dayunStartYear(i)) 起").font(.caption2).foregroundStyle(Ky.sub)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(i == selectedDayun ? Ky.gold.opacity(0.18) : Ky.bg)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).foregroundStyle(Ky.ink)
                    }
                }
            }
            Text("点任一步大运，进到它的流年；也可左右滑切换大运。").font(.caption2).foregroundStyle(Ky.sub)
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width < -30 { stepTime(1) } else if v.translation.width > 30 { stepTime(-1) }
        })
    }

    private var liunianLevel: some View {
        let start = chart.dayunStartYear(safeDayun)
        let nowYear = Calendar.current.component(.year, from: Date())
        return VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                ForEach(0..<10, id: \.self) { k in
                    let y = start + k
                    let gz = BaziChart.yearGanZhi(y)
                    Button { selectedYear = y; timeLevel = 2 } label: {
                        VStack(spacing: 2) {
                            Text(gz).font(.system(.callout, design: .serif)).fontWeight(.semibold)
                            Text(String(y) + (y == nowYear ? " · 今" : "")).font(.caption2).foregroundStyle(Ky.sub)
                            Text(BaziTables.shiShen(day: chart.rizhu.first!, stem: gz.first!))
                                .font(.caption2).foregroundStyle(Ky.gold)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(y == nowYear ? Ky.gold.opacity(0.18) : Ky.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).foregroundStyle(Ky.ink)
                }
            }
            Text("\(chart.dayunGanZhi[safeDayun]) 运（\(start) 起）十年流年，干下小字为流年天干十神；点任意一年进流月，也可左右滑切换流年。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width < -30 { stepTime(1) } else if v.translation.width > 30 { stepTime(-1) }
        })
    }

    private var liuyueLevel: some View {
        let year = selectedYear ?? chart.dayunStartYear(safeDayun)
        let ygz = BaziChart.yearGanZhi(year)
        let branches: [(Character, String)] = [("寅", "正月"), ("卯", "二月"), ("辰", "三月"), ("巳", "四月"),
            ("午", "五月"), ("未", "六月"), ("申", "七月"), ("酉", "八月"), ("戌", "九月"), ("亥", "十月"),
            ("子", "冬月"), ("丑", "腊月")]
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(year) 年（\(ygz)）流月 · 以节气为界")
                .font(.callout).fontWeight(.semibold).foregroundStyle(Ky.ink)
            ForEach(branches.indices, id: \.self) { i in
                let gz = BaziTables.monthGanZhi(yearStem: ygz.first!, monthBranch: branches[i].0)
                HStack(spacing: 10) {
                    Text(branches[i].1).font(.caption).foregroundStyle(Ky.sub).frame(width: 34, alignment: .leading)
                    Text(gz).font(.system(.callout, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
                    Text(BaziTables.shiShen(day: chart.rizhu.first!, stem: gz.first!))
                        .font(.caption2).foregroundStyle(Ky.gold)
                    Spacer()
                    if let rel = BaziTables.relation(gz.last!, chart.monthPillar.last!) {
                        Text("\(rel)月令").font(.caption2).foregroundStyle(Ky.cinnabar)
                    }
                }
                .padding(.vertical, 4)
                Divider().opacity(0.35)
            }
            Text("流月干支按五虎遁自流年干推，月份以交节为界（寅月自立春起）；与月令的冲合单独标出。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }
    }

    private var liuriLevel: some View {
        let dp = BaziEngine.dayPillar(for: flowDate)
        let dayStemForTime: Character = flowHour == 23
            ? BaziEngine.dayPillar(for: flowDate.addingTimeInterval(86400)).first! : dp.first!
        let tp = BaziTables.timeGanZhi(dayStem: dayStemForTime, hour: flowHour)
        return VStack(alignment: .leading, spacing: 10) {
            DatePicker("选一天", selection: $flowDate, displayedComponents: [.date])
            Stepper("时刻：\(flowHour) 时（\(tp)）", value: $flowHour, in: 0...23)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("流日").font(.caption2).foregroundStyle(Ky.sub)
                    HStack(spacing: 6) {
                        Text(dp).font(.system(.title3, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        Text(BaziTables.shiShen(day: chart.rizhu.first!, stem: dp.first!))
                            .font(.caption).foregroundStyle(Ky.gold)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("流时").font(.caption2).foregroundStyle(Ky.sub)
                    HStack(spacing: 6) {
                        Text(tp).font(.system(.title3, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        Text(BaziTables.shiShen(day: chart.rizhu.first!, stem: tp.first!))
                            .font(.caption).foregroundStyle(Ky.gold)
                    }
                }
                Spacer()
            }
            if let rel = BaziTables.relation(dp.last!, chart.dayPillar.last!) {
                Text("流日支与命盘日支成「\(rel)」——日子落到自身宫位的引动，细读看解盘口径。")
                    .font(.caption).foregroundStyle(Ky.cinnabar)
            } else {
                Text("流日支与命盘日支无直接冲合。").font(.caption).foregroundStyle(Ky.sub)
            }
            Text("流日按晚子时口径（23 时后日柱不换、时干按次日日干推），与排盘一致。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("基本信息").font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
            Text("胎元 \(chart.taiYuan) · 胎息 \(chart.taiXi) · 命宫 \(chart.mingGong) · 身宫 \(chart.shenGong)")
                .font(.caption).foregroundStyle(Ky.ink)
            if !chart.siliText.isEmpty {
                Text("人元司令 \(chart.siliText)").font(.caption).foregroundStyle(Ky.ink)
            }
        }
        .kyCard()
    }

    private var interpretLink: some View {
        NavigationLink { InterpretView(chart: chart, name: name) } label: {
            HStack(spacing: 10) {
                Image(systemName: "text.book.closed").foregroundStyle(Ky.cinnabar)
                VStack(alignment: .leading, spacing: 2) {
                    Text("解盘 · 全维度").font(.system(.subheadline, design: .serif)).fontWeight(.semibold)
                    Text("25 个维度逐条说清：事业财运婚姻子女健康守年＋颜色数字方位＋注意事项与化解").font(.caption2).foregroundStyle(Ky.sub)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ky.sub)
            }
            .kyCard()
        }.buttonStyle(.plain).foregroundStyle(Ky.ink)
    }

    private var lifePlanLink: some View {
        NavigationLink { LifePlanView(chart: chart, name: name) } label: {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet.rectangle.portrait").foregroundStyle(Ky.cinnabar)
                VStack(alignment: .leading, spacing: 2) {
                    Text("逐年全程 · 人生规划").font(.system(.subheadline, design: .serif)).fontWeight(.semibold)
                    Text("1 岁到 88 岁逐年说清＋八阶段总规划：哪年进取、哪年守成").font(.caption2).foregroundStyle(Ky.sub)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ky.sub)
            }
            .kyCard()
        }.buttonStyle(.plain).foregroundStyle(Ky.ink)
    }

    private var yearlyLink: some View {
        NavigationLink { YearByYearView(chart: chart, name: name) } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock").foregroundStyle(Ky.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("逐年直断").font(.system(.subheadline, design: .serif)).fontWeight(.semibold)
                    Text("四查生成：引动分级＋岁运叠加＋喜忌称重，重断有门槛").font(.caption2).foregroundStyle(Ky.sub)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ky.sub)
            }
            .kyCard()
        }.buttonStyle(.plain).foregroundStyle(Ky.ink)
    }

    // 四柱表格：行＝维度，列＝四柱；专业细盘多三行（藏干十神/星运/纳音）
    private func plateGrid(_ ch: BaziChart) -> some View {
        let cols = ["年柱", "月柱", "日柱", "时柱"]
        return VStack(spacing: 0) {
            plateRow(cells: cols, header: true)
            if proMode { plateRow(cells: ch.stemShiShen, small: true) }
            plateRow(cells: ch.pillars.map { String($0.first!) }, big: true)
            plateRow(cells: ch.pillars.map { String($0.last!) }, big: true)
            plateRow(cells: ch.hideGan.map { $0.joined(separator: " ") }, small: true)
            if proMode {
                plateRow(cells: ch.hideShiShen.map { $0.joined(separator: " ") }, small: true, dim: true)
                plateRow(cells: ch.diShi, small: true)
                plateRow(cells: ch.naYin, small: true, dim: true)
                plateRow(cells: BaziTables.shenSha(ch).map { $0.joined(separator: " ") }, small: true, dim: true)
            }
        }
    }

    private func plateRow(cells: [String], header: Bool = false, big: Bool = false, small: Bool = false, dim: Bool = false) -> some View {
        HStack(spacing: 6) {
            ForEach(cells.indices, id: \.self) { i in
                Text(cells[i])
                    .font(header ? .caption2 : big ? .system(.title2, design: .serif).weight(.bold)
                          : small ? .caption : .callout)
                    .foregroundStyle(header ? Ky.sub : dim ? Ky.sub : (big && i == 2 ? Ky.cinnabar : Ky.ink))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, header ? 2 : big ? 5 : 3)
        .overlay(Divider().opacity(header ? 1 : 0.35), alignment: .bottom)
    }
}
