// 奇门遁甲 · 时家排盘（拆补法定局，2026-11-04 落仓）
// 口径（已逐项核实，勿凭记忆改）：
// 定局：当前节气 = LunarSwift prevJieQi；阴阳遁节气分属见 yangJieqi；
// 三元按日干支符头（日干支前推至最近甲/己日）：甲子甲午己卯己酉上元、
// 甲寅甲申己巳己亥中元、甲辰甲戌己丑己未下元；局数见 juTable。
// 地盘干：戊起局数宫，阳顺阴逆，序戊己庚辛壬癸丁丙乙，含中宫。
// 旬首（时干支所属旬）遁干：甲子戊、甲戌己、甲申庚、甲午辛、甲辰壬、甲寅癸；
// 值符星/值使门 = 地盘旬首遁干所落宫的本位星/门（中宫禽星、门寄坤死）。
// 天盘星：值符星飞到时干所落地盘宫（甲时遁戊），余星按蓬芮冲辅禽心柱任英阳顺阴逆布（含中宫）。
// 天盘干：旬首遁干随值符星到时干宫，余干按戊己庚辛壬癸丁丙乙阳顺阴逆布（含中宫）。
// 人盘门：值使门从本宫起，按时支顺数（阳宫序 1→2→3→4→9→8→7→6→1，阴逆之）
// 到时支落宫；余门按休生伤杜景死惊开顺/逆布（跳中宫）。
// 神盘：值符神随值符星到时干宫（时干宫为中宫时寄坤），余神按值符螣蛇太阴六合
// 白虎玄武九地九天阳顺阴逆布（跳中宫）。
// 空亡：时干支旬空；马星：申子辰→寅、寅午戌→申、巳酉丑→亥、亥卯未→巳。
// 格局 v1 只做已核实项（见 Pattern 解说）；三奇得使取统宗严格版（天盘奇加地盘旬首之仪）：
// 天乙加地辛（甲午）/己（甲戌）、天丙加地戊（甲子）/庚（甲申）、天丁加地癸（甲寅）/壬（甲辰）。
// G3（2026-11-07）：口径收据行、寄宫四档切换、日家奇门、置闰法定局、
// 四害（空/击刑/入墓/门迫）＋十干克应＋十二长生＋暗干层、真太阳时开关、案例库。
// 默认行为与 G3 前完全一致（拆补法、恒寄坤二、不校正、布暗干）；
// 寄宫只影响中宫旬首仪门与时干宫中宫时的神盘寄宫，星与天盘干在中五照常有值。
// 置闰行走锚点：冬至上元 1717-12-16（甲子），闰奇块集见 zhiyunRunqiStarts
// （由 Python 行走生成，对拍脚本 test_qimen_zhiyun_swift_table.py 逐字比对）。
import SwiftUI
import LunarSwift

// MARK: - G3 寄宫四档
/// 寄宫：中五无本位星门神时所寄之宫。出处：深层调研 §17；
/// 《奇门遁甲统宗》卷二（ctext）："天禽陽遁陰遁俱寄坤宮，一本陽遁寄坤宮陰遁寄艮宮"；
/// 遁甲神盤四种寄宫方式。默认恒寄坤二（与 G3 前行为一致）。
enum QimenJigong: String, CaseIterable {
    case kun2 = "kun2"
    case gen8 = "gen8"
    case yanggenYinkun = "yanggen_yinkun"
    case yangkunYingen = "yangkun_yingen"
    var name: String {
        switch self {
        case .kun2: return "恒寄坤二"
        case .gen8: return "恒寄艮八"
        case .yanggenYinkun: return "阳艮阴坤"
        case .yangkunYingen: return "阳坤阴艮"
        }
    }
    /// 当前阴阳遁下所寄宫号
    func palace(yang: Bool) -> Int {
        switch self {
        case .kun2: return 2
        case .gen8: return 8
        case .yanggenYinkun: return yang ? 8 : 2
        case .yangkunYingen: return yang ? 2 : 8
        }
    }
}

// MARK: - 引擎

enum QimenEngine {
    static let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    static let seqStems = ["戊", "己", "庚", "辛", "壬", "癸", "丁", "丙", "乙"]
    static let seqStars = ["蓬", "芮", "冲", "辅", "禽", "心", "柱", "任", "英"]
    static let seqDoors = ["休", "生", "伤", "杜", "景", "死", "惊", "开"]
    static let seqGods = ["值符", "螣蛇", "太阴", "六合", "白虎", "玄武", "九地", "九天"]
    static let baseStar: [Int: String] = [1: "蓬", 2: "芮", 3: "冲", 4: "辅", 5: "禽", 6: "心", 7: "柱", 8: "任", 9: "英"]
    static let baseDoor: [Int: String] = [1: "休", 2: "死", 3: "伤", 4: "杜", 9: "景", 7: "惊", 6: "开", 8: "生"]
    static let seq8 = [1, 2, 3, 4, 9, 8, 7, 6]  // 旧口径留档备查（2026-11-08 大修前值使／星／门／神飞宫序，已废止）
    /// 方位环序（2026-11-08 大修口径）：星／干／门／神一律沿此环布（阴遁逆环），
    /// 中宫不布星干，天禽与中宫原干随芮。依据《遁甲演义》卷一／卷二诸例。
    static let ring = [1, 8, 3, 4, 9, 2, 7, 6]
    static let ringStars = ["蓬", "任", "冲", "辅", "英", "芮", "柱", "心"]  // 本宫与 ring 一一对应
    static let ringDoors = ["休", "生", "伤", "杜", "景", "死", "惊", "开"]  // 本宫与 ring 一一对应
    static let ringGodsYin = ["值符", "九天", "九地", "玄武", "白虎", "六合", "太阴", "螣蛇"]  // 阴遁神序（沿顺时针环逆布）
    static let palaceName: [Int: String] = [1: "坎", 2: "坤", 3: "震", 4: "巽", 5: "中", 6: "乾", 7: "兑", 8: "艮", 9: "离"]
    static let palaceDir: [Int: String] = [1: "正北", 2: "西南", 3: "正东", 4: "东南", 5: "中宫", 6: "西北", 7: "正西", 8: "东北", 9: "正南"]
    static let yangJieqi: Set<String> = ["冬至", "小寒", "大寒", "立春", "雨水", "惊蛰", "春分", "清明", "谷雨", "立夏", "小满", "芒种"]
    // 节气 → （上元局，中元局，下元局）
    static let juTable: [String: (Int, Int, Int)] = [
        "冬至": (1, 7, 4), "惊蛰": (1, 7, 4), "小寒": (2, 8, 5), "大寒": (3, 9, 6), "春分": (3, 9, 6),
        "立春": (8, 5, 2), "雨水": (9, 6, 3), "清明": (4, 1, 7), "立夏": (4, 1, 7), "谷雨": (5, 2, 8), "小满": (5, 2, 8), "芒种": (6, 3, 9),
        "夏至": (9, 3, 6), "白露": (9, 3, 6), "小暑": (8, 2, 5), "大暑": (7, 1, 4), "秋分": (7, 1, 4),
        "立秋": (2, 5, 8), "处暑": (1, 4, 7), "寒露": (6, 9, 3), "立冬": (6, 9, 3), "霜降": (5, 8, 2), "小雪": (5, 8, 2), "大雪": (4, 7, 1),
    ]
    static let sanyuanOfFu: [String: String] = [
        "甲子": "上元", "甲午": "上元", "己卯": "上元", "己酉": "上元",
        "甲寅": "中元", "甲申": "中元", "己巳": "中元", "己亥": "中元",
        "甲辰": "下元", "甲戌": "下元", "己丑": "下元", "己未": "下元",
    ]
    static let doorWx: [String: String] = ["休": "水", "生": "土", "伤": "木", "杜": "木", "景": "火", "死": "土", "惊": "金", "开": "金"]
    static let palaceWx: [Int: String] = [1: "水", 2: "土", 3: "木", 4: "木", 5: "土", 6: "金", 7: "金", 8: "土", 9: "火"]
    // 五行相克：克者 → 被克者
    static let ke: [String: String] = ["木": "土", "土": "水", "水": "火", "火": "金", "金": "木"]
    static let stemChong: [String: String] = ["甲": "庚", "庚": "甲", "乙": "辛", "辛": "乙", "丙": "壬", "壬": "丙", "丁": "癸", "癸": "丁", "戊": "己", "己": "戊"]

    struct Pattern: Identifiable {
        var id: String { name }
        var name: String
        var good: Bool
        var note: String
    }
    struct Palace {
        var diStem: String
        var tianStem: String?  // 中宫为 nil（无天盘干；中宫原干随芮，见 hostedTianStem）
        var star: String?  // 中宫为 nil（无星；天禽随芮，见 hostedStar）
        var hostedStar: String? = nil  // 天禽随芮落此宫时为 "禽"
        var hostedTianStem: String? = nil  // 中宫原干随芮落此宫时为地盘中宫干
        var door: String?
        var god: String?
        var patterns: [Pattern] = []
        // G3 后段层（默认空值＝未命中）
        var siHaiKong: Bool = false
        var siHaiJiXing: Bool = false
        var siHaiRuMu: Bool = false
        var siHaiMenPo: Bool = false
        var keYingName: String? = nil
        var keYingNote: String? = nil
        var changshengTian: [String: String]? = nil  // 天盘干长生：支 → 状态；中宫为 nil
        var angan: String? = nil
    }
    struct Chart {
        var date: Date
        var pillars: [String]
        var lunarText: String
        var jieqi: String
        var yang: Bool
        var ju: Int
        var sanyuan: String
        var zhiFuStar: String
        var zhiShiDoor: String
        var hourPalace: Int  // 时干地盘原宫（可为中五 5）
        var zhiShiPalace: Int
        var zhiFuPalace: Int = 1  // 值符星落宫（禽在芮宫，其余在时干宫寄宫后）
        var tianRuiPalace: Int = 2  // 天芮落宫（天禽与中宫原干随芮落此宫）
        var qinPalace: Int = 2  // 天禽落宫（随芮）
        var zhishiRawPalace: Int = 1  // 值使移宫原宫（落 5 时寄宫，见 zhiShiPalace）
        var kongWang: String
        var maXing: String
        var xunShou: String
        var palaces: [Int: Palace]
        // G3 字段（均带默认值，旧调用点不受影响）
        var dingju: String = "拆补法"
        var jigong: QimenJigong = .kun2
        var angan: Bool = true
        var runqi: Bool = false
        var solarMinutes: Double? = nil
        var longitude: Double? = nil
        var clockDate: Date? = nil  // 校正前的钟表时间（未校正时为 nil）
        var riGan: String? = nil
        var shiGanRumu: Bool = false
        var hitPatterns: [(palace: Int, pattern: Pattern)] {
            palaces.sorted { $0.key < $1.key }.flatMap { p in p.value.patterns.map { (p.key, $0) } }
        }
        /// 口径收据行：定局法／盘式／寄宫／八神／换日／真太阳时／暗干，全部取实算值。
        /// 文本与服务端 build_receipt 逐字同式（App/Web 对拍以此为准）。
        func receiptText() -> String {
            var text = "定局：\(dingju)"
            if runqi { text += " · 闰奇" }
            text += " · 时家·转盘 · 寄宫\(jigong.name) · 八神阴阳同用（白虎／玄武） · 换日 23:00（晚子时日柱不换） · "
            if let m = solarMinutes, let lon = longitude {
                text += "真太阳时已校正 \(String(format: "%+.1f", m)) 分钟（经度 \(lon)） · "
            } else {
                text += "真太阳时未校正（按钟表时间起局） · "
            }
            text += angan ? "暗干（值使门起）" : "暗干不布"
            return text
        }
        /// 日干／时干十二长生全表（每项：支、宫、状态），与服务端 changsheng_table 同式。
        func changshengTable(stem: String) -> [(branch: String, palace: Int, stage: String)] {
            var out: [(branch: String, palace: Int, stage: String)] = []
            for b in QimenEngine.branches {
                guard let stage = QimenEngine.changshengStage(stem: stem, branch: b),
                      let pal = QimenEngine.branchPalace[b] else { continue }
                out.append((branch: b, palace: pal, stage: stage))
            }
            return out
        }
    }

