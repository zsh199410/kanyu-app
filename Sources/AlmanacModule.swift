// 黄历完整版（2026-11-05 build-72 闪退根治与性能加速版）：
// 根治闪退：旧版 AlmanacCalendarCard 中 @State showYear=0 / showMonth=0 在首次 body 求值时（.onAppear 触发前）
// 直接传入 Solar.fromYmdHms(year: 0, month: 0, ...) 引发 LunarSwift 月份越界致命闪退；
// 现改为在 init 中直接按初始日期完成年月日初始化，并在所有历算入口加安全边界钳制与内存级月历缓存。
import SwiftUI
import LunarSwift
import UserNotifications

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
        let y = min(max(c.year ?? 2026, 1900), 2100)
        let m = min(max(c.month ?? 1, 1), 12)
        let d = min(max(c.day ?? 1, 1), 31)
        return (y, m, d)
    }

    static func monthLunarLabels(year: Int, month: Int, count: Int) -> [String] {
        let y = min(max(year, 1900), 2100)
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
    @State private var zejiPerson: Person? = nil
    init(initialDate: Date = Date()) { _date = State(initialValue: initialDate) }

    var body: some View {
        let info = AlmanacLunarCache.dayInfo(for: date)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                PersonQuickBar(store: PeopleStore.shared) { p in zejiPerson = p }
                if let zp = zejiPerson {
                    let zch = BaziEngine.cachedPaipan(clock: zp.birthDate, gender: zp.gender, longitude: zp.useLongitude ? zp.longitude : nil)
                    let zdb = String(zch.pillars[2].last ?? "?")
                    let yb = String(info.dayInGanZhi.last ?? "?")
                    let clash: [String: String] = ["子": "午", "午": "子", "丑": "未", "未": "丑", "寅": "申", "申": "寅", "卯": "酉", "酉": "卯", "辰": "戌", "戌": "辰", "巳": "亥", "亥": "巳"]
                    let liuHe: [String: String] = ["子": "丑", "丑": "子", "寅": "亥", "亥": "寅", "卯": "戌", "戌": "卯", "辰": "酉", "酉": "辰", "巳": "申", "申": "巳", "午": "未", "未": "午"]
                    let verdict = clash[zdb] == yb ? "相冲 · 当日避大事" : (liuHe[zdb] == yb ? "六合 · 吉" : "无刑冲")
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill").foregroundStyle(Ky.qingdai)
                        Text("命主 \(zp.name.isEmpty ? "未命名" : zp.name)日支 \(zdb)：今日日支 \(yb)——\(verdict)").font(.caption).foregroundStyle(Ky.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Ky.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
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
            .padding(.bottom, 100)
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
    private var safeYear: Int { min(max(showYear, 1900), 2100) }
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
        if m < 1 { m = 12; y = max(1900, y - 1) }
        if m > 12 { m = 1; y = min(2100, y + 1) }
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
                Text("\(String(safeYear))年\(safeMonth)月")
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
        let safeY = min(max(year, 1900), 2100)
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
            // G8 季度提示：只讲当季主气与客气、节律（主客同气为顺、客胜主为逆），不落病名。
            VStack(alignment: .leading, spacing: 6) {
                KySectionTitle(title: "季度提示", trailing: "只讲节律")
                let quarters: [(String, [Int], String)] = [
                    ("春", [0, 1], "气由寒转温"),
                    ("夏", [2], "气最盛，司天当令"),
                    ("秋", [3, 4], "气由盛转收"),
                    ("冬", [5], "气归藏，在泉当令"),
                ]
                ForEach(quarters.indices, id: \.self) { qi in
                    let q = quarters[qi]
                    let qZhu = q.1.map { zhu[$0] }.joined(separator: "、")
                    let qKe = q.1.map { ke[$0] }.joined(separator: "、")
                    let tong = q.1.contains { ke[$0] == zhu[$0] }
                    let tongText = tong ? "；主客同气为顺。" : "；客气与主气相异，以客胜主为逆。"
                    HStack(alignment: .top, spacing: 8) {
                        Text(q.0 + "季").font(.caption).fontWeight(.semibold).foregroundStyle(Ky.qingdai).frame(width: 28, alignment: .leading)
                        Text("主气 \(qZhu)；客气 \(qKe)。\(q.2)\(tongText)")
                            .font(.caption).foregroundStyle(Ky.ink).lineSpacing(2)
                    }
                }
            }
            Text("主客同气为顺，客胜主为逆；此为《素问》运气节令通参，不作诊疗断语。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }.kyCard()
    }
}

// MARK: - G1 每日运势「今日」三行（本机现算，不编断语）
// 口径与 Web app/today_card.py 逐字同源：
// ① 五行旺衰＝当日干支五行 vs InterpretEngine.posterXiJi 喜忌定论；
// ② 冲合＝当日地支 vs 四柱地支，BaziTables.relationFull 分级（冲＞刑＞穿＞合＞破）＋三合半合；
// ③ 大运流年＝YearEngine.report 四查定级＋现行大运（dayunMark 喜忌标）。
// 每行只报实算结果，附依据链；算不出的写「无据」。
struct TodayLine: Identifiable {
    let id: String
    let title: String
    let text: String
    let basis: String
}

enum TodayFortune {
    private static let wxNames = ["木", "火", "土", "金", "水"]
    private static let palaces = ["年柱", "月柱", "日柱", "时柱"]

    private static func wxName(of stem: Character) -> String {
        if let w = BaziTables.wx[stem] {
            return w.0
        }
        return "—"
    }

    private static func wxIndex(of stem: Character) -> Int {
        return wxNames.firstIndex(of: wxName(of: stem)) ?? 0
    }

    private static func word(for wxIdx: Int, xi: [Int], ji: [Int]) -> String {
        if xi.contains(wxIdx) {
            return "喜用"
        }
        if ji.contains(wxIdx) {
            return "忌"
        }
        return "中性"
    }

    @MainActor static func lines(chart ch: BaziChart, date: Date = Date()) -> [TodayLine] {
        let info = AlmanacLunarCache.dayInfo(for: date)
        let dayGanzhi = info.dayInGanZhi
        let dayStem = dayGanzhi.first ?? "?"
        let dayBranch = dayGanzhi.last ?? "?"
        let xj = InterpretEngine.posterXiJi(chart: ch)
        let xiNames = xj.xi.map { wxNames[$0] }.joined(separator: "、")
        let jiNames = xj.ji.map { wxNames[$0] }.joined(separator: "、")
        let stemWx = wxName(of: dayStem)
        let stemWxIdx = wxIndex(of: dayStem)
        let branchBenqi = BaziTables.cangGan[dayBranch]?.first ?? "?"
        let branchWx = wxName(of: branchBenqi)
        let branchWxIdx = wxIndex(of: branchBenqi)
        let line1: TodayLine
        if xj.level == "中和" || (xj.xi.isEmpty && xj.ji.isEmpty) {
            line1 = TodayLine(
                id: "wuxing",
                title: "今日五行旺衰",
                text: "今日\(dayStem)\(stemWx)、\(dayBranch)\(branchWx)：命主中和盘无固定喜忌，干支五行只作生克参考，不定喜忌。",
                basis: "依据：今日干支\(dayGanzhi)（干\(dayStem)行\(stemWx)、支\(dayBranch)行\(branchWx)）；命主喜忌定论为中和盘（InterpretEngine.posterXiJi：扶抑中和，无固定喜忌）。"
            )
        } else {
            let stemWord = word(for: stemWxIdx, xi: xj.xi, ji: xj.ji)
            let branchWord = word(for: branchWxIdx, xi: xj.xi, ji: xj.ji)
            line1 = TodayLine(
                id: "wuxing",
                title: "今日五行旺衰",
                text: "今日\(dayStem)\(stemWx)为命主\(stemWord)之行、\(dayBranch)\(branchWx)为命主\(branchWord)之行。",
                basis: "依据：今日干支\(dayGanzhi)（干\(dayStem)行\(stemWx)、支\(dayBranch)行\(branchWx)）；命主喜\(xiNames.isEmpty ? "无" : xiNames)、忌\(jiNames.isEmpty ? "无" : jiNames)（posterXiJi 定论：扶抑初判＋调候优先）。"
            )
        }

        var hits: [(palace: String, branch: Character, rel: String, rank: Int)] = []
        for i in ch.pillars.indices {
            let pb = ch.pillars[i].last ?? "?"
            if let r = BaziTables.relationFull(dayBranch, pb) {
                hits.append((palaces[i], pb, r.0, r.1))
            }
        }
        let hitPalaces = Set(hits.map { $0.palace })
        for i in ch.pillars.indices {
            if hitPalaces.contains(palaces[i]) {
                continue
            }
            let pb = ch.pillars[i].last ?? "?"
            if pb == dayBranch {
                continue
            }
            let inSameGroup = BaziTables.sanHeGroups.contains { g in
                g.members.contains(dayBranch) && g.members.contains(pb)
            }
            if inSameGroup {
                hits.append((palaces[i], pb, "三合半合", 0))
            }
        }
        hits.sort { $0.rank > $1.rank }
        let branchList = ch.pillars.indices.map { "\(palaces[$0])\(ch.pillars[$0].last ?? "?")" }.joined(separator: "、")
        let line2: TodayLine
        if hits.isEmpty {
            line2 = TodayLine(
                id: "chonghe",
                title: "今日冲合",
                text: "无冲合：今日地支\(dayBranch)与命主四柱地支无冲、合、刑、穿、破，亦无三合半合。",
                basis: "依据：今日地支\(dayBranch)；命主四柱地支\(branchList)（BaziTables.relationFull 分级：冲＞刑＞穿＞合＞破；三合半合为同组两支，未成局）。"
            )
        } else {
            let parts = hits.map { "\($0.palace)\($0.branch)\($0.rel)" }.joined(separator: "、")
            line2 = TodayLine(
                id: "chonghe",
                title: "今日冲合",
                text: "今日\(dayBranch)与命主\(parts)。",
                basis: "依据：今日地支\(dayBranch)；命主四柱地支\(branchList)（BaziTables.relationFull 分级：冲＞刑＞穿＞合＞破；三合半合为同组两支，未成局）。"
            )
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? TimeZone.current
        let year = cal.component(.year, from: date)
        let rep = YearEngine.report(chart: ch, year: year)
        let rizhuStem = ch.rizhu.first ?? "?"
        let line3: TodayLine
        if let di = YearEngine.dayunIndex(chart: ch, year: year) {
            let dgz = ch.dayunGanZhi[di]
            let dss = BaziTables.shiShen(day: rizhuStem, stem: dgz.first ?? "?")
            let mark = InterpretEngine.dayunMark(chart: ch, index: di)
            let dayunText = "\(dgz)运（\(dss)，喜忌\(mark)）"
            line3 = TodayLine(
                id: "dayun_liunian",
                title: "大运流年",
                text: "现行\(dayunText)；\(year)年流年\(rep.gz)，流年干为\(BaziTables.shiShen(day: rizhuStem, stem: rep.gz.first ?? "?"))，逐年定级\(rep.level)。",
                basis: "依据：逐年四查（YearEngine.report，\(year)年定级\(rep.level)）；现行大运\(dayunText)；流年干支\(rep.gz)。"
            )
        } else {
            let dayunText = year < ch.qiyunYear ? "未起运（童限）" : "已出所排大运范围"
            line3 = TodayLine(
                id: "dayun_liunian",
                title: "大运流年",
                text: "\(dayunText)；\(year)年流年\(rep.gz)，流年干为\(BaziTables.shiShen(day: rizhuStem, stem: rep.gz.first ?? "?"))，逐年定级\(rep.level)。",
                basis: "依据：逐年四查（YearEngine.report，\(year)年定级\(rep.level)）；\(dayunText)；流年干支\(rep.gz)。"
            )
        }
        return [line1, line2, line3]
    }
}

// MARK: - G1 每日运势本地通知（iOS 本地推送，不走服务端、不收集数据）
// 默认关闭；设置页一个开关＋时间选择（默认 07:30），每日一条（当日干支＋三行首句）。
// 通知内容在排期当时由本机引擎现算；开关／时间一改即重新排期，关闭即取消。
enum TodayNotificationManager {
    static let requestId = "kanyu.today.daily"
    static let enabledKey = "todayNotify.enabled"
    static let hourKey = "todayNotify.hour"
    static let minuteKey = "todayNotify.minute"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }
    static var hour: Int {
        let h = UserDefaults.standard.integer(forKey: hourKey)
        return h == 0 && UserDefaults.standard.object(forKey: hourKey) == nil ? 7 : h
    }
    static var minute: Int {
        if UserDefaults.standard.object(forKey: minuteKey) == nil {
            return 30
        }
        return UserDefaults.standard.integer(forKey: minuteKey)
    }

    static func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    @MainActor static func scheduleDaily(person: Person?) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestId])
        guard let p = person else {
            return
        }
        let chart = BaziEngine.cachedPaipan(clock: p.birthDate, gender: p.gender, longitude: p.useLongitude ? p.longitude : nil)
        let lines = TodayFortune.lines(chart: chart)
        let info = AlmanacLunarCache.dayInfo(for: Date())
        let firstLine = lines.first?.text ?? ""
        let content = UNMutableNotificationContent()
        content.title = "今日运势"
        content.body = "今日\(info.dayInGanZhi)日 · \(firstLine)"
        content.sound = .default
        var dc = DateComponents()
        dc.hour = hour
        dc.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)
        center.add(request)
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestId])
    }
}

