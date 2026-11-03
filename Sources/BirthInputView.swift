// 出生录入组件 v2（2026-11-03 重做，取代五列滚轮版）
// 卡顿根因：旧版 5 列滚轮每滑一格就写回 clock，父页面整页重算（盘面＋解盘卡片全量重绘），
// 加上 116 行年份滚轮与每格农历换算，滑起来必然掉帧。新版改成「草稿＋确认」：
// 选时间全程只改本地草稿，点「确定」才写回 clock 一次；表单页本身不再有滚轮与页面滚动抢手势。
// 细节模仿点（对标问真/文墨＋iOS 原生）：底部弹层选时间、公历农历分段切换、日历格点选日期、
// 时辰 chips、年份直输、分钟常用刻度、近时辰交界红字提醒、双历对照预览。
// 三个录入面共用（八字/紫微/人物表单），调用签名与旧版一致。
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
    // 出生地省市两级（与旧版同口径：城市中心值 0.1°；340 城全表待审计后再扩）。
    private static let provinceCities: [(String, [(String, Double)])] = [
        ("北京", [("北京", 116.4)]), ("天津", [("天津", 117.2)]), ("河北", [("石家庄", 114.5)]),
        ("山西", [("太原", 112.6)]), ("内蒙古", [("呼和浩特", 111.7)]), ("辽宁", [("沈阳", 123.4)]),
        ("吉林", [("长春", 125.3)]), ("黑龙江", [("哈尔滨", 126.5)]), ("上海", [("上海", 121.5)]),
        ("江苏", [("南京", 118.8)]), ("浙江", [("杭州", 120.2)]), ("安徽", [("合肥", 116.9)]),
        ("福建", [("福州", 119.3)]), ("江西", [("南昌", 115.9)]), ("山东", [("济南", 117.0)]),
        ("河南", [("郑州", 113.6)]), ("湖北", [("武汉", 114.3)]), ("湖南", [("长沙", 112.9)]),
        ("广东", [("广州", 113.3), ("深圳", 114.1)]), ("广西", [("南宁", 108.3)]), ("海南", [("海口", 110.3)]),
        ("重庆", [("重庆主城", 106.5), ("梁平", 107.8)]), ("四川", [("成都", 104.1)]), ("贵州", [("贵阳", 106.7)]),
        ("云南", [("昆明", 102.8)]), ("西藏", [("拉萨", 91.1)]), ("陕西", [("西安", 108.9)]),
        ("甘肃", [("兰州", 103.8)]), ("青海", [("西宁", 101.8)]), ("宁夏", [("银川", 106.3)]),
        ("新疆", [("乌鲁木齐", 87.6)]), ("香港", [("香港", 114.2)]), ("澳门", [("澳门", 113.5)]),
        ("台湾", [("台北", 121.6)]),
    ]
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
    private var cityOptions: [(String, Double)] {
        if let prov = Self.provinceCities.first(where: { $0.0 == provinceSel }) { return prov.1 }
        return Self.places
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 摘要卡：点一下弹层改时间；表单页本身不再放滚轮。
            Button { showSheet = true } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summarySolar).font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
                        Text(summaryLunar).font(.caption).foregroundStyle(Ky.sub)
                        if unknownHour {
                            Text("时辰未知：先按午时（12:00）暂排——时柱相关的子女、晚年断语仅供参考，知道时辰后改回来重排。")
                                .font(.caption2).foregroundStyle(Ky.cinnabar)
                        }
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Image(systemName: "calendar").foregroundStyle(Ky.qingdai)
                        Text("修改").font(.caption2).foregroundStyle(Ky.qingdai)
                    }
                }
                .padding(10).background(Ky.bg).clipShape(RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain)
            .sheet(isPresented: $showSheet) {
                TimePickerSheet(initial: clock, mode: $mode, useLongitude: useLongitude, longitudeText: longitudeText) { date, unknown in
                    clock = date; unknownHour = unknown; showSheet = false
                }
            }
            summaryDetails
            Toggle("真太阳时校正（按出生地经度）", isOn: $useLongitude)
            if useLongitude {
                VStack(spacing: 8) {
                    HStack {
                        Text("出生地 · 省份")
                        Spacer()
                        Menu {
                            ForEach(Self.provinceCities, id: \.0) { prov in
                                Button(prov.0) { provinceSel = prov.0 }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(provinceSel.isEmpty ? "选省份" : provinceSel).foregroundStyle(Ky.sub)
                                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Ky.sub)
                            }
                        }
                    }
                    HStack {
                        Text("出生地 · 城市")
                        Spacer()
                        Menu {
                            ForEach(cityOptions, id: \.0) { p in
                                Button("\(p.0)（东经 \(String(format: "%.1f", p.1))）") { longitudeText = String(format: "%.1f", p.1) }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(placeName).foregroundStyle(Ky.sub)
                                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Ky.sub)
                            }
                        }
                    }
                    Text("先选省份再选城市；经度为城市中心值（0.1°），也可直接手填。未选省份时城市菜单列出全部城市。")
                        .font(.caption2).foregroundStyle(Ky.sub).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Text("经度（可手填）").foregroundStyle(Ky.sub)
                    Spacer()
                    TextField("107.8", text: $longitudeText)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                }
            }
        }
        .onAppear {
            if provinceSel.isEmpty, placeName != "自定义", let prov = Self.province(of: placeName) { provinceSel = prov }
        }
    }

    // 摘要行：只随 clock（确认后）变化，平时不重算。
    private var summarySolar: String {
        let s = Self.solarOf(clock)
        return "公历 \(s.year) 年 \(s.month) 月 \(s.day) 日 \(String(format: "%02d:%02d", s.hour, s.minute))"
    }
    private var summaryLunar: String {
        let l = Self.solarOf(clock).lunar
        let mName = Self.lunarMonths[abs(l.month) - 1]
        let dName = Self.lunarDays[max(0, min(29, l.day - 1))]
        let br = Self.branches[((l.hour + 1) / 2) % 12]
        return "农历 \(BaziChart.yearGanZhi(l.year)) 年\(l.month < 0 ? "闰" : "")\(mName)\(dName) · \(br)时"
    }

    // 详情行（旧版 readoutLine 内容，确认后才随 clock 变一次）。
    private var summaryDetails: some View {
        let s = Self.solarOf(clock)
        let l = s.lunar
        let lon = Double(longitudeText)
        return VStack(alignment: .leading, spacing: 2) {
            if useLongitude {
                if let lo = lon, (-180...180).contains(lo) {
                    let corr = TrueSolarTime.corrected(clock: clock, longitude: lo)
                    let delta = Int((corr.timeIntervalSince(clock) / 60).rounded())
                    let cs = Self.solarOf(corr)
                    Text("真太阳时 \(String(format: "%02d:%02d", cs.hour, cs.minute))（经度时差＋均时差合计 \(delta >= 0 ? "+" : "")\(delta) 分钟，排盘以此为准）")
                } else {
                    Text("经度没填对：将按不校正（钟表时间）排盘！请填数字，如 107.8，或从出生地里选。")
                        .foregroundStyle(Ky.cinnabar).fontWeight(.semibold)
                }
            }
            if s.hour == 23 {
                Text("夜子时（23 点后）：归日口径见设置页（默认 sect=2 算当日）。").foregroundStyle(Ky.cinnabar)
            }
            if let jq = Self.nearestJieQiText(lunar: l, clock: clock) {
                Text(jq).foregroundStyle(Ky.cinnabar)
            }
        }
        .font(.caption).foregroundStyle(Ky.qingdai)
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
        return "出生距节气「\(b.0)」仅约 \(Int(b.1.rounded())) 小时——月柱按节气切换，出生时间请务必核准（差一小时可能换月柱）。"
    }
}

