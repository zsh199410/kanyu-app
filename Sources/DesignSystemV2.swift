// 设计系统 v2（2026-10-30 UI 对标调研定版，规范全文见 UI-DESIGN.md v2 节）
// 铁律：盘面永远是不透明的纸；玻璃只许出现在浮动控制层（导航/时间胶囊），且只用 regular；
// 颜色永不单独编码（五行色必配文字）；数字一律等宽对齐；朱砂点缀全屏 ≤3 处。
import SwiftUI
import LunarSwift

enum KyV2 {
    // 五行色（双编码：色＋文字标签并行，正文对比 ≥4.5:1 取深值）
    static let wuxingNames = ["木", "火", "土", "金", "水"]
    static var wuxingColors: [Color] = [
        .kyDyn(0x2E7D4F, 0x4CAF7D),  // 木
        .kyDyn(0xB33727, 0xD95F43),  // 火
        .kyDyn(0x96690F, 0xC9973F),  // 土
        .kyDyn(0xA87F14, 0xC9A227),  // 金
        .kyDyn(0x2E5F8A, 0x5B8DB8),  // 水
    ]
    static func tabular(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

// 五行横条（禁饼图：角度误读；横条＋等宽数字＋来源计法注脚）
struct WuxingBarsView: View {
    let percents: [Double]  // 木火土金水，合计 100
    var body: some View {
        VStack(spacing: 7) {
            ForEach(0..<min(KyV2.wuxingNames.count, percents.count), id: \.self) { i in
                HStack(spacing: 8) {
                    Text(KyV2.wuxingNames[i])
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(KyV2.wuxingColors[i])
                        .frame(width: 16)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Ky.line.opacity(0.5))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(KyV2.wuxingColors[i])
                                .frame(width: max(3, geo.size.width * CGFloat(percents[i]) / 100))
                        }
                    }.frame(height: 10)
                    Text(String(format: "%.0f%%", percents[i]))
                        .font(KyV2.tabular(12)).foregroundStyle(Ky.ink)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}

// 五级时间胶囊（学文墨天机底部时间转盘的单手逻辑，形态按 v2：唯一时间切换组件）
// 未开放级别灰置并标注阶段，不假装可用。
struct TimeCapsuleBar: View {
    let levels: [String]
    let enabled: [Bool]
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(levels.indices, id: \.self) { i in
                Button { if enabled.indices.contains(i) && enabled[i] { selection = i } } label: {
                    HStack(spacing: 3) {
                        Text(levels[i]).font(.caption).fontWeight(selection == i ? .semibold : .regular)
                        if !(enabled.indices.contains(i) && enabled[i]) {
                            Text("P2").font(.system(size: 8)).foregroundStyle(Ky.sub)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(selection == i ? Ky.ink : Color.clear)
                    .foregroundStyle(selection == i ? Ky.bg : ((enabled.indices.contains(i) && enabled[i]) ? Ky.ink : Ky.sub))
                    .clipShape(Capsule())
                }.buttonStyle(.plain).disabled(!(enabled.indices.contains(i) && enabled[i]))
            }
        }
        .padding(3)
        .kyGlass(corner: 20)
    }
}

// 依据链组件（独门：结论 ← 规则 ← 盘面事实 ← 古籍原文；P2 断语层接入，先立形）
struct EvidenceChainView: View {
    let conclusion: String
    let links: [(label: String, text: String)]  // 自上而下：规则/盘面事实/原文
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "text.book.closed").foregroundStyle(Ky.cinnabar)
                Text(conclusion).font(.callout).fontWeight(.medium).foregroundStyle(Ky.ink)
            }
            ForEach(links.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 6) {
                    Text(links[i].label).font(.caption2).foregroundStyle(Ky.gold)
                        .frame(width: 34, alignment: .leading)
                    Text(links[i].text).font(.caption).foregroundStyle(Ky.sub)
                }.padding(.leading, 22)
            }
        }
    }
}

