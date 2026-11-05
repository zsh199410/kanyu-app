// 黄历完整版（2026-11-05 build-72 闪退根治与性能加速版）：
// 根治闪退：旧版 AlmanacCalendarCard 中 @State showYear=0 / showMonth=0 在首次 body 求值时（.onAppear 触发前）
// 直接传入 Solar.fromYmdHms(year: 0, month: 0, ...) 引发 LunarSwift 月份越界致命闪退；
// 现改为在 init 中直接按初始日期完成年月日初始化，并在所有历算入口加安全边界钳制与内存级月历缓存。
import SwiftUI
import LunarSwift

@MainActor
enum AlmanacLunarCache {
    struct DayInfo {
        let dayInGanZhi: String
        let yearInGanZhi: String
        let monthInGanZhi: String
        let yearShengXiao: String
        let monthInChinese: String
        let dayInChinese: String
        let weekInChinese: String
        let zhiXing: String
        let dayNaYin: String
        let xiuText: String
        let tianShenText: String
        let nineStarText: String
        let chongShaText: String
        let taiShen: String
        let festivals: String
        let otherFestivals: String
        let jieQiText: String
        let dayYi: [String]
        let dayJi: [String]
        let jiShen: String
        let xiongSha: String
        let xiPos: String
        let caiPos: String
        let fuPos: String
        let yangGuiPos: String
        let yinGuiPos: String
        let pengZu: String
        let times: [(ganZhi: String, luck: String, yi: String, ji: String)]
        let year: Int
    }

    private static var monthLabelsCache: [String: [String]] = [:]
    private static var dayInfoCache: [String: DayInfo] = [:]

    static func clampedYMD(from date: Date) -> (Int, Int, Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        let y = min(max(c.year ?? 2026, 1901), 2099)
        let m = min(max(c.month ?? 1, 1), 12)
        let d = min(max(c.day ?? 1, 1), 31)
        return (y, m, d)
    }

    static func monthLunarLabels(year: Int, month: Int, count: Int) -> [String] {
        let y = min(max(year, 1901), 2099)
        let m = min(max(month, 1), 12)
        let key = "\(y)-\(m)-\(count)"
        if let hit = monthLabelsCache[key] { return hit }
        var out: [String] = []
        out.reserveCapacity(count)
        for d in 1...max(1, count) {
            let l = Solar.fromYmdHms(year: y, month: m, day: d, hour: 12, minute: 0).lunar
            out.append(l.day == 1 ? "\(l.monthInChinese)月" : l.dayInChinese)
        }
        monthLabelsCache[key] = out
        return out
    }

    static func dayInfo(for date: Date) -> DayInfo {
        let (y, m, d) = clampedYMD(from: date)
        let key = "\(y)-\(m)-\(d)"
        if let hit = dayInfoCache[key] { return hit }
        let l = Solar.fromYmdHms(year: y, month: m, day: d, hour: 12, minute: 0).lunar
        let tList: [(String, String, String, String)] = l.times.map { t in
            (t.ganZhi, t.tianShenLuck,
             "宜 " + t.yi.prefix(6).joined(separator: " "),
             "忌 " + t.ji.prefix(5).joined(separator: " ") + " · " + t.chongDesc)
        }
        let info = DayInfo(
            dayInGanZhi: l.dayInGanZhi,
            yearInGanZhi: l.yearInGanZhi,
            monthInGanZhi: l.monthInGanZhi,
            yearShengXiao: l.yearShengXiao,
            monthInChinese: l.monthInChinese,
            dayInChinese: l.dayInChinese,
            weekInChinese: l.weekInChinese,
            zhiXing: l.zhiXing,
            dayNaYin: l.dayNaYin,
            xiuText: "\(l.xiu)\(l.zheng)\(l.animal)（\(l.xiuLuck)）— \(l.xiuSong)",
            tianShenText: "\(l.dayTianShen)（\(l.dayTianShenType)·\(l.dayTianShenLuck)）",
            nineStarText: "\(l.dayNineStar.number)\(l.dayNineStar.color) \(l.dayNineStar.wuXing) · 北斗\(l.dayNineStar.nameInBeiDou)",
            chongShaText: "\(l.dayChongDesc)，煞\(l.daySha)",
            taiShen: l.dayPositionTai,
            festivals: l.festivals.joined(separator: "、"),
            otherFestivals: l.otherFestivals.joined(separator: "、"),
            jieQiText: "上一节气 \(l.prevJieQi.name) · 下一节气 \(l.nextJieQi.name)",
            dayYi: l.dayYi,
            dayJi: l.dayJi,
            jiShen: l.dayJiShen.joined(separator: " "),
            xiongSha: l.dayXiongSha.joined(separator: " "),
            xiPos: "\(l.dayPositionXi)（\(l.dayPositionXiDesc)）",
            caiPos: "\(l.dayPositionCai)（\(l.dayPositionCaiDesc)）",
            fuPos: "\(l.dayPositionFu)（\(l.dayPositionFuDesc)）",
            yangGuiPos: "\(l.dayPositionYangGui)（\(l.dayPositionYangGuiDesc)）",
            yinGuiPos: "\(l.dayPositionYinGui)（\(l.dayPositionYinGuiDesc)）",
            pengZu: "\(l.pengZuGan)；\(l.pengZuZhi)",
            times: tList,
            year: l.year
        )
        dayInfoCache[key] = info
        return info
    }
}

