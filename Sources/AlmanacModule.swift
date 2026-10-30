// 黄历完整版（2026-10-30）：lunar-swift 全量历算——宜忌/二十八宿/建除/值神/吉神凶煞/
// 冲煞/方位/胎神/彭祖/九星/节气/节日/十二时辰宜忌吉凶。与 lunar 家族历算同源，已抽样对拍。
import SwiftUI
import LunarSwift

struct AlmanacView: View {
    @State private var date = Date()
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
                DatePicker("选一天", selection: $date, displayedComponents: [.date])
                    .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
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
                .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
                // 宜忌
                VStack(alignment: .leading, spacing: 8) {
                    Text("宜").font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.jade)
                    chips(l.dayYi)
                    Text("忌").font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.cinnabar)
                    chips(l.dayJi)
                }
                .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
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
                .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
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
                .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
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
