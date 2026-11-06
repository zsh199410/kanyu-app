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

    // 划动缓存：body 每求值一次就重算全盘是卡顿主因之一；按（出生时刻＋性别＋经度＋晚子时口径）缓存，口径改了即换键
    private static var paipanCache: [String: BaziChart] = [:]
    static func cachedPaipan(clock: Date, gender: String, longitude: Double?) -> BaziChart {
        let key = "\(clock.timeIntervalSince1970)-\(gender)-\(longitude ?? 0)-\(AppSettings.baziSect)"
        if let hit = paipanCache[key] { return hit }
        let c = paipan(clock: clock, gender: gender, longitude: longitude)
        if paipanCache.count > 64 { paipanCache.removeAll() }
        paipanCache[key] = c
        return c
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

// MARK: - 八字排盘页 v5（宋纸·青黛盘面：自动折叠录入卡＋四柱干支五行分色＋无重复表头＋可折叠十二时辰）

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
    @State private var inputCollapsed = false
    @StateObject private var palmStore = PalmRecordStore()

    private var inputSnapshot: String { "\(name)|\(gender)|\(birth.timeIntervalSince1970)|\(useLongitude)|\(longitudeText)" }
    private var isStale: Bool { chart != nil && chartSnapshot != inputSnapshot }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if chart != nil && inputCollapsed && !isStale {
                    collapsedInputBar
                } else {
                    inputCard
                }
                if let ch = chart {
                    BaziResultView(chart: ch, name: name)
                    NavigationLink {
                        HeCanPosterSheetView(
                            bazi: ch,
                            ziwei: ZiweiEngine.cachedChart(clock: birth, gender: gender,
                                                           longitude: useLongitude ? Double(longitudeText) : nil),
                            name: name,
                            palmLines: palmStore.records(for: name).map { "\($0.kind)：\($0.summary)" })
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "photo.artframe")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Ky.gold)
                                .frame(width: 34, height: 34)
                                .background(Ky.gold.opacity(0.13))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("合参海报导出").font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.ink)
                                Text("八字总断 · 紫微命宫 · 手相要点 一页合参").font(.caption2).foregroundStyle(Ky.sub)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Ky.sub)
                        }
                        .padding(12)
                        .background(Ky.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ky.line.opacity(0.85), lineWidth: 0.8))
                    }.buttonStyle(.plain)
                }
                HStack(spacing: 12) {
                    NavigationLink { GanZhiLookupView() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass.circle.fill")
                            Text("已知四柱？干支反查出生日期 ›")
                        }
                        .font(.caption).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                    }.buttonStyle(.plain)
                    Spacer()
                    NavigationLink { CaliberSettingsView() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                            Text("口径设置 ›")
                        }
                        .font(.caption).foregroundStyle(Ky.sub)
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 4)
            }
            .padding(16)
            .padding(.bottom, 36)
        }
        .background(Ky.bg)
        .navigationTitle("八字排盘")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Ky.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // 排盘后自动折叠为一行精致眉卡，释放首屏空间直接看盘
    private var collapsedInputBar: some View {
        let s = BirthInputView.solarOf(birth)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name.isEmpty ? "当前命盘" : name)
                        .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                    KyBadge(text: gender == "M" ? "乾造（男）" : "坤造（女）", color: gender == "M" ? Ky.qingdai : Ky.cinnabar)
                    if savedTip {
                        KyBadge(text: "已存档案", color: Ky.jade)
                    }
                }
                Text("公历 \(s.year)-\(String(format: "%02d-%02d %02d:%02d", s.month, s.day, s.hour, s.minute))" + (useLongitude ? " · 东经 \(longitudeText)°" : " · 钟表时间"))
                    .font(KyV2.tabular(12)).foregroundStyle(Ky.sub)
            }
            Spacer()
            if !savedTip {
                Button {
                    peopleStore.upsert(Person(name: name.isEmpty ? "未命名" : name, gender: gender,
                                              birthEpoch: birth.timeIntervalSince1970,
                                              useLongitude: useLongitude, longitude: Double(longitudeText) ?? 107.8))
                    savedTip = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.subheadline)
                        .padding(8)
                        .background(Ky.elevated)
                        .foregroundStyle(Ky.qingdai)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("存入人物档案")
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { inputCollapsed = false }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.below.rectangle")
                    Text("改生辰")
                }
                .font(.caption).fontWeight(.semibold)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Ky.qingdai.opacity(0.13))
                .foregroundStyle(Ky.qingdai)
                .clipShape(Capsule())
            }.buttonStyle(.plain)
        }
        .kyCard()
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                KySectionTitle(title: "生辰录入", trailing: "支持公农历与真太阳时")
                if chart != nil {
                    Button("收起") {
                        withAnimation(.easeInOut(duration: 0.2)) { inputCollapsed = true }
                    }
                    .font(.caption).foregroundStyle(Ky.qingdai)
                }
            }

            // 档案人物一键速选横栏（取代原版隐藏式 Menu，点一下即排盘）
            if !peopleStore.people.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Label("速选：", systemImage: "person.crop.rectangle.stack")
                            .font(.caption2).foregroundStyle(Ky.sub)
                        ForEach(peopleStore.people.prefix(8)) { p in
                            Button {
                                name = p.name; gender = p.gender; birth = p.birthDate
                                useLongitude = p.useLongitude; longitudeText = String(format: "%.1f", p.longitude)
                                chart = BaziEngine.paipan(clock: birth, gender: gender,
                                                          longitude: useLongitude ? Double(longitudeText) : nil)
                                chartSnapshot = inputSnapshot; savedTip = true; inputCollapsed = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text(p.name.isEmpty ? "未命名" : p.name).fontWeight(.medium)
                                    Text(p.gender == "M" ? "男" : "女").opacity(0.75)
                                }
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Ky.elevated)
                                .foregroundStyle(Ky.ink)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Ky.line, lineWidth: 0.7))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }

            // 姓名与性别同行排布，干净利落
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "person.text.rectangle").foregroundStyle(Ky.sub)
                    TextField("命主姓名（可留空）", text: $name)
                        .font(.subheadline)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Ky.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 9))

                Picker("性别", selection: $gender) {
                    Text("乾造（男）").tag("M")
                    Text("坤造（女）").tag("F")
                }
                .pickerStyle(.segmented)
                .frame(width: 156)
            }

            BirthInputView(clock: $birth, useLongitude: $useLongitude, longitudeText: $longitudeText)

            Button("立即排盘") {
                chart = BaziEngine.paipan(clock: birth, gender: gender,
                                          longitude: useLongitude ? Double(longitudeText) : nil)
                chartSnapshot = inputSnapshot; savedTip = false
                withAnimation(.easeInOut(duration: 0.2)) { inputCollapsed = true }
            }.buttonStyle(KyPrimaryButton())

            if isStale {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                    Text("上方生辰已修改，请点「立即排盘」刷新下方命盘。")
                }
                .font(.caption).fontWeight(.semibold).foregroundStyle(Ky.cinnabar)
            }
            if chart != nil {
                HStack(spacing: 10) {
                    Button {
                        peopleStore.upsert(Person(name: name.isEmpty ? "未命名" : name, gender: gender,
                                                  birthEpoch: birth.timeIntervalSince1970,
                                                  useLongitude: useLongitude, longitude: Double(longitudeText) ?? 107.8))
                        savedTip = true
                    } label: {
                        Label(savedTip ? "已存入人物档案" : "存入人物档案（三术共用）",
                              systemImage: savedTip ? "checkmark.circle.fill" : "person.crop.circle.badge.plus")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(savedTip ? Ky.jade : Ky.qingdai)
                    }.buttonStyle(.plain)
                    Spacer()
                }
            }
        }
        .kyCard()
    }
}

