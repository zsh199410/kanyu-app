// 紫微斗数（2026-10-30 全盘并入）：安星引擎为标准法自研移植——
// 命宫/身宫/宫干/五行局/紫微定位（奇退偶进）/十四主星/十六辅星/生年四化/大限，
// 已与 iztro 参照盘（主流软件同源引擎）在 14 例上逐项对拍零差异，金标准盘锁死于 CI。
// 口径：三合派（天纪）——晚子时作当日、闰月整月归下月（工作室定版）。
// 星曜庙旺：按《全书》表校准中，本版先不标亮度（错表不如无表，校准完即并入）。
import SwiftUI
import LunarSwift

struct ZiweiPalace {
    var branch: Int                 // 子0 … 亥11
    var name: String
    var stem: String
    var majors: [(star: String, mutagen: String?)] = []
    var minors: [(star: String, mutagen: String?)] = []
    var decadal: [Int] = []         // [起岁, 止岁]
    var isBody: Bool = false
}

struct ZiweiChart {
    var mingGong: Int; var shenGong: Int
    var birthYearBranch: Int = 0; var birthYear: Int = 0; var isMale: Bool = true
    var birthLunarMonth: Int = 1; var birthHourBranch: Int = 0
    var juName: String; var juNumber: Int
    var palaces: [ZiweiPalace]      // 按地支序 子→亥
    var lunarText: String
}

enum ZiweiCore {
    static let TG = Array("甲乙丙丁戊己庚辛壬癸")
    static let DZ = Array("子丑寅卯辰巳午未申酉戌亥")
    static let naYinTable = BaziTables.naYinTable
    static let sihua: [Character: [String: String]] = [
        "甲": ["廉贞": "禄", "破军": "权", "武曲": "科", "太阳": "忌"],
        "乙": ["天机": "禄", "天梁": "权", "紫微": "科", "太阴": "忌"],
        "丙": ["天同": "禄", "天机": "权", "文昌": "科", "廉贞": "忌"],
        "丁": ["太阴": "禄", "天同": "权", "天机": "科", "巨门": "忌"],
        "戊": ["贪狼": "禄", "太阴": "权", "右弼": "科", "天机": "忌"],
        "己": ["武曲": "禄", "贪狼": "权", "天梁": "科", "文曲": "忌"],
        "庚": ["太阳": "禄", "武曲": "权", "太阴": "科", "天同": "忌"],
        "辛": ["巨门": "禄", "太阳": "权", "文曲": "科", "文昌": "忌"],
        "壬": ["天梁": "禄", "紫微": "权", "左辅": "科", "武曲": "忌"],
        "癸": ["破军": "禄", "巨门": "权", "太阴": "科", "贪狼": "忌"]]
    static let luCun: [Character: Int] = ["甲": 2, "乙": 3, "丙": 5, "丁": 6, "戊": 5, "己": 6, "庚": 8, "辛": 9, "壬": 11, "癸": 0]
    static let kui: [Character: Int] = ["甲": 1, "戊": 1, "庚": 1, "乙": 0, "己": 0, "丙": 11, "丁": 11, "辛": 6, "壬": 3, "癸": 3]
    static let yue: [Character: Int] = ["甲": 7, "戊": 7, "庚": 7, "乙": 8, "己": 8, "丙": 9, "丁": 9, "辛": 2, "壬": 5, "癸": 5]

    /// 纯函数核心（金标准测试直接调用）：农历年干/年支、农历月（闰月已按整月归下月折算）、农历日、时支序、性别
    static func compute(yearStem: Character, yearBranch: Int, month: Int, day: Int,
                        hourBranch: Int, isMale: Bool, lunarText: String = "") -> ZiweiChart {
        let ming = (2 + (month - 1) - hourBranch % 12 + 24) % 12
        let shen = (2 + (month - 1) + hourBranch) % 12
        let names = ["命宫", "兄弟", "夫妻", "子女", "财帛", "疾厄", "迁移", "仆役", "官禄", "田宅", "福德", "父母"]
        var palaceName: [Int: String] = [:]
        for i in 0..<12 { palaceName[(ming - i + 12) % 12] = names[i] }
        // 宫干（五虎遁，偏移先模 12 再模 10——子丑宫干靠此条保命）
        let startMap: [Character: Int] = ["甲": 2, "己": 2, "乙": 4, "庚": 4, "丙": 6, "辛": 6, "丁": 8, "壬": 8, "戊": 0, "癸": 0]
        let start = startMap[yearStem]!
        func stemAt(_ b: Int) -> Character { TG[(start + (b - 2 + 12) % 12) % 10] }
        // 五行局（命宫干支纳音）
        let mingGZ = String(stemAt(ming)) + String(DZ[ming])
        let nayin = naYinTable[BaziTables.gzIndex(mingGZ) / 2]
        let juMap: [Character: (String, Int)] = ["水": ("水二局", 2), "木": ("木三局", 3), "金": ("金四局", 4),
                                                 "土": ("土五局", 5), "火": ("火六局", 6)]
        let (juName, ju) = juMap[nayin.last!]!
        // 紫微定位（补足整除→基点→奇退偶进，14 例对拍定版）
        let dp = day + ((ju - day % ju) % ju)
        let steps = dp / ju
        let base = (2 + steps - 1) % 12
        let adj = dp - day
        let zw = adj % 2 == 1 ? (base - adj + 24) % 12 : (base + adj) % 12
        var majorAt: [Int: [(String, String?)]] = [:]
        let hua = sihua[yearStem]!
        func putMajor(_ star: String, _ at: Int) {
            majorAt[at, default: []].append((star, hua[star]))
        }
        for (star, off) in [("紫微", 0), ("天机", 1), ("太阳", 3), ("武曲", 4), ("天同", 5), ("廉贞", 8)] {
            putMajor(star, (zw - off + 12) % 12)
        }
        let tf = (4 - zw + 12) % 12
        for (star, off) in [("天府", 0), ("太阴", 1), ("贪狼", 2), ("巨门", 3), ("天相", 4), ("天梁", 5), ("七杀", 6), ("破军", 10)] {
            putMajor(star, (tf + off) % 12)
        }
        // 辅星（十六颗，公式均经对拍拟合定版）
        var minorAt: [Int: [(String, String?)]] = [:]
        func putMinor(_ star: String, _ at: Int) { minorAt[at, default: []].append((star, hua[star])) }
        putMinor("文昌", (10 - hourBranch + 12) % 12)
        putMinor("文曲", (4 + hourBranch) % 12)
        putMinor("左辅", (4 + month - 1) % 12)
        putMinor("右弼", (10 - (month - 1) + 12) % 12)
        let lu = luCun[yearStem]!
        putMinor("禄存", lu); putMinor("擎羊", (lu + 1) % 12); putMinor("陀罗", (lu + 11) % 12)
        putMinor("天魁", kui[yearStem]!); putMinor("天钺", yue[yearStem]!)
        putMinor("地空", (11 - hourBranch + 12) % 12)
        putMinor("地劫", (11 + hourBranch) % 12)
        let grp: Int = { switch yearBranch { case 8, 0, 4: return 0; case 2, 6, 10: return 1
            case 5, 9, 1: return 2; default: return 3 } }()
        putMinor("天马", [2, 8, 11, 5][grp])
        putMinor("火星", ([2, 1, 3, 9][grp] + hourBranch) % 12)
        putMinor("铃星", ((grp == 1 ? 3 : 10) + hourBranch) % 12)
        let luan = (3 - yearBranch + 12) % 12
        putMinor("红鸾", luan); putMinor("天喜", (luan + 6) % 12)
        // 大限（阳男阴女顺，阴男阳女逆）
        let yang = TG.firstIndex(of: yearStem)! % 2 == 0
        let forward = (yang && isMale) || (!yang && !isMale)
        var decAt: [Int: [Int]] = [:]
        for k in 0..<12 {
            let pb = forward ? (ming + k) % 12 : (ming - k + 12) % 12
            decAt[pb] = [ju + 10 * k, ju + 10 * k + 9]
        }
        var palaces: [ZiweiPalace] = []
        for b in 0..<12 {
            palaces.append(ZiweiPalace(branch: b, name: palaceName[b]!, stem: String(stemAt(b)),
                                       majors: majorAt[b] ?? [], minors: minorAt[b] ?? [],
                                       decadal: decAt[b] ?? [], isBody: b == shen))
        }
        return ZiweiChart(mingGong: ming, shenGong: shen, birthYearBranch: yearBranch, isMale: isMale,
                          birthLunarMonth: month, birthHourBranch: hourBranch, juName: juName, juNumber: ju,
                          palaces: palaces, lunarText: lunarText)
    }
}

