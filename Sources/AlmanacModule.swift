// 黄历完整版（2026-10-30）：lunar-swift 全量历算——宜忌/二十八宿/建除/值神/吉神凶煞/
// 冲煞/方位/胎神/彭祖/九星/节气/节日/十二时辰宜忌吉凶。与 lunar 家族历算同源，已抽样对拍。
import SwiftUI
import LunarSwift

struct AlmanacView: View {
    @State private var date: Date
    init(initialDate: Date = Date()) { _date = State(initialValue: initialDate) }
    private var lunar: Lunar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return Solar.fromYmdHms(year: c.year!, month: c.month!, day: c.day!, hour: 12, minute: 0).lunar
    }
    var body: some View {
        let l = lunar
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AlmanacCalendarCard(date: $date)
                // 头卡：干支日＋农历＋宿
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(l.dayInGanZhi).font(.system(.largeTitle, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        Text("\(l.yearShengXiao)年 · \(l.monthInChinese)月\(l.dayInChinese)")
                            .font(.callout).foregroundStyle(Ky.sub)
                    }
                    Text("年柱 \(l.yearInGanZhi) · 月柱 \(l.monthInGanZhi) · 日纳音 \(l.dayNaYin) · 星期\(l.weekInChinese)")
                        .font(.caption).foregroundStyle(Ky.sub)
                    Divider()
                    row("二十八宿", "\(l.xiu)\(l.zheng)\(l.animal)（\(l.xiuLuck)）— \(l.xiuSong)")
                    row("建除", "\(l.zhiXing)日")
                    row("值神", "\(l.dayTianShen)（\(l.dayTianShenType)·\(l.dayTianShenLuck)）")
                    row("日九星", "\(l.dayNineStar.number)\(l.dayNineStar.color) \(l.dayNineStar.wuXing) · 北斗\(l.dayNineStar.nameInBeiDou)")
                    row("冲煞", "\(l.dayChongDesc)，煞\(l.daySha)")
                    row("胎神", l.dayPositionTai)
                    if !l.festivals.isEmpty { row("节日", l.festivals.joined(separator: "、")) }
                    if !l.otherFestivals.isEmpty { row("纪念日", l.otherFestivals.joined(separator: "、")) }
                    row("节气", "上一节气 \(l.prevJieQi.name) · 下一节气 \(l.nextJieQi.name)")
                }
                .kyCard()
                // 宜忌
                VStack(alignment: .leading, spacing: 8) {
                    Text("宜").font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.jade)
                    chips(l.dayYi)
                    Text("忌").font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.cinnabar)
                    chips(l.dayJi)
                }
                .kyCard()
                // 吉神凶煞＋方位＋彭祖
                VStack(alignment: .leading, spacing: 8) {
                    row("吉神宜趋", l.dayJiShen.joined(separator: " "))
                    row("凶煞宜忌", l.dayXiongSha.joined(separator: " "))
                    Divider()
                    row("喜神", "\(l.dayPositionXi)（\(l.dayPositionXiDesc)）")
                    row("财神", "\(l.dayPositionCai)（\(l.dayPositionCaiDesc)）")
                    row("福神", "\(l.dayPositionFu)（\(l.dayPositionFuDesc)）")
                    row("阳贵", "\(l.dayPositionYangGui)（\(l.dayPositionYangGuiDesc)）")
                    row("阴贵", "\(l.dayPositionYinGui)（\(l.dayPositionYinGuiDesc)）")
                    Divider()
                    row("彭祖百忌", "\(l.pengZuGan)；\(l.pengZuZhi)")
                }
                .kyCard()
                // 十二时辰
                VStack(alignment: .leading, spacing: 8) {
                    Text("十二时辰").font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
                    ForEach(l.times.indices, id: \.self) { i in
                        let t = l.times[i]
                        HStack(alignment: .top, spacing: 8) {
                            Text(t.ganZhi).font(.callout).fontWeight(.semibold).foregroundStyle(Ky.ink)
                                .frame(width: 44, alignment: .leading)
                            Text(t.tianShenLuck).font(.caption).fontWeight(.bold)
                                .foregroundStyle(t.tianShenLuck == "吉" ? Ky.jade : Ky.cinnabar)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("宜 \(t.yi.prefix(6).joined(separator: " "))").font(.caption).foregroundStyle(Ky.ink).lineLimit(2)
                                Text("忌 \(t.ji.prefix(6).joined(separator: " ")) · \(t.chongDesc)").font(.caption).foregroundStyle(Ky.sub).lineLimit(2)
                            }
                        }
                        if i < l.times.count - 1 { Divider() }
                    }
                }
                .kyCard()
                YunQiView(year: l.year)
                Text("数据为 lunar 历算全量输出（宜忌含时辰层），与主流黄历同源算法；择吉仍须结合当事人命局，历书只作通参。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("黄历")
        .navigationBarTitleDisplayMode(.inline)
    }
    private func chips(_ items: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { s in
                Text(s).font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Ky.bg).clipShape(Capsule()).foregroundStyle(Ky.ink)
            }
        }
    }
    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).font(.caption).fontWeight(.semibold).foregroundStyle(Ky.gold).frame(width: 58, alignment: .leading)
            Text(value).font(.callout).foregroundStyle(Ky.ink)
        }
    }
}