    static func gzIndex(stem: String, branch: String) -> Int? {
        for n in 0..<60 where stems[n % 10] == stem && branches[n % 12] == branch { return n }
        return nil
    }
    // 日干支符头：前推至最近甲/己日
    static func fuTou(dayPillar: String) -> String? {
        guard dayPillar.count == 2,
              let si = stems.firstIndex(of: String(dayPillar.prefix(1))),
              let n = gzIndex(stem: String(dayPillar.prefix(1)), branch: String(dayPillar.suffix(1))) else { return nil }
        let fu = (n - si % 5 + 60) % 60
        return stems[fu % 10] + branches[fu % 12]
    }
    // 时干支旬首与遁干
    static func xunShou(hourPillar: String) -> (xun: String, dun: String)? {
        guard hourPillar.count == 2,
              let n = gzIndex(stem: String(hourPillar.prefix(1)), branch: String(hourPillar.suffix(1))) else { return nil }
        let x = n - n % 10
        return ("甲" + branches[x % 12], ["戊", "己", "庚", "辛", "壬", "癸"][x / 10])
    }
    static func kongWang(xun: String) -> String {
        guard let bi = branches.firstIndex(of: String(xun.suffix(1))) else { return "" }
        return branches[(bi + 10) % 12] + branches[(bi + 11) % 12]
    }
    static func maXing(hourBranch: String) -> String {
        switch hourBranch {
        case "申", "子", "辰": return "寅"
        case "寅", "午", "戌": return "申"
        case "巳", "酉", "丑": return "亥"
        default: return "巳"
        }
    }

    // MARK: - G3 后段层
    /// 十二长生：阳干顺行、阴干逆行；长生位见 changshengStart。
    /// 出处：《五行大义·论生死》最早系统表述，《渊海子平》《三命通会》一脉通行表。
    static func changshengStage(stem: String, branch: String) -> String? {
        guard let start = changshengStart[stem],
              let si = branches.firstIndex(of: start),
              let bi = branches.firstIndex(of: branch) else { return nil }
        let yangStems: Set<String> = ["甲", "丙", "戊", "庚", "壬"]
        let step = yangStems.contains(stem) ? (bi - si + 12) % 12 : (si - bi + 12) % 12
        return changshengStages[step]
    }
    /// 十干克应：天盘干加地盘干（甲隐于六仪以戊代之）。出处：hkfff.cn 十干克应全表。
    static func keYingFor(tian: String, di: String) -> (name: String, note: String)? {
        return keYing[tian + di]
    }
    /// 暗干：值使门起一法——时干放值使宫，按戊己庚辛壬癸丁丙乙沿洛书宫数（含中宫）
    /// 布满九宫，阳顺阴逆；时干为甲时遁戊。出处：深层调研 §18、命之经纬。
    static func anGanMap(zhiShiPalace: Int, hourStem: String, yang: Bool) -> [Int: String] {
        let seq = seqStems
        let hs = hourStem == "甲" ? "戊" : hourStem
        guard let s0 = seq.firstIndex(of: hs) else { return [:] }
        var out: [Int: String] = [:]
        for k in 0..<9 {
            let p = yang ? (zhiShiPalace - 1 + k) % 9 + 1 : ((zhiShiPalace - 1 - k) % 9 + 9) % 9 + 1
            out[p] = seq[yang ? (s0 + k) % 9 : (s0 - k + 90) % 9]
        }
        return out
    }