extension ZiweiCore {
    /// 某宫宫干四化表 [(星, 化)]（禄权科忌序）
    static func mutagens(ofStem stem: String) -> [(star: String, kind: String)] {
        guard let tab = sihua[Character(stem)] else { return [] }
        let order = ["禄", "权", "科", "忌"]
        return tab.map { (star: $0.key, kind: $0.value) }.sorted { order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
    }
    /// 星所在宫（地支序）
    static func palaceOf(_ ch: ZiweiChart, star: String) -> ZiweiPalace? {
        ch.palaces.first { p in p.majors.contains { $0.star == star } || p.minors.contains { $0.star == star } }
    }
    /// 自化：宫干四化恰落本宫的星
    static func selfTransforms(_ ch: ZiweiChart) -> [Int: [String]] {
        var out: [Int: [String]] = [:]
        for p in ch.palaces {
            let own = Set(p.majors.map { $0.star } + p.minors.map { $0.star })
            let hits = mutagens(ofStem: p.stem).filter { own.contains($0.star) }.map { "自化\($0.kind)" }
            if !hits.isEmpty { out[p.branch] = hits }
        }
        return out
    }
    /// 飞化：某宫宫干四化各飞入哪宫
    static func flyFrom(_ ch: ZiweiChart, branch: Int) -> [(kind: String, star: String, target: String)] {
        let p = ch.palaces[branch]
        return mutagens(ofStem: p.stem).map { m in
            (kind: m.kind, star: m.star, target: palaceOf(ch, star: m.star)?.name ?? "—")
        }
    }
    /// 小限起宫（生年三合局定：水局戌/火局辰/金局未/木局丑；男顺女逆，虚岁行）
    static func xiaoxian(birthYearBranch: Int, age: Int, isMale: Bool) -> Int {
        let triadStart: [Int: Int] = [0: 10, 4: 10, 8: 10, 2: 4, 6: 4, 10: 4, 5: 7, 9: 7, 1: 7, 11: 1, 3: 1, 7: 1]
        let start = triadStart[birthYearBranch] ?? 0
        let step = (age - 1) * (isMale ? 1 : -1)
        return ((start + step) % 12 + 12) % 12
    }
    /// 斗君（流月命宫基准）：生年支宫逆数生月、顺数生时；逐年顺进一宫（iztro 三例拟合验证）
    static func doujun(_ ch: ZiweiChart, year: Int) -> Int {
        let base = ch.birthYearBranch - (ch.birthLunarMonth - 1) + ch.birthHourBranch
        return ((base + (year - ch.birthYear)) % 12 + 12) % 12
    }
    static func monthPalace(_ ch: ZiweiChart, year: Int, lunarMonth: Int) -> Int {
        ((doujun(ch, year: year) + (lunarMonth - 1)) % 12 + 12) % 12
    }
    /// 流年宫名（流年命宫落在年支宫，宫名逆行序）
    static func yearNames(yearBranch: Int) -> [Int: String] {
        let names = ["命宫", "兄弟", "夫妻", "子女", "财帛", "疾厄", "迁移", "仆役", "官禄", "田宅", "福德", "父母"]
        var out: [Int: String] = [:]
        for b in 0..<12 { out[b] = names[((yearBranch - b) % 12 + 12) % 12] }
        return out
    }
}

enum ZiweiEngine {
    /// 适配层：钟表时间＋经度（真太阳时）→ 农历字段 → 核心。晚子时作当日（时支子、日不进位，与八字 sect=2 同调）
    static func chart(clock: Date, gender: String, longitude: Double?) -> ZiweiChart {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let used = longitude.map { TrueSolarTime.corrected(clock: clock, longitude: $0, calendar: cal) } ?? clock
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: used)
        let solar = Solar.fromYmdHms(year: c.year!, month: c.month!, day: c.day!, hour: c.hour!, minute: c.minute!)
        let lunar = solar.lunar
        let rawMonth = lunar.month
        let leap = rawMonth < 0
        let month = leap ? (AppSettings.ziweiLeapNext ? min(abs(rawMonth) + 1, 12) : abs(rawMonth)) : rawMonth   // 闰月归属（设置页可调，默认归下月）
        let yearStem = ZiweiCore.TG[lunar.yearGanIndex % 10]
        let yearBranch = lunar.yearZhiIndex % 12
        let hourBranch = ((c.hour! + 1) / 2) % 12
        let text = "农历 \(lunar.year) 年\(leap ? "闰" : "")\(abs(rawMonth)) 月 \(lunar.day) 日 · \(ZiweiCore.DZ[hourBranch])时"
        if AppSettings.ziweiLateZiNext && c.hour! >= 23 {
            let nd = used.addingTimeInterval(86400)
            let nc = cal.dateComponents([.year, .month, .day], from: nd)
            let nl = Solar.fromYmdHms(year: nc.year!, month: nc.month!, day: nc.day!, hour: 0, minute: 30).lunar
            let nMonth = nl.month < 0 ? (AppSettings.ziweiLeapNext ? min(abs(nl.month) + 1, 12) : abs(nl.month)) : nl.month
            var ch = ZiweiCore.compute(yearStem: ZiweiCore.TG[nl.yearGanIndex % 10], yearBranch: nl.yearZhiIndex % 12,
                                       month: nMonth, day: nl.day, hourBranch: 0,
                                       isMale: gender == "M", lunarText: text + "（晚子时作次日）")
            ch.birthYear = c.year!
            return ch
        }
        var ch = ZiweiCore.compute(yearStem: yearStem, yearBranch: yearBranch, month: month,
                                 day: lunar.day, hourBranch: hourBranch,
                                 isMale: gender == "M", lunarText: text)
        ch.birthYear = c.year!
        return ch
    }

    // 划动缓存：与八字同理，按（出生时刻＋性别＋经度＋闰月/晚子时口径）缓存
    private static var chartCache: [String: ZiweiChart] = [:]
    static func cachedChart(clock: Date, gender: String, longitude: Double?) -> ZiweiChart {
        let key = "\(clock.timeIntervalSince1970)-\(gender)-\(longitude ?? 0)-\(AppSettings.ziweiLeapNext)-\(AppSettings.ziweiLateZiNext)"
        if let hit = chartCache[key] { return hit }
        let c = chart(clock: clock, gender: gender, longitude: longitude)
        if chartCache.count > 64 { chartCache.removeAll() }
        chartCache[key] = c
        return c
    }
}

