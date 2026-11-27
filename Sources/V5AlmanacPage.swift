import SwiftUI

/// The original lunar cache is the sole source of calendar facts and auspicious labels.
struct V5AlmanacPage: View {
    @State private var date = Date()
    private var calendar: Calendar { BirthClockInput.calendar }
    private var range: ClosedRange<Date> {
        calendar.date(from: DateComponents(year: 1900, month: 1, day: 1))! ...
        calendar.date(from: DateComponents(year: 2100, month: 12, day: 31, hour: 23, minute: 59, second: 59))!
    }
    var body: some View {
        let info = AlmanacLunarCache.dayInfo(for: date)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: V5Metric.gap) {
                V5SectionHeading(title: "万年历", subtitle: "日月往来 · 岁时有序")
                V5Card {
                    VStack(alignment: .leading, spacing: 12) {
                        DatePicker("选择日期（北京时间）", selection: $date, in: range, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .environment(\.calendar, calendar)
                            .environment(\.timeZone, calendar.timeZone)
                            .accessibilityIdentifier("v5.almanac.date")
                        Button("回到今天") { date = Date() }.frame(minHeight: V5Metric.target)
                    }
                }
                V5Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(info.dayInGanZhi + "日").font(V5Typography.page)
                        Text("\(info.yearShengXiao)年 · 农历\(info.monthInChinese)月\(info.dayInChinese)").font(V5Typography.title)
                        Text("年柱 \(info.yearInGanZhi) · 月柱 \(info.monthInGanZhi)").font(V5Typography.detail)
                        Text("星期\(info.weekInChinese) · \(info.zhiXing)日 · \(info.dayNaYin)").font(V5Typography.detail)
                        Text(info.jieQiText).font(V5Typography.evidence)
                        if !info.festivals.isEmpty { Text(info.festivals).font(V5Typography.title) }
                        if !info.otherFestivals.isEmpty { Text(info.otherFestivals).font(V5Typography.detail) }
                    }
                }
                V5Card {
                    VStack(alignment: .leading, spacing: 16) {
                        V5SectionHeading(title: "民俗宜忌", subtitle: "来自既有历法资料，仅作传统文化参考；不构成行动保证。")
                        fact("宜", info.dayYi.joined(separator: " · "))
                        Divider()
                        fact("忌", info.dayJi.joined(separator: " · "))
                        Divider()
                        fact("冲煞", info.chongShaText)
                        fact("彭祖百忌", info.pengZu)
                    }
                }
                V5Card {
                    VStack(alignment: .leading, spacing: 16) {
                        V5SectionHeading(title: "时辰序列", subtitle: "按既有历法时辰顺序显示，不使用示例或自造评分。")
                        ForEach(Array(info.times.enumerated()), id: \.offset) { index, time in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(time.ganZhi) · \(time.luck)").font(V5Typography.title)
                                Text(time.yi).font(V5Typography.detail)
                                Text(time.ji).font(V5Typography.detail)
                            }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
                            if index + 1 < info.times.count { Divider() }
                        }
                    }
                }
                NavigationLink { AlmanacView(initialDate: date) } label: {
                    V5Card { V5LibraryRow(title: "专业历法与择吉", detail: "命主日支对照、方位、神煞与完整历法资料", icon: "calendar.badge.clock") }
                }.buttonStyle(.plain)
            }.padding(V5Metric.page)
        }
        .background(V5Palette.color(V5Palette.current.paper))
        .foregroundStyle(V5Palette.color(V5Palette.current.ink))
        .navigationTitle("万年历").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("v5.almanac.page")
    }
    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(V5Typography.title).foregroundStyle(V5Palette.color(V5Palette.current.ornamentText))
            Text(value.isEmpty ? "历法资料未提供" : value).font(V5Typography.body)
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }
}