    // MARK: - G3 置闰法行走
    /// 节气序（立春起，24 节气）
    static let jieqiOrder = ["立春", "雨水", "惊蛰", "春分", "清明", "谷雨", "立夏", "小满", "芒种", "夏至", "小暑", "大暑", "立秋", "处暑", "白露", "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至", "小寒", "大寒"]
    /// 锚点：冬至上元 1717-12-16（甲子）。出处：统宗卷一「置闰法」：
    /// 冬至交节 1717-12-22，含首尾超七日（传本"甲午"为误，甲午实为 11-28）。
    static let zhiyunAnchor: (year: Int, month: Int, day: Int) = (1717, 12, 16)
    /// 闰奇块上元日期集（yyyy-MM-dd，1718–2098 共 134 块，仅芒种／大雪节后）。
    /// 由 Python 置闰行走生成；对拍脚本 test_qimen_zhiyun_swift_table.py 逐字比对。
    static let zhiyunRunqiStarts: Set<String> = [
        "1718-06-14", "1721-06-13", "1724-06-12", "1726-12-14", "1729-12-13", "1732-12-12",
        "1735-12-12", "1738-06-14", "1741-06-13", "1744-06-12", "1746-12-14", "1749-12-13",
        "1752-12-12", "1755-12-12", "1758-12-11", "1761-06-13", "1764-06-12", "1766-12-14",
        "1769-12-13", "1772-12-12", "1775-12-12", "1778-12-11", "1781-06-13", "1784-06-12",
        "1787-06-12", "1789-12-13", "1792-12-12", "1795-12-12", "1798-12-11", "1801-06-14",
        "1804-06-13", "1807-06-13", "1809-12-14", "1812-12-13", "1815-12-13", "1818-12-12",
        "1821-06-14", "1824-06-13", "1827-06-13", "1829-12-14", "1832-12-13", "1835-12-13",
        "1838-12-12", "1841-12-11", "1844-06-13", "1847-06-13", "1849-12-14", "1852-12-13",
        "1855-12-13", "1858-12-12", "1861-12-11", "1864-06-13", "1867-06-13", "1869-12-14",
        "1872-12-13", "1875-12-13", "1878-12-12", "1881-12-11", "1884-06-13", "1887-06-13",
        "1890-06-12", "1892-12-13", "1895-12-13", "1898-12-12", "1901-12-12", "1904-06-14",
        "1907-06-14", "1910-06-13", "1912-12-14", "1915-12-14", "1918-12-13", "1921-12-12",
        "1924-06-14", "1927-06-14", "1930-06-13", "1932-12-14", "1935-12-14", "1938-12-13",
        "1941-12-12", "1944-12-11", "1947-06-14", "1950-06-13", "1952-12-14", "1955-12-14",
        "1958-12-13", "1961-12-12", "1964-12-11", "1967-06-14", "1970-06-13", "1972-12-14",
        "1975-12-14", "1978-12-13", "1981-12-12", "1984-12-11", "1987-06-14", "1990-06-13",
        "1993-06-12", "1995-12-14", "1998-12-13", "2001-12-12", "2004-12-11", "2007-06-14",
        "2010-06-13", "2013-06-12", "2015-12-14", "2018-12-13", "2021-12-12", "2024-12-11",
        "2027-12-11", "2030-06-13", "2033-06-12", "2035-12-14", "2038-12-13", "2041-12-12",
        "2044-12-11", "2047-12-11", "2050-06-13", "2053-06-12", "2055-12-14", "2058-12-13",
        "2061-12-12", "2064-12-11", "2067-12-11", "2070-06-13", "2073-06-12", "2075-12-14",
        "2078-12-13", "2081-12-12", "2084-12-11", "2087-12-11", "2090-06-13", "2093-06-12",
        "2096-06-11", "2098-12-13",
    ]
    /// 置闰行走：从锚点出发，按上元 +15 天逐节步进；芒种／大雪节后若下一上元
    /// （本节上元 +15 天）在闰奇块集内，则插入闰奇块（重复本节局数），下一上元 +30 天。
    /// 向后行走同理（闰奇块上元在集内即向前多退 15 天）。覆盖 1715–2100 年。
    /// 纯日期算术，不依赖 LunarSwift 的节气表（1714–1900 年节气计算未经证实）。
    static func zhiyunLookup(date: Date) -> (jieqi: String, yang: Bool, sanyuan: String, ju: Int, runqi: Bool)? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        guard let anchor = cal.date(from: DateComponents(year: zhiyunAnchor.year, month: zhiyunAnchor.month, day: zhiyunAnchor.day, hour: 0, minute: 0)),
              let floorDate = cal.date(from: DateComponents(year: 1715, month: 1, day: 1)),
              let ceilDate = cal.date(from: DateComponents(year: 2101, month: 1, day: 1)) else { return nil }
        guard date >= floorDate, date < ceilDate else { return nil }
        let fmt: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
            return f
        }()
        // 块状态：上元日期、节气名
        var start = anchor
        var name = "冬至"
        if date >= anchor {
            while true {
                let nextStart = nextZhiyunStart(from: start, jieqi: name, fmt: fmt, cal: cal)
                if date < nextStart.date { break }
                start = nextStart.date
                name = nextStart.jieqi
            }
        } else {
            while start > date {
                let prevStart = prevZhiyunStart(from: start, jieqi: name, fmt: fmt, cal: cal)
                start = prevStart.date
                name = prevStart.jieqi
            }
        }
        // 当前块：上元 start，节气 name；块内偏移 0–4 上元、5–9 中元、10–14 下元
        let off = cal.dateComponents([.day], from: start, to: date).day ?? -1
        guard off >= 0, off < 15 else { return nil }
        let sanyuan = off < 5 ? "上元" : (off < 10 ? "中元" : "下元")
        guard let table = juTable[name] else { return nil }
        let ju = sanyuan == "上元" ? table.0 : (sanyuan == "中元" ? table.1 : table.2)
        let runqi = zhiyunRunqiStarts.contains(fmt.string(from: start))
        return (jieqi: name, yang: yangJieqi.contains(name), sanyuan: sanyuan, ju: ju, runqi: runqi)
    }
    /// 向前一步：返回下一块的上元日期与节气名
    static func nextZhiyunStart(from start: Date, jieqi name: String, fmt: DateFormatter, cal: Calendar) -> (date: Date, jieqi: String) {
        let idx = jieqiOrder.firstIndex(of: name) ?? 0
        let nname = jieqiOrder[(idx + 1) % 24]
        let nxt = cal.date(byAdding: .day, value: 15, to: start) ?? start
        if (name == "芒种" || name == "大雪") && zhiyunRunqiStarts.contains(fmt.string(from: nxt)) {
            // 闰奇块：上元 = 本节上元 +15 天，节气仍为本节（芒种／大雪）
            return (date: nxt, jieqi: name)
        }
        return (date: nxt, jieqi: nname)
    }
    /// 向后一步：返回上一块的上元日期与节气名
    static func prevZhiyunStart(from start: Date, jieqi name: String, fmt: DateFormatter, cal: Calendar) -> (date: Date, jieqi: String) {
        // 当前块本身就是闰奇块：上一块是同节气的正常块，在 start - 15 天处
        if zhiyunRunqiStarts.contains(fmt.string(from: start)) {
            let prev = cal.date(byAdding: .day, value: -15, to: start) ?? start
            return (date: prev, jieqi: name)
        }
        let idx = jieqiOrder.firstIndex(of: name) ?? 0
        let pname = jieqiOrder[(idx + 23) % 24]
        // 上一块上元：正常为 start - 15 天；若 start - 15 天是闰奇块，
        // 则上一块就是该闰奇块（节气为 pname）
        let cand15 = cal.date(byAdding: .day, value: -15, to: start) ?? start
        if (pname == "芒种" || pname == "大雪") && zhiyunRunqiStarts.contains(fmt.string(from: cand15)) {
            return (date: cand15, jieqi: pname)
        }
        return (date: cand15, jieqi: pname)
    }

    /// 直接按局数/阴阳/时干支起盘（测试与金标准用；日期版见 chart(for:)）。
    /// G3：jigong 寄宫档（默认 kun2 恒寄坤二）、angan 是否布暗干、riGan 日干
    /// （十二长生盘级表用）、dingju 定局法、solarMinutes/longitude 真太阳时、
    /// runqi 是否闰奇。2026-11-08 大修口径：值使移宫旬首起数＋数字宫序 1→9，
    /// 星／干／门／神一律沿方位环序 [1,8,3,4,9,2,7,6] 布（阴遁逆环），
    /// 中宫不布星干，天禽与中宫原干随芮（《遁甲演义》卷一／卷二为据）。
    static func chart(ju: Int, yang: Bool, hourStem: String, hourBranch: String,
                      jigong: QimenJigong = .kun2, angan: Bool = true, riGan: String? = nil,
                      dingju: String = "拆补法", solarMinutes: Double? = nil,
                      longitude: Double? = nil, runqi: Bool = false) -> Chart? {
        guard let xun = xunShou(hourPillar: hourStem + hourBranch) else { return nil }
        // 寄宫：影响值使门本位（值使移宫落中五时）、值符神起宫、
        // 值使移宫落中五时、时干宫中五时；星／干／门／神沿方位环序布（2026-11-08 大修口径）
        let jp = jigong.palace(yang: yang)
        // 地盘干
        var di: [Int: String] = [:]
        for (i, s) in seqStems.enumerated() {
            let p = yang ? (ju - 1 + i) % 9 + 1 : ((ju - 1 - i) % 9 + 9) % 9 + 1
            di[p] = s
        }
        guard let dunPal = di.first(where: { $0.value == xun.dun })?.key,
              let zhiFu = baseStar[dunPal] else { return nil }
        let zhiShi = baseDoor[dunPal] ?? baseDoor[jp] ?? "死"  // 中宫寄宫：坤→死、艮→生
        // 时干宫（甲时遁戊）
        let hs = hourStem == "甲" ? "戊" : hourStem
        guard let hourPal = di.first(where: { $0.value == hs })?.key else { return nil }
        // 方位环序（2026-11-08 大修口径）：阳顺环、阴逆环
        func rot<T>(_ arr: [T], _ start: T) -> [T] where T: Equatable {
            guard let i = arr.firstIndex(of: start) else { return arr }
            return Array(arr[i...] + arr[..<i])
        }
        let ring: [Int] = yang ? Self.ring : Array(Self.ring.reversed())
        let hourHosted = hourPal == 5 ? jp : hourPal
        let xunHosted = dunPal == 5 ? jp : dunPal
        // 值使移宫：从旬首遁干地盘宫（原宫，可为中五）起，按旬首起数
        // （时支与旬首支的支序差，0–9）沿数字宫序 1→9 移宫（阳顺阴逆）；
        // 落中五时寄所选寄宫档（默认坤二）。旧口径（时支绝对序号起、SEQ8 跳中五）已废止。
        let xunBranch = String(xun.xun.suffix(1))
        let hours = (branches.firstIndex(of: hourBranch)! - branches.firstIndex(of: xunBranch)! + 12) % 12
        let zhiShiRaw = yang ? (dunPal - 1 + hours) % 9 + 1 : ((dunPal - 1 - hours) % 9 + 9) % 9 + 1
        let zhiShiPal = zhiShiRaw == 5 ? jp : zhiShiRaw
        // 天盘星：值符星飞到时干宫，余星沿环布；中宫不布星。
        // 值符星的环首取旬首寄宫的本宫星（旬首在中宫时：寄坤取芮、寄艮取任——
        // 寄宫切换时星盘整体不变，仅寄宫标签换位；默认坤二档下即芮，与「天禽随芮」一致）
        let palaceOrder = rot(ring, hourHosted)
        let effFu = ringStars[Self.ring.firstIndex(of: xunHosted)!]
        let starSeq: [String] = yang ? ringStars : Array(ringStars.reversed())
        var stars: [Int: String] = [:]
        for (p, s) in zip(palaceOrder, rot(starSeq, effFu)) { stars[p] = s }
        let tianRuiPal = stars.first(where: { $0.value == "芮" })!.key
        // 值符宫：值符为禽时禽随芮在芮宫；其余值符星在时干宫（寄宫后）。
        // 默认坤二档下两者恒等，仅非默认寄宫档区分。
        let zhiFuPal = zhiFu == "禽" ? tianRuiPal : hourHosted
        // 天盘干：旬首遁干随值符到时干宫，余干按地盘干沿环序布；
        // 旬首遁干落中五时，取寄宫地盘干为起排干；中宫原干随芮转至芮宫，中宫不布干
        let outerEarth = ring.map { di[$0]! }
        let skyStart = dunPal == 5 ? di[xunHosted]! : xun.dun
        var tian: [Int: String] = [:]
        for (p, s) in zip(palaceOrder, rot(outerEarth, skyStart)) { tian[p] = s }
        // 人盘门：值使门在值使宫，余门沿环布
        let doorSeq: [String] = yang ? ringDoors : Array(ringDoors.reversed())
        var doors: [Int: String] = [:]
        for (p, d) in zip(rot(ring, zhiShiPal), rot(doorSeq, zhiShi)) { doors[p] = d }
        // 神盘：值符神在时干宫（寄宫后），余神沿顺时针环布（阴遁用逆序，等价于沿逆环顺布）
        var gods: [Int: String] = [:]
        for (p, g) in zip(rot(Self.ring, hourHosted), yang ? seqGods : ringGodsYin) { gods[p] = g }
        // G3 层：空亡宫、暗干映射（值使门起）
        let kongBranches = Array(kongWang(xun: xun.xun))
        let kongPals: Set<Int> = Set(kongBranches.compactMap { branchPalace[String($0)] })
        let anganMap = angan ? anGanMap(zhiShiPalace: zhiShiPal, hourStem: hourStem, yang: yang) : [:]
        // 格局 v1
        var palaces: [Int: Palace] = [:]
        for p in 1...9 {
            var pats: [Pattern] = []
            let t = tian[p], d = di[p]!  // 中宫无天盘干（t 为 nil）；地盘干照常有值
            func add(_ name: String, _ good: Bool, _ note: String) { pats.append(Pattern(name: name, good: good, note: note)) }
            if t == d { add("伏吟", false, "天盘干与地盘干同宫：伏吟主迟滞，事宜缓、不宜急进。") }
            if let t, stemChong[t] == d { add("反吟", false, "天盘干冲地盘干：反吟主反复变动，计划易生变，宜留后手。") }
            if t == "戊" && d == "丙" { add("青龙返首", true, "天戊临丙：青龙回头看顾，事情容易顺着来，宜主动推进。") }
            if t == "丙" && d == "戊" { add("飞鸟跌穴", true, "天丙临戊：飞鸟落回巢里，谋事容易落定，宜静守、宜收成。") }
            if t == "辛" && d == "乙" { add("白虎猖狂", false, "天辛临乙：白虎猖狂，主口舌是非、意外损伤，宜低调避让。") }
            if t == "丁" && d == "癸" { add("朱雀投江", false, "天丁临癸：朱雀投江，主文书口舌、信息失真，文书事须再三核对。") }
            if t == "癸" && d == "丁" { add("螣蛇夭矫", false, "天癸临丁：螣蛇夭矫，主虚惊怪异、事多反复，宜多方核实再定。") }
            if (t == "乙" && (d == "辛" || d == "己")) || (t == "丙" && (d == "戊" || d == "庚")) || (t == "丁" && (d == "癸" || d == "壬")) {
                add("三奇得使", true, "三奇得其使（统宗严格版）：天盘奇加临地盘旬首之仪，奇门有靠，贵人暗助，宜借力行事。")
            }
            if p == zhiShiPal && d == "丁" { add("玉女守门", true, "值使门落宫逢丁奇守门：事有暗助，宜私下谋划、暗中推进。") }
            let door = doors[p]
            let menpo = door.flatMap { doorWx[$0] }.flatMap { ke[$0] } == palaceWx[p]
            if menpo {
                add("门迫", false, "门克宫：此宫行事多阻力，不宜硬来，宜绕道或换个打法。")
            }
            // G3 层：四害（空／击刑／入墓／门迫）＋十干克应＋天盘干十二长生＋暗干
            // 中宫无天盘干：长生／克应／击刑／入墓皆为 nil／false
            let pBranches = palaceBranches[p] ?? []
            let csTian: [String: String]? = (t == nil || pBranches.isEmpty) ? nil : Dictionary(uniqueKeysWithValues: pBranches.map { ($0, changshengStage(stem: t!, branch: $0) ?? "—") })
            let ky = t.flatMap { keYingFor(tian: $0, di: d) }
            palaces[p] = Palace(diStem: d, tianStem: t, star: stars[p], hostedStar: p == tianRuiPal ? "禽" : nil, hostedTianStem: p == tianRuiPal ? di[5] : nil, door: doors[p], god: gods[p], patterns: pats,
                                siHaiKong: kongPals.contains(p),
                                siHaiJiXing: t.flatMap { jiXing[$0] } == p,
                                siHaiRuMu: t.flatMap { ruMu[$0] } == p,
                                siHaiMenPo: menpo,
                                keYingName: ky?.name,
                                keYingNote: ky?.note,
                                changshengTian: csTian,
                                angan: anganMap[p])
        }
        return Chart(date: Date(), pillars: [], lunarText: "", jieqi: "", yang: yang, ju: ju, sanyuan: "",
                     zhiFuStar: zhiFu, zhiShiDoor: zhiShi, hourPalace: hourPal, zhiShiPalace: zhiShiPal,
                     zhiFuPalace: zhiFuPal, tianRuiPalace: tianRuiPal, qinPalace: tianRuiPal, zhishiRawPalace: zhiShiRaw,
                     kongWang: kongWang(xun: xun.xun), maXing: maXing(hourBranch: hourBranch), xunShou: xun.xun,
                     palaces: palaces, dingju: dingju, jigong: jigong, angan: angan, runqi: runqi,
                     solarMinutes: solarMinutes, longitude: longitude, riGan: riGan,
                     shiGanRumu: shiGanRumu.contains(hourStem + hourBranch))
    }

    /// 日期版：四柱取 BaziEngine.paipan（金标准口径），节气取 LunarSwift prevJieQi。
    /// （旧口径：拆补法、恒寄坤二、不校正、布暗干）
    static func chart(for date: Date) -> Chart? {
        return chart(for: date, longitude: nil, jigong: .kun2, angan: true)
    }
    /// 日期版全参数：longitude 为 nil＝不校正（旧口径）；给经度即按真太阳时校正
    /// （与服务端 paipan 同式，收据行写清校正分钟数＋经度）。
    static func chart(for date: Date, longitude: Double?, jigong: QimenJigong, angan: Bool) -> Chart? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        var clockDate: Date? = nil
        var solarMinutes: Double? = nil
        var used = date
        if let lon = longitude {
            used = TrueSolarTime.corrected(clock: date, longitude: lon, calendar: cal)
            solarMinutes = TrueSolarTime.correctionMinutes(clock: date, longitude: lon, calendar: cal)
            clockDate = date
        }
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: used)
        guard let y = c.year, let mo = c.month, let d = c.day, let h = c.hour, let mi = c.minute else { return nil }
        let solar = Solar.fromYmdHms(year: y, month: mo, day: d, hour: h, minute: mi)
        let lunar = solar.lunar
        let jieqi = lunar.prevJieQi.name
        guard let table = juTable[jieqi] else { return nil }
        let yang = yangJieqi.contains(jieqi)
        let bazi = BaziEngine.paipan(clock: used, gender: "M", longitude: nil)
        guard let fu = fuTou(dayPillar: bazi.dayPillar), let sanyuan = sanyuanOfFu[fu] else { return nil }
        let ju = sanyuan == "上元" ? table.0 : (sanyuan == "中元" ? table.1 : table.2)
        let timePillar = bazi.timePillar
        guard var plate = chart(ju: ju, yang: yang, hourStem: String(timePillar.prefix(1)), hourBranch: String(timePillar.suffix(1)),
                                jigong: jigong, angan: angan, riGan: String(bazi.dayPillar.prefix(1)),
                                solarMinutes: solarMinutes, longitude: longitude) else { return nil }
        plate.date = used
        plate.pillars = bazi.pillars
        plate.lunarText = "\(lunar.monthInChinese)月\(lunar.dayInChinese)"
        plate.jieqi = jieqi
        plate.sanyuan = sanyuan
        plate.clockDate = clockDate
        return plate
    }

    // MARK: - G3 日家奇门
    struct RijiaPalace {
        var diStem: String
        var star: String
        var door: String?
    }
    struct RijiaChart {
        var date: Date
        var pillars: [String]
        var lunarText: String
        var jieqi: String
        var yang: Bool
        var ju: Int
        var palaces: [Int: RijiaPalace]
        var solarMinutes: Double? = nil
        var longitude: Double? = nil
        var clockDate: Date? = nil
        /// 收据行（与服务端 rijia receipt_text 同式）
        func receiptText() -> String {
            var text = "定局：日家奇门（统宗卷二附日奇门起例（一）） · 局数按日支 · 九星八门不分阴阳遁 · 无天盘干／值符／值使／八神 · "
            if let m = solarMinutes, let lon = longitude {
                text += "真太阳时已校正 \(String(format: "%+.1f", m)) 分钟（经度 \(lon)）"
            } else {
                text += "真太阳时未校正（按钟表时间起局）"
            }
            return text
        }
    }
    /// 日家局数：按日支——子午二、丑未六、寅申一、卯酉八、辰戌四、巳亥九
    static let rijiaJu: [String: Int] = ["子": 2, "午": 2, "丑": 6, "未": 6, "寅": 1, "申": 1, "卯": 8, "酉": 8, "辰": 4, "戌": 4, "巳": 9, "亥": 9]
    /// 日家八门宫序（跳中宫）：休门起坎一，三日顺转一宫
    static let rijiaDoorSeq = [1, 2, 3, 4, 6, 7, 8, 9]
    /// 日家奇门（统宗卷二附日奇门起例（一））：冬至后阳遁、夏至后阴遁；
    /// 局数按日支；九星甲子日天蓬起艮八宫、一日顺移；八门甲子日休门起坎一、
    /// 三日顺转一宫；余门顺布；地盘干戊起局数宫、阳顺阴逆；
    /// 九星八门不分阴阳遁；无天盘干／值符／值使／八神。
    static func rijiaChart(for date: Date, longitude: Double? = nil) -> RijiaChart? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        var clockDate: Date? = nil
        var solarMinutes: Double? = nil
        var used = date
        if let lon = longitude {
            used = TrueSolarTime.corrected(clock: date, longitude: lon, calendar: cal)
            solarMinutes = TrueSolarTime.correctionMinutes(clock: date, longitude: lon, calendar: cal)
            clockDate = date
        }
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: used)
        guard let y = c.year, let mo = c.month, let d = c.day, let h = c.hour, let mi = c.minute else { return nil }
        let lunar = Solar.fromYmdHms(year: y, month: mo, day: d, hour: h, minute: mi).lunar
        let jieqi = lunar.prevJieQi.name
        let yang = yangJieqi.contains(jieqi)
        let bazi = BaziEngine.paipan(clock: used, gender: "M", longitude: nil)
        let dayPillar = bazi.dayPillar
        guard let n = gzIndex(stem: String(dayPillar.prefix(1)), branch: String(dayPillar.suffix(1))),
              let ju = rijiaJu[String(dayPillar.suffix(1))] else { return nil }
        // 九星：甲子日天蓬起艮八宫，一日顺移（天蓬宫 = ((7+n)%9)+1，含中五）
        let pengPal = ((7 + n) % 9) + 1
        var stars: [Int: String] = [:]
        let si = seqStars.firstIndex(of: "蓬")!
        for k in 0..<9 {
            let p = (pengPal - 1 + k) % 9 + 1
            stars[p] = seqStars[(si + k) % 9]
        }
        // 八门：甲子日休门起坎一，三日顺转一宫
        let xiuPal = rijiaDoorSeq[(n / 3) % 8]
        var doors: [Int: String] = [:]
        let d0 = seqDoors.firstIndex(of: "休")!
        let zp = rijiaDoorSeq.firstIndex(of: xiuPal)!
        for k in 0..<8 {
            let p = rijiaDoorSeq[(zp + k) % 8]
            doors[p] = seqDoors[(d0 + k) % 8]
        }
        // 地盘干：戊起局数宫，阳顺阴逆（与时家同式）
        var di: [Int: String] = [:]
        for (i, s) in seqStems.enumerated() {
            let p = yang ? (ju - 1 + i) % 9 + 1 : ((ju - 1 - i) % 9 + 9) % 9 + 1
            di[p] = s
        }
        var palaces: [Int: RijiaPalace] = [:]
        for p in 1...9 {
            palaces[p] = RijiaPalace(diStem: di[p]!, star: stars[p]!, door: doors[p])
        }
        return RijiaChart(date: used, pillars: bazi.pillars,
                          lunarText: "\(lunar.monthInChinese)月\(lunar.dayInChinese)",
                          jieqi: jieqi, yang: yang, ju: ju, palaces: palaces,
                          solarMinutes: solarMinutes, longitude: longitude, clockDate: clockDate)
    }

    // MARK: - G3 置闰法定局
    /// 置闰法定局（统宗卷一「置闰法」）：行走见 zhiyunLookup；
    /// 局内三元按块内偏移（0–4 上元、5–9 中元、10–14 下元）。
    /// 其余排盘与拆补法同式（值符值使、九星八门八神、后段层全同）。
    static func zhiyunChart(for date: Date, jigong: QimenJigong = .kun2, angan: Bool = true, longitude: Double? = nil) -> Chart? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        var clockDate: Date? = nil
        var solarMinutes: Double? = nil
        var used = date
        if let lon = longitude {
            used = TrueSolarTime.corrected(clock: date, longitude: lon, calendar: cal)
            solarMinutes = TrueSolarTime.correctionMinutes(clock: date, longitude: lon, calendar: cal)
            clockDate = date
        }
        guard let z = zhiyunLookup(date: used) else { return nil }
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: used)
        guard let y = c.year, let mo = c.month, let d = c.day, let h = c.hour, let mi = c.minute else { return nil }
        let lunar = Solar.fromYmdHms(year: y, month: mo, day: d, hour: h, minute: mi).lunar
        let bazi = BaziEngine.paipan(clock: used, gender: "M", longitude: nil)
        let timePillar = bazi.timePillar
        guard var plate = chart(ju: z.ju, yang: z.yang, hourStem: String(timePillar.prefix(1)), hourBranch: String(timePillar.suffix(1)),
                                jigong: jigong, angan: angan, riGan: String(bazi.dayPillar.prefix(1)),
                                dingju: "置闰法", solarMinutes: solarMinutes, longitude: longitude, runqi: z.runqi) else { return nil }
        plate.date = used
        plate.pillars = bazi.pillars
        plate.lunarText = "\(lunar.monthInChinese)月\(lunar.dayInChinese)"
        plate.jieqi = z.jieqi
        plate.sanyuan = z.sanyuan
        plate.clockDate = clockDate
        return plate
    }
}