// MARK: - 紫微页 v5（修复 4×4 方盘中央重复渲染 4 个小格 Bug，实现真正中央 2×2 合并天心宫＋三方四正飞线）
struct ZiweiHomeView: View {
    @State private var name = ""
    @State private var gender = "M"
    @State private var birth = Date()
    @State private var useLongitude = true
    @State private var longitudeText = "107.8"
    @State private var chart: ZiweiChart?
    @EnvironmentObject var peopleStore: PeopleStore
    @State private var chartSnapshot = ""
    @State private var savedTip = false
    @State private var inputCollapsed = false

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
                    ZiweiBoardView(chart: ch, name: name)
                    ZiweiYearView(chart: ch)
                    ZiweiReadingView(chart: ch)
                    NavigationLink { ZiweiPosterSheetView(chart: ch, name: name) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "photo.artframe")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Ky.gold)
                                .frame(width: 34, height: 34)
                                .background(Ky.gold.opacity(0.13))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("紫微命盘海报导出".scriptConverted).font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.ink)
                                Text("方盘缩印 · 命宫主星 · 生年四化".scriptConverted).font(.caption2).foregroundStyle(Ky.sub)
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
                NavigationLink { CaliberSettingsView() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                        Text("排盘口径设置（三合派安星 · 晚子时/闰月口径 · 14例金标准对拍）".scriptConverted).font(.caption)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2)
                    }.foregroundStyle(Ky.sub).padding(.horizontal, 4)
                }.buttonStyle(.plain)
            }
            .padding(16)
            .padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle("紫微斗数".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Ky.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var collapsedInputBar: some View {
        let s = BirthInputView.solarOf(birth)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name.isEmpty ? "当前紫微盘".scriptConverted : name)
                        .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                    KyBadge(text: gender == "M" ? "乾造（男）" : "坤造（女）", color: gender == "M" ? Ky.qingdai : Ky.cinnabar)
                    if let ch = chart {
                        KyBadge(text: ch.juName, color: Ky.gold)
                    }
                }
                Text("公历 \(String(s.year))-\(String(format: "%02d-%02d %02d:%02d", s.month, s.day, s.hour, s.minute))".scriptConverted + (useLongitude ? " · 东经 \(longitudeText)°".scriptConverted : " · 钟表时间".scriptConverted))
                    .font(KyV2.tabular(12)).foregroundStyle(Ky.sub)
            }
            Spacer()
            Button {
                withAnimation(KyMotion.toggle) { inputCollapsed = false }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.below.rectangle")
                    Text("改生辰".scriptConverted)
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
                KySectionTitle(title: "紫微安星录入", trailing: "天纪三合派")
                if chart != nil {
                    Button("收起".scriptConverted) {
                        withAnimation(KyMotion.toggle) { inputCollapsed = true }
                    }
                    .font(.caption).foregroundStyle(Ky.qingdai)
                }
            }
            if !peopleStore.people.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Label("速选：".scriptConverted, systemImage: "person.crop.rectangle.stack")
                            .font(.caption2).foregroundStyle(Ky.sub)
                        ForEach(peopleStore.people.prefix(8)) { p in
                            Button {
                                // 速选回填：姓名／性别／生辰／经度全部取自所点档案记录的本地值，
                                // 排盘与快照也用同一份本地值现算，不依赖刚写入的 @State 重读，保证姓名栏同步回填、快照与输入一致
                                name = p.name; gender = p.gender; birth = p.birthDate
                                useLongitude = p.useLongitude; longitudeText = String(format: "%.1f", p.longitude)
                                chart = ZiweiEngine.chart(clock: p.birthDate, gender: p.gender,
                                                          longitude: p.useLongitude ? p.longitude : nil)
                                chartSnapshot = "\(p.name)|\(p.gender)|\(p.birthDate.timeIntervalSince1970)|\(p.useLongitude)|\(String(format: "%.1f", p.longitude))"
                                savedTip = true; inputCollapsed = true
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
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "person.text.rectangle").foregroundStyle(Ky.sub)
                    TextField("命主姓名（可留空）", text: $name)
                        .font(.subheadline)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Ky.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 9))

                Picker("性别".scriptConverted, selection: $gender) {
                    Text("乾造（男）".scriptConverted).tag("M")
                    Text("坤造（女）".scriptConverted).tag("F")
                }
                .pickerStyle(.segmented)
                .frame(width: 156)
            }
            BirthInputView(clock: $birth, useLongitude: $useLongitude, longitudeText: $longitudeText)
            Button("立即排紫微盘".scriptConverted) {
                chart = ZiweiEngine.chart(clock: birth, gender: gender,
                                          longitude: useLongitude ? Double(longitudeText) : nil)
                chartSnapshot = inputSnapshot; savedTip = false
                withAnimation(KyMotion.toggle) { inputCollapsed = true }
            }.buttonStyle(KyPrimaryButton())
            if isStale {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                    Text("生辰输入已改动，请点「立即排紫微盘」刷新盘面。".scriptConverted)
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

struct ZiweiBoardView: View {
    let chart: ZiweiChart
    let name: String
    // UI 2.1 第6批：选中宫位跨启动保留（SceneStorage；-1＝未选）
    @SceneStorage("ziwei.selectedBranch") private var selectedStored: Int = -1
    private var selected: Int? {
        get { selectedStored >= 0 ? selectedStored : nil }
        set { selectedStored = newValue ?? -1 }
    }
    @State private var showPalaceSheet = false
    @State private var flyProgress: Double = 0
    // UI 2.1 第6批：紫微方盘独立放大（缩放变换，不进布局；按钮 1.0↔1.6，双指捏合 1.0–1.8）
    @State private var boardScale: CGFloat = 1.0
    @State private var pinchScale: CGFloat = 1.0
    @Environment(\.dynamicTypeSize) private var typeSize

    // 传统十二宫外框方位坐标（归一化到 4×4 网格的各宫中心点，供中宫三方四正连线指示）
    private static let cellPos: [Int: (Int, Int)] = [
        5: (0, 0), 6: (0, 1), 7: (0, 2), 8: (0, 3),
        4: (1, 0),                       9: (1, 3),
        3: (2, 0),                      10: (2, 3),
        2: (3, 0), 1: (3, 1), 0: (3, 2), 11: (3, 3)
    ]

    private var activeBranch: Int { selected ?? chart.mingGong }
    private var highlighted: Set<Int> {
        let s = activeBranch
        return [s, (s + 4) % 12, (s + 8) % 12, (s + 6) % 12]   // 本宫＋三合两宫＋对宫
    }

    // P1：全盘飞线——宫位真实中心（cellPos 行列＋实测格宽／行高换算，gap 5pt；中央 2×2 天心宫无宫位端点）
    private func palaceCenter(branch: Int, size: CGSize) -> CGPoint {
        let gap: CGFloat = 5
        let cellW = (size.width - gap * 3) / 4
        let cellH: CGFloat = 114
        guard let (row, col) = Self.cellPos[branch] else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        let x = CGFloat(col) * (cellW + gap) + cellW / 2
        let y = CGFloat(row) * (cellH + gap) + cellH / 2
        return CGPoint(x: x, y: y)
    }

    // P1：单层 Canvas 画本宫→对宫／三合宫飞线（雅金三合虚线＋朱砂对宫虚线；只画线，不叠多层；不拦截点按）
    private var flyLinesOverlay: some View {
        Canvas { ctx, size in
            let s = activeBranch
            let from = palaceCenter(branch: s, size: size)
            let targets: [(Int, Color, [CGFloat])] = [
                ((s + 6) % 12, Ky.cinnabar, [3, 3]),
                ((s + 4) % 12, Ky.gold, [4, 3]),
                ((s + 8) % 12, Ky.gold, [4, 3])
            ]
            for (idx, target) in targets.enumerated() {
                let to = palaceCenter(branch: target.0, size: size)
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                let lineOpacity = min(max(flyProgress - Double(idx), 0), 1) * 0.65
                ctx.stroke(path, with: .color(target.1.opacity(lineOpacity)), style: StrokeStyle(lineWidth: 1.1, dash: target.2))
            }
        }
        .allowsHitTesting(false)
    }

    // P1 续：飞线分段淡入——对宫先亮（0–0.25 秒），三合两宫随后（各 0.25 秒）；几何与虚线样式不动
    private func replayFlyLines() {
        flyProgress = 0
        withAnimation(KyMotion.flyline) {
            flyProgress = 3
        }
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize { textBoard } else { gridBoard }
        }
        .sheet(isPresented: $showPalaceSheet) {
            KyBottomSheet(title: palaceSheetTitle) { palaceSheetContent }
                .presentationBackgroundInteraction(.enabled)
        }
    }

    // 大字号合规形态：方盘自动切换为高可读列表盘
    private var textBoard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(chart.juName) · 命宫\(ZiweiCore.DZ[chart.mingGong]) · 身宫\(chart.palaces[chart.shenGong].name)".scriptConverted)
                .font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
            ForEach(chart.palaces.sorted { ($0.decadal.first ?? 0) < ($1.decadal.first ?? 0) }, id: \.branch) { p in
                let majorsText: String = p.majors.map { $0.star + ZiweiBrightness.of($0.star, branch: p.branch) + ($0.mutagen.map { "(化\($0))" } ?? "") }.joined(separator: "、")
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(p.name.scriptConverted).font(.callout).fontWeight(.bold).foregroundStyle(p.branch == chart.mingGong ? Ky.cinnabar : Ky.ink)
                        Text("\(p.stem)\(ZiweiCore.DZ[p.branch])").font(.caption).foregroundStyle(Ky.sub)
                        if p.isBody { KyBadge(text: "身宫", color: Ky.gold) }
                        Spacer()
                        Text("\(p.decadal.first ?? 0)–\(p.decadal.last ?? 0) 岁").font(.caption).foregroundStyle(Ky.sub)
                    }
                    if !p.majors.isEmpty {
                        Text(majorsText.scriptConverted)
                            .font(.callout).foregroundStyle(Ky.ink)
                    }
                    if !p.minors.isEmpty {
                        Text((p.minors.map { $0.star }.joined(separator: " ")).scriptConverted).font(.caption).foregroundStyle(Ky.sub)
                    }
                }
                .kyCard()
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(p.branch == activeBranch ? Ky.cinnabar.opacity(0.05) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(p.branch == activeBranch ? Ky.cinnabar : Color.clear, lineWidth: 2.0)
                )
                .onTapGesture {
                    KyV6.impact(.light)
                    selectedStored = p.branch
                    showPalaceSheet = true
                }
            }
        }
    }

    // 标准传统 4×4 紫微方盘：外围 12 宫 + 中央合并 2×2 天心宫（彻底修复旧版 4 个重复小圆圈问题）
    private var gridBoard: some View {
        let cellH: CGFloat = 114
        let gap: CGFloat = 5
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                KySectionTitle(title: "紫微十二宫方盘", trailing: "点任意宫位切换三方四正")
                if selected != nil {
                    Button("回命宫".scriptConverted) { selectedStored = -1 }
                        .font(.caption2).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                }
                Button(boardScale > 1.0 ? "复位".scriptConverted : "放大".scriptConverted) {
                    withAnimation(KyMotion.toggle) { boardScale = boardScale > 1.0 ? 1.0 : 1.6 }
                }
                .font(.caption2).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                .accessibilityLabel(boardScale > 1.0 ? "复位紫微方盘" : "放大紫微方盘")
            }

            VStack(spacing: gap) {
                // 顶行：巳(5) · 午(6) · 未(7) · 申(8)
                HStack(spacing: gap) {
                    cell(chart.palaces[5], height: cellH)
                    cell(chart.palaces[6], height: cellH)
                    cell(chart.palaces[7], height: cellH)
                    cell(chart.palaces[8], height: cellH)
                }

                // 中间两行：左列 辰(4)/卯(3) + 中央合并 2×2 天心宫 + 右列 酉(9)/戌(10)
                HStack(spacing: gap) {
                    VStack(spacing: gap) {
                        cell(chart.palaces[4], height: cellH)
                        cell(chart.palaces[3], height: cellH)
                    }
                    .frame(maxWidth: .infinity)

                    centerPalaceView(height: cellH * 2 + gap)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)

                    VStack(spacing: gap) {
                        cell(chart.palaces[9], height: cellH)
                        cell(chart.palaces[10], height: cellH)
                    }
                    .frame(maxWidth: .infinity)
                }

                // 底行：寅(2) · 丑(1) · 子(0) · 亥(11)
                HStack(spacing: gap) {
                    cell(chart.palaces[2], height: cellH)
                    cell(chart.palaces[1], height: cellH)
                    cell(chart.palaces[0], height: cellH)
                    cell(chart.palaces[11], height: cellH)
                }
            }
            .overlay { flyLinesOverlay }
            .onChange(of: activeBranch) { _, _ in replayFlyLines() }
            .onAppear { replayFlyLines() }
            .scaleEffect(boardScale * pinchScale)
            .gesture(
                MagnificationGesture()
                    .onChanged { pinchScale = $0 }
                    .onEnded { v in
                        boardScale = min(max(boardScale * v, 1.0), 1.8)
                        pinchScale = 1.0
                    }
            )

            // 选中宫位的三方四正与飞化详单
            selectedPalaceDetailBar
        }
        .kyCard()
    }

    // 中央 2×2 合并天心宫：只展示当前选中宫位的核心摘要（宫名＋主星＋一句话定型）；旧示意三角已移除，盘面飞线不受影响
    private func centerPalaceView(height: CGFloat) -> some View {
        let p = chart.palaces[activeBranch]
        let opp = chart.palaces[(p.branch + 6) % 12]
        let majorText: String = p.majors.isEmpty
            ? "无主星 · 借对宫\(opp.name)\(opp.majors.map { $0.star }.joined(separator: "、"))"
            : p.majors.map { $0.star + ZiweiBrightness.of($0.star, branch: p.branch) + ($0.mutagen.map { "化\($0)" } ?? "") }.joined(separator: "、")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(p.name.scriptConverted)
                    .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.cinnabar)
                Text("\(p.stem)\(ZiweiCore.DZ[p.branch]) · 大限 \(p.decadal.first ?? 0)–\(p.decadal.last ?? 0) 岁".scriptConverted)
                    .font(.system(size: 10)).foregroundStyle(Ky.sub)
                Spacer(minLength: 0)
                if p.isBody { KyBadge(text: "身宫", color: Ky.gold) }
            }
            Text("主星：\(majorText)".scriptConverted)
                .font(.system(size: 12)).fontWeight(.semibold).foregroundStyle(Ky.ink)
            Text(palaceDigest(p).scriptConverted)
                .font(.system(size: 11)).foregroundStyle(Ky.sub)
                .lineLimit(4)
            Spacer(minLength: 0)
            Text("点任意宫位切换 · 三方四正飞线见盘面".scriptConverted)
                .font(.system(size: 9)).foregroundStyle(Ky.sub.opacity(0.8))
        }
        .padding(10)
        .frame(minWidth: 168, maxWidth: .infinity)
        .frame(height: height)
        .background(Ky.elevated.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Ky.line, lineWidth: 0.8))
    }

    /// 中央摘要与抽屉共用的一句话定型：优先本宫星曜角色注，否则主星性情；无主星借对宫
    private func palaceDigest(_ p: ZiweiPalace) -> String {
        if p.majors.isEmpty {
            let opp = chart.palaces[(p.branch + 6) % 12]
            let stars = opp.majors.map { $0.star }.joined(separator: "、")
            return "无主星，借对宫\(opp.name)\(stars)参，定型随环境与际遇塑形更明显。"
        }
        for m in p.majors {
            if let note = ZiweiReading.palaceRoles[p.name]?[m.star] {
                return note + "。"
            }
            if let n = ZiweiReading.starNature[m.star] {
                return m.star + "：" + n + "。"
            }
        }
        return "主星" + p.majors.map { $0.star }.joined(separator: "、") + "坐守。"
    }

    private var selectedPalaceDetailBar: some View {
        let p = chart.palaces[activeBranch]
        let fly = ZiweiCore.flyFrom(chart, branch: activeBranch)
        let selfT = ZiweiCore.selfTransforms(chart)[activeBranch]
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                KyBadge(text: "\(p.name)（\(p.stem)\(ZiweiCore.DZ[p.branch])）", color: Ky.qingdai, filled: true)
                Text("大限 \(p.decadal.first ?? 0)–\(p.decadal.last ?? 0) 岁")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(Ky.ink)
                Spacer()
                Text("三方四正已标亮".scriptConverted).font(.caption2).foregroundStyle(Ky.sub)
            }
            Text(("宫干四化飞星：" + fly.map { "\($0.star)化\($0.kind)入\($0.target)" }.joined(separator: " · ")).scriptConverted)
                .font(.caption).foregroundStyle(Ky.ink)
            if let st = selfT {
                Text(("本宫自化：" + st.joined(separator: "、") + "（自化者，该宫事项由自身内因触发变动）").scriptConverted)
                    .font(.caption).fontWeight(.medium).foregroundStyle(Ky.cinnabar)
            }
        }
        .kySubCard()
    }

    // P1 续：宫位详情底部抽屉（复用奇门 P2 宫位弹层模式；内容随 activeBranch 实时切换）。
    // 抽屉以 .presentationBackgroundInteraction(.enabled) 弹出，打开时点盘面另一宫直接切过去，不用先关抽屉
    private var palaceSheetTitle: String {
        let p = chart.palaces[activeBranch]
        return "\(p.name) · \(p.stem)\(ZiweiCore.DZ[p.branch])"
    }

    private var palaceSheetContent: some View {
        let p = chart.palaces[activeBranch]
        let opp = chart.palaces[(activeBranch + 6) % 12]
        let tri1 = chart.palaces[(activeBranch + 4) % 12]
        let tri2 = chart.palaces[(activeBranch + 8) % 12]
        let fly = ZiweiCore.flyFrom(chart, branch: activeBranch)
        let selfT = ZiweiCore.selfTransforms(chart)[activeBranch]
        let majorText: String = p.majors.isEmpty
            ? "无主星 · 借对宫\(opp.name)\(opp.majors.map { $0.star }.joined(separator: "、"))"
            : p.majors.map { $0.star + ZiweiBrightness.of($0.star, branch: p.branch) + ($0.mutagen.map { "化\($0)" } ?? "") }.joined(separator: "、")
        let minorText: String = p.minors.map { $0.star + ($0.mutagen.map { "(化\($0))" } ?? "") }.joined(separator: " ")
        let flyText: String = fly.map { "\($0.star)化\($0.kind)入\($0.target)" }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 10) {
            Text(palaceDigest(p).scriptConverted)
                .font(.callout).foregroundStyle(Ky.ink)
            HStack(spacing: 6) {
                KyBadge(text: "大限 \(p.decadal.first ?? 0)–\(p.decadal.last ?? 0) 岁", color: Ky.qingdai)
                if p.branch == chart.mingGong { KyBadge(text: "命宫", color: Ky.cinnabar) }
                if p.isBody { KyBadge(text: "身宫", color: Ky.gold) }
            }
            Text("主星：\(majorText)".scriptConverted)
                .font(.callout).foregroundStyle(Ky.ink)
            if !p.minors.isEmpty {
                Text("辅星：\(minorText)".scriptConverted)
                    .font(.callout).foregroundStyle(Ky.sub)
            }
            Text("三方四正：对宫\(opp.name) · 三合\(tri1.name) / \(tri2.name)".scriptConverted)
                .font(.callout).foregroundStyle(Ky.ink)
            Text("宫干四化飞星：\(flyText)".scriptConverted)
                .font(.callout).foregroundStyle(Ky.ink)
            if let st = selfT {
                Text("本宫自化：\(st.joined(separator: "、"))".scriptConverted)
                    .font(.callout).fontWeight(.medium).foregroundStyle(Ky.cinnabar)
            }
            Text("完整解读见下方「天纪三合解读」；抽屉打开时点盘面其他宫位可直接切换。".scriptConverted)
                .font(.caption2).foregroundStyle(Ky.sub)
        }
    }

    private func cell(_ p: ZiweiPalace, height: CGFloat) -> some View {
        let isSel = activeBranch == p.branch
        let isHL = highlighted.contains(p.branch)
        let isMing = p.branch == chart.mingGong
        return Button {
            KyV6.impact(.light)
            withAnimation(KyMotion.toggle) {
                selectedStored = p.branch
            }
            showPalaceSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 2.5) {
                // 顶部：宫名＋命/身标记＋宫干支
                HStack(spacing: 2) {
                    Text(p.name.scriptConverted)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle((isMing || isSel) ? Ky.cinnabar : Ky.ink)
                    if p.isBody {
                        Text("身")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 3).padding(.vertical, 0.5)
                            .background(Ky.gold.opacity(0.2)).foregroundStyle(Ky.gold)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Spacer(minLength: 1)
                    Text("\(p.stem)\(ZiweiCore.DZ[p.branch])")
                        .font(.system(size: 9))
                        .foregroundStyle(Ky.sub)
                }

                // 主星＋亮度＋生年四化徽章
                if p.majors.isEmpty {
                    Text("无主星·借对宫".scriptConverted)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Ky.sub.opacity(0.75))
                        .padding(.vertical, 2)
                } else {
                    ForEach(p.majors.indices, id: \.self) { i in
                        let mj = p.majors[i]
                        let bright = ZiweiBrightness.of(mj.star, branch: p.branch)
                        HStack(spacing: 2) {
                            Text(mj.star.scriptConverted)
                                .font(.system(size: 12.5, weight: .bold, design: .serif))
                                .foregroundStyle(Ky.ink)
                            if !bright.isEmpty {
                                Text(bright.scriptConverted)
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(bright == "陷" || bright == "不" ? Ky.cinnabar.opacity(0.8) : Ky.sub)
                            }
                            if let m = mj.mutagen {
                                Text(m.scriptConverted)
                                    .font(.system(size: 8.5, weight: .bold))
                                    .padding(.horizontal, 3.5).padding(.vertical, 0.5)
                                    .background(m == "忌" ? Ky.cinnabar : Ky.qingdai)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                    }
                }

                // 辅星/杂曜
                if !p.minors.isEmpty {
                    Text((p.minors.map { $0.star + ($0.mutagen.map { "(化\($0))" } ?? "") }.joined(separator: " ")).scriptConverted)
                        .font(.system(size: 8.5))
                        .foregroundStyle(Ky.sub)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                // 底部：大限区间＋自化标记
                HStack(spacing: 2) {
                    Text("\(p.decadal.first ?? 0)–\(p.decadal.last ?? 0)")
                        .font(KyV2.tabular(9, weight: .medium))
                        .foregroundStyle(Ky.sub)
                    Spacer(minLength: 0)
                    if let selfT = ZiweiCore.selfTransforms(chart)[p.branch] {
                        Text(selfT.joined(separator: "").scriptConverted)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Ky.gold)
                            .lineLimit(1)
                    }
                }
            }
            .padding(5.5)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            .opacity(isHL ? 1.0 : 0.58)
            .background(isSel ? Ky.cinnabar.opacity(0.10) : (isHL ? Ky.gold.opacity(0.08) : Ky.card))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSel ? Ky.cinnabar : (isMing ? Ky.cinnabar.opacity(0.6) : (isHL ? Ky.gold.opacity(0.65) : Ky.line)),
                            lineWidth: isSel ? 2.0 : (isMing || isHL ? 1.0 : 0.6))
            )
        }
        .buttonStyle(.plain)
    }
}

