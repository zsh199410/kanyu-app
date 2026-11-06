// 出生录入组件 v5（2026-11-05 体验升级版）
// 核心修复与升级：
// 1. 修复 iOS .numberPad 纯数字键盘无回车键导致手输年份不触发 onSubmit 的严重交互 Bug（新增 .onChange 4位年份即时联动 + 键盘完成栏 + 确定前强制同步）；
// 2. 新增「年代速选胶囊（60后–20后）」，排父母/自己/孩子盘一键跳年代，免反复点按；
// 3. 升级生辰摘要卡为宋式票据卡片，公历/农历/真太阳时校正量/交节预警一目了然；
// 4. 三个录入面共用（八字/紫微/人物表单），外部调用签名 100% 保持不变。
import SwiftUI
import LunarSwift

struct BirthInputView: View {
    @Binding var clock: Date
    @Binding var useLongitude: Bool
    @Binding var longitudeText: String

    @State private var mode = 0   // 0 公历 1 农历（弹层内外共用，切换后保持）
    @State private var unknownHour = false
    @State private var showSheet = false
    @State private var provinceSel = ""

    private static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    // 出生地省市两级（城市中心值 0.1°）
    private static let provinceCities: [(String, [(String, Double)])] = [
        ("重庆", [("梁平", 107.8), ("重庆主城", 106.5), ("万州", 108.4), ("涪陵", 107.4), ("永川", 105.9),
                  ("合川", 106.3), ("江津", 106.3), ("长寿", 107.1), ("垫江", 107.4), ("忠县", 108.0),
                  ("开州", 108.4), ("云阳", 108.7), ("奉节", 109.5), ("巫山", 109.9), ("黔江", 108.8),
                  ("石柱", 108.1), ("秀山", 109.0), ("大足", 105.7), ("璧山", 106.2), ("铜梁", 106.1)]),
        ("四川", [("成都", 104.1), ("绵阳", 104.7), ("达州", 107.5), ("南充", 106.1), ("宜宾", 104.6),
                  ("泸州", 105.4), ("德阳", 104.4), ("乐山", 103.8), ("广安", 106.6), ("遂宁", 105.6),
                  ("内江", 105.1), ("自贡", 104.8), ("眉山", 103.8), ("广元", 105.8), ("巴中", 106.8),
                  ("攀枝花", 101.7), ("西昌", 102.3), ("康定", 102.0), ("马尔康", 102.2)]),
        ("北京", [("北京", 116.4)]),
        ("上海", [("上海", 121.5)]),
        ("天津", [("天津", 117.2)]),
        ("广东", [("广州", 113.3), ("深圳", 114.1), ("佛山", 113.1), ("东莞", 113.8), ("珠海", 113.6),
                  ("中山", 113.4), ("惠州", 114.4), ("汕头", 116.7), ("潮州", 116.6), ("湛江", 110.4), ("江门", 113.1)]),
        ("浙江", [("杭州", 120.2), ("宁波", 121.6), ("温州", 120.7), ("绍兴", 120.6), ("嘉兴", 120.8),
                  ("台州", 121.4), ("金华", 119.6), ("湖州", 120.1), ("丽水", 119.9), ("衢州", 118.9), ("舟山", 122.2)]),
        ("江苏", [("南京", 118.8), ("苏州", 120.6), ("无锡", 120.3), ("常州", 119.9), ("南通", 120.9),
                  ("徐州", 117.2), ("扬州", 119.4), ("盐城", 120.2), ("泰州", 119.9), ("镇江", 119.4), ("淮安", 119.0), ("连云港", 119.2)]),
        ("山东", [("济南", 117.0), ("青岛", 120.4), ("烟台", 121.4), ("潍坊", 119.2), ("临沂", 118.4),
                  ("济宁", 116.6), ("淄博", 118.1), ("威海", 122.1), ("泰安", 117.1), ("德州", 116.4)]),
        ("河南", [("郑州", 113.6), ("洛阳", 112.5), ("南阳", 112.5), ("新乡", 113.9), ("开封", 114.3),
                  ("安阳", 114.4), ("商丘", 115.7), ("周口", 114.7), ("信阳", 114.1), ("驻马店", 114.0)]),
        ("湖北", [("武汉", 114.3), ("宜昌", 111.3), ("襄阳", 112.1), ("荆州", 112.2), ("十堰", 110.8),
                  ("恩施", 109.5), ("黄冈", 114.9), ("孝感", 113.9)]),
        ("湖南", [("长沙", 112.9), ("株洲", 113.2), ("湘潭", 112.9), ("衡阳", 112.6), ("岳阳", 113.1),
                  ("常德", 111.7), ("张家界", 110.5), ("怀化", 110.0), ("吉首", 109.7)]),
        ("福建", [("福州", 119.3), ("厦门", 118.1), ("泉州", 118.7), ("漳州", 117.6), ("莆田", 119.0),
                  ("宁德", 119.5), ("南平", 118.2), ("龙岩", 117.0), ("三明", 117.6)]),
        ("安徽", [("合肥", 117.2), ("芜湖", 118.4), ("蚌埠", 117.4), ("安庆", 117.1), ("阜阳", 115.8), ("黄山", 118.3)]),
        ("江西", [("南昌", 115.9), ("赣州", 114.9), ("九江", 116.0), ("上饶", 117.9), ("景德镇", 117.2), ("吉安", 115.0)]),
        ("河北", [("石家庄", 114.5), ("唐山", 118.2), ("保定", 115.5), ("邯郸", 114.5), ("秦皇岛", 119.6), ("张家口", 114.9), ("承德", 117.9)]),
        ("山西", [("太原", 112.6), ("大同", 113.3), ("运城", 111.0), ("临汾", 111.5), ("长治", 113.1)]),
        ("陕西", [("西安", 108.9), ("咸阳", 108.7), ("宝鸡", 107.2), ("榆林", 109.7), ("延安", 109.5), ("汉中", 107.0), ("安康", 109.0)]),
        ("辽宁", [("沈阳", 123.4), ("大连", 121.6), ("鞍山", 123.0), ("锦州", 121.1), ("丹东", 124.4)]),
        ("吉林", [("长春", 125.3), ("吉林市", 126.5), ("延吉", 129.5), ("四平", 124.4)]),
        ("黑龙江", [("哈尔滨", 126.5), ("齐齐哈尔", 124.0), ("牡丹江", 129.6), ("大庆", 125.1), ("佳木斯", 130.4)]),
        ("广西", [("南宁", 108.3), ("桂林", 110.3), ("柳州", 109.4), ("北海", 109.1), ("玉林", 110.2)]),
        ("云南", [("昆明", 102.8), ("大理", 100.3), ("丽江", 100.2), ("曲靖", 103.8), ("西双版纳", 100.8)]),
        ("贵州", [("贵阳", 106.7), ("遵义", 106.9), ("六盘水", 104.8), ("毕节", 105.3), ("铜仁", 109.2)]),
        ("海南", [("海口", 110.3), ("三亚", 109.5)]),
        ("内蒙古", [("呼和浩特", 111.7), ("包头", 109.8), ("赤峰", 118.9), ("鄂尔多斯", 109.8), ("呼伦贝尔", 119.8)]),
        ("甘肃", [("兰州", 103.8), ("天水", 105.7), ("酒泉", 98.5), ("敦煌", 94.7)]),
        ("新疆", [("乌鲁木齐", 87.6), ("喀什", 76.0), ("伊宁", 81.3), ("克拉玛依", 84.9), ("哈密", 93.5)]),
        ("青海", [("西宁", 101.8), ("格尔木", 94.9)]),
        ("宁夏", [("银川", 106.3), ("中卫", 105.2)]),
        ("西藏", [("拉萨", 91.1), ("日喀则", 88.9), ("林芝", 94.4)]),
        ("香港", [("香港", 114.2)]),
        ("澳门", [("澳门", 113.5)]),
        ("台湾", [("台北", 121.6), ("台中", 120.7), ("高雄", 120.3)]),    ]
    private static var places: [(String, Double)] { provinceCities.flatMap { $0.1 } }
    private static func province(of city: String) -> String? {
        provinceCities.first(where: { $0.1.contains(where: { $0.0 == city }) })?.0
    }
    private static let lunarMonths = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
    private static let lunarDays = ["初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                                    "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                                    "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]

    static func solarOf(_ date: Date) -> Solar {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return Solar.fromYmdHms(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1, hour: c.hour ?? 12, minute: c.minute ?? 0)
    }

    private var placeName: String {
        if let p = Self.places.first(where: { abs($0.1 - (Double(longitudeText) ?? -999)) < 0.051 }) { return p.0 }
        return "自定义"
    }

    /// 经度 → 「省·城市」标签（供预测单题头用；与输入页同表同口径，误差 0.051° 内匹配）
    static func placeLabel(longitude: Double) -> String? {
        for (prov, cities) in provinceCities {
            if let c = cities.first(where: { abs($0.1 - longitude) < 0.051 }) {
                return "\(prov)·\(c.0)"
            }
        }
        return nil
    }
    private var cityOptions: [(String, Double)] {
        if let prov = Self.provinceCities.first(where: { $0.0 == provinceSel }) { return prov.1 }
        return Self.places
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 生辰摘要票据卡：点一下弹层改时间
            Button { showSheet = true } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            KyBadge(text: "生辰", color: Ky.qingdai)
                            Text(summarySolar)
                                .font(KyV2.tabular(15, weight: .semibold))
                                .foregroundStyle(Ky.ink)
                        }
                        HStack(spacing: 6) {
                            KyBadge(text: "农历", color: Ky.gold)
                            Text(summaryLunar)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Ky.sub)
                        }
                        if unknownHour {
                            Text("时辰未知：当前按午时（12:00）暂排，涉时柱结论降权参考")
                                .font(.caption2).foregroundStyle(Ky.cinnabar)
                        }
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.clock")
                        Text("修改")
                    }
                    .font(.caption).fontWeight(.semibold)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Ky.qingdai.opacity(0.12))
                    .foregroundStyle(Ky.qingdai)
                    .clipShape(Capsule())
                }
                .kySubCard()
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showSheet) {
                TimePickerSheet(initial: clock, mode: $mode, useLongitude: useLongitude, longitudeText: longitudeText) { date, unknown in
                    clock = date; unknownHour = unknown; showSheet = false
                }
            }

            summaryDetails

            // 真太阳时与出生地级联区
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $useLongitude) {
                    HStack(spacing: 6) {
                        Image(systemName: "sun.max.fill").foregroundStyle(Ky.gold)
                        Text("真太阳时校正").font(.subheadline).fontWeight(.medium).foregroundStyle(Ky.ink)
                        if useLongitude {
                            Text(placeName).font(.caption).foregroundStyle(Ky.qingdai)
                        }
                    }
                }
                .tint(Ky.qingdai)

                if useLongitude {
                    HStack(spacing: 8) {
                        // 省份选择
                        Menu {
                            ForEach(Self.provinceCities, id: \.0) { prov in
                                Button(prov.0) {
                                    provinceSel = prov.0
                                    if let firstCity = prov.1.first {
                                        longitudeText = String(format: "%.1f", firstCity.1)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(provinceSel.isEmpty ? "选省份" : provinceSel)
                                    .font(.caption).fontWeight(.medium).foregroundStyle(Ky.ink)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Ky.sub)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Ky.card)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Ky.line, lineWidth: 0.7))
                        }

                        // 城市选择
                        Menu {
                            ForEach(cityOptions, id: \.0) { p in
                                Button("\(p.0)（东经 \(String(format: "%.1f", p.1))°）") {
                                    longitudeText = String(format: "%.1f", p.1)
                                    if let prov = Self.province(of: p.0) { provinceSel = prov }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(placeName)
                                    .font(.caption).fontWeight(.medium).foregroundStyle(Ky.ink)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Ky.sub)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Ky.card)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Ky.line, lineWidth: 0.7))
                        }

                        // 经度微调框
                        HStack(spacing: 2) {
                            Text("东经").font(.caption2).foregroundStyle(Ky.sub)
                            TextField("107.8", text: $longitudeText)
                                .keyboardType(.decimalPad)
                                .font(KyV2.tabular(13, weight: .semibold))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 50)
                            Text("°").font(.caption).foregroundStyle(Ky.sub)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 7)
                        .background(Ky.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Ky.line, lineWidth: 0.7))
                    }
                }
            }
            .kySubCard()
        }
        .onAppear {
            if provinceSel.isEmpty, placeName != "自定义", let prov = Self.province(of: placeName) { provinceSel = prov }
        }
    }

    private var summarySolar: String {
        let s = Self.solarOf(clock)
        return "\(s.year)年\(s.month)月\(s.day)日 \(String(format: "%02d:%02d", s.hour, s.minute))"
    }
    private var summaryLunar: String {
        let l = Self.solarOf(clock).lunar
        let mName = Self.lunarMonths[abs(l.month) - 1]
        let dName = Self.lunarDays[max(0, min(29, l.day - 1))]
        let br = Self.branches[((l.hour + 1) / 2) % 12]
        return "\(BaziChart.yearGanZhi(l.year))年\(l.month < 0 ? "闰" : "")\(mName)\(dName) · \(br)时"
    }

    private var summaryDetails: some View {
        let s = Self.solarOf(clock)
        let l = s.lunar
        let lon = Double(longitudeText)
        return VStack(alignment: .leading, spacing: 4) {
            if useLongitude {
                if let lo = lon, (-180...180).contains(lo) {
                    let corr = TrueSolarTime.corrected(clock: clock, longitude: lo)
                    let delta = Int((corr.timeIntervalSince(clock) / 60).rounded())
                    let cs = Self.solarOf(corr)
                    HStack(spacing: 5) {
                        Image(systemName: "clock.badge.checkmark").foregroundStyle(Ky.qingdai)
                        Text("真太阳时 \(String(format: "%02d:%02d", cs.hour, cs.minute))（经度＋均时差 \(delta >= 0 ? "+" : "")\(delta) 分钟，入盘为准）")
                    }
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("经度格式有误：将按未校正钟表时间排盘，请填 -180~180 数字（如梁平 107.8）")
                    }
                    .foregroundStyle(Ky.cinnabar).fontWeight(.semibold)
                }
            }
            if s.hour == 23 {
                HStack(spacing: 5) {
                    Image(systemName: "moon.stars").foregroundStyle(Ky.cinnabar)
                    Text("夜子时（23:00–24:00）：当前按口径设置（默认 sect=2 日柱算当日、时干按次日推）")
                }.foregroundStyle(Ky.cinnabar)
            }
            if let jq = Self.nearestJieQiText(lunar: l, clock: clock) {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "sparkles").foregroundStyle(Ky.cinnabar)
                    Text(jq)
                }.foregroundStyle(Ky.cinnabar)
            }
        }
        .font(.caption)
        .foregroundStyle(Ky.qingdai)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func nearestJieQiText(lunar l: Lunar, clock: Date) -> String? {
        func hoursTo(_ sol: Solar) -> Double {
            var c = DateComponents(); c.year = sol.year; c.month = sol.month; c.day = sol.day; c.hour = sol.hour; c.minute = sol.minute
            guard let d = Calendar(identifier: .gregorian).date(from: c) else { return 999 }
            return abs(d.timeIntervalSince(clock)) / 3600
        }
        var best: (String, Double)?
        for jq in [l.prevJieQi, l.nextJieQi] {
            let h = hoursTo(jq.solar)
            if h < 24, best == nil || h < best!.1 { best = (jq.name, h) }
        }
        guard let b = best else { return nil }
        return "出生距节气「\(b.0)」仅约 \(Int(b.1.rounded())) 小时——月柱以交节时刻切换，请核准分钟。"
    }
}