// MARK: - 黄历选日卡（自绘中文日历，2026-11-03）
// 取代系统 DatePicker 弹窗：弹窗在部分环境下走英文月份/星期（November、MON–SUN），
// 且浮层盖住下方干支卡；自绘卡片随页面滚动、不遮挡，月份星期全部中文，格内小字配农历日。
// 与选时间弹层同套日历格做法（周一起始，与原弹窗版式一致；2026-11-01 周日落在最后一列）。
struct AlmanacCalendarCard: View {
    @Binding var date: Date
    @State private var showYear = 0
    @State private var showMonth = 0
    @State private var seeded = false
    private static let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return c
    }
    private var today: (Int, Int, Int) {
        let c = cal.dateComponents([.year, .month, .day], from: Date())
        return (c.year!, c.month!, c.day!)
    }
    private var selected: (Int, Int, Int) {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return (c.year!, c.month!, c.day!)
    }
    private var daysInMonth: Int {
        var c = DateComponents(); c.year = showYear; c.month = showMonth
        if let d = cal.date(from: c), let r = cal.range(of: .day, in: .month, for: d) { return r.count }
        return 30
    }
    private var firstOffset: Int {
        var c = DateComponents(); c.year = showYear; c.month = showMonth; c.day = 1
        let d = cal.date(from: c) ?? Date()
        let w = cal.component(.weekday, from: d)  // 1=周日
        return (w + 5) % 7  // 周一起始
    }
    private func lunarText(_ day: Int) -> String {
        let l = Solar.fromYmdHms(year: showYear, month: showMonth, day: day, hour: 12, minute: 0).lunar
        return l.day == 1 ? l.monthInChinese : l.dayInChinese
    }
    private func pick(_ day: Int) {
        var c = DateComponents(); c.year = showYear; c.month = showMonth; c.day = day; c.hour = 12; c.minute = 0
        if let d = cal.date(from: c) { date = d }
    }
    private func stepMonth(_ d: Int) {
        var m = showMonth + d, y = showYear
        if m < 1 { m = 12; y -= 1 }
        if m > 12 { m = 1; y += 1 }
        showMonth = m; showYear = y
    }
    private func stepDay(_ d: Int) {
        if let nd = cal.date(byAdding: .day, value: d, to: date) {
            date = nd
            let c = cal.dateComponents([.year, .month], from: nd)
            showYear = c.year!; showMonth = c.month!
        }
    }
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("选一天").font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
                Spacer()
                Button("今天") {
                    let t = today
                    showYear = t.0; showMonth = t.1
                    pick(t.2)
                }.font(.caption)
                Button { stepMonth(-1) } label: { Image(systemName: "chevron.left").font(.subheadline) }
                Text("\(showYear)年\(showMonth)月").font(.subheadline).fontWeight(.semibold).frame(minWidth: 92)
                Button { stepMonth(1) } label: { Image(systemName: "chevron.right").font(.subheadline) }
            }
            HStack(spacing: 0) {
                ForEach(Self.weekdays, id: \.self) { w in
                    Text(w).font(.caption2).foregroundStyle(Ky.sub).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<firstOffset, id: \.self) { _ in Color.clear.frame(height: 40) }
                ForEach(1...daysInMonth, id: \.self) { d in
                    let isSel = selected == (showYear, showMonth, d)
                    let isToday = today == (showYear, showMonth, d)
                    Button { pick(d) } label: {
                        VStack(spacing: 0) {
                            Text("\(d)").font(.subheadline).fontWeight(isSel ? .semibold : .regular)
                            Text(lunarText(d)).font(.caption2).foregroundStyle(Ky.sub)
                        }
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(isSel ? Ky.qingdai.opacity(0.16) : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isToday ? Ky.gold : Color.clear, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Ky.ink)
                    }.buttonStyle(.plain)
                }
            }
            HStack {
                Button("前一天") { stepDay(-1) }.font(.caption2)
                Spacer()
                Text("\(selected.0)年\(selected.1)月\(selected.2)日").font(.caption2).foregroundStyle(Ky.sub)
                Spacer()
                Button("后一天") { stepDay(1) }.font(.caption2)
            }
        }
        .kyCard()
        .onAppear {
            if !seeded {
                showYear = selected.0; showMonth = selected.1; seeded = true
            }
        }
    }
}