// 盘面结果（录入页与人物详情共用同一块）
struct BaziResultView: View {
    let chart: BaziChart
    let name: String
    @State private var proMode = true       // 默认开启专业细盘，干支藏干十神星运一次看全
    @State private var timeLevel = 0        // 0 大运 1 流年 2 流月 3 流日
    @State private var selectedDayun = 0
    private var safeDayun: Int { chart.dayunGanZhi.isEmpty ? 0 : min(selectedDayun, chart.dayunGanZhi.count - 1) }
    @State private var selectedYear: Int? = nil
    @State private var flowDate = Date()
    @State private var flowHour = 12
    @State private var copied = false
    @State private var detailPillar = 0
    @State private var showDetail = false
    @State private var showShichen = false  // 十二时辰对照默认折叠，不喧宾夺主

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            plateCard
            yucedanSummaryCard
            deepDiveGrid
            wuxingCard
            timeCard
            shichenCard()
            infoCard
        }
        .sheet(isPresented: $showDetail) { pillarDetailView(detailPillar) }
    }

    // MARK: - 易辰预测单式直断速览卡（对标预测单 7 大实务项：喜忌/行业/婚姻/财库一目了然；吉数吉色按喜用五行现算，不写死）
    private var yucedanSummaryCard: some View {
        let dayStem = chart.rizhu.first!
        let dayWx = BaziTables.wx[dayStem]?.0 ?? ""
        let pct = chart.wuxingPercents
        let shengWo = { switch dayWx { case "木": return "水"; case "火": return "木"; case "土": return "火"; case "金": return "土"; default: return "金" } }()
        let tong = (pct[KyV2.elementIndex(dayWx) ?? 0] + pct[KyV2.elementIndex(shengWo) ?? 0])
        let level = tong >= 55 ? "偏强" : (tong <= 40 ? "偏弱" : "中和")
        let ku = ["木": "未", "火": "戌", "土": "辰", "金": "丑", "水": "辰"][dayWx] ?? ""
        let kuCount = chart.pillars.filter { $0.hasSuffix(ku) }.count
        // 吉数吉色按喜用五行现算：偏弱喜生扶（印星＋比劫），否则喜克泄耗（食伤＋财＋官）
        let wxOrder = ["木", "火", "土", "金", "水"]
        let dayIdx = wxOrder.firstIndex(of: dayWx) ?? 2
        let xiWx: [String] = level == "偏弱" ? [shengWo, dayWx] : [wxOrder[(dayIdx + 1) % 5], wxOrder[(dayIdx + 2) % 5], wxOrder[(dayIdx + 3) % 5]]
        let numMap = ["木": "3、8", "火": "2、7", "土": "5、0", "金": "4、9", "水": "1、6"]
        let colorMap = ["木": "绿、青", "火": "红", "土": "黄", "金": "白、金", "水": "黑、蓝"]
        let xiNums = xiWx.compactMap { numMap[$0] }.joined(separator: "、")
        let xiColors = xiWx.compactMap { colorMap[$0] }.joined(separator: "、")

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                KySectionTitle(title: "八字预测单直断速览", trailing: "实务七项要诀")
                Spacer()
                NavigationLink { PosterSheetView(chart: chart, name: name) } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "photo.artframe")
                        Text("出预测单海报 ›")
                    }
                    .font(.caption2).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                }.buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("【喜用神】").font(.caption).fontWeight(.bold).foregroundStyle(Ky.cinnabar)
                    Text(level == "偏弱" ? "喜生扶（印星\(shengWo)、比劫\(dayWx)）· 调候温润为先" : "喜克泄耗（食伤、财星、官杀）· 忌再添重党")
                        .font(.caption).foregroundStyle(Ky.ink)
                    Spacer()
                    KyBadge(text: "身\(level)", color: level == "偏弱" ? Ky.gold : Ky.qingdai)
                }

                HStack(spacing: 8) {
                    Text("【财星财库】").font(.caption).fontWeight(.bold).foregroundStyle(Ky.gold)
                    Text(kuCount > 0 ? "原局见真财库「\(ku)」\(kuCount)处，财运聚散有存，防库逢冲动荡" : "原局无特定财库，周转流通为主，宜配置固定资产")
                        .font(.caption).foregroundStyle(Ky.ink)
                }

                HStack(spacing: 8) {
                    Text("【事业赛道】").font(.caption).fontWeight(.bold).foregroundStyle(Ky.qingdai)
                    Text("优先契合喜用五行与强神行业：规矩平台/技术变现两利，方位宜向喜用方扩展")
                        .font(.caption).foregroundStyle(Ky.ink)
                }

                HStack(spacing: 8) {
                    Text("【吉数吉色】").font(.caption).fontWeight(.bold).foregroundStyle(Ky.jade)
                    Text("日常喜用 \(xiNums)（\(xiWx.joined(separator: "、"))）数；穿衣家居宜\(xiColors)")
                        .font(.caption).foregroundStyle(Ky.ink)
                }
            }
            .padding(11)
            .background(Ky.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .kyCard()
    }

    // MARK: - 核心四柱命盘卡（消除旧版重复四柱按钮行，直接在四柱列点击查看详情，干支按五行分色）
    private var plateCard: some View {
        let dayEl = KyV2.element(ofChar: chart.rizhu.first!)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(name.isEmpty ? "四柱命盘" : name)
                            .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        KyBadge(text: "日主 \(chart.rizhu)\(dayEl)", color: KyV2.color(forChar: chart.rizhu.first!))
                        KyBadge(text: "旬空 \(chart.xunKong)", color: Ky.gold)
                    }
                    Text("胎元 \(chart.taiYuan) · 命宫 \(chart.mingGong) · 身宫 \(chart.shenGong)")
                        .font(.caption2).foregroundStyle(Ky.sub)
                }
                Spacer()
                Picker("密度", selection: $proMode) {
                    Text("简盘").tag(false)
                    Text("细盘").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 116)
            }

            plateGrid(chart)

            HStack {
                Text("点任意一柱可展开藏干、长生、纳音与神煞详解")
                    .font(.caption2).foregroundStyle(Ky.sub)
                Spacer()
                Button {
                    let dy = chart.dayunGanZhi.enumerated().map { "\(chart.dayunStartYear($0.offset)) \($0.element)" }.joined(separator: "、")
                    UIPasteboard.general.string = "\(name.isEmpty ? "命盘" : name)：\(chart.pillars.joined(separator: " "))｜日主 \(chart.rizhu) 命宫 \(chart.mingGong) 身宫 \(chart.shenGong)｜起运 \(chart.qiyunDate)（\(chart.qiyunDirection)）｜大运：\(dy)"
                    copied = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        Text(copied ? "已复制文本" : "复制盘面")
                    }
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundStyle(copied ? Ky.jade : Ky.qingdai)
                }.buttonStyle(.plain)
            }
        }
        .kyCard()
    }

    // 四柱并排交互卡片：每一柱是一列独立可点击的宋纸柱卡，干支自带五行色＋五行小字双编码
    private func plateGrid(_ ch: BaziChart) -> some View {
        let cols = ["年柱", "月柱", "日柱", "时柱"]
        let palaces = ["祖上/根基", "父母/月令", "自身/配偶", "子女/晚景"]
        let shaList = BaziTables.shenSha(ch)
        return HStack(alignment: .top, spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                let gz = ch.pillars[i]
                let stem = gz.first!
                let branch = gz.last!
                let stemEl = KyV2.element(ofChar: stem)
                let branchEl = KyV2.element(ofChar: branch)
                let isDay = (i == 2)
                Button {
                    detailPillar = i
                    showDetail = true
                } label: {
                    VStack(spacing: 6) {
                        // 柱头＋宫位
                        VStack(spacing: 1) {
                            Text(cols[i])
                                .font(.caption).fontWeight(.bold)
                                .foregroundStyle(isDay ? Ky.cinnabar : Ky.ink)
                            Text(palaces[i])
                                .font(.system(size: 9))
                                .foregroundStyle(Ky.sub)
                        }
                        .padding(.bottom, 2)

                        // 天干十神
                        Text(isDay ? "日主" : ch.stemShiShen[i])
                            .font(.caption2).fontWeight(.semibold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((isDay ? Ky.cinnabar : Ky.qingdai).opacity(0.12))
                            .foregroundStyle(isDay ? Ky.cinnabar : Ky.qingdai)
                            .clipShape(Capsule())

                        // 天干大字（五行分色＋五行小标）
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(stem))
                                .font(.system(size: 28, weight: .bold, design: .serif))
                                .foregroundStyle(KyV2.color(forChar: stem))
                            Text(stemEl)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(KyV2.color(forChar: stem).opacity(0.85))
                        }

                        // 地支大字（五行分色＋五行小标）
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(branch))
                                .font(.system(size: 28, weight: .bold, design: .serif))
                                .foregroundStyle(KyV2.color(forChar: branch))
                            Text(branchEl)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(KyV2.color(forChar: branch).opacity(0.85))
                        }

                        Divider().opacity(0.5)

                        // 藏干与藏干十神（本气置顶加粗）
                        VStack(spacing: 2) {
                            ForEach(ch.hideGan[i].indices, id: \.self) { hi in
                                let hg = ch.hideGan[i][hi]
                                let hss = ch.hideShiShen[i].indices.contains(hi) ? ch.hideShiShen[i][hi] : ""
                                HStack(spacing: 3) {
                                    Text(hg)
                                        .font(.system(size: 11, weight: hi == 0 ? .bold : .regular))
                                        .foregroundStyle(KyV2.color(forChar: hg.first ?? "甲"))
                                    Text(proMode ? hss : KyV2.shiShenShort(hss))
                                        .font(.system(size: 10, weight: hi == 0 ? .medium : .regular))
                                        .foregroundStyle(hi == 0 ? Ky.ink : Ky.sub)
                                }
                            }
                        }
                        .frame(minHeight: 46, alignment: .top)

                        if proMode {
                            Divider().opacity(0.4)
                            // 星运（长生十二宫）＋纳音
                            VStack(spacing: 2) {
                                Text("长生 · \(ch.diShi[i])")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Ky.ink)
                                Text(ch.naYin[i])
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(Ky.sub)
                                if !shaList[i].isEmpty {
                                    Text(shaList[i].prefix(2).joined(separator: " "))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(Ky.gold)
                                        .lineLimit(1)
                                } else {
                                    Text("—")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Ky.sub.opacity(0.4))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10).padding(.horizontal, 4)
                    .background(isDay ? Ky.cinnabar.opacity(0.04) : Ky.elevated.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(isDay ? Ky.cinnabar.opacity(0.55) : Ky.line, lineWidth: isDay ? 1.3 : 0.7)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("四柱：年柱 \(ch.pillars[0])，月柱 \(ch.pillars[1])，日柱 \(ch.pillars[2])，时柱 \(ch.pillars[3])，日主 \(ch.rizhu)")
    }

    // MARK: - 四大深度模块 2×2 导航矩阵（解盘25维 / 逐年四查 / 1-88岁规划 / 命盘海报）
    private var deepDiveGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            NavigationLink { InterpretView(chart: chart, name: name) } label: {
                hubCard(icon: "text.book.closed.fill", title: "解盘 · 25维详批",
                        subtitle: "格局喜忌 · 六亲事业 · 依据链", color: Ky.qingdai)
            }.buttonStyle(.plain)

            NavigationLink { YearByYearView(chart: chart, name: name) } label: {
                hubCard(icon: "calendar.badge.clock", title: "逐年直断 · 四查",
                        subtitle: "当前运20年 · 关口与主线定级", color: Ky.cinnabar)
            }.buttonStyle(.plain)

            NavigationLink { LifePlanView(chart: chart, name: name) } label: {
                hubCard(icon: "list.bullet.rectangle.portrait.fill", title: "1–88岁全程规划",
                        subtitle: "人生八阶段总纲 · 逐年进退策略", color: Ky.jade)
            }.buttonStyle(.plain)

            NavigationLink { PosterSheetView(chart: chart, name: name) } label: {
                hubCard(icon: "photo.artframe", title: "命盘海报导出",
                        subtitle: "宋纸青黛 / 墨金 / 宣纸高清图", color: Ky.gold)
            }.buttonStyle(.plain)
        }
    }

    private func hubCard(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.ink).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(Ky.sub).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Ky.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ky.line.opacity(0.85), lineWidth: 0.8))
    }

    // 四柱详情弹窗 Sheet
    private func pillarDetailView(_ i: Int) -> some View {
        let idx = min(max(i, 0), 3)
        let names = ["年柱（祖上/根基宫）", "月柱（父母/提纲宫）", "日柱（自身/配偶宫）", "时柱（子女/晚景宫）"]
        let sha = BaziTables.shenSha(chart)[idx]
        let gz = chart.pillars[idx]
        let stem = gz.first!
        let branch = gz.last!
        return NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        HStack(spacing: 4) {
                            Text(String(stem)).foregroundStyle(KyV2.color(forChar: stem))
                            Text(String(branch)).foregroundStyle(KyV2.color(forChar: branch))
                        }
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Ky.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(names[idx]).font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                            Text("天干：\(stem)（\(KyV2.element(ofChar: stem)) · \(chart.stemShiShen[idx])）")
                                .font(.caption).foregroundStyle(Ky.sub)
                            Text("地支：\(branch)（\(KyV2.element(ofChar: branch)) · 长生处「\(chart.diShi[idx])」）")
                                .font(.caption).foregroundStyle(Ky.sub)
                        }
                        Spacer()
                    }.kyCard()

                    VStack(alignment: .leading, spacing: 8) {
                        KySectionTitle(title: "藏干与人元（本气/中气/余气）")
                        ForEach(chart.hideGan[idx].indices, id: \.self) { hi in
                            let role = hi == 0 ? "本气（主根）" : (hi == 1 ? "中气" : "余气")
                            let hg = chart.hideGan[idx][hi]
                            let hss = chart.hideShiShen[idx].indices.contains(hi) ? chart.hideShiShen[idx][hi] : ""
                            HStack {
                                KyBadge(text: role, color: hi == 0 ? Ky.qingdai : Ky.sub)
                                Text("\(hg)（\(KyV2.element(ofChar: hg.first ?? "甲"))）")
                                    .font(.callout).fontWeight(.bold)
                                    .foregroundStyle(KyV2.color(forChar: hg.first ?? "甲"))
                                Spacer()
                                Text(hss).font(.callout).fontWeight(.medium).foregroundStyle(Ky.ink)
                            }
                            .padding(.vertical, 3)
                        }
                    }.kyCard()

                    VStack(alignment: .leading, spacing: 8) {
                        KySectionTitle(title: "星运 · 纳音 · 神煞")
                        HStack {
                            Text("长生十二宫").font(.caption).foregroundStyle(Ky.sub).frame(width: 84, alignment: .leading)
                            Text(chart.diShi[idx]).font(.callout).fontWeight(.semibold).foregroundStyle(Ky.ink)
                            Spacer()
                        }
                        HStack {
                            Text("纳音五行").font(.caption).foregroundStyle(Ky.sub).frame(width: 84, alignment: .leading)
                            Text(chart.naYin[idx]).font(.callout).foregroundStyle(Ky.ink)
                            Spacer()
                        }
                        if idx == 2 {
                            HStack {
                                Text("日柱旬空").font(.caption).foregroundStyle(Ky.sub).frame(width: 84, alignment: .leading)
                                Text(chart.xunKong).font(.callout).fontWeight(.semibold).foregroundStyle(Ky.cinnabar)
                                Spacer()
                            }
                        }
                        HStack(alignment: .top) {
                            Text("本柱神煞").font(.caption).foregroundStyle(Ky.sub).frame(width: 84, alignment: .leading)
                            Text(sha.isEmpty ? "无特定神煞" : sha.joined(separator: "、"))
                                .font(.callout).foregroundStyle(sha.isEmpty ? Ky.sub : Ky.gold)
                            Spacer()
                        }
                        Text("注：藏干以本气为立格与通根之主；神煞属《三命通会》辅助层，随格局增减分量，不单凭神煞定吉凶。")
                            .font(.caption2).foregroundStyle(Ky.sub).padding(.top, 4)
                    }.kyCard()
                }.padding(16)
            }
            .background(Ky.bg)
            .navigationTitle("\(["年柱", "月柱", "日柱", "时柱"][idx])详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showDetail = false }.foregroundStyle(Ky.qingdai)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // 十二时辰对照：改为可折叠抽屉（默认收起，保持页面清爽；点击一键展开）
    private func shichenCard() -> some View {
        let branches = BaziTables.DZ
        let hours = [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22]
        let ranges = ["23–1", "1–3", "3–5", "5–7", "7–9", "9–11", "11–13", "13–15", "15–17", "17–19", "19–21", "21–23"]
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showShichen.toggle() }
            } label: {
                HStack {
                    KySectionTitle(title: "同日十二时辰对照", trailing: "本盘时柱 \(chart.timePillar)")
                    Image(systemName: showShichen ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(Ky.qingdai)
                }
            }.buttonStyle(.plain)

            if showShichen {
                Text("同一日干下十二时辰的时柱并排：生辰分钟临界或时辰不详时，可在此对照相邻时辰的十神差异。")
                    .font(.caption2).foregroundStyle(Ky.sub)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(0..<12, id: \.self) { i in
                        let tp = BaziTables.timeGanZhi(dayStem: chart.rizhu.first!, hour: hours[i])
                        let isCurrent = branches[i] == chart.timePillar.last!
                        VStack(spacing: 2) {
                            Text("\(String(branches[i]))时 \(ranges[i])").font(.caption2).foregroundStyle(Ky.sub)
                            Text(tp).font(.system(.callout, design: .serif)).fontWeight(.bold)
                                .foregroundStyle(isCurrent ? Ky.qingdai : Ky.ink)
                            Text(BaziTables.shiShen(day: chart.rizhu.first!, stem: tp.first!))
                                .font(.caption2).foregroundStyle(isCurrent ? Ky.cinnabar : Ky.gold)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(isCurrent ? Ky.qingdai.opacity(0.14) : Ky.elevated)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isCurrent ? Ky.qingdai : Color.clear, lineWidth: 1.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                Text("口径：时干按五鼠遁自日干推；夜子时（23 点后）时干按次日日干推，以本盘时柱为准。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }
        }
        .kyCard()
    }

    private var wuxingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            KySectionTitle(title: "五行力量与气势", trailing: "天干＋藏干加权")
            WuxingBarsView(percents: chart.wuxingPercents)
            Text("计法：天干各 1.0，地支藏干本气 1.0 / 中气 0.5 / 余气 0.3，归一化百分比；强弱取用仍以月令提纲与本气通根为纲。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                KySectionTitle(title: "岁运推演", trailing: "起运 \(chart.qiyunDirection) · \(chart.qiyunDate)")
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

    private func timeNavRow() -> some View {
        HStack(spacing: 8) {
            Button { stepTime(-1) } label: {
                Label("上一步", systemImage: "chevron.left")
                    .font(.caption).fontWeight(.medium)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Ky.elevated).clipShape(Capsule())
            }.foregroundStyle(Ky.qingdai)
            Spacer()
            Button { backToCurrentYear() } label: {
                Label("定位今年", systemImage: "scope")
                    .font(.caption).fontWeight(.semibold)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Ky.cinnabar.opacity(0.12)).clipShape(Capsule())
            }.foregroundStyle(Ky.cinnabar)
            Spacer()
            Button { stepTime(1) } label: {
                Label("下一步", systemImage: "chevron.right")
                    .font(.caption).fontWeight(.medium)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Ky.elevated).clipShape(Capsule())
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
        let nowYear = Calendar.current.component(.year, from: Date())
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chart.dayunGanZhi.indices, id: \.self) { i in
                        let gz = chart.dayunGanZhi[i]
                        let startY = chart.dayunStartYear(i)
                        let isCurYun = (nowYear >= startY && nowYear <= startY + 9)
                        let isSel = (i == selectedDayun)
                        let ss = BaziTables.shiShen(day: chart.rizhu.first!, stem: gz.first!)
                        Button { selectedDayun = i; selectedYear = startY; timeLevel = 1 } label: {
                            VStack(spacing: 4) {
                                HStack(spacing: 2) {
                                    Text("\(startY)")
                                        .font(KyV2.tabular(10, weight: .medium))
                                    if isCurYun {
                                        Text("当前").font(.system(size: 8, weight: .bold))
                                            .padding(.horizontal, 4).padding(.vertical, 1)
                                            .background(Ky.cinnabar).foregroundStyle(.white).clipShape(Capsule())
                                    }
                                }
                                .foregroundStyle(isSel ? Color.white.opacity(0.9) : Ky.sub)

                                Text(gz)
                                    .font(.system(.title3, design: .serif)).fontWeight(.bold)
                                    .foregroundStyle(isSel ? Color.white : Ky.ink)

                                Text(ss)
                                    .font(.caption2)
                                    .foregroundStyle(isSel ? Color.white.opacity(0.9) : Ky.gold)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(isSel ? Ky.qingdai : (isCurYun ? Ky.gold.opacity(0.14) : Ky.elevated))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isCurYun && !isSel ? Ky.gold : Color.clear, lineWidth: 1.2)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }
            }
            Text("点任一步大运直接下钻该运十年流年；标「当前」者为今年所在大运。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width < -30 { stepTime(1) } else if v.translation.width > 30 { stepTime(-1) }
        })
    }

    private var liunianLevel: some View {
        let start = chart.dayunStartYear(safeDayun)
        let nowYear = Calendar.current.component(.year, from: Date())
        return VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(0..<10, id: \.self) { k in
                    let y = start + k
                    let gz = BaziChart.yearGanZhi(y)
                    let isNow = (y == nowYear)
                    let isSel = (selectedYear == y)
                    Button { selectedYear = y; timeLevel = 2 } label: {
                        VStack(spacing: 3) {
                            Text(String(y) + (isNow ? "·今" : ""))
                                .font(KyV2.tabular(10, weight: isNow ? .bold : .regular))
                                .foregroundStyle(isSel ? Color.white.opacity(0.9) : (isNow ? Ky.cinnabar : Ky.sub))
                            Text(gz)
                                .font(.system(.callout, design: .serif)).fontWeight(.bold)
                                .foregroundStyle(isSel ? Color.white : Ky.ink)
                            Text(BaziTables.shiShen(day: chart.rizhu.first!, stem: gz.first!))
                                .font(.system(size: 10))
                                .foregroundStyle(isSel ? Color.white.opacity(0.9) : Ky.gold)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(isSel ? Ky.qingdai : (isNow ? Ky.gold.opacity(0.18) : Ky.elevated))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(isNow && !isSel ? Ky.cinnabar.opacity(0.6) : Color.clear, lineWidth: 1.1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
            }
            Text("\(chart.dayunGanZhi[safeDayun])运（\(start)–\(start + 9)）十年流年：点任一年进流月。")
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
            HStack {
                Text("\(year) 年（\(ygz)）十二节气流月")
                    .font(.callout).fontWeight(.bold).foregroundStyle(Ky.ink)
                Spacer()
                Button("返回流年") { timeLevel = 1 }.font(.caption).foregroundStyle(Ky.qingdai)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(branches.indices, id: \.self) { i in
                    let gz = BaziTables.monthGanZhi(yearStem: ygz.first!, monthBranch: branches[i].0)
                    let rel = BaziTables.relation(gz.last!, chart.monthPillar.last!)
                    VStack(spacing: 2) {
                        Text(branches[i].1).font(.caption2).foregroundStyle(Ky.sub)
                        Text(gz).font(.system(.callout, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        Text(BaziTables.shiShen(day: chart.rizhu.first!, stem: gz.first!))
                            .font(.system(size: 10)).foregroundStyle(Ky.gold)
                        if let r = rel {
                            Text("\(r)月令").font(.system(size: 9, weight: .bold)).foregroundStyle(Ky.cinnabar)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(rel != nil ? Ky.cinnabar.opacity(0.08) : Ky.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Text("流月干支按五虎遁自流年干推，以节气交节为界（寅月自立春起）。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }
    }

    private var liuriLevel: some View {
        let dp = BaziEngine.dayPillar(for: flowDate)
        let dayStemForTime: Character = flowHour == 23
            ? BaziEngine.dayPillar(for: flowDate.addingTimeInterval(86400)).first! : dp.first!
        let tp = BaziTables.timeGanZhi(dayStem: dayStemForTime, hour: flowHour)
        return VStack(alignment: .leading, spacing: 10) {
            Text("选定流日").font(.subheadline).fontWeight(.medium).foregroundStyle(Ky.ink)
            KyChineseDatePicker(date: $flowDate)
            Stepper("选定流时：\(flowHour):00（\(tp)时）", value: $flowHour, in: 0...23)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("流日干支").font(.caption2).foregroundStyle(Ky.sub)
                    HStack(spacing: 6) {
                        Text(dp).font(.system(.title3, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        KyBadge(text: BaziTables.shiShen(day: chart.rizhu.first!, stem: dp.first!), color: Ky.gold)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).kySubCard()

                VStack(alignment: .leading, spacing: 3) {
                    Text("流时干支").font(.caption2).foregroundStyle(Ky.sub)
                    HStack(spacing: 6) {
                        Text(tp).font(.system(.title3, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        KyBadge(text: BaziTables.shiShen(day: chart.rizhu.first!, stem: tp.first!), color: Ky.qingdai)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).kySubCard()
            }
            if let rel = BaziTables.relation(dp.last!, chart.dayPillar.last!) {
                Text("流日支与命盘日支成「\(rel)」——自身与配偶宫位受引动，当日行事宜稳。")
                    .font(.caption).foregroundStyle(Ky.cinnabar)
            } else {
                Text("流日支与命盘日支无直接刑冲合会。")
                    .font(.caption).foregroundStyle(Ky.sub)
            }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            KySectionTitle(title: "命盘附元", trailing: "古法三垣与司令")
            HStack(spacing: 16) {
                Text("胎元：\(chart.taiYuan)").font(.caption).foregroundStyle(Ky.ink)
                Text("胎息：\(chart.taiXi)").font(.caption).foregroundStyle(Ky.ink)
                Text("命宫：\(chart.mingGong)").font(.caption).foregroundStyle(Ky.ink)
                Text("身宫：\(chart.shenGong)").font(.caption).foregroundStyle(Ky.ink)
            }
            if !chart.siliText.isEmpty {
                Text("月令人元分野：\(chart.siliText)").font(.caption).foregroundStyle(Ky.sub)
            }
        }
        .kyCard()
    }
}


// MARK: - 四柱干支反查出生日期（对标问真/文墨高阶能力：五虎遁自动定月干、五鼠遁自动定时干、60日周期跳步毫秒级检索）
struct GanZhiLookupView: View {
    private static let stems: [Character] = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    private static let branches: [Character] = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    private static let monthBranches: [Character] = ["寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥", "子", "丑"]
    private static let jiazi60: [String] = (0..<60).map { i in
        String(stems[i % 10]) + String(branches[i % 12])
    }

    @State private var yearGZ = "甲辰"
    @State private var monthBranch: Character = "子"
    @State private var dayGZ = "己未"
    @State private var hourBranch: Character = "未"
    @State private var startYear = 1950
    @State private var endYear = 2035
    @State private var gender = "M"
    @State private var results: [MatchedBirth] = []
    @State private var searched = false

    struct MatchedBirth: Identifiable {
        let id = UUID()
        let date: Date
        let solarText: String
        let lunarText: String
        let pillars: [String]
    }

    // 五虎遁由年干自动推导月柱
    private var derivedMonthGZ: String {
        BaziTables.monthGanZhi(yearStem: yearGZ.first!, monthBranch: monthBranch)
    }

    // 五鼠遁由日干自动推导时柱
    private var derivedTimeGZ: String {
        let hIdx = Self.branches.firstIndex(of: hourBranch) ?? 0
        let hour = (hIdx * 2) % 24
        return BaziTables.timeGanZhi(dayStem: dayGZ.first!, hour: hour)
    }

    private func runSearch() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let loY = min(startYear, endYear)
        let hiY = max(startYear, endYear)
        let hIdx = Self.branches.firstIndex(of: hourBranch) ?? 6
        let sampleHour = hIdx == 0 ? 0 : (hIdx * 2)

        // 先找出年柱等于 yearGZ 的所有候选公历年份（含立春跨年边界，故每个甲子年查当年与次年 1–2 月）
        var candidateYears: [Int] = []
        for y in loY...hiY {
            let gz = BaziChart.yearGanZhi(y)
            if gz == yearGZ {
                candidateYears.append(y)
            }
        }

        // 2000-01-01 为戊午日（60甲子序号 54）
        let anchorDate = cal.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: 12, minute: 0))!
        let targetDayIdx = Self.jiazi60.firstIndex(of: dayGZ) ?? 0
        let anchorDayIdx = 54 // 戊午

        var found: [MatchedBirth] = []
        for cy in candidateYears {
            // 扫描从 cy 年 1 月 20 日 到 cy+1 年 2 月 15 日（完整覆盖立春交界）
            guard let winStart = cal.date(from: DateComponents(year: cy, month: 1, day: 20, hour: 12, minute: 0)),
                  let winEnd = cal.date(from: DateComponents(year: cy + 1, month: 2, day: 15, hour: 12, minute: 0)) else { continue }
            let diffDays = cal.dateComponents([.day], from: anchorDate, to: winStart).day ?? 0
            let startIdx = ((anchorDayIdx + diffDays) % 60 + 60) % 60
            let delta = (targetDayIdx - startIdx + 60) % 60
            guard var cur = cal.date(byAdding: .day, value: delta, to: winStart) else { continue }

            while cur <= winEnd {
                let c = cal.dateComponents([.year, .month, .day], from: cur)
                if let y = c.year, let m = c.month, let d = c.day {
                    let s = Solar.fromYmdHms(year: y, month: m, day: d, hour: sampleHour, minute: 30)
                    let ec = s.lunar.eightChar
                    ec.sect = AppSettings.baziSect
                    if ec.year == yearGZ && ec.month == derivedMonthGZ && ec.day == dayGZ && ec.time == derivedTimeGZ {
                        if let exactDate = cal.date(from: DateComponents(year: y, month: m, day: d, hour: sampleHour, minute: 0)) {
                            let l = s.lunar
                            found.append(MatchedBirth(
                                date: exactDate,
                                solarText: "公历 \(y)年\(String(format: "%02d", m))月\(String(format: "%02d", d))日 \(hourBranch)时（\(String(format: "%02d:00", sampleHour))）",
                                lunarText: "农历 \(l.yearInGanZhi)年\(l.monthInChinese)月\(l.dayInChinese) · \(hourBranch)时",
                                pillars: [ec.year, ec.month, ec.day, ec.time]
                            ))
                        }
                    }
                }
                guard let next = cal.date(byAdding: .day, value: 60, to: cur) else { break }
                cur = next
            }
        }
        results = found
        searched = true
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    KySectionTitle(title: "四柱设定", trailing: "五虎遁/五鼠遁自动联动")

                    // 当前预览四柱
                    HStack(spacing: 10) {
                        pillarPreviewBox("年柱", yearGZ)
                        pillarPreviewBox("月柱（自动推干）", derivedMonthGZ)
                        pillarPreviewBox("日柱", dayGZ)
                        pillarPreviewBox("时柱（自动推干）", derivedTimeGZ)
                    }

                    Divider()

                    HStack {
                        Text("1. 选定年柱（六十甲子）").font(.subheadline).fontWeight(.medium).foregroundStyle(Ky.ink)
                        Spacer()
                        Picker("年柱", selection: $yearGZ) {
                            ForEach(Self.jiazi60, id: \.self) { gz in Text(gz).tag(gz) }
                        }.pickerStyle(.menu).tint(Ky.qingdai)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("2. 选定月支（月干按五虎遁自动配为 \(derivedMonthGZ)）").font(.subheadline).fontWeight(.medium).foregroundStyle(Ky.ink)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                            ForEach(Self.monthBranches, id: \.self) { mb in
                                let active = monthBranch == mb
                                let mgz = BaziTables.monthGanZhi(yearStem: yearGZ.first!, monthBranch: mb)
                                Button { monthBranch = mb } label: {
                                    Text(mgz)
                                        .font(.system(.callout, design: .serif)).fontWeight(active ? .bold : .regular)
                                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                                        .background(active ? Ky.qingdai : Ky.elevated)
                                        .foregroundStyle(active ? Color.white : Ky.ink)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }.buttonStyle(.plain)
                            }
                        }
                    }

                    HStack {
                        Text("3. 选定日柱（六十甲子）").font(.subheadline).fontWeight(.medium).foregroundStyle(Ky.ink)
                        Spacer()
                        Picker("日柱", selection: $dayGZ) {
                            ForEach(Self.jiazi60, id: \.self) { gz in Text(gz).tag(gz) }
                        }.pickerStyle(.menu).tint(Ky.qingdai)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("4. 选定时支（时干按五鼠遁自动配为 \(derivedTimeGZ)）").font(.subheadline).fontWeight(.medium).foregroundStyle(Ky.ink)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                            ForEach(Self.branches, id: \.self) { hb in
                                let active = hourBranch == hb
                                let hIdx = Self.branches.firstIndex(of: hb) ?? 0
                                let tgz = BaziTables.timeGanZhi(dayStem: dayGZ.first!, hour: (hIdx * 2) % 24)
                                Button { hourBranch = hb } label: {
                                    Text(tgz)
                                        .font(.system(.callout, design: .serif)).fontWeight(active ? .bold : .regular)
                                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                                        .background(active ? Ky.qingdai : Ky.elevated)
                                        .foregroundStyle(active ? Color.white : Ky.ink)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }.buttonStyle(.plain)
                            }
                        }
                    }

                    HStack {
                        Text("查询年份范围").font(.caption).foregroundStyle(Ky.sub)
                        Spacer()
                        Stepper("\(startYear)", value: $startYear, in: 1901...2090).labelsHidden()
                        Text("\(startYear) – \(endYear) 年").font(KyV2.tabular(13, weight: .bold)).foregroundStyle(Ky.ink)
                        Stepper("\(endYear)", value: $endYear, in: 1910...2099).labelsHidden()
                    }

                    Picker("排盘性别", selection: $gender) {
                        Text("乾造（男）").tag("M")
                        Text("坤造（女）").tag("F")
                    }.pickerStyle(.segmented)

                    Button("反查匹配生辰") {
                        runSearch()
                    }.buttonStyle(KyPrimaryButton())
                }.kyCard()

                if searched {
                    KySectionTitle(title: "反查结果", trailing: "共找到 \(results.count) 个匹配时辰")
                    if results.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.exclamationmark").font(.title2).foregroundStyle(Ky.cinnabar)
                            Text("在 \(min(startYear, endYear))–\(max(startYear, endYear)) 年间未找到该四柱组合")
                                .font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
                            Text("原因：该年柱的此节气月内正好未逢「\(dayGZ)」日（一月约 30 天而甲子周期为 60 天，故每个月仅有约一半日柱出现），可换相邻年份或扩大年份范围再查。")
                                .font(.caption).foregroundStyle(Ky.sub).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(18).kyCard()
                    } else {
                        ForEach(results) { item in
                            NavigationLink {
                                ScrollView {
                                    BaziResultView(
                                        chart: BaziEngine.cachedPaipan(clock: item.date, gender: gender, longitude: nil),
                                        name: item.pillars.joined(separator: " ")
                                    )
                                    .padding(16)
                                }
                                .background(Ky.bg)
                                .navigationTitle(item.pillars.joined(separator: " "))
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.solarText)
                                            .font(KyV2.tabular(14, weight: .bold)).foregroundStyle(Ky.ink)
                                        Text(item.lunarText)
                                            .font(.caption).foregroundStyle(Ky.sub)
                                    }
                                    Spacer()
                                    KyBadge(text: "看全盘 ›", color: Ky.qingdai, filled: true)
                                }
                                .kyCard()
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 36)
        }
        .background(Ky.bg)
        .navigationTitle("四柱干支反查")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !searched { runSearch() }
        }
    }

    private func pillarPreviewBox(_ label: String, _ gz: String) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 9.5)).foregroundStyle(Ky.sub).lineLimit(1)
            HStack(spacing: 2) {
                Text(String(gz.first!)).foregroundStyle(KyV2.color(forChar: gz.first!))
                Text(String(gz.last!)).foregroundStyle(KyV2.color(forChar: gz.last!))
            }
            .font(.system(size: 22, weight: .bold, design: .serif))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(Ky.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