// MARK: - G3 Tables (generated by tools/gen_qimen_swift.py — do not hand-edit)
// 口径出处见 app/qimen.py 各表注释；本段由 Python 已验证表生成，逐字对拍。
extension QimenEngine {
    static let jigongModes: [(code: String, name: String)] = [
        (code: "kun2", name: "恒寄坤二"),
        (code: "gen8", name: "恒寄艮八"),
        (code: "yanggen_yinkun", name: "阳艮阴坤"),
        (code: "yangkun_yingen", name: "阳坤阴艮"),
    ]
    static let jiXing: [String: Int] = ["壬": 4, "己": 2, "庚": 8, "戊": 3, "癸": 4, "辛": 9]
    static let ruMu: [String: Int] = ["丁": 8, "丙": 6, "乙": 2]
    static let shiGanRumu: Set<String> = ["丁丑", "丙戌", "壬辰", "戊戌", "癸未"]
    static let branchPalace: [String: Int] = ["子": 1, "丑": 8, "寅": 8, "卯": 3, "辰": 4, "巳": 4, "午": 9, "未": 2, "申": 2, "酉": 7, "戌": 6, "亥": 6]
    static let palaceBranches: [Int: [String]] = [1: ["子"], 2: ["未", "申"], 3: ["卯"], 4: ["辰", "巳"], 5: [], 6: ["戌", "亥"], 7: ["酉"], 8: ["丑", "寅"], 9: ["午"]]
    static let changshengStages: [String] = ["长生", "沐浴", "冠带", "临官", "帝旺", "衰", "病", "死", "墓", "绝", "胎", "养"]
    static let changshengStart: [String: String] = ["丁": "酉", "丙": "寅", "乙": "午", "壬": "申", "己": "酉", "庚": "巳", "戊": "寅", "甲": "亥", "癸": "卯", "辛": "子"]
    static let keYing: [String: (name: String, note: String)] = [
        "丁丁": (name: "星奇入太阴", note: "书信即至，喜事遂心，万事如意。"),
        "丁丙": (name: "星随月转", note: "当官的会越级高升，老百姓则乐中生悲。"),
        "丁乙": (name: "人遁吉格", note: "当官的加官晋爵，老百姓有婚姻、发财之喜。"),
        "丁壬": (name: "五神互合", note: "贵人恩诏，讼狱公平；婚多为苟合。"),
        "丁己": (name: "火入勾陈", note: "奸私仇冤，事端由女人引起。"),
        "丁庚": (name: "文书阻隔", note: "行人必归。"),
        "丁戊": (name: "青龙转光", note: "官人升迁，常人有威昌盛。"),
        "丁癸": (name: "朱雀投江", note: "文书口舌是非，经动官符，词讼不利，音信长期不通。"),
        "丁辛": (name: "朱雀入狱", note: "罪人被释放，官人失位。"),
        "丙丁": (name: "星奇朱雀", note: "有贵人文书到来，吉利；常人则生活平静，得三奇门为天遁。"),
        "丙丙": (name: "月奇悖师", note: "主文书逼迫，财产破耗，单据票证遗失不明。"),
        "丙乙": (name: "日月并明", note: "无论做什么事都吉利。"),
        "丙壬": (name: "火入天罗", note: "为客不利，是非颇多。"),
        "丙己": (name: "大悖入刑", note: "坐监牢，被杖责，文书公文不能传递；得吉门则吉，得凶门则转吉为凶。"),
        "丙庚": (name: "荧入太白", note: "主家庭破败，盗贼偷窃，财产损失。"),
        "丙戊": (name: "飞鸟跌穴", note: "无论干什么事都吉利。"),
        "丙癸": (name: "华盖悖师", note: "阴人害事，灾祸较多。"),
        "丙辛": (name: "日月相会", note: "谋事能成，为病人不凶。"),
        "乙丁": (name: "奇仪相佐", note: "最利文书、考试，百事可做。"),
        "乙丙": (name: "奇仪顺遂", note: "遇吉星可以升官进职，遇凶星则夫妻分离。"),
        "乙乙": (name: "日奇伏吟", note: "不宜谒见贵人、求功名，只可安分守己。"),
        "乙壬": (name: "日奇入地", note: "尊卑颠倒，要吃官司。"),
        "乙己": (name: "日奇入墓", note: "前程不明，凶门事必凶，得二吉门为地遁。"),
        "乙庚": (name: "日奇被刑", note: "打官司破财，夫妻各怀私心。"),
        "乙戊": (name: "利阴害阳", note: "门逢凶迫，财伤人。"),
        "乙癸": (name: "华盖逢星", note: "宜于隐居、修道，不露形迹、躲灾避难为吉。"),
        "乙辛": (name: "青龙逃走", note: "奴仆盗窃主家钱财，六畜皆伤。"),
        "壬丁": (name: "干合蛇刑", note: "贵人匆匆而过，文书牵连，男吉女凶。"),
        "壬丙": (name: "水蛇入火", note: "主官灾刑禁之事络绎不绝。"),
        "壬乙": (name: "小蛇得势", note: "女子柔顺，男子通达，占孕生男孩，前程光明。"),
        "壬壬": (name: "蛇入地罗", note: "外事缠绕，内事烦锁；若逢吉门吉星，也许可以免受损害。"),
        "壬己": (name: "反吟蛇刑", note: "大祸将至，宫司败诉，守本分可吉，轻举妄动必凶。"),
        "壬庚": (name: "太白擒蛇", note: "讼狱公平，立剖正邪。"),
        "壬戊": (name: "小蛇化龙", note: "男人飞黄腾达，女人产孩儿。"),
        "壬癸": (name: "幼女奸淫", note: "家有丑事外传；若逢吉门凶星反祸为福。"),
        "壬辛": (name: "螣蛇相缠", note: "纵得吉门亦不能安宁，若有谋望被人欺瞒、哄骗。"),
        "己丁": (name: "朱雀入墓", note: "先动者失利，受冤枉，后得平反昭雪。"),
        "己丙": (name: "火悖地户", note: "男人冤冤相害，女人必定淫乱不堪。"),
        "己乙": (name: "墓神不明", note: "地户逢星，宜隐匿不出，逃走则有利。"),
        "己壬": (name: "地网高张", note: "遇狡童淫女，有奸情杀伤凶。"),
        "己己": (name: "地户逢鬼", note: "病者必死，暂不谋为，谋为则凶。"),
        "己庚": (name: "刑格返名", note: "词讼先动者不利，如临阴星有谋害之情。"),
        "己戊": (name: "犬遇青龙", note: "逢吉门则吉，若逢凶门，枉费心机。"),
        "己癸": (name: "地刑玄武", note: "男女疾病垂危，并有官司牢狱之灾。"),
        "己辛": (name: "游魂入墓", note: "易遇阴邪鬼怪作祟。"),
        "庚丁": (name: "亭亭自奸", note: "因官司，逢吉门则有救。"),
        "庚丙": (name: "太白入荧", note: "贼必来，为客者有利，为主者破财。"),
        "庚乙": (name: "太白逢星", note: "退吉进凶。"),
        "庚壬": (name: "上格", note: "远行迷路，男女音信难通。"),
        "庚己": (name: "刑格", note: "官司口舌，因官讼被判刑，住牢狱更凶。"),
        "庚庚": (name: "太白同宫", note: "又为战格，官灾横祸，兄弟、朋友相冲克，不利为事。"),
        "庚戊": (name: "天乙伏宫", note: "百事不可谋，大凶。"),
        "庚癸": (name: "大格", note: "多主车祸，官事不止，生育母子俱伤，大凶。"),
        "庚辛": (name: "白虎干格", note: "远行车折马伤，求财更是大凶。"),
        "戊丁": (name: "青龙耀明", note: "宜见贵人、求功名；但若逢墓迫，则招惹是非。"),
        "戊丙": (name: "青龙返首", note: "大吉大利；但若逢墓迫击刑，则吉事变凶。"),
        "戊乙": (name: "青龙合灵", note: "遇吉门则吉，遇凶门则凶。"),
        "戊壬": (name: "青龙入天牢", note: "无论什么事都不吉利。"),
        "戊己": (name: "贵人入狱", note: "公私皆不吉利。"),
        "戊庚": (name: "值符飞宫", note: "吉事不吉，凶事更凶；飞宫格也主换地方。"),
        "戊戊": (name: "伏吟", note: "不宜动，隐闭静守则吉，动则凶。"),
        "戊癸": (name: "青龙华盖", note: "逢吉门吉格者招福，逢凶门凶格者，诸事不利，为凶。"),
        "戊辛": (name: "青龙折足", note: "若逢吉门则有救，还可有所作为；若见凶门，主招灾失财和患疾病。"),
        "癸丁": (name: "螣蛇夭矫", note: "文书官司，火焚也逃不掉。"),
        "癸丙": (name: "华盖悖师", note: "贵贱逢之，命运好的人有喜事临门。"),
        "癸乙": (name: "华盖逢星", note: "贵人可以得到禄位，常人本安无事。"),
        "癸壬": (name: "复见螣蛇", note: "婚姻不利，都会丧偶再婚，出嫁太晚则无子，并且会早死。"),
        "癸己": (name: "华盖地户", note: "无论男女占之，音信皆阻，躲灾避难为上吉。"),
        "癸庚": (name: "太白入网", note: "以暴力争讼，自罗罪责。"),
        "癸戊": (name: "天乙合会", note: "宜求财，婚姻喜美，有贵人帮助；若逢凶门迫制，反而有官司之祸。"),
        "癸癸": (name: "天网四张", note: "外出远行伙伴走失，无讼患病或吃官司都会受到伤害。"),
        "癸辛": (name: "网盖天牢", note: "无论诉讼占病，结果都是死亡，罪责难逃。"),
        "辛丁": (name: "狱神得奇", note: "经商获利倍增，囚人遇赦获释。"),
        "辛丙": (name: "干合悖师", note: "求雨无雨，求晴天旱，必因财产纠纷讼诉公堂。"),
        "辛乙": (name: "白虎猖狂", note: "主家败人亡，外出远行必遭祸殃；测婚姻离散，主因男人。"),
        "辛壬": (name: "凶蛇入狱", note: "两男争一女，诉讼不息，先动者失理获罪。"),
        "辛己": (name: "入狱自刑", note: "奴仆背主，有冤诉讼难伸。"),
        "辛庚": (name: "白虎出力", note: "刀兵相接、主客相残，逊让退步稍可，强进血溅衣衫。"),
        "辛戊": (name: "困龙被伤", note: "主有官司、破财，安守本分；轻举妄动则有祸殃。"),
        "辛癸": (name: "天牢华盖", note: "日月失明，误入天网，无论干什么事都不顺利。"),
        "辛辛": (name: "伏吟天庭", note: "公事失败，私事成功，讼诉自招罪名。"),
    ]
}
// MARK: - End G3 Tables

