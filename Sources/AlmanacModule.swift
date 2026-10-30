// 黄历简卡（2026-10-30）：干支/建除/彭祖/冲煞四样硬事实，全部可复核；
// 二十八宿与完整宜忌体系未并入，不拿半成品冒充全黄历。
import SwiftUI
import LunarSwift

struct AlmanacView: View {
    @State private var date = Date()
    private static let buildNames = ["建", "除", "满", "平", "定", "执", "破", "危", "成", "收", "开", "闭"]
    private static let buildText = ["建": "气专之日，宜立事开端", "除": "除旧之日，宜清理断舍", "满": "圆满之日，宜庆贺聚会",
        "平": "平稳之日，诸事平常心", "定": "安定之日，宜签约定局", "执": "执守之日，宜坚持推进",
        "破": "破败之日，宜破旧拆改、忌开张嫁娶", "危": "危险之日，行事留余地", "成": "成就之日，宜成事收官",
        "收": "收纳之日，宜收款入库", "开": "开市之日，宜开张出行", "闭": "闭藏之日，宜收尾封存"]
    private static let pengZuGan: [Character: String] = ["甲": "甲不开仓，财物耗亡", "乙": "乙不栽植，千株不长",
        "丙": "丙不修灶，必见灾殃", "丁": "丁不剃头，头必生疮", "戊": "戊不受田，田主不祥",
        "己": "己不破券，二比并亡", "庚": "庚不经络，织机虚张", "辛": "辛不合酱，主人不尝",
        "壬": "壬不汲水，更难提防", "癸": "癸不词讼，理弱敌强"]
    private static let pengZuZhi: [Character: String] = ["子": "子不问卜，自惹祸殃", "丑": "丑不冠带，主不还乡",
        "寅": "寅不祭祀，神鬼不尝", "卯": "卯不穿井，水泉不香", "辰": "辰不哭泣，必主重丧",
        "巳": "巳不远行，财物伏藏", "午": "午不苫盖，屋主更张", "未": "未不服药，毒气入肠",
        "申": "申不安床，鬼祟入房", "酉": "酉不会客，不主颠狂", "戌": "戌不吃犬，作怪上床", "亥": "亥不嫁娶，不利新郎"]
    private static let zodiac: [Character: String] = ["子": "鼠", "丑": "牛", "寅": "虎", "卯": "兔", "辰": "龙", "巳": "蛇",
        "午": "马", "未": "羊", "申": "猴", "酉": "鸡", "戌": "狗", "亥": "猪"]

    private var facts: (day: String, monthGZ: String, build: String, chong: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        let solar = Solar.fromYmdHms(year: c.year!, month: c.month!, day: c.day!, hour: 12, minute: 0)
        let ec = solar.lunar.eightChar
        ec.sect = 2
        let day = ec.day; let monthGZ = ec.month
        let dz = Array("子丑寅卯辰巳午未申酉戌亥")
        let off = (dz.firstIndex(of: day.last!)! - dz.firstIndex(of: monthGZ.last!)! + 12) % 12
        let chongBranch: [Character: Character] = ["子": "午", "午": "子", "丑": "未", "未": "丑", "寅": "申", "申": "寅",
                                                   "卯": "酉", "酉": "卯", "辰": "戌", "戌": "辰", "巳": "亥", "亥": "巳"]
        let cb = chongBranch[day.last!]!
        return (day, monthGZ, Self.buildNames[off], "\(cb)（\(Self.zodiac[cb] ?? "")）")
    }

    var body: some View {
        let f = facts
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DatePicker("选一天", selection: $date, displayedComponents: [.date])
                    .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(f.day).font(.system(.largeTitle, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        Text("日 · 月柱 \(f.monthGZ)").font(.callout).foregroundStyle(Ky.sub)
                    }
                    Divider()
                    row("建除", "\(f.build)日 — \(Self.buildText[f.build] ?? "")")
                    row("冲", "冲\(f.chong)，属\(Self.zodiac[f.day.last!] ?? "")者当日避冲位大事")
                    row("彭祖（干）", Self.pengZuGan[f.day.first!] ?? "")
                    row("彭祖（支）", Self.pengZuZhi[f.day.last!] ?? "")
                }
                .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
                Text("简卡口径：干支与节气月柱为历算事实；建除按月建起例；彭祖百忌为传统民俗条文。二八宿与完整宜忌未并入，先用这四样硬的。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("黄历简卡")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).font(.caption).fontWeight(.semibold).foregroundStyle(Ky.gold).frame(width: 58, alignment: .leading)
            Text(value).font(.callout).foregroundStyle(Ky.ink)
        }
    }
}