// 紫微星曜亮度（《斗数全书》派 SB_QS 表，源自工作室天纪仓库 school-tables，星×十二宫全量）：

enum ZiweiBrightness {
    static let table: [String: [String]] = [
        "紫微": ["平", "庙", "旺", "旺", "得", "旺", "庙", "庙", "旺", "旺", "得", "旺"],
        "天机": ["庙", "陷", "得", "旺", "利", "平", "庙", "陷", "得", "旺", "利", "平"],
        "太阳": ["陷", "不", "旺", "庙", "旺", "旺", "旺", "得", "得", "平", "不", "陷"],
        "武曲": ["旺", "庙", "得", "利", "庙", "平", "旺", "庙", "得", "利", "庙", "平"],
        "天同": ["旺", "不", "利", "平", "平", "庙", "陷", "不", "旺", "平", "平", "庙"],
        "廉贞": ["平", "利", "庙", "平", "利", "陷", "平", "利", "庙", "平", "利", "陷"],
        "天府": ["庙", "庙", "庙", "得", "庙", "得", "旺", "庙", "得", "旺", "庙", "得"],
        "太阴": ["庙", "庙", "旺", "陷", "陷", "陷", "不", "不", "利", "旺", "旺", "庙"],
        "贪狼": ["旺", "庙", "平", "利", "庙", "陷", "旺", "庙", "平", "利", "庙", "陷"],
        "巨门": ["旺", "不", "庙", "庙", "陷", "旺", "旺", "不", "庙", "庙", "陷", "旺"],
        "天相": ["庙", "庙", "庙", "陷", "得", "得", "庙", "得", "庙", "陷", "得", "得"],
        "天梁": ["庙", "旺", "庙", "庙", "庙", "得", "庙", "旺", "陷", "得", "庙", "陷"],
        "七杀": ["旺", "庙", "庙", "旺", "庙", "平", "旺", "庙", "庙", "旺", "庙", "平"],
        "破军": ["庙", "旺", "得", "陷", "旺", "平", "庙", "旺", "得", "陷", "旺", "平"],
        "文昌": ["得", "庙", "陷", "利", "得", "庙", "陷", "利", "得", "庙", "陷", "利"],
        "文曲": ["得", "庙", "平", "旺", "得", "庙", "陷", "旺", "得", "庙", "陷", "旺"],
        "左辅": ["旺", "庙", "庙", "陷", "庙", "平", "旺", "庙", "平", "陷", "庙", "不"],
        "右弼": ["庙", "庙", "旺", "陷", "庙", "平", "旺", "庙", "不", "陷", "庙", "平"],
        "天魁": ["旺", "旺", "", "庙", "", "", "庙", "", "", "", "", "旺"],
        "天钺": ["", "", "旺", "", "", "旺", "", "旺", "庙", "庙", "", ""],
        "禄存": ["庙", "", "庙", "庙", "", "庙", "庙", "", "庙", "庙", "", "庙"],
        "天马": ["", "", "旺", "", "", "平", "", "", "旺", "", "", "平"],
        "火星": ["陷", "得", "庙", "利", "陷", "得", "庙", "利", "陷", "得", "庙", "利"],
        "铃星": ["陷", "得", "庙", "利", "陷", "得", "庙", "利", "陷", "得", "庙", "利"],
        "擎羊": ["陷", "庙", "", "陷", "庙", "", "陷", "庙", "", "陷", "庙", ""],
        "陀罗": ["", "庙", "陷", "", "庙", "陷", "", "庙", "陷", "", "庙", "陷"],
        "地空": ["平", "陷", "陷", "平", "陷", "庙", "庙", "平", "庙", "庙", "陷", "陷"],
        "地劫": ["陷", "陷", "平", "平", "陷", "不", "庙", "平", "庙", "平", "平", "陷"],
        "天福": ["平", "", "旺", "平", "", "旺", "平", "", "庙", "庙", "", "庙"],
        "天官": ["", "", "平", "旺", "旺", "旺", "庙", "庙", "", "平", "平", "旺"],
        "天刑": ["平", "陷", "庙", "庙", "平", "陷", "平", "陷", "陷", "庙", "庙", "陷"],
        "八座": ["陷", "庙", "庙", "平", "旺", "庙", "旺", "平", "庙", "庙", "平", "庙"],
        "三台": ["平", "庙", "平", "陷", "庙", "平", "旺", "庙", "旺", "庙", "旺", "平"],
        "天才": ["旺", "平", "庙", "旺", "陷", "庙", "旺", "平", "庙", "旺", "陷", "庙"],
        "天空": ["陷", "平", "陷", "平", "庙", "庙", "庙", "陷", "旺", "旺", "陷", "平"],
        "天姚": ["陷", "平", "旺", "庙", "陷", "平", "平", "旺", "陷", "庙", "庙", "陷"],
        "天哭": ["平", "庙", "平", "庙", "平", "不", "陷", "平", "庙", "不", "平", "平"],
        "天喜": ["旺", "陷", "庙", "旺", "陷", "庙", "庙", "陷", "旺", "庙", "陷", "旺"],
        "天虚": ["陷", "庙", "旺", "庙", "陷", "旺", "平", "陷", "庙", "旺", "陷", "平"],
        "天贵": ["庙", "旺", "平", "旺", "旺", "平", "庙", "旺", "陷", "庙", "旺", "平"],
        "天寿": ["平", "庙", "旺", "陷", "庙", "平", "平", "旺", "旺", "平", "庙", "旺"],
        "天德": ["庙", "庙", "平", "平", "庙", "旺", "旺", "庙", "平", "不", "庙", "平"],
        "孤辰": ["", "", "平", "", "", "陷", "", "", "平", "", "", "陷"],
        "红鸾": ["庙", "陷", "旺", "庙", "庙", "旺", "旺", "陷", "庙", "旺", "陷", "庙"],
        "恩光": ["平", "庙", "平", "庙", "庙", "平", "庙", "旺", "平", "陷", "庙", "不"],
        "破碎": ["", "陷", "", "", "", "陷", "", "", "", "平", "", ""],
        "华盖": ["", "陷", "", "", "庙", "", "", "陷", "", "", "平", ""],
        "解神": ["庙", "平", "庙", "庙", "庙", "旺", "庙", "平", "不", "旺", "庙", "平"],
        "寡宿": ["", "平", "", "", "陷", "", "", "不", "", "", "陷", ""],
        "凤阁": ["庙", "平", "庙", "旺", "陷", "庙", "平", "陷", "不", "庙", "庙", "旺"],
        "龙池": ["旺", "平", "平", "庙", "庙", "陷", "不", "庙", "平", "庙", "陷", "旺"],
        "大耗": ["旺", "平", "陷", "不", "平", "陷", "旺", "平", "陷", "不", "平", "陷"],
        "天使": ["陷", "陷", "平", "平", "陷", "平", "平", "平", "平", "陷", "陷", "旺"],
        "天伤": ["陷", "平", "平", "陷", "平", "平", "陷", "陷", "平", "平", "平", "旺"],
        "截空": ["陷", "不", "陷", "平", "陷", "庙", "庙", "庙", "庙", "庙", "", ""],
        "副旬": ["陷", "平", "陷", "平", "陷", "庙", "庙", "陷", "庙", "庙", "陷", "平"],
        "年解": ["庙", "得", "庙", "庙", "庙", "旺", "庙", "得", "利", "旺", "庙", "得"],
        "咸池": ["陷", "", "", "平", "", "", "陷", "", "", "平", "", ""],
    ]
    static func of(_ star: String, branch: Int) -> String {
        table[star]?[branch] ?? ""
    }
}
// MARK: - 紫微解读（读盘六步的 App 化：命宫定型→三方四正→四化议题→大限主题，全带依据链）
enum ZiweiReading {
    static let starNature: [String: String] = [
        "紫微": "帝星：主导与自尊强，要舞台也要班底，孤君无辅则辛苦",
        "天机": "智星：善谋好动、思虑细，动中求成，最忌犹豫自耗",
        "太阳": "光明星：主贵显与付出，利他中得名分，怕过耗",
        "武曲": "财星兼武星：刚毅务实，以技艺与执行力立身",
        "天同": "福星：温和知足、享福缘厚，多晚发而稳",
        "廉贞": "囚星兼桃花：执着深情，成败都系于专注的方向",
        "天府": "库星：稳重善守成，调度资源是本能，贵气内藏",
        "太阴": "富星：细腻积累、夜里发光型，情绪即财库的水位",
        "贪狼": "欲望桃花星：多才多欲，交际场里开创局面",
        "巨门": "口舌暗星：以言立业，是非中见真章，研究与表达见长",
        "天相": "印星：忠厚得人助，借平台成事，宜辅佐不宜独断",
        "天梁": "荫星：清高好管事，逢难有解，宜公职专业与长辈缘",
        "七杀": "将星：独断开创，变动里见功名，不喜被管束",
        "破军": "耗星先锋：破旧立新，大起大落中成事，先破后立"]
    /// 十二宫深度直断 · 宫位角色注（只写实际在宫之星的注；未列出的主星走 starNature）
    /// 赋文出处口径：以本机星曜性情库（天纪三合）为准，不编造典籍原文
    static let palaceRoles: [String: [String: String]] = [
        "财帛": ["武曲": "武曲坐财帛：以技艺与执行力生财，财来得稳也守得住",
                 "太阴": "太阴坐财帛：细腻积累型，宜不动产与长线",
                 "贪狼": "贪狼坐财帛：多才多欲，交际场里开财路，欲望须有刹车",
                 "禄存": "禄存同宫：财库有根",
                 "地空": "地空在财帛：财来财去，宜化整为零、留足备用金",
                 "地劫": "地劫在财帛：财来财去，宜化整为零、留足备用金"],
        "官禄": ["太阳": "太阳坐官禄：利贵显与付出，宜体制、教育、传播",
                 "天相": "天相坐官禄：借平台成事，宜辅佐、行政、专业服务",
                 "廉贞": "廉贞坐官禄：执着深情于一业，化禄则名利双收，化忌则防口舌是非",
                 "七杀": "七杀坐官禄：将星开创，宜创业、开拓、变动中取功名",
                 "紫微": "紫微坐官禄：宜带团队、有舞台的位子，孤君无辅则辛苦"],
        "夫妻": ["天机": "天机坐夫妻：伴侣聪明善谋，相处宜多沟通、少猜心",
                 "七杀": "七杀坐夫妻：伴侣性烈直接，宜先立规则再谈感情",
                 "巨门": "巨门坐夫妻：口舌暗星，以言立业也以言伤人，相处宜把话说透、忌冷战",
                 "天同": "天同坐夫妻：伴侣温和知足，宜慢热长情"],
        "疾厄": ["擎羊": "擎羊在疾厄：金气偏旺，肺与大肠为传统弱项，宜润肺、忌燥烈",
                 "陀罗": "陀罗在疾厄：缠绵之气，旧疾宜慢调",
                 "火星": "火星在疾厄：火气偏旺，心与小肠为传统弱项，宜降火、忌熬夜",
                 "铃星": "铃星在疾厄：火气暗藏，宜静养、忌骤动",
                 "天同": "天同在疾厄：逢难有解，宜顺势调养",
                 "天梁": "天梁在疾厄：逢难有解，宜顺势调养"],
        "田宅": ["天府": "天府坐田宅：库星守成，不动产缘分厚，宜守祖业、宜置业",
                 "太阴": "太阴坐田宅：宜近水、宜稳，置业宜实",
                 "禄存": "禄存同宫：祖荫积蓄有根",
                 "地空": "地空在田宅：置业宜实、忌投机，祖产宜守不宜散",
                 "地劫": "地劫在田宅：置业宜实、忌投机，祖产宜守不宜散"],
        "福德": ["天同": "天同坐福德：温和知足，精神底子厚",
                 "天梁": "天梁坐福德：清高好管事，逢难有解",
                 "太阴": "太阴坐福德：心思细腻，情绪即福德的水位"],
        "迁移": ["天马": "天马在迁移：外出多动，异地有机遇",
                 "七杀": "七杀在迁移：宜闯荡，变动里见功名",
                 "破军": "破军在迁移：宜闯荡，先破后立"],
    ]
    /// 命宫格局判定（杀破狼／机月同梁／紫府朝垣／日月并明；只判三方实际见到的组合）
    private static func gejuNote(chart ch: ZiweiChart) -> String {
        func palace(_ name: String) -> ZiweiPalace { ch.palaces.first { $0.name == name }! }
        let ming = ch.palaces[ch.mingGong]
        let cai = palace("财帛"), guan = palace("官禄"), qian = palace("迁移")
        let sanfang = ming.majors.map { $0.star } + cai.majors.map { $0.star } + guan.majors.map { $0.star }
        var notes: [String] = []
        if sanfang.contains("七杀") && sanfang.contains("破军") && sanfang.contains("贪狼") { notes.append("杀破狼格：三方见七杀、破军、贪狼，开创变动型，变动里见功名") }
        let jiYue = ["天机", "太阴", "天同", "天梁"]
        if sanfang.filter({ jiYue.contains($0) }).count >= 3 { notes.append("机月同梁格：三方见天机、太阴、天同、天梁三者以上，宜公职、专业、文化教职") }
        if ming.majors.contains(where: { $0.star == "紫微" }) && (ming.majors.contains(where: { $0.star == "天府" }) || qian.majors.contains(where: { $0.star == "天府" })) { notes.append("紫府朝垣：命宫见紫微、天府对照，帝库相会，宜带团队、有舞台的位子") }
        if sanfang.contains("太阳") && sanfang.contains("太阴") { notes.append("日月并明：三方见太阳、太阴，光暗互补，宜名利双线") }
        return notes.isEmpty ? "" : "格局：" + notes.joined(separator: "；")
    }
    /// 单宫深度直断卡（星曜事实＋天纪赋文出处＋白话深度直断）
    private static func palaceCard(chart ch: ZiweiChart, name: String, title: String, theme: String) -> (title: String, conclusion: String, facts: String, source: String) {
        let p = ch.palaces.first { $0.name == name }!
        func starLine(_ pp: ZiweiPalace) -> String {
            pp.majors.isEmpty ? "无主星（借对宫）" : pp.majors.map { $0.star }.joined(separator: "、")
        }
        let opp = ch.palaces[(p.branch + 6) % 12]
        let brightness = p.majors.map { ZiweiBrightness.of($0.star, branch: p.branch) }.filter { !$0.isEmpty }.joined(separator: "、")
        let hua = (p.majors + p.minors).compactMap { m in m.mutagen.map { "\(m.star)化\($0)" } }.joined(separator: "、")
        let sha = p.minors.filter { ["擎羊", "陀罗", "火星", "铃星", "地空", "地劫"].contains($0.star) }.map { $0.star }
        let ji = p.minors.filter { ["左辅", "右弼", "文昌", "文曲", "禄存", "天马"].contains($0.star) }.map { $0.star }
        var facts = "\(name)\(p.stem)\(ZiweiCore.DZ[p.branch])，主星 \(starLine(p))"
        if !brightness.isEmpty { facts += "（\(brightness)）" }
        if !ji.isEmpty { facts += "；吉星 \(ji.joined(separator: "、"))" }
        if !sha.isEmpty { facts += "；煞星 \(sha.joined(separator: "、"))" }
        if !hua.isEmpty { facts += "；\(hua)" }
        if p.majors.isEmpty { facts += "；无主星，借对宫 \(opp.name)\(starLine(opp))" }
        var parts: [String] = []
        if p.majors.isEmpty {
            parts.append("\(name)无主星，定型借对宫\(opp.name)参：\(starLine(opp))的性情会投射到本宫，\(theme)随环境与际遇塑形更明显")
        } else {
            for m in p.majors {
                if let note = palaceRoles[name]?[m.star] { parts.append(note) }
                else if let n = starNature[m.star] { parts.append("\(m.star)：\(n)") }
            }
        }
        for s in p.minors {
            if let note = palaceRoles[name]?[s.star] { parts.append(note) }
        }
        let shaGeneric = sha.filter { palaceRoles[name]?[$0] == nil }
        if !shaGeneric.isEmpty { parts.append("煞星 \(shaGeneric.joined(separator: "、"))在宫，\(theme)多波折，宜先立规矩再求进") }
        if !hua.isEmpty { parts.append("四化 \(hua)，为一生反复出题之处") }
        if name == "疾厄" { parts.append("以上为传统象义，不落病名；身体不适以临床为准") }
        let conclusion = parts.joined(separator: "。") + "。"
        let source = "天纪三合 · \(name)星曜性情（\(p.majors.map { $0.star }.joined(separator: "、"))\(p.majors.isEmpty ? "借对宫" : "")）"
        return (title, conclusion, facts, source)
    }
    static func cards(chart ch: ZiweiChart) -> [(title: String, conclusion: String, facts: String, source: String)] {
        var out: [(String, String, String, String)] = []
        let ming = ch.palaces[ch.mingGong]
        func starLine(_ p: ZiweiPalace) -> String {
            p.majors.isEmpty ? "无主星（借对宫）" : p.majors.map { $0.star }.joined(separator: "、")
        }
        let mingStars = ming.majors.map { $0.star }
        let mingText = mingStars.isEmpty ? "命宫无主星：定型借对宫迁移宫主星参，性格随环境塑形更明显。"
            : mingStars.map { "\($0)：\(starNature[$0] ?? "")" }.joined(separator: "；")
        let mingBase = mingText.hasSuffix("。") ? String(mingText.dropLast()) : mingText
        let geju = gejuNote(chart: ch)
        out.append(("命宫定型",
                    mingBase + "。" + (geju.isEmpty ? "" : geju + "。"),
                    "命宫在\(ming.stem)\(ZiweiCore.DZ[ming.branch])，主星 \(starLine(ming))",
                    "天纪三合 · 命宫星曜性情（\(mingStars.isEmpty ? "借对宫" : mingStars.joined(separator: "、"))）"))
        // 十二宫深度直断：财帛／官禄／夫妻／疾厄／田宅／福德／迁移
        out.append(palaceCard(chart: ch, name: "财帛", title: "财帛赚钱", theme: "赚钱模式与财库厚度"))
        out.append(palaceCard(chart: ch, name: "官禄", title: "官禄事业", theme: "事业赛道与晋升天花板"))
        out.append(palaceCard(chart: ch, name: "夫妻", title: "夫妻婚恋", theme: "配偶象义与婚恋相处"))
        out.append(palaceCard(chart: ch, name: "疾厄", title: "疾厄体质", theme: "脏腑体质弱项"))
        out.append(palaceCard(chart: ch, name: "田宅", title: "田宅置业", theme: "不动产缘分与祖荫积蓄"))
        out.append(palaceCard(chart: ch, name: "福德", title: "福德心境", theme: "内心精神世界与压力化解"))
        out.append(palaceCard(chart: ch, name: "迁移", title: "迁移外出", theme: "外出贵人与异地发展"))
        // 三方四正：财帛/官禄/迁移
        func palace(_ name: String) -> ZiweiPalace { ch.palaces.first { $0.name == name }! }
        let cai = palace("财帛"); let guan = palace("官禄"); let qian = palace("迁移")
        out.append(("三方四正",
                    "财帛坐\(starLine(cai))定赚钱方式，官禄坐\(starLine(guan))定事业形态，迁移坐\(starLine(qian))定外出方为——四宫合看才是完整的用武之地。",
                    "财帛\(cai.stem)\(ZiweiCore.DZ[cai.branch])、官禄\(guan.stem)\(ZiweiCore.DZ[guan.branch])、迁移\(qian.stem)\(ZiweiCore.DZ[qian.branch])",
                    "天纪三合 · 三方四正（财帛／官禄／迁移）"))
        // 四化议题
        var huaLines: [String] = []
        for p in ch.palaces {
            for m in p.majors where m.mutagen != nil {
                let role = ["禄": "资源与享受所在", "权": "掌控与发力所在", "科": "名声与贵人所在", "忌": "债与执念、反复出题所在"][m.mutagen!]!
                huaLines.append("\(m.star)化\(m.mutagen!)入\(p.name)：\(role)")
            }
            for s in p.minors where s.mutagen != nil {
                let role = ["禄": "资源与享受所在", "权": "掌控与发力所在", "科": "名声与贵人所在", "忌": "债与执念、反复出题所在"][s.mutagen!]!
                huaLines.append("\(s.star)化\(s.mutagen!)入\(p.name)：\(role)")
            }
        }
        out.append(("生年四化", huaLines.joined(separator: "；") + "。四化落哪宫，哪宫就是一生反复出题之处。",
                    "生年干四化（天纪口径，不搞多层飞星）",
                    "天纪三合 · 生年四化（天干四化口径）"))
        // 大限（按虚岁粗定位：以当前年份-出生年+1 落入哪步大限；此处以宫位大限表展示全程）
        let daxianText = ch.palaces.sorted { ($0.decadal.first ?? 0) < ($1.decadal.first ?? 0) }
            .map { "\($0.decadal.first ?? 0)–\($0.decadal.last ?? 0) 岁走\($0.name)（\(starLine($0))）" }
            .joined(separator: "；")
        out.append(("大限推程", daxianText + "。每限十年以该宫及其三方四正断主题。",
                    "\(ch.juName)，\(ch.juNumber) 岁起限",
                    "天纪三合 · 大限推程（\(ch.juName)，\(ch.juNumber) 岁起限）"))
        return out
    }
}