// MARK: - 设计系统 v3（2026-10-30 UI 对标调研七准则落地）
// 准则：盘面是纸不是玻璃 / 密度双层可关 / 时间轴主交互 / 专注模式其余淡化 /
// 首页是工作台 / 朱砂每屏一处·印章只作落款判定 / 大字号方盘变文字盘。
struct KySectionTitle: View {
    let title: String
    var trailing: String = ""
    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
            Rectangle().fill(Ky.gold.opacity(0.55)).frame(height: 1)
            if !trailing.isEmpty {
                Text(trailing).font(.caption2).foregroundStyle(Ky.sub)
            }
        }
    }
}

/// 朱砂印章小记：只用于「落判/落款」语义（回验落判、报告落款），不作普通按钮
struct KySeal: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, design: .serif)).fontWeight(.bold)
            .foregroundStyle(Ky.cinnabar)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Ky.cinnabar, lineWidth: 1.4))
            .rotationEffect(.degrees(-4))
    }
}

extension View {
    /// v3 标准卡：纸面＋发丝描边＋极浅投影（内容层，永不玻璃）
    func kyCard() -> some View {
        self.padding(16)
            .background(Ky.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ky.line.opacity(0.7), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// MARK: - 排盘口径设置（对标文墨天机的安星参数页：口径成套可调，默认值＝现行金标准口径）
enum AppSettings {
    static var baziSect: Int { let v = UserDefaults.standard.integer(forKey: "baziSect"); return v == 1 ? 1 : 2 }
    static var ziweiLeapNext: Bool { UserDefaults.standard.object(forKey: "ziweiLeapNext") as? Bool ?? true }
    static var ziweiLateZiNext: Bool { UserDefaults.standard.bool(forKey: "ziweiLateZiNext") }
}

struct CaliberSettingsView: View {
    @AppStorage("signDateEpoch") private var signDateEpoch: Double = 0
    @AppStorage("signCertDays") private var signCertDays: Int = 365
    @AppStorage("baziSect") private var baziSect = 2
    @AppStorage("ziweiLeapNext") private var ziweiLeapNext = true
    @AppStorage("ziweiLateZiNext") private var ziweiLateZiNext = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    KySectionTitle(title: "八字口径")
                    Picker("晚子时归日", selection: $baziSect) {
                        Text("23 点后算次日（sect=1）").tag(1)
                        Text("23 点后算当日（sect=2）").tag(2)
                    }.pickerStyle(.segmented)
                    Text("现行金标准盘以 sect=2 对拍验证；改口径后盘面随之变化，属预期。").font(.caption2).foregroundStyle(Ky.sub)
                }.kyCard()
                VStack(alignment: .leading, spacing: 10) {
                    KySectionTitle(title: "紫微口径（天纪三合派）")
                    Toggle("闰月整月归下月", isOn: $ziweiLeapNext)
                    Toggle("晚子时作次日", isOn: $ziweiLateZiNext)
                    Text("默认：闰月归下月、晚子时作当日，与紫微金标准盘（iztro 同源参照）一致。").font(.caption2).foregroundStyle(Ky.sub)
                }.kyCard()
                VStack(alignment: .leading, spacing: 10) {
                    KySectionTitle(title: "签名信息（侧载）")
                    DatePicker("签名日期", selection: Binding(
                        get: { signDateEpoch > 0 ? Date(timeIntervalSince1970: signDateEpoch) : Date() },
                        set: { signDateEpoch = $0.timeIntervalSince1970 }), displayedComponents: .date)
                    Picker("证书类型", selection: $signCertDays) {
                        Text("免费证书（7 天）").tag(7)
                        Text("付费证书（1 年）").tag(365)
                    }.pickerStyle(.segmented)
                    if signDateEpoch > 0 {
                        let expiry = Date(timeIntervalSince1970: signDateEpoch).addingTimeInterval(Double(signCertDays) * 86400)
                        let remain = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
                        Text("到期日 \(expiry.formatted(date: .abbreviated, time: .omitted))，还剩 \(remain) 天。到期前 7 天起首页会亮提醒：到期后 App 打不开是证书问题、不是数据问题，续签覆盖安装即可，数据不丢。")
                            .font(.caption2).foregroundStyle(remain <= 7 ? Ky.cinnabar : Ky.sub)
                    } else {
                        Text("装好 App 后在这里记下签名日期，临近到期首页会提醒续签。").font(.caption2).foregroundStyle(Ky.sub)
                    }
                }.kyCard()
                VStack(alignment: .leading, spacing: 10) {
                    KySectionTitle(title: "紫微亮度表")
                    Text("现行：《斗数全书》派亮度（58 星×12 宫全量）。中州派亮度表数据源未核实，不编造，缺位标注在此——宁缺毋假。").font(.caption).foregroundStyle(Ky.sub)
                }.kyCard()
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("排盘口径设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 出生录入组件（对标问真：公历/农历双轨＋五轮滚轮＋时辰速选＋出生地预设＋双历对照）
// 三个录入面共用（八字/紫微/人物表单），保证全 App 选日期一个样。
struct BirthInputView: View {
    @Binding var clock: Date
    @Binding var useLongitude: Bool
    @Binding var longitudeText: String

    private struct SF: Equatable { var y = 2000; var mo = 1; var d = 1; var h = 12; var mi = 0 }
    private struct LF: Equatable { var y = 2000; var mo = 1; var d = 1; var h = 12; var mi = 0; var leap = false }
    @State private var mode = 0   // 0 公历 1 农历
    @State private var sf = SF()
    @State private var lf = LF()
    @State private var unknownHour = false
    @State private var ready = false
    @State private var yearJump = ""

    private static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    private static let places: [(String, Double)] = [
        ("梁平", 107.8), ("重庆主城", 106.5), ("成都", 104.1), ("北京", 116.4), ("上海", 121.5),
        ("广州", 113.3), ("深圳", 114.1), ("西安", 108.9), ("武汉", 114.3), ("拉萨", 91.1), ("乌鲁木齐", 87.6),
    ]
    private static let lunarMonths = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
    private static let lunarDays = ["初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                                    "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                                    "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]

    private var daysInSolarMonth: Int {
        var c = DateComponents(); c.year = sf.y; c.month = sf.mo
        let cal = Calendar(identifier: .gregorian)
        if let d = cal.date(from: c), let r = cal.range(of: .day, in: .month, for: d) { return r.count }
        return 31
    }
    private var leapMonthOfYear: Int { LunarYear.fromYear(lf.y).leapMonth }
    private var hasLeapChoice: Bool { leapMonthOfYear == lf.mo }
    private var lunarDayCount: Int {
        let m = lf.leap ? -lf.mo : lf.mo
        return Lunar.fromYmdHms(lf.y, m, 30, 0, 0, 0).day == 30 ? 30 : 29
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("历法", selection: $mode) { Text("公历").tag(0); Text("农历").tag(1) }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _ in syncFromClock() }
            HStack(spacing: 8) {
                Text("年份直达").font(.caption).foregroundStyle(Ky.sub)
                TextField("如 1994", text: $yearJump)
                    .keyboardType(.numberPad).multilineTextAlignment(.center)
                    .frame(width: 76).padding(.vertical, 5)
                    .background(Ky.bg).clipShape(RoundedRectangle(cornerRadius: 7))
                Button("跳转") {
                    if let y = Int(yearJump), (1920...2035).contains(y) {
                        if mode == 0 { sf.y = y } else { lf.y = y }
                    }
                }.font(.caption).disabled(Int(yearJump) == nil)
                Spacer()
                Text("滚轮可直接滑年份").font(.caption2).foregroundStyle(Ky.sub)
            }
            if mode == 0 { solarWheels } else { lunarWheels }
            shichenRow
            readoutLine
            Toggle("真太阳时校正（按出生地经度）", isOn: $useLongitude)
            if useLongitude {
                HStack {
                    Text("出生地")
                    Spacer()
                    Menu {
                        ForEach(Self.places, id: \.0) { p in
                            Button("\(p.0)（东经 \(String(format: "%.1f", p.1))）") { longitudeText = String(format: "%.1f", p.1) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(placeName).foregroundStyle(Ky.sub)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Ky.sub)
                        }
                    }
                }
                HStack {
                    Text("经度（可手填）").foregroundStyle(Ky.sub)
                    Spacer()
                    TextField("107.8", text: $longitudeText)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                }
            }
        }
        .onAppear { if !ready { syncFromClock(); ready = true } }
        .onChange(of: sf) { _ in guard ready, mode == 0 else { return }; unknownHour = false; clock = composeSolar() }
        .onChange(of: lf) { _ in guard ready, mode == 1 else { return }; unknownHour = false; clock = composeLunar() }
    }

    private var placeName: String {
        if let p = Self.places.first(where: { abs($0.1 - (Double(longitudeText) ?? -999)) < 0.051 }) { return p.0 }
        return "自定义"
    }

    private func wheelCol<V: Hashable>(_ label: String, _ sel: Binding<V>, _ items: [V], _ fmt: @escaping (V) -> String, _ w: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(Ky.sub)
            Picker(label, selection: sel) { ForEach(items, id: \.self) { Text(fmt($0)).tag($0) } }
                .pickerStyle(.wheel).frame(width: w, height: 118).clipped()
        }
    }

    private var solarWheels: some View {
        HStack(spacing: 0) {
            wheelCol("年", $sf.y, Array(1920...2035), { "\($0)" }, 74)
            wheelCol("月", $sf.mo, Array(1...12), { "\($0)月" }, 56)
            wheelCol("日", Binding(get: { min(sf.d, daysInSolarMonth) }, set: { sf.d = $0 }), Array(1...daysInSolarMonth), { "\($0)日" }, 56)
            wheelCol("时", $sf.h, Array(0...23), { $0 < 10 ? "0\($0)" : "\($0)" }, 52)
            wheelCol("分", $sf.mi, Array(0...59), { $0 < 10 ? "0\($0)" : "\($0)" }, 52)
        }
    }

    private var lunarWheels: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                wheelCol("年", $lf.y, Array(1920...2035), { "\($0)" }, 74)
                wheelCol("月", $lf.mo, Array(1...12), { Self.lunarMonths[$0 - 1] }, 62)
                wheelCol("日", Binding(get: { min(lf.d, lunarDayCount) }, set: { lf.d = $0 }), Array(1...lunarDayCount), { Self.lunarDays[$0 - 1] }, 58)
                wheelCol("时", $lf.h, Array(0...23), { $0 < 10 ? "0\($0)" : "\($0)" }, 52)
                wheelCol("分", $lf.mi, Array(0...59), { $0 < 10 ? "0\($0)" : "\($0)" }, 52)
            }
            if hasLeapChoice {
                Toggle("闰月（\(Self.lunarMonths[lf.mo - 1])）", isOn: $lf.leap)
            } else if lf.leap {
                Text("该年无此闰月，已按平月排。").font(.caption2).foregroundStyle(Ky.cinnabar)
            }
        }
    }

    private var shichenRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("时辰速选（点一下定位到该时辰中段）").font(.caption2).foregroundStyle(Ky.sub)
                Spacer()
                Button("上一时辰") { shiftBranch(-1) }.font(.caption2)
                Button("下一时辰") { shiftBranch(1) }.font(.caption2)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<12, id: \.self) { i in
                    Button(Self.branches[i]) { pickBranch(i) }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(currentBranch == i ? Ky.qingdai.opacity(0.16) : Ky.bg)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(currentBranch == i ? Ky.qingdai : Ky.line, lineWidth: currentBranch == i ? 1.2 : 0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Ky.ink)
                }
                Button("未知") {
                    unknownHour = true
                    if mode == 0 { sf.h = 12; sf.mi = 0 } else { lf.h = 12; lf.mi = 0 }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(unknownHour ? Ky.cinnabar.opacity(0.12) : Ky.bg)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Ky.line, lineWidth: 0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Ky.ink)
            }
            if unknownHour {
                Text("时辰未知：先按午时（12:00）暂排——时柱相关的子女、晚年断语仅供参考，知道时辰后改回来重排。")
                    .font(.caption2).foregroundStyle(Ky.cinnabar)
            }
        }
    }

    private var currentBranch: Int {
        let h = mode == 0 ? sf.h : lf.h
        return ((h + 1) / 2) % 12
    }
    private func shiftBranch(_ d: Int) {
        if mode == 0 { sf.h = (sf.h + d * 2 + 24) % 24 } else { lf.h = (lf.h + d * 2 + 24) % 24 }
    }
    private func pickBranch(_ i: Int) {
        let h = (i * 2 + 23) % 24   // 子时中段 0 点，丑 2，寅 4 … 亥 22
        if mode == 0 { sf.h = h; sf.mi = 0 } else { lf.h = h; lf.mi = 0 }
    }

    private var readoutLine: some View {
        let s = Solar.fromDate(clock)
        let l = s.lunar
        let lm = l.month
        let mName = Self.lunarMonths[abs(lm) - 1]
        let dName = Self.lunarDays[max(0, min(29, l.day - 1))]
        let lon = Double(longitudeText)
        return VStack(alignment: .leading, spacing: 2) {
            Text("公历 \(s.year) 年 \(s.month) 月 \(s.day) 日 \(String(format: "%02d:%02d", s.hour, s.minute))")
            Text("农历 \(BaziChart.yearGanZhi(l.year)) 年\(lm < 0 ? "闰" : "")\(mName)\(dName)（\(Self.branches[((s.hour + 1) / 2) % 12])时）")
            if useLongitude {
                if let lo = lon, (-180...180).contains(lo) {
                    let corr = TrueSolarTime.corrected(clock: clock, longitude: lo)
                    let delta = Int((corr.timeIntervalSince(clock) / 60).rounded())
                    let cs = Solar.fromDate(corr)
                    Text("真太阳时 \(String(format: "%02d:%02d", cs.hour, cs.minute))（经度时差＋均时差合计 \(delta >= 0 ? "+" : "")\(delta) 分钟，排盘以此为准）")
                } else {
                    Text("经度没填对：将按不校正（钟表时间）排盘！请填数字，如 107.8，或从出生地里选。")
                        .foregroundStyle(Ky.cinnabar).fontWeight(.semibold)
                }
            }
            if s.hour == 23 {
                Text("夜子时（23 点后）：归日口径见设置页（默认 sect=2 算当日）。").foregroundStyle(Ky.cinnabar)
            }
            if let jq = nearestJieQiText(l) {
                Text(jq).foregroundStyle(Ky.cinnabar)
            }
        }
        .font(.caption).foregroundStyle(Ky.qingdai)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9).background(Ky.qingdai.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func nearestJieQiText(_ l: Lunar) -> String? {
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

    private func syncFromClock() {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: clock)
        sf = SF(y: c.year ?? 2000, mo: c.month ?? 1, d: c.day ?? 1, h: c.hour ?? 12, mi: c.minute ?? 0)
        let l = Solar.fromDate(clock).lunar
        lf = LF(y: l.year, mo: abs(l.month), d: l.day, h: l.hour, mi: l.minute, leap: l.month < 0)
    }
    private func composeSolar() -> Date {
        var c = DateComponents(); c.year = sf.y; c.month = sf.mo; c.day = min(sf.d, daysInSolarMonth); c.hour = sf.h; c.minute = sf.mi
        return Calendar(identifier: .gregorian).date(from: c) ?? clock
    }
    private func composeLunar() -> Date {
        let m = (lf.leap && hasLeapChoice) ? -lf.mo : lf.mo
        let s = Lunar.fromYmdHms(lf.y, m, min(lf.d, lunarDayCount), lf.h, lf.mi, 0).solar
        var c = DateComponents(); c.year = s.year; c.month = s.month; c.day = s.day; c.hour = s.hour; c.minute = s.minute
        return Calendar(identifier: .gregorian).date(from: c) ?? clock
    }
}