struct AlmanacView: View {
    @State private var date: Date
    init(initialDate: Date = Date()) { _date = State(initialValue: initialDate) }

    var body: some View {
        let info = AlmanacLunarCache.dayInfo(for: date)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                AlmanacCalendarCard(date: $date)

                // 头卡：干支日＋农历＋宿
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(info.dayInGanZhi + "日")
                            .font(.system(.largeTitle, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        Text("\(info.yearShengXiao)年 · 农历\(info.monthInChinese)月\(info.dayInChinese)")
                            .font(.callout).foregroundStyle(Ky.sub)
                        Spacer()
                        KyBadge(text: "\(info.zhiXing)日", color: Ky.qingdai, filled: true)
                    }
                    Text("年柱 \(info.yearInGanZhi) · 月柱 \(info.monthInGanZhi) · 日纳音 \(info.dayNaYin) · 星期\(info.weekInChinese)")
                        .font(.caption).foregroundStyle(Ky.sub)
                    Divider()
                    row("二十八宿", info.xiuText)
                    row("值神建除", "\(info.zhiXing)日 · \(info.tianShenText)")
                    row("日九星", info.nineStarText)
                    row("冲煞胎神", "\(info.chongShaText) · 胎神 \(info.taiShen)")
                    if !info.festivals.isEmpty { row("传统节日", info.festivals) }
                    if !info.otherFestivals.isEmpty { row("纪念日", info.otherFestivals) }
                    row("相邻节气", info.jieQiText)
                }
                .kyCard()

                // 宜忌
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        KySectionTitle(title: "当日宜忌", trailing: "历书通参")
                        NavigationLink { ZejiView() } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles")
                                Text("近30天择吉 ›")
                            }.font(.caption).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                        }
                    }
                    HStack(alignment: .top, spacing: 8) {
                        KyBadge(text: "宜", color: Ky.jade, filled: true)
                        Text(info.dayYi.isEmpty ? "诸事不宜" : info.dayYi.joined(separator: " · "))
                            .font(.callout).foregroundStyle(Ky.ink).lineSpacing(3)
                    }
                    Divider().opacity(0.5)
                    HStack(alignment: .top, spacing: 8) {
                        KyBadge(text: "忌", color: Ky.cinnabar, filled: true)
                        Text(info.dayJi.isEmpty ? "无特定忌事" : info.dayJi.joined(separator: " · "))
                            .font(.callout).foregroundStyle(Ky.sub).lineSpacing(3)
                    }
                }
                .kyCard()

                // 吉神凶煞＋方位＋彭祖
                VStack(alignment: .leading, spacing: 8) {
                    KySectionTitle(title: "吉神方位", trailing: "彭祖百忌")
                    row("吉神宜趋", info.jiShen)
                    row("凶煞宜忌", info.xiongSha)
                    Divider()
                    row("喜神 / 财神", "喜神\(info.xiPos) · 财神\(info.caiPos)")
                    row("福神 / 贵神", "福神\(info.fuPos) · 阳贵\(info.yangGuiPos) · 阴贵\(info.yinGuiPos)")
                    Divider()
                    row("彭祖百忌", info.pengZu)
                }
                .kyCard()

                // 十二时辰
                VStack(alignment: .leading, spacing: 8) {
                    KySectionTitle(title: "十二时辰", trailing: "时辰吉凶宜忌")
                    ForEach(info.times.indices, id: \.self) { i in
                        let t = info.times[i]
                        HStack(alignment: .top, spacing: 8) {
                            Text(t.ganZhi)
                                .font(.system(.callout, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                                .frame(width: 44, alignment: .leading)
                            KyBadge(text: t.luck, color: t.luck == "吉" ? Ky.jade : Ky.cinnabar)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.yi).font(.caption).foregroundStyle(Ky.ink).lineLimit(1)
                                Text(t.ji).font(.caption2).foregroundStyle(Ky.sub).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        if i < info.times.count - 1 { Divider().opacity(0.4) }
                    }
                }
                .kyCard()

                YunQiView(year: info.year)
            }
            .padding(16)
            .padding(.bottom, 32)
        }
        .background(Ky.bg)
        .navigationTitle("今日黄历")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).font(.caption).fontWeight(.semibold).foregroundStyle(Ky.gold).frame(width: 68, alignment: .leading)
            Text(value).font(.callout).foregroundStyle(Ky.ink)
        }
    }
}