// MARK: - 紫微展开集编解码（纯函数，可单元测试）
/// 紫微 11 卡展开集编码：Set<String> -> 逗号串（排序后拼接，空集 -> ""）
func encodeExpandedCards(_ s: Set<String>) -> String {
    s.sorted().joined(separator: ",")
}

/// 紫微 11 卡展开集解码：逗号串 -> Set<String>（空串 -> 空集）
func decodeExpandedCards(_ s: String) -> Set<String> {
    Set(s.split(separator: ",").map { String($0) })
}

struct ZiweiReadingView: View {
    let chart: ZiweiChart
    // 展开集跨启动保留：SceneStorage 存逗号串（读走计算属性，写走存储变量；11 卡标题均不含逗号）
    @SceneStorage("ziwei.expandedCards") private var expandedCardsStored: String = "命宫定型"
    private var expandedCards: Set<String> { decodeExpandedCards(expandedCardsStored) }  // P1：11 卡抽屉化，默认只展开首卡「命宫定型」
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            KySectionTitle(title: "天纪三合解读", trailing: "命身 · 十二宫 · 三方 · 四化 · 大限")
            ForEach(ZiweiReading.cards(chart: chart), id: \.title) { c in
                DisclosureGroup(isExpanded: Binding(
                    get: { expandedCards.contains(c.title) },
                    set: {
                        var s = expandedCards
                        if $0 { s.insert(c.title) } else { s.remove(c.title) }
                        expandedCardsStored = encodeExpandedCards(s)
                    }
                )) {
                    EvidenceChainView(conclusion: c.conclusion, links: [("盘面", c.facts), ("天纪出处", c.source)])
                        .padding(.top, 6)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(c.title.scriptConverted)
                                .font(.system(.subheadline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                            Spacer()
                            KyBadge(text: "天纪口径", color: Ky.qingdai)
                        }
                        if !expandedCards.contains(c.title) {
                            Text(c.conclusion.scriptConverted)
                                .font(.callout).foregroundStyle(Ky.ink)
                                .lineLimit(2)
                        }
                    }
                }
                .kyCard()
            }
        }
    }
}

