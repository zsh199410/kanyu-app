// 底部 Tab 栏（2026-11-03，用户定：按问真 Tab 栏样式，天气位换成排盘）
// 日历 / 黄历 / 择吉 / 排盘 / 我的；首启引导页移到根视图，只出现一次。
// 排盘 Tab 即原首页（HomePageView）；各 Tab 自带 NavigationStack，内页标题与原先一致。
import SwiftUI
import LunarSwift

struct RootTabView: View {
    @AppStorage("onboardingDone") private var onboardingDone = false
    @ObservedObject private var errorCenter = AppErrorCenter.shared
    @State private var showingOnboarding = false
    @State private var tab = 3  // 默认落在排盘（原首页），老用户不用重新找路
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { MonthCalendarTabView() }
                .tabItem { Label("日历", systemImage: "calendar") }.tag(0)
            NavigationStack { AlmanacView() }
                .tabItem { Label("黄历", systemImage: "moon.stars.fill") }.tag(1)
            NavigationStack { ZejiView() }
                .tabItem { Label("择吉", systemImage: "star.fill") }.tag(2)
            NavigationStack { HomePageView() }
                .tabItem { Label("排盘", systemImage: "tablecells.fill") }.tag(3)
            NavigationStack { MyView() }
                .tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(4)
        }
        .sheet(isPresented: $showingOnboarding) { OnboardingView(onDone: { onboardingDone = true; showingOnboarding = false }) }
        .onAppear { if !onboardingDone { showingOnboarding = true } }
        .overlay(alignment: .top) {
            if let message = errorCenter.message {
                AppErrorBanner(message: message) { errorCenter.dismiss() }
                    .padding(.horizontal, 16).padding(.top, 8)
            }
        }
    }
}

