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
    var minors: [String] = []
    var decadal: [Int] = []         // [起岁, 止岁]
    var isBody: Bool = false
}

struct ZiweiChart {
    var mingGong: Int; var shenGong: Int
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
        var minorAt: [Int: [String]] = [:]
        func putMinor(_ star: String, _ at: Int) { minorAt[at, default: []].append(star) }
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
        return ZiweiChart(mingGong: ming, shenGong: shen, juName: juName, juNumber: ju,
                          palaces: palaces, lunarText: lunarText)
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
        let month = leap ? min(abs(rawMonth) + 1, 12) : rawMonth   // 闰月整月归下月（天纪口径）
        let yearStem = ZiweiCore.TG[lunar.yearGanIndex % 10]
        let yearBranch = lunar.yearZhiIndex % 12
        let hourBranch = ((c.hour! + 1) / 2) % 12
        let text = "农历 \(lunar.year) 年\(leap ? "闰" : "")\(abs(rawMonth)) 月 \(lunar.day) 日 · \(ZiweiCore.DZ[hourBranch])时"
        return ZiweiCore.compute(yearStem: yearStem, yearBranch: yearBranch, month: month,
                                 day: lunar.day, hourBranch: hourBranch,
                                 isMale: gender == "M", lunarText: text)
    }
}

// MARK: - 紫微页（录入＋方盘；方盘保形 4×4，点宫看三方四正）
struct ZiweiHomeView: View {
    @State private var name = ""
    @State private var gender = "M"
    @State private var birth = Date()
    @State private var useLongitude = true
    @State private var longitudeText = "107.8"
    @State private var chart: ZiweiChart?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("姓名（可空）", text: $name)
                    Picker("性别", selection: $gender) { Text("男").tag("M"); Text("女").tag("F") }
                        .pickerStyle(.segmented)
                    DatePicker("出生钟表时间", selection: $birth, displayedComponents: [.date, .hourAndMinute])
                    Toggle("真太阳时校正（按经度）", isOn: $useLongitude)
                    if useLongitude {
                        HStack { Text("出生地经度"); Spacer()
                            TextField("107.8", text: $longitudeText)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90) }
                    }
                    Button("排紫微盘") {
                        chart = ZiweiEngine.chart(clock: birth, gender: gender,
                                                  longitude: useLongitude ? Double(longitudeText) : nil)
                    }.buttonStyle(KyPrimaryButton())
                }
                .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
                if let ch = chart {
                    ZiweiBoardView(chart: ch, name: name)
                }
                Text("口径：三合派安星（晚子时作当日、闰月整月归下月），已与主流参照引擎 14 例逐项对拍；庙旺亮度按《全书》表校准中，暂不标。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("紫微斗数")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ZiweiBoardView: View {
    let chart: ZiweiChart
    let name: String
    @State private var selected: Int? = nil
    // 方盘格位：branch → (row, col)
    private static let cellPos: [Int: (Int, Int)] = [
        5: (0, 0), 6: (0, 1), 7: (0, 2), 8: (0, 3),
        4: (1, 0), 9: (1, 3),
        3: (2, 0), 10: (2, 3),
        2: (3, 0), 1: (3, 1), 0: (3, 2), 11: (3, 3)]
    private var highlighted: Set<Int> {
        guard let s = selected else { return [] }
        return [s, (s + 4) % 12, (s + 8) % 12, (s + 6) % 12]   // 本宫＋三合＋对宫
    }
    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                ForEach(0..<16, id: \.self) { idx in
                    let row = idx / 4; let col = idx % 4
                    if let branch = Self.cellPos.first(where: { $0.value == (row, col) })?.key {
                        cell(chart.palaces[branch])
                    } else {
                        centerCell
                    }
                }
            }
            if let s = selected {
                let p = chart.palaces[s]
                Text("已选\(p.name)（\(p.stem)\(ZiweiCore.DZ[p.branch])）：高亮为其三方四正——本宫、三合两宫与对宫，读盘时四宫合看。")
                    .font(.caption).foregroundStyle(Ky.sub)
            } else {
                Text("点任一宫，高亮它的三方四正。").font(.caption).foregroundStyle(Ky.sub)
            }
        }
    }
    private var centerCell: some View {
        VStack(spacing: 3) {
            Text(name.isEmpty ? "紫微盘" : name).font(.system(.subheadline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
            Text(chart.juName).font(.caption).foregroundStyle(Ky.gold)
            Text(chart.lunarText).font(.system(size: 9)).foregroundStyle(Ky.sub)
                .multilineTextAlignment(.center).lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 104)
        .background(Ky.bg).clipShape(RoundedRectangle(cornerRadius: 8))
    }
    private func cell(_ p: ZiweiPalace) -> some View {
        let isSel = selected == p.branch
        let isHL = highlighted.contains(p.branch)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(p.name).font(.system(size: 10)).fontWeight(.semibold)
                    .foregroundStyle(p.branch == chart.mingGong ? Ky.cinnabar : Ky.ink)
                if p.isBody { Text("身").font(.system(size: 8)).foregroundStyle(Ky.gold) }
                Spacer()
                Text("\(p.stem)\(ZiweiCore.DZ[p.branch])").font(.system(size: 8)).foregroundStyle(Ky.sub)
            }
            ForEach(p.majors.indices, id: \.self) { i in
                HStack(spacing: 2) {
                    Text(p.majors[i].star).font(.system(size: 12, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                    if let m = p.majors[i].mutagen {
                        Text(m).font(.system(size: 8)).fontWeight(.bold)
                            .foregroundStyle(m == "忌" ? Ky.cinnabar : Ky.gold)
                    }
                }
            }
            if !p.minors.isEmpty {
                Text(p.minors.joined(separator: " ")).font(.system(size: 8)).foregroundStyle(Ky.sub).lineLimit(2)
            }
            Spacer()
            Text("\(p.decadal.first ?? 0)–\(p.decadal.last ?? 0)").font(.system(size: 8)).foregroundStyle(Ky.sub)
        }
        .padding(5)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(isSel ? Ky.gold.opacity(0.22) : isHL ? Ky.gold.opacity(0.10) : Ky.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { selected = isSel ? nil : p.branch }
    }
}