// MARK: - 黄历选日卡（init 直接注入合法年月，彻底消灭 showYear=0/showMonth=0 闪退）
struct AlmanacCalendarCard: View {
    @Binding var date: Date
    @State private var showYear: Int
    @State private var showMonth: Int
    private static let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    init(date: Binding<Date>) {
        self._date = date
        let (y, m, _) = AlmanacLunarCache.clampedYMD(from: date.wrappedValue)
        self._showYear = State(initialValue: y)
        self._showMonth = State(initialValue: m)
    }

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return c
    }
    private var today: (Int, Int, Int) {
        AlmanacLunarCache.clampedYMD(from: Date())
    }
    private var selected: (Int, Int, Int) {
        AlmanacLunarCache.clampedYMD(from: date)
    }
    private var safeYear: Int { min(max(showYear, 1901), 2099) }
    private var safeMonth: Int { min(max(showMonth, 1), 12) }

    private var daysInMonth: Int {
        var c = DateComponents(); c.year = safeYear; c.month = safeMonth; c.day = 1
        if let d = cal.date(from: c), let r = cal.range(of: .day, in: .month, for: d) { return r.count }
        return 30
    }
    private var firstOffset: Int {
        var c = DateComponents(); c.year = safeYear; c.month = safeMonth; c.day = 1
        let d = cal.date(from: c) ?? Date()
        let w = cal.component(.weekday, from: d)  // 1=周日
        return (w + 5) % 7  // 周一起始
    }
    private func pick(_ day: Int) {
        var c = DateComponents(); c.year = safeYear; c.month = safeMonth; c.day = min(max(day, 1), daysInMonth); c.hour = 12; c.minute = 0
        if let d = cal.date(from: c) { date = d }
    }
    private func stepMonth(_ d: Int) {
        var m = safeMonth + d, y = safeYear
        if m < 1 { m = 12; y = max(1901, y - 1) }
        if m > 12 { m = 1; y = min(2099, y + 1) }
        showMonth = m; showYear = y
    }
    private func stepDay(_ d: Int) {
        if let nd = cal.date(byAdding: .day, value: d, to: date) {
            date = nd
            let (ny, nm, _) = AlmanacLunarCache.clampedYMD(from: nd)
            showYear = ny; showMonth = nm
        }
    }

    var body: some View {
        let count = daysInMonth
        let labels = AlmanacLunarCache.monthLunarLabels(year: safeYear, month: safeMonth, count: count)
        let sel = selected
        let tod = today
        VStack(spacing: 10) {
            HStack {
                Text("选定日期").font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.ink)
                Spacer()
                Button("回今天") {
                    showYear = tod.0; showMonth = tod.1
                    pick(tod.2)
                }
                .font(.caption).fontWeight(.semibold)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Ky.qingdai.opacity(0.12)).foregroundStyle(Ky.qingdai).clipShape(Capsule())

                Button { stepMonth(-1) } label: {
                    Image(systemName: "chevron.left").font(.caption).frame(width: 28, height: 28).background(Ky.elevated).clipShape(Circle())
                }.accessibilityLabel("上个月")
                Text("\(safeYear)年\(safeMonth)月")
                    .font(KyV2.tabular(14, weight: .bold)).frame(minWidth: 88, alignment: .center)
                Button { stepMonth(1) } label: {
                    Image(systemName: "chevron.right").font(.caption).frame(width: 28, height: 28).background(Ky.elevated).clipShape(Circle())
                }.accessibilityLabel("下个月")
            }
            HStack(spacing: 0) {
                ForEach(Self.weekdays, id: \.self) { w in
                    Text(w).font(.caption2).fontWeight(.medium).foregroundStyle(Ky.sub).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<firstOffset, id: \.self) { _ in Color.clear.frame(height: 38) }
                ForEach(1...count, id: \.self) { d in
                    let isSel = sel == (safeYear, safeMonth, d)
                    let isToday = tod == (safeYear, safeMonth, d)
                    let lTxt = labels.indices.contains(d - 1) ? labels[d - 1] : ""
                    Button { pick(d) } label: {
                        VStack(spacing: 0) {
                            Text("\(d)").font(KyV2.tabular(14, weight: isSel ? .bold : .regular))
                            Text(lTxt).font(.system(size: 9))
                                .foregroundStyle(isSel ? Color.white.opacity(0.85) : Ky.sub)
                        }
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(isSel ? Ky.qingdai : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isToday && !isSel ? Ky.gold : Color.clear, lineWidth: 1.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(isSel ? Color.white : Ky.ink)
                    }.buttonStyle(.plain)
                }
            }
            HStack {
                Button("‹ 前一天") { stepDay(-1) }.font(.caption).foregroundStyle(Ky.qingdai)
                Spacer()
                Text("当前：\(sel.0)年\(sel.1)月\(sel.2)日")
                    .font(KyV2.tabular(12)).foregroundStyle(Ky.sub)
                Spacer()
                Button("后一天 ›") { stepDay(1) }.font(.caption).foregroundStyle(Ky.qingdai)
            }
        }
        .kyCard()
    }
}