// MARK: - 日历 Tab：月历选日，点一天进当日黄历
struct MonthCalendarTabView: View {
    @State private var date = Date()
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                AlmanacCalendarCard(date: $date)
                NavigationLink { AlmanacView(initialDate: date) } label: {
                    HStack {
                        Image(systemName: "book.pages").foregroundStyle(Ky.qingdai)
                        Text("查看当日黄历：宜忌 · 吉神 · 时辰").font(.subheadline).foregroundStyle(Ky.ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Ky.sub)
                    }
                    .padding(12).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
                Text("点日历上的日子，再点这里看当日黄历；黄历 Tab 里同一张日历也可直接改日。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("日历").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 择吉：按事项查近 30 天宜日（只用 lunar 日宜忌，不编新口径）
struct ZejiView: View {
    @State private var event = "嫁娶"
    private static let events = ["嫁娶", "纳采", "开市", "入宅", "移徙", "安葬", "动土", "出行"]
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return c
    }
    private var matches: [(Date, Lunar)] {
        var out: [(Date, Lunar)] = []
        let start = cal.startOfDay(for: Date())
        for i in 0..<30 {
            guard let d = cal.date(byAdding: .day, value: i, to: start) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: d)
            let l = Solar.fromYmdHms(year: c.year!, month: c.month!, day: c.day!, hour: 12, minute: 0).lunar
            if l.dayYi.contains(event) { out.append((d, l)) }
        }
        return out
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("选事项，列出近 30 天宜此事的日子；点一天进当日黄历核对全文。")
                    .font(.caption).foregroundStyle(Ky.sub)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Self.events, id: \.self) { e in
                        Button(e) { event = e }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(event == e ? Ky.qingdai.opacity(0.16) : Ky.card)
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(event == e ? Ky.qingdai : Ky.line, lineWidth: event == e ? 1.2 : 0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(Ky.ink)
                    }
                }
                if matches.isEmpty {
                    Text("近 30 天没有宜「\(event)」的日子——可换个事项，或放宽到下个月再查。")
                        .font(.callout).foregroundStyle(Ky.cinnabar).padding(.top, 8)
                } else {
                    ForEach(matches, id: \.0) { d, l in
                        NavigationLink { AlmanacView(initialDate: d) } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(l.monthInChinese)月\(l.dayInChinese) · 星期\(l.weekInChinese)")
                                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
                                    Text("宜 \(l.dayYi.prefix(8).joined(separator: " "))").font(.caption).foregroundStyle(Ky.jade).lineLimit(1)
                                    Text("忌 \(l.dayJi.prefix(6).joined(separator: " "))").font(.caption).foregroundStyle(Ky.sub).lineLimit(1)
                                }
                                Spacer()
                                Text("\(cal.component(.month, from: d))月\(cal.component(.day, from: d))日")
                                    .font(.caption).foregroundStyle(Ky.sub)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Ky.sub)
                            }
                            .padding(12).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }
                Text("择吉只按历书宜忌初筛；大事仍须结合当事人命局与实际情况定，历书不作最终决定。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("择吉").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 八字论财：财星 / 财库 / 五行占比 / 财运大运（只用本盘已有字段，不新增断法）
struct WealthView: View {
    @StateObject private var peopleStore = PeopleStore()
    @State private var selectedID: UUID?
    private var person: Person? {
        peopleStore.people.first(where: { $0.id == selectedID }) ?? peopleStore.people.first
    }
    private var chart: BaziChart? {
        guard let p = person else { return nil }
        return BaziEngine.paipan(clock: p.birthDate, gender: p.gender,
                                 longitude: p.useLongitude ? p.longitude : nil)
    }
    private static let kuOf: [String: String] = ["木": "未", "火": "戌", "土": "辰", "金": "丑", "水": "辰"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if peopleStore.people.isEmpty {
                    Text("还没有人物档案——先到「人物档案」建一个人，再回来看论财。")
                        .font(.callout).foregroundStyle(Ky.sub).padding(.top, 12)
                } else {
                    Menu {
                        ForEach(peopleStore.people) { p in
                            Button("\(p.name)（\(p.gender == "M" ? "男" : "女")）") { selectedID = p.id }
                        }
                    } label: {
                        HStack {
                            Text(person?.name ?? "选人").font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Ky.sub)
                        }.padding(12).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if let p = person, let ch = chart {
                        wealthCard(p: p, ch: ch)
                    }
                }
                Text("论财只作通参：财星多不等于发财，财星弱不等于无财，须结合日主强弱、大运流年与现实行业整体看。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("八字论财").navigationBarTitleDisplayMode(.inline)
    }

    private func wealthCard(p: Person, ch: BaziChart) -> some View {
        let dayStem = ch.rizhu.first!
        let dayWx = BaziTables.wx[dayStem]?.0 ?? ""
        let allShiShen = ch.stemShiShen.enumerated().filter { $0.offset != 2 }.map { $0.element } + ch.hideShiShen.flatMap { $0 }
        let zhengCai = allShiShen.filter { $0 == "正财" }.count
        let pianCai = allShiShen.filter { $0 == "偏财" }.count
        let ku = Self.kuOf[dayWx] ?? ""
        let kuPillars = ["年", "月", "日", "时"].enumerated().filter { ch.pillars[$0.offset].last.map { String($0) } == ku }.map { $0.element }
        let wxNames = ["木", "火", "土", "金", "水"]
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(p.name.isEmpty ? "未命名" : p.name) · \(ch.pillars.joined(separator: " ")) · 日主 \(ch.rizhu)")
                .font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("正财").font(.caption2).foregroundStyle(Ky.sub)
                    Text("\(zhengCai) 个").font(.headline).foregroundStyle(Ky.ink)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("偏财").font(.caption2).foregroundStyle(Ky.sub)
                    Text("\(pianCai) 个").font(.headline).foregroundStyle(Ky.ink)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("财库（\(dayWx)库\(ku)）").font(.caption2).foregroundStyle(Ky.sub)
                    Text(kuPillars.isEmpty ? "原局无库" : "\(kuPillars.joined(separator: "、"))柱有库").font(.headline).foregroundStyle(Ky.ink)
                }
            }
            Text("五行占比（天干＋藏干加权）：\(wxNames.enumerated().map { "\(wxNames[$0.offset]) \(Int((ch.wuxingPercents[$0.offset] * 100).rounded()))%" }.joined(separator: " · "))")
                .font(.caption).foregroundStyle(Ky.sub)
            Divider()
            Text("财运大运（干支天干十神含财星的标出）").font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
            ForEach(ch.dayunGanZhi.indices, id: \.self) { i in
                let gz = ch.dayunGanZhi[i]
                let ss = BaziTables.shiShen(day: dayStem, stem: gz.first!)
                HStack {
                    Text("\(ch.dayunStartYear(i)) 起 · \(gz)").font(.callout).foregroundStyle(Ky.ink)
                    Spacer()
                    Text(ss).font(.callout).fontWeight(ss == "正财" || ss == "偏财" ? .semibold : .regular)
                        .foregroundStyle(ss == "正财" || ss == "偏财" ? Ky.gold : Ky.sub)
                }
            }
        }.kyCard()
    }
}

