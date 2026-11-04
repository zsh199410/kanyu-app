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
import SwiftUI
import LunarSwift

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
    static let seq8 = [1, 2, 3, 4, 9, 8, 7, 6]
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
        var tianStem: String
        var star: String
        var door: String?
        var god: String?
        var patterns: [Pattern] = []
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
        var hourPalace: Int
        var zhiShiPalace: Int
        var kongWang: String
        var maXing: String
        var xunShou: String
        var palaces: [Int: Palace]
        var hitPatterns: [(palace: Int, pattern: Pattern)] {
            palaces.sorted { $0.key < $1.key }.flatMap { p in p.value.patterns.map { (p.key, $0) } }
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

    /// 直接按局数/阴阳/时干支起盘（测试与金标准用；日期版见 chart(for:)）。
    static func chart(ju: Int, yang: Bool, hourStem: String, hourBranch: String) -> Chart? {
        guard let xun = xunShou(hourPillar: hourStem + hourBranch) else { return nil }
        // 地盘干
        var di: [Int: String] = [:]
        for i, s in seqStems.enumerated() {
            let p = yang ? (ju - 1 + i) % 9 + 1 : ((ju - 1 - i) % 9 + 9) % 9 + 1
            di[p] = s
        }
        guard let dunPal = di.first(where: { $0.value == xun.dun })?.key,
              let zhiFu = baseStar[dunPal] else { return nil }
        let zhiShi = baseDoor[dunPal] ?? "死"  // 中宫寄坤死
        // 时干宫（甲时遁戊）
        let hs = hourStem == "甲" ? "戊" : hourStem
        guard let hourPal = di.first(where: { $0.value == hs })?.key else { return nil }
        func flyPalace(from start: Int, steps: Int, yang: Bool) -> Int {
            yang ? (start - 1 + steps) % 9 + 1 : ((start - 1 - steps) % 9 + 9) % 9 + 1
        }
        // 天盘星 / 天盘干（含中宫）
        var stars: [Int: String] = [:]
        var tian: [Int: String] = [:]
        let si = seqStars.firstIndex(of: zhiFu)!
        let di0 = seqStems.firstIndex(of: xun.dun)!
        for k in 0..<9 {
            let p = flyPalace(from: hourPal, steps: k, yang: yang)
            stars[p] = seqStars[(si + k) % 9]
            tian[p] = seqStems[(di0 + k) % 9]
        }
        // 人盘门（跳中宫）
        let zhiShiBase = dunPal == 5 ? 2 : dunPal
        let pos = seq8.firstIndex(of: zhiShiBase)!
        let bi = branches.firstIndex(of: hourBranch)!
        let zhiShiPal = seq8[yang ? (pos + bi) % 8 : (pos - bi + 80) % 8]
        var doors: [Int: String] = [:]
        let d0 = seqDoors.firstIndex(of: zhiShi)!
        let zp = seq8.firstIndex(of: zhiShiPal)!
        for k in 0..<8 {
            let p = seq8[yang ? (zp + k) % 8 : (zp - k + 80) % 8]
            doors[p] = seqDoors[(d0 + k) % 8]
        }
        // 神盘（跳中宫；时干宫为中宫时值符神寄坤）
        var gods: [Int: String] = [:]
        let godStart = hourPal == 5 ? 2 : hourPal
        let sp = seq8.firstIndex(of: godStart)!
        for k in 0..<8 {
            let p = seq8[yang ? (sp + k) % 8 : (sp - k + 80) % 8]
            gods[p] = seqGods[k]
        }
        // 格局 v1
        var palaces: [Int: Palace] = [:]
        for p in 1...9 {
            var pats: [Pattern] = []
            let t = tian[p]!, d = di[p]!
            func add(_ name: String, _ good: Bool, _ note: String) { pats.append(Pattern(name: name, good: good, note: note)) }
            if t == d { add("伏吟", false, "天盘干与地盘干同宫：伏吟主迟滞，事宜缓、不宜急进。") }
            if stemChong[t] == d { add("反吟", false, "天盘干冲地盘干：反吟主反复变动，计划易生变，宜留后手。") }
            if t == "戊" && d == "丙" { add("青龙返首", true, "天戊临丙：青龙回头看顾，事情容易顺着来，宜主动推进。") }
            if t == "丙" && d == "戊" { add("飞鸟跌穴", true, "天丙临戊：飞鸟落回巢里，谋事容易落定，宜静守、宜收成。") }
            if t == "辛" && d == "乙" { add("白虎猖狂", false, "天辛临乙：白虎猖狂，主口舌是非、意外损伤，宜低调避让。") }
            if t == "丁" && d == "癸" { add("朱雀投江", false, "天丁临癸：朱雀投江，主文书口舌、信息失真，文书事须再三核对。") }
            if t == "癸" && d == "丁" { add("螣蛇夭矫", false, "天癸临丁：螣蛇夭矫，主虚惊怪异、事多反复，宜多方核实再定。") }
            if (t == "乙" && (d == "辛" || d == "己")) || (t == "丙" && (d == "戊" || d == "庚")) || (t == "丁" && (d == "癸" || d == "壬")) {
                add("三奇得使", true, "三奇得其使（统宗严格版）：天盘奇加临地盘旬首之仪，奇门有靠，贵人暗助，宜借力行事。")
            }
            if p == zhiShiPal && d == "丁" { add("玉女守门", true, "值使门落宫逢丁奇守门：事有暗助，宜私下谋划、暗中推进。") }
            if let door = doors[p], let dw = doorWx[door], let pw = palaceWx[p], ke[dw] == pw {
                add("门迫", false, "门克宫：此宫行事多阻力，不宜硬来，宜绕道或换个打法。")
            }
            palaces[p] = Palace(diStem: d, tianStem: t, star: stars[p]!, door: doors[p], god: gods[p], patterns: pats)
        }
        return Chart(date: Date(), pillars: [], lunarText: "", jieqi: "", yang: yang, ju: ju, sanyuan: "",
                     zhiFuStar: zhiFu, zhiShiDoor: zhiShi, hourPalace: hourPal, zhiShiPalace: zhiShiPal,
                     kongWang: kongWang(xun: xun.xun), maXing: maXing(hourBranch: hourBranch), xunShou: xun.xun,
                     palaces: palaces)
    }

    /// 日期版：四柱取 BaziEngine.paipan（金标准口径），节气取 LunarSwift prevJieQi。
    static func chart(for date: Date) -> Chart? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let y = c.year, let mo = c.month, let d = c.day, let h = c.hour, let mi = c.minute else { return nil }
        let solar = Solar.fromYmdHms(year: y, month: mo, day: d, hour: h, minute: mi)
        let lunar = solar.lunar
        let jieqi = lunar.prevJieQi.name
        guard let table = juTable[jieqi] else { return nil }
        let yang = yangJieqi.contains(jieqi)
        let bazi = BaziEngine.paipan(clock: date, gender: "M", longitude: nil)
        guard let fu = fuTou(dayPillar: bazi.dayPillar), let sanyuan = sanyuanOfFu[fu] else { return nil }
        let ju = sanyuan == "上元" ? table.0 : (sanyuan == "中元" ? table.1 : table.2)
        let timePillar = bazi.timePillar
        guard var plate = chart(ju: ju, yang: yang, hourStem: String(timePillar.prefix(1)), hourBranch: String(timePillar.suffix(1))) else { return nil }
        plate.date = date
        plate.pillars = bazi.pillars
        plate.lunarText = "\(lunar.monthInChinese)月\(lunar.dayInChinese)"
        plate.jieqi = jieqi
        plate.sanyuan = sanyuan
        return plate
    }
}

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