// MARK: - 释义库（大白话卡片）

enum QimenGlossary {
    static let doors: [(String, String)] = [
        ("休门", "休息、安稳：宜休整、谈和，不宜大动。"),
        ("生门", "生发、财利：最利求财、做生意、置产。"),
        ("伤门", "损伤、争执：宜动中取利，忌冲动伤人。"),
        ("杜门", "闭塞、隐藏：宜暗中谋划、保密行事。"),
        ("景门", "文书、名声：宜考试、文书、宣传。"),
        ("死门", "终结、滞塞：宜收尾、丧葬，忌开张动土。"),
        ("惊门", "惊恐、口舌：宜诉讼、揭发，忌惊扰。"),
        ("开门", "开启、官贵：宜开业、求官、见贵人。"),
    ]
    static let stars: [(String, String)] = [
        ("天蓬", "险中带智：水性，宜智取，忌贪险。"),
        ("天芮", "病与学：坤土，宜学习、看病，忌拖延。"),
        ("天冲", "动与冲劲：雷性，宜速战、冲锋。"),
        ("天辅", "辅佐与文：风性，宜辅佐、文教。"),
        ("天禽", "中宫统领：土性，宜居中调度。"),
        ("天心", "心智与金：宜谋划、医药、管理。"),
        ("天柱", "破与口舌：金性，宜破局，忌口舌。"),
        ("天任", "稳与担当：山性，宜稳守、担责。"),
        ("天英", "火与名：烈性，宜扬名、文书，忌急躁。"),
    ]
    static let gods: [(String, String)] = [
        ("值符", "主帅，最吉：所到之处诸事有靠。"),
        ("螣蛇", "虚惊缠绕：事多反复，宜核实。"),
        ("太阴", "暗助阴私：宜暗中谋划、女性助力。"),
        ("六合", "和合婚姻：宜合婚、合伙、和解。"),
        ("白虎", "凶煞血光：宜避让，忌动武见血。"),
        ("玄武", "盗与暗昧：宜防盗、防骗。"),
        ("九地", "稳与潜藏：宜潜伏、稳守、置产。"),
        ("九天", "高远扬名：宜远行、高就、扬名。"),
    ]
    static let patterns: [(String, String)] = [
        ("青龙返首", "天戊临丙，吉：事情顺着来，宜主动。"),
        ("飞鸟跌穴", "天丙临戊，吉：谋事易落定，宜静守。"),
        ("三奇得使", "天盘奇加地盘旬首之仪（乙加辛/己、丙加戊/庚、丁加癸/壬），吉：贵人暗助，宜借力。"),
        ("玉女守门", "值使门逢丁，吉：暗助在，宜私下推进。"),
        ("白虎猖狂", "天辛临乙，凶：口舌意外，宜避让。"),
        ("朱雀投江", "天丁临癸，凶：文书失真，须核对。"),
        ("螣蛇夭矫", "天癸临丁，凶：虚惊反复，宜核实。"),
        ("伏吟", "天盘干同地盘干，凶滞：事宜缓。"),
        ("反吟", "天盘干冲地盘干，凶变：计划易变，留后手。"),
        ("门迫", "门克宫，凶阻：此宫行事多阻力。"),
    ]
    static let yongShen: [(String, String)] = [
        ("求财", "生门 · 甲子戊（看生门落宫与戊的旺衰）"),
        ("婚姻", "乙庚 · 六合（乙为女、庚为男，六合为媒）"),
        ("出行", "值使 · 九天（值使为动向，九天为远行）"),
        ("求官", "开门 · 值符（开门为官禄，值符为贵人）"),
        ("失物", "玄武 · 值使（玄武为失，值使为去向）"),
        ("疾病", "天芮 · 死门（天芮为病星，死门为病灶）"),
        ("考试", "景门 · 丁奇（景门为文书，丁奇为文章）"),
        ("官司", "惊门 · 白虎（惊门为讼，白虎为刑伤）"),
    ]
}