// MARK: - 选时间弹层（草稿制：所有改动只动本地草稿，点「确定」先同步年份输入再回写）
private struct TimePickerSheet: View {
    let initial: Date
    @Binding var mode: Int
    let useLongitude: Bool
    let longitudeText: String
    let onConfirm: (Date, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var yearFieldFocused: Bool

    @State private var sy = 2000; @State private var smo = 1; @State private var sd = 1
    @State private var sh = 12; @State private var smi = 0
    @State private var ly = 2000; @State private var lmo = 1; @State private var ld = 1
    @State private var lh = 12; @State private var lmi = 0; @State private var leap = false
    @State private var unknown = false
    @State private var useWheel = false  // 输入方式：false 点选日历 / true 紧凑滚轮
    @State private var yearText = ""
    @State private var seeded = false

    private static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    private static let branchRange = ["23–1", "1–3", "3–5", "5–7", "7–9", "9–11", "11–13", "13–15", "15–17", "17–19", "19–21", "21–23"]
    private static let lunarMonths = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
    private static let lunarDays = ["初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                                    "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                                    "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]
    private static let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
    private static let decades: [(String, Int)] = [
        ("40后", 1945), ("50后", 1955), ("60后", 1965), ("70后", 1975),
        ("80后", 1985), ("90后", 1994), ("00后", 2004), ("10后", 2015), ("20后", 2024)
    ]

    private var curHour: Int { mode == 0 ? sh : lh }
    private var curMinute: Int { mode == 0 ? smi : lmi }
    private var curBranch: Int { ((curHour + 1) / 2) % 12 }
    private var leapMonthOfYear: Int { LunarYear.fromYear(lunarYear: ly).leapMonth }
    private var hasLeapChoice: Bool { leapMonthOfYear == lmo }
    private var lunarDayCount: Int {
        let m = leap ? -lmo : lmo
        return Lunar.fromYmdHms(lunarYear: ly, lunarMonth: m, lunarDay: 30, hour: 0, minute: 0).day == 30 ? 30 : 29
    }
    private var solarDayCount: Int {
        var c = DateComponents(); c.year = sy; c.month = smo
        let cal = Calendar(identifier: .gregorian)
        if let d = cal.date(from: c), let r = cal.range(of: .day, in: .month, for: d) { return r.count }
        return 31
    }
    private var dayCount: Int { mode == 0 ? solarDayCount : lunarDayCount }
    private var curDay: Int { mode == 0 ? sd : ld }
    private var firstWeekday: Int {
        let solar: Solar
        if mode == 0 {
            solar = Solar.fromYmdHms(year: sy, month: smo, day: 1, hour: 12, minute: 0)
        } else {
            solar = Lunar.fromYmdHms(lunarYear: ly, lunarMonth: (leap && hasLeapChoice) ? -lmo : lmo, lunarDay: 1, hour: 12, minute: 0).solar
        }
        var c = DateComponents(); c.year = solar.year; c.month = solar.month; c.day = solar.day
        let d = Calendar(identifier: .gregorian).date(from: c) ?? Date()
        return Calendar(identifier: .gregorian).component(.weekday, from: d) - 1
    }
    private var minutesToBoundary: Int {
        let h = curHour, m = curMinute
        return (h % 2 == 1 ? 120 : 60) - m
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Picker("历法", selection: $mode) {
                        Text("公历（阳历）").tag(0)
                        Text("农历（阴历）").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _ in convertDraft() }

                    Picker("输入方式", selection: $useWheel) {
                        Text("点选日历").tag(false)
                        Text("年月日时滚轮").tag(true)
                    }
                    .pickerStyle(.segmented)

                    previewCard

                    VStack(alignment: .leading, spacing: 12) {
                        if useWheel {
                            eraBar
                            wheelView
                        } else {
                            yearRow
                            decadeBar
                            eraBar
                            Divider()
                            monthRow
                            dayGrid
                        }
                        if mode == 1 {
                            leapChip
                            if hasLeapChoice {
                                Toggle("闰\(Self.lunarMonths[lmo - 1])", isOn: $leap)
                                    .tint(Ky.qingdai)
                            } else if leap {
                                Text("该年无此闰月，已自动按平月排。").font(.caption2).foregroundStyle(Ky.cinnabar)
                            }
                        }
                    }.kyCard()

                    VStack(alignment: .leading, spacing: 12) {
                        shichenSection
                        Divider()
                        hourMinuteSection
                        if minutesToBoundary <= 15 {
                            HStack(spacing: 5) {
                                Image(systemName: "exclamationmark.clock")
                                Text("距下一时辰交界仅约 \(minutesToBoundary) 分钟——分钟数会影响时柱，请核准。")
                            }
                            .font(.caption2).foregroundStyle(Ky.cinnabar)
                        }
                    }.kyCard()
                }.padding(16)
            }
            .background(Ky.bg)
            .navigationTitle("选择出生时间").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.foregroundStyle(Ky.sub)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        applyYearText()
                        onConfirm(compose(), unknown)
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(Ky.qingdai)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        applyYearText()
                        yearFieldFocused = false
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Ky.qingdai)
                }
            }
        }
        .onAppear {
            if !seeded {
                let cal = Calendar(identifier: .gregorian)
                let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: initial)
                sy = c.year ?? 2000; smo = c.month ?? 1; sd = c.day ?? 1; sh = c.hour ?? 12; smi = c.minute ?? 0
                let l = BirthInputView.solarOf(initial).lunar
                ly = l.year; lmo = abs(l.month); ld = l.day; lh = l.hour; lmi = l.minute; leap = l.month < 0
                yearText = "\(sy)"
                seeded = true
            }
        }
    }

    // MARK: 年月步进＋4位年份即时联动
    private var yearRow: some View {
        HStack(spacing: 10) {
            Text("出生年份").font(.subheadline).fontWeight(.medium).foregroundStyle(Ky.ink)
            Spacer()
            Button { stepYear(-10) } label: {
                Text("-10年").font(.caption2).padding(.horizontal, 7).padding(.vertical, 5)
                    .background(Ky.elevated).clipShape(Capsule()).foregroundStyle(Ky.sub)
            }.buttonStyle(.plain)
            Button { stepYear(-1) } label: {
                Image(systemName: "chevron.left").font(.subheadline)
                    .frame(width: 30, height: 30).background(Ky.elevated).clipShape(Circle())
            }.accessibilityLabel("上一年")
            TextField("1994", text: $yearText)
                .keyboardType(.numberPad)
                .focused($yearFieldFocused)
                .font(KyV2.tabular(16, weight: .bold))
                .multilineTextAlignment(.center)
                .frame(width: 78)
                .padding(.vertical, 6)
                .background(Ky.elevated)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Ky.qingdai.opacity(0.45), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: yearText) { _, newValue in
                    let digits = newValue.filter { $0.isNumber }
                    if digits.count == 4, let y = Int(digits), (1900...2099).contains(y) {
                        let clamped = clampYear(y)
                        if mode == 0 { sy = clamped; sd = min(sd, solarDayCount) }
                        else { ly = clamped; ld = min(ld, lunarDayCount) }
                    }
                }
                .onSubmit { applyYearText() }
            Button { stepYear(1) } label: {
                Image(systemName: "chevron.right").font(.subheadline)
                    .frame(width: 30, height: 30).background(Ky.elevated).clipShape(Circle())
            }.accessibilityLabel("下一年")
            Button { stepYear(10) } label: {
                Text("+10年").font(.caption2).padding(.horizontal, 7).padding(.vertical, 5)
                    .background(Ky.elevated).clipShape(Capsule()).foregroundStyle(Ky.sub)
            }.buttonStyle(.plain)
        }
    }

    private var decadeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Self.decades, id: \.0) { label, yr in
                    let curY = mode == 0 ? sy : ly
                    let active = (yr / 10) == (curY / 10)
                    Button {
                        if mode == 0 { sy = yr; sd = min(sd, solarDayCount) }
                        else { ly = yr; ld = min(ld, lunarDayCount) }
                        yearText = "\(yr)"
                        yearFieldFocused = false
                    } label: {
                        Text(label)
                            .font(.caption2).fontWeight(active ? .semibold : .regular)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(active ? Ky.qingdai : Ky.elevated)
                            .foregroundStyle(active ? Color.white : Ky.ink)
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 年代快跳（长辈时代／新生儿）——点一下跳到该段中位年份，免反复点按
    private var eraBar: some View {
        HStack(spacing: 6) {
            eraButton("长辈时代", "1930–1959", 1930...1959, 1945)
            eraButton("新生儿", "2020–2026", 2020...2026, 2023)
            Spacer()
        }
    }
    private func eraButton(_ label: String, _ rangeText: String, _ range: ClosedRange<Int>, _ yr: Int) -> some View {
        let curY = mode == 0 ? sy : ly
        let active = range.contains(curY)
        return Button {
            if mode == 0 { sy = yr; sd = min(sd, solarDayCount) }
            else { ly = yr; ld = min(ld, lunarDayCount) }
            yearText = "\(yr)"
            yearFieldFocused = false
        } label: {
            HStack(spacing: 4) {
                Text(label).font(.caption2).fontWeight(.semibold)
                Text(rangeText).font(.caption2)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(active ? Ky.gold : Ky.gold.opacity(0.12))
            .foregroundStyle(active ? Color.white : Ky.ink)
            .clipShape(Capsule())
        }.buttonStyle(.plain)
    }

    // MARK: 闰月快捷芯片——当年有闰月即浮现，点一下直跳闰月（原 Toggle 只在已选闰月时才出现）
    private var leapChip: some View {
        Group {
            if mode == 1, leapMonthOfYear != 0 {
                HStack(spacing: 6) {
                    Image(systemName: "moon.fill").font(.caption2).foregroundStyle(Ky.qingdai)
                    Text("今年闰\(Self.lunarMonths[leapMonthOfYear - 1])")
                        .font(.caption).fontWeight(.medium).foregroundStyle(Ky.ink)
                    Spacer()
                    if lmo == leapMonthOfYear, leap {
                        Text("已在闰月").font(.caption2).foregroundStyle(Ky.sub)
                    } else {
                        Button("跳至闰月") {
                            lmo = leapMonthOfYear; leap = true; ld = min(ld, lunarDayCount)
                        }
                        .font(.caption2).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Ky.qingdai.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: 年月日时紧凑滚轮——与点选日历双轨并存，随历法切换公历／农历
    private var yearBinding: Binding<Int> {
        Binding(get: { mode == 0 ? sy : ly }, set: { y in
            if mode == 0 { sy = y; sd = min(sd, solarDayCount) }
            else { ly = y; ld = min(ld, lunarDayCount) }
            yearText = "\(y)"
        })
    }
    private var monthBinding: Binding<Int> {
        Binding(get: { mode == 0 ? smo : lmo }, set: { m in
            if mode == 0 { smo = m; sd = min(sd, solarDayCount) }
            else { lmo = m; leap = false; ld = min(ld, lunarDayCount) }
        })
    }
    private var dayBinding: Binding<Int> {
        Binding(get: { mode == 0 ? sd : ld }, set: { d in
            if mode == 0 { sd = d } else { ld = d }
        })
    }
    private var wheelBranch: Binding<Int> {
        Binding(get: { curBranch }, set: { pickBranch($0) })
    }
    private var wheelView: some View {
        HStack(spacing: 2) {
            Picker("年", selection: yearBinding) {
                ForEach(1920...2035, id: \.self) { y in Text("\(y)").tag(y) }
            }
            .pickerStyle(.wheel).frame(width: 84, height: 132).clipped()
            Picker("月", selection: monthBinding) {
                ForEach(1...12, id: \.self) { m in
                    Text(mode == 0 ? "\(m)月" : Self.lunarMonths[m - 1]).tag(m)
                }
            }
            .pickerStyle(.wheel).frame(width: 66, height: 132).clipped()
            Picker("日", selection: dayBinding) {
                ForEach(1...dayCount, id: \.self) { d in
                    Text(mode == 0 ? "\(d)日" : Self.lunarDays[d - 1]).tag(d)
                }
            }
            .pickerStyle(.wheel).frame(width: 66, height: 132).clipped()
            Picker("时辰", selection: wheelBranch) {
                ForEach(0..<12, id: \.self) { i in
                    Text("\(Self.branches[i]) \(Self.branchRange[i])").tag(i)
                }
            }
            .pickerStyle(.wheel).frame(width: 96, height: 132).clipped()
        }
        .frame(maxWidth: .infinity)
    }

    private func stepYear(_ d: Int) {
        applyYearText()
        let y = clampYear((mode == 0 ? sy : ly) + d)
        if mode == 0 { sy = y; sd = min(sd, solarDayCount) }
        else { ly = y; ld = min(ld, lunarDayCount) }
        yearText = "\(y)"
    }
    private func applyYearText() {
        let digits = yearText.filter { $0.isNumber }
        if let y = Int(digits), (1920...2035).contains(y) {
            if mode == 0 { sy = y; sd = min(sd, solarDayCount) }
            else { ly = y; ld = min(ld, lunarDayCount) }
            yearText = "\(y)"
        } else {
            yearText = "\(mode == 0 ? sy : ly)"
        }
    }
    private func clampYear(_ y: Int) -> Int { min(2035, max(1920, y)) }

    private var monthRow: some View {
        HStack(spacing: 10) {
            Text("出生月份").font(.subheadline).fontWeight(.medium).foregroundStyle(Ky.ink)
            Spacer()
            Button { stepMonth(-1) } label: {
                Image(systemName: "chevron.left").font(.subheadline)
                    .frame(width: 30, height: 30).background(Ky.elevated).clipShape(Circle())
            }.accessibilityLabel("上个月")
            Text(mode == 0 ? "\(smo) 月" : Self.lunarMonths[lmo - 1])
                .font(.subheadline).fontWeight(.bold).frame(minWidth: 72, alignment: .center)
            Button { stepMonth(1) } label: {
                Image(systemName: "chevron.right").font(.subheadline)
                    .frame(width: 30, height: 30).background(Ky.elevated).clipShape(Circle())
            }.accessibilityLabel("下个月")
        }
    }
    private func stepMonth(_ d: Int) {
        applyYearText()
        if mode == 0 {
            var m = smo + d, y = sy
            if m < 1 { m = 12; y = clampYear(y - 1) }
            if m > 12 { m = 1; y = clampYear(y + 1) }
            smo = m; sy = y; sd = min(sd, solarDayCount); yearText = "\(sy)"
        } else {
            var m = lmo + d, y = ly
            if m < 1 { m = 12; y = clampYear(y - 1) }
            if m > 12 { m = 1; y = clampYear(y + 1) }
            lmo = m; ly = y; ld = min(ld, lunarDayCount); leap = false; yearText = "\(ly)"
        }
    }

    // MARK: 日期格
    private var dayGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Self.weekdays, id: \.self) { w in
                    Text(w).font(.caption2).fontWeight(.medium).foregroundStyle(Ky.sub).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 5) {
                ForEach(0..<firstWeekday, id: \.self) { _ in Color.clear.frame(height: 36) }
                ForEach(1...dayCount, id: \.self) { d in
                    let isSel = d == curDay
                    Button {
                        applyYearText()
                        setDay(d)
                    } label: {
                        VStack(spacing: 0) {
                            Text(mode == 0 ? "\(d)" : Self.lunarDays[d - 1])
                                .font(.subheadline).fontWeight(isSel ? .bold : .regular)
                            if mode == 1 {
                                Text(solarDayText(d)).font(.system(size: 9))
                                    .foregroundStyle(isSel ? Color.white.opacity(0.85) : Ky.sub)
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(isSel ? Ky.qingdai : Ky.elevated.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(isSel ? Color.white : Ky.ink)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private func setDay(_ d: Int) { if mode == 0 { sd = d } else { ld = d } }
    // 按月缓存：未缓存前每次 body 求值要对 28–31 个格子各算一次农历；缓存后同月直接命中
    private static var solarDayTextCache: [String: [Int: String]] = [:]
    private func solarDayText(_ lunarDay: Int) -> String {
        let m = (leap && hasLeapChoice) ? -lmo : lmo
        let key = "\(ly)-\(m)-\(lunarDayCount)"
        if let hit = Self.solarDayTextCache[key]?[lunarDay] { return hit }
        let s = Lunar.fromYmdHms(lunarYear: ly, lunarMonth: m, lunarDay: min(lunarDay, lunarDayCount), hour: 12, minute: 0).solar
        let v = "\(s.day)"
        var d = Self.solarDayTextCache[key] ?? [:]; d[lunarDay] = v
        if Self.solarDayTextCache.count > 24 { Self.solarDayTextCache.removeAll() }
        Self.solarDayTextCache[key] = d
        return v
    }

    // MARK: 时辰与时分
    private var shichenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("出生时辰").font(.subheadline).fontWeight(.medium).foregroundStyle(Ky.ink)
                Spacer()
                Button("‹ 上一时辰") { shiftBranch(-1) }.font(.caption).foregroundStyle(Ky.qingdai)
                Text("·").foregroundStyle(Ky.sub)
                Button("下一时辰 ›") { shiftBranch(1) }.font(.caption).foregroundStyle(Ky.qingdai)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(0..<12, id: \.self) { i in
                    let active = curBranch == i && !unknown
                    Button { pickBranch(i) } label: {
                        VStack(spacing: 1) {
                            Text(Self.branches[i]).font(.system(.subheadline, design: .serif)).fontWeight(.bold)
                            Text(Self.branchRange[i]).font(.system(size: 9))
                                .foregroundStyle(active ? Color.white.opacity(0.85) : Ky.sub)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(active ? Ky.qingdai : Ky.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(active ? Color.white : Ky.ink)
                    }.buttonStyle(.plain)
                }
            }
            Button { unknown.toggle(); if unknown { setHour(12); setMinute(0) } } label: {
                HStack(spacing: 6) {
                    Image(systemName: unknown ? "checkmark.square.fill" : "square")
                        .foregroundStyle(unknown ? Ky.cinnabar : Ky.sub)
                    Text("时辰未知（暂按午时 12:00 起盘，结果页可对比同日十二时辰）")
                        .font(.caption).foregroundStyle(unknown ? Ky.cinnabar : Ky.sub)
                    Spacer()
                }
                .padding(.top, 2)
            }.buttonStyle(.plain)
        }
    }
    private func shiftBranch(_ d: Int) {
        unknown = false
        let h = (curHour + d * 2 + 24) % 24
        setHour(h); setMinute(0)
    }
    private func pickBranch(_ i: Int) {
        unknown = false
        setHour((i * 2 + 23) % 24); setMinute(0)
    }
    private func setHour(_ h: Int) { if mode == 0 { sh = h } else { lh = h } }
    private func setMinute(_ m: Int) { if mode == 0 { smi = m } else { lmi = m } }

    private var hourMinuteSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("精确时分").font(.caption).foregroundStyle(Ky.sub)
                Spacer()
                Button { unknown = false; setHour((curHour + 23) % 24) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("上一小时")
                Text("\(String(format: "%02d", curHour)) 时").font(KyV2.tabular(15, weight: .bold)).frame(minWidth: 46)
                Button { unknown = false; setHour((curHour + 1) % 24) } label: { Image(systemName: "plus.circle") }.accessibilityLabel("下一小时")
                Text(":").foregroundStyle(Ky.sub)
                Button { unknown = false; setMinute((curMinute + 59) % 60) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("上一分钟")
                Text("\(String(format: "%02d", curMinute)) 分").font(KyV2.tabular(15, weight: .bold)).frame(minWidth: 46)
                Button { unknown = false; setMinute((curMinute + 1) % 60) } label: { Image(systemName: "plus.circle") }.accessibilityLabel("下一分钟")
            }
            .foregroundStyle(Ky.qingdai)

            HStack(spacing: 6) {
                Text("快捷分钟").font(.caption2).foregroundStyle(Ky.sub)
                ForEach([0, 10, 15, 20, 30, 45, 50], id: \.self) { m in
                    Button(String(format: ":%02d", m)) { unknown = false; setMinute(m) }
                        .font(KyV2.tabular(11, weight: curMinute == m ? .bold : .regular))
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background(curMinute == m ? Ky.qingdai : Ky.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(curMinute == m ? Color.white : Ky.ink)
                }
            }
        }
    }

    // MARK: 顶部实时双历预览卡
    private var previewCard: some View {
        let d = draftDate()
        let s = BirthInputView.solarOf(d)
        let l = s.lunar
        let lm = Self.lunarMonths[abs(l.month) - 1]
        let ldName = Self.lunarDays[max(0, min(29, l.day - 1))]
        let br = Self.branches[((s.hour + 1) / 2) % 12]
        let lon = Double(longitudeText)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("当前选定").font(.caption2).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                Spacer()
                if useLongitude, let lo = lon, (-180...180).contains(lo) {
                    let corr = TrueSolarTime.corrected(clock: d, longitude: lo)
                    let cs = BirthInputView.solarOf(corr)
                    Text("真太阳时 \(String(format: "%02d:%02d", cs.hour, cs.minute))")
                        .font(KyV2.tabular(11, weight: .semibold)).foregroundStyle(Ky.gold)
                }
            }
            Text("公历 \(s.year) 年 \(s.month) 月 \(s.day) 日 \(String(format: "%02d:%02d", s.hour, s.minute))")
                .font(KyV2.tabular(15, weight: .bold)).foregroundStyle(Ky.ink)
            Text("农历 \(BaziChart.yearGanZhi(l.year)) 年\(l.month < 0 ? "闰" : "")\(lm)\(ldName) · \(br)时")
                .font(.caption).foregroundStyle(Ky.sub)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ky.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ky.qingdai.opacity(0.35), lineWidth: 1))
    }

    private func draftDate() -> Date {
        if mode == 0 {
            var c = DateComponents(); c.year = sy; c.month = smo; c.day = min(sd, solarDayCount); c.hour = sh; c.minute = smi
            return Calendar(identifier: .gregorian).date(from: c) ?? initial
        }
        let m = (leap && hasLeapChoice) ? -lmo : lmo
        let s = Lunar.fromYmdHms(lunarYear: ly, lunarMonth: m, lunarDay: min(ld, lunarDayCount), hour: lh, minute: lmi).solar
        var c = DateComponents(); c.year = s.year; c.month = s.month; c.day = s.day; c.hour = s.hour; c.minute = s.minute
        return Calendar(identifier: .gregorian).date(from: c) ?? initial
    }

    private func convertDraft() {
        applyYearText()
        if mode == 1 {
            let l = BirthInputView.solarOf(draftSolar()).lunar
            ly = l.year; lmo = abs(l.month); ld = l.day; lh = l.hour; lmi = l.minute; leap = l.month < 0
            yearText = "\(ly)"
        } else {
            let s = BirthInputView.solarOf(draftDate())
            sy = s.year; smo = s.month; sd = s.day; sh = s.hour; smi = s.minute
            yearText = "\(sy)"
        }
    }
    private func draftSolar() -> Date {
        var c = DateComponents(); c.year = sy; c.month = smo; c.day = min(sd, solarDayCount); c.hour = sh; c.minute = smi
        return Calendar(identifier: .gregorian).date(from: c) ?? initial
    }

    private func compose() -> Date {
        var d = draftDate()
        if unknown {
            var c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: d)
            c.hour = 12; c.minute = 0
            d = Calendar(identifier: .gregorian).date(from: c) ?? d
        }
        return d
    }
}