// MARK: - G1 首页「今日」卡（与 Web /api/today 同款三行）
struct TodayFortuneCard: View {
    let person: Person?
    let chart: BaziChart?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                KyBadge(text: "今日运势", color: Ky.qingdai, filled: true)
                if let p = person {
                    Text(p.name.isEmpty ? "命主" : p.name)
                        .font(.caption).fontWeight(.semibold).foregroundStyle(Ky.ink)
                }
                Spacer()
                Text("本机现算 · 不编断语")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }
            if let ch = chart {
                let lines = TodayFortune.lines(chart: ch)
                ForEach(lines) { ln in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .top, spacing: 6) {
                            Text(ln.title)
                                .font(.caption).fontWeight(.bold).foregroundStyle(Ky.gold)
                                .frame(width: 86, alignment: .leading)
                            Text(ln.text)
                                .font(.callout).foregroundStyle(Ky.ink).lineSpacing(3)
                        }
                        Text(ln.basis)
                            .font(.caption2).foregroundStyle(Ky.sub).lineSpacing(2)
                            .padding(.leading, 92)
                    }
                    if ln.id != lines.last?.id {
                        Divider().opacity(0.5)
                    }
                }
            } else {
                Text("建档后可见命主专属三行（今日五行旺衰 · 今日冲合 · 大运流年），均由本机引擎现算。")
                    .font(.callout).foregroundStyle(Ky.sub).lineSpacing(3)
            }
        }
        .kyCard()
    }
}