// MARK: - G3 案例库（只收公开记载、可核验案例；与 Web app/qimen_cases.json 同源）
// 典籍／教程算例仅核定局与值符值使，无实战应验记录，应验栏如实写"无"。
// 值使落宫口径已裁决（2026-11-08 奇门大修）：引擎改旬首起数＋数字宫序 1→9
// （含中五寄坤二），依据《遁甲演义》卷二·地遁辛卯时；有教程值者（01–06）
// 引擎值与教程值全部一致。
struct QimenCase: Identifiable {
    var id: String
    var title: String
    var datetime: String
    var dingju: String
    var dun: String
    var jieqi: String
    var ju: Int
    var sanyuan: String
    var pillars: [String]
    var zhifu: String
    var zhifuPalaceEngine: Int
    var zhifuPalaceSource: Int?
    var zhishi: String
    var zhishiPalaceEngine: Int
    var zhishiPalaceSource: Int?
    var sourceName: String
    var sourceText: String
    var sourceUrl: String
    var yingyan: String
    var verified: String
    var status: String
    var zhifuNote: String
    var zhishiNote: String
}
enum QimenCases {
    static let all: [QimenCase] = [
        QimenCase(
            id: "qimen-case-01",
            title: "新浪教程起局实例 1：丙午日丙申时",
            datetime: "1996-05-09 16:20",
            dingju: "拆补法",
            dun: "阳遁",
            jieqi: "立夏",
            ju: 7,
            sanyuan: "下元",
            pillars: ["丙子", "癸巳", "丙午", "丙申"],
            zhifu: "天蓬带辛",
            zhifuPalaceEngine: 2,
            zhifuPalaceSource: 2,
            zhishi: "休门",
            zhishiPalaceEngine: 3,
            zhishiPalaceSource: 3,
            sourceName: "新浪《奇门遁甲入门教程》起局实例 1",
            sourceText: "丙午日甲辰壬旬，辰为下元，立夏阳 7 局；丙申时甲午辛旬，值符天蓬带辛，值使休门；时干丙落 5 宫寄二宫，值符落二宫；时支申（午1未2申3）落三宫，值使休门落三宫。",
            sourceUrl: "http://k.sina.cn/article_6398138586_17d5bd8da0010036ro.html",
            yingyan: "无（典籍算例，仅核定局与值符值使）",
            verified: "引擎复核：立夏阳 7 局下元，值符天蓬落 2 宫，值使休门落 3 宫，局／星／门／落宫全部一致。",
            status: "已验",
            zhifuNote: "时干丙之地盘宫为 5 宫（中五），新口径下值符星寄坤落 2 宫，与教程一致。",
            zhishiNote: "口径已裁决（2026-11-08 奇门大修）：引擎改旬首起数＋数字宫序 1→9（含中五寄坤二），与教程值一致；依据《遁甲演义》卷二·地遁辛卯时。",
        ),
        QimenCase(
            id: "qimen-case-02",
            title: "新浪教程起局实例 2：戊申日戊午时",
            datetime: "2008-11-04 12:30",
            dingju: "拆补法",
            dun: "阴遁",
            jieqi: "霜降",
            ju: 2,
            sanyuan: "下元",
            pillars: ["戊子", "壬戌", "戊申", "戊午"],
            zhifu: "天心带癸",
            zhifuPalaceEngine: 2,
            zhifuPalaceSource: 2,
            zhishi: "开门",
            zhishiPalaceEngine: 2,
            zhishiPalaceSource: 2,
            sourceName: "新浪《奇门遁甲入门教程》起局实例 2",
            sourceText: "戊申日甲辰壬旬，辰为下元，霜降阴 2 局；戊午时甲寅癸旬，值符天心带癸，值使开门；时干戊落二宫，值符落二宫；时支午（寅6卯5辰4巳3午2）落二宫，值使开门落二宫。",
            sourceUrl: "http://k.sina.cn/article_6398138586_17d5bd8da0010036ro.html",
            yingyan: "无（典籍算例，仅核定局与值符值使）",
            verified: "引擎复核：霜降阴 2 局下元，值符天心落 2 宫，值使开门落 2 宫，局／星／门／落宫全部一致。",
            status: "已验",
            zhifuNote: "",
            zhishiNote: "",
        ),
        QimenCase(
            id: "qimen-case-03",
            title: "新浪教程起局实例 3：壬子日甲辰时",
            datetime: "2004-08-01 08:20",
            dingju: "拆补法",
            dun: "阴遁",
            jieqi: "大暑",
            ju: 7,
            sanyuan: "上元",
            pillars: ["甲申", "辛未", "壬子", "甲辰"],
            zhifu: "天冲带壬",
            zhifuPalaceEngine: 7,
            zhifuPalaceSource: 3,
            zhishi: "伤门",
            zhishiPalaceEngine: 3,
            zhishiPalaceSource: 3,
            sourceName: "新浪《奇门遁甲入门教程》起局实例 3",
            sourceText: "壬子日甲辰壬旬，辰为下元，大暑阴 7 局；甲辰时甲辰壬旬，值符天冲带壬，值使伤门；时干壬落三宫，值符落三宫；时支辰落三宫，值使伤门落三宫。",
            sourceUrl: "http://k.sina.cn/article_6398138586_17d5bd8da0010036ro.html",
            yingyan: "无（典籍算例，仅核定局与值符值使）",
            verified: "引擎复核：大暑阴 7 局上元，值符天冲，值使伤门，局／星／门一致。",
            status: "已验",
            zhifuNote: "教程“时干壬”实为旬首遁干壬（地盘宫 3 宫）；时干甲遁戊落 7 宫，引擎值符星落时干宫 7 宫。甲时教程以遁干代时干记宫，引擎按时干宫为准。",
            zhishiNote: "口径已裁决（2026-11-08 奇门大修）：引擎改旬首起数＋数字宫序 1→9（含中五寄坤二），与教程值一致；依据《遁甲演义》卷二·地遁辛卯时。",
        ),
        QimenCase(
            id: "qimen-case-04",
            title: "新浪教程起局实例 4：丁卯日丙午时",
            datetime: "2004-10-15 12:30",
            dingju: "拆补法",
            dun: "阴遁",
            jieqi: "寒露",
            ju: 6,
            sanyuan: "上元",
            pillars: ["甲申", "甲戌", "丁卯", "丙午"],
            zhifu: "天芮带壬",
            zhifuPalaceEngine: 8,
            zhifuPalaceSource: 8,
            zhishi: "死门",
            zhishiPalaceEngine: 9,
            zhishiPalaceSource: 9,
            sourceName: "新浪《奇门遁甲入门教程》起局实例 4",
            sourceText: "丁卯日甲子戊旬，子为上元，寒露阴 6 局；丙午时甲辰壬旬，值符天芮带壬，值使死门；时干丙落八宫，值符落八宫；时支午（辰2巳1午9）落九宫，值使死门落九宫。",
            sourceUrl: "http://k.sina.cn/article_6398138586_17d5bd8da0010036ro.html",
            yingyan: "无（典籍算例，仅核定局与值符值使）",
            verified: "引擎复核：寒露阴 6 局上元，值符天芮落 8 宫，值使死门，局／星／门／值符宫一致。",
            status: "已验",
            zhifuNote: "",
            zhishiNote: "口径已裁决（2026-11-08 奇门大修）：引擎改旬首起数＋数字宫序 1→9（含中五寄坤二），与教程值一致；依据《遁甲演义》卷二·地遁辛卯时。",
        ),
        QimenCase(
            id: "qimen-case-05",
            title: "新浪教程起局实例 5：乙酉日庚辰时",
            datetime: "2004-11-02 08:30",
            dingju: "拆补法",
            dun: "阴遁",
            jieqi: "霜降",
            ju: 8,
            sanyuan: "中元",
            pillars: ["甲申", "甲戌", "乙酉", "庚辰"],
            zhifu: "天柱带己",
            zhifuPalaceEngine: 6,
            zhifuPalaceSource: 6,
            zhishi: "惊门",
            zhishiPalaceEngine: 1,
            zhishiPalaceSource: 1,
            sourceName: "新浪《奇门遁甲入门教程》起局实例 5",
            sourceText: "乙酉日甲申庚旬，申为中元，霜降阴 8 局；庚辰时甲戌己旬，值符天柱带己，值使惊门；时干庚落六宫，值符落六宫；时支辰（戌7亥6子5丑4寅3卯2辰1）落一宫，值使惊门落一宫。",
            sourceUrl: "http://k.sina.cn/article_6398138586_17d5bd8da0010036ro.html",
            yingyan: "无（典籍算例，仅核定局与值符值使）",
            verified: "引擎复核：霜降阴 8 局中元，值符天柱落 6 宫，值使惊门，局／星／门／值符宫一致。",
            status: "已验",
            zhifuNote: "",
            zhishiNote: "口径已裁决（2026-11-08 奇门大修）：引擎改旬首起数＋数字宫序 1→9（含中五寄坤二），与教程值一致；依据《遁甲演义》卷二·地遁辛卯时。",
        ),
        QimenCase(
            id: "qimen-case-06",
            title: "新浪教程起局实例 6：壬辰日癸卯时",
            datetime: "2003-03-20 05:35",
            dingju: "拆补法",
            dun: "阳遁",
            jieqi: "惊蛰",
            ju: 4,
            sanyuan: "下元",
            pillars: ["癸未", "乙卯", "壬辰", "癸卯"],
            zhifu: "天柱带辛",
            zhifuPalaceEngine: 9,
            zhifuPalaceSource: 9,
            zhishi: "惊门",
            zhishiPalaceEngine: 7,
            zhishiPalaceSource: 7,
            sourceName: "新浪《奇门遁甲入门教程》起局实例 6",
            sourceText: "壬辰日甲申庚旬，申为中元，惊蛰阳 4 局；癸卯时甲午辛旬，值符天柱带辛，值使惊门；时干癸落九宫，值符落九宫；时支卯（午7未8申9酉1戌2亥3子4丑5寅6卯7）落七宫，值使惊门落七宫。",
            sourceUrl: "http://k.sina.cn/article_6398138586_17d5bd8da0010036ro.html",
            yingyan: "无（典籍算例，仅核定局与值符值使）",
            verified: "引擎复核：惊蛰阳 4 局下元，值符天柱落 9 宫，值使惊门，局／星／门／值符宫一致。",
            status: "已验",
            zhifuNote: "",
            zhishiNote: "口径已裁决（2026-11-08 奇门大修）：引擎改旬首起数＋数字宫序 1→9（含中五寄坤二），与教程值一致；依据《遁甲演义》卷二·地遁辛卯时。",
        ),
        QimenCase(
            id: "qimen-case-07",
            title: "《奇门元灵经》算例：芒种后癸亥日丙辰时",
            datetime: "2026-06-18 08:00",
            dingju: "拆补法",
            dun: "阳遁",
            jieqi: "芒种",
            ju: 9,
            sanyuan: "下元",
            pillars: ["丙午", "甲午", "癸亥", "丙辰"],
            zhifu: "天禽",
            zhifuPalaceEngine: 7,
            zhifuPalaceSource: nil,
            zhishi: "死门",
            zhishiPalaceEngine: 7,
            zhishiPalaceSource: nil,
            sourceName: "《奇门元灵经》日奇门算例（芒种后癸亥日丙辰时，阳九局下元）",
            sourceText: "芒种后癸亥日丙辰时，阳九局下元。原书未给公历日期，本条以 2026-06-18 癸亥日丙辰时复核。",
            sourceUrl: "https://pdf.fengshui86.com/wzpdf/6254496.pdf",
            yingyan: "无（典籍算例，仅核定局）",
            verified: "引擎复核：2026-06-18 癸亥日丙辰时，芒种阳 9 局下元，值符天禽落 7 宫，值使死门落 7 宫，局数一致。",
            status: "已验",
            zhifuNote: "",
            zhishiNote: "",
        ),
        QimenCase(
            id: "qimen-case-08",
            title: "《奇门遁甲统宗》算例：康熙五十七年芒种置闰",
            datetime: "1718-06-14 08:00",
            dingju: "置闰法",
            dun: "阳遁",
            jieqi: "芒种",
            ju: 6,
            sanyuan: "上元",
            pillars: ["戊戌", "戊午", "甲子", "戊辰"],
            zhifu: "天心",
            zhifuPalaceEngine: 6,
            zhifuPalaceSource: nil,
            zhishi: "开门",
            zhishiPalaceEngine: 1,
            zhishiPalaceSource: nil,
            sourceName: "《奇门遁甲统宗》卷一置闰法（康熙五十七年芒种置闰）",
            sourceText: "农历五月十六甲子日为闰奇上局（芒种闰奇上局阳 6 局）；农历五月初一己酉为芒种上局，五月廿一己巳为闰奇中局，五月廿六甲戌为闰奇下局，六月初二己卯始为夏至上局。农历日期经 lunar_python 换算为公历（五月十六甲子＝1718-06-14）。",
            sourceUrl: "https://ctext.org/wiki.pl?if=en&chapter=666094",
            yingyan: "无（典籍算例，仅核定局与置闰）",
            verified: "引擎复核：置闰行走 1718-06-14 为芒种闰奇上局阳 6 局（runqi=True），值符天心落 6 宫，值使开门落 1 宫；拆补法同日为芒种上元阳 6 局（闰奇上局期间两者同局，分叉在夏至交节后）。",
            status: "已验",
            zhifuNote: "",
            zhishiNote: "",
        ),
    ]
}
struct QimenCasesView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("只收公开记载、可核验的奇门案例。典籍／教程算例仅核定局与值符值使，无实战应验记录，应验栏如实写“无”。值使落宫口径差异见各条标注（待裁决）。")
                    .font(.caption).foregroundStyle(Ky.sub)
                ForEach(QimenCases.all) { c in
                    caseCard(c)
                }
                Text("回验登记走“前瞻登记”（ForecastModule），每条案例登记一条前瞻，来源标记 qimen_case。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16).padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle("奇门案例库").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Ky.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
    // P2：案例纯文本分享摘要（不新增图片渲染、不碰引擎）
    private func caseShareText(_ c: QimenCase) -> String {
        let lines = [
            "【奇门案例】\(c.title)",
            "起局时间：\(c.datetime)",
            "定局：\(c.dingju) · \(c.dun) \(c.ju) 局 · \(c.sanyuan) · \(c.jieqi)",
            "四柱：\(c.pillars.joined(separator: " "))",
            "值符 / 值使：\(c.zhifu) / \(c.zhishi)",
            "来源：\(c.sourceName)",
            "应验：\(c.yingyan)",
        ]
        return lines.joined(separator: "\n")
    }
    private func caseCard(_ c: QimenCase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(c.title).font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
            infoRow("起局时间", c.datetime)
            infoRow("定局", "\(c.dingju) · \(c.dun) \(c.ju) 局 · \(c.sanyuan) · \(c.jieqi)")
            infoRow("四柱", c.pillars.joined(separator: " "))
            infoRow("值符 / 值使", "\(c.zhifu) / \(c.zhishi)")
            infoRow("值符落宫", "引擎 \(c.zhifuPalaceEngine) 宫\(c.zhifuPalaceSource.map { " · 教程 \($0) 宫" } ?? "")")
            infoRow("值使落宫", "引擎 \(c.zhishiPalaceEngine) 宫\(c.zhishiPalaceSource.map { " · 教程 \($0) 宫" } ?? "")")
            if !c.zhifuNote.isEmpty {
                Text(c.zhifuNote).font(.caption).foregroundStyle(Ky.cinnabar)
            }
            if !c.zhishiNote.isEmpty {
                Text(c.zhishiNote).font(.caption).foregroundStyle(Ky.cinnabar)
            }
            Text("局象原文：\(c.sourceText)").font(.callout).foregroundStyle(Ky.ink)
            Text("来源：\(c.sourceName)").font(.caption).foregroundStyle(Ky.sub)
            Text("应验：\(c.yingyan)").font(.callout).foregroundStyle(Ky.ink)
            Text("复核：\(c.verified)").font(.callout).foregroundStyle(Ky.qingdai)
            Text("状态：\(c.status)").font(.caption).foregroundStyle(Ky.sub)
            ShareLink(item: caseShareText(c)) {
                Label("分享案例", systemImage: "square.and.arrow.up")
            }
            .font(.callout).foregroundStyle(Ky.qingdai)
        }.kyCard()
    }
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(Ky.sub).frame(width: 72, alignment: .leading)
            Text(value).font(.callout).foregroundStyle(Ky.ink)
            Spacer()
        }
    }
}