// MARK: - 多盘对比：档案里挑 2–4 人并排比四柱 / 日主 / 命宫身宫 / 旬空
struct CompareView: View {
    @StateObject private var peopleStore = PeopleStore()
    @State private var selected: Set<UUID> = []
    private var picked: [Person] { peopleStore.people.filter { selected.contains($0.id) } }
    private func chart(_ p: Person) -> BaziChart {
        BaziEngine.paipan(clock: p.birthDate, gender: p.gender, longitude: p.useLongitude ? p.longitude : nil)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("在档案里勾 2–4 个人，并排比盘；日主或日柱相同的会单独标出来。")
                    .font(.caption).foregroundStyle(Ky.sub)
                if peopleStore.people.isEmpty {
                    Text("还没有人物档案——先到「人物档案」建人，再回来对比。")
                        .font(.callout).foregroundStyle(Ky.sub).padding(.top, 12)
                } else {
                    VStack(spacing: 8) {
                        ForEach(peopleStore.people) { p in
                            Button {
                                if selected.contains(p.id) { selected.remove(p.id) }
                                else if selected.count < 4 { selected.insert(p.id) }
                            } label: {
                                HStack {
                                    Image(systemName: selected.contains(p.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(p.id) ? Ky.qingdai : Ky.sub)
                                    Text(p.name.isEmpty ? "未命名" : p.name).font(.subheadline).foregroundStyle(Ky.ink)
                                    Text(p.gender == "M" ? "男" : "女").font(.caption).foregroundStyle(Ky.sub)
                                    Spacer()
                                    if selected.count >= 4 && !selected.contains(p.id) {
                                        Text("已选满 4 人").font(.caption2).foregroundStyle(Ky.sub)
                                    }
                                }.padding(10).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }
                    if picked.count >= 2 {
                        let charts = picked.map { chart($0) }
                        let sameRizhu = Set(charts.map { $0.rizhu }).count == 1
                        let sameDay = Set(charts.map { $0.dayPillar }).count == 1
                        if sameRizhu || sameDay {
                            Text("相同点：\(sameRizhu ? "日主皆 \(charts[0].rizhu)" : "")\(sameRizhu && sameDay ? "；" : "")\(sameDay ? "日柱皆 \(charts[0].dayPillar)" : "")")
                                .font(.callout).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                        }
                        ForEach(picked.indices, id: \.self) { i in
                            let p = picked[i]; let ch = charts[i]
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(p.name.isEmpty ? "未命名" : p.name)（\(p.gender == "M" ? "男" : "女")）")
                                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
                                Text("四柱 \(ch.pillars.joined(separator: " ")) · 日主 \(ch.rizhu) · 命宫 \(ch.mingGong) · 身宫 \(ch.shenGong) · 日柱旬空 \(ch.xunKong)")
                                    .font(.caption).foregroundStyle(Ky.sub)
                            }.kyCard()
                        }
                        NavigationLink { SynastryView() } label: {
                            Text("要看两个人合不合，走「合盘」（合婚四看流程）更合适。")
                                .font(.caption).foregroundStyle(Ky.qingdai)
                        }
                    } else if !selected.isEmpty {
                        Text("已选 \(selected.count) 人，再选 1 人以上才出对比。").font(.caption).foregroundStyle(Ky.sub)
                    }
                }
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("多盘对比").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 五运六气独立页（原在黄历页内，现抽出来单独立口）
struct YunQiPageView: View {
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text("年份").font(.subheadline).foregroundStyle(Ky.sub)
                    Spacer()
                    Button { year = max(1900, year - 1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("上一年")
                    Text("\(year) 年").font(.subheadline).fontWeight(.semibold).frame(minWidth: 80)
                    Button { year = min(2100, year + 1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("下一年")
                }.kyCard()
                YunQiView(year: year)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("五运六气").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 我的：设置 / 档案 / 前瞻 / 关于（不放任何破坏性操作）
struct MyView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                NavigationLink { CaliberSettingsView() } label: {
                    HStack { Image(systemName: "slider.horizontal.3").foregroundStyle(Ky.qingdai); Text("排盘口径设置").font(.subheadline).foregroundStyle(Ky.ink); Spacer(); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Ky.sub) }
                        .padding(12).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
                NavigationLink { PeopleView() } label: {
                    HStack { Image(systemName: "person.2.fill").foregroundStyle(Ky.jade); Text("人物档案").font(.subheadline).foregroundStyle(Ky.ink); Spacer(); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Ky.sub) }
                        .padding(12).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
                NavigationLink { ForecastView() } label: {
                    HStack { Image(systemName: "checkmark.seal.fill").foregroundStyle(Ky.jade); Text("前瞻登记").font(.subheadline).foregroundStyle(Ky.ink); Spacer(); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Ky.sub) }
                        .padding(12).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 4) {
                    Text("三术合参").font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
                    Text("八字 · 紫微 · 风水 · 手相面相，全部计算都在本机完成；人物、断语与勘察数据只存本机，不上传。")
                        .font(.caption).foregroundStyle(Ky.sub)
                }.kyCard()
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("我的").navigationBarTitleDisplayMode(.inline)
    }
}