// MARK: - 紫微流年层（流年命宫/流年宫名/流年四化/小限）
struct ZiweiYearView: View {
    let chart: ZiweiChart
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var lmonth = abs(Solar.fromYmdHms(year: Calendar.current.component(.year, from: Date()), month: Calendar.current.component(.month, from: Date()), day: 15, hour: 12, minute: 0).lunar.month)
    var body: some View {
        let solar = Solar.fromYmdHms(year: year, month: 7, day: 1, hour: 12, minute: 0)
        let yStem = ZiweiCore.TG[solar.lunar.yearGanIndex % 10]
        let yBranch = solar.lunar.yearZhiIndex % 12
        let names = ZiweiCore.yearNames(yearBranch: yBranch)
        let age = year - chart.birthYear + 1
        let xiao = ZiweiCore.xiaoxian(birthYearBranch: chart.birthYearBranch, age: max(age, 1), isMale: chart.isMale)
        let muts = ZiweiCore.mutagens(ofStem: String(yStem))
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                KySectionTitle(title: "流年与小限推演", trailing: "\(year) \(yStem)\(ZiweiCore.DZ[yBranch])年")
                Button { year = max(1950, year - 1) } label: {
                    Image(systemName: "chevron.left").frame(width: 26, height: 26).background(Ky.elevated).clipShape(Circle())
                }.accessibilityLabel("上一年")
                Button { year = min(2100, year + 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 26, height: 26).background(Ky.elevated).clipShape(Circle())
                }.accessibilityLabel("下一年")
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("流年命宫".scriptConverted).font(.caption2).foregroundStyle(Ky.sub)
                    Text(chart.palaces[yBranch].name.scriptConverted).font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.qingdai)
                }
                .frame(maxWidth: .infinity, alignment: .leading).kySubCard()

                VStack(alignment: .leading, spacing: 2) {
                    Text("小限（虚岁 \(age)）".scriptConverted).font(.caption2).foregroundStyle(Ky.sub)
                    Text(chart.palaces[xiao].name.scriptConverted).font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.gold)
                }
                .frame(maxWidth: .infinity, alignment: .leading).kySubCard()

                VStack(alignment: .leading, spacing: 2) {
                    Text("流年四化".scriptConverted).font(.caption2).foregroundStyle(Ky.sub)
                    Text((muts.map { "\($0.star)\($0.kind)" }.joined(separator: " ")).scriptConverted)
                        .font(.caption).fontWeight(.bold).foregroundStyle(Ky.ink).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading).kySubCard()
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(0..<12, id: \.self) { b in
                    HStack(spacing: 4) {
                        Text((names[b] ?? "").scriptConverted).font(.caption2).fontWeight(names[b] == "命宫" ? .bold : .regular)
                            .foregroundStyle(names[b] == "命宫" ? Ky.cinnabar : Ky.ink)
                        Spacer(minLength: 0)
                        Text(chart.palaces[b].name.scriptConverted).font(.system(size: 10)).foregroundStyle(Ky.sub)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 7).padding(.vertical, 5)
                    .background(b == yBranch ? Ky.qingdai.opacity(0.14) : Ky.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Divider()
            let mp = ZiweiCore.monthPalace(chart, year: year, lunarMonth: lmonth)
            let mStemIdx = (solar.lunar.yearGanIndex % 5) * 2 + 2 + (lmonth - 1)
            let mMuts = ZiweiCore.mutagens(ofStem: String(ZiweiCore.TG[mStemIdx % 10]))
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("斗君流月命宫（农历 \(lmonth) 月）".scriptConverted).font(.caption2).foregroundStyle(Ky.sub)
                    Text(chart.palaces[mp].name.scriptConverted).font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("流月四化".scriptConverted).font(.caption2).foregroundStyle(Ky.sub)
                    Text((mMuts.map { "\($0.star)\($0.kind)" }.joined(separator: " ")).scriptConverted).font(.caption).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                }
                Stepper("", value: $lmonth, in: 1...12).labelsHidden()
            }
            Text("读法：流年命宫定当年舞台，流年四化定引动方向，小限看自身感受；与大限宫位叠看。".scriptConverted)
                .font(.caption2).foregroundStyle(Ky.sub)
        }.kyCard()
    }
}