// MARK: - 五运六气（问真独有项，补齐：岁运/司天在泉/主客气，《素问》体系通参）
struct YunQiView: View {
    let year: Int
    var body: some View {
        let solar = Solar.fromYmdHms(year: year, month: 7, day: 1, hour: 12, minute: 0)
        let sIdx = solar.lunar.yearGanIndex % 10
        let bIdx = solar.lunar.yearZhiIndex % 12
        let stems = Array("甲乙丙丁戊己庚辛壬癸")
        let yunNames = ["土", "金", "水", "木", "火"]  // 甲己土 乙庚金 丙辛水 丁壬木 戊癸火
        let yun = yunNames[(sIdx % 5)]
        let tai = [0, 2, 4, 6, 8].contains(sIdx) ? "太过" : "不及"
        // 司天/在泉（年支组）：[司天, 在泉]
        let si: [Int: (String, String)] = [
            0: ("少阴君火", "阳明燥金"), 6: ("少阴君火", "阳明燥金"),
            1: ("太阴湿土", "太阳寒水"), 7: ("太阴湿土", "太阳寒水"),
            2: ("少阳相火", "厥阴风木"), 8: ("少阳相火", "厥阴风木"),
            3: ("阳明燥金", "少阴君火"), 9: ("阳明燥金", "少阴君火"),
            4: ("太阳寒水", "太阴湿土"), 10: ("太阳寒水", "太阴湿土"),
            5: ("厥阴风木", "少阳相火"), 11: ("厥阴风木", "少阳相火"),
        ]
        let (sitian, zaiquan) = si[bIdx] ?? ("", "")
        let seq = ["厥阴风木", "少阴君火", "太阴湿土", "少阳相火", "阳明燥金", "太阳寒水"]
        let siPos = seq.firstIndex(of: sitian) ?? 0
        let ke = (0..<6).map { seq[(siPos - 2 + $0 + 6) % 6] }
        let zhu = ["厥阴风木", "少阴君火", "少阳相火", "太阴湿土", "阳明燥金", "太阳寒水"]
        let steps = ["初之气", "二之气", "三之气", "四之气", "五之气", "终之气"]
        VStack(alignment: .leading, spacing: 8) {
            KySectionTitle(title: "五运六气", trailing: "\(year) \(stems[sIdx])\(Array("子丑寅卯辰巳午未申酉戌亥")[bIdx])年")
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("岁运").font(.caption2).foregroundStyle(Ky.sub)
                    Text("\(yun)运\(tai)").font(.headline).foregroundStyle(Ky.ink)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("司天").font(.caption2).foregroundStyle(Ky.sub)
                    Text(sitian).font(.headline).foregroundStyle(Ky.ink)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("在泉").font(.caption2).foregroundStyle(Ky.sub)
                    Text(zaiquan).font(.headline).foregroundStyle(Ky.ink)
                }
            }
            ForEach(0..<6, id: \.self) { i in
                HStack(spacing: 10) {
                    Text(steps[i]).font(.caption).fontWeight(.semibold).foregroundStyle(Ky.gold).frame(width: 46, alignment: .leading)
                    Text("主 \(zhu[i])").font(.caption).foregroundStyle(Ky.ink)
                    Text("客 \(ke[i])").font(.caption).foregroundStyle(ke[i] == zhu[i] ? Ky.jade : Ky.sub)
                    if i == 2 { Text("司天所临").font(.caption2).foregroundStyle(Ky.cinnabar) }
                    if i == 5 { Text("在泉所临").font(.caption2).foregroundStyle(Ky.cinnabar) }
                }
            }
            Text("主客相同为顺（气得其常），客胜主为逆；此为《素问》运气通参，不作诊疗断语。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }.kyCard()
    }
}