// MARK: - 选时间弹层（草稿制：所有改动只动本地草稿，点「确定」才回写）
private struct TimePickerSheet: View {
    let initial: Date
    @Binding var mode: Int
    let useLongitude: Bool
    let longitudeText: String
    let onConfirm: (Date, Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    // 草稿：公历与农历各一套，切换历法时按同一时刻互换（旧版行为保留）。
    @State private var sy = 2000; @State private var smo = 1; @State private var sd = 1
    @State private var sh = 12; @State private var smi = 0
    @State private var ly = 2000; @State private var lmo = 1; @State private var ld = 1
    @State private var lh = 12; @State private var lmi = 0; @State private var leap = false
    @State private var unknown = false
    @State private var yearText = ""
    @State private var seeded = false

    private static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    private static let branchRange = ["23–1", "1–3", "3–5", "5–7", "7–9", "9–11", "11–13", "13–15", "15–17", "17–19", "19–21", "21–23"]
    private static let lunarMonths = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
    private static let lunarDays = ["初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                                    "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                                    "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]
    private static let weekdays = ["日", "一", "二", "三", "四", "五", "六"]

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
    // 当月 1 号星期几（用于日历格前置空白；农历取该月初一对应的公历星期）。
    private var firstWeekday: Int {
        let solar: Solar
        if mode == 0 {
            solar = Solar.fromYmdHms(year: sy, month: smo, day: 1, hour: 12, minute: 0)
        } else {
            solar = Lunar.fromYmdHms(lunarYear: ly, lunarMonth: (leap && hasLeapChoice) ? -lmo : lmo, lunarDay: 1, hour: 12, minute: 0).solar
        }
        var c = DateComponents(); c.year = solar.year; c.month = solar.month; c.day = solar.day
        let d = Calendar(identifier: .gregorian).date(from: c) ?? Date()
        return Calendar(identifier: .gregorian).component(.weekday, from: d) - 1  // 0=周日
    }
    // 距下一时辰交界（奇数整点）还有几分钟；≤15 分钟提醒分钟会影响时柱。
    private var minutesToBoundary: Int {
        let h = curHour, m = curMinute
        return (h % 2 == 1 ? 120 : 60) - m
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("历法", selection: $mode) { Text("公历").tag(0); Text("农历").tag(1) }
                        .pickerStyle(.segmented)
                        .onChange(of: mode) { _ in convertDraft() }
                    yearRow
                    monthRow
                    dayGrid
                    if mode == 1 {
                        if hasLeapChoice {
                            Toggle("闰月（\(Self.lunarMonths[lmo - 1])）", isOn: $leap)
                        } else if leap {
                            Text("该年无此闰月，已按平月排。").font(.caption2).foregroundStyle(Ky.cinnabar)
                        }
                    }
                    shichenSection
                    hourMinuteSection
                    if minutesToBoundary <= 15 {
                        Text("距下一时辰交界仅约 \(minutesToBoundary) 分钟——分钟数会影响时柱，请核准到分钟。")
                            .font(.caption2).foregroundStyle(Ky.cinnabar)
                    }
                    previewCard
                }.padding(16)
            }
            .background(Ky.bg)
            .navigationTitle("选择出生时间").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") { onConfirm(compose(), unknown) }.fontWeight(.semibold)
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

    // MARK: 年月步进
    private var yearRow: some View {
        HStack(spacing: 10) {
            Text("年份").font(.subheadline).foregroundStyle(Ky.sub)
            Spacer()
            Button { stepYear(-1) } label: { Image(systemName: "chevron.left").font(.subheadline) }
            TextField("如 1994", text: $yearText)
                .keyboardType(.numberPad).multilineTextAlignment(.center).frame(width: 76)
                .padding(.vertical, 5).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 7))
                .onSubmit { applyYearText() }
            Button { stepYear(1) } label: { Image(systemName: "chevron.right").font(.subheadline) }
            Text("1920–2035").font(.caption2).foregroundStyle(Ky.sub)
        }
    }
    private func stepYear(_ d: Int) {
        let y = clampYear((mode == 0 ? sy : ly) + d)
        if mode == 0 { sy = y } else { ly = y }
        yearText = "\(y)"
    }
    private func applyYearText() {
        if let y = Int(yearText), (1920...2035).contains(y) {
            if mode == 0 { sy = y } else { ly = y }
        } else {
            yearText = "\(mode == 0 ? sy : ly)"
        }
    }
    private func clampYear(_ y: Int) -> Int { min(2035, max(1920, y)) }

    private var monthRow: some View {
        HStack(spacing: 10) {
            Text("月份").font(.subheadline).foregroundStyle(Ky.sub)
            Spacer()
            Button { stepMonth(-1) } label: { Image(systemName: "chevron.left").font(.subheadline) }
            Text(mode == 0 ? "\(smo)月" : Self.lunarMonths[lmo - 1])
                .font(.subheadline).fontWeight(.semibold).frame(minWidth: 64)
            Button { stepMonth(1) } label: { Image(systemName: "chevron.right").font(.subheadline) }
        }
    }
    private func stepMonth(_ d: Int) {
        if mode == 0 {
            var m = smo + d, y = sy
            if m < 1 { m = 12; y = clampYear(y - 1) }
            if m > 12 { m = 1; y = clampYear(y + 1) }
            smo = m; sy = y; sd = min(sd, solarDayCount); yearText = "\(sy)"
        } else {
            var m = lmo + d, y = ly
            if m < 1 { m = 12; y = clampYear(y - 1) }
            if m > 12 { m = 1; y = clampYear(y + 1) }
            lmo = m; ly = y; ld = min(ld, lunarDayCount); leap = false
        }
    }

    // MARK: 日期格
    private var dayGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Self.weekdays, id: \.self) { w in
                    Text(w).font(.caption2).foregroundStyle(Ky.sub).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<firstWeekday, id: \.self) { _ in Color.clear.frame(height: 34) }
                ForEach(1...dayCount, id: \.self) { d in
                    Button { setDay(d) } label: {
                        VStack(spacing: 0) {
                            Text(mode == 0 ? "\(d)" : Self.lunarDays[d - 1])
                                .font(.subheadline).fontWeight(d == curDay ? .semibold : .regular)
                            if mode == 1 {
                                Text(solarDayText(d)).font(.caption2).foregroundStyle(Ky.sub)
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(d == curDay ? Ky.qingdai.opacity(0.16) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Ky.ink)
                    }.buttonStyle(.plain)
                }
            }
            Text(mode == 0 ? "点日期直接选；跨月用上面月份步进" : "格内大字是农历日、小字是对应公历日")
                .font(.caption2).foregroundStyle(Ky.sub)
        }
    }
    private func setDay(_ d: Int) { if mode == 0 { sd = d } else { ld = d } }
    // 农历某日对应的公历日（只取日号，格内小字用）。
    private func solarDayText(_ lunarDay: Int) -> String {
        let m = (leap && hasLeapChoice) ? -lmo : lmo
        let s = Lunar.fromYmdHms(lunarYear: ly, lunarMonth: m, lunarDay: min(lunarDay, lunarDayCount), hour: 12, minute: 0).solar
        return "\(s.day)"
    }

    // MARK: 时辰与时分
    private var shichenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("时辰（点一下定位到该时辰中段）").font(.caption2).foregroundStyle(Ky.sub)
                Spacer()
                Button("上一时辰") { shiftBranch(-1) }.font(.caption2)
                Button("下一时辰") { shiftBranch(1) }.font(.caption2)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(0..<12, id: \.self) { i in
                    Button { pickBranch(i) } label: {
                        VStack(spacing: 1) {
                            Text(Self.branches[i]).font(.subheadline).fontWeight(.semibold)
                            Text(Self.branchRange[i]).font(.caption2).foregroundStyle(Ky.sub)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(curBranch == i && !unknown ? Ky.qingdai.opacity(0.16) : Ky.card)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(curBranch == i && !unknown ? Ky.qingdai : Ky.line, lineWidth: curBranch == i && !unknown ? 1.2 : 0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Ky.ink)
                    }.buttonStyle(.plain)
                }
                Button { unknown = true; setHour(12); setMinute(0) } label: {
                    Text("未知").font(.subheadline)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(unknown ? Ky.cinnabar.opacity(0.12) : Ky.card)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Ky.line, lineWidth: 0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Ky.ink)
                }.buttonStyle(.plain)
            }
            if unknown {
                Text("时辰未知：先按午时（12:00）暂排——时柱相关的子女、晚年断语仅供参考，知道时辰后改回来重排。")
                    .font(.caption2).foregroundStyle(Ky.cinnabar)
            }
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
                Text("时").font(.subheadline).foregroundStyle(Ky.sub)
                Button { unknown = false; setHour((curHour + 23) % 24) } label: { Image(systemName: "chevron.left") }
                Text(String(format: "%02d", curHour)).font(.subheadline).fontWeight(.semibold).frame(minWidth: 40)
                Button { unknown = false; setHour((curHour + 1) % 24) } label: { Image(systemName: "chevron.right") }
                Spacer()
                Text("分").font(.subheadline).foregroundStyle(Ky.sub)
                Button { unknown = false; setMinute((curMinute + 59) % 60) } label: { Image(systemName: "chevron.left") }
                Text(String(format: "%02d", curMinute)).font(.subheadline).fontWeight(.semibold).frame(minWidth: 40)
                Button { unknown = false; setMinute((curMinute + 1) % 60) } label: { Image(systemName: "chevron.right") }
            }
            HStack(spacing: 8) {
                Text("分钟常用").font(.caption2).foregroundStyle(Ky.sub)
                ForEach([0, 15, 30, 45], id: \.self) { m in
                    Button(String(format: "%02d", m)) { unknown = false; setMinute(m) }
                        .font(.caption)
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background(curMinute == m ? Ky.qingdai.opacity(0.16) : Ky.card)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(Ky.ink)
                }
            }
        }
    }

    // MARK: 预览与合成
    private var previewCard: some View {
        let d = draftDate()
        let s = BirthInputView.solarOf(d)
        let l = s.lunar
        let lm = Self.lunarMonths[abs(l.month) - 1]
        let ldName = Self.lunarDays[max(0, min(29, l.day - 1))]
        let br = Self.branches[((s.hour + 1) / 2) % 12]
        let lon = Double(longitudeText)
        return VStack(alignment: .leading, spacing: 3) {
            Text("公历 \(s.year) 年 \(s.month) 月 \(s.day) 日 \(String(format: "%02d:%02d", s.hour, s.minute))")
            Text("农历 \(BaziChart.yearGanZhi(l.year)) 年\(l.month < 0 ? "闰" : "")\(lm)\(ldName) · \(br)时")
            if useLongitude {
                if let lo = lon, (-180...180).contains(lo) {
                    let corr = TrueSolarTime.corrected(clock: d, longitude: lo)
                    let delta = Int((corr.timeIntervalSince(d) / 60).rounded())
                    let cs = BirthInputView.solarOf(corr)
                    Text("真太阳时 \(String(format: "%02d:%02d", cs.hour, cs.minute))（合计 \(delta >= 0 ? "+" : "")\(delta) 分钟，排盘以此为准）")
                } else {
                    Text("经度没填对：排盘将按不校正（钟表时间）算。").foregroundStyle(Ky.cinnabar).fontWeight(.semibold)
                }
            }
            if s.hour == 23 {
                Text("夜子时（23 点后）：归日口径见设置页（默认 sect=2 算当日）。").foregroundStyle(Ky.cinnabar)
            }
            if let jq = BirthInputView.nearestJieQiText(lunar: l, clock: d) {
                Text(jq).foregroundStyle(Ky.cinnabar)
            }
        }
        .font(.caption).foregroundStyle(Ky.qingdai)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10).background(Ky.qingdai.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 8))
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
        if mode == 1 {
            // 刚切到农历：按公历草稿换算
            let l = BirthInputView.solarOf(draftSolar()).lunar
            ly = l.year; lmo = abs(l.month); ld = l.day; lh = l.hour; lmi = l.minute; leap = l.month < 0
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