// MARK: - 界面

struct QimenHomeView: View {
    @State private var date = Date()
    private var chart: QimenEngine.Chart? { QimenEngine.chart(for: date) }
    private var dateText: String {
        let f = DateFormatter(); f.dateFormat = "yyyy年M月d日 HH:mm"; f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return f.string(from: date)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 时间选择
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        DatePicker("起局时间", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                        Spacer()
                        Button("此刻") { date = Date() }
                            .font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                    }
                    Text("默认此刻；改时间即重起局。时辰按北京时间取，晚子时口径与八字排盘一致。")
                        .font(.caption2).foregroundStyle(Ky.sub)
                }.kyCard()
                if let ch = chart {
                    infoCard(ch)
                    boardCard(ch)
                    patternCard(ch)
                    yongShenCard()
                    glossaryCard()
                } else {
                    Text("未能起局：节气或干支不在口径表内，请换个时间再试。")
                        .font(.callout).foregroundStyle(Ky.cinnabar)
                        .onAppear { AppErrorCenter.shared.report("奇门起局失败：当前时间不在定局口径表内，请换个时间再试。") }
                }
                Text("仅供娱乐与决策参考，不作最终决定；大事仍须结合实际情况与专业意见定。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("奇门遁甲").navigationBarTitleDisplayMode(.inline)
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
                        cell(ch, palace: p)
                    }
                }
            }
        }.kyCard()
    }

    private func cell(_ ch: QimenEngine.Chart, palace p: Int) -> some View {
        guard let pc = ch.palaces[p] else { return AnyView(EmptyView()) }
        let isFu = ch.hourPalace == p
        let isShi = ch.zhiShiPalace == p
        let name = QimenEngine.palaceName[p] ?? ""
        let dir = QimenEngine.palaceDir[p] ?? ""
        let a11y = "\(name)宫·\(dir)：天盘\(pc.tianStem)，地盘\(pc.diStem)，\(pc.star)星，\(pc.door ?? "无门")，\(pc.god ?? "无神")\(pc.patterns.isEmpty ? "" : "，格局：" + pc.patterns.map { $0.name }.joined(separator: "、"))"
        return AnyView(
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("\(name)\(p)").font(.caption2).fontWeight(.semibold).foregroundStyle(Ky.sub)
                    if isFu { Text("值符").font(.system(size: 9)).fontWeight(.bold).foregroundStyle(Ky.gold) }
                    if isShi { Text("值使").font(.system(size: 9)).fontWeight(.bold).foregroundStyle(Ky.cinnabar) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(pc.tianStem).font(.system(.title3, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                    Text(pc.diStem).font(.caption).foregroundStyle(Ky.sub)
                }
                Text("\(pc.star)星").font(.callout).foregroundStyle(Ky.ink)
                Text(pc.door.map { "\($0)门" } ?? "—").font(.callout).foregroundStyle(Ky.ink)
                Text(pc.god.map { "\($0)神" } ?? "—").font(.caption).foregroundStyle(Ky.sub)
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