// MARK: - 五运六气（岁运/司天在泉/主客气，《素问》体系通参）
struct YunQiView: View {
    let year: Int
    var body: some View {
        let safeY = min(max(year, 1901), 2099)
        let solar = Solar.fromYmdHms(year: safeY, month: 7, day: 1, hour: 12, minute: 0)
        let sIdx = ((solar.lunar.yearGanIndex % 10) + 10) % 10
        let bIdx = ((solar.lunar.yearZhiIndex % 12) + 12) % 12
        let stems = Array("甲乙丙丁戊己庚辛壬癸")
        let yunNames = ["土", "金", "水", "木", "火"]
        let yun = yunNames[(sIdx % 5)]
        let tai = [0, 2, 4, 6, 8].contains(sIdx) ? "太过" : "不及"
        let si: [Int: (String, String)] = [
            0: ("少阴君火", "阳明燥金"), 6: ("少阴君火", "阳明燥金"),
            1: ("太阴湿土", "太阳寒水"), 7: ("太阴湿土", "太阳寒水"),
            2: ("少阳相火", "厥阴风木"), 8: ("少阳相火", "厥阴风木"),
            3: ("阳明燥金", "少阴君火"), 9: ("阳明燥金", "少阴君火"),
            4: ("太阳寒水", "太阴湿土"), 10: ("太阳寒水", "太阴湿土"),
            5: ("厥阴风木", "少阳相火"), 11: ("厥阴风木", "少阳相火"),
        ]
        let (sitian, zaiquan) = si[bIdx] ?? ("少阴君火", "阳明燥金")
        let seq = ["厥阴风木", "少阴君火", "太阴湿土", "少阳相火", "阳明燥金", "太阳寒水"]
        let siPos = seq.firstIndex(of: sitian) ?? 0
        let ke = (0..<6).map { seq[(siPos - 2 + $0 + 6) % 6] }
        let zhu = ["厥阴风木", "少阴君火", "少阳相火", "太阴湿土", "阳明燥金", "太阳寒水"]
        let steps = ["初之气", "二之气", "三之气", "四之气", "五之气", "终之气"]
        VStack(alignment: .leading, spacing: 8) {
            KySectionTitle(title: "五运六气", trailing: "\(safeY) \(stems[sIdx])\(Array("子丑寅卯辰巳午未申酉戌亥")[bIdx])年")
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("大运统岁").font(.caption2).foregroundStyle(Ky.sub)
                    Text("\(yun)运\(tai)").font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.ink)
                }.frame(maxWidth: .infinity, alignment: .leading).kySubCard()
                VStack(alignment: .leading, spacing: 2) {
                    Text("上半年司天").font(.caption2).foregroundStyle(Ky.sub)
                    Text(sitian).font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.qingdai)
                }.frame(maxWidth: .infinity, alignment: .leading).kySubCard()
                VStack(alignment: .leading, spacing: 2) {
                    Text("下半年在泉").font(.caption2).foregroundStyle(Ky.sub)
                    Text(zaiquan).font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.gold)
                }.frame(maxWidth: .infinity, alignment: .leading).kySubCard()
            }
            ForEach(0..<6, id: \.self) { i in
                HStack(spacing: 10) {
                    Text(steps[i]).font(.caption).fontWeight(.semibold).foregroundStyle(Ky.gold).frame(width: 48, alignment: .leading)
                    Text("主气：\(zhu[i])").font(.caption).foregroundStyle(Ky.ink)
                    Text("客气：\(ke[i])").font(.caption).foregroundStyle(ke[i] == zhu[i] ? Ky.jade : Ky.sub)
                    Spacer()
                    if i == 2 { KyBadge(text: "司天", color: Ky.qingdai) }
                    if i == 5 { KyBadge(text: "在泉", color: Ky.gold) }
                }
            }
            Text("主客同气为顺，客胜主为逆；此为《素问》运气节令通参，不作诊疗断语。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }.kyCard()
    }
}
