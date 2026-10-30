// 八字模块（综合 App 第一块新拼图，并入堪舆仓库 2026-10-30）
// 引擎：lunar-swift（6tail，与服务端 lunar-python 同谱系，MIT）＋自研真太阳时层。
// 口径钉死（八字线定版）：晚子时 sect=2 显式设置；月干/时干五虎遁/五鼠遁复算互校；
// 胎元/胎息/命宫/身宫随盘输出（对标问真三层盘面，金标准盘 12 例对拍守口径）。
// 细盘层（藏干/十神/长生/纳音/旬空）为查表自算移植，2026-10-30 已与 paipan.py 库输出
// 在 12 例金标准盘上逐项对拍全过（原型验证记录见 sanhe-app），不猜 lunar-swift 未核对的接口。
import SwiftUI
import LunarSwift

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
    var pillars: [String] { [yearPillar, monthPillar, dayPillar, timePillar] }
    var qiyunYear: Int { Int(qiyunDate.prefix(4)) ?? 0 }
    func dayunStartYear(_ i: Int) -> Int { qiyunYear + i * 10 }
    static func yearGanZhi(_ year: Int) -> String {
        let tg = Array("甲乙丙丁戊己庚辛壬癸"); let dz = Array("子丑寅卯辰巳午未申酉戌亥")
        return String(tg[(year - 4) % 10]) + String(dz[(year - 4) % 12])
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
        ec.sect = 2  // 晚子时：日柱算当天，钉死不许漂移
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
        return BaziChart(yearPillar: yg, monthPillar: mg, dayPillar: dg, timePillar: tg,
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
                         wuxingPercents: BaziTables.wuxingPercents(pillars: pillars))
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                inputCard
                if let ch = chart { BaziResultView(chart: ch, name: name) }
                Text("口径：真太阳时＋晚子时 sect=2；细盘查表与服务端已验证引擎逐项对拍（金标准盘 12 例）。断语与报告在 P2 接入。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("八字排盘")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var inputCard: some View {
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
            Button("排盘") {
                chart = BaziEngine.paipan(clock: birth, gender: gender,
                                          longitude: useLongitude ? Double(longitudeText) : nil)
            }.buttonStyle(KyPrimaryButton())
            Text("家里人建议到「人物档案」建档，建一次，八字、手相、案件都直接调人。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// 盘面结果（录入页与人物详情共用同一块，保证两处长得一模一样）
struct BaziResultView: View {
    let chart: BaziChart
    let name: String
    @State private var proMode = false
    @State private var timeLevel = 0        // 0 大运 1 流年（流月/流日/流时 P2）
    @State private var selectedDayun = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            plateCard
            wuxingCard
            timeCard
            infoCard
            interpretLink
        }
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
            plateGrid(chart)
        }
        .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var wuxingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("五行力量").font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
            WuxingBarsView(percents: chart.wuxingPercents)
            Text("计法：天干各 1，藏干本气 1 / 中气 0.5 / 余气 0.3，归一化。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("岁运").font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
                Spacer()
                Text("起运 \(chart.qiyunDirection) · \(chart.qiyunDate)").font(.caption).foregroundStyle(Ky.sub)
            }
            TimeCapsuleBar(levels: ["大运", "流年", "流月", "流日", "流时"],
                           enabled: [true, true, false, false, false], selection: $timeLevel)
            if timeLevel == 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chart.dayunGanZhi.indices, id: \.self) { i in
                            Button { selectedDayun = i; timeLevel = 1 } label: {
                                VStack(spacing: 2) {
                                    Text(chart.dayunGanZhi[i]).font(.system(.callout, design: .serif)).fontWeight(.semibold)
                                    Text("\(chart.dayunStartYear(i)) 起").font(.caption2).foregroundStyle(Ky.sub)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(i == selectedDayun ? Ky.gold.opacity(0.18) : Ky.bg)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).foregroundStyle(Ky.ink)
                        }
                    }
                }
                Text("点任一步大运，进到它的流年。").font(.caption2).foregroundStyle(Ky.sub)
            } else {
                let start = chart.dayunStartYear(selectedDayun)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                    ForEach(0..<10, id: \.self) { k in
                        VStack(spacing: 2) {
                            Text(BaziChart.yearGanZhi(start + k)).font(.system(.callout, design: .serif)).fontWeight(.semibold)
                            Text(String(start + k)).font(.caption2).foregroundStyle(Ky.sub)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Ky.bg).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                Text("\(chart.dayunGanZhi[selectedDayun]) 运（\(start) 起）十年流年；流月/流日/流时在 P2 下钻。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }
        }
        .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("基本信息").font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
            Text("胎元 \(chart.taiYuan) · 胎息 \(chart.taiXi) · 命宫 \(chart.mingGong) · 身宫 \(chart.shenGong)")
                .font(.caption).foregroundStyle(Ky.ink)
        }
        .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var interpretLink: some View {
        NavigationLink { InterpretView(chart: chart, name: name) } label: {
            HStack(spacing: 10) {
                Image(systemName: "text.book.closed").foregroundStyle(Ky.cinnabar)
                VStack(alignment: .leading, spacing: 2) {
                    Text("解盘 · 初断").font(.system(.subheadline, design: .serif)).fontWeight(.semibold)
                    Text("命局风景 / 格局候选 / 喜忌 / 十神 / 岁运，逐条附依据链").font(.caption2).foregroundStyle(Ky.sub)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ky.sub)
            }
            .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
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