// MARK: - 界面

struct QimenHomeView: View {
    @State private var date = Date()
    @State private var qmPersonName = ""
    // G3 控制：定局法／寄宫／暗干／真太阳时／日家显示
    @State private var dingju = "拆补法"
    @State private var jigong: QimenJigong = .kun2
    @State private var angan = true
    @State private var solar = false
    @State private var longitude = 107.8
    @State private var showRijia = false
    @State private var rijiaChart: QimenEngine.RijiaChart? = nil
    // P2：九宫盘宫位点击详情弹层
    @State private var selectedPalace: Int? = nil
    @State private var showPalaceSheet = false
    // 起局只在时间变时算一次：排盘是纯计算但不便宜，body 每求值一次就重算会拖滑动；
    // 初值直接起局，避免首帧先闪一下「未能起局」
    @State private var cachedChart: QimenEngine.Chart? = QimenEngine.chart(for: Date())
    /// 按当前 G3 参数重起局（定局法／寄宫／暗干／真太阳时／日家）
    private func recompute() {
        let lon: Double? = solar ? longitude : nil
        if dingju == "置闰法" {
            cachedChart = QimenEngine.zhiyunChart(for: date, jigong: jigong, angan: angan, longitude: lon)
        } else {
            cachedChart = QimenEngine.chart(for: date, longitude: lon, jigong: jigong, angan: angan)
        }
        rijiaChart = showRijia ? QimenEngine.rijiaChart(for: date, longitude: lon) : nil
    }
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy年M月d日 HH:mm"; f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return f
    }()
    private static let weekdayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "EEEE"
        return f
    }()
    private var dateText: String { Self.dateFmt.string(from: date) }
    private var weekdayText: String { Self.weekdayFmt.string(from: date) }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                PersonQuickBar(store: PeopleStore.shared) { p in
                    date = p.birthDate
                    qmPersonName = p.name
                }
                // 时间选择
                VStack(alignment: .leading, spacing: 10) {
                    Text("起局时间：\(dateText) \(weekdayText)").font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
                    if !qmPersonName.isEmpty {
                        Text("起局命主：\(qmPersonName)（已按其生辰起局）").font(.caption).foregroundStyle(Ky.qingdai)
                    }
                    HStack {
                        DatePicker("起局时间", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .environment(\.locale, Locale(identifier: "zh_CN")) // 锁死中文
                        Spacer()
                        Button("上一时辰") { date = date.addingTimeInterval(-7200) }
                            .font(.subheadline).foregroundStyle(Ky.qingdai)
                        Button("下一时辰") { date = date.addingTimeInterval(7200) }
                            .font(.subheadline).foregroundStyle(Ky.qingdai)
                        Button("此刻") { date = Date() }
                            .font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                    }
                    Text("默认此刻；改时间即重起局。时辰按北京时间取，晚子时口径与八字排盘一致。")
                        .font(.caption2).foregroundStyle(Ky.sub)
                    DisclosureGroup("起局口径") {
                        Picker("定局法", selection: $dingju) {
                            Text("拆补法").tag("拆补法")
                            Text("置闰法").tag("置闰法")
                        }.pickerStyle(.segmented)
                        Picker("寄宫", selection: $jigong) {
                            ForEach(QimenJigong.allCases, id: \.self) { j in
                                Text(j.name).tag(j)
                            }
                        }
                        Toggle("布暗干（值使门起）", isOn: $angan)
                        Toggle("真太阳时校正", isOn: $solar)
                        HStack {
                            Text("经度").font(.caption).foregroundStyle(Ky.sub)
                            TextField("经度", value: $longitude, format: .number)
                                .keyboardType(.decimalPad)
                                .disabled(!solar)
                                .textFieldStyle(.roundedBorder)
                            Text("°（默认 107.8 梁平）").font(.caption2).foregroundStyle(Ky.sub)
                        }
                        Toggle("显示日家盘", isOn: $showRijia)
                        Text("定局法、寄宫、暗干、真太阳时切换即重起局；口径见局象卡收据行。")
                            .font(.caption2).foregroundStyle(Ky.sub)
                    }
                }.kyCard()
                if let ch = cachedChart {
                    infoCard(ch)
                    boardCard(ch)
                        .kyBottomSheet(isPresented: $showPalaceSheet, title: palaceSheetTitle) {
                            palaceSheetContent(ch)
                        }
                    layersCard(ch)
                    changshengCard(ch)
                    if let rj = rijiaChart { rijiaCard(rj) }
                    patternCard(ch)
                    yongShenCard()
                    glossaryCard()
                    NavigationLink("奇门案例库（8 条已验）") { QimenCasesView() }
                        .font(.callout).foregroundStyle(Ky.qingdai)
                } else {
                    Text("未能起局：节气或干支不在口径表内，请换个时间再试。")
                        .font(.callout).foregroundStyle(Ky.cinnabar)
                        .onAppear { AppErrorCenter.shared.report("奇门起局失败：当前时间不在定局口径表内，请换个时间再试。") }
                }
                Text("仅供娱乐与决策参考，不作最终决定；大事仍须结合实际情况与专业意见定。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16).padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle("奇门遁甲").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Ky.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { recompute() }
        .onChange(of: date) { _, _ in recompute() }
        .onChange(of: dingju) { _, _ in recompute() }
        .onChange(of: jigong) { _, _ in recompute() }
        .onChange(of: angan) { _, _ in recompute() }
        .onChange(of: solar) { _, _ in recompute() }
        .onChange(of: longitude) { _, _ in recompute() }
        .onChange(of: showRijia) { _, _ in recompute() }
    }

    private func infoCard(_ ch: QimenEngine.Chart) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(ch.yang ? "阳遁" : "阴遁") \(ch.ju) 局 · \(ch.sanyuan) · \(ch.jieqi)")
                .font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
            infoRow("公历", dateText)
            infoRow("农历", ch.lunarText)
            infoRow("四柱", ch.pillars.joined(separator: " "))
            infoRow("值符 / 值使", "\(ch.zhiFuStar)星 / \(ch.zhiShiDoor)门")
            infoRow("旬首 / 空亡 / 马星", "\(ch.xunShou)旬 · 空 \(ch.kongWang) · 马 \(ch.maXing)")
            Text(ch.receiptText()).font(.caption).foregroundStyle(Ky.sub)
        }.kyCard()
    }
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(Ky.sub).frame(width: 92, alignment: .leading)
            Text(value).font(.callout).foregroundStyle(Ky.ink)
            Spacer()
        }
    }

    private func boardCard(_ ch: QimenEngine.Chart) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("九宫盘面（后天八卦方位）").font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
            Text("大字为天盘干，小字为地盘干；金框为值符星宫，红框为值使门宫。")
                .font(.caption2).foregroundStyle(Ky.sub)
            let rows = [[4, 9, 2], [3, 5, 7], [8, 1, 6]]
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(rows[r], id: \.self) { p in
                        Button {
                            selectedPalace = p
                            showPalaceSheet = true
                        } label: {
                            cell(ch, palace: p)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }.kyCard()
    }

    // MARK: - P2 宫位详情弹层（只复用已有盘面数据，不改引擎）
    private var palaceSheetTitle: String {
        guard let p = selectedPalace else { return "宫位详情" }
        let name = QimenEngine.palaceName[p] ?? ""
        let dir = QimenEngine.palaceDir[p] ?? ""
        return "\(name)宫 · \(dir)"
    }
    private func glossaryNote(_ list: [(String, String)], key: String) -> String? {
        list.first { $0.0 == key }?.1
    }
    private func siHaiText(_ pc: QimenEngine.Palace) -> String {
        var marks: [String] = []
        if pc.siHaiKong { marks.append("空") }
        if pc.siHaiJiXing { marks.append("击刑") }
        if pc.siHaiRuMu { marks.append("入墓") }
        if pc.siHaiMenPo { marks.append("门迫") }
        return marks.isEmpty ? "无" : marks.joined(separator: "、")
    }
    private func palaceSheetContent(_ ch: QimenEngine.Chart) -> some View {
        Group {
            if let p = selectedPalace, let pc = ch.palaces[p] {
                VStack(alignment: .leading, spacing: 8) {
                    let name = QimenEngine.palaceName[p] ?? ""
                    let dir = QimenEngine.palaceDir[p] ?? ""
                    Text("\(name)宫 · \(dir) · \(p) 宫")
                        .font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
                    infoRow("天盘 / 地盘", "\(pc.tianStem ?? "—") / \(pc.diStem)")
                    if let hosted = pc.hostedTianStem {
                        Text("中宫原干 \(hosted) 随芮落此宫").font(.caption).foregroundStyle(Ky.sub)
                    }
                    if let star = pc.star {
                        infoRow("星", "\(star)星")
                        if let note = glossaryNote(QimenGlossary.stars, key: "天\(star)") {
                            Text(note).font(.callout).foregroundStyle(Ky.sub)
                        }
                    } else {
                        infoRow("星", "—")
                    }
                    if pc.hostedStar == "禽" {
                        Text("天禽随芮落此宫").font(.caption).foregroundStyle(Ky.sub)
                    }
                    if let door = pc.door {
                        infoRow("门", "\(door)门")
                        if let note = glossaryNote(QimenGlossary.doors, key: "\(door)门") {
                            Text(note).font(.callout).foregroundStyle(Ky.sub)
                        }
                    } else {
                        infoRow("门", "—")
                    }
                    if let god = pc.god {
                        infoRow("神", god)
                        if let note = glossaryNote(QimenGlossary.gods, key: god) {
                            Text(note).font(.callout).foregroundStyle(Ky.sub)
                        }
                    } else {
                        infoRow("神", "—")
                    }
                    infoRow("四害", siHaiText(pc))
                    if let ky = pc.keYingName {
                        infoRow("克应", ky)
                        if let note = pc.keYingNote {
                            Text(note).font(.callout).foregroundStyle(Ky.sub)
                        }
                    } else {
                        infoRow("克应", "无")
                    }
                    if let cs = pc.changshengTian {
                        let ordered = cs.sorted { (QimenEngine.branches.firstIndex(of: $0.key) ?? 0) < (QimenEngine.branches.firstIndex(of: $1.key) ?? 0) }
                        infoRow("长生", ordered.map { "\($0.key)\($0.value)" }.joined(separator: " "))
                    } else {
                        infoRow("长生", "中宫无本位地支")
                    }
                    infoRow("暗干", pc.angan.map { "暗\($0)" } ?? "无")
                    if pc.patterns.isEmpty {
                        infoRow("格局", "无")
                    } else {
                        Text("格局").font(.callout).fontWeight(.semibold).foregroundStyle(Ky.ink)
                        ForEach(pc.patterns) { pat in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pat.name).font(.callout).fontWeight(.semibold)
                                    .foregroundStyle(pat.good ? Ky.jade : Ky.cinnabar)
                                Text(glossaryNote(QimenGlossary.patterns, key: pat.name) ?? pat.note)
                                    .font(.callout).foregroundStyle(Ky.sub)
                            }
                        }
                    }
                }
            } else {
                Text("未选中宫位").font(.callout).foregroundStyle(Ky.sub)
            }
        }
    }

    private func cell(_ ch: QimenEngine.Chart, palace p: Int) -> some View {
        guard let pc = ch.palaces[p] else { return AnyView(EmptyView()) }
        let isFu = ch.zhiFuPalace == p
        let isShi = ch.zhiShiPalace == p
        let name = QimenEngine.palaceName[p] ?? ""
        let dir = QimenEngine.palaceDir[p] ?? ""
        let a11y = "\(name)宫·\(dir)：天盘\(pc.tianStem ?? "无")，地盘\(pc.diStem)，\(pc.star.map { "\($0)星" } ?? "无星")，\(pc.door ?? "无门")，\(pc.god ?? "无神")\(pc.patterns.isEmpty ? "" : "，格局：" + pc.patterns.map { $0.name }.joined(separator: "、"))"
        return AnyView(
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("\(name)\(p)").font(.caption2).fontWeight(.semibold).foregroundStyle(Ky.sub)
                    if isFu { Text("值符").font(.system(size: 9)).fontWeight(.bold).foregroundStyle(Ky.gold) }
                    if isShi { Text("值使").font(.system(size: 9)).fontWeight(.bold).foregroundStyle(Ky.cinnabar) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(pc.tianStem ?? "—").font(.system(.title3, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                    Text(pc.diStem).font(.caption).foregroundStyle(Ky.sub)
                }
                Text(pc.star.map { "\($0)星" } ?? "—").font(.callout).foregroundStyle(Ky.ink)
                Text(pc.door.map { "\($0)门" } ?? "—").font(.callout).foregroundStyle(Ky.ink)
                Text(pc.god.map { "\($0)神" } ?? "—").font(.caption).foregroundStyle(Ky.sub)
                HStack(spacing: 4) {
                    if pc.siHaiKong { Text("空").font(.system(size: 9)).fontWeight(.bold).foregroundStyle(Ky.cinnabar) }
                    if pc.siHaiJiXing { Text("刑").font(.system(size: 9)).fontWeight(.bold).foregroundStyle(Ky.cinnabar) }
                    if pc.siHaiRuMu { Text("墓").font(.system(size: 9)).fontWeight(.bold).foregroundStyle(Ky.cinnabar) }
                    if pc.siHaiMenPo { Text("迫").font(.system(size: 9)).fontWeight(.bold).foregroundStyle(Ky.cinnabar) }
                }
                if let cs = pc.changshengTian {
                    let ordered = cs.sorted { (QimenEngine.branches.firstIndex(of: $0.key) ?? 0) < (QimenEngine.branches.firstIndex(of: $1.key) ?? 0) }
                    Text(ordered.map { "\($0.key)\($0.value)" }.joined(separator: " ")).font(.system(size: 10)).foregroundStyle(Ky.sub)
                }
                if let ag = pc.angan {
                    Text("暗\(ag)").font(.system(size: 10)).foregroundStyle(Ky.sub)
                }
                ForEach(pc.patterns) { pat in
                    Text(pat.name).font(.system(size: 10)).fontWeight(.semibold)
                        .foregroundStyle(pat.good ? Ky.jade : Ky.cinnabar)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(isFu ? Ky.gold.opacity(0.14) : (isShi ? Ky.cinnabar.opacity(0.08) : Ky.card))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isFu ? Ky.gold : (isShi ? Ky.cinnabar : Ky.line.opacity(0.7)), lineWidth: isFu || isShi ? 1.4 : 0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel(a11y)
        )
    }

    // MARK: - G3 后段层卡片
    private func layersCard(_ ch: QimenEngine.Chart) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("四害与克应").font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
            if ch.shiGanRumu {
                Text("时干入墓：本局时柱入墓，问事多阻滞，宜缓。").font(.callout).foregroundStyle(Ky.cinnabar)
            }
            ForEach(1...9, id: \.self) { p in
                if let pc = ch.palaces[p] {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(QimenEngine.palaceName[p] ?? "")宫").font(.callout).fontWeight(.semibold).foregroundStyle(Ky.ink).frame(width: 34, alignment: .leading)
                            if pc.siHaiKong { Text("空").font(.system(size: 10)).fontWeight(.semibold).foregroundStyle(Ky.cinnabar) }
                            if pc.siHaiJiXing { Text("击刑").font(.system(size: 10)).fontWeight(.semibold).foregroundStyle(Ky.cinnabar) }
                            if pc.siHaiRuMu { Text("入墓").font(.system(size: 10)).fontWeight(.semibold).foregroundStyle(Ky.cinnabar) }
                            if pc.siHaiMenPo { Text("门迫").font(.system(size: 10)).fontWeight(.semibold).foregroundStyle(Ky.cinnabar) }
                            if let ky = pc.keYingName {
                                Text(ky).font(.callout).foregroundStyle(Ky.ink)
                            }
                            Spacer()
                        }
                        if let note = pc.keYingNote {
                            Text(note).font(.caption).foregroundStyle(Ky.sub)
                        }
                    }
                }
            }
            Text("四害：空（旬空）、击刑（六仪击刑，天盘干口径）、入墓（三奇入墓）、门迫（门克宫）。克应：十干克应（天盘干加地盘干，hkfff.cn 全表）。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }.kyCard()
    }

    private func changshengCard(_ ch: QimenEngine.Chart) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("十二长生（阳顺阴逆）").font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
            if let ri = ch.riGan {
                changshengRow(label: "日干 \(ri)", table: ch.changshengTable(stem: ri))
            }
            if ch.pillars.count == 4 {
                let shi = String(ch.pillars[3].prefix(1))
                changshengRow(label: "时干 \(shi)", table: ch.changshengTable(stem: shi))
            }
            Text("每宫天盘干长生见九宫格小字：四正宫一值，四维宫两值，中宫无本位地支。出处：《五行大义·论生死》，《渊海子平》《三命通会》通行表。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }.kyCard()
    }
    private func changshengRow(label: String, table: [(branch: String, palace: Int, stage: String)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.callout).fontWeight(.semibold).foregroundStyle(Ky.ink)
            Text(table.map { "\($0.branch)\($0.stage)" }.joined(separator: " ")).font(.caption).foregroundStyle(Ky.sub)
        }
    }

    private func rijiaCard(_ rj: QimenEngine.RijiaChart) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("日家奇门 · \(rj.yang ? "阳遁" : "阴遁") \(rj.ju) 局 · \(rj.jieqi)").font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
            Text(rj.receiptText()).font(.caption).foregroundStyle(Ky.sub)
            let rows = [[4, 9, 2], [3, 5, 7], [8, 1, 6]]
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(rows[r], id: \.self) { p in
                        rijiaCell(rj, palace: p)
                    }
                }
            }
        }.kyCard()
    }
    private func rijiaCell(_ rj: QimenEngine.RijiaChart, palace p: Int) -> some View {
        guard let pc = rj.palaces[p] else { return AnyView(EmptyView()) }
        let name = QimenEngine.palaceName[p] ?? ""
        return AnyView(
            VStack(alignment: .leading, spacing: 3) {
                Text("\(name)\(p)").font(.caption2).fontWeight(.semibold).foregroundStyle(Ky.sub)
                Text(pc.diStem).font(.system(.title3, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                Text("\(pc.star)星").font(.callout).foregroundStyle(Ky.ink)
                Text(pc.door.map { "\($0)门" } ?? "—").font(.callout).foregroundStyle(Ky.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Ky.card)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Ky.line.opacity(0.7), lineWidth: 0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        )
    }

    private func patternCard(_ ch: QimenEngine.Chart) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("格局（本局命中）").font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
            if ch.hitPatterns.isEmpty {
                Text("本局无 v1 格局命中——无格局也是一种信息：盘面平顺，无特殊吉凶标记。")
                    .font(.callout).foregroundStyle(Ky.sub)
            } else {
                ForEach(ch.hitPatterns.indices, id: \.self) { i in
                    let (p, pat) = ch.hitPatterns[i]
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(QimenEngine.palaceName[p] ?? "")宫").font(.caption).fontWeight(.semibold)
                            .foregroundStyle(pat.good ? Ky.jade : Ky.cinnabar).frame(width: 34, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pat.name).font(.callout).fontWeight(.semibold).foregroundStyle(Ky.ink)
                            Text(pat.note).font(.caption).foregroundStyle(Ky.sub)
                        }
                    }
                }
            }
        }.kyCard()
    }

    private func yongShenCard() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("用神速查（通参）").font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
            ForEach(QimenGlossary.yongShen.indices, id: \.self) { i in
                HStack {
                    Text(QimenGlossary.yongShen[i].0).font(.callout).fontWeight(.semibold).foregroundStyle(Ky.ink).frame(width: 44, alignment: .leading)
                    Text(QimenGlossary.yongShen[i].1).font(.callout).foregroundStyle(Ky.sub)
                    Spacer()
                }
            }
            Text("用神只给看盘的入口，具体断语须结合落宫旺衰、格局与问事背景综合看，不可单凭一行取用。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }.kyCard()
    }

    private func glossaryCard() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("释义库").font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
            DisclosureGroup("八门") {
                ForEach(QimenGlossary.doors.indices, id: \.self) { i in
                    HStack(alignment: .top) {
                        Text(QimenGlossary.doors[i].0).font(.callout).fontWeight(.semibold).foregroundStyle(Ky.ink).frame(width: 52, alignment: .leading)
                        Text(QimenGlossary.doors[i].1).font(.callout).foregroundStyle(Ky.sub)
                        Spacer()
                    }.padding(.vertical, 2)
                }
            }
            DisclosureGroup("九星") {
                ForEach(QimenGlossary.stars.indices, id: \.self) { i in
                    HStack(alignment: .top) {
                        Text(QimenGlossary.stars[i].0).font(.callout).fontWeight(.semibold).foregroundStyle(Ky.ink).frame(width: 52, alignment: .leading)
                        Text(QimenGlossary.stars[i].1).font(.callout).foregroundStyle(Ky.sub)
                        Spacer()
                    }.padding(.vertical, 2)
                }
            }
            DisclosureGroup("八神") {
                ForEach(QimenGlossary.gods.indices, id: \.self) { i in
                    HStack(alignment: .top) {
                        Text(QimenGlossary.gods[i].0).font(.callout).fontWeight(.semibold).foregroundStyle(Ky.ink).frame(width: 52, alignment: .leading)
                        Text(QimenGlossary.gods[i].1).font(.callout).foregroundStyle(Ky.sub)
                        Spacer()
                    }.padding(.vertical, 2)
                }
            }
            DisclosureGroup("格局 v1") {
                ForEach(QimenGlossary.patterns.indices, id: \.self) { i in
                    HStack(alignment: .top) {
                        Text(QimenGlossary.patterns[i].0).font(.callout).fontWeight(.semibold).foregroundStyle(Ky.ink).frame(width: 72, alignment: .leading)
                        Text(QimenGlossary.patterns[i].1).font(.callout).foregroundStyle(Ky.sub)
                        Spacer()
                    }.padding(.vertical, 2)
                }
            }
        }.kyCard()
    }
}
